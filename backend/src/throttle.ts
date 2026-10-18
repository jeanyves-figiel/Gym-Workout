import type { DB } from './db.ts';

/**
 * Durable per-key counters for abuse limits that must hold across IPs and code rotations (#432):
 * codes issued per account, wrong guesses per account, mails per recipient. Rows expire with their window
 * (purge.ts). Keys are opaque strings such as `code:reset_password:<userId>` or `mail:<email>`.
 */
export const ensureThrottleSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS throttle_hits (
      key TEXT NOT NULL,
      at TEXT NOT NULL,
      expires_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS throttle_hits_key ON throttle_hits(key, at);
    CREATE INDEX IF NOT EXISTS throttle_hits_expires ON throttle_hits(expires_at);
  `);
};

/** Hits for `key` inside the last `windowMs`. */
export const throttleCount = (db: DB, key: string, windowMs: number, now: Date): number =>
  (db.prepare('SELECT COUNT(*) AS n FROM throttle_hits WHERE key = ? AND at > ?').get(key, new Date(now.getTime() - windowMs).toISOString()) as { n: number }).n;

export const throttleHit = (db: DB, key: string, windowMs: number, now: Date): void => {
  db.prepare('INSERT INTO throttle_hits (key, at, expires_at) VALUES (?, ?, ?)').run(
    key,
    now.toISOString(),
    new Date(now.getTime() + windowMs).toISOString(),
  );
};

/** Records a hit unless `max` is already reached; false when over the limit. */
export const throttleTake = (db: DB, key: string, max: number, windowMs: number, now: Date): boolean => {
  if (throttleCount(db, key, windowMs, now) >= max) return false;
  throttleHit(db, key, windowMs, now);
  return true;
};

export const throttleClear = (db: DB, key: string): void => {
  db.prepare('DELETE FROM throttle_hits WHERE key = ?').run(key);
};

// Shared limits.
export const HOUR = 3_600_000;
export const DAY = 86_400_000;
/** Codes mailed per account and purpose per hour. */
export const CODES_PER_HOUR = 5;
/** Wrong code / 2-step / password guesses per account and kind per day before it refuses until the window rolls. */
export const GUESSES_PER_DAY = 20;
/** Mails of one kind to one recipient per hour. */
export const MAILS_PER_HOUR = 3;
