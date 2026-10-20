import { describe, expect, it } from 'vitest';
import { openDb } from '../src/db.ts';
import { memberNotHiddenSql } from '../src/community/moderation.ts';
import { purgeExpired } from '../src/purge.ts';

const plan = (db: ReturnType<typeof openDb>, sql: string, ...args: (string | number)[]) =>
  (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((r) => r.detail).join('\n');

describe('hot queries use an index', () => {
  it('prunes "Taken?" taps by time in the purge job, not on every tap', () => {
    const db = openDb(':memory:');
    expect(plan(db, 'DELETE FROM gym_busy WHERE at < ?', 'x')).toMatch(/USING (COVERING )?INDEX gym_busy_at/);
    db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run('u', 'u@example.com', 'x', 'x');
    const tap = db.prepare('INSERT INTO gym_busy (user_id, gym_id, zone, at) VALUES (?, ?, ?, ?)');
    tap.run('u', 'g', 'rack', '2026-08-01T10:00:00.000Z');
    tap.run('u', 'g', 'rack', '2026-10-01T10:00:00.000Z');
    purgeExpired(db, new Date('2026-10-20T10:00:00Z'));
    expect((db.prepare('SELECT at FROM gym_busy').all() as { at: string }[]).map((r) => r.at)).toEqual(['2026-10-01T10:00:00.000Z']);
  });

  it('looks up reports about a member by target user', () => {
    const db = openDb(':memory:');
    expect(plan(db, `SELECT 1 FROM users u WHERE ${memberNotHiddenSql('u.id')}`)).toMatch(/INDEX community_reports_target_user/);
  });

  it('finds a shared workout by id in any letter case', () => {
    const db = openDb(':memory:');
    expect(plan(db, 'SELECT 1 FROM custom_workouts w WHERE lower(w.id) = lower(?)', 'A')).toMatch(/INDEX custom_workouts_lower_id/);
  });
});
