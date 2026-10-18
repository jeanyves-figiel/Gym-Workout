import type { DB } from './db.ts';
import { ApiError } from './errors.ts';

type UsageTable = 'coach_chat_usage' | 'gym_scan_usage';

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
 * Rows one member may keep per synced table (#432): far above real use (a set logged every day for decades), low
 * enough that one account can't fill the disk. Keys are table names; the id column is what the upsert conflicts on.
 */
export const ROW_QUOTAS = {
  workout_logs: { idCol: 'id', max: 100_000 },
  workouts: { idCol: 'id', max: 20_000 },
  climbs: { idCol: 'id', max: 20_000 },
  sports: { idCol: 'id', max: 20_000 },
  pr_attempts: { idCol: 'id', max: 20_000 },
  body_measurements: { idCol: 'id', max: 20_000 },
  custom_workouts: { idCol: 'id', max: 500 },
  machine_notes: { idCol: 'id', max: 1_000 },
  gym_reports: { idCol: 'gym_id', max: 200 },
  gym_maps: { idCol: 'gym_id', max: 200 },
} as const;

export type QuotaTable = keyof typeof ROW_QUOTAS;

/**
 * Throws 413 `quota_exceeded` when writing `ids` would leave the member with more than the table's cap. Ids the
 * member already has don't count (updates are always allowed). Call inside the upsert's transaction.
 */
export const assertRowQuota = (db: DB, table: QuotaTable, userId: string, ids: readonly string[]): void => {
  const { idCol, max } = ROW_QUOTAS[table];
  const has = db.prepare(`SELECT 1 FROM ${table} WHERE user_id = ? AND ${idCol} = ?`);
  const fresh = new Set(ids.filter((id) => !has.get(userId, id))).size;
  if (!fresh) return;
  const { n } = db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id = ?`).get(userId) as { n: number };
  if (n + fresh > max) throw new ApiError(413, 'quota_exceeded', 'Storage limit reached for this kind of data.', { limit: max });
};
