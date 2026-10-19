import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { cleanScan } from '../src/coach/gymScan.ts';
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
    foodScan: async (_jpeg, catalog) => cleanScan(['egg', 'unicorn-steak', 'rice', 'egg'], catalog),
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
    expect(res.json()).toEqual({ items: ['rice', 'egg'], remainingToday: 19 });
    expect((db.prepare('SELECT count FROM food_scan_usage').get() as { count: number }).count).toBe(1);
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

  it('needs a signed-in member', async () => {
    expect((await app.inject({ method: 'POST', url: '/v1/me/food-scan', payload: { photo: jpeg, catalog } })).statusCode).toBe(401);
  });
});
