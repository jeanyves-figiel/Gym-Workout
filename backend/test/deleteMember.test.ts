import { describe, expect, it } from 'vitest';
import { memberFootprint } from '../src/admin/deleteMember.ts';
import { openDb } from '../src/db.ts';

describe('delete a member on request (#315)', () => {
  it('lists every table holding the member, and nothing is left after the account row goes', () => {
    const db = openDb(':memory:');
    const T = '2026-10-15T00:00:00Z';
    for (const id of ['u1', 'u2']) db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, `${id}@x.ch`, T, T);
    db.prepare("INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES ('w1', 'u1', ?, '{}', ?)").run(T, T);
    db.prepare("INSERT INTO climbs (id, user_id, start, data, updated_at) VALUES ('c1', 'u1', ?, '{}', ?)").run(T, T);
    db.prepare("INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES ('w2', 'u2', ?, '{}', ?)").run(T, T);
    expect(memberFootprint(db, 'u1')).toEqual({ workouts: 1, climbs: 1 });
    db.prepare("DELETE FROM users WHERE id = 'u1'").run();
    expect(memberFootprint(db, 'u1')).toEqual({});
    expect(memberFootprint(db, 'u2')).toEqual({ workouts: 1 });
  });
});
