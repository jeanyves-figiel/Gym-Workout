import { randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { randomToken, sha256 } from '../crypto.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';

/**
 * Garmin watches (#550). The Connect IQ app talks to this API through the Garmin Connect phone app, so it works with
 * an iPhone. Pairing: the watch asks for a code (`POST /v1/garmin/pair`) and shows it; the member types it in the app
 * (`POST /me/garmin/claim`). The watch then sends its token as `X-Garmin-Token`.
 * The plan is built on the phone, which publishes what the watch shows (`PUT /me/garmin/snapshot`); the watch sends
 * sets, finished workouts and water back as events the phone picks up (`GET /me/garmin/inbox`, then ack).
 */

/** No 0/O, 1/I/L: read off a watch face. */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_MINUTES = 15;
export const MAX_DEVICES = 5;
const MAX_INBOX = 500;

const newCode = () => Array.from({ length: 6 }, () => ALPHABET[randomInt(0, ALPHABET.length)]).join('');

type Device = { id: string; user_id: string | null; code: string | null; code_expires: string | null };

const deviceFor = (db: DB, req: FastifyRequest): Device => {
  const token = req.headers['x-garmin-token'];
  const row =
    typeof token === 'string' && token.length >= 20
      ? (db.prepare('SELECT id, user_id, code, code_expires FROM garmin_devices WHERE token_hash = ?').get(sha256(token)) as Device | undefined)
      : undefined;
  if (!row) throw new ApiError(401, 'invalid_token', 'Unknown Garmin watch.');
  return row;
};

const event = z
  .object({
    id: z.string().min(8).max(64),
    type: z.enum(['set', 'finished', 'water', 'done']),
  })
  .catchall(z.unknown());

/** Watch-facing routes: `X-Garmin-Token`, no bearer token, rate limited. */
export const garminWatchRoutes = (app: FastifyInstance, db: DB, now: () => Date) => {
  const limit = { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } };

  app.post('/v1/garmin/pair', { config: { rateLimit: { max: 5, timeWindow: '1 minute' } } }, async (req) => {
    const b = z.object({ model: z.string().max(60).optional() }).parse(req.body ?? {});
    const token = randomToken(32);
    const t = now();
    const expires = new Date(t.getTime() + CODE_MINUTES * 60_000).toISOString();
    // Old unclaimed watches go, so codes stay free.
    db.prepare('DELETE FROM garmin_devices WHERE user_id IS NULL AND code_expires < ?').run(t.toISOString());
    for (let i = 0; ; i++) {
      const code = newCode();
      try {
        db.prepare('INSERT INTO garmin_devices (id, token_hash, code, code_expires, model, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(
          randomUUID(), sha256(token), code, expires, b.model ?? null, t.toISOString());
        return { token, code, expiresAt: expires };
      } catch (e) {
        if (i >= 5) throw e;
      }
    }
  });

  /** Snapshot once paired; `{ paired: false, code }` while waiting (a fresh code once the old one ran out). */
  app.get('/v1/garmin/snapshot', limit, async (req) => {
    const d = deviceFor(db, req);
    const t = now().toISOString();
    if (!d.user_id) {
      if (!d.code || (d.code_expires ?? '') < t) {
        const code = newCode();
        const expires = new Date(now().getTime() + CODE_MINUTES * 60_000).toISOString();
        db.prepare('UPDATE garmin_devices SET code = ?, code_expires = ? WHERE id = ?').run(code, expires, d.id);
        return { paired: false, code, expiresAt: expires };
      }
      return { paired: false, code: d.code, expiresAt: d.code_expires };
    }
    db.prepare('UPDATE garmin_devices SET last_seen = ? WHERE id = ?').run(t, d.id);
    const s = db.prepare('SELECT data, updated_at FROM garmin_snapshots WHERE user_id = ?').get(d.user_id) as
      | { data: string; updated_at: string }
      | undefined;
    return { paired: true, snapshot: s ? JSON.parse(s.data) : null, updatedAt: s?.updated_at ?? null };
  });

  app.post('/v1/garmin/events', limit, async (req) => {
    const d = deviceFor(db, req);
    if (!d.user_id) throw new ApiError(403, 'not_paired', 'Pair this watch in the app first.');
    const b = z.object({ events: z.array(event).max(50) }).parse(req.body);
    const t = now().toISOString();
    const userId = d.user_id;
    const saved = tx(db, () => {
      const queued = (db.prepare('SELECT COUNT(*) AS n FROM garmin_inbox WHERE user_id = ?').get(userId) as { n: number }).n;
      if (queued + b.events.length > MAX_INBOX) throw new ApiError(429, 'inbox_full', 'Open the app to sync your Garmin workouts.');
      const ins = db.prepare('INSERT OR IGNORE INTO garmin_inbox (id, user_id, device_id, data, created_at) VALUES (?, ?, ?, ?, ?)');
      let n = 0;
      for (const e of b.events) {
        const json = JSON.stringify(e);
        if (json.length > 8_000) throw Object.assign(new Error('Event too large'), { statusCode: 413 });
        n += Number(ins.run(`${d.id}:${e.id}`, userId, d.id, json, t).changes);
      }
      return n;
    });
    db.prepare('UPDATE garmin_devices SET last_seen = ? WHERE id = ?').run(t, d.id);
    return { saved, serverTime: t };
  });
};

