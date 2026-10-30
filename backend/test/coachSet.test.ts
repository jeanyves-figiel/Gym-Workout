import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type SetContext, type SetTalkModel, cleanSetAnswer, describeSet } from '../src/coach/setTalk.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let seen: { question: string; context: SetContext }[] = [];

const context: SetContext = {
  exercise: 'Back squat',
  set: 3,
  sets: 4,
  kg: 100,
  reps: 5,
  step: 2.5,
  done: [
    { kg: 100, reps: 5, rir: 1 },
    { kg: 100, reps: 4, rir: 0 },
  ],
  lastTime: '97.5 kg × 5',
  restSec: 150,
  swaps: [{ id: 'leg-press', name: 'Leg press' }],
};

const start = (opts: { talk?: SetTalkModel | null; env?: Record<string, string> } = {}) => {
  mailer = new ConsoleMailer(() => {});
  seen = [];
  const talk: SetTalkModel = async (question, c) => {
    seen.push({ question, context: c });
    return cleanSetAnswer(
      {
        answer: '  Drop to 92.5 kg and brace harder.  ',
        actions: [
          { kind: 'weight', kg: 91, exerciseId: null, sec: null },
          { kind: 'weight', kg: 80, exerciseId: null, sec: null },
          { kind: 'swap', exerciseId: 'made-up', kg: null, sec: null },
          { kind: 'swap', exerciseId: 'leg-press', kg: null, sec: null },
          { kind: 'rest', sec: 120, kg: null, exerciseId: null },
        ],
      },
      c,
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
    setTalk: opts.talk === null ? undefined : (opts.talk ?? talk),
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
  app.inject({ method: 'POST', url: '/v1/me/coach-set', payload, headers: { authorization: `Bearer ${token}` } });

describe('talk to Coach mid-set (#874)', () => {
  it('answers with fixes that fit the set', async () => {
    start();
    const t = await signUp('a@example.com');
    const res = await ask(t, { question: 'Felt it in my lower back', context });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      answer: 'Drop to 92.5 kg and brace harder.',
      actions: [
        { kind: 'weight', kg: 90 },
        { kind: 'swap', exerciseId: 'leg-press' },
      ],
    });
    expect(seen[0]?.question).toBe('Felt it in my lower back');
  });

  it('caps questions per member per day', async () => {
    start();
    const t = await signUp('b@example.com');
    for (let i = 0; i < 30; i++) expect((await ask(t, { question: 'too heavy?', context })).statusCode).toBe(200);
    const res = await ask(t, { question: 'too heavy?', context });
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
  });

  it('gives the slot back when the model fails, is off without a key and checks the body', async () => {
    start({
      talk: async () => {
        throw new Error('down');
      },
    });
    const t = await signUp('c@example.com');
    expect((await ask(t, { question: 'too heavy?', context })).statusCode).toBe(502);
    expect((await ask(t, { question: '', context })).statusCode).toBe(400);
    await app.close();
    start({ talk: null });
    const t2 = await signUp('d@example.com');
    expect((await ask(t2, { question: 'too heavy?', context })).statusCode).toBe(503);
  });

  it('describes the set without identifiers', () => {
    const text = describeSet(context);
    expect(text).toContain('Back squat, set 3 of 4');
    expect(text).toContain('Coming set: 100 kg × 5');
    expect(text).toContain('Set 2 done: 100 kg × 4, 0 reps in reserve');
    expect(text).toContain('Swaps: Leg press (id leg-press)');
  });

  it('is Pro once subscriptions are enforced', async () => {
    start({ env: { SUBSCRIPTIONS: 'enforced' } });
    const t = await signUp('e@example.com');
    expect((await ask(t, { question: 'too heavy?', context })).statusCode).toBe(402);
  });
});
