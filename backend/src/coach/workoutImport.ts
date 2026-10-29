import Anthropic from '@anthropic-ai/sdk';
import type { Fetch } from '../appleTokens.ts';
import { AI_MODELS, CACHED, tracked } from './models.ts';
import type { ScanItem } from './gymScan.ts';

/**
 * Save a workout seen on TikTok / Instagram (#909): the post's caption (shared with the link, or read from the
 * platform's public oEmbed), up to 4 screenshots and/or the member's own words in; a named workout out, every move
 * mapped onto the app's exercise ids. Videos are never fetched; photos are passed through and never kept; no
 * identifiers are sent.
 */
export type Platform = 'tiktok' | 'instagram' | 'youtube' | 'web';

export interface ImportSource {
  platform: Platform;
  url: string;
  /** Creator handle or name, when the platform says it. */
  author?: string;
}

export interface ImportAsk {
  caption?: string;
  /** What the member says they saw ("Tell Coach", #909 C). */
  text?: string;
  photos: Buffer[];
  catalog: ScanItem[];
}

export type ImportUnit = 'reps' | 'sec' | 'min';

export interface ImportedItem {
  /** The move as the post or member named it ("Frog pumps"). */
  said: string;
  /** Catalog id of the closest exercise; empty when nothing fits. */
  id: string;
  sets: number;
  reps: number;
  unit: ImportUnit;
  /** False when `id` is only a near match the member should check. */
  sure: boolean;
}

export interface ImportedWorkout {
  name: string;
  minutes: number;
  items: ImportedItem[];
}

export type WorkoutImportModel = (ask: ImportAsk) => Promise<ImportedWorkout>;

const SYSTEM = `You turn a workout someone saw in a social video (TikTok, Instagram, YouTube) into a workout they can do.
You get any of: the post's caption, screenshots of the video, and their own description.
- List the exercises in the order shown. For each: "said" = the move as written or described (max 40 characters), "id" = the closest id from the exercise list.
- "sure" = true only when the id is the same exercise (same movement and equipment). A close substitute gets sure = false. If nothing in the list is close, id = "" and sure = false.
- Sets and reps as given. If missing, pick sensible ones (3 x 10; holds 3 x 30 seconds; cardio 1 x 10 minutes). "unit": reps, sec or min.
- "name" is a short, catchy name for the workout (max 40 characters), from the post's title if it has one. "minutes" = realistic total time.
- Ignore hashtags, music, sponsor codes, calls to follow and anything that is not part of the workout. If there is no workout at all, return no items.`;

const schema = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    minutes: { type: 'integer' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          said: { type: 'string' },
          id: { type: 'string' },
          sets: { type: 'integer' },
          reps: { type: 'integer' },
          unit: { type: 'string', enum: ['reps', 'sec', 'min'] },
          sure: { type: 'boolean' },
        },
        required: ['said', 'id', 'sets', 'reps', 'unit', 'sure'],
        additionalProperties: false,
      },
    },
  },
  required: ['name', 'minutes', 'items'],
  additionalProperties: false,
} as const;

const int = (n: unknown, min: number, max: number, fallback: number) =>
  typeof n === 'number' && Number.isFinite(n) ? Math.round(Math.min(max, Math.max(min, n))) : fallback;

const tidy = (s: unknown, max: number) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, max);

/** Known ids only (else empty and unsure), numbers in the editor's ranges, at most 40 moves. */
export const cleanImport = (raw: Partial<Omit<ImportedWorkout, 'items'>> & { items?: Partial<ImportedItem>[] }, catalog: ScanItem[]): ImportedWorkout => {
  const known = new Map(catalog.map((c) => [c.id, c.label]));
  const items: ImportedItem[] = [];
  for (const r of raw.items ?? []) {
    const id = r.id && known.has(r.id) ? r.id : '';
    const said = tidy(r.said, 40) || (id ? known.get(id)! : '');
    if (!said) continue;
    const unit: ImportUnit = r.unit === 'sec' || r.unit === 'min' ? r.unit : 'reps';
    items.push({
      said,
      id,
      sets: int(r.sets, 1, 20, 3),
      reps: int(r.reps, 1, unit === 'sec' ? 600 : unit === 'min' ? 120 : 100, unit === 'sec' ? 30 : 10),
      unit,
      sure: !!id && r.sure === true,
    });
    if (items.length >= 40) break;
  }
  return { name: tidy(raw.name, 40) || 'Saved workout', minutes: int(raw.minutes, 5, 180, 30), items };
};

