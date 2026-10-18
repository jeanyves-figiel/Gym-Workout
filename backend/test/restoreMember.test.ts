import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { restoreMember } from '../src/admin/restoreMember.ts';
import { backupDirFor, backupNow } from '../src/backup.ts';
import { type DB, openDb } from '../src/db.ts';

let root: string;
let db: DB;
const T = '2026-10-14T10:00:00Z';

const user = (id: string, email: string) => db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, email, T, T);
const workout = (id: string, userId: string, data = '{}') =>
  db.prepare('INSERT OR REPLACE INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)').run(id, userId, T, data, T);
const ids = (userId: string) => (db.prepare('SELECT id FROM workouts WHERE user_id = ? ORDER BY id').all(userId) as { id: string }[]).map((r) => r.id);

let backup: DatabaseSync;
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'member-'));
  db = openDb(join(root, 'app.db'));
  user('u1', 'ana@example.com');
  user('u2', 'ben@example.com');
  workout('w1', 'u1', '{"v":1}');
  workout('w2', 'u1');
  workout('b1', 'u2');
  db.prepare('INSERT INTO profiles (user_id, data, updated_at) VALUES (?, ?, ?)').run('u1', '{"goal":"strength"}', T);
  const b = backupNow(db, backupDirFor(join(root, 'app.db')), { keep: 7, now: new Date(T) });
  backup = new DatabaseSync(join(backupDirFor(join(root, 'app.db')), b.file), { readOnly: true });
  // After the backup: ana loses w2, edits w1 and her profile, adds w3; ben loses b1.
  db.prepare("DELETE FROM workouts WHERE id IN ('w2', 'b1')").run();
  workout('w1', 'u1', '{"v":2}');
  workout('w3', 'u1');
  db.prepare("UPDATE profiles SET data = '{\"goal\":\"fat loss\"}' WHERE user_id = 'u1'").run();
});
afterEach(() => {
  backup.close();
  db.close();
  rmSync(root, { recursive: true, force: true });
});

describe('restore one member (#315)', () => {
  it('dry run lists what would come back and changes nothing', () => {
    const r = restoreMember(db, backup, { email: 'Ana@example.com' }, root);
    expect(r.summary.workouts).toEqual({ missing: 1, changed: 1, restored: 0 });
    expect(ids('u1')).toEqual(['w1', 'w3']);
    expect(r.saved).toBeUndefined();
  });

  it('puts back only missing rows of that member, with a fresh updated_at, and saves what it did', () => {
    const r = restoreMember(db, backup, { email: 'ana@example.com', apply: true }, root, new Date('2026-10-15T06:00:00Z'));
    expect(ids('u1')).toEqual(['w1', 'w2', 'w3']);
    expect(ids('u2')).toEqual([]);
    expect(db.prepare("SELECT data FROM workouts WHERE id = 'w1'").get()).toEqual({ data: '{"v":2}' });
    expect(db.prepare("SELECT updated_at FROM workouts WHERE id = 'w2'").get()).toEqual({ updated_at: '2026-10-15T06:00:00.000Z' });
    expect(db.prepare("SELECT data FROM profiles WHERE user_id = 'u1'").get()).toEqual({ data: '{"goal":"fat loss"}' });
    expect(existsSync(r.saved!)).toBe(true);
    expect(JSON.parse(readFileSync(r.saved!, 'utf8')).inserted.workouts).toEqual(['w2']);
  });

  it('overwrite and profile replace changed rows and keep the replaced ones in the saved file', () => {
    const r = restoreMember(db, backup, { email: 'ana@example.com', apply: true, overwrite: true, profile: true }, root);
    expect(db.prepare("SELECT data FROM workouts WHERE id = 'w1'").get()).toEqual({ data: '{"v":1}' });
    expect(db.prepare("SELECT data FROM profiles WHERE user_id = 'u1'").get()).toEqual({ data: '{"goal":"strength"}' });
    expect(ids('u1')).toEqual(['w1', 'w2', 'w3']);
    expect(JSON.parse(readFileSync(r.saved!, 'utf8')).replaced.workouts[0].data).toBe('{"v":2}');
  });

  it('never restores a deleted or re-created account', () => {
    db.prepare("DELETE FROM users WHERE id = 'u1'").run();
    expect(() => restoreMember(db, backup, { email: 'ana@example.com', apply: true }, root)).toThrow(/deleted accounts/);
    user('u9', 'ana@example.com');
    expect(() => restoreMember(db, backup, { email: 'ana@example.com', apply: true }, root)).toThrow(/created again/);
    expect(ids('u9')).toEqual([]);
  });

  it('photos unchanged since the backup are not listed as changed (#432)', () => {
    db.prepare("INSERT INTO machine_note_photos (id, user_id, note_id, data, created_at) VALUES ('p1', 'u1', 'n1', ?, ?)").run(Buffer.from([1, 2, 3]), T);
    const b = backupNow(db, join(root, 'b2'), { keep: 7, now: new Date(T) });
    const copy = new DatabaseSync(join(root, 'b2', b.file), { readOnly: true });
    try {
      expect(restoreMember(db, copy, { email: 'ana@example.com' }, root).summary.machine_note_photos).toEqual({ missing: 0, changed: 0, restored: 0 });
    } finally {
      copy.close();
    }
  });
});
