import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type ReviewDigest, type ReviewModel, cleanReview, describeWeek } from '../src/coach/review.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let seen: ReviewDigest[] = [];

const digest: ReviewDigest = {
  weekOf: '2026-10-26',
  goal: 'strength',
  days: [
    { weekday: 1, title: 'Push', done: true, minutes: 62 },
    { weekday: 4, title: 'Legs', done: false },
  ],
  bests: ['Bench press 85 kg (was 82.5)'],
  sleepHours: 6.1,
  hrv: '−8 % vs usual',
  mood: 3.2,
  moodAbout: ['Work'],
  next: [
    { id: 'w2-push', weekday: 1, title: 'Push', lifts: [{ uid: 'a', name: 'Bench press', sets: 4 }] },
    { id: 'w2-legs', weekday: 4, title: 'Legs', lifts: [{ uid: 'c', name: 'Back squat', sets: 4 }] },
  ],
  offDays: [6],
};

const start = (opts: { review?: ReviewModel | null; env?: Record<string, string> } = {}) => {
  mailer = new ConsoleMailer(() => {});
  seen = [];
  const review: ReviewModel = async (d) => {
    seen.push(d);
    return cleanReview(
      {
        score: 140,
        headline: '1 of 2 done · 1 PR',
        summary: 'Bench went up. Thursday legs slipped again.',
        changes: [
          { kind: 'move', sessionId: 'w2-legs', weekday: 2, uid: 'x', label: 'Legs to Tue (you skip Thu)' },
          { kind: 'addSet', sessionId: 'w2-push', weekday: 3, uid: 'zz', label: 'Unknown lift' },
          { kind: 'lighter', sessionId: 'nope', weekday: null, uid: null, label: 'Unknown workout' },
          { kind: 'addSet', sessionId: 'w2-push', weekday: null, uid: 'a', label: '+1 set bench' },
        ],
      },
      d,
    );
  };
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...opts.env }),
    db: openDb(':memory:'),
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-11-01T18:00:00Z'),
    review: opts.review === null ? undefined : (opts.review ?? review),
  });
};
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};
const ask = (token: string, payload: object) =>
  app.inject({ method: 'POST', url: '/v1/me/coach-review', payload, headers: { authorization: `Bearer ${token}` } });

describe('weekly Coach review (#867)', () => {
  it('answers a cleaned review of the week', async () => {
    start();
    const t = await signUp('a@example.com');
    const res = await ask(t, { digest });
    expect(res.statusCode).toBe(200);
    const r = res.json();
    expect(r.weekOf).toBe('2026-10-26');
    expect(r.score).toBe(100);
    expect(r.changes).toEqual([
      { kind: 'move', sessionId: 'w2-legs', weekday: 2, uid: null, label: 'Legs to Tue (you skip Thu)' },
      { kind: 'addSet', sessionId: 'w2-push', weekday: null, uid: 'a', label: '+1 set bench' },
    ]);
    expect(seen[0]?.next).toHaveLength(2);
  });

  it('caps reviews per member per day', async () => {
    start();
    const t = await signUp('b@example.com');
    for (let i = 0; i < 3; i++) expect((await ask(t, { digest })).statusCode).toBe(200);
    const res = await ask(t, { digest });
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
  });

  it('gives the slot back when the model fails, is off without a key and checks the digest', async () => {
    start({
      review: async () => {
        throw new Error('down');
      },
    });
    const t = await signUp('c@example.com');
    expect((await ask(t, { digest })).statusCode).toBe(502);
    expect((await ask(t, { digest: { ...digest, weekOf: 'last week' } })).statusCode).toBe(400);
    await app.close();
    start({ review: null });
    const t2 = await signUp('d@example.com');
    expect((await ask(t2, { digest })).statusCode).toBe(503);
  });

  it('describes the week without identifiers', () => {
    const text = describeWeek(digest);
    expect(text).toContain('1 of 2 workouts done');
    expect(text).toContain('Thu Legs: missed');
    expect(text).toContain('id w2-legs, Thu (weekday 4), Legs: Back squat 4 sets (uid c)');
    expect(text).toContain('Sleep: 6.1 h');
    expect(text).toContain('Days off next week: Sat');
    expect(text).not.toContain('@');
  });

  it('is Pro once subscriptions are enforced', async () => {
    start({ env: { SUBSCRIPTIONS: 'enforced' } });
    const t = await signUp('e@example.com');
    expect((await ask(t, { digest })).statusCode).toBe(402);
  });
});
