import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { cleanImport, type ImportAsk, sourceOf } from '../src/coach/workoutImport.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;
let asks: ImportAsk[];
let fetched: string[];

const catalog = [
  { id: 'hip-thrust', label: 'Barbell hip thrust' },
  { id: 'bulgarian-split-squat', label: 'Bulgarian split squat' },
  { id: 'glute-bridge', label: 'Glute bridge' },
];

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  asks = [];
  fetched = [];
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-10-29T10:00:00Z'),
    fetch: (async (url: string) => {
      fetched.push(String(url));
      return new Response(JSON.stringify({ title: 'Glute burner: hip thrust 4x12, frog pumps 2x30', author_unique_id: 'fitwithlea' }), { status: 200 });
    }) as typeof fetch,
    workoutImport: async (ask) => {
      asks.push(ask);
      return cleanImport(
        {
          name: '  Glute   burner ',
          minutes: 20,
          items: [
            { said: 'Hip thrust', id: 'hip-thrust', sets: 4, reps: 12, unit: 'reps', sure: true },
            { said: 'Frog pumps', id: 'glute-bridge', sets: 2, reps: 30, unit: 'reps', sure: false },
            { said: 'Moon walk', id: 'made-up', sets: 99, reps: 0, unit: 'reps', sure: true },
          ],
        },
        ask.catalog,
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

const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(200, 1)]).toString('base64');
const post = (token: string, payload: object) =>
  app.inject({ method: 'POST', url: '/v1/me/workout-import', payload: { catalog, ...payload }, headers: { authorization: `Bearer ${token}` } });

describe('Save a workout from a video (#909)', () => {
  it('reads a shared caption into catalog moves, keeps the clean link and counts the day', async () => {
    const a = await signUp('a@example.com');
    const res = await post(a, { link: 'https://www.instagram.com/reel/ABC123/?igsh=track', caption: 'Hip thrust 4x12' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      name: 'Glute burner',
      minutes: 20,
      items: [
        { said: 'Hip thrust', id: 'hip-thrust', sets: 4, reps: 12, unit: 'reps', sure: true },
        { said: 'Frog pumps', id: 'glute-bridge', sets: 2, reps: 30, unit: 'reps', sure: false },
        { said: 'Moon walk', id: '', sets: 20, reps: 1, unit: 'reps', sure: false },
      ],
      source: { platform: 'instagram', url: 'https://www.instagram.com/reel/ABC123/' },
      remainingToday: 19,
    });
    expect(asks[0]!.caption).toBe('Hip thrust 4x12');
    expect(fetched).toEqual([]);
    expect(db.prepare('SELECT count FROM workout_import_usage').get()).toEqual({ count: 1 });
  });

  it('takes a TikTok caption and creator from its public oEmbed when the share has only the link', async () => {
    const a = await signUp('a@example.com');
    const res = await post(a, { link: 'https://www.tiktok.com/@fitwithlea/video/123?is_from_webapp=1' });
    expect(res.statusCode).toBe(200);
    expect(fetched).toEqual([`https://www.tiktok.com/oembed?url=${encodeURIComponent('https://www.tiktok.com/@fitwithlea/video/123')}`]);
    expect(asks[0]!.caption).toContain('frog pumps');
    expect(res.json().source).toEqual({ platform: 'tiktok', url: 'https://www.tiktok.com/@fitwithlea/video/123', author: '@fitwithlea' });
  });

  it('asks for screenshots or words when an Instagram link has nothing to read, without using a slot', async () => {
    const a = await signUp('a@example.com');
    const res = await post(a, { link: 'https://instagram.com/reel/XYZ' });
    expect(res.statusCode).toBe(422);
    expect(res.json().error).toBe('nothing_to_read');
    expect(fetched).toEqual([]);
    expect(db.prepare('SELECT count FROM workout_import_usage').get()).toBeUndefined();
    const words = await post(a, { text: 'hip thrusts then split squats' });
    expect(words.statusCode).toBe(200);
    expect(words.json().source).toBeUndefined();
  });

  it('passes screenshots through and rejects non-JPEGs and bad links', async () => {
    const a = await signUp('a@example.com');
    expect((await post(a, { photos: [jpeg, jpeg] })).statusCode).toBe(200);
    expect(asks[0]!.photos).toHaveLength(2);
    expect((await post(a, { photos: [Buffer.alloc(200, 1).toString('base64')] })).json().error).toBe('bad_photo');
    expect((await post(a, { link: 'javascript:alert(1)', text: 'x' })).json().error).toBe('bad_link');
    expect((await post(a, { photos: [jpeg, jpeg, jpeg, jpeg, jpeg] })).statusCode).toBe(400);
  });

  it('stops at the daily cap', async () => {
    const a = await signUp('a@example.com');
    const userId = (db.prepare('SELECT id FROM users').get() as { id: string }).id;
    db.prepare("INSERT INTO workout_import_usage (user_id, day, count) VALUES (?, '2026-10-29', 20)").run(userId);
    const res = await post(a, { text: 'squats' });
    expect(res.statusCode).toBe(429);
    expect(res.json().error).toBe('daily_limit');
  });
});

describe('sourceOf', () => {
  it('names the platform and drops share tracking', () => {
    expect(sourceOf('https://vm.tiktok.com/ZMabc/')).toEqual({ platform: 'tiktok', url: 'https://vm.tiktok.com/ZMabc/' });
    expect(sourceOf('https://www.youtube.com/watch?v=abc&si=x')).toEqual({ platform: 'youtube', url: 'https://www.youtube.com/watch?v=abc' });
    expect(sourceOf('https://youtu.be/abc?si=x')).toEqual({ platform: 'youtube', url: 'https://youtu.be/abc' });
    expect(sourceOf('https://example.com/post?a=1')).toEqual({ platform: 'web', url: 'https://example.com/post' });
    expect(sourceOf('ftp://x.com')).toBeUndefined();
    expect(sourceOf('https://user:pw@tiktok.com/x')).toBeUndefined();
  });
});
