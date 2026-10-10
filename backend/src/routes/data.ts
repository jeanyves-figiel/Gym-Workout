import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type AuthService, publicUser } from '../auth.ts';
import { type DB, tx } from '../db.ts';
import { listCustomWorkouts } from './customWorkouts.ts';
import { listPrAttempts } from './prAttempts.ts';

const logEntry = z.object({
  id: z.uuid(),
  date: z.iso.datetime({ offset: true }),
  exerciseId: z.string().min(1).max(64),
  sessionId: z.string().max(64).nullish(),
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

/** Profile (opaque JSON owned by the app) + workout log sync + export. */
export const dataRoutes = (r: FastifyInstance, db: DB, now: () => Date, auth: AuthService) => {
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
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    const rows = (
      q.since
        ? db.prepare('SELECT * FROM workout_logs WHERE user_id = ? AND updated_at > ? ORDER BY updated_at').all(req.userId!, q.since)
        : db.prepare('SELECT * FROM workout_logs WHERE user_id = ? ORDER BY updated_at').all(req.userId!)
    ) as unknown as LogRow[];
    return { logs: rows.map(toLog), serverTime: now().toISOString() };
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
    tx(db, () => {
      for (const l of b.logs) up.run(
          l.id, req.userId!, l.date, l.exerciseId, l.sessionId ?? null, l.weightKg ?? null, l.reps ?? null,
          l.setIndex ?? null, l.rir ?? null, ts,
        );
    });
    return { saved: b.logs.length, serverTime: ts };
  });

  r.delete('/me/logs/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM workout_logs WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });

  // ───────────── completed workout sessions (opaque app-defined records)
  const workout = z
    .object({ id: z.uuid(), startedAt: z.iso.datetime({ offset: true }) })
    .catchall(z.unknown());

  const listWorkouts = (userId: string, since?: string) =>
    (
      (since
        ? db.prepare('SELECT data, updated_at FROM workouts WHERE user_id = ? AND updated_at > ? ORDER BY started_at').all(userId, since)
        : db.prepare('SELECT data, updated_at FROM workouts WHERE user_id = ? ORDER BY started_at').all(userId)) as unknown as {
        data: string;
        updated_at: string;
      }[]
    ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

  r.get('/me/workouts', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { workouts: listWorkouts(req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/workouts', async (req) => {
    const b = z.object({ workouts: z.array(workout).max(100) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET started_at = excluded.started_at, data = excluded.data, updated_at = excluded.updated_at
       WHERE workouts.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const w of b.workouts) {
        const json = JSON.stringify(w);
        if (json.length > 100_000) throw Object.assign(new Error('Workout too large'), { statusCode: 413 });
        up.run(w.id, req.userId!, w.startedAt, json, ts);
      }
    });
    return { saved: b.workouts.length, serverTime: ts };
  });

  r.delete('/me/workouts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });

  r.get('/me/export', async (req, reply) => {
    const logs = (db.prepare('SELECT * FROM workout_logs WHERE user_id = ? ORDER BY date').all(req.userId!) as unknown as LogRow[]).map(toLog);
    reply.header('Content-Disposition', 'attachment; filename="gym-workout-export.json"');
    return {
      exportedAt: now().toISOString(),
      user: publicUser(auth.userById(req.userId!)!),
      profile: getProfile(req.userId!),
      logs,
      workouts: listWorkouts(req.userId!),
      customWorkouts: listCustomWorkouts(db, req.userId!),
      prAttempts: listPrAttempts(db, req.userId!),
      sessions: auth.sessions(req.userId!),
    };
  });
};
