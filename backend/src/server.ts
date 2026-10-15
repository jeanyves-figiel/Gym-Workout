import { createAppleVerifier } from './apple.ts';
import { buildApp } from './app.ts';
import { applyPendingRestore, startBackupJob } from './backup.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { createMailer } from './mailer.ts';
import { startPurgeJob } from './purge.ts';

const config = loadConfig();
let restored: string | undefined;
let restoreError: string | undefined;
try {
  restored = applyPendingRestore(config.dbPath);
} catch (e) {
  restoreError = (e as Error).message;
}
const db = openDb(config.dbPath);
const app = buildApp({
  config,
  db,
  mailer: createMailer(config),
  apple: createAppleVerifier(config.appleBundleIds),
  logger: true,
});

const stopPurge = startPurgeJob(db, { intervalMs: config.purgeIntervalMin * 60_000, log: (m) => app.log.info(m) });
if (restored) app.log.warn(`restore: staged backup swapped in, previous database kept as backups/${restored}`);
if (restoreError) app.log.error(`restore skipped: ${restoreError}`);
const stopBackup = config.backup.dir
  ? startBackupJob(db, { dir: config.backup.dir, keep: config.backup.keepDays, intervalMs: 3_600_000, log: (m) => app.log.info(m) })
  : () => {};

const shutdown = async () => {
  stopPurge();
  stopBackup();
  await app.close();
  db.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ host: config.host, port: config.port });
