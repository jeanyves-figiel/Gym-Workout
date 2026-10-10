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

/** Push data for the account export (#69): preferences and registered devices (token shortened). */
export const pushExport = (db: DB, userId: string) => {
  const prefs = db.prepare('SELECT data FROM notification_prefs WHERE user_id = ?').get(userId) as { data: string } | undefined;
  const devices = db
    .prepare('SELECT token, env, topic, tz, created_at FROM push_devices WHERE user_id = ? ORDER BY created_at')
    .all(userId) as unknown as { token: string; env: string; topic: string; tz: string | null; created_at: string }[];
  return {
    prefs: prefs ? JSON.parse(prefs.data) : null,
    devices: devices.map((d) => ({ token: `${d.token.slice(0, 8)}…`, env: d.env, topic: d.topic, tz: d.tz, createdAt: d.created_at })),
  };
};
