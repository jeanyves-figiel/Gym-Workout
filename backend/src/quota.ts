import type { DB } from './db.ts';
import { ApiError } from './errors.ts';

type UsageTable = 'coach_chat_usage' | 'gym_scan_usage' | 'food_scan_usage' | 'coach_review_usage' | 'meal_ideas_usage' | 'coach_set_usage' | 'coach_plan_usage';

/**
 * Takes one of `limit` daily slots before a paid model call (#432): atomic, so parallel requests can't all pass a
 * read-then-count check. The new count, or undefined when the day is full. Give it back with `refundDaily` on failure.
 */
export const reserveDaily = (db: DB, table: UsageTable, userId: string, day: string, limit: number): number | undefined => {
  if (limit <= 0) return undefined;
  const row = db
    .prepare(
      `INSERT INTO ${table} (user_id, day, count) VALUES (?, ?, 1)
       ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1 WHERE count < ?
       RETURNING count`,
    )
    .get(userId, day, limit) as { count: number } | undefined;
  return row?.count;
};

export const refundDaily = (db: DB, table: UsageTable, userId: string, day: string): void => {
  db.prepare(`UPDATE ${table} SET count = count - 1 WHERE user_id = ? AND day = ? AND count > 0`).run(userId, day);
};

/**
 * Global budget (`AI_DAILY_LIMIT`): one slot of the day's paid model calls across all members, so many accounts at
 * their own cap can't run up the bill. False when the day is spent.
 */
export const reserveGlobal = (db: DB, day: string, limit: number): boolean =>
  limit > 0 &&
  !!db
    .prepare('INSERT INTO ai_daily_usage (day, count) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET count = count + 1 WHERE count < ? RETURNING count')
    .get(day, limit);

export const refundGlobal = (db: DB, day: string): void => {
  db.prepare('UPDATE ai_daily_usage SET count = count - 1 WHERE day = ? AND count > 0').run(day);
};

/**
 * Member's slot then a global one (#432 + global budget). The member's new count, `member` when their day is full,
 * `all` when the global budget is (their slot is given back). Undo a taken pair with `refundAiCall`.
 */
export const reserveAiCall = (
  db: DB,
  table: UsageTable,
  userId: string,
  day: string,
  limit: number,
  globalLimit: number,
): number | 'member' | 'all' => {
  const count = reserveDaily(db, table, userId, day, limit);
  if (count === undefined) return 'member';
  if (!reserveGlobal(db, day, globalLimit)) {
    refundDaily(db, table, userId, day);
    return 'all';
  }
  return count;
};

export const refundAiCall = (db: DB, table: UsageTable, userId: string, day: string): void => {
  refundDaily(db, table, userId, day);
  refundGlobal(db, day);
};

/** Scans need a verified email, Sign in with Apple, or an account older than a day: throwaway sign-ups can't farm them. */
export const trustedAccount = (db: DB, userId: string, now: Date): boolean => {
  const u = db.prepare('SELECT email_verified_at, apple_sub, created_at FROM users WHERE id = ?').get(userId) as
    | { email_verified_at: string | null; apple_sub: string | null; created_at: string }
    | undefined;
  return !!u && (!!u.email_verified_at || !!u.apple_sub || u.created_at <= new Date(now.getTime() - 86_400_000).toISOString());
};

/** Per-member cap on model calls running at once; `enter` is false when the member already has `max` in flight. */
export const inFlight = (max: number) => {
  const running = new Map<string, number>();
  return {
    enter: (userId: string): boolean => {
      const n = running.get(userId) ?? 0;
      if (n >= max) return false;
      running.set(userId, n + 1);
      return true;
    },
    leave: (userId: string): void => {
      const n = (running.get(userId) ?? 1) - 1;
      if (n <= 0) running.delete(userId);
      else running.set(userId, n);
    },
  };
};

/**
 * Rows one member may keep per synced table (#432, lowered in #712): far above real use (a set logged every day for
 * decades, a workout a day for 27 years), low enough that one account can't fill the disk. Keys are table names; the
 * id column is what the upsert conflicts on. The account's bytes are capped too (`ACCOUNT_BYTES`).
 */
