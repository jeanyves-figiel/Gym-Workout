import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import type { ApnsMessage } from '../src/push/apns.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { isoWeek } from '../src/routes/live.ts';

/** Live group sessions (#626): gym buddies, live sets, cheers, weekly challenge room. */

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;
let pushed: ApnsMessage[];

beforeEach(() => {
  clock = new Date('2026-10-22T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  pushed = [];
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
    apns: async (m) => {
      pushed.push(m);
      return { status: 200 };
    },
  });
});
afterEach(() => app.close());

const req = (method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  return { t: j.tokens.accessToken, id: j.user.id };
};

const join = async (email: string, nickname: string) => {
  const u = await signUp(email);
  expect((await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true })).statusCode).toBe(200);
  return u;
};

const set = { title: 'Legs day', exercise: 'Squat', detail: '70 kg × 8', state: 'set' };

describe('iso week', () => {
  it('matches ISO 8601, across the year end', () => {
    expect(isoWeek(new Date('2026-10-22T10:00:00Z'))).toBe('2026-W43');
    expect(isoWeek(new Date('2027-01-01T00:00:00Z'))).toBe('2026-W53');
    expect(isoWeek(new Date('2025-12-29T00:00:00Z'))).toBe('2026-W01');
  });
});

describe('gym buddies', () => {
  it('pairs on both sides, then shows live sets and carries cheers', async () => {
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    expect((await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t)).json()).toEqual({ status: 'invited' });
    expect((await req('GET', '/v1/community/buddies', tom.t)).json().buddies[0]).toMatchObject({ nickname: 'ana', status: 'invites_you', live: null });
    // Not paired yet: no cheers.
    expect((await req('POST', `/v1/community/buddies/${ana.id}/cheers`, tom.t, { kind: 'fire' })).statusCode).toBe(404);
    expect((await req('PUT', `/v1/community/buddies/${ana.id}`, tom.t)).json()).toEqual({ status: 'paired' });

    expect((await req('PUT', '/v1/community/live', ana.t, set)).statusCode).toBe(204);
    const seen = (await req('GET', '/v1/community/buddies', tom.t)).json().buddies[0];
    expect(seen).toMatchObject({ status: 'paired', live: { exercise: 'Squat', detail: '70 kg × 8', state: 'set' } });

    expect((await req('POST', `/v1/community/buddies/${ana.id}/cheers`, tom.t, { kind: 'banana' })).statusCode).toBe(204);
    expect((await req('POST', `/v1/community/buddies/${ana.id}/cheers`, tom.t, { kind: 'cake' })).statusCode).toBe(400);
    const got = (await req('GET', '/v1/community/live/cheers', ana.t)).json();
    expect(got.cheers).toHaveLength(1);
    expect(got.cheers[0]).toMatchObject({ from: { nickname: 'tom' }, kind: 'banana' });
    expect((await req('GET', `/v1/community/live/cheers?after=${got.last}`, ana.t)).json().cheers).toEqual([]);

    // Stale live rows stop showing.
    clock = new Date(clock.getTime() + 11 * 60_000);
    expect((await req('GET', '/v1/community/buddies', tom.t)).json().buddies[0].live).toBeNull();
    expect((await req('GET', '/v1/community/live/cheers', ana.t)).json().cheers).toEqual([]);
  });

  it('keeps the live set from one buddy (#675)', async () => {
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await req('PUT', `/v1/community/buddies/${ana.id}`, tom.t);
    await req('PUT', '/v1/community/live', ana.t, set);
    expect((await req('GET', '/v1/community/buddies', ana.t)).json().buddies[0]).toMatchObject({ shareLive: true });
    expect((await req('PATCH', `/v1/community/buddies/${tom.id}`, ana.t, { shareLive: false })).json()).toEqual({ shareLive: false });
    expect((await req('GET', '/v1/community/buddies', ana.t)).json().buddies[0]).toMatchObject({ shareLive: false });
    expect((await req('GET', '/v1/community/buddies', tom.t)).json().buddies[0]).toMatchObject({ status: 'paired', live: null });
    await req('PATCH', `/v1/community/buddies/${tom.id}`, ana.t, { shareLive: true });
    expect((await req('GET', '/v1/community/buddies', tom.t)).json().buddies[0].live).toMatchObject({ exercise: 'Squat' });
    expect((await req('PATCH', `/v1/community/buddies/${ana.id}x`, ana.t, { shareLive: false })).statusCode).toBe(404);
  });

  it('pushes the invite, and the pairing back, once', async () => {
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    const device = (token: string) => ({ token, env: 'production', topic: 'Com.app.MonkeyWorkout', tz: 'Europe/Zurich' });
    await req('PUT', '/v1/me/push-device', ana.t, device('a'.repeat(64)));
    await req('PUT', '/v1/me/push-device', tom.t, device('b'.repeat(64)));
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await app.push.idle();
    expect(pushed).toHaveLength(1);
    expect(pushed[0]).toMatchObject({ token: 'b'.repeat(64), payload: { kind: 'buddy_invite', actorId: ana.id, actorName: 'ana' } });
    await req('PUT', `/v1/community/buddies/${ana.id}`, tom.t);
    await app.push.idle();
    expect(pushed).toHaveLength(2);
    expect(pushed[1]).toMatchObject({ token: 'a'.repeat(64), payload: { kind: 'buddy_invite', actorId: tom.id } });
    expect(JSON.stringify(pushed[1]!.payload)).toContain('tom is your gym buddy');
  });

  it('a block or leaving ends the pair', async () => {
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await req('PUT', `/v1/community/buddies/${ana.id}`, tom.t);
    expect((await req('POST', '/v1/community/blocks', ana.t, { userId: tom.id })).statusCode).toBe(204);
    expect((await req('GET', '/v1/community/buddies', tom.t)).json().buddies).toEqual([]);
    expect((await req('PUT', `/v1/community/buddies/${ana.id}`, tom.t)).statusCode).toBe(404);
    await req('DELETE', `/v1/community/blocks/${tom.id}`, ana.t);
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    expect((await req('DELETE', '/v1/community/me', ana.t)).statusCode).toBe(204);
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_buddies').get()).toEqual({ n: 0 });
  });

  it('needs a community profile and refuses yourself', async () => {
    const ana = await join('ana@example.com', 'ana');
    const solo = await signUp('solo@example.com');
    expect((await req('GET', '/v1/community/buddies', solo.t)).statusCode).toBe(403);
    expect((await req('PUT', '/v1/community/live', solo.t, set)).statusCode).toBe(403);
    expect((await req('PUT', `/v1/community/buddies/${ana.id}`, ana.t)).statusCode).toBe(400);
    expect((await req('PUT', `/v1/community/buddies/${solo.id}`, ana.t)).statusCode).toBe(404);
  });
});

