import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AppleIdentity } from '../src/apple.ts';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';
const EMAIL = 'climber@example.com';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
const appleIds = new Map<string, AppleIdentity>();

const setup = (env: Record<string, string> = {}) => {
  clock = new Date('2026-10-07T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...env }),
    db: openDb(':memory:'),
    mailer,
    apple: async (t) => {
      const id = appleIds.get(t);
      if (!id) throw new Error('bad token');
      return id;
    },
    now: () => clock,
  });
};
const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));

const post = (url: string, payload: object, token?: string) =>
  app.inject({ method: 'POST', url, payload, headers: token ? { authorization: `Bearer ${token}` } : {} });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${token}` } });
const lastCode = () => {
  const m = [...mailer.outbox].reverse().find((x) => /\d{6} is your code/.test(x.subject));
  return m!.subject.match(/(\d{6})/)![1]!;
};

const signUp = async (email = EMAIL, password = PW) => {
  expect((await post('/v1/auth/register', { email, password, acceptedTerms: true })).statusCode).toBe(202);
  const res = await post('/v1/auth/verify-email', { email, code: lastCode() });
  expect(res.statusCode).toBe(200);
  return res.json() as { user: { id: string }; tokens: { accessToken: string; refreshToken: string } };
};

beforeEach(() => setup());
afterEach(() => app.close());

describe('registration & verification', () => {
  it('registers, requires verification, then signs in', async () => {
    const r = await post('/v1/auth/register', { email: ' Climber@Example.com ', password: PW, acceptedTerms: true, name: 'JY' });
    expect(r.statusCode).toBe(202);
    expect(mailer.outbox).toHaveLength(1);
    expect(mailer.outbox[0]!.to).toBe(EMAIL);

    const early = await post('/v1/auth/login', { email: EMAIL, password: PW });
    expect(early.statusCode).toBe(403);
    expect(early.json().error).toBe('email_not_verified');

    expect((await post('/v1/auth/verify-email', { email: EMAIL, code: '000000' === lastCode() ? '111111' : '000000' })).statusCode).toBe(400);
    const ok = await post('/v1/auth/verify-email', { email: EMAIL, code: lastCode() });
    expect(ok.statusCode).toBe(200);
    const { tokens, user } = ok.json();
    expect(user.emailVerified).toBe(true);

    const me = await get('/v1/me', tokens.accessToken);
    expect(me.json().user).toMatchObject({ email: EMAIL, name: 'JY', hasPassword: true, appleLinked: false });
    expect(JSON.stringify(me.json())).not.toContain('password_hash');
  });

  it('is enumeration-safe for existing verified accounts', async () => {
    await signUp();
    const n = mailer.outbox.length;
    const r = await post('/v1/auth/register', { email: EMAIL, password: 'another-long-pass', acceptedTerms: true });
    expect(r.statusCode).toBe(202);
    expect(mailer.outbox[n]!.subject).toContain('already have an account');
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(200);
  });

  it('enforces terms and password policy', async () => {
    expect((await post('/v1/auth/register', { email: EMAIL, password: PW, acceptedTerms: false })).json().error).toBe('terms_required');
    expect((await post('/v1/auth/register', { email: EMAIL, password: 'short', acceptedTerms: true })).json().error).toBe('weak_password');
    expect((await post('/v1/auth/register', { email: EMAIL, password: 'climber-rocks-2026', acceptedTerms: true })).json().error).toBe(
      'weak_password',
    );
    expect((await post('/v1/auth/register', { email: 'nope', password: PW, acceptedTerms: true })).json().error).toBe('invalid_request');
  });

  it('burns code after 5 wrong attempts and expires codes', async () => {
    await post('/v1/auth/register', { email: EMAIL, password: PW, acceptedTerms: true });
    const good = lastCode();
    const bad = good === '123456' ? '654321' : '123456';
    for (let i = 0; i < 4; i++) expect((await post('/v1/auth/verify-email', { email: EMAIL, code: bad })).json().error).toBe('invalid_code');
    expect((await post('/v1/auth/verify-email', { email: EMAIL, code: bad })).json().error).toBe('too_many_attempts');
    expect((await post('/v1/auth/verify-email', { email: EMAIL, code: good })).statusCode).toBe(400);

    advance(61_000);
    await post('/v1/auth/resend-verification', { email: EMAIL });
    const fresh = lastCode();
    advance(16 * 60_000);
    expect((await post('/v1/auth/verify-email', { email: EMAIL, code: fresh })).statusCode).toBe(400);
  });

  it('throttles resend to one per minute', async () => {
    await post('/v1/auth/register', { email: EMAIL, password: PW, acceptedTerms: true });
    await post('/v1/auth/resend-verification', { email: EMAIL });
    expect(mailer.outbox).toHaveLength(1);
    advance(61_000);
    await post('/v1/auth/resend-verification', { email: EMAIL });
    expect(mailer.outbox).toHaveLength(2);
  });
});

describe('login & sessions', () => {
  it('rejects bad credentials uniformly and locks after 10 failures', async () => {
    await signUp();
    expect((await post('/v1/auth/login', { email: 'ghost@example.com', password: PW })).json().error).toBe('invalid_credentials');
    for (let i = 0; i < 10; i++) expect((await post('/v1/auth/login', { email: EMAIL, password: 'wrong-password!' })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(429);
    advance(16 * 60_000);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(200);
  });

  it('rotates refresh tokens and revokes family on reuse', async () => {
    const { tokens } = await signUp();
    const r1 = await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(r1.statusCode).toBe(200);
    const t2 = r1.json().refreshToken as string;
    expect(t2).not.toBe(tokens.refreshToken);
    // replay of old token → family revoked
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: t2 })).statusCode).toBe(401);
  });

  it('expires access tokens', async () => {
    const { tokens } = await signUp();
    expect((await get('/v1/me', tokens.accessToken)).statusCode).toBe(200);
    advance(16 * 60_000);
    expect((await get('/v1/me', tokens.accessToken)).json().error).toBe('invalid_token');
  });

  it('logout and logout-all revoke refresh tokens', async () => {
    const a = await signUp();
    expect((await post('/v1/auth/logout', { refreshToken: a.tokens.refreshToken })).statusCode).toBe(204);
    expect((await post('/v1/auth/refresh', { refreshToken: a.tokens.refreshToken })).statusCode).toBe(401);

    const b = (await post('/v1/auth/login', { email: EMAIL, password: PW })).json();
    const c = (await post('/v1/auth/login', { email: EMAIL, password: PW })).json();
    expect((await get('/v1/me/sessions', c.tokens.accessToken)).json().sessions).toHaveLength(2);
    expect((await post('/v1/me/logout-all', {}, c.tokens.accessToken)).statusCode).toBe(204);
    expect((await post('/v1/auth/refresh', { refreshToken: b.tokens.refreshToken })).statusCode).toBe(401);
  });

  it('rejects requests without token', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/me' })).statusCode).toBe(401);
  });
});

describe('password reset & change', () => {
  it('resets via emailed code and signs out everywhere', async () => {
    const { tokens } = await signUp();
    expect((await post('/v1/auth/password/forgot', { email: EMAIL })).statusCode).toBe(202);
    expect((await post('/v1/auth/password/forgot', { email: 'ghost@example.com' })).statusCode).toBe(202);
    const code = lastCode();
    expect((await post('/v1/auth/password/reset', { email: EMAIL, code, newPassword: 'brand-new-secret-9' })).statusCode).toBe(204);
    expect(mailer.outbox.at(-1)!.subject).toContain('password changed');
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: EMAIL, password: 'brand-new-secret-9' })).statusCode).toBe(200);
    expect((await post('/v1/auth/password/reset', { email: EMAIL, code, newPassword: 'another-secret-10' })).statusCode).toBe(400);
  });

  it('changes password with current password', async () => {
    const { tokens } = await signUp();
    expect((await post('/v1/me/password', { currentPassword: 'nope-nope-nope', newPassword: 'brand-new-secret-9' }, tokens.accessToken)).statusCode).toBe(401);
    const ok = await post('/v1/me/password', { currentPassword: PW, newPassword: 'brand-new-secret-9' }, tokens.accessToken);
    expect(ok.statusCode).toBe(200);
    expect(ok.json().tokens.refreshToken).toBeTruthy();
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
  });
});

describe('Sign in with Apple', () => {
  it('creates, re-uses and links accounts', async () => {
    appleIds.set('tok-new-identity-token', { sub: 'apple-1', email: 'relay@privaterelay.appleid.com', emailVerified: true });
    const a = await post('/v1/auth/apple', { identityToken: 'tok-new-identity-token', name: 'JY' });
    expect(a.statusCode).toBe(200);
    expect(a.json()).toMatchObject({ created: true, user: { appleLinked: true, hasPassword: false, emailVerified: true, name: 'JY' } });
    const again = await post('/v1/auth/apple', { identityToken: 'tok-new-identity-token' });
    expect(again.json()).toMatchObject({ created: false, user: { id: a.json().user.id } });

    const { user } = await signUp();
    appleIds.set('tok-link-identity-token', { sub: 'apple-2', email: EMAIL, emailVerified: true });
    const linked = await post('/v1/auth/apple', { identityToken: 'tok-link-identity-token' });
    expect(linked.json()).toMatchObject({ created: false, user: { id: user.id, appleLinked: true, hasPassword: true } });

    expect((await post('/v1/auth/apple', { identityToken: 'forged-token' })).json().error).toBe('invalid_apple_token');
  });

  it('lets apple-only users delete without password', async () => {
    appleIds.set('tok-del-identity-token', { sub: 'apple-3', email: 'x@privaterelay.appleid.com', emailVerified: true });
    const { tokens } = (await post('/v1/auth/apple', { identityToken: 'tok-del-identity-token' })).json();
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { confirm: 'DELETE' }, headers: { authorization: `Bearer ${tokens.accessToken}` } });
    expect(del.statusCode).toBe(204);
  });
});

describe('account deletion, data sync & export', () => {
  it('syncs profile and logs, exports, then deletes everything', async () => {
    const { tokens } = await signUp();
    const t = tokens.accessToken;
    expect((await get('/v1/me/profile', t)).json().data).toBeNull();
    const put = await app.inject({
      method: 'PUT',
      url: '/v1/me/profile',
      payload: { data: { goal: 'climbing', sessionsPerWeek: 4 } },
      headers: { authorization: `Bearer ${t}` },
    });
    expect(put.statusCode).toBe(200);
    expect((await get('/v1/me/profile', t)).json().data).toEqual({ goal: 'climbing', sessionsPerWeek: 4 });

    const id = randomUUID();
    const log = { id, date: '2026-10-07T10:00:00Z', exerciseId: 'back-squat', weightKg: 80, reps: 5 };
    expect((await post('/v1/me/logs', { logs: [log] }, t)).json().saved).toBe(1);
    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    await post('/v1/me/logs', { logs: [{ ...log, weightKg: 82.5 }] }, t);
    const delta = (await get(`/v1/me/logs?since=${encodeURIComponent(since)}`, t)).json().logs;
    expect(delta).toHaveLength(1);
    expect(delta[0].weightKg).toBe(82.5);

    // another user cannot overwrite or see it
    const other = await signUp('other@example.com');
    await post('/v1/me/logs', { logs: [{ ...log, weightKg: 1 }] }, other.tokens.accessToken);
    expect((await get('/v1/me/logs', other.tokens.accessToken)).json().logs).toHaveLength(0);
    expect((await get('/v1/me/logs', t)).json().logs[0].weightKg).toBe(82.5);

    const exp = (await get('/v1/me/export', t)).json();
    expect(exp.user.email).toBe(EMAIL);
    expect(exp.logs).toHaveLength(1);
    expect(exp.profile.data.goal).toBe('climbing');

    const del = (payload: object) =>
      app.inject({ method: 'DELETE', url: '/v1/me', payload, headers: { authorization: `Bearer ${t}` } });
    expect((await del({ password: PW })).statusCode).toBe(400);
    expect((await del({ password: 'wrong-password!', confirm: 'DELETE' })).statusCode).toBe(401);
    expect((await del({ password: PW, confirm: 'DELETE' })).statusCode).toBe(204);
    expect((await get('/v1/me', t)).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(401);
    expect(mailer.outbox.at(-1)!.subject).toContain('account deleted');
  });

  it('validates log payloads', async () => {
    const { tokens } = await signUp();
    const bad = await post('/v1/me/logs', { logs: [{ id: 'x', date: 'nope', exerciseId: '' }] }, tokens.accessToken);
    expect(bad.statusCode).toBe(400);
  });
});

describe('rate limiting', () => {
  it('limits auth endpoints per IP', async () => {
    await app.close();
    setup({ AUTH_RATE_LIMIT_PER_MIN: '3' });
    const codes = [];
    for (let i = 0; i < 4; i++) codes.push((await post('/v1/auth/password/forgot', { email: EMAIL })).statusCode);
    expect(codes).toEqual([202, 202, 202, 429]);
  });
});
