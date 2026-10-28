import { afterEach, describe, expect, it } from 'vitest';
import { aiCallRecorder, aiUsageReport } from '../src/aiUsage.ts';
import { costUsd, onAiCall, tracked } from '../src/coach/models.ts';
import { openDb } from '../src/db.ts';

describe('AI usage (#877)', () => {
  afterEach(() => onAiCall(undefined));

  it('records each call per day, feature and model, failures too, and reports cost', async () => {
    const db = openDb(':memory:');
    let at = new Date('2026-10-27T10:00:00Z');
    onAiCall(aiCallRecorder(db, () => at));
    const usage = { input_tokens: 1000, output_tokens: 500, cache_read_input_tokens: 9000, cache_creation_input_tokens: 0 };
    await tracked('chat', 'claude-opus-5-5', async () => ({ usage }));
    await tracked('chat', 'claude-opus-5-5', async () => ({ usage }));
    await expect(tracked('gym-scan', 'claude-sonnet-5-5', async () => Promise.reject(new Error('down')))).rejects.toThrow('down');
    at = new Date('2026-10-28T08:00:00Z');
    await tracked('review', 'claude-opus-5-5', async () => ({ usage: { input_tokens: 2000, output_tokens: 800 } }));
    db.prepare('INSERT INTO ai_daily_usage (day, count) VALUES (?, ?)').run('2026-10-28', 1);

    const r = aiUsageReport(db, 7, at, 500);
    expect(r.rows.map((x) => [x.day, x.feature, x.calls, x.failures])).toEqual([
      ['2026-10-28', 'review', 1, 0],
      ['2026-10-27', 'chat', 2, 0],
      ['2026-10-27', 'gym-scan', 1, 1],
    ]);
    const chat = r.rows[1]!;
    expect(chat.input).toBe(2000);
    expect(chat.cacheHit).toBeCloseTo(0.9);
    expect(chat.costUsd).toBeCloseTo(costUsd('claude-opus-5-5', 2000, 1000, 18000, 0));
    expect(r.days[0]).toMatchObject({ day: '2026-10-28', calls: 1, capUsed: 1, cap: 500 });
    expect(r.totalUsd).toBeCloseTo(r.rows.reduce((s, x) => s + x.costUsd, 0));
    expect(aiUsageReport(db, 1, at, 500).rows).toHaveLength(1);
  });

  it('prices unknown models as the top model', () => {
    expect(costUsd('claude-next', 1_000_000, 0, 0, 0)).toBe(costUsd('claude-opus-5-5', 1_000_000, 0, 0, 0));
    expect(costUsd('claude-sonnet-5-5', 0, 1_000_000, 0, 0)).toBe(10);
  });
});
