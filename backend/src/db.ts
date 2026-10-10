import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { ensurePushSchema } from './push/schema.ts';
import { ensureSchemaExtras } from './schemaExtras.ts';

export type DB = DatabaseSync;

const MIGRATIONS: string[] = [
  `CREATE TABLE users (
     id TEXT PRIMARY KEY,
     email TEXT UNIQUE COLLATE NOCASE,
     password_hash TEXT,
     email_verified_at TEXT,
     name TEXT,
     apple_sub TEXT UNIQUE,
     terms_accepted_at TEXT,
     failed_logins INTEGER NOT NULL DEFAULT 0,
     locked_until TEXT,
     created_at TEXT NOT NULL,
     updated_at TEXT NOT NULL
   );
   CREATE TABLE codes (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     purpose TEXT NOT NULL CHECK (purpose IN ('verify_email', 'reset_password')),
     code_hash TEXT NOT NULL,
     attempts INTEGER NOT NULL DEFAULT 0,
     expires_at TEXT NOT NULL,
     consumed_at TEXT,
     created_at TEXT NOT NULL
   );
   CREATE INDEX codes_user_purpose ON codes(user_id, purpose);
   CREATE TABLE refresh_tokens (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     family_id TEXT NOT NULL,
     token_hash TEXT NOT NULL UNIQUE,
     device TEXT,
     expires_at TEXT NOT NULL,
     revoked_at TEXT,
     replaced_by TEXT,
     created_at TEXT NOT NULL
   );
   CREATE INDEX refresh_user ON refresh_tokens(user_id);
   CREATE INDEX refresh_family ON refresh_tokens(family_id);
   CREATE TABLE profiles (
     user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
     data TEXT NOT NULL,
     updated_at TEXT NOT NULL
   );
   CREATE TABLE workout_logs (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     date TEXT NOT NULL,
     exercise_id TEXT NOT NULL,
     session_id TEXT,
     weight_kg REAL,
     reps INTEGER,
     updated_at TEXT NOT NULL
   );
   CREATE INDEX logs_user_updated ON workout_logs(user_id, updated_at);`,
  `CREATE TABLE workouts (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     started_at TEXT NOT NULL,
     data TEXT NOT NULL,
     updated_at TEXT NOT NULL
   );
   CREATE INDEX workouts_user_updated ON workouts(user_id, updated_at);`,
  // Per-set logging: which set (0-based) and reps in reserve. Nullable → old rows/clients unaffected.
  `ALTER TABLE workout_logs ADD COLUMN set_index INTEGER;
   ALTER TABLE workout_logs ADD COLUMN rir INTEGER;`,
  `CREATE TABLE custom_workouts (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     data TEXT NOT NULL,
     updated_at TEXT NOT NULL
   );
   CREATE INDEX custom_workouts_user_updated ON custom_workouts(user_id, updated_at);`,
];

export const openDb = (path: string): DB => {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON;');
  if (path !== ':memory:') db.exec('PRAGMA journal_mode = WAL;');
  migrate(db);
  ensureSchemaExtras(db);
  ensurePushSchema(db);
  return db;
};

const migrate = (db: DB) => {
  db.exec('CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)');
  const row = db.prepare('SELECT version FROM schema_version').get() as { version: number } | undefined;
  let v = row?.version ?? 0;
  if (!row) db.prepare('INSERT INTO schema_version (version) VALUES (0)').run();
  for (; v < MIGRATIONS.length; v++) {
    tx(db, () => {
      db.exec(MIGRATIONS[v]!);
      db.prepare('UPDATE schema_version SET version = ?').run(v + 1);
    });
  }
};

export const tx = <T>(db: DB, fn: () => T): T => {
  db.exec('BEGIN IMMEDIATE');
  try {
    const out = fn();
    db.exec('COMMIT');
    return out;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
};
