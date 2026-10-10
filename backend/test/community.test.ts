import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { isObjectionable } from '../src/community/filter.ts';
import { sanitizeJpeg } from '../src/community/image.ts';
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
    expect(ok.json().profile).toMatchObject({ nickname: 'monkey_jy', bio: 'Climber who lifts', defaultVisibility: 'private', autoShare: false, avatarUrl: null });
    // later edits need no re-acceptance and keep omitted fields
    const ed = await req('PUT', '/v1/community/me', a.t, { nickname: 'monkey_jy', defaultVisibility: 'members' });
    expect(ed.json().profile).toMatchObject({ bio: 'Climber who lifts', defaultVisibility: 'members' });
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

describe('community feed', () => {
  it('honours visibility, cheers, blocks and deletion', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'members' });
    const b = await join('b@example.com', 'monkey_jy');
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

  it('reports notify moderation and auto-hide after 3 reporters', async () => {
    const a = await join('a@example.com', 'bea', { defaultVisibility: 'public' });
    const post = (await share(a.t)).json().post;
    expect((await app.inject({ method: 'GET', url: `/share/${post.id}` })).statusCode).toBe(200);
    expect((await req('POST', '/v1/community/reports', a.t, { postId: post.id, reason: 'spam' })).statusCode).toBe(400);
    const reporters = [await join('b@example.com', 'b_b'), await join('c@example.com', 'c_c'), await join('d@example.com', 'd_d')];
    for (const [i, r] of reporters.entries()) {
      const res = await req('POST', '/v1/community/reports', r.t, { postId: post.id, reason: 'harassment', details: 'mean' });
      expect(res.statusCode).toBe(202);
      expect(res.json().hidden).toBe(i === 2);
    }
    expect(mailer.outbox.filter((m) => m.to === 'mod@example.com')).toHaveLength(3);
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
