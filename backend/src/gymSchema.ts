import type { DB } from './db.ts';

/**
 * Gym memory (#162): each member's equipment list per gym, so the next member picking that gym (or another branch of
 * the same chain) starts from what others found there. Gym Map (#406) adds floor plans, busy taps and scan usage. Only counts are shared, never who reported. Rows cascade with
 * the user.
 */
/** "Taken?" taps are kept this long (rush hours over 8 weeks); purge.ts deletes older ones. */
export const BUSY_KEEP_DAYS = 56;

export const ensureGymSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS gym_reports (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      gym_id TEXT NOT NULL,
      name TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      equipment TEXT NOT NULL,
      unsure TEXT NOT NULL DEFAULT '[]',
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, gym_id)
    );
    CREATE INDEX IF NOT EXISTS gym_reports_gym ON gym_reports(gym_id);
    -- Gym Map (#406): each member's floor plan per gym; others at the same gym start from the one most agree with.
    CREATE TABLE IF NOT EXISTS gym_maps (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      gym_id TEXT NOT NULL,
      name TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      layout TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, gym_id)
    );
    CREATE INDEX IF NOT EXISTS gym_maps_gym ON gym_maps(gym_id);
    -- "Taken?" taps (#406): live crowd and rush hours per zone, shared as counts only; pruned after 8 weeks.
    CREATE TABLE IF NOT EXISTS gym_busy (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      gym_id TEXT NOT NULL,
      zone TEXT NOT NULL,
      at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS gym_busy_gym ON gym_busy(gym_id, at);
    CREATE INDEX IF NOT EXISTS gym_busy_at ON gym_busy(at);
    -- Gym scan (#406): photos sent per member per day, for the daily limit (the photo itself is never kept).
    CREATE TABLE IF NOT EXISTS gym_scan_usage (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      count INTEGER NOT NULL,
      PRIMARY KEY (user_id, day)
    );
    -- Food scan (#496): fridge / receipt photos per member per day (the photo itself is never kept).
    CREATE TABLE IF NOT EXISTS food_scan_usage (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      count INTEGER NOT NULL,
      PRIMARY KEY (user_id, day)
    );
  `);
};
