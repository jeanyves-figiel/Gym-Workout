import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';
import { findCandidates, undoWorkout } from '../src/admin/undoWorkout.ts';
import { type DB, openDb } from '../src/db.ts';

const T = '2026-10-11T00:00:00Z';
let db: DB;

const user = (id: string, email: string) =>
  db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, email, T, T);
const workout = (id: string, userId: string, sessionId: string, startedAt: string, durationSec: number, saved: string) =>
  db.prepare('INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)').run(
    id, userId, startedAt, JSON.stringify({ id, startedAt, sessionId, durationSec, title: 'Upper', exercises: [{ setsDone: 3 }] }), saved,
  );
const log = (id: string, userId: string, sessionId: string, date: string) =>
  db.prepare('INSERT INTO workout_logs (id, user_id, date, exercise_id, session_id, weight_kg, reps, updated_at) VALUES (?, ?, ?, ?, ?, 50, 8, ?)').run(
    id, userId, date, 'bench', sessionId, T,
  );
const count = (table: string) => (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;

beforeEach(() => {
  db = openDb(':memory:');
  user('u1', 'me@example.com');
  user('u2', 'other@example.com');
  // Mistaken workout: 10:50–11:20, same session done again later at 12:00.
  workout('w-bad', 'u1', 's-mon', '2026-10-11T10:50:00Z', 1800, '2026-10-11T11:20:05Z');
  workout('w-old', 'u1', 's-mon', '2026-10-04T10:00:00Z', 3600, '2026-10-04T11:00:00Z');
  workout('w-later', 'u1', 's-mon', '2026-10-11T12:00:00Z', 1800, '2026-10-11T12:30:00Z');
  workout('w-other', 'u2', 's-mon', '2026-10-11T10:50:00Z', 1800, '2026-10-11T11:20:00Z');
  log('l-bad1', 'u1', 's-mon', '2026-10-11T10:55:00Z');
  log('l-bad2', 'u1', 's-mon', '2026-10-11T11:10:00Z');
  log('l-otherSession', 'u1', 's-tue', '2026-10-11T11:00:00Z');
  log('l-later', 'u1', 's-mon', '2026-10-11T12:05:00Z');
  log('l-old', 'u1', 's-mon', '2026-10-04T10:10:00Z');
  log('l-u2', 'u2', 's-mon', '2026-10-11T11:00:00Z');
  db.prepare("INSERT INTO pr_attempts (id, user_id, exercise_id, date, data, updated_at) VALUES ('pa1', 'u1', 'bench', '2026-10-11T11:05:00Z', '{}', ?)").run(T);
  db.prepare("INSERT INTO pr_attempts (id, user_id, exercise_id, date, data, updated_at) VALUES ('pa2', 'u1', 'bench', '2026-10-09T11:05:00Z', '{}', ?)").run(T);
  const post = db.prepare("INSERT INTO community_posts (id, user_id, kind, ref_id, visibility, payload, created_at, updated_at) VALUES (?, 'u1', 'workout', ?, 'members', '{}', ?, ?)");
  post.run('p-bad', 'w-bad', T, T);
  post.run('p-old', 'w-old', T, T);
  db.prepare("INSERT INTO community_reactions (post_id, user_id, kind, created_at) VALUES ('p-bad', 'u2', 'like', ?)").run(T);
});

const window = { email: 'ME@example.com', from: '2026-10-11T11:10:00Z', to: '2026-10-11T11:30:00Z' };

describe('undo workout (ops)', () => {
  it('lists only the user’s workouts in the window, with what they would remove', () => {
    const { candidates } = findCandidates(db, window);
    expect(candidates.map((c) => c.workout.id)).toEqual(['w-bad']);
    const c = candidates[0]!;
    expect(c.logs.map((l) => l.id).sort()).toEqual(['l-bad1', 'l-bad2']);
    expect(c.prAttempts.map((a) => a.id)).toEqual(['pa1']);
    expect(c.posts.map((p) => p.id)).toEqual(['p-bad']);
    expect(c.reactions).toHaveLength(1);
  });

  it('backs up then deletes exactly that workout and its data, nothing else', () => {
    const dir = mkdtempSync(join(tmpdir(), 'undo-'));
    const r = undoWorkout(db, { ...window, workoutId: 'w-bad', apply: true }, dir);
    expect(r.removed).toEqual({ workouts: 1, workout_logs: 2, pr_attempts: 1, community_posts: 1, community_reactions: 1 });
    expect(existsSync(r.backup)).toBe(true);
    expect(JSON.parse(readFileSync(r.backup, 'utf8')).workout.id).toBe('w-bad');
    expect((db.prepare('SELECT id FROM workouts ORDER BY id').all() as { id: string }[]).map((x) => x.id)).toEqual(['w-later', 'w-old', 'w-other']);
    expect(count('workout_logs')).toBe(4);
    expect(count('pr_attempts')).toBe(1);
    expect(count('community_posts')).toBe(1);
    expect(count('community_reactions')).toBe(0);
  });

  it('refuses an id outside the window or another user’s workout', () => {
    const dir = mkdtempSync(join(tmpdir(), 'undo-'));
    expect(() => undoWorkout(db, { ...window, workoutId: 'w-old', apply: true }, dir)).toThrow();
    expect(() => undoWorkout(db, { ...window, workoutId: 'w-other', apply: true }, dir)).toThrow();
    expect(count('workouts')).toBe(4);
  });
});
