import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { cleanFoodScan } from '../src/coach/foodScan.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-10-19T10:00:00Z'),
    foodScan: async (_jpeg, catalog) =>
      cleanFoodScan(
        [
          { id: 'egg', name: 'Eggs', group: 'protein', sure: true, per100: { protein: 13, carbs: 1, fat: 10, kcal: 143 } },
          { id: 'unicorn-steak', name: 'Appenzeller Bier', group: 'drink', sure: true, alcohol: true, per100: { protein: 0.5, carbs: 3.4, fat: 0, kcal: 42 } },
          { id: 'rice', name: 'Rice', group: 'grain', sure: false, per100: { protein: 7, carbs: 78, fat: 1, kcal: 350 } },
          { id: 'egg', name: 'Eggs', group: 'protein', sure: true },
        ],
        catalog,
      ),
  });
});
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(200, 1)]).toString('base64');
const catalog = [
  { id: 'rice', label: 'Rice (dry)' },
  { id: 'egg', label: 'Eggs' },
  { id: 'milk', label: 'Milk' },
];
const scan = (token: string, photo = jpeg) =>
  app.inject({ method: 'POST', url: '/v1/me/food-scan', payload: { photo, catalog }, headers: { authorization: `Bearer ${token}` } });

describe('Food scan (#496)', () => {
  it('turns a photo into known food ids, in catalog order, and counts the scans', async () => {
    const a = await signUp('a@example.com');
    const res = await scan(a);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ items: ['rice', 'egg'], remainingToday: 19 });
    expect((db.prepare('SELECT count FROM food_scan_usage').get() as { count: number }).count).toBe(1);
  });

  it('stops every member once the global AI budget of the day is spent, without using up their own', async () => {
    const a = await signUp('a@example.com');
    expect((await scan(a)).statusCode).toBe(200);
    expect(db.prepare('SELECT count FROM ai_daily_usage WHERE day = ?').get('2026-10-19')).toEqual({ count: 1 });
    db.prepare('UPDATE ai_daily_usage SET count = 500').run();
    const res = await scan(a);
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
    expect((db.prepare('SELECT count FROM food_scan_usage').get() as { count: number }).count).toBe(1);
    expect(db.prepare('SELECT count FROM ai_daily_usage').get()).toEqual({ count: 500 });
  });

  it('needs a verified email or an account older than a day', async () => {
    const a = await signUp('a@example.com');
    db.prepare("UPDATE users SET email_verified_at = NULL, created_at = '2026-10-19T00:00:00.000Z'").run();
    const res = await scan(a);
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('verification_required');
    db.prepare("UPDATE users SET created_at = '2026-10-18T09:00:00.000Z'").run();
    expect((await scan(a)).statusCode).toBe(200);
  });

  it('rejects anything but a JPEG and stops at the daily cap', async () => {
    const a = await signUp('a@example.com');
    expect((await scan(a, Buffer.alloc(200, 1).toString('base64'))).statusCode).toBe(400);
    const userId = (db.prepare('SELECT id FROM users').get() as { id: string }).id;
    db.prepare("INSERT INTO food_scan_usage (user_id, day, count) VALUES (?, '2026-10-19', 20)").run(userId);
    const res = await scan(a);
    expect(res.statusCode).toBe(429);
    expect(res.json()).toMatchObject({ error: 'daily_limit' });
  });

  it('keeps foods not on the list as new foods instead of the nearest id, with sure/unsure (#573)', async () => {
    const a = await signUp('a@example.com');
    const found = (await scan(a)).json().found;
    expect(found).toEqual([
      { id: 'egg', name: 'Eggs', group: 'protein', sure: true, alcohol: false, per100: { protein: 13, carbs: 1, fat: 10, kcal: 143 } },
      { name: 'Appenzeller Bier', group: 'drink', sure: true, alcohol: true, per100: { protein: 0.5, carbs: 3.4, fat: 0, kcal: 42 } },
      { id: 'rice', name: 'Rice (dry)', group: 'grain', sure: false, alcohol: false, per100: { protein: 7, carbs: 78, fat: 1, kcal: 350 } },
    ]);
  });

  it('needs a signed-in member', async () => {
    expect((await app.inject({ method: 'POST', url: '/v1/me/food-scan', payload: { photo: jpeg, catalog } })).statusCode).toBe(401);
  });
});
