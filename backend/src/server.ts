import { createAppleVerifier } from './apple.ts';
import { buildApp } from './app.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { createMailer } from './mailer.ts';
import { startPurgeJob } from './purge.ts';

const config = loadConfig();
const db = openDb(config.dbPath);
const app = buildApp({
  config,
  db,
  mailer: createMailer(config),
  apple: createAppleVerifier(config.appleBundleIds),
  logger: true,
});

const stopPurge = startPurgeJob(db, { intervalMs: config.purgeIntervalMin * 60_000, log: (m) => app.log.info(m) });

const shutdown = async () => {
  stopPurge();
  await app.close();
  db.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ host: config.host, port: config.port });
