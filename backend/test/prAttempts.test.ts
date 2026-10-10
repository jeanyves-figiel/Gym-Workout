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
  exerciseId: 'bench-press',
  date: '2026-10-07T09:00:00Z',
  kind: 'oneRepMax',
  kg: 92.5,
  reps: 1,
  success: true,
  isRecord: true,
  previousBestKg: 90,
  sets: [{ kg: 40, reps: 8, warmup: true }],
});

describe('PR attempts sync', () => {
  it('upserts, deltas, isolates, exports and deletes attempts', async () => {
    const t = await signUp('lifter@example.com');
    const a = sample();
    expect((await post('/v1/me/pr-attempts', { attempts: [a] }, t)).json().saved).toBe(1);
    const all = (await get('/v1/me/pr-attempts', t)).json().attempts;
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ id: a.id, kg: 92.5, previousBestKg: 90, sets: [{ warmup: true }] });

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    const other = sample();
    await post('/v1/me/pr-attempts', { attempts: [{ ...a, kg: 95 }, other] }, t);
    const delta = (await get(`/v1/me/pr-attempts?since=${encodeURIComponent(since)}`, t)).json().attempts;
    expect(delta).toHaveLength(2);
    expect(delta.find((x: { id: string }) => x.id === a.id).kg).toBe(95);

    const t2 = await signUp('other@example.com');
    await post('/v1/me/pr-attempts', { attempts: [{ ...a, kg: 1 }] }, t2);
    expect((await get('/v1/me/pr-attempts', t2)).json().attempts).toHaveLength(0);
    expect((await del(`/v1/me/pr-attempts/${a.id}`, t2)).statusCode).toBe(204);
    expect((await get('/v1/me/pr-attempts', t)).json().attempts.find((x: { id: string }) => x.id === a.id).kg).toBe(95);

    expect((await get('/v1/me/export', t)).json().prAttempts).toHaveLength(2);
    expect((await del(`/v1/me/pr-attempts/${a.id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/pr-attempts', t)).json().attempts.map((x: { id: string }) => x.id)).toEqual([other.id]);
  });

  it('rejects malformed or oversized attempts', async () => {
    const t = await signUp('lifter@example.com');
    const bad = [
      { ...sample(), id: 'nope' },
      { ...sample(), kind: 'bestEver' },
      { ...sample(), kg: -1 },
      { ...sample(), reps: 1.5 },
      { ...sample(), exerciseId: '' },
      { ...sample(), date: 'yesterday' },
    ];
    for (const a of bad) expect((await post('/v1/me/pr-attempts', { attempts: [a] }, t)).statusCode).toBe(400);
    expect((await post('/v1/me/pr-attempts', { attempts: [{ ...sample(), notes: 'x'.repeat(20_001) }] }, t)).statusCode).toBe(413);
    expect((await get('/v1/me/pr-attempts', t)).json().attempts).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: '/v1/me/pr-attempts' })).statusCode).toBe(401);
  });

  it('is removed with the account', async () => {
    const t = await signUp('lifter@example.com');
    await post('/v1/me/pr-attempts', { attempts: [sample()] }, t);
    const res = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { password: PW, confirm: 'DELETE' }, headers: auth(t) });
    expect(res.statusCode).toBe(204);
    expect((db.prepare('SELECT COUNT(*) AS n FROM pr_attempts').get() as { n: number }).n).toBe(0);
  });
});
