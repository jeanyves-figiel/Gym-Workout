import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { isoWeek, weeksInYear } from '../src/routes/live.ts';

/** Community privacy (#713), correctness (#714) and speed (#715) fixes. */
const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-22T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
  });
});
afterEach(() => app.close());

const tick = () => (clock = new Date(clock.getTime() + 1000));
const req = (method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  return { t: j.tokens.accessToken, id: j.user.id };
};
const join = async (email: string, nickname: string, extra: object = {}) => {
  const u = await signUp(email);
  expect((await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true, ...extra })).statusCode).toBe(200);
  return u;
};
const share = (t: string, extra: object = {}) =>
  req('POST', '/v1/community/posts', t, { id: randomUUID(), kind: 'workout', payload: { title: 'Leg day' }, visibility: 'members', ...extra });

/** Three reports about `target` as a person from accounts older than a week: hidden pending review. */
const hideMember = (target: string) => {
  const old = '2026-01-01T00:00:00.000Z';
  for (let i = 0; i < 3; i++) {
    const id = randomUUID();
    db.prepare('INSERT INTO users (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, `r${i}-${target}@example.com`, old, old);
    db.prepare("INSERT INTO community_reports (id, reporter_id, target_user_id, reason, created_at) VALUES (?, ?, ?, 'spam', ?)").run(randomUUID(), id, target, clock.toISOString());
  }
};

const jpeg = () => {
  const seg = (m: number, body: Buffer) => Buffer.concat([Buffer.from([0xff, m, (body.length + 2) >> 8, (body.length + 2) & 0xff]), body]);
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    seg(0xc0, Buffer.from([8, 1, 0, 1, 0, 1, 1, 0x11, 0])),
    seg(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])),
    Buffer.from([0x12, 0x34, 0xff, 0xd9]),
  ]);
};

describe('privacy (#713)', () => {
  it('a member hidden by reports has no page for others, still for themselves', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    hideMember(a.id);
    expect((await req('GET', `/v1/community/members/${a.id}`, b.t)).json().error).toBe('not_found');
    expect((await req('GET', `/v1/community/members/${a.id}`, a.t)).statusCode).toBe(200);
  });

  it("a hidden member's posts leave the feeds and the share page, not their own feed (#819)", async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    expect((await req('PUT', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBe(204);
    const post = (await share(a.t, { visibility: 'public' })).json().post as { id: string };
    expect((await app.inject({ method: 'GET', url: `/share/${post.id}` })).statusCode).toBe(200);
    hideMember(a.id);
    for (const scope of ['members', 'following'])
      expect((await req('GET', `/v1/community/feed?scope=${scope}`, b.t)).json().posts).toHaveLength(0);
    expect((await req('GET', '/v1/community/feed?scope=mine', a.t)).json().posts).toHaveLength(1);
    expect((await app.inject({ method: 'GET', url: `/share/${post.id}` })).statusCode).toBe(404);
  });

  it('leaving the community deletes reports the member filed and their photo', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    await app.inject({ method: 'PUT', url: '/v1/community/me/avatar', headers: { authorization: `Bearer ${a.t}`, 'content-type': 'image/jpeg' }, payload: jpeg() });
    expect((await req('POST', '/v1/community/reports', a.t, { userId: b.id, reason: 'spam' })).statusCode).toBe(202);
    expect((await req('DELETE', '/v1/community/me', a.t)).statusCode).toBe(204);
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_reports WHERE reporter_id = ?').get(a.id)).toEqual({ n: 0 });
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_avatars WHERE user_id = ?').get(a.id)).toEqual({ n: 0 });
  });

  it('the export has level, pronouns, photo, reports filed, saves, copies, Garmin and sign-in settings without secrets', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    await req('PUT', '/v1/community/me/level', a.t, { level: 12 });
    await req('PUT', '/v1/community/me/pronouns', a.t, { pronouns: 'she/her' });
    await app.inject({ method: 'PUT', url: '/v1/community/me/avatar', headers: { authorization: `Bearer ${a.t}`, 'content-type': 'image/jpeg' }, payload: jpeg() });
    await req('POST', '/v1/community/reports', a.t, { userId: b.id, reason: 'spam', details: 'ads' });
    const w = randomUUID();
    await req('POST', '/v1/me/custom-workouts', b.t, { workouts: [{ id: w, name: 'Arms', items: [], visibility: 'members' }] });
    await req('POST', `/v1/library/shared/${w}/save`, a.t);
    const watchKey = (await req('POST', '/v1/me/watch-key', a.t)).json().key as string;
    await req('PUT', '/v1/me/garmin/snapshot', a.t, { snapshot: { next: 'Push' } });
    const exp = (await req('GET', '/v1/me/export', a.t)).json();
    expect(exp.community.profile).toMatchObject({ level: 12, pronouns: 'she/her' });
    expect(exp.community.avatarJpegBase64).toBe(jpeg().toString('base64'));
    expect(exp.communityReportsFiled).toEqual([expect.objectContaining({ targetUserId: b.id, reason: 'spam', details: 'ads' })]);
    expect(exp.librarySaves).toEqual([{ workoutId: w, savedAt: clock.toISOString() }]);
    expect(exp.programCopies).toEqual([]);
    expect(exp.garmin).toMatchObject({ devices: [], snapshot: { data: { next: 'Push' } }, inbox: [] });
    expect(exp.security).toEqual({ passkeys: [], twoStep: false, watchKey: true });
    expect(JSON.stringify(exp)).not.toContain(watchKey);
  });
});

