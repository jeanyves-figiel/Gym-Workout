import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import type { ApnsMessage } from '../src/push/apns.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { CHALLENGE_DECK, deckOrder, deckWod, isMemberWeek, thursdayOf } from '../src/community/challenges.ts';
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
    // Unpair and invite again: no second ring the same day (#712), one the next day.
    await req('DELETE', `/v1/community/buddies/${tom.id}`, ana.t);
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await app.push.idle();
    expect(pushed).toHaveLength(2);
    await req('DELETE', `/v1/community/buddies/${tom.id}`, ana.t);
    db.prepare("UPDATE throttle_hits SET at = '2026-01-01T00:00:00.000Z' WHERE key LIKE 'buddy-push:%'").run(); // a day later
    await req('PUT', `/v1/community/buddies/${tom.id}`, ana.t);
    await app.push.idle();
    expect(pushed).toHaveLength(3);
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

/** Moves the clock to the Thursday of the first 2026 week whose deck card has `format` (not a member week). */
const weekWith = (format: string) => {
  for (let n = 1; n <= 52; n++) {
    const w = `2026-W${String(n).padStart(2, '0')}`;
    if (deckWod(w).wod.format === format && !isMemberWeek(w, isoWeek)) {
      clock = new Date(thursdayOf(w).getTime() + 10 * 3_600_000);
      return w;
    }
  }
  throw new Error(format);
};

