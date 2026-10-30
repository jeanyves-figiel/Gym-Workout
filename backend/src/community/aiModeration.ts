import { createHash } from 'node:crypto';
import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS } from '../coach/models.ts';
import type { DB } from '../db.ts';
import { reserveGlobal } from '../quota.ts';
import { ApiError } from '../errors.ts';
import { DAY, throttleTake } from '../throttle.ts';

/**
 * AI moderation (#871, epic #865): before a shared name, caption or profile photo goes live, a small model checks it
 * against the community guidelines. The word filter (`filter.ts`) still runs first and refuses outright; the model
 * catches what words can't (threats, harassment, sexual or hateful photos, spam). Flagged text or photos are refused on
 * the spot like the word filter (#871 follow-up: no review queue, nobody has to moderate); reports and blocks stay the
 * human backstop. Free to members, counted in AI_DAILY_LIMIT; when the model is off, over budget, slow or failing, the
 * word filter alone decides (fail open).
 */
export const FLAG_CATEGORIES = ['harassment', 'hate', 'sexual', 'violence', 'self_harm', 'spam', 'other'] as const;
export type FlagCategory = (typeof FLAG_CATEGORIES)[number];

export interface ModerationInput {
  texts: string[];
  /** Profile photo, JPEG. */
  jpeg?: Buffer;
}
/** Null = fine; a category = hold it. Throws when the model can't answer (the caller fails open). */
export type ModerationModel = (input: ModerationInput) => Promise<FlagCategory | null>;

const SYSTEM = `You moderate a gym app's community: members share workout posts, captions, plan and workout names, nicknames, short bios and profile photos. Decide if the content breaks the guidelines.

Flag only clear problems: harassment or insults aimed at someone, hate against a group, sexual content or nudity, threats or glorified violence, encouraging self-harm or eating disorders, spam (ads, links to sell something, scams, contact-me-for-money), or other clearly unsafe content (drugs for sale, doxxing).

Never flag ordinary gym talk, even when it sounds rough: "killed legs today", "destroyed my PR", "beast mode", "suicide sprints", "dead bug", "skull crushers", "this workout is murder", swearing at oneself or at the weights, body parts in exercise names, shirtless or sports-bra gym photos, physique progress photos, sweat, blood from a torn callus. Text may be English, French, German or other languages. When unsure, do not flag.`;

const schema = {
  type: 'object',
  properties: {
    flagged: { type: 'boolean' },
    category: { type: 'string', enum: [...FLAG_CATEGORIES, 'none'] },
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
    return FLAG_CATEGORIES.includes(out.category as FlagCategory) ? (out.category as FlagCategory) : 'other';
  };
};

/** Non-empty, trimmed, de-duplicated. */
const texts = (xs: (string | null | undefined)[]) => [...new Set(xs.map((x) => x?.trim()).filter((x): x is string => !!x))];

/** Checks one member may run per UTC day (#920); then their changes wait until tomorrow (fail closed for them). */
export const MODERATION_PER_MEMBER = 40;
/** Clean texts remembered, so re-sending the same words costs nothing (#920). */
const CLEAN_CACHE = 5_000;

export interface Moderator {
  /**
   * 400 `objectionable_content` when the model flags the texts or photo; 429 `daily_limit` when `userId` used up their
   * checks today; resolves when clean or the check could not run.
   */
  assertAllowed: (input: { userId?: string; texts: (string | null | undefined)[]; jpeg?: Buffer }) => Promise<void>;
}

/**
 * Budget (#920): moderation has its own daily pool (`limit`, `MODERATION_DAILY_LIMIT`), separate from the paid features'
 * `AI_DAILY_LIMIT`, so a member editing captions in a loop can't make Coach "busy" for everyone. Each member gets
 * `MODERATION_PER_MEMBER` checks a day; clean texts already checked are free.
 */
export const aiModerator = (
  db: DB,
  now: () => Date,
  model: ModerationModel | undefined,
  limit: number,
  log: { warn: (msg: string) => void; info: (msg: string) => void },
): Moderator => {
  const clean = new Set<string>();
  const keyOf = (t: string) => createHash('sha256').update(t).digest('hex');
  return {
    assertAllowed: async (input) => {
      const t = texts(input.texts).filter((x) => !clean.has(keyOf(x)));
      if (!model || (!t.length && !input.jpeg)) return;
      const at = now();
      if (input.userId && !throttleTake(db, `moderate:${input.userId}`, MODERATION_PER_MEMBER, DAY, at))
        throw new ApiError(429, 'daily_limit', "That's a lot of changes today. Try again tomorrow!");
      if (!reserveGlobal(db, `moderation:${at.toISOString().slice(0, 10)}`, limit)) {
        log.warn('AI moderation skipped (word filter only): daily moderation budget spent');
        return;
      }
      let category: FlagCategory | null;
      try {
        category = await model({ texts: t, jpeg: input.jpeg });
      } catch (e) {
        log.warn(`AI moderation skipped (word filter only): ${String(e)}`);
        return;
      }
      if (!category) {
        for (const x of t) clean.add(keyOf(x));
        while (clean.size > CLEAN_CACHE) clean.delete(clean.values().next().value!);
        return;
      }
      log.info(`AI moderation refused ${input.jpeg ? 'a photo' : 'text'}: ${category}`);
      throw input.jpeg
        ? new ApiError(400, 'objectionable_content', 'Please pick another photo: that one is not allowed in the community.')
        : new ApiError(400, 'objectionable_content', 'Please keep it friendly: that text is not allowed in the community.');
    },
  };
};

/** Test / no-key stand-in. */
export const noModerator = (): Moderator => ({ assertAllowed: () => Promise.resolve() });
