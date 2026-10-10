import type { DB } from './db.ts';

/**
 * Idempotent schema for account-security features (#12 / #13): Apple refresh tokens (for revocation),
 * pending email changes, and indexes used by the purge job. Kept outside the numbered MIGRATIONS
 * so it can land independently; every statement is IF NOT EXISTS.
 */
export const ensureSchemaExtras = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS apple_tokens (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      client_id TEXT NOT NULL,
      refresh_token_enc TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS email_changes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      new_email TEXT NOT NULL COLLATE NOCASE,
      code_hash TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      expires_at TEXT NOT NULL,
      consumed_at TEXT,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS email_changes_user ON email_changes(user_id);
    CREATE INDEX IF NOT EXISTS codes_expires ON codes(expires_at);
    CREATE INDEX IF NOT EXISTS refresh_expires ON refresh_tokens(expires_at);
  `);
};
