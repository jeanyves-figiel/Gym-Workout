import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { SetTalkModel } from '../coach/setTalk.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall } from '../quota.ts';

const kg = z.number().min(0).max(1000);
const reps = z.number().int().min(0).max(1000);

const body = z.object({
  question: z.string().trim().min(1).max(300),
  context: z.object({
    exercise: z.string().trim().min(1).max(80),
    set: z.number().int().min(1).max(50),
    sets: z.number().int().min(1).max(50),
    kg: kg.optional(),
    reps: reps.optional(),
    step: z.number().min(0.25).max(20).default(2.5),
    done: z.array(z.object({ kg, reps, rir: z.number().int().min(0).max(10).optional() })).max(50).default([]),
    lastTime: z.string().trim().max(80).optional(),
    restSec: z.number().int().min(0).max(1200).optional(),
    swaps: z.array(z.object({ id: z.string().trim().min(1).max(80), name: z.string().trim().min(1).max(80) })).max(4).default([]),
  }),
});

/**
 * Talk to Coach mid-set (#874): POST /v1/me/coach-set with the question and the set on screen; answers a short spoken
 * reply and up to 2 fixes (weight, swap, rest). Pro once subscriptions are enforced; 30 a day per member.
 */
export const coachSetRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  talk: SetTalkModel | undefined,
  hasAccess: (userId: string) => boolean,
  globalLimit: number,
  dailyLimit = 30,
) => {
  const busy = inFlight(1);

  r.post('/me/coach-set', async (req) => {
    if (!talk) throw new ApiError(503, 'coach_unavailable', 'Coach is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Talking to Coach is part of MonkeyWorkout Pro.');
    const { question, context } = body.parse(req.body);
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Coach is still answering.');
    try {
      const slot = reserveAiCall(db, 'coach_set_usage', req.userId!, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', "That's a lot of questions today. Coach is back tomorrow!");
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Coach is very busy today. Try again tomorrow!');
      try {
        return await talk(question, context);
      } catch (e) {
        refundAiCall(db, 'coach_set_usage', req.userId!, day);
        req.log.warn(`coach set failed: ${(e as Error).message}`);
        throw new ApiError(502, 'coach_failed', 'Coach is catching breath. Try again in a moment.');
      }
    } finally {
      busy.leave(req.userId!);
    }
  });
};
