import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type AuthService, publicUser } from '../auth.ts';
import { type DB, tx } from '../db.ts';

const logEntry = z.object({
  id: z.uuid(),
  date: z.iso.datetime({ offset: true }),
  exerciseId: z.string().min(1).max(64),
  sessionId: z.string().max(64).nullish(),
  weightKg: z.number().min(0).max(1000).nullish(),
  reps: z.number().int().min(0).max(1000).nullish(),
});

interface LogRow {
  id: string;
  date: string;
  exercise_id: string;
  session_id: string | null;
  weight_kg: number | null;
  reps: number | null;
  updated_at: string;
}

const toLog = (r: LogRow) => ({
  id: r.id,
  date: r.date,
  exerciseId: r.exercise_id,
  sessionId: r.session_id,
  weightKg: r.weight_kg,
  reps: r.reps,
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
      `INSERT INTO workout_logs (id, user_id, date, exercise_id, session_id, weight_kg, reps, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET date = excluded.date, exercise_id = excluded.exercise_id, session_id = excluded.session_id,
         weight_kg = excluded.weight_kg, reps = excluded.reps, updated_at = excluded.updated_at
       WHERE workout_logs.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const l of b.logs) up.run(l.id, req.userId!, l.date, l.exerciseId, l.sessionId ?? null, l.weightKg ?? null, l.reps ?? null, ts);
    });
    return { saved: b.logs.length, serverTime: ts };
  });

  r.delete('/me/logs/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM workout_logs WHERE id = ? AND user_id = ?').run(id, req.userId!);
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
      sessions: auth.sessions(req.userId!),
    };
  });
};