describe('correctness (#714)', () => {
  it('re-sharing by refId keeps the caption and visibility it does not send', async () => {
    const a = await join('a@example.com', 'ann_a');
    const first = (await share(a.t, { refId: 'w-1', caption: 'PB!', visibility: 'public' })).json().post;
    const again = (await share(a.t, { refId: 'w-1', payload: { title: 'Leg day (edited)' }, visibility: undefined })).json().post;
    expect(again).toMatchObject({ id: first.id, caption: 'PB!', visibility: 'public', payload: { title: 'Leg day (edited)' } });
    expect((await share(a.t, { refId: 'w-1', caption: null })).json().post.caption).toBeNull();
  });

  it("someone else's post or plan is not found; a cheer on a post you can't see stays", async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    const post = (await share(a.t)).json().post;
    expect((await req('DELETE', `/v1/community/posts/${post.id}`, b.t)).json().error).toBe('not_found');
    expect((await req('DELETE', `/v1/community/posts/${randomUUID()}`, b.t)).statusCode).toBe(204);
    const plan = randomUUID();
    const body = { name: 'Strong 8', level: 'beginner', weeks: 8, sessionsPerWeek: 3, programme: { name: 'Strong 8' } };
    expect((await req('PUT', `/v1/community/programs/${plan}`, a.t, body)).statusCode).toBe(200);
    expect((await req('DELETE', `/v1/community/programs/${plan}`, b.t)).json().error).toBe('not_found');
    expect((await req('GET', `/v1/community/programs/${plan}`, a.t)).statusCode).toBe(200);

    await req('PUT', `/v1/community/posts/${post.id}/reactions/fire`, b.t);
    db.prepare('UPDATE community_posts SET hidden_at = ? WHERE id = ?').run(clock.toISOString(), post.id);
    expect((await req('DELETE', `/v1/community/posts/${post.id}/reactions/fire`, b.t)).statusCode).toBe(404);
    expect(db.prepare('SELECT COUNT(*) AS n FROM community_reactions').get()).toEqual({ n: 1 });
  });

  it('plans page by when they were shared, so an edit does not move one between pages', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    const ids: string[] = [];
    for (let i = 0; i < 3; i++) {
      const id = randomUUID();
      ids.push(id);
      await req('PUT', `/v1/community/programs/${id}`, a.t, { name: `Plan ${i}`, level: 'beginner', weeks: 4, sessionsPerWeek: 3, programme: { name: 'P' } });
      tick();
    }
    const first = (await req('GET', '/v1/community/programs?limit=2', b.t)).json();
    expect(first.programs.map((p: { id: string }) => p.id)).toEqual([ids[2], ids[1]]);
    await req('PUT', `/v1/community/programs/${ids[0]}`, a.t, { name: 'Plan 0 v2', level: 'beginner', weeks: 4, sessionsPerWeek: 3, programme: { name: 'P' } });
    const next = (await req('GET', `/v1/community/programs?limit=2&before=${encodeURIComponent(first.nextBefore)}&beforeId=${first.nextBeforeId}`, b.t)).json();
    expect(next.programs.map((p: { id: string }) => p.id)).toEqual([ids[0]]);
  });

  it('copy and save counts come from who copied or saved, so a deleted account no longer counts', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    const plan = randomUUID();
    await req('PUT', `/v1/community/programs/${plan}`, a.t, { name: 'Strong 8', level: 'beginner', weeks: 8, sessionsPerWeek: 3, programme: { name: 'S' } });
    expect((await req('POST', `/v1/community/programs/${plan}/copy`, b.t)).json().program).toMatchObject({ copies: 1, copiedByMe: true });
    expect((await req('POST', `/v1/community/programs/${plan}/copy`, b.t)).json().program.copies).toBe(1);
    const w = randomUUID();
    await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [{ id: w, name: 'Arms', items: [], visibility: 'members' }] });
    expect((await req('POST', `/v1/library/shared/${w}/save`, b.t)).json().workout.saves).toBe(1);
    await app.inject({ method: 'DELETE', url: '/v1/me', headers: { authorization: `Bearer ${b.t}` }, payload: { password: PW, confirm: 'DELETE' } });
    expect((await req('GET', `/v1/community/programs/${plan}`, a.t)).json().program.copies).toBe(0);
    expect((await req('GET', '/v1/me/custom-workouts', a.t)).json().workouts[0].saves).toBe(0);
  });

  it('challenge ranks and counts leave out blocked and hidden members; weeks must exist', async () => {
    const a = await join('a@example.com', 'ann_a');
    const b = await join('b@example.com', 'bob_b');
    const c = await join('c@example.com', 'cat_c');
    const wk = isoWeek(clock);
    await req('PUT', '/v1/community/challenge/score', b.t, { week: wk, rounds: 9, reps: 0 });
    await req('PUT', '/v1/community/challenge/score', c.t, { week: wk, rounds: 8, reps: 0 });
    expect((await req('PUT', '/v1/community/challenge/score', a.t, { week: wk, rounds: 5, reps: 0 })).json().rank).toBe(3);
    await req('POST', '/v1/community/blocks', a.t, { userId: b.id });
    hideMember(c.id);
    const board = (await req('GET', '/v1/community/challenge', a.t)).json();
    expect(board).toMatchObject({ joined: 1, me: { rank: 1 } });
    expect(board.leaderboard.map((e: { userId: string }) => e.userId)).toEqual([a.id]);
    expect((await req('PUT', '/v1/community/challenge/score', a.t, { week: wk, rounds: 5, reps: 1 })).json().rank).toBe(1);
    // c, hidden, still sees their own place: behind b, ahead of a.
    expect((await req('GET', '/v1/community/challenge', c.t)).json().me.rank).toBe(2);

    expect(weeksInYear(2026)).toBe(53);
    expect(weeksInYear(2027)).toBe(52);
    for (const w of ['2026-W00', '2027-W53', '2026-W54']) expect((await req('GET', `/v1/community/challenge?week=${w}`, a.t)).statusCode).toBe(400);
    expect((await req('GET', '/v1/community/challenge?week=2026-W53', a.t)).statusCode).toBe(200);
  });
});

