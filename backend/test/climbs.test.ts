import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { purgeExpired } from '../src/purge.ts';

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
  kind: 'boulder',
  start: '2026-10-07T18:00:00Z',
  minutes: 90,
  effort: 7,
  topGrade: '6B+',
  notes: null,
});

describe('climbs sync (#312)', () => {
  it('keeps the gym or crag of a climb (#832)', async () => {
    const t = await signUp('crag@example.com');
    const place = { id: 'custom:block', name: 'Block Factory', gymId: 'custom:block' };
    expect((await post('/v1/me/climbs', { climbs: [{ ...sample(), place }] }, t)).json().saved).toBe(1);
    expect((await get('/v1/me/climbs', t)).json().climbs[0].place).toEqual(place);
    expect((await post('/v1/me/climbs', { climbs: [{ ...sample(), place: { id: 'x', name: 'y'.repeat(200) } }] }, t)).statusCode).toBe(400);
  });

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

  it('since without milliseconds or with an offset, or equal to updated_at, keeps the rows of that moment (#432)', async () => {
    const t = await signUp('climber@example.com');
    clock = new Date('2026-10-07T10:00:00.300Z');
    const a = sample();
    await post('/v1/me/climbs', { climbs: [a] }, t);
    for (const since of ['2026-10-07T10:00:00Z', '2026-10-07T12:00:00+02:00', '2026-10-07T10:00:00.300Z'])
      expect((await get(`/v1/me/climbs?since=${encodeURIComponent(since)}`, t)).json().climbs.map((x: { id: string }) => x.id)).toEqual([a.id]);
    expect((await get(`/v1/me/climbs?since=${encodeURIComponent('2026-10-07T10:00:01Z')}`, t)).json().climbs).toEqual([]);
  });

  it('saved counts only rows written, not ids of another account (#432)', async () => {
    const t = await signUp('climber@example.com');
    const a = sample();
    await post('/v1/me/climbs', { climbs: [a] }, t);
    const t2 = await signUp('other@example.com');
    expect((await post('/v1/me/climbs', { climbs: [{ ...a, effort: 1 }, sample()] }, t2)).json().saved).toBe(1);
  });

  it('refuses new rows past the per-member quota, still allows updates (#432)', async () => {
    const t = await signUp('climber@example.com');
    const { id: userId } = db.prepare('SELECT id FROM users WHERE email = ?').get('climber@example.com') as { id: string };
    const fill = db.prepare('INSERT INTO climbs (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)');
    db.exec('BEGIN');
    for (let i = 0; i < 9_999; i++) fill.run(randomUUID(), userId, '2026-01-01T00:00:00Z', '{}', clock.toISOString());
    db.exec('COMMIT');
    const a = sample();
    const over = await post('/v1/me/climbs', { climbs: [a, sample()] }, t);
    expect(over.statusCode).toBe(409);
    expect(over.json()).toMatchObject({ error: 'quota_exceeded', limit: 10_000 });
    expect((await post('/v1/me/climbs', { climbs: [a] }, t)).json().saved).toBe(1);
    expect((await post('/v1/me/climbs', { climbs: [sample()] }, t)).json().error).toBe('quota_exceeded');
    expect((await post('/v1/me/climbs', { climbs: [{ ...a, effort: 9 }] }, t)).json().saved).toBe(1);
  });

  it('a delete reaches other devices as deleted; a re-upload (Undo) brings it back (#432)', async () => {
    const t = await signUp('climber@example.com');
    const a = sample();
    const b = sample();
    await post('/v1/me/climbs', { climbs: [a, b] }, t);
    advance(1000);
    const lastPullB = clock.toISOString();
    // Full pulls have no `deleted`; since pulls always do.
    expect((await get('/v1/me/climbs', t)).json().deleted).toBeUndefined();
    expect((await get(`/v1/me/climbs?since=${encodeURIComponent(lastPullB)}`, t)).json()).toMatchObject({ climbs: [], deleted: [] });

    advance(1000);
    expect((await del(`/v1/me/climbs/${a.id}`, t)).statusCode).toBe(204); // device A
    advance(1000);
    const pull = (await get(`/v1/me/climbs?since=${encodeURIComponent(lastPullB)}`, t)).json(); // device B
    expect(pull.deleted).toEqual([a.id]);
    expect(pull.climbs).toEqual([]);

    // Undo on device A re-uploads the same id (any letter case): it's back and no longer reported as deleted.
    advance(1000);
    expect((await post('/v1/me/climbs', { climbs: [{ ...a, id: a.id.toLowerCase() }] }, t)).json().saved).toBe(1);
    expect((await get(`/v1/me/climbs?since=${encodeURIComponent(lastPullB)}`, t)).json().deleted).toEqual([]);
    await del(`/v1/me/climbs/${a.id}`, t);
    advance(1000);

    // Later pulls don't repeat it; tombstones go after 180 days.
    expect((await get(`/v1/me/climbs?since=${encodeURIComponent(clock.toISOString())}`, t)).json().deleted).toEqual([]);
    purgeExpired(db, new Date(clock.getTime() + 181 * 86_400_000));
    expect(db.prepare('SELECT COUNT(*) AS n FROM sync_tombstones').get()).toEqual({ n: 0 });
  });

  it('asks for a full resync when since is older than the tombstone retention', async () => {
    const t = await signUp('climber@example.com');
    const old = new Date(clock.getTime() - 181 * 86_400_000).toISOString();
    const recent = new Date(clock.getTime() - 179 * 86_400_000).toISOString();
    for (const kind of ['climbs', 'logs', 'workouts']) {
      expect((await get(`/v1/me/${kind}?since=${encodeURIComponent(old)}`, t)).json()).toMatchObject({ deleted: [], fullResync: true });
      expect((await get(`/v1/me/${kind}?since=${encodeURIComponent(recent)}`, t)).json()).not.toHaveProperty('fullResync');
      expect((await get(`/v1/me/${kind}`, t)).json()).not.toHaveProperty('fullResync');
    }
  });

  it('returns a conflict instead of overwriting a newer server copy when baseUpdatedAt is sent', async () => {
    const t = await signUp('climber@example.com');
    const c = sample();
    await post('/v1/me/climbs', { climbs: [c] }, t);
    const base = (await get('/v1/me/climbs', t)).json().climbs[0].updatedAt as string;
    advance(1000);
    // device B edits without a base (older app): overwrites as before
    expect((await post('/v1/me/climbs', { climbs: [{ ...c, minutes: 120 }] }, t)).json()).toEqual({ saved: 1, serverTime: clock.toISOString() });
    const newer = clock.toISOString();
    advance(1000);
    // device A edited from the older copy: kept back, server copy returned; the other item is written
    const other = sample();
    const r = (await post('/v1/me/climbs', { climbs: [{ ...c, minutes: 30, baseUpdatedAt: base }, { ...other, baseUpdatedAt: base }] }, t)).json();
    expect(r.saved).toBe(1);
    expect(r.conflicts).toEqual([{ ...c, minutes: 120, updatedAt: newer }]);
    // from the current copy it goes through, and baseUpdatedAt is not stored
    const ok = (await post('/v1/me/climbs', { climbs: [{ ...c, minutes: 45, baseUpdatedAt: newer.replace('.000Z', 'Z') }] }, t)).json();
    expect(ok).toEqual({ saved: 1, serverTime: clock.toISOString() });
    const stored = (await get('/v1/me/climbs', t)).json().climbs.find((x: { id: string }) => x.id === c.id);
    expect(stored.minutes).toBe(45);
    expect(stored).not.toHaveProperty('baseUpdatedAt');

    // logs answer conflicts in the pull's shape
    const log = { id: randomUUID(), date: '2026-10-07T18:00:00Z', exerciseId: 'bench', weightKg: 60, reps: 8 };
    await post('/v1/me/logs', { logs: [log] }, t);
    const logBase = clock.toISOString();
    advance(1000);
    await post('/v1/me/logs', { logs: [{ ...log, reps: 10 }] }, t);
    const lr = (await post('/v1/me/logs', { logs: [{ ...log, reps: 5, baseUpdatedAt: logBase }] }, t)).json();
    expect(lr.saved).toBe(0);
    expect(lr.conflicts).toEqual([expect.objectContaining({ id: log.id, reps: 10, updatedAt: clock.toISOString() })]);
  });

  it('logs and workouts report deletes too (#432)', async () => {
    const t = await signUp('climber@example.com');
    const since = clock.toISOString();
    const log = { id: randomUUID(), date: '2026-10-07T18:00:00Z', exerciseId: 'bench', weightKg: 60, reps: 8 };
    const w = { id: randomUUID(), startedAt: '2026-10-07T18:00:00Z' };
    await post('/v1/me/logs', { logs: [log] }, t);
    await post('/v1/me/workouts', { workouts: [w] }, t);
    advance(1000);
    await del(`/v1/me/logs/${log.id}`, t);
    await del(`/v1/me/workouts/${w.id}`, t);
    expect((await get(`/v1/me/logs?since=${encodeURIComponent(since)}`, t)).json().deleted).toEqual([log.id]);
    expect((await get(`/v1/me/workouts?since=${encodeURIComponent(since)}`, t)).json().deleted).toEqual([w.id]);
    db.prepare('DELETE FROM users').run();
    expect(db.prepare('SELECT COUNT(*) AS n FROM sync_tombstones').get()).toEqual({ n: 0 });
  });

  it('rejects malformed climbs', async () => {
    const t = await signUp('climber@example.com');
    for (const c of [{ ...sample(), id: 'x' }, { ...sample(), effort: 11 }, { ...sample(), start: 'today' }, { ...sample(), minutes: -5 }])
      expect((await post('/v1/me/climbs', { climbs: [c] }, t)).statusCode).toBe(400);
  });

  it("lower-cases ids, so the app's upper-case uuidString never makes a twin or misses a delete (#714)", async () => {
    const t = await signUp('climber@example.com');
    const a = sample(randomUUID().toUpperCase());
    await post('/v1/me/climbs', { climbs: [a] }, t);
    await post('/v1/me/climbs', { climbs: [{ ...a, id: a.id.toLowerCase(), effort: 9 }] }, t);
    const all = (await get('/v1/me/climbs', t)).json().climbs;
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ id: a.id.toLowerCase(), effort: 9 });
    expect((await del(`/v1/me/climbs/${a.id}`, t)).statusCode).toBe(204);
    expect((await get('/v1/me/climbs', t)).json().climbs).toEqual([]);
  });

  it('pages with limit + nextCursor; without limit every row comes back as before (#712)', async () => {
    const t = await signUp('climber@example.com');
    const ids: string[] = [];
    for (let i = 0; i < 5; i++) {
      const c = sample();
      ids.push(c.id);
      await post('/v1/me/climbs', { climbs: [c] }, t);
      advance(1000);
    }
    const seen: string[] = [];
    let cursor: string | null = '';
    for (let page = 0; cursor !== null; page++) {
      const r: { climbs: { id: string }[]; nextCursor: string | null } = (await get(`/v1/me/climbs?limit=2${cursor ? `&cursor=${cursor}` : ''}`, t)).json();
      expect(r.climbs.length).toBe(page < 2 ? 2 : 1);
      seen.push(...r.climbs.map((c: { id: string }) => c.id));
      cursor = r.nextCursor;
    }
    expect(seen).toEqual(ids);
    const full = await get('/v1/me/climbs', t);
    expect(full.headers['content-type']).toContain('application/json');
    expect(full.json().climbs.map((c: { id: string }) => c.id)).toEqual(ids);
    expect(full.json()).not.toHaveProperty('nextCursor');
    expect((await get('/v1/me/climbs?limit=0', t)).statusCode).toBe(400);
    expect((await get('/v1/me/climbs?limit=2&cursor=bad', t)).json().error).toBe('invalid_request');
  });

  it('refuses uploads past the account byte quota, still allows edits that do not grow it (#712)', async () => {
    const t = await signUp('climber@example.com');
    const { id: userId } = db.prepare('SELECT id FROM users WHERE email = ?').get('climber@example.com') as { id: string };
    const big = 'x'.repeat(1024 * 1024);
    const fill = db.prepare('INSERT INTO workouts (id, user_id, started_at, data, updated_at) VALUES (?, ?, ?, ?, ?)');
    for (let i = 0; i < 50; i++) fill.run(randomUUID(), userId, '2026-01-01T00:00:00Z', big, clock.toISOString());
    const over = await post('/v1/me/climbs', { climbs: [sample()] }, t);
    expect(over.statusCode).toBe(409);
    expect(over.json()).toMatchObject({ error: 'quota_exceeded', limit: 50 * 1024 * 1024 });
    db.prepare('UPDATE workouts SET data = substr(data, 1, 1048000) WHERE rowid = (SELECT MIN(rowid) FROM workouts)').run();
    const a = sample();
    expect((await post('/v1/me/climbs', { climbs: [a] }, t)).json().saved).toBe(1);
    expect((await post('/v1/me/climbs', { climbs: [{ ...a, notes: 'x'.repeat(2000) }] }, t)).json().error).toBe('quota_exceeded');
    expect((await post('/v1/me/climbs', { climbs: [{ ...a, topGrade: null }] }, t)).json().saved).toBe(1);
  });

  it('keeps a live session with 300 goes, refuses one far bigger (#829)', async () => {
    const t = await signUp('climber@example.com');
    const go = (i: number) => ({ id: randomUUID(), grade: '6A+', result: i % 3 ? 'send' : 'fall', at: 1_800_000_000 + i * 60 });
    const live = { ...sample(), scale: 'font', attempts: Array.from({ length: 300 }, (_, i) => go(i)) };
    expect((await post('/v1/me/climbs', { climbs: [live] }, t)).json().saved).toBe(1);
    const back = (await get('/v1/me/climbs', t)).json().climbs[0];
    expect(back.attempts).toHaveLength(300);
    expect(back.attempts[1]).toMatchObject({ grade: '6A+', result: 'send' });
    const huge = { ...sample(), attempts: Array.from({ length: 600 }, (_, i) => go(i)) };
    expect((await post('/v1/me/climbs', { climbs: [huge] }, t)).statusCode).toBe(413);
  });

  it('exports climbs in time order whatever the offset of start (#714)', async () => {
    const t = await signUp('climber@example.com');
    const late = { ...sample(), start: '2026-10-07T11:00:00Z' };
    const early = { ...sample(), start: '2026-10-07T12:00:00+02:00' };
    await post('/v1/me/climbs', { climbs: [late, early] }, t);
    expect((await get('/v1/me/export', t)).json().climbs.map((c: { id: string }) => c.id)).toEqual([early.id, late.id]);
  });
});
