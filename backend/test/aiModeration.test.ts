import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type ModerationInput } from '../src/community/aiModeration.ts';
import { ensureCommunitySchema } from '../src/community/schema.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let db: DB;
let calls: ModerationInput[];
/** Fake model: flags texts with "meet me for cash", flags photos while `flagPhotos`; throws while `down`. */
let flagPhotos: boolean;
let down: boolean;

const build = (moderationLimit = '500', aiDailyLimit = '500') =>
  buildApp({
    config: loadConfig({
      NODE_ENV: 'test',
      AUTH_RATE_LIMIT_PER_MIN: '1000',
      MODERATION_EMAIL: 'mod@example.com',
      AI_DAILY_LIMIT: aiDailyLimit,
      MODERATION_DAILY_LIMIT: moderationLimit,
    }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => new Date('2026-10-28T10:00:00Z'),
    moderation: async (input) => {
      calls.push(input);
      if (down) throw new Error('overloaded');
      if (input.jpeg) return flagPhotos ? 'sexual' : null;
      return input.texts.some((t) => t.includes('meet me for cash')) ? 'spam' : null;
    },
  });

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  calls = [];
  flagPhotos = false;
  down = false;
  app = build();
});
afterEach(() => app.close());

const req = (method: 'GET' | 'POST' | 'PUT' | 'PATCH', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const join = async (email: string, nickname: string) => {
  const reg = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  if (reg.statusCode >= 300) throw new Error(reg.body);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  expect((await req('PUT', '/v1/community/me', j.tokens.accessToken, { nickname, acceptGuidelines: true })).statusCode).toBe(200);
  return { t: j.tokens.accessToken, id: j.user.id };
};

const post = (t: string, caption: string, id = randomUUID()) =>
  req('POST', '/v1/community/posts', t, { id, kind: 'workout', refId: `w-${id}`, caption, payload: { title: 'Leg day' } });
const feed = async (t: string) => ((await req('GET', '/v1/community/feed', t)).json() as { posts: { id: string }[] }).posts.map((p) => p.id);

const jpeg = () =>
  Buffer.concat([
    Buffer.from([0xff, 0xd8, 0xff, 0xc0, 0, 11, 8, 1, 0, 1, 0, 1, 1, 0x11, 0]),
    Buffer.from([0xff, 0xda, 0, 8, 1, 1, 0, 0, 0x3f, 0, 0x12, 0x34, 0xff, 0xd9]),
  ]);

describe('AI moderation of shared content (#871)', () => {
  it('refuses a flagged post on the spot, like the word filter; nothing is stored', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Ben');
    const res = await post(a.t, 'DM me, meet me for cash');
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: 'objectionable_content' });
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_posts').get()).toEqual({ n: 0 });
    expect(await feed(b.t)).toEqual([]);
  });

  it('lets clean posts through and checks only new text (an auto re-share costs no call)', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Ben');
    calls = [];
    const id = randomUUID();
    expect((await post(a.t, 'New squat PR', id)).statusCode).toBe(200);
    expect(calls).toEqual([{ texts: ['New squat PR', 'Leg day'] }]);
    await post(a.t, 'New squat PR', id);
    expect(calls).toHaveLength(1);
    expect(await feed(b.t)).toContain(id);
    expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: 'meet me for cash' })).statusCode).toBe(400);
  });

  it('checks a private post when it is opened to members', async () => {
    const a = await join('a@example.com', 'Ana');
    const id = randomUUID();
    calls = [];
    expect((await req('POST', '/v1/community/posts', a.t, { id, kind: 'workout', visibility: 'private', caption: 'meet me for cash', payload: { title: 'Leg day' } })).statusCode).toBe(200);
    expect(calls).toHaveLength(0);
    expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { visibility: 'members' })).statusCode).toBe(400);
  });

  it('fails open to the word filter when the model is down or the moderation budget is spent', async () => {
    const a = await join('a@example.com', 'Ana');
    down = true;
    expect((await post(a.t, 'meet me for cash')).statusCode).toBe(200);
    expect((await post(a.t, 'fuck this')).statusCode).toBe(400);
    await app.close();
    down = false;
    app = build('0');
    calls = [];
    expect((await post(a.t, 'meet me for cash')).statusCode).toBe(200);
    expect(calls).toHaveLength(0);
  });

  it('refuses a flagged nickname or about', async () => {
    const a = await join('a@example.com', 'Ana');
    const r = await req('PUT', '/v1/community/me', a.t, { bio: 'meet me for cash' });
    expect(r.statusCode).toBe(400);
    expect(r.json()).toMatchObject({ error: 'objectionable_content' });
  });

  it('refuses a flagged profile photo; the current photo stays', async () => {
    const a = await join('a@example.com', 'Ana');
    const put = () => app.inject({ method: 'PUT', url: '/v1/community/me/avatar', headers: { authorization: `Bearer ${a.t}`, 'content-type': 'image/jpeg' }, payload: jpeg() });
    const ok = (await put()).json() as { profile: { avatarUrl: string } };
    flagPhotos = true;
    const r = await put();
    expect(r.statusCode).toBe(400);
    expect(r.json()).toMatchObject({ error: 'objectionable_content' });
    const now = (await req('GET', '/v1/community/me', a.t)).json() as { profile: { avatarUrl: string } };
    expect(now.profile.avatarUrl).toBe(ok.profile.avatarUrl);
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_avatars').get()).toEqual({ n: 1 });
  });

  it('refuses a flagged shared plan and a batch with a flagged shared workout name', async () => {
    const a = await join('a@example.com', 'Ana');
    const plan = { name: 'meet me for cash', about: 'Three days', level: 'beginner', goal: 'strength', weeks: 8, sessionsPerWeek: 3, programme: { id: 'p', name: 'PPL' } };
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, plan)).statusCode).toBe(400);
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, { ...plan, visibility: 'private' })).statusCode).toBe(200);

    const w = (name: string, visibility = 'members') => ({ id: randomUUID(), name, createdAt: '2026-10-28T09:00:00Z', items: [{ exerciseId: 'pull-up' }], visibility });
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [w('Pull strength'), w('meet me for cash')] })).statusCode).toBe(400);
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [w('Pull strength'), w('meet me for cash', 'private')] })).statusCode).toBe(200);
  });

  it('drops the old review queue and the photos it held', async () => {
    const a = await join('a@example.com', 'Ana');
    db.exec(`CREATE TABLE moderation_holds (id TEXT PRIMARY KEY, user_id TEXT, target_type TEXT, target_id TEXT, category TEXT, created_at TEXT, resolved_at TEXT, decision TEXT)`);
    db.prepare('INSERT INTO community_avatars (id, user_id, data, created_at) VALUES (?, ?, ?, ?)').run('held-photo', a.id, Buffer.from([1]), '2026-10-28T10:00:00Z');
    db.prepare("INSERT INTO moderation_holds VALUES ('h1', ?, 'avatar', 'held-photo', 'sexual', '2026-10-28T10:00:00Z', NULL, NULL)").run(a.id);
    ensureCommunitySchema(db);
    expect(db.prepare("SELECT name FROM sqlite_master WHERE name = 'moderation_holds'").get()).toBeUndefined();
    expect(db.prepare("SELECT COUNT(*) AS n FROM community_avatars WHERE id = 'held-photo'").get()).toEqual({ n: 0 });
  });

  it('keeps its own budget: caption edits never spend the paid AI budget, and a spent AI budget keeps moderation on (#920)', async () => {
    await app.close();
    app = build('500', '3');
    const a = await join('a@example.com', 'Ana');
    const id = randomUUID();
    expect((await post(a.t, 'first', id)).statusCode).toBe(200);
    for (let i = 0; i < 5; i++) expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: `edit ${i}` })).statusCode).toBe(200);
    expect(db.prepare("SELECT count FROM ai_daily_usage WHERE day = '2026-10-28'").get()).toBeUndefined();
    db.prepare("INSERT INTO ai_daily_usage (day, count) VALUES ('2026-10-28', 3)").run();
    expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: 'meet me for cash' })).statusCode).toBe(400);
  });

  it('caps checks per member per day, then refuses their changes until tomorrow (#920)', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Bea');
    const id = randomUUID();
    expect((await post(a.t, 'first', id)).statusCode).toBe(200);
    let last = 0;
    for (let i = 0; i < 45; i++) last = (await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: `edit ${i}` })).statusCode;
    expect(last).toBe(429);
    expect(calls.length).toBeLessThanOrEqual(41);
    // Others are unaffected.
    expect((await post(b.t, 'meet me for cash')).statusCode).toBe(400);
  });

  it('remembers clean texts: the same words again cost no call (#920)', async () => {
    const a = await join('a@example.com', 'Ana');
    const id = randomUUID();
    expect((await post(a.t, 'same words', id)).statusCode).toBe(200);
    calls = [];
    expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: 'other words' })).statusCode).toBe(200);
    expect((await req('PATCH', `/v1/community/posts/${id}`, a.t, { caption: 'same words' })).statusCode).toBe(200);
    expect(calls.map((c) => c.texts)).toEqual([['other words']]);
  });
});
