import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { GymScanModel } from '../coach/gymScan.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';

const MAX_PHOTO = 1_500_000;

const body = z.object({
  /** JPEG, base64. */
  photo: z.string().min(100).max(Math.ceil((MAX_PHOTO * 4) / 3) + 4),
  catalog: z
    .array(z.object({ id: z.string().regex(/^[a-z0-9-]{1,32}$/), label: z.string().trim().min(1).max(60) }))
    .min(1)
    .max(150),
});

/**
 * Gym scan (#406): POST /v1/me/gym-scan with one photo of an area; answers the equipment ids seen on it. Pro once
 * subscriptions are enforced; daily cap per member bounds the spend.
 */
export const gymScanRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  scan: GymScanModel | undefined,
  dailyLimit: number,
  hasAccess: (userId: string) => boolean,
) => {
  r.post('/me/gym-scan', { bodyLimit: 2_200_000 }, async (req) => {
    if (!scan) throw new ApiError(503, 'scan_unavailable', 'Gym scan is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Gym scan is part of MonkeyWorkout Pro.');
    const b = body.parse(req.body);
    const jpeg = Buffer.from(b.photo, 'base64');
    if (jpeg.length > MAX_PHOTO || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new ApiError(400, 'bad_photo', 'Send one JPEG photo up to 1.5 MB.');
    const day = now().toISOString().slice(0, 10);
    const used =
      (db.prepare('SELECT count FROM gym_scan_usage WHERE user_id = ? AND day = ?').get(req.userId!, day) as { count: number } | undefined)?.count ?? 0;
    if (used >= dailyLimit) throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} scans today. Scan more tomorrow!`);
    let items: string[];
    try {
      items = await scan(jpeg, b.catalog);
    } catch (e) {
      req.log.warn(`gym scan failed: ${(e as Error).message}`);
      throw new ApiError(502, 'scan_failed', "Couldn't read that photo. Try again in a moment.");
    }
    db.prepare(
      `INSERT INTO gym_scan_usage (user_id, day, count) VALUES (?, ?, 1)
       ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1`,
    ).run(req.userId!, day);
    return { items, remainingToday: Math.max(0, dailyLimit - used - 1) };
  });
};
