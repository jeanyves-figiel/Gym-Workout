import { Readable } from 'node:stream';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type AuthService, publicUser } from '../auth.ts';
import { type DB, tx } from '../db.ts';
import { deletedField, reviveUploaded, recordTombstone, sinceQuery } from './sync.ts';
import { assertRowQuota } from '../quota.ts';
import { ApiError } from '../errors.ts';
import { HOUR, throttleTake } from '../throttle.ts';
import { pushExport } from '../push/schema.ts';
import { communityExport } from './community.ts';
import { gymExport, gymMapExport } from './gyms.ts';
import { listCustomExercises } from './customExercises.ts';
import { listCustomWorkouts } from './customWorkouts.ts';
import { listBodyMeasurements } from './bodyMeasurements.ts';
import { listClimbs } from './climbs.ts';
import { listSports } from './sports.ts';
import { machineNoteExport } from './machineNotes.ts';
import { reportExport } from './reports.ts';
import { listPrAttempts } from './prAttempts.ts';

const logEntry = z.object({
  id: z.uuid(),
  date: z.iso.datetime({ offset: true }),
  exerciseId: z.string().min(1).max(128),
  /** Plan-insert ids are `custom-<uuid>~plan-<uuid>` (85 chars), so leave room. */
  sessionId: z.string().max(200).nullish(),
  weightKg: z.number().min(0).max(1000).nullish(),
  reps: z.number().int().min(0).max(1000).nullish(),
  /** 0-based set number within the session (per-set logging); absent for legacy one-weight logs. */
  setIndex: z.number().int().min(0).max(99).nullish(),
  /** Reps in reserve. */
  rir: z.number().int().min(0).max(10).nullish(),
});

interface LogRow {
  id: string;
  date: string;
  exercise_id: string;
  session_id: string | null;
  weight_kg: number | null;
  reps: number | null;
  set_index: number | null;
  rir: number | null;
  updated_at: string;
}

const toLog = (r: LogRow) => ({
  id: r.id,
  date: r.date,
  exerciseId: r.exercise_id,
  sessionId: r.session_id,
  weightKg: r.weight_kg,
  reps: r.reps,
  setIndex: r.set_index,
  rir: r.rir,
  updatedAt: r.updated_at,
});

/** Full data exports per member per hour: each one reads every row the member has. */
const EXPORTS_PER_HOUR = 3;

