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
  sport: 'snowboard',
  start: '2026-10-07T09:00:00Z',
  minutes: 240,
  effort: 7,
  distanceKm: 42.5,
  notes: null,
});

describe('sport sessions sync (#416)', () => {
  it('upserts, deltas, isolates, exports and deletes sessions; account delete removes them', async () => {
    const t = await signUp('rider@example.com');
    const a = sample();
    expect((await post('/v1/me/sports', { sports: [a] }, t)).json().saved).toBe(1);
    expect((await get('/v1/me/sports', t)).json().sports[0]).toMatchObject({ id: a.id, sport: 'snowboard', distanceKm: 42.5 });

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    const b = { ...sample(), sport: 'mountainBike' };
    await post('/v1/me/sports', { sports: [{ ...a, effort: 9 }, b] }, t);
    expect((await get(`/v1/me/sports?since=${encodeURIComponent(since)}`, t)).json().sports).toHaveLength(2);

    const t2 = await signUp('other@example.com');
    await post('/v1/me/sports', { sports: [{ ...a, effort: 1 }] }, t2);
    expect((await get('/v1/me/sports', t2)).json().sports).toHaveLength(0);
    expect((await del(`/v1/me/sports/${a.id}`, t2)).statusCode).toBe(204);
    expect((await get('/v1/me/sports', t)).json().sports).toHaveLength(2);

    expect((await get('/v1/me/export', t)).json().sports).toHaveLength(2);
    expect((await del(`/v1/me/sports/${a.id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/sports', t)).json().sports.map((x: { id: string }) => x.id)).toEqual([b.id]);

    db.prepare('DELETE FROM users').run();
    expect(db.prepare('SELECT COUNT(*) AS n FROM sports').get()).toEqual({ n: 0 });
  });

  it('rejects malformed sessions', async () => {
    const t = await signUp('rider@example.com');
    for (const c of [{ ...sample(), id: 'x' }, { ...sample(), effort: 0 }, { ...sample(), sport: '' }, { ...sample(), minutes: -5 }])
      expect((await post('/v1/me/sports', { sports: [c] }, t)).statusCode).toBe(400);
  });

  it('takes a Hyrox race straight from the Watch with its upload key (#426)', async () => {
    const t = await signUp('racer@example.com');
    const key1 = (await post('/v1/me/watch-key', {}, t)).json().key as string;
    const key = (await post('/v1/me/watch-key', {}, t)).json().key as string;
    expect(key).not.toBe(key1);
    const race = { ...sample(), sport: 'hyrox', minutes: 79, effort: 9, hyrox: { splits: [{ seconds: 239 }] } };
    const send = (k: string | undefined, payload: object = { sports: [race] }) =>
      app.inject({ method: 'POST', url: '/v1/watch/sports', payload, headers: k ? { 'x-watch-key': k } : {} });
    expect((await send(undefined)).statusCode).toBe(401);
    expect((await send(key1)).statusCode).toBe(401);
    expect((await send(key)).json().saved).toBe(1);
    expect((await get('/v1/me/sports', t)).json().sports[0]).toMatchObject({ id: race.id, sport: 'hyrox', hyrox: { splits: [{ seconds: 239 }] } });
    // The key only uploads sport sessions; it is no bearer token.
    expect((await app.inject({ method: 'GET', url: '/v1/me/sports', headers: { authorization: `Bearer ${key}` } })).statusCode).toBe(401);
    expect((await send(key, { sports: [{ ...race, effort: 0 }] })).statusCode).toBe(400);
    db.prepare('DELETE FROM users').run();
    expect(db.prepare('SELECT COUNT(*) AS n FROM watch_keys').get()).toEqual({ n: 0 });
  });
});
