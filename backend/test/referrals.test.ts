import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

/** Invite a friend (#745): codes, redeem rules, joined/subscribed counts, invite page; socials on profiles. */

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-25T10:00:00Z');
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

const req = (method: 'GET' | 'POST' | 'PUT', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  return { t: j.tokens.accessToken, id: j.user.id };
};

const join = async (email: string, nickname: string) => {
  const u = await signUp(email);
  expect((await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true })).statusCode).toBe(200);
  return u;
};

const paid = (userId: string, trial: boolean) =>
  db
    .prepare(
      `INSERT INTO app_store_subscriptions (original_transaction_id, user_id, product_id, last_transaction_id, environment, trial, updated_at)
       VALUES (?, ?, 'monkeyworkout.pro.monthly', 't', 'Sandbox', ?, ?)`,
    )
    .run(`ot-${userId}`, userId, Number(trial), clock.toISOString());

describe('referrals', () => {
  it('gives a stable code and counts joined and paid friends', async () => {
    const a = await join('a@example.com', 'Djy');
    const first = (await req('GET', '/v1/referrals/me', a.t)).json();
    expect(first.code).toMatch(/^[A-HJKMNP-Z2-9]{7}$/);
    expect(first.path).toBe(`/i/${first.code}`);
    expect((await req('GET', '/v1/referrals/me', a.t)).json().code).toBe(first.code);

    const b = await signUp('b@example.com');
    const red = await req('POST', '/v1/referrals/redeem', b.t, { code: first.code.toLowerCase() });
    expect(red.statusCode).toBe(200);
    expect(red.json().invitedBy.nickname).toBe('Djy');
    expect(red.json().canRedeem).toBe(false);

    expect((await req('GET', '/v1/referrals/me', a.t)).json()).toMatchObject({ joined: 1, subscribed: 0 });
    paid(b.id, true);
    expect((await req('GET', '/v1/referrals/me', a.t)).json().subscribed).toBe(0);
    db.prepare('UPDATE app_store_subscriptions SET trial = 0').run();
    expect((await req('GET', '/v1/referrals/me', a.t)).json().subscribed).toBe(1);
  });

  it('refuses own, unknown, second, cyclic and late codes', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    const c = await signUp('c@example.com');
    const codeA = (await req('GET', '/v1/referrals/me', a.t)).json().code;
    const codeB = (await req('GET', '/v1/referrals/me', b.t)).json().code;
    const codeC = (await req('GET', '/v1/referrals/me', c.t)).json().code;
    expect((await req('POST', '/v1/referrals/redeem', a.t, { code: codeA })).json().error).toBe('own_code');
    expect((await req('POST', '/v1/referrals/redeem', a.t, { code: 'ZZZZZZZ' })).json().error).toBe('invalid_code');
    expect((await req('POST', '/v1/referrals/redeem', b.t, { code: codeA })).statusCode).toBe(200);
    expect((await req('POST', '/v1/referrals/redeem', b.t, { code: codeC })).json().error).toBe('already_redeemed');
    expect((await req('POST', '/v1/referrals/redeem', a.t, { code: codeB })).json().error).toBe('referral_cycle');
    db.prepare('UPDATE users SET created_at = ? WHERE id = ?').run(new Date(clock.getTime() - 15 * 86_400_000).toISOString(), c.id);
    expect((await req('POST', '/v1/referrals/redeem', c.t, { code: codeA })).json().error).toBe('account_too_old');
  });

  it('serves the invite page with the code, escaped', async () => {
    const a = await join('a@example.com', 'Djy');
    const { code } = (await req('GET', '/v1/referrals/me', a.t)).json();
    const page = await app.inject({ method: 'GET', url: `/i/${code}` });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain(code);
    expect(page.body).toContain('Djy invites you');
    expect((await app.inject({ method: 'GET', url: '/i/NOPE123' })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/i/%3Cscript%3E' })).statusCode).toBe(404);
  });
});

describe('socials on the profile', () => {
  it('saves handles and shows them by visibility', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Bob');
    const put = await req('PUT', '/v1/community/me/socials', a.t, { socials: { instagram: '@djy.lifts', tiktok: '', strava: 'djy' } });
    expect(put.json()).toEqual({ socials: { instagram: 'djy.lifts', strava: 'djy' }, visibility: 'following' });
    expect((await req('PUT', '/v1/community/me/socials', a.t, { socials: { instagram: 'bad handle!' } })).statusCode).toBe(400);
    expect((await req('GET', '/v1/community/me', a.t)).json().profile.socials.instagram).toBe('djy.lifts');

    const view = async () => (await req('GET', `/v1/community/members/${a.id}`, b.t)).json().member.socials;
    expect(await view()).toBeNull();
    await req('PUT', `/v1/community/follows/${a.id}`, b.t);
    expect((await view()).instagram).toBe('djy.lifts');
    await req('PUT', '/v1/community/me/socials', a.t, { socials: { instagram: 'djy.lifts' }, visibility: 'nobody' });
    expect(await view()).toBeNull();
    expect((await req('GET', `/v1/community/members/${a.id}`, a.t)).json().member.socials.instagram).toBe('djy.lifts');
  });
});

describe('find a friend (#747)', () => {
  const codeOf = async (t: string) => ((await req('GET', '/v1/referrals/me', t)).json() as { code: string }).code;
  const follows = (a: string, b: string) => !!db.prepare('SELECT 1 FROM community_follows WHERE follower_id = ? AND followed_id = ?').get(a, b);

  it('finds a member by code and says when they have not joined Social', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await signUp('b@example.com');
    const code = await codeOf(b.t);
    const before = await req('GET', `/v1/community/members/by-code/${code.toLowerCase()}`, a.t);
    expect(before.statusCode).toBe(404);
    expect(before.json().error).toBe('not_joined');
    await req('PUT', '/v1/community/me', b.t, { nickname: 'Marco', acceptGuidelines: true });
    const after = await req('GET', `/v1/community/members/by-code/${code}`, a.t);
    expect(after.statusCode).toBe(200);
    expect(after.json().member).toMatchObject({ userId: b.id, nickname: 'Marco', followedByMe: false });
    expect((await req('GET', `/v1/community/members/by-code/${await codeOf(a.t)}`, a.t)).json().error).toBe('own_code');
    expect((await req('GET', '/v1/community/members/by-code/ZZZZZZZ', a.t)).json().error).toBe('invalid_code');
  });

  it('makes inviter and invitee follow each other once both are in Social', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await signUp('b@example.com');
    expect((await req('POST', '/v1/referrals/redeem', b.t, { code: await codeOf(a.t) })).statusCode).toBe(200);
    expect(follows(a.id, b.id)).toBe(false);
    await req('PUT', '/v1/community/me', b.t, { nickname: 'Marco', acceptGuidelines: true });
    expect(follows(a.id, b.id) && follows(b.id, a.id)).toBe(true);
  });

  it('follows right away when both already joined', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Marco');
    await req('POST', '/v1/referrals/redeem', b.t, { code: await codeOf(a.t) });
    expect(follows(a.id, b.id) && follows(b.id, a.id)).toBe(true);
  });
});
