import { type AiCall, costUsd } from './coach/models.ts';
import type { DB } from './db.ts';

/**
 * AI usage (#877): every paid model call adds to one row per UTC day, feature and model (calls, failures, tokens), so
 * the owner sees what each AI feature costs and how close the day gets to `AI_DAILY_LIMIT`. No member ids.
 */
export const aiCallRecorder = (db: DB, now: () => Date) => {
  const add = db.prepare(
    `INSERT INTO ai_call_log (day, feature, model, calls, failures, input, output, cache_read, cache_write)
     VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?)
     ON CONFLICT(day, feature, model) DO UPDATE SET calls = calls + 1, failures = failures + excluded.failures,
       input = input + excluded.input, output = output + excluded.output,
       cache_read = cache_read + excluded.cache_read, cache_write = cache_write + excluded.cache_write`,
  );
  return (c: AiCall) => {
    try {
      add.run(now().toISOString().slice(0, 10), c.feature, c.model, c.ok ? 0 : 1, c.input, c.output, c.cacheRead, c.cacheWrite);
    } catch {
      // Recording never breaks the member's call.
    }
  };
};

export interface AiUsageRow {
  day: string;
  feature: string;
  model: string;
  calls: number;
  failures: number;
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  /** Share of input tokens read from the cache, 0–1. */
  cacheHit: number;
  costUsd: number;
}

/** Last `days` UTC days, newest first, then by cost; plus the day totals and the global cap use. */
export const aiUsageReport = (db: DB, days: number, now: Date, dailyLimit: number) => {
  const from = new Date(now.getTime() - (Math.max(1, days) - 1) * 86_400_000).toISOString().slice(0, 10);
  const raw = db
    .prepare(
      `SELECT day, feature, model, calls, failures, input, output, cache_read AS cacheRead, cache_write AS cacheWrite
       FROM ai_call_log WHERE day >= ? ORDER BY day DESC`,
    )
    .all(from) as Omit<AiUsageRow, 'cacheHit' | 'costUsd'>[];
  const rows: AiUsageRow[] = raw
    .map((r) => {
      const all = r.input + r.cacheRead + r.cacheWrite;
      return { ...r, cacheHit: all ? r.cacheRead / all : 0, costUsd: costUsd(r.model, r.input, r.output, r.cacheRead, r.cacheWrite) };
    })
    .sort((a, b) => b.day.localeCompare(a.day) || b.costUsd - a.costUsd);
  const cap = new Map(
    (db.prepare('SELECT day, count FROM ai_daily_usage WHERE day >= ?').all(from) as { day: string; count: number }[]).map((r) => [r.day, r.count]),
  );
  const byDay = new Map<string, { day: string; calls: number; failures: number; costUsd: number; capUsed: number; cap: number }>();
  for (const r of rows) {
    const d = byDay.get(r.day) ?? { day: r.day, calls: 0, failures: 0, costUsd: 0, capUsed: cap.get(r.day) ?? 0, cap: dailyLimit };
    d.calls += r.calls;
    d.failures += r.failures;
    d.costUsd += r.costUsd;
    byDay.set(r.day, d);
  }
  return { rows, days: [...byDay.values()], totalUsd: rows.reduce((s, r) => s + r.costUsd, 0) };
};
