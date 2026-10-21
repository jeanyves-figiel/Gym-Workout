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
    -- Shared library look-up by id in any letter case (routes/library.ts: lower(w.id) = lower(?)).
    CREATE INDEX IF NOT EXISTS custom_workouts_lower_id ON custom_workouts(lower(id));
    -- Who saved which shared workout: a member's repeat saves don't bump the counter again.
    CREATE TABLE IF NOT EXISTS library_saves (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      workout_id TEXT NOT NULL REFERENCES custom_workouts(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, workout_id)
    );
    -- Climbing sessions (#312), synced from the app (routes/climbs.ts).
    CREATE TABLE IF NOT EXISTS climbs (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      start TEXT NOT NULL,
      data TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS climbs_user_updated ON climbs(user_id, updated_at);
    -- Other sport sessions (#416), synced from the app (routes/sports.ts).
    CREATE TABLE IF NOT EXISTS sports (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      start TEXT NOT NULL,
      data TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS sports_user_updated ON sports(user_id, updated_at);
    -- Upload-only key of the member's Apple Watch (#426), hashed (routes/sports.ts).
    CREATE TABLE IF NOT EXISTS watch_keys (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      key_hash TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    );
    -- Garmin watches (#550): a watch asks for a pairing code, the member types it in the app (routes/garmin.ts).
    CREATE TABLE IF NOT EXISTS garmin_devices (
      id TEXT PRIMARY KEY,
      token_hash TEXT NOT NULL UNIQUE,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      code TEXT,
      code_expires TEXT,
      model TEXT,
      created_at TEXT NOT NULL,
      last_seen TEXT
    );
    CREATE INDEX IF NOT EXISTS garmin_devices_user ON garmin_devices(user_id);
    CREATE UNIQUE INDEX IF NOT EXISTS garmin_devices_code ON garmin_devices(code) WHERE code IS NOT NULL;
    -- What the Garmin watch shows, published by the phone (the plan is built on the phone).
    CREATE TABLE IF NOT EXISTS garmin_snapshots (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    -- Sets, finished workouts and water from the Garmin watch, until the phone picks them up.
    CREATE TABLE IF NOT EXISTS garmin_inbox (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      data TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS garmin_inbox_user ON garmin_inbox(user_id, created_at);
    -- Paid model calls (coach chat, gym scan, food scan) across all members per UTC day: the global budget (quota.ts).
    CREATE TABLE IF NOT EXISTS ai_daily_usage (
      day TEXT PRIMARY KEY,
      count INTEGER NOT NULL
    );
    -- Workout chat (#381): messages per member per UTC day, for the daily cap (routes/coachChat.ts).
    CREATE TABLE IF NOT EXISTS coach_chat_usage (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      count INTEGER NOT NULL,
      PRIMARY KEY (user_id, day)
    );
    -- Machine setup notes (#355), private to the member (routes/machineNotes.ts).
    CREATE TABLE IF NOT EXISTS machine_notes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      gym_id TEXT NOT NULL,
      exercise_id TEXT NOT NULL,
      data TEXT NOT NULL,
      photo_id TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS machine_notes_user_updated ON machine_notes(user_id, updated_at);
    CREATE TABLE IF NOT EXISTS machine_note_photos (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      note_id TEXT NOT NULL,
      data BLOB NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS machine_note_photos_note ON machine_note_photos(user_id, note_id);
    -- Member problem reports (#467): private; screenshots never leave the server except by email to the team.
    CREATE TABLE IF NOT EXISTS member_reports (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      data TEXT NOT NULL,
      issue_number INTEGER,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS member_reports_user ON member_reports(user_id, created_at);
    CREATE TABLE IF NOT EXISTS member_report_shots (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      report_id TEXT NOT NULL,
      data BLOB NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS member_report_shots_report ON member_report_shots(user_id, report_id);
    -- Sync deletes (#432): ids a member deleted, so other devices drop them ('deleted' in since pulls) and a
    -- stale device can't upload them back. Purged after 180 days (purge.ts).
    CREATE TABLE IF NOT EXISTS sync_tombstones (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      item_id TEXT NOT NULL COLLATE NOCASE,
      deleted_at TEXT NOT NULL,
      PRIMARY KEY (user_id, kind, item_id)
    );
    CREATE INDEX IF NOT EXISTS sync_tombstones_deleted ON sync_tombstones(user_id, kind, deleted_at);
  `);
};
