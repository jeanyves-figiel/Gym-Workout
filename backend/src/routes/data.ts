import { Readable } from 'node:stream';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type AuthService, publicUser } from '../auth.ts';
import { type DB, tx } from '../db.ts';
import {
  baseUpdatedAt,
  conflictsField,
  opaqueCopy,
  reviveUploaded,
  recordTombstone,
  sendPull,
  type SyncTable,
  syncId,
  syncIdParams,
  takeConflicts,
  timeOrderedRows,
} from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';
import { ApiError } from '../errors.ts';
import { HOUR, throttleTake } from '../throttle.ts';
import { pushExport } from '../push/schema.ts';
import { refreshMemberGym } from '../community/schema.ts';
import { communityExport } from './community.ts';
import { referralExport } from './referrals.ts';
import { householdExport } from './household.ts';
import { programExport } from './programs.ts';
import { liveExport } from './live.ts';
import { gymExport, gymMapExport } from './gyms.ts';
import { customExerciseTable } from './customExercises.ts';
import { customWorkoutTable } from './customWorkouts.ts';
import { bodyMeasurementTable } from './bodyMeasurements.ts';
import { climbTable } from './climbs.ts';
import { sportTable } from './sports.ts';
import { machineNoteExport } from './machineNotes.ts';
import { reportExport } from './reports.ts';
import { prAttemptTable } from './prAttempts.ts';
import { accountExport } from './accountExport.ts';

const logEntry = z.object({
  id: syncId,
  baseUpdatedAt,
  date: z.iso.datetime({ offset: true }),
  exerciseId: z.string().min(1).max(128),
  /** Plan-insert ids are `custom-<uuid>~plan-<uuid>` (85 chars), so leave room. */
  sessionId: z.string().max(200).nullish(),
  weightKg: z.number().min(0).max(1000).nullish(),
  /** Lowering (eccentric) load when the machine sets it apart from the push (#792); weightKg is then the push. */
  lowerKg: z.number().min(0).max(1000).nullish(),
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
  lower_kg: number | null;
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
  lowerKg: r.lower_kg,
  reps: r.reps,
  setIndex: r.set_index,
  rir: r.rir,
  updatedAt: r.updated_at,
});

const logTable: SyncTable<LogRow> = { table: 'workout_logs', cols: '*', timeCol: 'date', map: toLog };

