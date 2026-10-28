import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { MEALS, type MealIdea, type MealIdeasModel } from '../coach/mealIdeas.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall, trustedAccount } from '../quota.ts';

const body = z.object({
  pantry: z
    .array(z.object({ id: z.string().regex(/^[a-z0-9-]{1,40}$/), label: z.string().trim().min(1).max(60) }))
    .min(1)
    .max(300),
  meal: z.enum(MEALS),
  left: z.object({ protein: z.number().min(0).max(500), carbs: z.number().min(0).max(1500) }),
  diet: z.string().trim().max(30).optional(),
  avoid: z.array(z.string().trim().min(1).max(30)).max(20).default([]),
});

/**
 * Meal ideas (#869): POST /v1/me/meal-ideas with the pantry, the meal and what is left of today's protein and carbs;
 * answers up to three meals made of pantry foods (`ideas[{name, minutes, foods[{id, grams}], steps}]`). Pro once
 * subscriptions are enforced; its own daily cap per member plus the global AI budget.
 */
export const mealIdeasRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  model: MealIdeasModel | undefined,
  dailyLimit: number,
  hasAccess: (userId: string) => boolean,
  globalLimit: number,
) => {
  const busy = inFlight(2);

  r.post('/me/meal-ideas', async (req) => {
    const b = body.parse(req.body);
    if (!model) throw new ApiError(503, 'ideas_unavailable', 'Meal ideas are not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Meal ideas are part of MonkeyWorkout Pro.');
    if (!trustedAccount(db, req.userId!, now()))
      throw new ApiError(403, 'verification_required', 'Verify your email to get meal ideas, or try again tomorrow.');
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Still thinking about your last ideas.');
    let ideas: MealIdea[];
    let count: number;
    try {
      const slot = reserveAiCall(db, 'meal_ideas_usage', req.userId!, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} rounds of ideas today. More tomorrow!`);
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Monkey is very busy today. Try again tomorrow!');
      count = slot;
      try {
        ideas = await model({ pantry: b.pantry, meal: b.meal, left: b.left, diet: b.diet, avoid: b.avoid });
      } catch (e) {
        refundAiCall(db, 'meal_ideas_usage', req.userId!, day);
        req.log.warn(`meal ideas failed: ${(e as Error).message}`);
        throw new ApiError(502, 'ideas_failed', "Couldn't think of meals right now. Try again in a moment.");
      }
    } finally {
      busy.leave(req.userId!);
    }
    return { ideas, remainingToday: Math.max(0, dailyLimit - count) };
  });
};
