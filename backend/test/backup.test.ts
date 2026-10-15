import { existsSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { applyPendingRestore, backupDirFor, backupNow, inspectCopy, listBackups, stageRestore } from '../src/backup.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';

let root: string;
let dbPath: string;
let db: DB;

const addUser = (id: string) =>
  db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, `${id}@example.com`, 'x', 'x');
const users = (d: DB) => (d.prepare('SELECT id FROM users ORDER BY id').all() as { id: string }[]).map((r) => r.id);

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'backup-'));
  dbPath = join(root, 'app.db');
  db = openDb(dbPath);
});
afterEach(() => {
  try {
    db.close();
  } catch {}
  rmSync(root, { recursive: true, force: true });
});

describe('daily backups (#310)', () => {
  it('writes a checked, private copy per day and keeps the newest N', () => {
    addUser('a');
    const dir = backupDirFor(dbPath);
    for (let d = 1; d <= 9; d++) backupNow(db, dir, { keep: 7, now: new Date(`2026-10-0${d}T03:00:00Z`) });
    const list = listBackups(dir);
    expect(list.map((b) => b.day)).toEqual(['2026-10-09', '2026-10-08', '2026-10-07', '2026-10-06', '2026-10-05', '2026-10-04', '2026-10-03']);
    expect(readdirSync(dir).some((f) => f.endsWith('.tmp'))).toBe(false);
    expect(statSync(join(dir, list[0]!.file)).mode & 0o777).toBe(0o600);
    expect(inspectCopy(join(dir, list[0]!.file))).toMatchObject({ ok: true, counts: { users: 1 } });
  });

  it('restores a staged backup on next start and keeps the replaced database', () => {
    addUser('a');
    const dir = backupDirFor(dbPath);
    const b = backupNow(db, dir, { keep: 7, now: new Date('2026-10-14T03:00:00Z') });
    addUser('b');
    stageRestore(dir, b.file, dbPath);
    db.close();
    const kept = applyPendingRestore(dbPath, new Date('2026-10-15T05:00:00Z'));
    expect(kept).toMatch(/^pre-restore-2026-10-15/);
    expect(existsSync(join(root, 'restore.db'))).toBe(false);
    db = openDb(dbPath);
    expect(users(db)).toEqual(['a']);
    expect(inspectCopy(join(dir, kept!)).counts.users).toBe(2);
    expect(applyPendingRestore(dbPath)).toBeUndefined();
  });

  it('rejects a corrupt staged restore and leaves the live database alone', () => {
    addUser('a');
    db.close();
    writeFileSync(join(root, 'restore.db'), 'not a database');
    expect(() => applyPendingRestore(dbPath)).toThrow();
    expect(existsSync(join(root, 'restore.db.rejected'))).toBe(true);
    db = openDb(dbPath);
    expect(users(db)).toEqual(['a']);
  });

  it('only accepts backup file names for restore', () => {
    expect(() => stageRestore(backupDirFor(dbPath), '../app.db', dbPath)).toThrow(/not a backup/);
  });

  it('is on by default in production next to the database, and can be turned off', () => {
    const base = { NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(32), CODE_PEPPER: 'p', MAIL_TRANSPORT: 'console', DB_PATH: '/data/app.db' };
    expect(loadConfig(base).backup).toEqual({ dir: '/data/backups', keepDays: 7 });
    expect(loadConfig({ ...base, BACKUP_DIR: 'off' }).backup.dir).toBeUndefined();
    expect(loadConfig({ NODE_ENV: 'test' }).backup.dir).toBeUndefined();
  });
});