describe('speed (#715)', () => {
  it('finds members by the gym on their community profile, kept in step with the training profile', async () => {
    const a = await join('a@example.com', 'ann_a', { showGym: true });
    const b = await join('b@example.com', 'bob_b', { showGym: true });
    const gym = { id: 'map:47.39,8.51', name: 'Kraftwerk Zürich', latitude: 47.39, longitude: 8.51 };
    for (const u of [a, b]) await req('PUT', '/v1/me/profile', u.t, { data: { profile: { gym } } });
    expect(db.prepare('SELECT gym_id, gym_name, gym_key FROM community_profiles WHERE user_id = ?').get(a.id)).toEqual({
      gym_id: gym.id,
      gym_name: gym.name,
      gym_key: 'kraftwerk zürich',
    });
    expect((await req('GET', '/v1/community/members?gym=mine', a.t)).json().members.map((m: { userId: string }) => m.userId)).toEqual([b.id]);
    expect((await req('GET', `/v1/community/members?q=${encodeURIComponent('kraftwerk zü')}`, a.t)).json().members[0]).toMatchObject({
      userId: b.id,
      gym: 'Kraftwerk Zürich',
      followers: 0,
      followedByMe: false,
    });
    await req('PUT', '/v1/me/profile', b.t, { data: { profile: { gym: { ...gym, id: 'elsewhere', name: 'Other Gym' } } } });
    expect((await req('GET', '/v1/community/members?gym=mine', a.t)).json().members).toEqual([]);
  });

  it('pages the members you follow by nickname; without paging the first 500 come as before', async () => {
    const me = await join('me@example.com', 'me_me');
    const names = ['cara', 'abe', 'bea'];
    for (const [i, n] of names.entries()) {
      const u = await join(`f${i}@example.com`, n);
      await req('PUT', `/v1/community/follows/${u.id}`, me.t);
    }
    const all = (await req('GET', '/v1/community/follows', me.t)).json();
    expect(all.following.map((m: { nickname: string }) => m.nickname)).toEqual(['abe', 'bea', 'cara']);
    expect(all.nextAfter).toBeNull();
    const p1 = (await req('GET', '/v1/community/follows?limit=2', me.t)).json();
    expect(p1.following.map((m: { nickname: string }) => m.nickname)).toEqual(['abe', 'bea']);
    const p2 = (await req('GET', `/v1/community/follows?limit=2&after=${p1.nextAfter}`, me.t)).json();
    expect(p2).toMatchObject({ following: [{ nickname: 'cara', followedByMe: true }], nextAfter: null });
  });
});
