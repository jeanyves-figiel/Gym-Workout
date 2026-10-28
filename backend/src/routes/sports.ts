import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { randomToken, sha256 } from '../crypto.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import { baseUpdatedAt, conflictsField, opaqueCopy, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts } from './sync.ts';
import { sessionPlace } from './climbs.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';

/** Other sport sessions (#416): snowboard, MTB, Hyrox… Synced like climbs (upsert by client id). */
const sport = z
  .object({
    id: syncId,
    baseUpdatedAt,
    start: z.iso.datetime({ offset: true }),
    minutes: z.number().int().min(0).max(24 * 60),
    effort: z.number().int().min(1).max(10),
    sport: z.string().min(1).max(32),
    notes: z.string().max(2000).nullish(),
    place: sessionPlace.nullish(),
  })
  .catchall(z.unknown());

const upsert = (db: DB, userId: string, upload: z.infer<typeof sport>[], ts: string) => {
  const up = db.prepare(
    `INSERT INTO sports (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET start = excluded.start, data = excluded.data, updated_at = excluded.updated_at
     WHERE sports.user_id = excluded.user_id`,
  );
  /** Rows written (another account's ids are skipped by the WHERE) and conflicts (see `takeConflicts`). */
  return tx(db, () => {
    const { fresh, conflicts } = takeConflicts(db, 'sports', userId, upload, opaqueCopy);
    const sports = reviveUploaded(db, userId, 'sports', fresh);
    const jsons = sports.map((c) => JSON.stringify(c));
    for (const j of jsons) assertItemSize(j, 10_000, 'Sport session');
    assertRowQuota(db, 'sports', userId, sports.map((c) => c.id));
    assertByteQuota(db, 'sports', userId, sports.map((c, i) => ({ id: c.id, bytes: Buffer.byteLength(jsons[i]!) })));
    let count = 0;
    sports.forEach((c, i) => (count += Number(up.run(c.id, userId, c.start, jsons[i]!, ts).changes)));
    return { saved: count, conflicts };
  });
};

export const sportTable: SyncTable<{ data: string; updated_at: string }> = { table: 'sports', cols: 'data, updated_at', timeCol: 'start', map: opaqueCopy };

export const sportRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/sports', async (req, reply) => sendPull(reply, db, sportTable, { key: 'sports', kind: 'sports', userId: req.userId!, query: req.query, now }));

  r.post('/me/sports', async (req) => {
    const b = z.object({ sports: z.array(sport).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const { saved, conflicts } = upsert(db, req.userId!, b.sports, ts);
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  // Upload-only key for the member's Apple Watch (#426): a Hyrox race goes straight to the server when the Watch has
  // Wi-Fi or cellular. One per account; a new one replaces the old. Only `POST /v1/watch/sports` accepts it.
  r.post('/me/watch-key', async (req) => {
    const key = randomToken(32);
    db.prepare(
      `INSERT INTO watch_keys (user_id, key_hash, created_at) VALUES (?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET key_hash = excluded.key_hash, created_at = excluded.created_at`,
    ).run(req.userId!, sha256(key), now().toISOString());
    return { key };
  });

  r.delete('/me/sports/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM sports WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'sports', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};

/** The Watch's direct upload (#426): `X-Watch-Key` instead of a bearer token, sport sessions only, rate limited. */
export const watchSportRoutes = (app: FastifyInstance, db: DB, now: () => Date) => {
  app.post('/v1/watch/sports', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req) => {
    const key = req.headers['x-watch-key'];
    const row =
      typeof key === 'string' && key.length >= 20
        ? (db.prepare('SELECT user_id FROM watch_keys WHERE key_hash = ?').get(sha256(key)) as { user_id: string } | undefined)
        : undefined;
    if (!row) throw new ApiError(401, 'invalid_token', 'Unknown Watch key.');
    const b = z.object({ sports: z.array(sport).max(10) }).parse(req.body);
    const ts = now().toISOString();
    return { saved: upsert(db, row.user_id, b.sports, ts).saved, serverTime: ts };
  });
};
