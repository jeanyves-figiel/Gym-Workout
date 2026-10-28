import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { ReviewModel } from '../coach/review.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall } from '../quota.ts';

const weekday = z.number().int().min(1).max(7);
const name = z.string().trim().min(1).max(60);
const id = z.string().trim().min(1).max(80);

const body = z.object({
  digest: z.object({
    weekOf: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    goal: z.string().max(40).optional(),
    level: z.string().max(40).optional(),
    days: z.array(z.object({ weekday, title: name, done: z.boolean(), minutes: z.number().int().min(0).max(600).optional() })).max(21),
    bests: z.array(z.string().trim().min(1).max(80)).max(10).default([]),
    sleepHours: z.number().min(0).max(24).optional(),
    hrv: z.string().max(40).optional(),
    mood: z.number().min(1).max(5).optional(),
    moodAbout: z.array(z.string().trim().min(1).max(30)).max(8).default([]),
    next: z
      .array(z.object({ id, weekday, title: name, lifts: z.array(z.object({ uid: id, name, sets: z.number().int().min(1).max(20) })).max(20) }))
      .max(14),
    offDays: z.array(weekday).max(7).default([]),
  }),
});

/**
 * Weekly Coach review (#867): POST /v1/me/coach-review with the week's digest; answers score, headline, summary and up
 * to 3 changes for the coming week. Pro once subscriptions are enforced; 3 a day per member (the app asks once a week
 * and caches the answer).
 */
export const coachReviewRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  review: ReviewModel | undefined,
  hasAccess: (userId: string) => boolean,
  globalLimit: number,
  dailyLimit = 3,
) => {
  const busy = inFlight(1);

  r.post('/me/coach-review', async (req) => {
    if (!review) throw new ApiError(503, 'coach_unavailable', 'Coach review is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Coach review is part of MonkeyWorkout Pro.');
    const { digest } = body.parse(req.body);
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Coach is still looking at your week.');
    try {
      const slot = reserveAiCall(db, 'coach_review_usage', req.userId!, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', 'Coach already looked at your week today.');
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Coach is very busy today. Try again tomorrow!');
      try {
        return await review(digest);
      } catch (e) {
        refundAiCall(db, 'coach_review_usage', req.userId!, day);
        req.log.warn(`coach review failed: ${(e as Error).message}`);
        throw new ApiError(502, 'coach_failed', 'Coach is catching breath. Try again in a moment.');
      }
    } finally {
      busy.leave(req.userId!);
    }
  });
};
