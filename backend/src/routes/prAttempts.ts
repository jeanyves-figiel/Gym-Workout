import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, opaqueCopy, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts } from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';

/** Personal-record attempts (#60): app-defined records; the typed fields are what a future community feed reads. */
const prAttempt = z
  .object({
    id: syncId,
    baseUpdatedAt,
    exerciseId: z.string().min(1).max(128),
    date: z.iso.datetime({ offset: true }),
    kind: z.enum(['oneRepMax', 'repMax', 'maxReps']),
    kg: z.number().min(0).max(1000),
    reps: z.number().int().min(0).max(1000),
    success: z.boolean(),
    isRecord: z.boolean().optional(),
  })
  .catchall(z.unknown());

export const prAttemptTable: SyncTable<{ data: string; updated_at: string }> = { table: 'pr_attempts', cols: 'data, updated_at', timeCol: 'date', map: opaqueCopy };

export const prAttemptRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/pr-attempts', async (req, reply) =>
    sendPull(reply, db, prAttemptTable, { key: 'attempts', kind: 'pr-attempts', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/pr-attempts', async (req) => {
    const b = z.object({ attempts: z.array(prAttempt).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO pr_attempts (id, user_id, exercise_id, date, data, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET exercise_id = excluded.exercise_id, date = excluded.date, data = excluded.data, updated_at = excluded.updated_at
       WHERE pr_attempts.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'pr_attempts', req.userId!, b.attempts, opaqueCopy);
      const attempts = reviveUploaded(db, req.userId!, 'pr-attempts', fresh);
      const jsons = attempts.map((a) => JSON.stringify(a));
      for (const j of jsons) assertItemSize(j, 20_000, 'Attempt');
      assertRowQuota(db, 'pr_attempts', req.userId!, attempts.map((a) => a.id));
      assertByteQuota(db, 'pr_attempts', req.userId!, attempts.map((a, i) => ({ id: a.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      attempts.forEach((a, i) => (count += Number(up.run(a.id, req.userId!, a.exerciseId, a.date, jsons[i]!, ts).changes)));
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/pr-attempts/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM pr_attempts WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'pr-attempts', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};
