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

const put = (url: string, payload: object, token: string) => app.inject({ method: 'PUT', url, payload, headers: auth(token) });
const watch = (method: 'GET' | 'POST', url: string, token?: string, payload?: object) =>
  app.inject({ method, url, payload, headers: token ? { 'x-garmin-token': token } : {} });

const pairWatch = async () => {
  const res = await app.inject({ method: 'POST', url: '/v1/garmin/pair', payload: { model: 'fenix 8' } });
  expect(res.statusCode).toBe(200);
  return res.json() as { token: string; code: string };
};

describe('Garmin watches (#550)', () => {
  it('pairs with a code, serves the snapshot, queues events for the phone, unpairs', async () => {
    const t = await signUp('garmin@example.com');
    const w = await pairWatch();
    expect(w.code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect((await watch('GET', '/v1/garmin/snapshot', w.token)).json()).toMatchObject({ paired: false, code: w.code });
    expect((await watch('GET', '/v1/garmin/snapshot')).statusCode).toBe(401);
    expect((await watch('POST', '/v1/garmin/events', w.token, { events: [] })).statusCode).toBe(403);

    expect((await post('/v1/me/garmin/claim', { code: 'ZZZZZZ' }, t)).statusCode).toBe(404);
    const claim = await post('/v1/me/garmin/claim', { code: w.code.toLowerCase() }, t);
    expect(claim.json()).toMatchObject({ model: 'fenix 8' });
    // A code works once.
    expect((await post('/v1/me/garmin/claim', { code: w.code }, t)).statusCode).toBe(404);

    expect((await watch('GET', '/v1/garmin/snapshot', w.token)).json()).toMatchObject({ paired: true, snapshot: null });
    await put('/v1/me/garmin/snapshot', { snapshot: { v: 1, next: 's1', sessions: [{ id: 's1', title: 'Push' }] } }, t);
    expect((await watch('GET', '/v1/garmin/snapshot', w.token)).json().snapshot).toMatchObject({ next: 's1' });

    const events = [
      { id: 'e1-aaaaaaaa', type: 'set', sessionId: 's1', exerciseId: 'bench', setIndex: 0, kg: 60, reps: 8 },
      { id: 'e2-aaaaaaaa', type: 'water', glasses: 1 },
    ];
    expect((await watch('POST', '/v1/garmin/events', w.token, { events })).json().saved).toBe(2);
    // Resent after a lost reply: not queued twice.
    expect((await watch('POST', '/v1/garmin/events', w.token, { events })).json().saved).toBe(0);
    expect((await watch('POST', '/v1/garmin/events', w.token, { events: [{ id: 'e3-aaaaaaaa', type: 'nope' }] })).statusCode).toBe(400);

    const inbox = (await get('/v1/me/garmin/inbox', t)).json().events as { id: string; type: string; kg?: number }[];
    expect(inbox.map((e) => e.type)).toEqual(['set', 'water']);
    expect(inbox[0]).toMatchObject({ kg: 60 });

    // Another member sees nothing and can't ack.
    const t2 = await signUp('other@example.com');
    expect((await get('/v1/me/garmin/inbox', t2)).json().events).toHaveLength(0);
    expect((await post('/v1/me/garmin/inbox/ack', { ids: inbox.map((e) => e.id) }, t2)).json().removed).toBe(0);
    expect((await post('/v1/me/garmin/inbox/ack', { ids: inbox.map((e) => e.id) }, t)).json().removed).toBe(2);
    expect((await get('/v1/me/garmin/inbox', t)).json().events).toHaveLength(0);

    const devices = (await get('/v1/me/garmin/devices', t)).json().devices as { id: string; lastSeen: string }[];
    expect(devices).toHaveLength(1);
    expect((await del(`/v1/me/garmin/devices/${devices[0]!.id}`, t2)).statusCode).toBe(204);
    expect((await get('/v1/me/garmin/devices', t)).json().devices).toHaveLength(1);
    expect((await del(`/v1/me/garmin/devices/${devices[0]!.id}`, t)).statusCode).toBe(204);
    expect((await watch('GET', '/v1/garmin/snapshot', w.token)).statusCode).toBe(401);
  });

  it('gives a fresh code once the old one ran out; account delete removes everything', async () => {
    const w = await pairWatch();
    advance(16 * 60_000);
    const t = await signUp('garmin@example.com');
    expect((await post('/v1/me/garmin/claim', { code: w.code }, t)).statusCode).toBe(404);
    const fresh = (await watch('GET', '/v1/garmin/snapshot', w.token)).json() as { code: string };
    expect(fresh.code).not.toBe(w.code);
    expect((await post('/v1/me/garmin/claim', { code: fresh.code }, t)).statusCode).toBe(200);
    await put('/v1/me/garmin/snapshot', { snapshot: { v: 1 } }, t);
    await watch('POST', '/v1/garmin/events', w.token, { events: [{ id: 'e1-aaaaaaaa', type: 'water' }] });
    db.prepare('DELETE FROM users').run();
    for (const table of ['garmin_devices', 'garmin_snapshots', 'garmin_inbox'])
      expect(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
  });
});
