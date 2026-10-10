import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-07T10:00:00Z');
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

const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const post = (url: string, payload: object, token: string) => app.inject({ method: 'POST', url, payload, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });
const del = (url: string, token: string) => app.inject({ method: 'DELETE', url, headers: auth(token) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const sample = (id: string = randomUUID()) => ({
  id,
  name: 'Push day',
  createdAt: '2026-10-07T09:00:00Z',
  items: [
    { id: randomUUID(), exerciseId: 'bench-press', sets: 4, reps: 8, restSec: 120 },
    { id: randomUUID(), exerciseId: 'dips', sets: 3, reps: 10, restSec: 90, kcal: 40 },
  ],
});

describe('custom workouts sync', () => {
  it('upserts, deltas, isolates, exports and deletes custom workouts', async () => {
    const t = await signUp('builder@example.com');
    const w = sample();
    expect((await post('/v1/me/custom-workouts', { workouts: [w] }, t)).json().saved).toBe(1);
    const all = (await get('/v1/me/custom-workouts', t)).json().workouts;
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ id: w.id, name: 'Push day', items: [{ exerciseId: 'bench-press', sets: 4 }, { kcal: 40 }] });
    expect(all[0].updatedAt).toBe(clock.toISOString());

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    const other = sample();
    await post('/v1/me/custom-workouts', { workouts: [{ ...w, name: 'Push day v2' }, other] }, t);
    const delta = (await get(`/v1/me/custom-workouts?since=${encodeURIComponent(since)}`, t)).json().workouts;
    expect(delta).toHaveLength(2);
    expect(delta.find((x: { id: string }) => x.id === w.id).name).toBe('Push day v2');
    advance(1000);
    expect((await get(`/v1/me/custom-workouts?since=${encodeURIComponent(clock.toISOString())}`, t)).json().workouts).toHaveLength(0);

    // another user can neither overwrite nor see them
    const t2 = await signUp('other@example.com');
    await post('/v1/me/custom-workouts', { workouts: [{ ...w, name: 'hijack' }] }, t2);
    expect((await get('/v1/me/custom-workouts', t2)).json().workouts).toHaveLength(0);
    expect((await del(`/v1/me/custom-workouts/${w.id}`, t2)).statusCode).toBe(204);
    const mine = (await get('/v1/me/custom-workouts', t)).json().workouts;
    expect(mine).toHaveLength(2);
    expect(mine.find((x: { id: string }) => x.id === w.id).name).toBe('Push day v2');

    expect((await get('/v1/me/export', t)).json().customWorkouts).toHaveLength(2);
    expect((await del(`/v1/me/custom-workouts/${w.id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/custom-workouts', t)).json().workouts.map((x: { id: string }) => x.id)).toEqual([other.id]);
  });

  it('accepts uppercase UUIDs as sent by iOS', async () => {
    const t = await signUp('builder@example.com');
    const id = randomUUID().toUpperCase();
    expect((await post('/v1/me/custom-workouts', { workouts: [sample(id)] }, t)).statusCode).toBe(200);
    expect((await del(`/v1/me/custom-workouts/${id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/custom-workouts', t)).json().workouts).toHaveLength(0);
  });

  it('rejects malformed or oversized custom workouts', async () => {
    const t = await signUp('builder@example.com');
    const bad = [
      { id: 'nope', name: 'x', items: [] },
      { ...sample(), name: '  ' },
      { ...sample(), items: [{ exerciseId: '' }] },
      { id: randomUUID(), name: 'no items' },
    ];
    for (const w of bad) expect((await post('/v1/me/custom-workouts', { workouts: [w] }, t)).statusCode).toBe(400);
    const huge = { ...sample(), notes: 'x'.repeat(100_001) };
    expect((await post('/v1/me/custom-workouts', { workouts: [huge] }, t)).statusCode).toBe(413);
    expect((await get('/v1/me/custom-workouts', t)).json().workouts).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: '/v1/me/custom-workouts' })).statusCode).toBe(401);
  });

  it('is removed with the account', async () => {
    const t = await signUp('builder@example.com');
    await post('/v1/me/custom-workouts', { workouts: [sample()] }, t);
    expect((db.prepare('SELECT COUNT(*) AS n FROM custom_workouts').get() as { n: number }).n).toBe(1);
    const res = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { password: PW, confirm: 'DELETE' }, headers: auth(t) });
    expect(res.statusCode).toBe(204);
    expect((db.prepare('SELECT COUNT(*) AS n FROM custom_workouts').get() as { n: number }).n).toBe(0);
  });
});
