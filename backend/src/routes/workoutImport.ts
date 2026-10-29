import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Fetch } from '../appleTokens.ts';
import { type ImportedWorkout, type ImportSource, oembed, sourceOf, type WorkoutImportModel } from '../coach/workoutImport.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall, trustedAccount } from '../quota.ts';

const MAX_PHOTO = 1_500_000;

const body = z.object({
  /** The post's link (TikTok, Instagram, YouTube or any page). */
  link: z.string().trim().max(500).optional(),
  /** The post's caption, when the share or the member gave it. */
  caption: z.string().trim().max(4000).optional(),
  /** The member's own words ("Tell Coach", #909 C). */
  text: z.string().trim().max(2000).optional(),
  /** Up to 4 screenshots, JPEG base64. */
  photos: z.array(z.string().min(100).max(Math.ceil((MAX_PHOTO * 4) / 3) + 4)).max(4).default([]),
  catalog: z
    .array(z.object({ id: z.string().regex(/^[A-Za-z0-9-]{1,64}$/), label: z.string().trim().min(1).max(60) }))
    .min(1)
    .max(600),
});

/**
 * Save a workout seen on TikTok / Instagram (#909): POST /v1/me/workout-import with the link, caption, screenshots
 * and/or the member's words; answers a workout mapped onto the app's exercise ids plus the cleaned source link and
 * creator. TikTok and YouTube captions come from their public oEmbed when the share had none. Pro; daily cap.
 */
export const workoutImportRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  model: WorkoutImportModel | undefined,
  dailyLimit: number,
  hasAccess: (userId: string) => boolean,
  globalLimit: number,
  fetch: Fetch,
) => {
  const busy = inFlight(2);

  r.post('/me/workout-import', { bodyLimit: 8_500_000 }, async (req) => {
    if (!model) throw new ApiError(503, 'import_unavailable', 'Saving from a video is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Saving workouts from videos is part of MonkeyWorkout Pro.');
    if (!trustedAccount(db, req.userId!, now()))
      throw new ApiError(403, 'verification_required', 'Verify your email to save from videos, or try again tomorrow.');
    const b = body.parse(req.body);
    const photos = b.photos.map((p) => Buffer.from(p, 'base64'));
    if (photos.some((j) => j.length > MAX_PHOTO || j[0] !== 0xff || j[1] !== 0xd8))
      throw new ApiError(400, 'bad_photo', 'Send JPEG screenshots up to 1.5 MB each.');
    const link = b.link ? sourceOf(b.link) : undefined;
    if (b.link && !link) throw new ApiError(400, 'bad_link', "That doesn't look like a link.");
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Still reading your last video.');
    let workout: ImportedWorkout;
    let count: number;
    let source: ImportSource | undefined = link;
    try {
      let caption = b.caption;
      if (link && !caption) {
        const o = await oembed(fetch, link);
        caption = o?.caption;
        if (o?.author) source = { ...link, author: o.author };
      }
      if (!caption && !b.text && !photos.length)
        throw new ApiError(422, 'nothing_to_read', 'That post has no workout in its text. Add screenshots or say what you saw.');
      const slot = reserveAiCall(db, 'workout_import_usage', req.userId!, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} saved videos today. Save more tomorrow!`);
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Coach is very busy today. Try again tomorrow!');
      count = slot;
      try {
        workout = await model({ caption, text: b.text, photos, catalog: b.catalog });
      } catch (e) {
        refundAiCall(db, 'workout_import_usage', req.userId!, day);
        req.log.warn(`workout import failed: ${(e as Error).message}`);
        throw new ApiError(502, 'import_failed', "Couldn't read that workout. Try again in a moment.");
      }
    } finally {
      busy.leave(req.userId!);
    }
    return { ...workout, ...(source ? { source } : {}), remainingToday: Math.max(0, dailyLimit - count) };
  });
};
