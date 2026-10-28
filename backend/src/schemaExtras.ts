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
    -- Weekly Coach review (#867): reviews per member per UTC day, for the daily cap (routes/coachReview.ts).
    CREATE TABLE IF NOT EXISTS coach_review_usage (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      count INTEGER NOT NULL,
      PRIMARY KEY (user_id, day)
    );
    -- AI usage (#877): paid model calls per UTC day, feature and model, no member ids (aiUsage.ts, admin ai-usage).
    CREATE TABLE IF NOT EXISTS ai_call_log (
      day TEXT NOT NULL,
      feature TEXT NOT NULL,
      model TEXT NOT NULL,
      calls INTEGER NOT NULL,
      failures INTEGER NOT NULL,
      input INTEGER NOT NULL,
      output INTEGER NOT NULL,
      cache_read INTEGER NOT NULL,
      cache_write INTEGER NOT NULL,
      PRIMARY KEY (day, feature, model)
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
  // Access tokens issued before this instant are refused (#712): set by password change / reset and logout-all.
  const userCols = db.prepare('PRAGMA table_info(users)').all() as { name: string }[];
  if (!userCols.some((c) => c.name === 'tokens_valid_after')) db.exec('ALTER TABLE users ADD COLUMN tokens_valid_after TEXT');
  // Separate push / lower loads (#792): the lowering (eccentric) kg of a set; null = same as the push.
  const logCols = db.prepare('PRAGMA table_info(workout_logs)').all() as { name: string }[];
  if (!logCols.some((c) => c.name === 'lower_kg')) db.exec('ALTER TABLE workout_logs ADD COLUMN lower_kg REAL');
  // The export lists records by their own instant, not their text (#714): `julianday()` reads any offset.
  db.exec(`
    CREATE INDEX IF NOT EXISTS logs_user_time ON workout_logs(user_id, julianday(date));
    CREATE INDEX IF NOT EXISTS workouts_user_time ON workouts(user_id, julianday(started_at));
    CREATE INDEX IF NOT EXISTS pr_attempts_user_time ON pr_attempts(user_id, julianday(date));
    CREATE INDEX IF NOT EXISTS body_measurements_user_time ON body_measurements(user_id, julianday(date));
    CREATE INDEX IF NOT EXISTS climbs_user_time ON climbs(user_id, julianday(start));
    CREATE INDEX IF NOT EXISTS sports_user_time ON sports(user_id, julianday(start));
  `);
  once(db, 'lowercase-sync-ids', lowercaseSyncIds);
};

/** Runs `fix` the first time a database starts with it, in one transaction (data fixes, unlike the schema above). */
const once = (db: DB, name: string, fix: (db: DB) => void): void => {
  db.exec('CREATE TABLE IF NOT EXISTS schema_fixes (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL)');
  if (db.prepare('SELECT 1 FROM schema_fixes WHERE name = ?').get(name)) return;
  db.exec('BEGIN IMMEDIATE');
  try {
    fix(db);
    db.prepare('INSERT INTO schema_fixes (name, applied_at) VALUES (?, ?)').run(name, new Date().toISOString());
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
};

/** Synced tables keyed by a client UUID (#714). */
export const SYNC_TABLES = ['workout_logs', 'workouts', 'climbs', 'sports', 'pr_attempts', 'body_measurements', 'custom_workouts', 'custom_exercises', 'machine_notes'];

/**
 * Sync ids are lower-cased on parse since #714; rows stored before keep the app's upper-case `uuidString`. Lower-case
 * them once so the next upload updates the row instead of adding a twin. Where both spellings exist for one member,
 * the newer row stays. Ids another account holds in lower case are left alone.
 */
const lowercaseSyncIds = (db: DB): void => {
  db.exec('PRAGMA defer_foreign_keys = ON');
  for (const t of SYNC_TABLES) {
    db.exec(`
      DELETE FROM ${t} WHERE id != lower(id) AND EXISTS
        (SELECT 1 FROM ${t} o WHERE o.id = lower(${t}.id) AND o.user_id = ${t}.user_id AND o.updated_at >= ${t}.updated_at);
      DELETE FROM ${t} WHERE id = lower(id) AND EXISTS
        (SELECT 1 FROM ${t} o WHERE o.id != lower(o.id) AND lower(o.id) = ${t}.id AND o.user_id = ${t}.user_id AND o.updated_at > ${t}.updated_at);
      UPDATE OR IGNORE ${t} SET id = lower(id) WHERE id != lower(id);
    `);
  }
  db.exec(`
    UPDATE OR IGNORE library_saves SET workout_id = lower(workout_id)
      WHERE workout_id != lower(workout_id) AND EXISTS (SELECT 1 FROM custom_workouts w WHERE w.id = lower(library_saves.workout_id));
    DELETE FROM library_saves WHERE NOT EXISTS (SELECT 1 FROM custom_workouts w WHERE w.id = library_saves.workout_id);
    UPDATE machine_note_photos SET note_id = lower(note_id) WHERE note_id != lower(note_id);
  `);
};
