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

  it('purges App Store notification ids after 90 days', () => {
    const db = openDb(':memory:');
    const add = db.prepare('INSERT INTO app_store_notifications (uuid, type, received_at) VALUES (?, ?, ?)');
    add.run('old', 'DID_RENEW', '2026-07-01T00:00:00.000Z');
    add.run('new', 'DID_RENEW', '2026-10-01T00:00:00.000Z');
    purgeExpired(db, new Date('2026-10-20T10:00:00Z'));
    expect(db.prepare('SELECT uuid FROM app_store_notifications').all()).toEqual([{ uuid: 'new' }]);
  });

  it('looks up reports about a member by target user', () => {
    const db = openDb(':memory:');
    expect(plan(db, `SELECT 1 FROM users u WHERE ${memberNotHiddenSql('u.id')}`)).toMatch(/INDEX community_reports_target_user/);
  });

  it('finds a shared workout by id in any letter case', () => {
    const db = openDb(':memory:');
    expect(plan(db, 'SELECT 1 FROM custom_workouts w WHERE lower(w.id) = lower(?)', 'A')).toMatch(/INDEX custom_workouts_lower_id/);
  });

  it('finds gyms by their name key (#715)', () => {
    const db = openDb(':memory:');
    for (const t of ['gym_reports', 'gym_maps'])
      expect(plan(db, `SELECT * FROM ${t} WHERE (gym_id = ? OR (name_key >= ? AND name_key < ?)) AND user_id != ?`, 'g', 'a', 'b', 'u')).toMatch(
        new RegExp(`INDEX ${t}_name_key`),
      );
  });

  it('finds members at a gym without reading training profiles (#715)', () => {
    const db = openDb(':memory:');
    expect(plan(db, 'SELECT 1 FROM community_profiles WHERE gym_id = ?', 'g')).toMatch(/INDEX community_profiles_gym\b/);
    expect(plan(db, 'SELECT 1 FROM community_profiles WHERE show_gym = 1 AND gym_key = ?', 'k')).toMatch(/INDEX community_profiles_gym_key/);
  });

  it("looks up one member's cheers, live cheers and challenge scores (#715)", () => {
    const db = openDb(':memory:');
    expect(plan(db, 'SELECT 1 FROM community_reactions WHERE user_id = ?', 'u')).toMatch(/INDEX community_reactions_user/);
    expect(plan(db, 'SELECT 1 FROM community_live_cheers WHERE from_id = ?', 'u')).toMatch(/INDEX community_live_cheers_from/);
    expect(plan(db, 'SELECT 1 FROM community_challenge_scores WHERE user_id = ?', 'u')).toMatch(/INDEX community_challenge_scores_user/);
  });

  it('lists the export in time order from an index (#714)', () => {
    const db = openDb(':memory:');
    expect(plan(db, 'SELECT id FROM workouts WHERE user_id = ? ORDER BY julianday(started_at), id', 'u')).toMatch(/INDEX workouts_user_time/);
    expect(plan(db, 'SELECT id FROM climbs WHERE user_id = ? ORDER BY julianday(start), id', 'u')).toMatch(/INDEX climbs_user_time/);
  });
});
