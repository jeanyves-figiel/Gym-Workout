import { createAppleVerifier } from './apple.ts';
import { buildApp } from './app.ts';
import { applyPendingRestore, startBackupJob, startHourlyCopyJob } from './backup.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { OffsiteStore } from './offsite.ts';
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
const offsite = config.offsite && new OffsiteStore(config.offsite);
const stopBackup = config.backup.dir
  ? startBackupJob(db, {
      dir: config.backup.dir,
      keep: config.backup.keepDays,
      intervalMs: 3_600_000,
      log: (m) => app.log.info(m),
      after: offsite
        ? async (path, day) => {
            const r = await offsite.upload(path, day);
            return `backup off-site: ${r.key} ${r.bytes} bytes, ${r.pruned} pruned`;
          }
        : undefined,
    })
  : () => {};
const stopHourly =
  config.backup.dir && offsite && config.offsite!.keepHours > 0
    ? startHourlyCopyJob(db, {
        dir: config.backup.dir,
        intervalMs: 3_600_000,
        log: (m) => app.log.info(m),
        upload: async (path, hour) => {
          const r = await offsite.uploadHourly(path, hour);
          return `backup hourly off-site: ${r.key} ${r.bytes} bytes, ${r.pruned} pruned`;
        },
      })
    : () => {};
if (config.backup.dir && !offsite) app.log.warn('backup off-site copy off (needs Tigris bucket secrets + BACKUP_KEY)');

const shutdown = async () => {
  stopPurge();
  stopBackup();
  stopHourly();
  await app.close();
  db.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ host: config.host, port: config.port });
