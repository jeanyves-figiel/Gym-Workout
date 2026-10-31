import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { recipeFlags } from '../src/routes/recipeReviews.ts';

const PW = 'correct-horse-battery';
let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;
const clock = new Date('2026-10-31T10:00:00Z');

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
    now: () => clock,
  });
});
afterEach(() => app.close());

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const put = (url: string, payload: object, token: string) => app.inject({ method: 'PUT', url, payload, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

describe('recipe reviews (#1017)', () => {
  it('saves one review per member and recipe, summarises anonymously, flags wrong numbers', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    expect((await put('/v1/me/recipe-reviews/bircher-muesli', { stars: 5, numbers: 'right', cooking: 'easy' }, a)).statusCode).toBe(200);
    expect((await put('/v1/me/recipe-reviews/bircher-muesli', { stars: 3 }, a)).json().mine).toMatchObject({ stars: 3, numbers: null });
    const res = await put('/v1/me/recipe-reviews/bircher-muesli', { stars: 4, numbers: 'kcal-off' }, b);
    expect(res.json().summary).toEqual({ reviews: 2, stars: 3.5, rated: 2, valuesRight: 0, flagged: 1 });

    const list = (await get('/v1/recipe-reviews?ids=bircher-muesli,egg-white-omelette', a)).json();
    expect(list.summaries['bircher-muesli'].reviews).toBe(2);
    expect(list.summaries['egg-white-omelette']).toBeUndefined();
    expect(list.mine['bircher-muesli'].stars).toBe(3);
    expect(JSON.stringify(list)).not.toContain('@example.com');

    expect(recipeFlags(db)).toEqual([{ id: 'bircher-muesli', reason: 'kcal-off', count: 1, latest: clock.toISOString() }]);

    const exp = (await get('/v1/me/export', a)).json() as { recipeReviews: { recipeId: string }[] };
    expect(exp.recipeReviews.map((r) => r.recipeId)).toEqual(['bircher-muesli']);

    expect((await app.inject({ method: 'DELETE', url: '/v1/me/recipe-reviews/bircher-muesli', headers: auth(a) })).statusCode).toBe(204);
    expect((await get('/v1/recipe-reviews?ids=bircher-muesli', b)).json().summaries['bircher-muesli'].reviews).toBe(1);
  });

  it('rejects empty answers, unknown chips, own recipe ids and anonymous calls', async () => {
    const a = await signUp('a@example.com');
    expect((await put('/v1/me/recipe-reviews/bircher-muesli', {}, a)).statusCode).toBe(400);
    expect((await put('/v1/me/recipe-reviews/bircher-muesli', { numbers: 'tasty' }, a)).statusCode).toBe(400);
    expect((await put('/v1/me/recipe-reviews/bircher-muesli', { stars: 6 }, a)).statusCode).toBe(400);
    expect((await put('/v1/me/recipe-reviews/Own_Recipe', { stars: 4 }, a)).statusCode).toBe(400);
    expect((await app.inject({ method: 'GET', url: '/v1/recipe-reviews?ids=bircher-muesli' })).statusCode).toBe(401);
  });
});