describe('weekly challenge room', () => {
  it('keeps the best score, ranks, and shows who trains now', async () => {
    weekWith('amrap');
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

describe('week challenge deck + member weeks (#748)', () => {
  it('deals 60 WODs, none twice in a year, in 4 formats', () => {
    expect(CHALLENGE_DECK.length).toBeGreaterThanOrEqual(53);
    expect(new Set(CHALLENGE_DECK.map((w) => w.name)).size).toBe(CHALLENGE_DECK.length);
    expect(new Set(CHALLENGE_DECK.map((w) => w.format))).toEqual(new Set(['amrap', 'emom', 'fortime', 'tabata']));
    const names = Array.from({ length: 53 }, (_, i) => deckWod(`2026-W${String(i + 1).padStart(2, '0')}`).wod.name);
    expect(new Set(names).size).toBe(53);
    // Another year, another order.
    expect(deckOrder(2027)).not.toEqual(deckOrder(2026));
  });

  it('member weeks are the last ISO week of each month', () => {
    expect(isMemberWeek('2026-W43', isoWeek)).toBe(false);
    expect(isMemberWeek('2026-W44', isoWeek)).toBe(true);
    expect(Array.from({ length: 53 }, (_, i) => `2026-W${String(i + 1).padStart(2, '0')}`).filter((w) => isMemberWeek(w, isoWeek))).toHaveLength(12);
  });

  it('room shows the WOD, the teaser, history and the vote', async () => {
    const w = weekWith('emom');
    const ana = await join('ana@example.com', 'ana');
    const room = (await req('GET', '/v1/community/challenge', ana.t)).json();
    expect(room.wod).toMatchObject({ format: 'emom', memberWeek: false, by: null, deckSize: CHALLENGE_DECK.length });
    expect(room.wod.card).toBeGreaterThan(0);
    expect(room.next.week > w).toBe(true);
    expect(room.history).toHaveLength(4);
    expect(room.vote).toMatchObject({ finalists: [] });
    expect(isMemberWeek(room.vote.week, isoWeek)).toBe(true);
  });

  it('scores For time by time under the cap, above unfinished, tier first', async () => {
    const w = weekWith('fortime');
    const cap = deckWod(w).wod.minutes * 60;
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    const mia = await join('mia@example.com', 'mia');
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week: w, seconds: cap + 1 })).json()).toMatchObject({ error: 'over_cap' });
    await req('PUT', '/v1/community/challenge/score', ana.t, { week: w, seconds: cap - 60 });
    await req('PUT', '/v1/community/challenge/score', tom.t, { week: w, reps: 150 });
    await req('PUT', '/v1/community/challenge/score', mia.t, { week: w, seconds: cap - 30, tier: 'beast' });
    const board = (await req('GET', '/v1/community/challenge', ana.t)).json().leaderboard;
    expect(board.map((e: { nickname: string }) => e.nickname)).toEqual(['mia', 'ana', 'tom']);
    expect(board[0]).toMatchObject({ tier: 'beast', seconds: cap - 30 });
  });

  it('suggest → Coach check → approve → vote → the winner runs the member week', async () => {
    clock = new Date('2026-10-25T09:55:00Z'); // W43, Sunday; W44 is the member week.
    const ana = await join('ana@example.com', 'ana');
    const tom = await join('tom@example.com', 'tom');
    const bad = await req('POST', '/v1/community/challenge/suggestions', ana.t, { name: 'Nope', format: 'amrap', minutes: 12, moves: ['10 deadlifts', '10 burpees'] });
    expect(bad.json()).toMatchObject({ error: 'challenge_unsafe' });
    const tooMany = await req('POST', '/v1/community/challenge/suggestions', ana.t, { name: 'Nope', format: 'amrap', minutes: 12, moves: ['80 burpees', '10 sit-ups'] });
    expect(tooMany.json()).toMatchObject({ error: 'challenge_unsafe' });
    const a = await req('POST', '/v1/community/challenge/suggestions', ana.t, { name: 'Lemur Leap', format: 'amrap', minutes: 12, moves: ['10 Burpees', '15 air squats'] });
    expect(a.statusCode).toBe(201);
    expect(a.json().suggestion).toMatchObject({ status: 'pending', moves: ['10 burpees', '15 air squats'] });
    const b = (await req('POST', '/v1/community/challenge/suggestions', tom.t, { name: 'Tabata Ape', format: 'tabata', minutes: 4, moves: ['jump squats', 'push-ups'] })).json().suggestion;
    expect(b.minutes).toBe(8);
    const mine = (await req('GET', '/v1/community/challenge/suggestions', ana.t)).json();
    expect(mine.suggestions).toHaveLength(1);
    expect(mine.moves).toContain('burpees');

    // Pending ones aren't in the vote.
    expect((await req('PUT', '/v1/community/challenge/vote', ana.t, { suggestionId: b.id })).statusCode).toBe(400);
    const { reviewSuggestion } = await import('../src/community/challenges.ts');
    expect(reviewSuggestion(db, a.json().suggestion.id, 'approved', clock)).toBe(true);
    expect(reviewSuggestion(db, b.id, 'approved', new Date(clock.getTime() + 1000))).toBe(true);
    expect((await req('PUT', '/v1/community/challenge/vote', ana.t, { suggestionId: b.id })).json()).toMatchObject({ week: '2026-W44' });
    await req('PUT', '/v1/community/challenge/vote', tom.t, { suggestionId: b.id });
    const room = (await req('GET', '/v1/community/challenge', ana.t)).json();
    expect(room.vote.finalists.map((f: { name: string; votes: number }) => [f.name, f.votes])).toEqual([['Lemur Leap', 0], ['Tabata Ape', 2]]);
    expect(room.vote.finalists[1].mine).toBe(true);
    expect(room.next).toMatchObject({ week: '2026-W44', memberWeek: true });

    expect(room.vote.endsAt).toBe('2026-10-25T10:00:00.000Z');

    // Member week starts (UTC+14 first): Tabata Ape runs, by tom, and leaves the vote.
    clock = new Date('2026-10-25T10:05:00Z');
    const w44 = (await req('GET', '/v1/community/challenge?week=2026-W44', ana.t)).json();
    expect(w44.wod).toMatchObject({ name: 'Tabata Ape', format: 'tabata', memberWeek: true, by: { nickname: 'tom' } });
    expect(w44.vote.finalists.map((f: { name: string }) => f.name)).toEqual(['Lemur Leap']);
    expect(w44.vote.week).toBe('2026-W48');
    // Tabata scores reps.
    expect((await req('PUT', '/v1/community/challenge/score', ana.t, { week: '2026-W44', reps: 210 })).json()).toMatchObject({ rank: 1, reps: 210 });
    // A WOD that ran can't be withdrawn; a waiting one can.
    expect((await req('DELETE', `/v1/community/challenge/suggestions/${b.id}`, tom.t)).statusCode).toBe(404);
    expect((await req('DELETE', `/v1/community/challenge/suggestions/${a.json().suggestion.id}`, ana.t)).statusCode).toBe(204);
  });

  it('caps pending suggestions', async () => {
    const ana = await join('ana@example.com', 'ana');
    const body = { name: 'Again', format: 'emom', minutes: 10, moves: ['10 burpees', '10 sit-ups'] };
    for (let i = 0; i < 3; i++) expect((await req('POST', '/v1/community/challenge/suggestions', ana.t, body)).statusCode).toBe(201);
    expect((await req('POST', '/v1/community/challenge/suggestions', ana.t, body)).statusCode).toBe(409);
  });
});

