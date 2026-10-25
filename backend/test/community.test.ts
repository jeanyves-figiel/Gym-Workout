import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { containsObjectionable as isObjectionable } from '../src/community/filter.ts';
import { sanitizeJpeg } from '../src/community/image.ts';
import { ensureCommunitySchema } from '../src/community/schema.ts';
import { followerIds } from '../src/community/moderation.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-10T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', MODERATION_EMAIL: 'mod@example.com' }),
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
const h = (t: string) => ({ authorization: `Bearer ${t}` });
const req = (method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: h(t), ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  return { t: j.tokens.accessToken, id: j.user.id };
};

const join = async (email: string, nickname: string, extra: object = {}) => {
  const u = await signUp(email);
  const r = await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true, ...extra });
  expect(r.statusCode).toBe(200);
  return u;
};

const share = (t: string, extra: object = {}) =>
  req('POST', '/v1/community/posts', t, {
    id: randomUUID().toUpperCase(),
    kind: 'workout',
    payload: { title: 'Upper body power', metric: { value: '6.4', unit: 't lifted' }, stats: [{ label: 'min', value: '52' }] },
    ...extra,
  });

/** Minimal JPEG: SOI, APP0 JFIF, APP1 Exif (with "GPS"), COM, SOF0 w×h, SOS + data, EOI. */
const jpeg = (w = 256, hgt = 256) => {
  const seg = (m: number, body: Buffer) => Buffer.concat([Buffer.from([0xff, m]), Buffer.from([(body.length + 2) >> 8, (body.length + 2) & 0xff]), body]);
  const sof = Buffer.from([8, hgt >> 8, hgt & 0xff, w >> 8, w & 0xff, 1, 1, 0x11, 0]);
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    seg(0xe0, Buffer.from('JFIF\0\x01\x01\0\0\x01\0\x01\0\0', 'binary')),
    seg(0xe1, Buffer.from('Exif\0\0GPS-SECRET-48.85N', 'binary')),
    seg(0xfe, Buffer.from('comment-secret')),
    seg(0xc0, sof),
    seg(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])),
    Buffer.from([0x12, 0x34, 0xff, 0x00, 0x56]),
    Buffer.from([0xff, 0xd9]),
  ]);
};

