import Anthropic from '@anthropic-ai/sdk';
import { randomUUID } from 'node:crypto';
import { AI_MODELS } from '../coach/models.ts';
import type { DB } from '../db.ts';
import type { Mailer } from '../mailer.ts';
import { reserveGlobal } from '../quota.ts';
import { isHidden } from './moderation.ts';

/**
 * AI moderation (#871, epic #865): before a shared name, caption or profile photo goes live, a small model checks it
 * against the community guidelines. The word filter (`filter.ts`) still runs first and refuses outright; the model
 * catches what words can't (threats, harassment, sexual or hateful photos, spam). Flagged items are held: hidden from
 * others until an owner releases or rejects them (`admin.ts holds`). Free to members, counted in AI_DAILY_LIMIT; when
 * the model is off, over budget, slow or failing, items go live on the word filter alone (fail open).
 */
export const HOLD_CATEGORIES = ['harassment', 'hate', 'sexual', 'violence', 'self_harm', 'spam', 'other'] as const;
export type HoldCategory = (typeof HOLD_CATEGORIES)[number];
export type HoldTarget = 'post' | 'program' | 'workout' | 'avatar';

export interface ModerationInput {
  texts: string[];
  /** Profile photo, JPEG. */
  jpeg?: Buffer;
}
/** Null = fine; a category = hold it. Throws when the model can't answer (the caller fails open). */
export type ModerationModel = (input: ModerationInput) => Promise<HoldCategory | null>;

const SYSTEM = `You moderate a gym app's community: members share workout posts, captions, plan and workout names, nicknames, short bios and profile photos. Decide if the content breaks the guidelines.

Flag only clear problems: harassment or insults aimed at someone, hate against a group, sexual content or nudity, threats or glorified violence, encouraging self-harm or eating disorders, spam (ads, links to sell something, scams, contact-me-for-money), or other clearly unsafe content (drugs for sale, doxxing).

Never flag ordinary gym talk, even when it sounds rough: "killed legs today", "destroyed my PR", "beast mode", "suicide sprints", "dead bug", "skull crushers", "this workout is murder", swearing at oneself or at the weights, body parts in exercise names, shirtless or sports-bra gym photos, physique progress photos, sweat, blood from a torn callus. Text may be English, French, German or other languages. When unsure, do not flag.`;

const schema = {
  type: 'object',
  properties: {
    flagged: { type: 'boolean' },
    category: { type: 'string', enum: [...HOLD_CATEGORIES, 'none'] },
  },
  required: ['flagged', 'category'],
  additionalProperties: false,
} as const;

/** Claude Haiku (task model `moderate`, #866) with structured output, low effort; one try, short timeout. */
export const claudeModeration = (apiKey: string, workspaceId?: string, model = AI_MODELS.moderate): ModerationModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 8_000,
    maxRetries: 0,
    ...(workspaceId ? { defaultHeaders: { 'anthropic-workspace-id': workspaceId } } : {}),
  });
  return async ({ texts, jpeg }) => {
    const res = await client.messages.create({
      model,
      max_tokens: 2000,
      system: SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages: [
        {
          role: 'user',
          content: [
            ...(jpeg ? [{ type: 'image' as const, source: { type: 'base64' as const, media_type: 'image/jpeg' as const, data: jpeg.toString('base64') } }] : []),
            { type: 'text', text: texts.length ? `Shared text, one item per line:\n${texts.join('\n')}` : 'Profile photo above.' },
          ],
        },
      ],
    });
    // A safety refusal on member content means it is not fit to share either.
    if (res.stop_reason === 'refusal') return 'other';
    const text = res.content.find((b) => b.type === 'text');
    if (!text || text.type !== 'text') throw new Error('moderation: no answer');
    const out = JSON.parse(text.text) as { flagged?: unknown; category?: unknown };
    if (out.flagged !== true) return null;
    return HOLD_CATEGORIES.includes(out.category as HoldCategory) ? (out.category as HoldCategory) : 'other';
  };
};

/** Non-empty, trimmed, de-duplicated. */
const texts = (xs: (string | null | undefined)[]) => [...new Set(xs.map((x) => x?.trim()).filter((x): x is string => !!x))];

export interface Moderator {
  /** Category to hold for, or null (clean, or the check could not run). */
  check: (input: { texts: (string | null | undefined)[]; jpeg?: Buffer }) => Promise<HoldCategory | null>;
  /** Records a hold and tells the moderation mailbox. The caller hides the item. */
  hold: (h: { userId: string; type: HoldTarget; id: string; category: HoldCategory; texts?: (string | null | undefined)[]; jpeg?: Buffer }) => void;
}

