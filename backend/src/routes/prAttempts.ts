import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';

/** Personal-record attempts (#60): app-defined records; the typed fields are what a future community feed reads. */
const prAttempt = z
  .object({
    id: z.uuid(),
    exerciseId: z.string().min(1).max(64),
    date: z.iso.datetime({ offset: true }),
    kind: z.enum(['oneRepMax', 'repMax', 'maxReps']),
    kg: z.number().min(0).max(1000),
    reps: z.number().int().min(0).max(1000),
    success: z.boolean(),
    isRecord: z.boolean().optional(),
  })
  .catchall(z.unknown());

export const listPrAttempts = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM pr_attempts WHERE user_id = ? AND updated_at > ? ORDER BY date').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM pr_attempts WHERE user_id = ? ORDER BY date').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const prAttemptRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/pr-attempts', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { attempts: listPrAttempts(db, req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/pr-attempts', async (req) => {
    const b = z.object({ attempts: z.array(prAttempt).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO pr_attempts (id, user_id, exercise_id, date, data, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET exercise_id = excluded.exercise_id, date = excluded.date, data = excluded.data, updated_at = excluded.updated_at
       WHERE pr_attempts.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const a of b.attempts) {
        const json = JSON.stringify(a);
        if (json.length > 20_000) throw Object.assign(new Error('Attempt too large'), { statusCode: 413 });
        up.run(a.id, req.userId!, a.exerciseId, a.date, json, ts);
      }
    });
    return { saved: b.attempts.length, serverTime: ts };
  });

  r.delete('/me/pr-attempts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM pr_attempts WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });
};
