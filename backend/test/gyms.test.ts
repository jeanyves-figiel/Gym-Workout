import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { chainOf } from '../src/routes/gyms.ts';
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

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const put = (url: string, payload: object, token: string) => app.inject({ method: 'PUT', url, payload, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });
const del = (url: string, token: string) => app.inject({ method: 'DELETE', url, headers: auth(token) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const holmes = { id: 'map:47.37800,8.53000', name: 'Holmes Place Europaallee', latitude: 47.378, longitude: 8.53 };
const known = (token: string, g: { id: string; name: string; latitude?: number; longitude?: number }) =>
  get(`/v1/gyms/known?id=${encodeURIComponent(g.id)}&name=${encodeURIComponent(g.name)}` + (g.latitude != null ? `&lat=${g.latitude}&lng=${g.longitude}` : ''), token);

describe('Gym memory (#162)', () => {
  it('chain names need more than generic words', () => {
    expect(chainOf('Holmes Place Europaallee', 'Holmes Place Bern')).toBe('holmes place');
    expect(chainOf('Basic-Fit Altstetten', 'Basic-Fit Oerlikon')).toBe('basic-fit');
    expect(chainOf('The Gym Zurich', 'The Gym Bern')).toBeNull();
    expect(chainOf('Fitness Center A', 'Fitness Center B')).toBeNull();
    expect(chainOf('Holmes Place', 'Holmes Place')).toBeNull();
  });

  it('finds the same place by a non-ASCII name; a name without words matches by id only (#432)', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const elan = { id: 'map:46.20000,6.14000', name: 'Élan Fitness', latitude: 46.2, longitude: 6.14 };
    await put('/v1/gyms/reports', { gym: elan, equipment: ['barbell'] }, a);
    expect((await known(b, { ...elan, id: 'map:46.20010,6.14010', name: 'élan fitness' })).json().place).toMatchObject({ members: 1 });
    expect((await known(b, { id: 'other', name: '!!!' })).json()).toEqual({ place: null, chain: null });
    expect((await known(b, { id: elan.id, name: '!!!' })).json().place).toMatchObject({ members: 1 });
  });

  it('tallies other members per place and per chain, never counting you, and exports and replaces your list', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const c = await signUp('c@example.com');
    const d = await signUp('d@example.com');

    expect((await known(a, holmes)).json()).toEqual({ place: null, chain: null });

    expect((await put('/v1/gyms/reports', { gym: holmes, equipment: ['barbell', 'rack', 'sled'], unsure: ['sled'] }, a)).statusCode).toBe(200);
    // Same place found by another search: id differs slightly, same name nearby.
    expect((await put('/v1/gyms/reports', { gym: { ...holmes, id: 'map:47.37810,8.53010', latitude: 47.3781 }, equipment: ['barbell', 'cable'] }, b)).statusCode).toBe(200);
    expect((await put('/v1/gyms/reports', { gym: { id: 'map:46.9,7.4', name: 'Holmes Place Bern', latitude: 46.9, longitude: 7.4 }, equipment: ['barbell', 'smith'] }, c)).statusCode).toBe(200);

    const forD = (await known(d, holmes)).json();
    expect(forD.place).toEqual({ members: 2, votes: { barbell: 2, rack: 1, cable: 1 }, equipment: ['barbell', 'cable', 'rack'] });
    expect(forD.chain).toMatchObject({ members: 1, equipment: ['barbell', 'smith'], name: 'holmes place', gyms: 1 });

    // Your own report isn't counted.
    expect((await known(a, holmes)).json().place).toMatchObject({ members: 1, equipment: ['barbell', 'cable'] });

    // A correction replaces the earlier list.
    await put('/v1/gyms/reports', { gym: holmes, equipment: ['barbell'] }, a);
    expect((await known(d, holmes)).json().place).toEqual({ members: 2, votes: { barbell: 2, cable: 1 }, equipment: ['barbell', 'cable'] });

    const exp = (await get('/v1/me/export', a)).json();
    expect(exp.gyms).toEqual([{ gymId: holmes.id, name: holmes.name, equipment: ['barbell'], unsure: [], updatedAt: expect.any(String) }]);

    expect((await del(`/v1/gyms/reports?id=${encodeURIComponent(holmes.id)}`, a)).statusCode).toBe(204);
    expect((await known(d, holmes)).json().place).toMatchObject({ members: 1 });

    expect((await put('/v1/gyms/reports', { gym: holmes, equipment: ['DROP TABLE'] }, a)).statusCode).toBe(400);
    expect((await app.inject({ method: 'GET', url: '/v1/gyms/known?id=x&name=y' })).statusCode).toBe(401);
  });

  it('one vote per member and place: a second id for the same place replaces the first (#712)', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    await put('/v1/gyms/reports', { gym: holmes, equipment: ['barbell'] }, a);
    clock = new Date(clock.getTime() + 1000);
    await put('/v1/gyms/reports', { gym: { ...holmes, id: 'map:47.37801,8.53001' }, equipment: ['rower'] }, a);
    // Rows stored before #712 (one member, two ids at one place) count once, with the latest.
    db.prepare("INSERT INTO gym_reports (user_id, gym_id, name, name_key, latitude, longitude, equipment, unsure, updated_at) SELECT user_id, 'map:47.37802,8.53002', name, name_key, latitude, longitude, '[\"cable\"]', '[]', '2026-01-01T00:00:00.000Z' FROM gym_reports").run();
    expect((db.prepare('SELECT COUNT(*) AS n FROM gym_reports').get() as { n: number }).n).toBe(2);
    expect((await known(b, holmes)).json().place).toEqual({ members: 1, votes: { rower: 1 }, equipment: ['rower'] });
  });

  it('takes the documented gym{lat, lon} as well as latitude/longitude and stores them (#714)', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const { latitude: lat, longitude: lon, ...rest } = holmes;
    expect((await put('/v1/gyms/reports', { gym: { ...rest, lat, lon }, equipment: ['barbell'] }, a)).json()).toEqual({ saved: true });
    expect(db.prepare('SELECT latitude, longitude, name_key FROM gym_reports').get()).toEqual({ latitude: lat, longitude: lon, name_key: 'holmes place europaallee' });
    // Same name nearby under another id: found because the place has coordinates.
    expect((await known(b, { ...holmes, id: 'map:47.37810,8.53010' })).json().place).toMatchObject({ members: 1 });
  });
});