describe('community profile', () => {
  it('requires guidelines, validates and filters nickname/bio, enforces unique nickname', async () => {
    const a = await signUp('a@example.com');
    expect((await req('GET', '/v1/community/me', a.t)).json().profile).toBeNull();
    expect((await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy' })).json().error).toBe('guidelines_required');
    expect((await req('PUT', '/v1/community/me', a.t, { nickname: 'x', acceptGuidelines: true })).statusCode).toBe(400);
    expect((await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy', bio: 'f.u.c.k this', acceptGuidelines: true })).json().error).toBe('objectionable_content');
    const ok = await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy', bio: 'Climber who lifts', acceptGuidelines: true });
    // new members default to sharing with members (#90)
    expect(ok.json().profile).toMatchObject({ nickname: 'monkey_jy', bio: 'Climber who lifts', defaultVisibility: 'members', autoShare: false, avatarUrl: null });
    // later edits need no re-acceptance and keep omitted fields
    const ed = await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy', defaultVisibility: 'private' });
    expect(ed.json().profile).toMatchObject({ bio: 'Climber who lifts', defaultVisibility: 'private' });
    expect((await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy' })).json().profile.defaultVisibility).toBe('private');
    const b = await signUp('b@example.com');
    expect((await req('PUT', '/v1/community/me', b.t, { nickname: 'MONKEY_JY', acceptGuidelines: true })).statusCode).toBe(409);
  });

  it('stores a sanitized avatar served publicly, rejects bad images', async () => {
    const a = await join('a@example.com', 'bea');
    const put = (body: Buffer, type = 'image/jpeg') => app.inject({ method: 'PUT', url: '/v1/community/me/avatar', headers: { ...h(a.t), 'content-type': type }, payload: body });
    expect((await put(Buffer.from('not a jpeg'))).statusCode).toBe(400);
    expect((await put(jpeg(32, 32))).statusCode).toBe(400);
    expect((await put(jpeg(4000, 4000))).statusCode).toBe(400);
    expect((await put(Buffer.alloc(600 * 1024, 1))).statusCode).toBe(413);
    const ok = await put(jpeg());
    expect(ok.statusCode).toBe(200);
    const url = ok.json().profile.avatarUrl as string;
    const img = await app.inject({ method: 'GET', url });
    expect(img.statusCode).toBe(200);
    expect(img.headers['content-type']).toBe('image/jpeg');
    expect(img.rawPayload.includes('GPS-SECRET')).toBe(false);
    expect(img.rawPayload.includes('comment-secret')).toBe(false);
    expect(img.rawPayload.includes('JFIF')).toBe(true);
    expect((await req('DELETE', '/v1/community/me/avatar', a.t)).json().profile.avatarUrl).toBeNull();
    expect((await app.inject({ method: 'GET', url })).statusCode).toBe(404);
  });
});

describe('game level (#242)', () => {
  it('is reported by the app and shown on profile, member page, search rows and posts', async () => {
    const solo = await signUp('solo@example.com');
    expect((await req('PUT', '/v1/community/me/level', solo.t, { level: 3 })).statusCode).toBe(404);
    const a = await join('lvl-a@example.com', 'legend_a', { defaultVisibility: 'members' });
    const b = await join('lvl-b@example.com', 'viewer_b');
    expect((await req('GET', '/v1/community/me', a.t)).json().profile.level).toBeNull();
    expect((await req('PUT', '/v1/community/me/level', a.t, { level: 0 })).statusCode).toBe(400);
    expect((await req('PUT', '/v1/community/me/level', a.t, { level: 41 })).json()).toEqual({ level: 41 });
    expect((await req('GET', '/v1/community/me', a.t)).json().profile.level).toBe(41);
    expect((await share(a.t, { visibility: 'members' })).statusCode).toBe(200);
    const member = (await req('GET', `/v1/community/members/${a.id}`, b.t)).json();
    expect(member.member.level).toBe(41);
    expect(member.posts[0].author.level).toBe(41);
    const found = (await req('GET', '/v1/community/members?q=legend', b.t)).json();
    expect(JSON.stringify(found)).toContain('"level":41');
  });
});

describe('pronouns (#415)', () => {
  it('are shown next to the nickname only once set, and null hides them', async () => {
    const solo = await signUp('pro-solo@example.com');
    expect((await req('PUT', '/v1/community/me/pronouns', solo.t, { pronouns: 'she/her' })).statusCode).toBe(404);
    const a = await join('pro-a@example.com', 'pro_a', { defaultVisibility: 'members' });
    const b = await join('pro-b@example.com', 'pro_b');
    expect((await req('GET', '/v1/community/me', a.t)).json().profile.pronouns).toBeNull();
    expect((await req('PUT', '/v1/community/me/pronouns', a.t, { pronouns: 'x'.repeat(25) })).statusCode).toBe(400);
    expect((await req('PUT', '/v1/community/me/pronouns', a.t, { pronouns: ' she/her ' })).json()).toEqual({ pronouns: 'she/her' });
    expect((await share(a.t, { visibility: 'members' })).statusCode).toBe(200);
    const member = (await req('GET', `/v1/community/members/${a.id}`, b.t)).json();
    expect(member.member.pronouns).toBe('she/her');
    expect(member.posts[0].author.pronouns).toBe('she/her');
    expect(JSON.stringify((await req('GET', '/v1/community/members?q=pro_a', b.t)).json())).toContain('"pronouns":"she/her"');
    expect((await req('PUT', '/v1/community/me/pronouns', a.t, { pronouns: null })).json()).toEqual({ pronouns: null });
    expect((await req('GET', `/v1/community/members/${a.id}`, b.t)).json().member.pronouns).toBeNull();
  });
});

describe('community feed', () => {
  it('caps new posts at 50 a day; updating a post is not a new one', async () => {
    const u = await join('poster@example.com', 'poster');
    for (let i = 0; i < 50; i++) expect((await share(u.t)).statusCode).toBe(200);
    const over = await share(u.t);
    expect(over.statusCode).toBe(429);
    expect(over.json().error).toBe('daily_limit');
    const mine = db.prepare('SELECT id FROM community_posts LIMIT 1').get() as { id: string };
    expect((await share(u.t, { id: mine.id })).statusCode).toBe(200);
  });

  it('keeps the exercises of a shared workout so members can copy it (#779)', async () => {
    const a = await join('ex@example.com', 'lifter', { defaultVisibility: 'members' });
    const b = await join('ex2@example.com', 'watcher');
    const exercises = [
      { id: 'back-squat', name: 'Back squat', sets: 3, reps: 5, kg: 100 },
      { id: 'plank', name: 'Plank', sets: 2, reps: 45, kg: null },
    ];
    const r = await share(a.t, { payload: { title: 'Legs', stats: [{ label: 'sets', value: '5' }], exercises } });
    expect(r.statusCode).toBe(200);
    const feed = (await req('GET', '/v1/community/feed', b.t)).json().posts;
    expect(feed[0].payload.exercises).toEqual(exercises);
    expect((await share(a.t, { payload: { title: 'Legs', exercises: [{ id: 'x', name: 'shit lift', sets: 1 }] } })).json().error).toBe(
      'objectionable_content',
    );
    const many = Array.from({ length: 41 }, (_, i) => ({ id: `e${i}`, name: 'Curl', sets: 1 }));
    expect((await share(a.t, { payload: { title: 'Arms', exercises: many } })).statusCode).toBe(400);
  });

  it('honours visibility, cheers, blocks and deletion', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'members' });
    const b = await join('b@example.com', 'monkey_jy', { defaultVisibility: 'private' });
    const outsider = await signUp('c@example.com');

    expect((await req('GET', '/v1/community/feed', outsider.t)).json().error).toBe('community_profile_required');
    expect((await share(outsider.t)).statusCode).toBe(403);

    const pub = (await share(a.t)).json().post; // profile default → members
    expect(pub.visibility).toBe('members');
    tick();
    const priv = (await share(a.t, { visibility: 'private', caption: 'just for me' })).json().post;
    tick();
    const bPost = (await share(b.t)).json().post; // b default → private
    expect(bPost.visibility).toBe('private');

    const bFeed = (await req('GET', '/v1/community/feed', b.t)).json().posts;
    expect(bFeed.map((p: { id: string }) => p.id)).toEqual([pub.id]);
    const aMine = (await req('GET', '/v1/community/feed?scope=mine', a.t)).json().posts;
    expect(aMine.map((p: { id: string }) => p.id)).toEqual([priv.id, pub.id]);

    // cheers
    expect((await req('PUT', `/v1/community/posts/${pub.id}/reactions/like`, a.t)).json().error).toBe('own_post');
    expect((await req('PUT', `/v1/community/posts/${priv.id}/reactions/like`, b.t)).statusCode).toBe(404);
    await req('PUT', `/v1/community/posts/${pub.id}/reactions/like`, b.t);
    const r = (await req('PUT', `/v1/community/posts/${pub.id}/reactions/strong`, b.t)).json().post;
    expect(r.reactions).toMatchObject({ like: 1, strong: 1, fire: 0 });
    expect(r.myReactions.sort()).toEqual(['like', 'strong']);
    expect((await req('DELETE', `/v1/community/posts/${pub.id}/reactions/like`, b.t)).json().post.reactions.like).toBe(0);
    // Beast and Banana cheers (#566), then back off so the counts below stay the same.
    const fun = (await req('PUT', `/v1/community/posts/${pub.id}/reactions/banana`, b.t)).json().post;
    expect(fun.reactions).toMatchObject({ beast: 0, banana: 1 });
    await req('DELETE', `/v1/community/posts/${pub.id}/reactions/banana`, b.t);
    expect((await req('GET', '/v1/community/me', a.t)).json().profile).toMatchObject({ sharedPosts: 1, cheersReceived: 1 });

    // member profile
    const m = (await req('GET', `/v1/community/members/${a.id}`, b.t)).json();
    expect(m.member.nickname).toBe('bea');
    expect(m.posts).toHaveLength(1);

    // block hides both ways
    expect((await req('POST', '/v1/community/blocks', b.t, { userId: a.id })).statusCode).toBe(204);
    expect((await req('GET', '/v1/community/feed', b.t)).json().posts).toHaveLength(0);
    expect((await req('GET', `/v1/community/members/${a.id}`, b.t)).statusCode).toBe(404);
    expect((await req('GET', `/v1/community/members/${b.id}`, a.t)).statusCode).toBe(404);
    expect((await req('GET', '/v1/community/blocks', b.t)).json().blocked[0]).toMatchObject({ userId: a.id, nickname: 'bea' });
    await req('DELETE', `/v1/community/blocks/${a.id}`, b.t);
    expect((await req('GET', '/v1/community/feed', b.t)).json().posts).toHaveLength(1);

    // edit + delete own post only
    expect((await req('PATCH', `/v1/community/posts/${pub.id}`, b.t, { visibility: 'private' })).statusCode).toBe(404);
    expect((await req('PATCH', `/v1/community/posts/${pub.id}`, a.t, { visibility: 'private' })).json().post.visibility).toBe('private');
    expect((await req('GET', '/v1/community/feed', b.t)).json().posts).toHaveLength(0);
    await req('DELETE', `/v1/community/posts/${pub.id}`, b.t);
    expect((await req('GET', '/v1/community/feed?scope=mine', a.t)).json().posts).toHaveLength(2);
    await req('DELETE', `/v1/community/posts/${pub.id}`, a.t);
    expect((await req('GET', '/v1/community/feed?scope=mine', a.t)).json().posts).toHaveLength(1);
  });

  it('follows: following feed, counts, provider, block removes follows', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'members' });
    const b = await join('b@example.com', 'monkey_jy');
    const c = await join('c@example.com', 'crimpy', { defaultVisibility: 'members' });
    await share(a.t);
    await share(c.t);
    expect((await req('PUT', `/v1/community/follows/${b.id}`, b.t)).statusCode).toBe(400);
    expect((await req('PUT', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBe(204);
    const feed = (await req('GET', '/v1/community/feed?scope=following', b.t)).json().posts;
    expect(feed.map((p: { author: { nickname: string } }) => p.author.nickname)).toEqual(['bea']);
    const m = (await req('GET', `/v1/community/members/${a.id}`, b.t)).json();
    expect(m.followedByMe).toBe(true);
    expect(m.member.followers).toBe(1);
    expect((await req('GET', '/v1/community/follows', b.t)).json().following[0].nickname).toBe('bea');
    expect(followerIds(db, a.id)).toEqual([b.id]);
    await req('POST', '/v1/community/blocks', a.t, { userId: b.id });
    expect(followerIds(db, a.id)).toEqual([]);
    expect((await req('PUT', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBe(404);
    await req('DELETE', `/v1/community/blocks/${b.id}`, a.t);
    await req('PUT', `/v1/community/follows/${a.id}`, b.t);
    expect((await req('DELETE', `/v1/community/follows/${a.id}`, b.t)).statusCode).toBe(204);
    expect(followerIds(db, a.id)).toEqual([]);
  });

  it('finds members by nickname, suggests, lists follows; skips self, blocks and reported members (#152)', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'members' });
    const b = await join('b@example.com', 'monkey_jy');
    const c = await join('c@example.com', 'crimpy');
    const d = await join('d@example.com', 'beast_mode');
    const e = await join('e@example.com', 'bxeast');
    await signUp('x@example.com'); // not a member: never listed
    const nicks = (r: { json(): { members: { nickname: string }[] } }) => r.json().members.map((m) => m.nickname);

    // Prefix matches first, then shortest; case-insensitive, never yourself; "_" is literal, not a wildcard.
    expect(nicks(await req('GET', '/v1/community/members?q=BE', b.t))).toEqual(['bea', 'beast_mode']);
    expect(nicks(await req('GET', '/v1/community/members?q=ea', b.t))).toEqual(['bea', 'bxeast', 'beast_mode']);
    expect(nicks(await req('GET', '/v1/community/members?q=t_m', b.t))).toEqual(['beast_mode']);
    expect(nicks(await req('GET', '/v1/community/members?q=monkey', b.t))).toEqual([]);
    expect(nicks(await req('GET', '/v1/community/members?q=%25', b.t))).toEqual([]) // not a wildcard;
    expect((await req('GET', '/v1/community/members?q=bea', (await signUp('y@example.com')).t)).statusCode).toBe(403);

    // Suggestions: not followed yet, most followed first.
    await req('PUT', `/v1/community/follows/${c.id}`, a.t);
    await share(a.t);
    const sug = (await req('GET', '/v1/community/members', b.t)).json().members;
    expect(sug.map((m: { nickname: string }) => m.nickname).slice(0, 2)).toEqual(['crimpy', 'bea']);
    expect(sug[0]).toMatchObject({ userId: c.id, followers: 1, followedByMe: false });
    await req('PUT', `/v1/community/follows/${c.id}`, b.t);
    expect(nicks(await req('GET', '/v1/community/members', b.t))).not.toContain('crimpy');
    expect((await req('GET', '/v1/community/members?q=crim', b.t)).json().members[0].followedByMe).toBe(true);
    expect((await req('GET', '/v1/community/follows', b.t)).json().following[0]).toMatchObject({ nickname: 'crimpy', followers: 2, followedByMe: true });

    // Block either way hides them; 3 open member reports hide them.
    await req('POST', '/v1/community/blocks', d.t, { userId: b.id });
    expect(nicks(await req('GET', '/v1/community/members?q=be', b.t))).toEqual(['bea']);
    for (const r of [b, c, d]) await req('POST', '/v1/community/reports', r.t, { userId: e.id, reason: 'spam' });
    expect(nicks(await req('GET', '/v1/community/members?q=bx', a.t))).toEqual(['bxeast']); // new accounts don't hide
    db.prepare("UPDATE users SET created_at = '2026-01-01T00:00:00.000Z'").run(); // reporters' accounts ≥ 7 days old (#432)
    expect(nicks(await req('GET', '/v1/community/members?q=bx', a.t))).toEqual([]);
  });

  it('finds members at your gym or by gym name, only when both show their gym (#152)', async () => {
    const gym = (t: string, g: object | null) => req('PUT', '/v1/me/profile', t, { data: { profile: g ? { gym: g } : {} } });
    const a = await join('a@example.com', 'bea', { showGym: true });
    const b = await join('b@example.com', 'monkey_jy');
    const c = await join('c@example.com', 'crimpy', { showGym: true });
    const d = await join('d@example.com', 'hidden_gym');
    await gym(a.t, { id: 'map:47.38000,8.53000', name: 'Kraftwerk Zürich', latitude: 47.38, longitude: 8.53 });
    await gym(b.t, { id: 'map:47.38010,8.53010', name: 'kraftwerk zürich', latitude: 47.3801, longitude: 8.5301 });
    await gym(c.t, null); // default gym
    await gym(d.t, { id: 'map:47.38000,8.53000', name: 'Kraftwerk Zürich', latitude: 47.38, longitude: 8.53 });
    const nicks = (r: { json(): { members: { nickname: string }[] } }) => r.json().members.map((m) => m.nickname);

    // b doesn't show their gym yet: no gym list, gym hidden on their rows.
    expect(nicks(await req('GET', '/v1/community/members?gym=mine', b.t))).toEqual([]);
    expect((await req('GET', '/v1/community/members?q=hidden', b.t)).json().members[0].gym).toBeNull();
    expect((await req('PUT', '/v1/community/me', b.t, { showGym: true })).json().profile).toMatchObject({ showGym: true, gym: 'kraftwerk zürich' });
    // Same name within a few metres counts; d does not show theirs.
    expect(nicks(await req('GET', '/v1/community/members?gym=mine', b.t))).toEqual(['bea']);
    expect((await req('GET', '/v1/community/members?gym=mine', b.t)).json().members[0].gym).toBe('Kraftwerk Zürich');
    expect(nicks(await req('GET', '/v1/community/members?gym=mine', a.t))).toEqual(['monkey_jy']);
    // Text search matches shown gym names too (default gym when none saved).
    expect(nicks(await req('GET', '/v1/community/members?q=Kraftwerk', c.t))).toEqual(['bea', 'monkey_jy']);
    expect(nicks(await req('GET', '/v1/community/members?q=puls 5', a.t))).toEqual(['crimpy']);
    expect((await req('GET', `/v1/community/members/${a.id}`, c.t)).json().member.gym).toBe('Kraftwerk Zürich');
    // Blocks apply.
    await req('POST', '/v1/community/blocks', a.t, { userId: b.id });
    expect(nicks(await req('GET', '/v1/community/members?gym=mine', b.t))).toEqual([]);
  });

  it('dedupes by refId, filters captions and paginates', async () => {
    const a = await join('a@example.com', 'bea');
    const first = (await share(a.t, { refId: 'w1', caption: 'v1' })).json().post;
    const again = (await share(a.t, { refId: 'w1', caption: 'v2' })).json().post;
    expect(again.id).toBe(first.id);
    expect(again.caption).toBe('v2');
    expect((await share(a.t, { caption: 'you are a b1tch' })).json().error).toBe('objectionable_content');
    expect((await share(a.t, { payload: { title: 'shit day' } })).json().error).toBe('objectionable_content');
    for (let i = 0; i < 4; i++) {
      tick();
      await share(a.t);
    }
    const p1 = (await req('GET', '/v1/community/feed?scope=mine&limit=3', a.t)).json();
    expect(p1.posts).toHaveLength(3);
    const p2 = (await req('GET', `/v1/community/feed?scope=mine&limit=3&before=${encodeURIComponent(p1.nextBefore)}`, a.t)).json();
    expect(p2.posts).toHaveLength(2);
    expect(p2.nextBefore).toBeNull();
  });

  it('pages through posts of the same moment with beforeId (#432)', async () => {
    const a = await join('a@example.com', 'bea');
    for (let i = 0; i < 5; i++) await share(a.t);
    const p1 = (await req('GET', '/v1/community/feed?scope=mine&limit=3', a.t)).json();
    expect(p1.nextBeforeId).toBe(p1.posts[2].id);
    // Old apps (before alone) still get a valid page.
    expect((await req('GET', `/v1/community/feed?scope=mine&limit=3&before=${encodeURIComponent(p1.nextBefore)}`, a.t)).statusCode).toBe(200);
    const p2 = (await req('GET', `/v1/community/feed?scope=mine&limit=3&before=${encodeURIComponent(p1.nextBefore)}&beforeId=${p1.nextBeforeId}`, a.t)).json();
    const ids = [...p1.posts, ...p2.posts].map((p: { id: string }) => p.id);
    expect(new Set(ids).size).toBe(5);
    expect(p2.nextBefore).toBeNull();
  });

  it('reports notify moderation and auto-hide after 3 reporters', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'public' });
    const post = (await share(a.t)).json().post;
    expect((await app.inject({ method: 'GET', url: `/share/${post.id}` })).statusCode).toBe(200);
    expect((await req('POST', '/v1/community/reports', a.t, { postId: post.id, reason: 'spam' })).statusCode).toBe(400);
    const reporters = [await join('b@example.com', 'b_b'), await join('c@example.com', 'c_c'), await join('d@example.com', 'd_d')];
    db.prepare("UPDATE users SET created_at = '2026-01-01T00:00:00.000Z'").run(); // reporters' accounts ≥ 7 days old (#432)
    // A fresh sign-up's report reaches moderation but doesn't count towards auto-hide.
    expect((await req('POST', '/v1/community/reports', (await join('g@example.com', 'g_g')).t, { postId: post.id, reason: 'spam' })).json().hidden).toBe(false);
    for (const [i, r] of reporters.entries()) {
      const res = await req('POST', '/v1/community/reports', r.t, { postId: post.id, reason: 'harassment', details: 'mean' });
      expect(res.statusCode).toBe(202);
      expect(res.json().hidden).toBe(i === 2);
    }
    expect(mailer.outbox.filter((m) => m.to === 'mod@example.com')).toHaveLength(4);
    expect((await req('GET', '/v1/community/feed', reporters[0]!.t)).json().posts).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: `/share/${post.id}` })).statusCode).toBe(404);
    // owner still sees it, flagged hidden
    expect((await req('GET', '/v1/community/feed?scope=mine', a.t)).json().posts[0].hidden).toBe(true);
    expect((await req('POST', '/v1/community/reports', reporters[0]!.t, { userId: a.id, reason: 'spam' })).statusCode).toBe(202);
  });

  it('public share page escapes content and hides non-public posts', async () => {
    const a = await join('a@example.com', 'bea');
    const post = (await share(a.t, { visibility: 'public', caption: '<script>alert(1)</script>' })).json().post;
    const page = await app.inject({ method: 'GET', url: `/share/${post.id}` });
    expect(page.body).toContain('Upper body power');
    expect(page.body).not.toContain('<script>');
    const members = (await share(a.t, { visibility: 'members' })).json().post;
    expect((await app.inject({ method: 'GET', url: `/share/${members.id}` })).statusCode).toBe(404);
  });

  it('is exported, leaving deletes content, account deletion removes everything', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'members' });
    const b = await join('b@example.com', 'monkey_jy');
    const post = (await share(a.t)).json().post;
    await req('PUT', `/v1/community/posts/${post.id}/reactions/clap`, b.t);
    const ex = (await req('GET', '/v1/me/export', b.t)).json().community;
    expect(ex.profile.nickname).toBe('monkey_jy');
    expect(ex.reactionsGiven).toHaveLength(1);
    expect((await req('DELETE', '/v1/community/me', b.t)).statusCode).toBe(204);
    expect((await req('GET', '/v1/community/me', b.t)).json().profile).toBeNull();
    expect((db.prepare('SELECT COUNT(*) AS n FROM community_reactions').get() as { n: number }).n).toBe(0);
    await app.inject({ method: 'DELETE', url: '/v1/me', headers: h(a.t), payload: { password: PW, confirm: 'DELETE' } });
    for (const t of ['community_profiles', 'community_posts'])
      expect((db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get() as { n: number }).n).toBe(0);
  });
});

