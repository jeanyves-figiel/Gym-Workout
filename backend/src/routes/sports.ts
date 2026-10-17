import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';

/** Other sport sessions (#416): snowboard, MTB, Hyrox… Synced like climbs (upsert by client id). */
const sport = z
  .object({
    id: z.uuid(),
    start: z.iso.datetime({ offset: true }),
    minutes: z.number().int().min(0).max(24 * 60),
    effort: z.number().int().min(1).max(10),
    sport: z.string().min(1).max(32),
    notes: z.string().max(2000).nullish(),
  })
  .catchall(z.unknown());

export const listSports = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM sports WHERE user_id = ? AND updated_at > ? ORDER BY start').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM sports WHERE user_id = ? ORDER BY start').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const sportRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/sports', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { sports: listSports(db, req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/sports', async (req) => {
    const b = z.object({ sports: z.array(sport).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO sports (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET start = excluded.start, data = excluded.data, updated_at = excluded.updated_at
       WHERE sports.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const c of b.sports) {
        const json = JSON.stringify(c);
        if (json.length > 10_000) throw Object.assign(new Error('Sport session too large'), { statusCode: 413 });
        up.run(c.id, req.userId!, c.start, json, ts);
      }
    });
    return { saved: b.sports.length, serverTime: ts };
  });

  r.delete('/me/sports/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM sports WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });
};
