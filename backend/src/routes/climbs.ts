import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';
import { deletedField, reviveUploaded, recordTombstone, sinceQuery } from './sync.ts';
import { assertRowQuota } from '../quota.ts';

/** Climbing sessions (#312): were kept only on the device; now synced like PR attempts (upsert by client id). */
const climb = z
  .object({
    id: z.uuid(),
    start: z.iso.datetime({ offset: true }),
    minutes: z.number().int().min(0).max(24 * 60),
    effort: z.number().int().min(1).max(10),
    kind: z.string().min(1).max(32),
    topGrade: z.string().max(32).nullish(),
    notes: z.string().max(2000).nullish(),
  })
  .catchall(z.unknown());

export const listClimbs = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM climbs WHERE user_id = ? AND updated_at >= ? ORDER BY start').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM climbs WHERE user_id = ? ORDER BY start').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const climbRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/climbs', async (req) => {
    const q = sinceQuery.parse(req.query);
    return { climbs: listClimbs(db, req.userId!, q.since), ...deletedField(db, req.userId!, 'climbs', q.since), serverTime: now().toISOString() };
  });

  r.post('/me/climbs', async (req) => {
    const b = z.object({ climbs: z.array(climb).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO climbs (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET start = excluded.start, data = excluded.data, updated_at = excluded.updated_at
       WHERE climbs.user_id = excluded.user_id`,
    );
    const saved = tx(db, () => {
      const climbs = reviveUploaded(db, req.userId!, 'climbs', b.climbs);
      assertRowQuota(db, 'climbs', req.userId!, climbs.map((c) => c.id));
      let count = 0;
      for (const c of climbs) {
        const json = JSON.stringify(c);
        if (json.length > 10_000) throw Object.assign(new Error('Climb too large'), { statusCode: 413 });
        count += Number(up.run(c.id, req.userId!, c.start, json, ts).changes);
      }
      return count;
    });
    return { saved, serverTime: ts };
  });

  r.delete('/me/climbs/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM climbs WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'climbs', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};