export const aiModerator = (
  db: DB,
  now: () => Date,
  model: ModerationModel | undefined,
  globalLimit: number,
  mailer: Mailer,
  moderationEmail: string | undefined,
  log: { warn: (msg: string) => void },
): Moderator => ({
  check: async (input) => {
    const t = texts(input.texts);
    if (!model || (!t.length && !input.jpeg)) return null;
    if (!reserveGlobal(db, now().toISOString().slice(0, 10), globalLimit)) return null;
    try {
      return await model({ texts: t, jpeg: input.jpeg });
    } catch (e) {
      log.warn(`AI moderation skipped (word filter only): ${String(e)}`);
      return null;
    }
  },
  hold: (h) => {
    const id = randomUUID();
    const ts = now().toISOString();
    db.prepare('INSERT INTO moderation_holds (id, user_id, target_type, target_id, category, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, h.userId, h.type, h.id, h.category, ts);
    if (moderationEmail)
      mailer
        .send({
          to: moderationEmail,
          subject: `Community hold: ${h.category} (${h.type})`,
          text: [
            `Held by AI moderation (#871): hidden until reviewed.`,
            `Hold: ${id}`,
            `Member: ${h.userId}`,
            `${h.type}: ${h.id}`,
            `Category: ${h.category}`,
            ...texts(h.texts ?? []).map((x) => `Text: ${x}`),
            `At: ${ts}`,
            `Release: "Moderation holds" workflow, action release, id ${id} (or reject).`,
          ].join('\n'),
          ...(h.jpeg ? { attachments: [{ filename: 'photo.jpg', contentType: 'image/jpeg', content: h.jpeg }] } : {}),
        })
        .catch((e: unknown) => log.warn(`moderation mail failed: ${String(e)}`));
  },
});

/** Test / no-key stand-in. */
export const noModerator = (): Moderator => ({ check: () => Promise.resolve(null), hold: () => undefined });

export interface HoldRow {
  id: string;
  user_id: string;
  target_type: HoldTarget;
  target_id: string;
  category: string;
  created_at: string;
}

/** True while an open hold keeps this item hidden (edits don't release it). */
export const isHeld = (db: DB, type: HoldTarget, id: string) =>
  !!db.prepare('SELECT 1 FROM moderation_holds WHERE target_type = ? AND target_id = ? AND resolved_at IS NULL').get(type, id);

export const openHolds = (db: DB) =>
  db
    .prepare(
      `SELECT h.*, cp.nickname FROM moderation_holds h LEFT JOIN community_profiles cp ON cp.user_id = h.user_id
       WHERE h.resolved_at IS NULL ORDER BY h.created_at`,
    )
    .all() as unknown as (HoldRow & { nickname: string | null })[];

const TABLE: Record<Exclude<HoldTarget, 'avatar'>, string> = { post: 'community_posts', program: 'community_programs', workout: 'custom_workouts' };

/**
 * Release puts the item live (unless reports still hide it; a held photo becomes the member's photo if it is still
 * their latest). Reject keeps it hidden (a photo is deleted). False when there is no open hold with that id.
 */
export const resolveHold = (db: DB, holdId: string, decision: 'released' | 'rejected', at: Date): boolean => {
  const h = db.prepare('SELECT * FROM moderation_holds WHERE id = ? AND resolved_at IS NULL').get(holdId) as HoldRow | undefined;
  if (!h) return false;
  const ts = at.toISOString();
  db.prepare('UPDATE moderation_holds SET resolved_at = ?, decision = ? WHERE id = ?').run(ts, decision, h.id);
  if (h.target_type === 'avatar') {
    if (decision === 'rejected') db.prepare('DELETE FROM community_avatars WHERE id = ?').run(h.target_id);
    else if (db.prepare('SELECT 1 FROM community_avatars WHERE id = ?').get(h.target_id)) {
      db.prepare('DELETE FROM community_avatars WHERE user_id = ? AND id != ?').run(h.user_id, h.target_id);
      db.prepare('UPDATE community_profiles SET avatar_id = ?, updated_at = ? WHERE user_id = ?').run(h.target_id, ts, h.user_id);
      db.prepare('UPDATE user_profiles SET avatar_id = ?, updated_at = ? WHERE user_id = ?').run(h.target_id, ts, h.user_id);
    }
  } else if (decision === 'released' && !isHeld(db, h.target_type, h.target_id) && !isHidden(db, h.target_type, h.target_id)) {
    db.prepare(`UPDATE ${TABLE[h.target_type]} SET hidden_at = NULL WHERE id = ?`).run(h.target_id);
  }
  return true;
};
