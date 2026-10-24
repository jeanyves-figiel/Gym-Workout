import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { sanitizeJpeg } from '../community/image.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import { assertByteQuota, assertItemSize } from '../quota.ts';
import { baseUpdatedAt, conflictsField, opaqueCopy, sendPull, type SyncTable, syncId, takeConflicts } from './sync.ts';

/** Max stored size of one exercise record (photo is a base64 JPEG the app keeps under ~300 KB). */
export const MAX_CUSTOM_EXERCISE_BYTES = 450_000;
/** Max custom exercises per user. */
export const MAX_CUSTOM_EXERCISES = 300;

/** User-built exercises (opaque app-defined records). Deletion is a soft `archived` flag set by the app,
 *  so history keeps resolving; rows go away with the account. */
const customExercise = z
  .object({
    id: syncId,
    baseUpdatedAt,
    name: z.string().trim().min(1).max(100),
    photo: z.string().max(MAX_CUSTOM_EXERCISE_BYTES).regex(/^[A-Za-z0-9+/=]*$/).optional(),
  })
  .catchall(z.unknown());

export const customExerciseTable: SyncTable<{ data: string; updated_at: string }> = {
  table: 'custom_exercises',
  cols: 'data, updated_at',
  timeCol: 'updated_at',
  map: opaqueCopy,
};

/** The photo as stored (#713): a real JPEG, re-encoded without EXIF (GPS, device) like every other uploaded image. */
const cleanPhoto = (photo: string | undefined): string | undefined =>
  photo ? sanitizeJpeg(Buffer.from(photo, 'base64')).data.toString('base64') : photo;

export const customExerciseRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  // Archived by a flag, never deleted: `deleted` stays empty, kept for the same since-pull shape (#432).
  r.get('/me/custom-exercises', async (req, reply) =>
    sendPull(reply, db, customExerciseTable, { key: 'exercises', kind: 'custom-exercises', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/custom-exercises', async (req) => {
    // Photos make records large: the app pushes a few per request (Fastify body limit 1 MB).
    const b = z.object({ exercises: z.array(customExercise).max(20) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO custom_exercises (id, user_id, data, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at
       WHERE custom_exercises.user_id = excluded.user_id`,
    );
    const count = db.prepare('SELECT COUNT(*) AS n FROM custom_exercises WHERE user_id = ?');
    const exists = db.prepare('SELECT 1 FROM custom_exercises WHERE id = ? AND user_id = ?');
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'custom_exercises', req.userId!, b.exercises, opaqueCopy);
      const jsons = fresh.map((e) => JSON.stringify(e.photo ? { ...e, photo: cleanPhoto(e.photo) } : e));
      for (const j of jsons) assertItemSize(j, MAX_CUSTOM_EXERCISE_BYTES, 'Exercise');
      assertByteQuota(db, 'custom_exercises', req.userId!, fresh.map((e, i) => ({ id: e.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let written = 0;
      fresh.forEach((e, i) => {
        if (!exists.get(e.id, req.userId!) && (count.get(req.userId!) as { n: number }).n >= MAX_CUSTOM_EXERCISES)
          throw new ApiError(409, 'quota_exceeded', 'Storage limit reached for this kind of data.', { limit: MAX_CUSTOM_EXERCISES });
        written += Number(up.run(e.id, req.userId!, jsons[i]!, ts).changes);
      });
      return { saved: written, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });
};
