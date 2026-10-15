import { chmodSync, existsSync, mkdirSync, readdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { DB } from './db.ts';

/**
 * Daily SQLite backups next to the database (#310). `VACUUM INTO` writes a consistent copy while the
 * API keeps serving; the copy is checked (`quick_check`) before it replaces anything. One file per UTC
 * day, newest `keep` kept. Fly volume snapshots (daily, separate storage) cover losing the volume itself.
 */

const FILE = /^app-(\d{4}-\d{2}-\d{2})\.db$/;
export const RESTORE_FILE = 'restore.db';

export interface BackupInfo {
  file: string;
  day: string;
  bytes: number;
  modified: string;
}

export const backupDirFor = (dbPath: string): string => join(dirname(dbPath), 'backups');

export const listBackups = (dir: string): BackupInfo[] =>
  existsSync(dir)
    ? readdirSync(dir)
        .map((f) => FILE.exec(f))
        .filter((m): m is RegExpExecArray => !!m)
        .map((m) => {
          const s = statSync(join(dir, m[0]));
          return { file: m[0], day: m[1]!, bytes: s.size, modified: s.mtime.toISOString() };
        })
        .sort((a, b) => b.day.localeCompare(a.day))
    : [];

/** Opens a copy read-only and returns its integrity check and row counts of the main tables. */
export const inspectCopy = (path: string): { ok: boolean; check: string; counts: Record<string, number> } => {
  let db: DatabaseSync;
  try {
    db = new DatabaseSync(path, { readOnly: true });
    db.prepare('SELECT COUNT(*) FROM sqlite_master').get();
  } catch (e) {
    return { ok: false, check: (e as Error).message, counts: {} };
  }
  try {
    const check = String((db.prepare('PRAGMA quick_check').get() as Record<string, unknown>)['quick_check']);
    const counts: Record<string, number> = {};
    for (const t of ['users', 'profiles', 'workouts', 'workout_logs']) {
      const exists = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(t);
      if (exists) counts[t] = Number((db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get() as { n: number }).n);
    }
    return { ok: check === 'ok', check, counts };
  } finally {
    db.close();
  }
};

/** Writes today's backup (overwrites today's file), verifies it, then prunes to the newest `keep` days. */
export const backupNow = (db: DB, dir: string, opts: { keep: number; now?: Date }): BackupInfo & { counts: Record<string, number> } => {
  const day = (opts.now ?? new Date()).toISOString().slice(0, 10);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const file = `app-${day}.db`;
  const tmp = join(dir, `${file}.tmp`);
  rmSync(tmp, { force: true });
  db.prepare('VACUUM INTO ?').run(tmp);
  chmodSync(tmp, 0o600);
  const r = inspectCopy(tmp);
  if (!r.ok) {
    rmSync(tmp, { force: true });
    throw new Error(`backup check failed: ${r.check}`);
  }
  renameSync(tmp, join(dir, file));
  for (const old of listBackups(dir).slice(Math.max(1, opts.keep))) rmSync(join(dir, old.file), { force: true });
  const info = listBackups(dir).find((b) => b.file === file)!;
  return { ...info, counts: r.counts };
};

/** Backs up whenever today's file is missing: at start, then every `intervalMs`. Returns a stop function. */
export const startBackupJob = (
  db: DB,
  opts: { dir: string; keep: number; intervalMs: number; now?: () => Date; log?: (msg: string) => void },
): (() => void) => {
  const run = () => {
    const now = opts.now?.() ?? new Date();
    if (listBackups(opts.dir)[0]?.day === now.toISOString().slice(0, 10)) return;
    try {
      const b = backupNow(db, opts.dir, { keep: opts.keep, now });
      opts.log?.(`backup: ${b.file} ${b.bytes} bytes ${JSON.stringify(b.counts)}`);
    } catch (e) {
      opts.log?.(`backup failed: ${(e as Error).message}`);
    }
  };
  const first = setTimeout(run, 5_000);
  first.unref();
  const timer = opts.intervalMs > 0 ? setInterval(run, opts.intervalMs) : undefined;
  timer?.unref();
  return () => {
    clearTimeout(first);
    if (timer) clearInterval(timer);
  };
};

/** Copies a backup to `restore.db` after checking it; the next start swaps it in (see `applyPendingRestore`). */
export const stageRestore = (dir: string, file: string, dbPath: string): void => {
  if (!FILE.test(file)) throw new Error(`not a backup file name: ${file}`);
  const src = join(dir, file);
  if (!existsSync(src)) throw new Error(`no such backup: ${file}`);
  const r = inspectCopy(src);
  if (!r.ok) throw new Error(`backup check failed: ${r.check}`);
  const dst = join(dirname(dbPath), RESTORE_FILE);
  const db = new DatabaseSync(src, { readOnly: true });
  try {
    rmSync(dst, { force: true });
    db.prepare('VACUUM INTO ?').run(dst);
  } finally {
    db.close();
  }
  chmodSync(dst, 0o600);
};

/**
 * Before the database is opened: if `restore.db` is staged, keep the current database as
 * `backups/pre-restore-<time>.db` and put the staged copy in its place. Returns the kept file, if any.
 */
export const applyPendingRestore = (dbPath: string, now = new Date()): string | undefined => {
  const staged = join(dirname(dbPath), RESTORE_FILE);
  if (!existsSync(staged)) return undefined;
  if (!inspectCopy(staged).ok) {
    renameSync(staged, `${staged}.rejected`);
    throw new Error('staged restore failed its check; kept as restore.db.rejected');
  }
  const dir = backupDirFor(dbPath);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  let kept: string | undefined;
  if (existsSync(dbPath)) {
    // Fold the WAL into the main file so the kept copy is complete.
    const cur = new DatabaseSync(dbPath);
    cur.exec('PRAGMA wal_checkpoint(TRUNCATE);');
    cur.close();
    kept = join(dir, `pre-restore-${now.toISOString().replace(/[:.]/g, '-')}.db`);
    renameSync(dbPath, kept);
  }
  for (const ext of ['-wal', '-shm']) rmSync(dbPath + ext, { force: true });
  renameSync(staged, dbPath);
  return kept && basename(kept);
};