/** Profile (opaque JSON owned by the app) + workout log sync + export. */
export const dataRoutes = (r: FastifyInstance, db: DB, now: () => Date, auth: AuthService, subscriptions?: (userId: string) => unknown) => {
  const getProfile = (userId: string) => {
    const row = db.prepare('SELECT data, updated_at FROM profiles WHERE user_id = ?').get(userId) as
      | { data: string; updated_at: string }
      | undefined;
    return row ? { data: JSON.parse(row.data) as unknown, updatedAt: row.updated_at } : { data: null, updatedAt: null };
  };

  r.get('/me/profile', async (req) => getProfile(req.userId!));

  r.put('/me/profile', async (req) => {
    const b = z.object({ data: z.record(z.string(), z.unknown()) }).parse(req.body);
    const json = JSON.stringify(b.data);
    if (json.length > 200_000) throw Object.assign(new Error('Profile too large'), { statusCode: 413 });
    const ts = now().toISOString();
    db.prepare(
      'INSERT INTO profiles (user_id, data, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at',
    ).run(req.userId!, json, ts);
    return { updatedAt: ts };
  });

  r.get('/me/logs', async (req) => {
    const q = sinceQuery.parse(req.query);
    const rows = (
      q.since
        ? db.prepare('SELECT * FROM workout_logs WHERE user_id = ? AND updated_at >= ? ORDER BY updated_at').all(req.userId!, q.since)
        : db.prepare('SELECT * FROM workout_logs WHERE user_id = ? ORDER BY updated_at').all(req.userId!)
    ) as unknown as LogRow[];
    return { logs: rows.map(toLog), ...deletedField(db, req.userId!, 'logs', q.since), serverTime: now().toISOString() };
  });

  r.post('/me/logs', async (req) => {
    const b = z.object({ logs: z.array(logEntry).max(500) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO workout_logs (id, user_id, date, exercise_id, session_id, weight_kg, reps, set_index, rir, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET date = excluded.date, exercise_id = excluded.exercise_id, session_id = excluded.session_id,
         weight_kg = excluded.weight_kg, reps = excluded.reps, set_index = excluded.set_index, rir = excluded.rir,
         updated_at = excluded.updated_at
       WHERE workout_logs.user_id = excluded.user_id`,
    );
    const saved = tx(db, () => {
      const logs = reviveUploaded(db, req.userId!, 'logs', b.logs);
      assertRowQuota(db, 'workout_logs', req.userId!, logs.map((l) => l.id));
      let count = 0;
      for (const l of logs) count += Number(up.run(
          l.id, req.userId!, l.date, l.exerciseId, l.sessionId ?? null, l.weightKg ?? null, l.reps ?? null,
          l.setIndex ?? null, l.rir ?? null, ts,
        ).changes);
      return count;
    });
    return { saved, serverTime: ts };
  });

  r.delete('/me/logs/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM workout_logs WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'logs', id, now().toISOString());
    });
    return reply.status(204).send();
  });

  // ───────────── completed workout sessions (opaque app-defined records)
  const workout = z
    .object({ id: z.uuid(), startedAt: z.iso.datetime({ offset: true }) })
    .catchall(z.unknown());

  const listWorkouts = (userId: string, since?: string) =>
    (
      (since
        ? db.prepare('SELECT data, updated_at FROM workouts WHERE user_id = ? AND updated_at >= ? ORDER BY started_at').all(userId, since)
        : db.prepare('SELECT data, updated_at FROM workouts WHERE user_id = ? ORDER BY started_at').all(userId)) as unknown as {
        data: string;
        updated_at: string;
      }[]
    ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

  r.get('/me/workouts', async (req) => {
    const q = sinceQuery.parse(req.query);
    return { workouts: listWorkouts(req.userId!, q.since), ...deletedField(db, req.userId!, 'workouts', q.since), serverTime: now().toISOString() };
  });

  r.post('/me/workouts', async (req) => {
    const b = z.object({ workouts: z.array(workout).max(100) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET started_at = excluded.started_at, data = excluded.data, updated_at = excluded.updated_at
       WHERE workouts.user_id = excluded.user_id`,
    );
    const saved = tx(db, () => {
      const workouts = reviveUploaded(db, req.userId!, 'workouts', b.workouts);
      assertRowQuota(db, 'workouts', req.userId!, workouts.map((w) => w.id));
      let count = 0;
      for (const w of workouts) {
        const json = JSON.stringify(w);
        if (json.length > 100_000) throw Object.assign(new Error('Workout too large'), { statusCode: 413 });
        count += Number(up.run(w.id, req.userId!, w.startedAt, json, ts).changes);
      }
      return count;
    });
    return { saved, serverTime: ts };
  });

  r.delete('/me/workouts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'workouts', id, now().toISOString());
    });
    return reply.status(204).send();
  });

  // Lazily built sections, serialised one at a time: photos in custom exercises and community posts can make
  // the whole document large, so it never sits in memory as one object plus one string.
  const exportSections = (userId: string): [string, () => unknown][] => [
    ['exportedAt', () => now().toISOString()],
    ['user', () => publicUser(auth.userById(userId)!)],
    ['profile', () => getProfile(userId)],
    ['logs', () => (db.prepare('SELECT * FROM workout_logs WHERE user_id = ? ORDER BY date').all(userId) as unknown as LogRow[]).map(toLog)],
    ['workouts', () => listWorkouts(userId)],
    ['customWorkouts', () => listCustomWorkouts(db, userId)],
    ['community', () => communityExport(db, userId)],
    ['customExercises', () => listCustomExercises(db, userId)],
    ['prAttempts', () => listPrAttempts(db, userId)],
    ['climbs', () => listClimbs(db, userId)],
    ['sports', () => listSports(db, userId)],
    ['machineNotes', () => machineNoteExport(db, userId)],
    ['problemReports', () => reportExport(db, userId)],
    ['bodyMeasurements', () => listBodyMeasurements(db, userId)],
    ['gyms', () => gymExport(db, userId)],
    ['gymMap', () => gymMapExport(db, userId)],
    ['notifications', () => pushExport(db, userId)],
    ['subscriptions', () => subscriptions?.(userId)],
    ['sessions', () => auth.sessions(userId)],
  ];

  r.get('/me/export', async (req, reply) => {
    if (!throttleTake(db, `export:${req.userId!}`, EXPORTS_PER_HOUR, HOUR, now()))
      throw new ApiError(429, 'rate_limited', 'You just exported your data. Try again in an hour.');
    const sections = exportSections(req.userId!);
    // Same bytes as JSON.stringify of the whole object: undefined members are left out.
    async function* body() {
      let first = true;
      for (const [key, build] of sections) {
        const json = JSON.stringify(build());
        if (json === undefined) continue;
        yield `${first ? '{' : ','}${JSON.stringify(key)}:${json}`;
        first = false;
      }
      yield first ? '{}' : '}';
    }
    reply.header('Content-Disposition', 'attachment; filename="gym-workout-export.json"');
    reply.type('application/json; charset=utf-8');
    return reply.send(Readable.from(body()));
  });
};
