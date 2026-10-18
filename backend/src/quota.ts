import type { DB } from './db.ts';

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
