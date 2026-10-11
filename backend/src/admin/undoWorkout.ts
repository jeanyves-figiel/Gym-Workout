import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { type DB, tx } from '../db.ts';

/**
 * Ops: remove one recorded workout from a user's account as if it never happened (e.g. ended by mistake).
 * Same scope as the app's Undo workout (#133): the workout record, the sets logged during it (same session,
 * from its start until its end + 6 h, never into a later workout of that session), PR attempts made during it,
 * and its community posts (reactions cascade). Lists candidates in a time window; deletes only with an exact id
 * and `apply`, after writing a JSON backup of every row next to the database. Run via the "Fly undo workout" workflow.
 */
export interface UndoInput {
  email: string;
  /** ISO window: workouts that started, ended or were saved in it are candidates. */
  from: string;
  to: string;
  workoutId?: string;
  apply?: boolean;
}

type Row = Record<string, unknown>;

export interface Candidate {
  workout: Row;
  title: unknown;
  startedAt: string;
  endedAt: string;
  totalSets: number;
  logs: Row[];
  prAttempts: Row[];
  posts: Row[];
  reactions: Row[];
}

const ms = (s: unknown) => new Date(String(s)).getTime();

export const findCandidates = (db: DB, input: UndoInput) => {
  const user = db.prepare('SELECT id, email FROM users WHERE email = ? COLLATE NOCASE').get(input.email) as
    | { id: string; email: string }
    | undefined;
  if (!user) throw new Error('user not found');
  const from = ms(input.from);
  const to = ms(input.to);
  if (Number.isNaN(from) || Number.isNaN(to) || from > to) throw new Error('bad window');

  const workouts = db.prepare('SELECT * FROM workouts WHERE user_id = ? ORDER BY started_at').all(user.id) as Row[];
  const logs = db.prepare('SELECT * FROM workout_logs WHERE user_id = ?').all(user.id) as Row[];
  const attempts = db.prepare('SELECT * FROM pr_attempts WHERE user_id = ?').all(user.id) as Row[];
  const inWindow = (t: number) => t >= from && t <= to;

  const candidates: Candidate[] = [];
  for (const w of workouts) {
    const data = JSON.parse(String(w.data)) as { sessionId?: string; durationSec?: number; title?: unknown; exercises?: { setsDone?: number }[] };
    const start = ms(w.started_at);
    const end = start + (data.durationSec ?? 0) * 1000;
    if (!inWindow(start) && !inWindow(end) && !inWindow(ms(w.updated_at))) continue;

    const next = workouts
      .filter((o) => o.id !== w.id && (JSON.parse(String(o.data)) as { sessionId?: string }).sessionId === data.sessionId && ms(o.started_at) > start)
      .map((o) => ms(o.started_at));
    const logTo = Math.min(next.length ? Math.min(...next) : Infinity, end + 6 * 3600_000);
    const wLogs = logs.filter((l) => l.session_id === data.sessionId && ms(l.date) >= start - 60_000 && ms(l.date) < logTo);
    const wAttempts = attempts.filter((a) => ms(a.date) >= start - 60_000 && ms(a.date) <= end + 60_000);
    const refs = [String(w.id).toLowerCase(), ...wAttempts.map((a) => String(a.id).toLowerCase())];
    const posts = (db.prepare('SELECT * FROM community_posts WHERE user_id = ? AND ref_id IS NOT NULL').all(user.id) as Row[]).filter((p) =>
      refs.includes(String(p.ref_id).toLowerCase()),
    );
    const reactions = posts.flatMap((p) => db.prepare('SELECT * FROM community_reactions WHERE post_id = ?').all(String(p.id)) as Row[]);
    candidates.push({
      workout: w,
      title: data.title,
      startedAt: new Date(start).toISOString(),
      endedAt: new Date(end).toISOString(),
      totalSets: (data.exercises ?? []).reduce((n, e) => n + (e.setsDone ?? 0), 0),
      logs: wLogs,
      prAttempts: wAttempts,
      posts,
      reactions,
    });
  }
  return { user, candidates };
};

/** Backs up, then deletes exactly one candidate. Returns the backup path and per-table counts. */
export const undoWorkout = (db: DB, input: UndoInput, backupDir: string, now = new Date()) => {
  const { user, candidates } = findCandidates(db, input);
  const c = candidates.find((x) => x.workout.id === input.workoutId);
  if (!c) throw new Error('workout id is not a candidate in this window');
  mkdirSync(backupDir, { recursive: true });
  const backup = join(backupDir, `undo-workout-${String(c.workout.id)}-${now.toISOString().replace(/[:.]/g, '-')}.json`);
  writeFileSync(backup, JSON.stringify({ user, removedAt: now.toISOString(), ...c }, null, 2));
  const ids = (rows: Row[]) => rows.map((r) => String(r.id));
  const counts = tx(db, () => ({
    workouts: Number(db.prepare('DELETE FROM workouts WHERE id = ? AND user_id = ?').run(String(c.workout.id), user.id).changes),
    workout_logs: ids(c.logs).reduce((n, id) => n + Number(db.prepare('DELETE FROM workout_logs WHERE id = ? AND user_id = ?').run(id, user.id).changes), 0),
    pr_attempts: ids(c.prAttempts).reduce((n, id) => n + Number(db.prepare('DELETE FROM pr_attempts WHERE id = ? AND user_id = ?').run(id, user.id).changes), 0),
    community_posts: ids(c.posts).reduce((n, id) => n + Number(db.prepare('DELETE FROM community_posts WHERE id = ? AND user_id = ?').run(id, user.id).changes), 0),
  }));
  return { backup, removed: { ...counts, community_reactions: c.reactions.length }, workout: c };
};

const summary = (c: Candidate) => ({
  id: c.workout.id,
  title: c.title,
  startedAt: c.startedAt,
  endedAt: c.endedAt,
  savedAt: c.workout.updated_at,
  totalSets: c.totalSets,
  logs: c.logs.length,
  prAttempts: c.prAttempts.length,
  posts: c.posts.length,
  reactions: c.reactions.length,
});

// CLI: node src/admin/undoWorkout.ts <base64 JSON UndoInput>
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const input = JSON.parse(Buffer.from(process.argv[2] ?? '', 'base64').toString('utf8')) as UndoInput;
  const path = process.env.DB_PATH ?? '/data/app.db';
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  if (input.apply && input.workoutId) {
    const r = undoWorkout(db, input, join(dirname(path), 'backups'));
    console.log(JSON.stringify({ removed: r.removed, workout: summary(r.workout), backupFile: r.backup }, null, 2));
    console.log('BACKUP ' + JSON.stringify(r.workout));
  } else {
    const { candidates } = findCandidates(db, input);
    console.log(JSON.stringify({ dryRun: true, candidates: candidates.map(summary) }, null, 2));
  }
  db.close();
}
