import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, deletedField, opaqueCopy, sinceQuery, takeConflicts } from './sync.ts';

/** Max stored size of one exercise record (photo is a base64 JPEG the app keeps under ~300 KB). */
export const MAX_CUSTOM_EXERCISE_BYTES = 450_000;
/** Max custom exercises per user. */
export const MAX_CUSTOM_EXERCISES = 300;

/** User-built exercises (opaque app-defined records). Deletion is a soft `archived` flag set by the app,
 *  so history keeps resolving; rows go away with the account. */
const customExercise = z
  .object({
    id: z.uuid(),
    baseUpdatedAt,
    name: z.string().trim().min(1).max(100),
    photo: z.string().max(MAX_CUSTOM_EXERCISE_BYTES).regex(/^[A-Za-z0-9+/=]*$/).optional(),
  })
  .catchall(z.unknown());

export const listCustomExercises = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM custom_exercises WHERE user_id = ? AND updated_at >= ? ORDER BY updated_at').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM custom_exercises WHERE user_id = ? ORDER BY updated_at').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const customExerciseRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/custom-exercises', async (req) => {
    const q = sinceQuery.parse(req.query);
    // Archived by a flag, never deleted: `deleted` stays empty, kept for the same since-pull shape (#432).
    return { exercises: listCustomExercises(db, req.userId!, q.since), ...deletedField(db, req.userId!, 'custom-exercises', q.since, now()), serverTime: now().toISOString() };
  });

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
      let written = 0;
      for (const e of fresh) {
        const json = JSON.stringify(e);
        if (json.length > MAX_CUSTOM_EXERCISE_BYTES) throw Object.assign(new Error('Exercise too large'), { statusCode: 413 });
        if (!exists.get(e.id, req.userId!) && (count.get(req.userId!) as { n: number }).n >= MAX_CUSTOM_EXERCISES)
          throw Object.assign(new Error('Too many custom exercises'), { statusCode: 409 });
        written += Number(up.run(e.id, req.userId!, json, ts).changes);
      }
      return { saved: written, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });
};
