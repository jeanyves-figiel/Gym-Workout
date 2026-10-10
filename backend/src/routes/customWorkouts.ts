import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';

/** User-built workouts (opaque app-defined records, like completed workouts). */
const customWorkout = z
  .object({
    id: z.uuid(),
    name: z.string().trim().min(1).max(100),
    items: z.array(z.object({ exerciseId: z.string().min(1).max(64) }).catchall(z.unknown())).max(100),
  })
  .catchall(z.unknown());

export const listCustomWorkouts = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM custom_workouts WHERE user_id = ? AND updated_at > ? ORDER BY updated_at').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM custom_workouts WHERE user_id = ? ORDER BY updated_at').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const customWorkoutRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/custom-workouts', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { workouts: listCustomWorkouts(db, req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/custom-workouts', async (req) => {
    const b = z.object({ workouts: z.array(customWorkout).max(100) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO custom_workouts (id, user_id, data, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at
       WHERE custom_workouts.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const w of b.workouts) {
        const json = JSON.stringify(w);
        if (json.length > 100_000) throw Object.assign(new Error('Workout too large'), { statusCode: 413 });
        up.run(w.id, req.userId!, json, ts);
      }
    });
    return { saved: b.workouts.length, serverTime: ts };
  });

  r.delete('/me/custom-workouts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM custom_workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });
};