/** Completed workout sessions: opaque app records; one is at most WORKOUT_MAX_BYTES (#712: was 100 KB). */
const WORKOUT_MAX_BYTES = 64_000;
const workoutTable: SyncTable<{ data: string; updated_at: string }> = { table: 'workouts', cols: 'data, updated_at', timeCol: 'started_at', map: opaqueCopy };

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
    assertItemSize(json, 200_000, 'Profile');
    const ts = now().toISOString();
    db.prepare(
      'INSERT INTO profiles (user_id, data, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at',
    ).run(req.userId!, json, ts);
    // Member search reads the gym from the community profile (#715).
    refreshMemberGym(db, req.userId!);
    return { updatedAt: ts };
  });

  r.get('/me/logs', async (req, reply) => sendPull(reply, db, logTable, { key: 'logs', kind: 'logs', userId: req.userId!, query: req.query, now }));

  r.post('/me/logs', async (req) => {
    const b = z.object({ logs: z.array(logEntry).max(500) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO workout_logs (id, user_id, date, exercise_id, session_id, weight_kg, lower_kg, reps, set_index, rir, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET date = excluded.date, exercise_id = excluded.exercise_id, session_id = excluded.session_id,
         weight_kg = excluded.weight_kg, lower_kg = excluded.lower_kg, reps = excluded.reps, set_index = excluded.set_index, rir = excluded.rir,
         updated_at = excluded.updated_at
       WHERE workout_logs.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'workout_logs', req.userId!, b.logs, toLog);
      const logs = reviveUploaded(db, req.userId!, 'logs', fresh);
      assertRowQuota(db, 'workout_logs', req.userId!, logs.map((l) => l.id));
      let count = 0;
      for (const l of logs) count += Number(up.run(
          l.id, req.userId!, l.date, l.exerciseId, l.sessionId ?? null, l.weightKg ?? null, l.lowerKg ?? null, l.reps ?? null,
          l.setIndex ?? null, l.rir ?? null, ts,
        ).changes);
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/logs/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM workout_logs WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'logs', id, now().toISOString());
    });
    return reply.status(204).send();
  });

  // ───────────── completed workout sessions (opaque app-defined records)
  const workout = z
    .object({ id: syncId, baseUpdatedAt, startedAt: z.iso.datetime({ offset: true }) })
    .catchall(z.unknown());

  r.get('/me/workouts', async (req, reply) =>
    sendPull(reply, db, workoutTable, { key: 'workouts', kind: 'workouts', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/workouts', async (req) => {
    const b = z.object({ workouts: z.array(workout).max(100) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET started_at = excluded.started_at, data = excluded.data, updated_at = excluded.updated_at
       WHERE workouts.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'workouts', req.userId!, b.workouts, opaqueCopy);
      const workouts = reviveUploaded(db, req.userId!, 'workouts', fresh);
      const jsons = workouts.map((w) => JSON.stringify(w));
      for (const j of jsons) assertItemSize(j, WORKOUT_MAX_BYTES, 'Workout');
      assertRowQuota(db, 'workouts', req.userId!, workouts.map((w) => w.id));
      assertByteQuota(db, 'workouts', req.userId!, workouts.map((w, i) => ({ id: w.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      workouts.forEach((w, i) => (count += Number(up.run(w.id, req.userId!, w.startedAt, jsons[i]!, ts).changes)));
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/workouts/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'workouts', id, now().toISOString());
    });
    return reply.status(204).send();
  });

  // Lazily built sections, serialised one at a time: photos in custom exercises and community posts can make
  // the whole document large, so it never sits in memory as one object plus one string. `rows` sections are lists
  // serialised item by item as they are read (#712).
  const rows = (gen: () => Iterable<unknown>) => Object.assign(gen, { rows: true as const });
  const exportSections = (userId: string): [string, (() => unknown) & { rows?: true }][] => [
    ['exportedAt', () => now().toISOString()],
    ['user', () => publicUser(auth.userById(userId)!)],
    ['profile', () => getProfile(userId)],
    ['logs', rows(() => timeOrderedRows(db, logTable, userId))],
    ['workouts', rows(() => timeOrderedRows(db, workoutTable, userId))],
    ['customWorkouts', rows(() => timeOrderedRows(db, customWorkoutTable, userId))],
    ['community', () => communityExport(db, userId)],
    ['live', () => liveExport(db, userId)],
    ['referrals', () => referralExport(db, userId)],
    ['fuelSharing', () => householdExport(db, userId)],
    ['programs', () => programExport(db, userId)],
    ['customExercises', rows(() => timeOrderedRows(db, customExerciseTable, userId))],
    ['prAttempts', rows(() => timeOrderedRows(db, prAttemptTable, userId))],
    ['climbs', rows(() => timeOrderedRows(db, climbTable, userId))],
    ['sports', rows(() => timeOrderedRows(db, sportTable, userId))],
    ['machineNotes', rows(() => machineNoteExport(db, userId))],
    ['problemReports', () => reportExport(db, userId)],
    ['bodyMeasurements', rows(() => timeOrderedRows(db, bodyMeasurementTable, userId))],
    ['gyms', () => gymExport(db, userId)],
    ['gymMap', () => gymMapExport(db, userId)],
    ['notifications', () => pushExport(db, userId)],
    ['subscriptions', () => subscriptions?.(userId)],
    ['sessions', () => auth.sessions(userId)],
    ...accountExport(db, userId),
  ];

  r.get('/me/export', async (req, reply) => {
    if (!throttleTake(db, `export:${req.userId!}`, EXPORTS_PER_HOUR, HOUR, now()))
      throw new ApiError(429, 'rate_limited', 'You just exported your data. Try again in an hour.');
    const sections = exportSections(req.userId!);
    // Same bytes as JSON.stringify of the whole object: undefined members are left out.
    async function* body() {
      let first = true;
      for (const [key, build] of sections) {
        if (build.rows) {
          yield `${first ? '{' : ','}${JSON.stringify(key)}:[`;
          first = false;
          let buf = '';
          let n = 0;
          for (const item of build() as Iterable<unknown>) {
            buf += (n++ ? ',' : '') + JSON.stringify(item);
            if (buf.length >= 64_000) {
              yield buf;
              buf = '';
            }
          }
          yield `${buf}]`;
          continue;
        }
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
