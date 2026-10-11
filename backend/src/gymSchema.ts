import type { DB } from './db.ts';

/**
 * Gym memory (#162): each member's equipment list per gym, so the next member picking that gym (or another branch of
 * the same chain) starts from what others found there. Only counts are shared, never who reported. Rows cascade with
 * the user.
 */
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
  `);
};
