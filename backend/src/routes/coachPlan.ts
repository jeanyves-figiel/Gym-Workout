import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { PlanSetupModel } from '../coach/planSetup.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall } from '../quota.ts';

const planBody = z.object({ text: z.string().trim().min(3).max(500) });

const helpBody = z.object({
  step: z.string().trim().min(1).max(40),
  options: z.array(z.object({ id: z.string().trim().min(1).max(40), label: z.string().trim().min(1).max(120) })).min(1).max(12),
  so: z.array(z.string().trim().min(1).max(80)).max(12).default([]),
  question: z.string().trim().min(1).max(300).optional(),
});

/**
 * Set up the plan with Coach (#873): POST /v1/me/coach-plan with the member's sentence → the plan form's values;
 * POST /v1/me/coach-plan/help with one form step → a short answer and Coach's pick. Part of onboarding, so free for
 * every member; 15 calls a day per member between both.
 */
export const coachPlanRoutes = (r: FastifyInstance, db: DB, now: () => Date, model: PlanSetupModel | undefined, globalLimit: number, dailyLimit = 15) => {
  const busy = inFlight(1);

  const run = async <T>(userId: string, log: (m: string) => void, call: (m: PlanSetupModel) => Promise<T>) => {
    if (!model) throw new ApiError(503, 'coach_unavailable', 'Coach is not available right now.');
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(userId)) throw new ApiError(429, 'busy', 'Coach is still thinking.');
    try {
      const slot = reserveAiCall(db, 'coach_plan_usage', userId, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', 'That is a lot of questions for one day. Pick on the form for now.');
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Coach is very busy today. Pick on the form for now.');
      try {
        return await call(model);
      } catch (e) {
        refundAiCall(db, 'coach_plan_usage', userId, day);
        log(`coach plan failed: ${(e as Error).message}`);
        throw new ApiError(502, 'coach_failed', 'Coach is catching breath. Try again in a moment.');
      }
    } finally {
      busy.leave(userId);
    }
  };

  r.post('/me/coach-plan', async (req) => {
    const { text } = planBody.parse(req.body);
    return run(req.userId!, (m) => req.log.warn(m), (m) => m.plan(text));
  });

  r.post('/me/coach-plan/help', async (req) => {
    const ask = helpBody.parse(req.body);
    return run(req.userId!, (m) => req.log.warn(m), (m) => m.help(ask));
  });
};
