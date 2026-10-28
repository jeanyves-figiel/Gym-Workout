import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type ModerationInput, openHolds, resolveHold } from '../src/community/aiModeration.ts';
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

const build = (aiDailyLimit = '500') =>
  buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', MODERATION_EMAIL: 'mod@example.com', AI_DAILY_LIMIT: aiDailyLimit }),
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
  it('holds a flagged post: hidden from others, visible to its owner, mailed to moderation; release puts it live', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Ben');
    const res = await post(a.t, 'DM me, meet me for cash');
    expect(res.statusCode).toBe(200);
    const p = res.json() as { post: { id: string; hidden: boolean; inReview: boolean } };
    expect(p.post).toMatchObject({ hidden: true, inReview: true });
    expect(await feed(b.t)).not.toContain(p.post.id);
    const mail = mailer.outbox.find((m) => m.subject === 'Community hold: spam (post)')!;
    expect(mail.text).toContain('meet me for cash');
    const [hold] = openHolds(db);
    expect(hold).toMatchObject({ target_type: 'post', target_id: p.post.id, category: 'spam', nickname: 'Ana' });

    // Editing it while held doesn't put it live.
    expect((await req('PATCH', `/v1/community/posts/${p.post.id}`, a.t, { caption: 'Leg day done' })).statusCode).toBe(200);
    expect(await feed(b.t)).not.toContain(p.post.id);

    expect(resolveHold(db, hold!.id, 'released', new Date())).toBe(true);
    expect(await feed(b.t)).toContain(p.post.id);
    const mine = (await req('GET', '/v1/community/feed', a.t)).json() as { posts: { id: string; inReview: boolean }[] };
    expect(mine.posts.find((x) => x.id === p.post.id)?.inReview).toBe(false);
    expect(resolveHold(db, hold!.id, 'released', new Date())).toBe(false);
    expect(openHolds(db)).toHaveLength(0);
  });

  it('lets clean posts through and checks only new text (an auto re-share costs no call)', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Ben');
    calls = [];
    const id = randomUUID();
    expect(((await post(a.t, 'New squat PR', id)).json() as { post: { hidden: boolean } }).post.hidden).toBe(false);
    expect(calls).toEqual([{ texts: ['New squat PR', 'Leg day'] }]);
    await post(a.t, 'New squat PR', id);
    expect(calls).toHaveLength(1);
    expect(await feed(b.t)).toContain(id);
  });

  it('fails open to the word filter when the model is down or the AI budget is spent', async () => {
    const a = await join('a@example.com', 'Ana');
    down = true;
    expect(((await post(a.t, 'meet me for cash')).json() as { post: { hidden: boolean } }).post.hidden).toBe(false);
    expect((await post(a.t, 'fuck this')).statusCode).toBe(400);
    await app.close();
    down = false;
    app = build('0');
    calls = [];
    expect(((await post(a.t, 'meet me for cash')).json() as { post: { hidden: boolean } }).post.hidden).toBe(false);
    expect(calls).toHaveLength(0);
  });

  it('refuses a flagged nickname or about (a profile cannot wait for review)', async () => {
    const a = await join('a@example.com', 'Ana');
    const r = await req('PUT', '/v1/community/me', a.t, { bio: 'meet me for cash' });
    expect(r.statusCode).toBe(400);
    expect(r.json()).toMatchObject({ error: 'objectionable_content' });
  });

  it('holds a flagged profile photo aside; the old photo stays until release, reject deletes it', async () => {
    const a = await join('a@example.com', 'Ana');
    const put = () => app.inject({ method: 'PUT', url: '/v1/community/me/avatar', headers: { authorization: `Bearer ${a.t}`, 'content-type': 'image/jpeg' }, payload: jpeg() });
    const ok = (await put()).json() as { profile: { avatarUrl: string }; held: boolean };
    expect(ok.held).toBe(false);
    flagPhotos = true;
    const held = (await put()).json() as { profile: { avatarUrl: string }; held: boolean };
    expect(held).toMatchObject({ held: true, profile: { avatarUrl: ok.profile.avatarUrl, avatarInReview: true } });
    expect(mailer.outbox.find((m) => m.subject === 'Community hold: sexual (avatar)')?.attachments).toHaveLength(1);
    const [hold] = openHolds(db);
    resolveHold(db, hold!.id, 'released', new Date());
    const now = (await req('GET', '/v1/community/me', a.t)).json() as { profile: { avatarUrl: string } };
    expect(now.profile.avatarUrl).toBe(`/v1/community/avatars/${hold!.target_id}`);
    await put();
    resolveHold(db, openHolds(db)[0]!.id, 'rejected', new Date());
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_avatars').get()).toEqual({ n: 1 });
  });

  it('holds a flagged shared plan and only the flagged workout of a batch', async () => {
    const a = await join('a@example.com', 'Ana');
    const b = await join('b@example.com', 'Ben');
    const planId = randomUUID();
    const plan = { name: 'meet me for cash', about: 'Three days', level: 'beginner', goal: 'strength', weeks: 8, sessionsPerWeek: 3, programme: { id: 'p', name: 'PPL' } };
    expect(((await req('PUT', `/v1/community/programs/${planId}`, a.t, plan)).json() as { program: object }).program).toMatchObject({ hidden: true, inReview: true });
    expect((await req('GET', `/v1/community/programs/${planId}`, b.t)).statusCode).toBe(404);

    const w = (name: string) => ({ id: randomUUID(), name, createdAt: '2026-10-28T09:00:00Z', items: [{ exerciseId: 'pull-up' }], visibility: 'members' });
    const good = w('Pull strength');
    const bad = w('meet me for cash');
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [good, bad] })).statusCode).toBe(200);
    const lib = ((await req('GET', '/v1/library/shared', b.t)).json() as { workouts: { id: string }[] }).workouts.map((x) => x.id);
    expect(lib).toEqual([good.id]);
    const own = ((await req('GET', '/v1/me/custom-workouts', a.t)).json() as { workouts: { id: string; inReview: boolean }[] }).workouts;
    expect(own.map((x) => [x.id === bad.id, x.inReview])).toEqual(expect.arrayContaining([[true, true], [false, false]]));
    expect(openHolds(db).map((h) => h.target_type).sort()).toEqual(['program', 'workout']);
  });
});
