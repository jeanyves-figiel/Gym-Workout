import type { DB } from '../db.ts';

/** Idempotent schema for push notifications (#69): APNs device tokens and per-user notification preferences. */
export const ensurePushSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS push_devices (
      token TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      env TEXT NOT NULL CHECK (env IN ('sandbox', 'production')),
      topic TEXT NOT NULL,
      tz TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS push_devices_user ON push_devices(user_id);
    CREATE TABLE IF NOT EXISTS achievement_announcements (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      achievement_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, achievement_id)
    );
    CREATE TABLE IF NOT EXISTS notification_prefs (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      data TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  `);
};
