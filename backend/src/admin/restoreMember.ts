import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { backupDirFor } from '../backup.ts';
import type { DB } from '../db.ts';

/**
 * Restores one member's training data from a daily backup (#315), for a support request ("my workouts are gone").
 * The whole-database restore (#310) would roll back every member, so this copies only that member's rows:
 * - rows in the backup but not live are put back (`missing`);
 * - rows that differ are listed (`changed`) and only replaced with `overwrite`;
 * - live rows not in the backup are never touched; other members are never touched.
 * Restored rows get a fresh `updated_at` so the member's devices pick them up on the next sync.
 * The account must still exist with the same id: deleted accounts are not restored (deletion is final).
 * Run via the "Fly backups" workflow (action member-restore); dry run unless `apply`.
 */

const TABLES = ['workouts', 'workout_logs', 'pr_attempts', 'body_measurements', 'climbs', 'custom_workouts', 'custom_exercises'] as const;

export interface MemberRestoreInput {
  email: string;
  apply?: boolean;
  /** Also replace rows that exist live but differ from the backup. */
  overwrite?: boolean;
  /** Also put back the training profile (one row, replaces the live one). */
  profile?: boolean;
}

type Row = Record<string, unknown>;

const columns = (db: DatabaseSync, t: string) => (db.prepare(`PRAGMA table_info(${t})`).all() as { name: string }[]).map((c) => c.name);
const hasTable = (db: DatabaseSync, t: string) => !!db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(t);
const same = (a: Row, b: Row, cols: string[]) => cols.every((c) => c === 'updated_at' || a[c] === b[c]);

export const restoreMember = (live: DB, backup: DatabaseSync, input: MemberRestoreInput, saveDir: string, now = new Date()) => {
  const email = input.email.trim().toLowerCase();
  const user = live.prepare('SELECT id FROM users WHERE email = ? COLLATE NOCASE').get(email) as { id: string } | undefined;
  const old = backup.prepare('SELECT id FROM users WHERE email = ? COLLATE NOCASE').get(email) as { id: string } | undefined;
  if (!old) throw new Error('no account with this email in the backup');
  if (!user) throw new Error('no live account with this email (deleted accounts are not restored)');
  if (user.id !== old.id) throw new Error('the account was deleted and created again since this backup; not restored');
  const ts = now.toISOString();
  const plan: Record<string, { missing: Row[]; changed: Row[]; replaced: Row[] }> = {};
  const tables: string[] = [...TABLES];
  if (input.profile) tables.push('profiles');
  for (const t of tables) {
    if (!hasTable(backup, t) || !hasTable(live, t)) continue;
    const liveCols = columns(live, t);
    const cols = columns(backup, t).filter((c) => liveCols.includes(c));
    const key = t === 'profiles' ? 'user_id' : 'id';
    const fromBackup = backup.prepare(`SELECT ${cols.join(', ')} FROM ${t} WHERE user_id = ?`).all(user.id) as Row[];
    const getLive = live.prepare(`SELECT * FROM ${t} WHERE ${key} = ?`);
    const p = (plan[t] = { missing: [] as Row[], changed: [] as Row[], replaced: [] as Row[] });
    for (const r of fromBackup) {
      const cur = getLive.get(r[key] as string) as Row | undefined;
      if (!cur) p.missing.push(r);
      else if (cur['user_id'] !== user.id) continue; // id now owned by someone else: never touch
      else if (!same(r, cur, cols)) {
        p.changed.push(r);
        p.replaced.push(cur);
      }
    }
    if (!input.apply) continue;
    const write = (r: Row, verb: string) => {
      const row: Row = cols.includes('updated_at') ? { ...r, updated_at: ts } : r;
      live.prepare(`${verb} INTO ${t} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`).run(...cols.map((c) => row[c] as never));
    };
    for (const r of p.missing) write(r, 'INSERT OR IGNORE');
    if (input.overwrite || t === 'profiles') for (const r of p.changed) write(r, 'INSERT OR REPLACE');
  }
  const summary = Object.fromEntries(
    Object.entries(plan).map(([t, p]) => [t, { missing: p.missing.length, changed: p.changed.length, restored: input.apply ? p.missing.length + (input.overwrite || t === 'profiles' ? p.changed.length : 0) : 0 }]),
  );
  let saved: string | undefined;
  if (input.apply) {
    // Live rows that were replaced, so the restore itself can be undone by hand.
    mkdirSync(saveDir, { recursive: true, mode: 0o700 });
    saved = join(saveDir, `member-restore-${user.id}-${ts.replace(/[:.]/g, '-')}.json`);
    const replaced = Object.fromEntries(Object.entries(plan).map(([t, p]) => [t, input.overwrite || t === 'profiles' ? p.replaced : []]));
    const inserted = Object.fromEntries(Object.entries(plan).map(([t, p]) => [t, p.missing.map((r) => r['id'] ?? r['user_id'])]));
    writeFileSync(saved, JSON.stringify({ userId: user.id, restoredAt: ts, inserted, replaced }, null, 2), { mode: 0o600 });
  }
  return { userId: user.id, apply: !!input.apply, summary, saved };
};

// CLI: node src/admin/restoreMember.ts <backup file name> <base64 JSON MemberRestoreInput>
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [file, b64] = process.argv.slice(2);
  if (!file || !/^app-\d{4}-\d{2}-\d{2}\.db$/.test(file) || !b64) {
    console.error('usage: restoreMember.ts app-YYYY-MM-DD.db <base64 JSON {email, apply, overwrite, profile}>');
    process.exit(2);
  }
  const input = JSON.parse(Buffer.from(b64, 'base64').toString('utf8')) as MemberRestoreInput;
  const path = process.env.DB_PATH ?? '/data/app.db';
  const dir = backupDirFor(path);
  const backup = new DatabaseSync(join(dir, file), { readOnly: true });
  const live = new DatabaseSync(path);
  live.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  live.exec('BEGIN IMMEDIATE');
  try {
    const r = restoreMember(live, backup, input, join(dirname(path), 'backups'));
    live.exec('COMMIT');
    console.log(JSON.stringify(r, null, 2));
  } catch (e) {
    live.exec('ROLLBACK');
    throw e;
  } finally {
    live.close();
    backup.close();
  }
}
