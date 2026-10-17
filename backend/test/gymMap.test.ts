import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { cleanScan } from '../src/coach/gymScan.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { agreement, consensus } from '../src/routes/gyms.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;
let scanned: string[];

beforeEach(() => {
  clock = new Date('2026-10-07T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  scanned = [];
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
    gymScan: async (_jpeg, catalog) => cleanScan(['rack', 'unicorn', 'bench', 'rack'], catalog).concat(scanned),
  });
});
afterEach(() => app.close());

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const send = (method: 'PUT' | 'POST', url: string, payload: object, token: string) => app.inject({ method, url, payload, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const gym = { id: 'map:47.37800,8.53000', name: 'Puls 5', latitude: 47.378, longitude: 8.53 };
const rect = { x: 0, y: 0, w: 0.5, h: 0.5 };
const plan = (benchIn: string) => ({
  zones: [
    { id: 'fw', name: 'Free weights', color: 0, items: benchIn === 'Free weights' ? ['rack', 'bench'] : ['rack'], rect },
    { id: 'm', name: 'Machines', color: 1, items: benchIn === 'Machines' ? ['leg-press', 'bench'] : ['leg-press'], rect: { ...rect, x: 0.5 } },
  ],
  door: { x: 0.5, y: 1 },
});
const mapsUrl = `/v1/gyms/maps?id=${encodeURIComponent(gym.id)}&name=${encodeURIComponent(gym.name)}`;

describe('Gym Map (#406)', () => {
  it('agreement compares where shared items sit, by zone name', () => {
    expect(agreement(plan('Free weights'), plan('Free weights'))).toBe(1);
    expect(agreement(plan('Free weights'), plan('Machines'))).toBeCloseTo(2 / 3);
    const c = consensus([
      { layout: plan('Machines'), updatedAt: '2026-10-01' },
      { layout: plan('Free weights'), updatedAt: '2026-10-02' },
      { layout: plan('Free weights'), updatedAt: '2026-10-03' },
    ])!;
    expect(c.layout.zones[0]!.items).toContain('bench');
    expect(c).toMatchObject({ members: 3 });
    expect(c.agreement).toBe(83);
  });

  it('shares the plan others agree with, never your own, and exports yours', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const c = await signUp('c@example.com');
    expect((await get(mapsUrl, c)).json()).toEqual({ map: null });
    expect((await send('PUT', '/v1/gyms/maps', { gym, layout: plan('Free weights') }, a)).statusCode).toBe(200);
    expect((await send('PUT', '/v1/gyms/maps', { gym, layout: plan('Machines') }, b)).statusCode).toBe(200);
    const seen = (await get(mapsUrl, c)).json() as { map: { members: number; agreement: number | null } };
    expect(seen.map).toMatchObject({ members: 2 });
    // a doesn't see their own plan: only b's.
    expect((await get(mapsUrl, a)).json()).toMatchObject({ map: { members: 1, agreement: null, layout: plan('Machines') } });
    expect((await send('PUT', '/v1/gyms/maps', { gym, layout: { zones: [] } }, a)).statusCode).toBe(400);
    const data = (await get('/v1/me/export', a)).json() as { gymMap: { maps: unknown[] } };
    expect(data.gymMap.maps).toHaveLength(1);
  });

  it('counts busy taps live and per hour on this weekday, once per member every 5 minutes', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const tap = (t: string) => send('POST', '/v1/gyms/busy', { gym: { id: gym.id }, zone: 'Free weights' }, t);
    await tap(a);
    await tap(a);
    await tap(b);
    const crowd = (await get(`/v1/gyms/crowd?id=${encodeURIComponent(gym.id)}&tz=120`, a)).json() as {
      now: { zone: string; reports: number }[];
      forecast: { zone: string; hours: number[] }[];
    };
    expect(crowd.now).toEqual([{ zone: 'free weights', reports: 2 }]);
    expect(crowd.forecast[0]!.hours[12]).toBe(2); // 10:00 UTC = 12:00 at +2 h
    clock = new Date(clock.getTime() + 30 * 60_000);
    const later = await signUp('c@example.com');
    expect(((await get(`/v1/gyms/crowd?id=${encodeURIComponent(gym.id)}`, later)).json() as { now: unknown[] }).now).toEqual([]);
  });

  it('scans a photo into known equipment ids and counts the scans', async () => {
    const a = await signUp('a@example.com');
    const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(200, 1)]).toString('base64');
    const catalog = [
      { id: 'bench', label: 'Bench' },
      { id: 'rack', label: 'Squat rack' },
    ];
    const res = await send('POST', '/v1/me/gym-scan', { photo: jpeg, catalog }, a);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ items: ['bench', 'rack'], remainingToday: 29 });
    const png = Buffer.alloc(200, 1).toString('base64');
    expect((await send('POST', '/v1/me/gym-scan', { photo: png, catalog }, a)).statusCode).toBe(400);
  });
});