describe('account profile (#108)', () => {
  it('is set on Account before joining, prefills join, stays in sync and survives leaving', async () => {
    const u = await signUp('a@example.com');
    expect((await req('GET', '/v1/me/public-profile', u.t)).json().profile).toEqual({ nickname: null, bio: null, avatarUrl: null, member: false });
    expect((await req('PUT', '/v1/me/public-profile', u.t, { nickname: 'x' })).statusCode).toBe(400);
    let p = (await req('PUT', '/v1/me/public-profile', u.t, { nickname: 'monkey_jy', bio: 'Climber who lifts' })).json().profile;
    expect(p).toMatchObject({ nickname: 'monkey_jy', bio: 'Climber who lifts', member: false });
    const up = await app.inject({ method: 'PUT', url: '/v1/me/public-profile/avatar', headers: { ...h(u.t), 'content-type': 'image/jpeg' }, payload: jpeg() });
    expect(up.statusCode).toBe(200);
    const avatar = up.json().profile.avatarUrl as string;
    expect(avatar).toMatch(/^\/v1\/community\/avatars\//);

    // Nickname reserved across account-only profiles and members.
    const other = await signUp('b@example.com');
    expect((await req('PUT', '/v1/community/me', other.t, { nickname: 'MONKEY_JY', acceptGuidelines: true })).statusCode).toBe(409);
    expect((await req('PUT', '/v1/me/public-profile', other.t, { nickname: 'monkey_jy' })).statusCode).toBe(409);

    // Join without resending nickname, about or photo.
    const j = await req('PUT', '/v1/community/me', u.t, { acceptGuidelines: true });
    expect(j.statusCode).toBe(200);
    expect(j.json().profile).toMatchObject({ nickname: 'monkey_jy', bio: 'Climber who lifts', avatarUrl: avatar });
    expect((db.prepare('SELECT COUNT(*) AS n FROM user_profiles').get() as { n: number }).n).toBe(0);

    // Account edits show in Community and vice versa.
    await req('PUT', '/v1/me/public-profile', u.t, { bio: 'Edited on Account' });
    expect((await req('GET', '/v1/community/me', u.t)).json().profile.bio).toBe('Edited on Account');
    await req('PUT', '/v1/community/me', u.t, { nickname: 'jy_lifts', bio: 'Edited in Community' });
    p = (await req('GET', '/v1/me/public-profile', u.t)).json().profile;
    expect(p).toMatchObject({ nickname: 'jy_lifts', bio: 'Edited in Community', avatarUrl: avatar, member: true });
    expect((await req('PUT', '/v1/me/public-profile', u.t, { nickname: '' })).statusCode).toBe(400);

    // Leaving keeps nickname and about on Account; the photo is removed with the community profile (#713).
    expect((await req('DELETE', '/v1/community/me', u.t)).statusCode).toBe(204);
    p = (await req('GET', '/v1/me/public-profile', u.t)).json().profile;
    expect(p).toEqual({ nickname: 'jy_lifts', bio: 'Edited in Community', avatarUrl: null, member: false });
    expect((await app.inject({ method: 'GET', url: avatar })).statusCode).toBe(404);
    expect((await req('GET', '/v1/me/export', u.t)).json().community.accountProfile.nickname).toBe('jy_lifts');

    // Clearing on Account; join then needs a nickname.
    await req('DELETE', '/v1/me/public-profile/avatar', u.t);
    await req('PUT', '/v1/me/public-profile', u.t, { nickname: null });
    expect((await req('PUT', '/v1/community/me', u.t, { acceptGuidelines: true })).json().error).toBe('nickname_required');
    await app.inject({ method: 'DELETE', url: '/v1/me', headers: h(u.t), payload: { password: PW, confirm: 'DELETE' } });
    expect((db.prepare('SELECT COUNT(*) AS n FROM user_profiles').get() as { n: number }).n).toBe(0);
  });
});

describe('filter & image helpers', () => {
  it('flags only objectionable words', () => {
    for (const s of ['F U C K', 'sh1t', 'fuuuuck', 'Connard', 'Salopé', 'bitch!']) expect(isObjectionable(s), s).toBe(true);
    for (const s of ['Bench 80 kg', 'Scunthorpe', 'Push day 💪', 'cumulative volume', 'Shiitake', null]) expect(isObjectionable(s), String(s)).toBe(false);
  });
  it('keeps image data after SOS untouched', () => {
    const out = sanitizeJpeg(jpeg(128, 96));
    expect(out).toMatchObject({ width: 128, height: 96 });
    expect(out.data.subarray(-2)).toEqual(Buffer.from([0xff, 0xd9]));
  });
});

describe('community reactions migration (#566)', () => {
  it('rebuilds the old kind CHECK and keeps existing cheers', async () => {
    const a = await join('mig-a@example.com', 'mig_a');
    const b = await join('mig-b@example.com', 'mig_b');
    const post = (await share(a.t, { visibility: 'members' })).json().post;
    await req('PUT', `/v1/community/posts/${post.id}/reactions/clap`, b.t);
    db.exec(`
      CREATE TABLE old_reactions (
        post_id TEXT NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK (kind IN ('like', 'strong', 'fire', 'clap')),
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, user_id, kind)
      );
      INSERT INTO old_reactions SELECT * FROM community_reactions;
      DROP TABLE community_reactions;
      ALTER TABLE old_reactions RENAME TO community_reactions;
    `);
    ensureCommunitySchema(db);
    ensureCommunitySchema(db);
    const r = (await req('PUT', `/v1/community/posts/${post.id}/reactions/beast`, b.t)).json().post;
    expect(r.reactions).toMatchObject({ clap: 1, beast: 1 });
  });
});
