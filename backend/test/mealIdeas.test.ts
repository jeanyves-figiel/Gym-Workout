import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type MealIdeasAsk, cleanMealIdeas } from '../src/coach/mealIdeas.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;
let asked: MealIdeasAsk | undefined;
let fail = false;

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  asked = undefined;
  fail = false;
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-10-28T18:00:00Z'),
    mealIdeas: async (ask) => {
      asked = ask;
      if (fail) throw new Error('model down');
      return cleanMealIdeas(
        [
          { name: 'Eggs, feta & spinach wrap', minutes: 15, foods: [{ id: 'egg', grams: 150 }, { id: 'feta', grams: 40 }], steps: ['Whisk eggs', 'Fold into wrap'] },
          { name: 'Unicorn stew', minutes: 30, foods: [{ id: 'unicorn', grams: 200 }], steps: ['Catch it'] },
          { name: 'Chicken rice bowl', minutes: 20, foods: [{ id: 'chicken-breast', grams: 180 }, { id: 'rice', grams: 70 }], steps: [] },
        ],
        ask.pantry,
      );
    },
  });
});
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const pantry = [
  { id: 'egg', label: 'Eggs' },
  { id: 'feta', label: 'Feta' },
  { id: 'chicken-breast', label: 'Chicken breast' },
  { id: 'rice', label: 'Rice (dry)' },
];
const ask = (token: string, payload: object = { pantry, meal: 'dinner', left: { protein: 42, carbs: 80 }, diet: 'omnivore', avoid: ['nuts'] }) =>
  app.inject({ method: 'POST', url: '/v1/me/meal-ideas', payload, headers: { authorization: `Bearer ${token}` } });

describe('Meal ideas (#869)', () => {
  it('answers pantry-only ideas with grams and steps, and counts the calls', async () => {
    const token = await signUp('cook@example.com');
    const res = await ask(token);
    expect(res.statusCode).toBe(200);
    const body = res.json() as { ideas: { name: string; foods: { id: string }[] }[]; remainingToday: number };
    expect(body.ideas.map((i) => i.name)).toEqual(['Eggs, feta & spinach wrap', 'Chicken rice bowl']);
    expect(body.ideas[1]!.foods).toEqual([{ id: 'chicken-breast', grams: 180 }, { id: 'rice', grams: 70 }]);
    expect(body.remainingToday).toBe(19);
    expect(asked).toMatchObject({ meal: 'dinner', left: { protein: 42, carbs: 80 }, diet: 'omnivore', avoid: ['nuts'] });
  });

  it('gives the slot back when the model fails', async () => {
    const token = await signUp('cook2@example.com');
    fail = true;
    expect((await ask(token)).statusCode).toBe(502);
    fail = false;
    expect((await ask(token)).json().remainingToday).toBe(19);
  });

  it('stops at the daily cap', async () => {
    const token = await signUp('cook3@example.com');
    for (let i = 0; i < 20; i++) expect((await ask(token)).statusCode).toBe(200);
    const res = await ask(token);
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
  });

  it('rejects a bad body and needs sign-in', async () => {
    const token = await signUp('cook4@example.com');
    expect((await ask(token, { pantry: [], meal: 'dinner', left: { protein: 10, carbs: 10 } })).statusCode).toBe(400);
    expect((await ask(token, { pantry, meal: 'brunch', left: { protein: 10, carbs: 10 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/v1/me/meal-ideas', payload: { pantry, meal: 'lunch', left: { protein: 1, carbs: 1 } } })).statusCode).toBe(401);
  });
});

describe('cleanMealIdeas', () => {
  it('keeps pantry foods once, clamps grams and minutes, caps at 3', () => {
    const raw = [
      { name: '  A  ', minutes: 999, foods: [{ id: 'egg', grams: 5000 }, { id: 'egg', grams: 10 }, { id: 'x', grams: 10 }], steps: ['  one ', '', 'two'] },
      { name: 'B', minutes: 5, foods: [{ id: 'rice', grams: 0.2 }], steps: [] },
      { name: 'C', minutes: 5, foods: [{ id: 'feta', grams: 30 }], steps: [] },
      { name: 'D', minutes: 5, foods: [{ id: 'feta', grams: 30 }], steps: [] },
    ];
    const out = cleanMealIdeas(raw, pantry);
    expect(out).toHaveLength(3);
    expect(out[0]).toEqual({ name: 'A', minutes: 180, foods: [{ id: 'egg', grams: 1000 }], steps: ['one', 'two'] });
    expect(out[1]!.foods).toEqual([{ id: 'rice', grams: 1 }]);
  });
});
