import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import type { ApnsMessage } from '../src/push/apns.ts';

// Release integration check: one journey across every feature stream, two members, ending in account deletion.

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;
let pushes: ApnsMessage[];

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  pushes = [];
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    apns: async (m) => {
      pushes.push(m);
      return { ok: true, status: 200 };
    },
  });
});
afterEach(() => app.close());

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
const req = (method: Method, url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  const body = res.json() as { tokens: { accessToken: string }; user: { id: string } };
  return { t: body.tokens.accessToken, id: body.user.id };
};

const userRows = (userId: string) => {
  const tables = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as { name: string }[]).map((r) => r.name);
  let n = 0;
  for (const name of tables) {
    const cols = (db.prepare(`PRAGMA table_info(${name})`).all() as { name: string }[]).map((c) => c.name);
    if (cols.includes('user_id')) n += (db.prepare(`SELECT COUNT(*) AS c FROM ${name} WHERE user_id = ?`).get(userId) as { c: number }).c;
  }
  return n;
};

describe('release integration journey', () => {
  it('works across profile, exercises, library, PRs, community, push, export and deletion', async () => {
    const a = await signUp('climber@example.com');
    const b = await signUp('lifter@example.com');

    // Training profile (opaque, incl. climbing + away periods + plan inserts).
    const profile = { goal: 'climbing', climbs: true, away: [{ kind: 'travel', start: '2026-10-20', end: '2026-10-24' }], planInserts: [] };
    expect((await req('PUT', '/v1/me/profile', a.t, { data: profile })).statusCode).toBe(200);

    // Custom exercise, then a workout using it, shared with members.
    const exId = randomUUID();
    const ex = { id: exId, name: 'Hip abductor machine', createdAt: '2026-10-10T09:00:00Z', category: 'strength', primary: ['glutes'], secondary: [], equipment: [], unit: 'reps', cues: [], archived: false };
    expect((await req('POST', '/v1/me/custom-exercises', a.t, { exercises: [ex] })).json().saved).toBe(1);
    const wId = randomUUID().toUpperCase();
    const workout = { id: wId, name: 'Hip day', createdAt: '2026-10-10T09:00:00Z', visibility: 'members', items: [{ id: randomUUID(), exerciseId: `user-${exId}`, sets: 3, reps: 12, restSec: 60 }] };

    // Sharing needs a community profile.
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [workout] })).statusCode).toBeLessThan(500);
    for (const [u, nick] of [[a, 'monkey_a'], [b, 'lifter_b']] as const) {
      expect((await req('PUT', '/v1/community/me', u.t, { nickname: nick, acceptGuidelines: true, defaultVisibility: 'members' })).statusCode).toBe(200);
    }
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [workout] })).statusCode).toBe(200);

    // B finds it in the library and saves a copy.
    const lib = (await req('GET', '/v1/library/shared', b.t)).json() as { workouts: { id: string; author: { nickname: string } }[] };
    expect(lib.workouts.map((w) => w.id.toUpperCase())).toContain(wId);
    expect((await req('POST', `/v1/library/shared/${wId.toLowerCase()}/save`, b.t)).statusCode).toBeLessThan(300);

    // B follows A, registers a device; A sets a PR and announces it → B gets a push.
    expect((await req('PUT', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBeLessThan(300);
    expect((await req('PUT', '/v1/me/push-device', b.t, { token: 'b'.repeat(64), env: 'production', topic: 'Com.app.MonkeyWorkout', tz: 'Europe/Zurich' })).statusCode).toBe(200);
    const prId = randomUUID();
    const attempt = { id: prId, exerciseId: 'bench-press', date: '2026-10-10T09:00:00Z', kind: 'oneRepMax', kg: 92.5, reps: 1, success: true, isRecord: true };
    expect((await req('POST', '/v1/me/pr-attempts', a.t, { attempts: [attempt] })).statusCode).toBe(200);
    const ann = await req('POST', '/v1/me/achievements', a.t, { achievements: [{ id: `pr-${prId}`, type: 'pr', text: 'Bench press 92.5 kg' }] });
    expect(ann.statusCode).toBe(200);
    expect(pushes.length).toBe(1);

    // A shares the win, B cheers.
    const postId = randomUUID().toUpperCase();
    expect((await req('POST', '/v1/community/posts', a.t, { id: postId, kind: 'record', refId: `pr-${prId}`, payload: { title: 'Bench press', metric: { value: '92.5', unit: 'kg' } }, visibility: 'members' })).statusCode).toBeLessThan(300);
    expect((await req('PUT', `/v1/community/posts/${postId}/reactions/strong`, b.t)).statusCode).toBeLessThan(300);
    const feed = (await req('GET', '/v1/community/feed?scope=following', b.t)).json() as { posts: { id: string }[] };
    expect(feed.posts.map((p) => p.id.toUpperCase())).toContain(postId);

    // Notification prefs.
    const prefs = (await req('GET', '/v1/me/notification-prefs', b.t)).json() as { prefs: object };
    expect((await req('PUT', '/v1/me/notification-prefs', b.t, { prefs: prefs.prefs })).statusCode).toBe(200);

    // Export carries every stream's data.
    const expA = (await req('GET', '/v1/me/export', a.t)).json();
    expect(expA.profile).toBeTruthy();
    expect(expA.customExercises).toHaveLength(1);
    expect(expA.customWorkouts).toHaveLength(1);
    expect(expA.prAttempts).toHaveLength(1);
    expect(expA.community).toBeTruthy();
    const expB = (await req('GET', '/v1/me/export', b.t)).json();
    expect(expB.notifications.devices).toHaveLength(1);
    expect(expB.notifications.devices[0].token).not.toBe('b'.repeat(64));
    expect(expB.notifications.prefs).toBeTruthy();

    // B blocks A: follow removed, A's content gone from B's library and feed.
    expect((await req('POST', '/v1/community/blocks', b.t, { userId: a.id })).statusCode).toBeLessThan(300);
    expect(((await req('GET', '/v1/community/follows', b.t)).json() as { follows?: unknown[] }).follows ?? []).toHaveLength(0);
    const libAfter = (await req('GET', '/v1/library/shared', b.t)).json() as { workouts: { id: string }[] };
    expect(libAfter.workouts.map((w) => w.id.toUpperCase())).not.toContain(wId);

    // Account deletion leaves no rows for A anywhere.
    expect(userRows(a.id)).toBeGreaterThan(0);
    expect((await req('DELETE', '/v1/me', a.t, { password: PW, confirm: 'DELETE' })).statusCode).toBeLessThan(300);
    expect(userRows(a.id)).toBe(0);
    expect((await req('GET', '/v1/me', a.t)).statusCode).toBe(401);
  });

  it('a member who joins without choosing a visibility shares wins with followers (#90)', async () => {
    const a = await signUp('climber@example.com');
    const b = await signUp('lifter@example.com');
    for (const [u, nick] of [[a, 'monkey_a'], [b, 'lifter_b']] as const) {
      const res = await req('PUT', '/v1/community/me', u.t, { nickname: nick, acceptGuidelines: true });
      expect(res.statusCode).toBe(200);
      expect(res.json().profile.defaultVisibility).toBe('members');
    }
    expect((await req('PUT', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBeLessThan(300);
    expect((await req('PUT', '/v1/me/push-device', b.t, { token: 'b'.repeat(64), env: 'production', topic: 'Com.app.MonkeyWorkout', tz: 'Europe/Zurich' })).statusCode).toBe(200);
    const ann = await req('POST', '/v1/me/achievements', a.t, { achievements: [{ id: 'badge-first', type: 'badge', text: 'First workout' }] });
    expect(ann.statusCode).toBe(200);
    expect(pushes.length).toBe(1);

    // Choosing "Only me" afterwards stops the follower pushes.
    expect((await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_a', defaultVisibility: 'private' })).statusCode).toBe(200);
    await req('POST', '/v1/me/achievements', a.t, { achievements: [{ id: 'badge-second', type: 'badge', text: 'Ten workouts' }] });
    expect(pushes.length).toBe(1);
  });
});
