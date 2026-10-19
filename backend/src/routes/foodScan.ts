import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { FoodScanModel } from '../coach/foodScan.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundDaily, reserveDaily } from '../quota.ts';

const MAX_PHOTO = 1_500_000;

const body = z.object({
  /** JPEG, base64. */
  photo: z.string().min(100).max(Math.ceil((MAX_PHOTO * 4) / 3) + 4),
  catalog: z
    .array(z.object({ id: z.string().regex(/^[a-z0-9-]{1,40}$/), label: z.string().trim().min(1).max(60) }))
    .min(1)
    .max(400),
});

/**
 * Food scan (#496): POST /v1/me/food-scan with one photo (fridge, cupboard, shopping, receipt); answers the food ids
 * seen on it. Pro once subscriptions are enforced; daily cap per member bounds the spend.
 */
export const foodScanRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  scan: FoodScanModel | undefined,
  dailyLimit: number,
  hasAccess: (userId: string) => boolean,
) => {
  const busy = inFlight(2);

  r.post('/me/food-scan', { bodyLimit: 2_200_000 }, async (req) => {
    if (!scan) throw new ApiError(503, 'scan_unavailable', 'Food scan is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Food scan is part of MonkeyWorkout Pro.');
    const b = body.parse(req.body);
    const jpeg = Buffer.from(b.photo, 'base64');
    if (jpeg.length > MAX_PHOTO || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new ApiError(400, 'bad_photo', 'Send one JPEG photo up to 1.5 MB.');
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Still reading your last photo.');
    let items: string[];
    let count: number | undefined;
    try {
      count = reserveDaily(db, 'food_scan_usage', req.userId!, day, dailyLimit);
      if (count === undefined) throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} food scans today. Scan more tomorrow!`);
      try {
        items = await scan(jpeg, b.catalog);
      } catch (e) {
        refundDaily(db, 'food_scan_usage', req.userId!, day);
        req.log.warn(`food scan failed: ${(e as Error).message}`);
        throw new ApiError(502, 'scan_failed', "Couldn't read that photo. Try again in a moment.");
      }
    } finally {
      busy.leave(req.userId!);
    }
    return { items, remainingToday: Math.max(0, dailyLimit - count) };
  });
};