/** Platform and a clean https link (tracking query dropped), or undefined for anything but a web link. */
export const sourceOf = (link: string): ImportSource | undefined => {
  let u: URL;
  try {
    u = new URL(link.trim());
  } catch {
    return undefined;
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return undefined;
  if (u.username || u.password) return undefined;
  const host = u.hostname.toLowerCase().replace(/^www\.|^m\./, '');
  const platform: Platform = /(^|\.)tiktok\.com$/.test(host)
    ? 'tiktok'
    : /(^|\.)instagram\.com$/.test(host) || host === 'instagr.am'
      ? 'instagram'
      : /(^|\.)youtube\.com$/.test(host) || host === 'youtu.be'
        ? 'youtube'
        : 'web';
  // YouTube keeps `v`; the rest of every query is share tracking.
  const keep = platform === 'youtube' && u.searchParams.get('v') ? `?v=${encodeURIComponent(u.searchParams.get('v')!)}` : '';
  return { platform, url: `https://${u.hostname.toLowerCase()}${u.pathname}${keep}`.slice(0, 500) };
};

/** Public oEmbed endpoints that need no key: TikTok's title is the caption, YouTube's only the title. */
const OEMBED: Partial<Record<Platform, string>> = {
  tiktok: 'https://www.tiktok.com/oembed?url=',
  youtube: 'https://www.youtube.com/oembed?format=json&url=',
};

/**
 * Caption and creator from the platform's public oEmbed (fixed hosts only, 5 s, small answers). Instagram's needs a
 * Meta app token, so its caption comes from the share or screenshots. Undefined when the platform says nothing.
 */
export const oembed = async (fetch: Fetch, source: ImportSource): Promise<{ caption?: string; author?: string } | undefined> => {
  const base = OEMBED[source.platform];
  if (!base) return undefined;
  try {
    const res = await fetch(base + encodeURIComponent(source.url), { signal: AbortSignal.timeout(5000), redirect: 'error' });
    if (!res.ok) return undefined;
    const text = await res.text();
    if (text.length > 200_000) return undefined;
    const j = JSON.parse(text) as { title?: unknown; author_name?: unknown; author_unique_id?: unknown };
    const caption = typeof j.title === 'string' ? j.title.slice(0, 4000) : undefined;
    const handle = typeof j.author_unique_id === 'string' ? `@${j.author_unique_id}` : typeof j.author_name === 'string' ? j.author_name : undefined;
    return { caption, author: handle ? tidy(handle, 60) : undefined };
  } catch {
    return undefined;
  }
};

/** Scan model (#866): reading a caption or screenshots against the exercise list, medium effort. */
export const claudeWorkoutImport = (apiKey: string, workspaceId?: string, model = AI_MODELS.scan): WorkoutImportModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 90_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (ask) => {
    const said = [
      ask.caption ? `Post caption:\n${ask.caption}` : '',
      ask.text ? `What they say they saw:\n${ask.text}` : '',
      ask.photos.length ? `${ask.photos.length} screenshot(s) of the video follow.` : '',
    ].filter(Boolean).join('\n\n');
    const res = await tracked('workout-import', model, () => client.beta.messages.create({
      model,
      max_tokens: 6000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SYSTEM,
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [
        {
          role: 'user',
          content: [
            // Catalog first and cached (same for every import), then the post.
            { type: 'text', text: `Exercise ids (id: name):\n${ask.catalog.map((c) => `${c.id}: ${c.label}`).join('\n')}`, cache_control: CACHED },
            { type: 'text', text: said },
            ...ask.photos.map((p) => ({ type: 'image' as const, source: { type: 'base64' as const, media_type: 'image/jpeg' as const, data: p.toString('base64') } })),
          ],
        },
      ],
    }));
    if (res.stop_reason === 'refusal') return { name: '', minutes: 30, items: [] };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return cleanImport(JSON.parse(text) as Partial<ImportedWorkout>, ask.catalog);
  };
};
