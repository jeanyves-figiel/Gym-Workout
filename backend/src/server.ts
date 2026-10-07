import { createAppleVerifier } from './apple.ts';
import { buildApp } from './app.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { createMailer } from './mailer.ts';

const config = loadConfig();
const db = openDb(config.dbPath);
const app = buildApp({
  config,
  db,
  mailer: createMailer(config),
  apple: createAppleVerifier(config.appleBundleIds),
  logger: true,
});

const shutdown = async () => {
  await app.close();
  db.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ host: config.host, port: config.port });
