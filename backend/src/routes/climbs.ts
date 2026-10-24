import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, opaqueCopy, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts } from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';

/** Climbing sessions (#312): were kept only on the device; now synced like PR attempts (upsert by client id). */
const climb = z
  .object({
    id: syncId,
    baseUpdatedAt,
    start: z.iso.datetime({ offset: true }),
    minutes: z.number().int().min(0).max(24 * 60),
    effort: z.number().int().min(1).max(10),
    kind: z.string().min(1).max(32),
    topGrade: z.string().max(32).nullish(),
    notes: z.string().max(2000).nullish(),
  })
  .catchall(z.unknown());

export const climbTable: SyncTable<{ data: string; updated_at: string }> = { table: 'climbs', cols: 'data, updated_at', timeCol: 'start', map: opaqueCopy };

export const climbRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/climbs', async (req, reply) => sendPull(reply, db, climbTable, { key: 'climbs', kind: 'climbs', userId: req.userId!, query: req.query, now }));

  r.post('/me/climbs', async (req) => {
    const b = z.object({ climbs: z.array(climb).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO climbs (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET start = excluded.start, data = excluded.data, updated_at = excluded.updated_at
       WHERE climbs.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'climbs', req.userId!, b.climbs, opaqueCopy);
      const climbs = reviveUploaded(db, req.userId!, 'climbs', fresh);
      const jsons = climbs.map((c) => JSON.stringify(c));
      for (const j of jsons) assertItemSize(j, 10_000, 'Climb');
      assertRowQuota(db, 'climbs', req.userId!, climbs.map((c) => c.id));
      assertByteQuota(db, 'climbs', req.userId!, climbs.map((c, i) => ({ id: c.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      climbs.forEach((c, i) => (count += Number(up.run(c.id, req.userId!, c.start, jsons[i]!, ts).changes)));
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/climbs/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM climbs WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'climbs', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};