export const ROW_QUOTAS = {
  workout_logs: { idCol: 'id', max: 100_000 },
  workouts: { idCol: 'id', max: 10_000 },
  climbs: { idCol: 'id', max: 10_000 },
  sports: { idCol: 'id', max: 10_000 },
  pr_attempts: { idCol: 'id', max: 10_000 },
  body_measurements: { idCol: 'id', max: 10_000 },
  custom_workouts: { idCol: 'id', max: 500 },
  machine_notes: { idCol: 'id', max: 1_000 },
  gym_reports: { idCol: 'gym_id', max: 200 },
  gym_maps: { idCol: 'gym_id', max: 200 },
} as const;

export type QuotaTable = keyof typeof ROW_QUOTAS;

const quotaExceeded = (limit: number) => new ApiError(409, 'quota_exceeded', 'Storage limit reached for this kind of data.', { limit });

/**
 * Throws 409 `quota_exceeded` when writing `ids` would leave the member with more than the table's cap. Ids the
 * member already has don't count (updates are always allowed). Call inside the upsert's transaction.
 */
export const assertRowQuota = (db: DB, table: QuotaTable, userId: string, ids: readonly string[]): void => {
  const { idCol, max } = ROW_QUOTAS[table];
  const has = db.prepare(`SELECT 1 FROM ${table} WHERE user_id = ? AND ${idCol} = ?`);
  const fresh = new Set(ids.filter((id) => !has.get(userId, id))).size;
  if (!fresh) return;
  const { n } = db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id = ?`).get(userId) as { n: number };
  if (n + fresh > max) throw quotaExceeded(max);
};

/** Synced data a member may store in all (#712): JSON records, machine-note photos and set logs together. */
export const ACCOUNT_BYTES = 50 * 1024 * 1024;
/** Stored size counted per set log (fixed columns, no JSON). */
const LOG_ROW_BYTES = 120;
/** Tables of opaque JSON records (`data` column) that count towards `ACCOUNT_BYTES`. */
const DATA_TABLES = ['profiles', 'workouts', 'custom_workouts', 'custom_exercises', 'pr_attempts', 'body_measurements', 'climbs', 'sports', 'machine_notes'] as const;
export type DataTable = Exclude<(typeof DATA_TABLES)[number], 'profiles'>;

/** Bytes the member stores now (`octet_length` reads the record header only, not the value). */
export const accountBytes = (db: DB, userId: string): number => {
  const parts = [
    ...DATA_TABLES.map((t) => `(SELECT COALESCE(SUM(octet_length(data)), 0) FROM ${t} WHERE user_id = ?)`),
    '(SELECT COALESCE(SUM(octet_length(data)), 0) FROM machine_note_photos WHERE user_id = ?)',
    `(SELECT COUNT(*) * ${LOG_ROW_BYTES} FROM workout_logs WHERE user_id = ?)`,
  ];
  return (db.prepare(`SELECT ${parts.join(' + ')} AS n`).get(...parts.map(() => userId)) as { n: number }).n;
};

/**
 * Throws 409 `quota_exceeded` when writing `items` (id + the JSON to store) would take the account over
 * `ACCOUNT_BYTES`. Uploads that don't grow it (edits, smaller copies) always pass. Call inside the upsert's transaction.
 */
export const assertByteQuota = (db: DB, table: DataTable | 'machine_note_photos', userId: string, items: readonly { id: string; bytes: number }[]): void => {
  const idCol = table === 'machine_note_photos' ? 'note_id' : 'id';
  const old = db.prepare(`SELECT COALESCE(SUM(octet_length(data)), 0) AS n FROM ${table} WHERE user_id = ? AND ${idCol} = ?`);
  const ids = new Map(items.map((i) => [i.id, i.bytes]));
  let grow = 0;
  for (const [id, bytes] of ids) grow += bytes - (old.get(userId, id) as { n: number }).n;
  if (grow > 0 && accountBytes(db, userId) + grow > ACCOUNT_BYTES) throw quotaExceeded(ACCOUNT_BYTES);
};

/** 413 `too_large` for one record over its per-item cap (#714: a stable code instead of `bad_request`). */
export const assertItemSize = (json: string, max: number, what: string): void => {
  if (json.length > max) throw new ApiError(413, 'too_large', `${what} is too large.`, { limit: max });
};