/** Member routes (bearer token). */
export const garminRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.post('/me/garmin/claim', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req) => {
    const b = z.object({ code: z.string().trim().min(4).max(12) }).parse(req.body);
    const code = b.code.toUpperCase().replace(/[^A-Z0-9]/g, '');
    const t = now().toISOString();
    const d = db.prepare('SELECT id, model FROM garmin_devices WHERE code = ? AND user_id IS NULL AND code_expires >= ?').get(code, t) as
      | { id: string; model: string | null }
      | undefined;
    if (!d) throw new ApiError(404, 'unknown_code', 'That code is wrong or ran out. Open MonkeyWorkout on the watch for a new one.');
    const count = (db.prepare('SELECT COUNT(*) AS n FROM garmin_devices WHERE user_id = ?').get(req.userId!) as { n: number }).n;
    if (count >= MAX_DEVICES) throw new ApiError(409, 'too_many_devices', `Up to ${MAX_DEVICES} Garmin watches. Remove one first.`);
    db.prepare('UPDATE garmin_devices SET user_id = ?, code = NULL, code_expires = NULL, last_seen = ? WHERE id = ?').run(req.userId!, t, d.id);
    return { id: d.id, model: d.model, pairedAt: t };
  });

  r.get('/me/garmin/devices', async (req) => ({
    devices: (
      db.prepare('SELECT id, model, created_at, last_seen FROM garmin_devices WHERE user_id = ? ORDER BY created_at').all(req.userId!) as {
        id: string;
        model: string | null;
        created_at: string;
        last_seen: string | null;
      }[]
    ).map((d) => ({ id: d.id, model: d.model, pairedAt: d.created_at, lastSeen: d.last_seen })),
  }));

  r.delete('/me/garmin/devices/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM garmin_devices WHERE id = ? AND user_id = ?').run(id, req.userId!);
      db.prepare('DELETE FROM garmin_inbox WHERE device_id = ? AND user_id = ?').run(id, req.userId!);
    });
    return reply.status(204).send();
  });

  r.put('/me/garmin/snapshot', async (req) => {
    const b = z.object({ snapshot: z.record(z.string(), z.unknown()) }).parse(req.body);
    const json = JSON.stringify(b.snapshot);
    if (json.length > 32_000) throw Object.assign(new Error('Snapshot too large'), { statusCode: 413 });
    const t = now().toISOString();
    db.prepare(
      `INSERT INTO garmin_snapshots (user_id, data, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
    ).run(req.userId!, json, t);
    return { updatedAt: t };
  });

  r.get('/me/garmin/inbox', async (req) => ({
    events: (
      db.prepare('SELECT id, data, created_at FROM garmin_inbox WHERE user_id = ? ORDER BY created_at, rowid LIMIT 200').all(req.userId!) as {
        id: string;
        data: string;
        created_at: string;
      }[]
    ).map((e) => ({ ...(JSON.parse(e.data) as object), id: e.id, receivedAt: e.created_at })),
  }));

  r.post('/me/garmin/inbox/ack', async (req) => {
    const b = z.object({ ids: z.array(z.string().max(120)).max(200) }).parse(req.body);
    const del = db.prepare('DELETE FROM garmin_inbox WHERE id = ? AND user_id = ?');
    const removed = tx(db, () => b.ids.reduce((n, id) => n + Number(del.run(id, req.userId!).changes), 0));
    return { removed };
  });
};
