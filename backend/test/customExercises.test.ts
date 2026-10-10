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

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const sample = (id: string = randomUUID()) => ({
  id,
  name: 'Technogym abductor',
  createdAt: '2026-10-07T09:00:00Z',
  category: 'strength',
  primary: ['glutes'],
  secondary: [],
  equipment: [],
  machine: 'Technogym abductor',
  unit: 'reps',
  cues: ['Slow return'],
  archived: false,
});

const photo = Buffer.alloc(200_000, 7).toString('base64'); // ~267 KB base64

describe('custom exercises sync', () => {
  it('upserts, deltas, isolates, exports and archives custom exercises', async () => {
    const t = await signUp('maker@example.com');
    const e = { ...sample(), photo };
    expect((await post('/v1/me/custom-exercises', { exercises: [e] }, t)).json().saved).toBe(1);
    const all = (await get('/v1/me/custom-exercises', t)).json().exercises;
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ id: e.id, name: 'Technogym abductor', machine: 'Technogym abductor', photo });
    expect(all[0].updatedAt).toBe(clock.toISOString());

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    await post('/v1/me/custom-exercises', { exercises: [{ ...e, archived: true }] }, t);
    const delta = (await get(`/v1/me/custom-exercises?since=${encodeURIComponent(since)}`, t)).json().exercises;
    expect(delta).toHaveLength(1);
    expect(delta[0].archived).toBe(true);

    const t2 = await signUp('other@example.com');
    await post('/v1/me/custom-exercises', { exercises: [{ ...e, name: 'hijack' }] }, t2);
    expect((await get('/v1/me/custom-exercises', t2)).json().exercises).toHaveLength(0);
    expect((await get('/v1/me/custom-exercises', t)).json().exercises[0].name).toBe('Technogym abductor');
    expect((await get('/v1/me/export', t)).json().customExercises).toHaveLength(1);
  });

  it('rejects malformed or oversized custom exercises', async () => {
    const t = await signUp('maker@example.com');
    const bad = [{ id: 'nope', name: 'x' }, { ...sample(), name: ' ' }, { ...sample(), photo: 'not base64!' }];
    for (const e of bad) expect((await post('/v1/me/custom-exercises', { exercises: [e] }, t)).statusCode).toBe(400);
    expect((await post('/v1/me/custom-exercises', { exercises: [{ ...sample(), pose: 'x'.repeat(460_000) }] }, t)).statusCode).toBe(413);
    expect((await get('/v1/me/custom-exercises', t)).json().exercises).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: '/v1/me/custom-exercises' })).statusCode).toBe(401);
  });

  it('is removed with the account', async () => {
    const t = await signUp('maker@example.com');
    await post('/v1/me/custom-exercises', { exercises: [sample()] }, t);
    const res = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { password: PW, confirm: 'DELETE' }, headers: auth(t) });
    expect(res.statusCode).toBe(204);
    expect((db.prepare('SELECT COUNT(*) AS n FROM custom_exercises').get() as { n: number }).n).toBe(0);
  });
});
