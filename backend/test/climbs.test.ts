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


const sample = (id: string = randomUUID().toUpperCase()) => ({
  id,
  kind: 'boulder',
  start: '2026-10-07T18:00:00Z',
  minutes: 90,
  effort: 7,
  topGrade: '6B+',
  notes: null,
});

describe('climbs sync (#312)', () => {
  it('upserts, deltas, isolates, exports and deletes climbs; account delete removes them', async () => {
    const t = await signUp('climber@example.com');
    const a = sample();
    expect((await post('/v1/me/climbs', { climbs: [a] }, t)).json().saved).toBe(1);
    expect((await get('/v1/me/climbs', t)).json().climbs[0]).toMatchObject({ id: a.id, topGrade: '6B+' });

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    const b = sample();
    await post('/v1/me/climbs', { climbs: [{ ...a, effort: 9 }, b] }, t);
    const delta = (await get(`/v1/me/climbs?since=${encodeURIComponent(since)}`, t)).json().climbs;
    expect(delta).toHaveLength(2);
    expect(delta.find((x: { id: string }) => x.id === a.id).effort).toBe(9);

    const t2 = await signUp('other@example.com');
    await post('/v1/me/climbs', { climbs: [{ ...a, effort: 1 }] }, t2);
    expect((await get('/v1/me/climbs', t2)).json().climbs).toHaveLength(0);
    expect((await del(`/v1/me/climbs/${a.id}`, t2)).statusCode).toBe(204);
    expect((await get('/v1/me/climbs', t)).json().climbs).toHaveLength(2);

    expect((await get('/v1/me/export', t)).json().climbs).toHaveLength(2);
    expect((await del(`/v1/me/climbs/${a.id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/climbs', t)).json().climbs.map((x: { id: string }) => x.id)).toEqual([b.id]);

    db.prepare('DELETE FROM users').run();
    expect(db.prepare('SELECT COUNT(*) AS n FROM climbs').get()).toEqual({ n: 0 });
  });

  it('rejects malformed climbs', async () => {
    const t = await signUp('climber@example.com');
    for (const c of [{ ...sample(), id: 'x' }, { ...sample(), effort: 11 }, { ...sample(), start: 'today' }, { ...sample(), minutes: -5 }])
      expect((await post('/v1/me/climbs', { climbs: [c] }, t)).statusCode).toBe(400);
  });
});
