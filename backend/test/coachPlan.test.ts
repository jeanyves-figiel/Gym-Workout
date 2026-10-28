import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type HelpAsk, type PlanSetupModel, cleanHelp, cleanPlan, describeHelp } from '../src/coach/planSetup.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let heard: string[] = [];

const help: HelpAsk = {
  step: 'How you train',
  options: [
    { id: 'strength', label: 'Strength' },
    { id: 'build', label: 'Hypertrophy' },
  ],
  so: ['Goal: climbing', '3 days'],
  question: 'What is hypertrophy?',
};

const fake: PlanSetupModel = {
  plan: async (text) => {
    heard.push(text);
    return cleanPlan({ goal: 'build', experience: 'beginner', sessions: 9, weekdays: [6, 2, 2, 9, 4, 1, 3], minutes: 50, climbs: false, climbDays: 3, protect: '  knee ', summary: 'Muscle and fat loss, 4 days.' });
  },
  help: async (h) => cleanHelp({ answer: 'Hypertrophy is 8–12 reps for size. For climbing pick Strength.', pick: 'strength' }, h),
};

const start = (opts: { model?: PlanSetupModel | null; env?: Record<string, string> } = {}) => {
  mailer = new ConsoleMailer(() => {});
  heard = [];
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...opts.env }),
    db: openDb(':memory:'),
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-11-01T18:00:00Z'),
    planSetup: opts.model === null ? undefined : (opts.model ?? fake),
  });
};
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};
const post = (token: string, url: string, payload: object) =>
  app.inject({ method: 'POST', url, payload, headers: { authorization: `Bearer ${token}` } });

describe('plan set-up with Coach (#873)', () => {
  it('turns one sentence into plan form values', async () => {
    start();
    const t = await signUp('a@example.com');
    const res = await post(t, '/v1/me/coach-plan', { text: 'Lose weight and build muscle, 4 days, home with dumbbells, bad knee' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      goal: 'build',
      experience: 'beginner',
      sessions: 6,
      weekdays: [1, 2, 3, 4, 6],
      minutes: 45,
      climbs: false,
      climbDays: null,
      protect: 'knee',
      summary: 'Muscle and fat loss, 4 days.',
    });
    expect(heard[0]).toContain('bad knee');
  });

  it('answers a form step with a pick from its options only', async () => {
    start();
    const t = await signUp('b@example.com');
    const res = await post(t, '/v1/me/coach-plan/help', help);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ answer: 'Hypertrophy is 8–12 reps for size. For climbing pick Strength.', pick: 'strength' });
    expect(cleanHelp({ answer: '', pick: 'endurance' }, help).pick).toBeNull();
    expect(describeHelp(help)).toContain('- build: Hypertrophy');
    expect(describeHelp(help)).toContain('So far: Goal: climbing; 3 days');
  });

  it('keeps unknown values on safe defaults', () => {
    const d = cleanPlan({ goal: 'yoga' as never, sessions: 0, weekdays: [], minutes: null, climbs: false, protect: ' ', summary: '' });
    expect(d).toMatchObject({ goal: 'balanced', experience: 'beginner', sessions: 3, minutes: null, protect: null });
    expect(cleanPlan({ goal: 'climbing', climbDays: 7 })).toMatchObject({ climbs: true, climbDays: 4 });
  });

  it('caps calls per member per day across both', async () => {
    start();
    const t = await signUp('c@example.com');
    for (let i = 0; i < 15; i++) expect((await post(t, i % 2 ? '/v1/me/coach-plan/help' : '/v1/me/coach-plan', i % 2 ? help : { text: '3 days strength' })).statusCode).toBe(200);
    const res = await post(t, '/v1/me/coach-plan', { text: '3 days strength' });
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
  });

  it('gives the slot back on failure, checks input, is off without a key and free with subscriptions on', async () => {
    start({
      model: {
        plan: async () => {
          throw new Error('down');
        },
        help: fake.help,
      },
      env: { SUBSCRIPTIONS: 'enforced' },
    });
    const t = await signUp('d@example.com');
    expect((await post(t, '/v1/me/coach-plan', { text: '4 days' })).statusCode).toBe(502);
    expect((await post(t, '/v1/me/coach-plan', { text: 'x'.repeat(501) })).statusCode).toBe(400);
    expect((await post(t, '/v1/me/coach-plan/help', { ...help, options: [] })).statusCode).toBe(400);
    expect((await post(t, '/v1/me/coach-plan/help', help)).statusCode).toBe(200);
    await app.close();
    start({ model: null });
    const t2 = await signUp('e@example.com');
    expect((await post(t2, '/v1/me/coach-plan', { text: '4 days' })).statusCode).toBe(503);
  });
});