describe('weekly challenge room', () => {
  it('keeps the best score, ranks, and shows who trains now', async () => {
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    const mia = await join('mia@example.com', 'mia');
    const week = isoWeek(clock);
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week, rounds: 8, reps: 12 })).json()).toMatchObject({ rank: 1, best: true });
    expect((await req('PUT', '/v1/community/challenge/score', tom.t, { week, rounds: 9, reps: 0 })).json()).toMatchObject({ rank: 1 });
    // A lower score keeps the best one.
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week, rounds: 7, reps: 0 })).json()).toMatchObject({ rounds: 8, reps: 12, rank: 2, best: false });
    await req('PUT', '/v1/community/live', mia.t, { ...set, challengeWeek: week });
    await req('PUT', '/v1/community/challenge/score', mia.t, { week, rounds: 8, reps: 0 });

    const room = (await req('GET', '/v1/community/challenge', ana.t)).json();
    expect(room).toMatchObject({ week, joined: 3, training: 1, me: { rank: 2, rounds: 8, reps: 12, me: true } });
    expect(room.leaderboard.map((e: { nickname: string }) => e.nickname)).toEqual(['tom', 'ana', 'mia']);
    expect(room.leaderboard[2].live).toBe(true);

    // Blocked members drop off the board.
    await req('POST', '/v1/community/blocks', ana.t, { userId: tom.id });
    expect((await req('GET', '/v1/community/challenge', ana.t)).json().leaderboard.map((e: { nickname: string }) => e.nickname)).toEqual(['ana', 'mia']);
  });

  it('refuses closed weeks', async () => {
    const ana = await join('ana@example.com', 'ana');
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week: '2026-W30', rounds: 5, reps: 0 })).statusCode).toBe(400);
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week: 'soon', rounds: 5, reps: 0 })).statusCode).toBe(400);
  });
});
