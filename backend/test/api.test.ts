import { createHash, randomUUID } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { type AppleIdentity, audienceAllowed } from '../src/apple.ts';
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

describe('health', () => {
  it('reports mail transport', async () => {
    const r = await app.inject({ method: 'GET', url: '/healthz' });
    expect(r.json()).toEqual({ ok: true, mail: 'console' });
  });
});

describe('compression', () => {
  it('compresses JSON over 1 KB when asked, leaves small and unasked responses alone', async () => {
    const { tokens } = await signUp();
    const logs = Array.from({ length: 40 }, () => ({ id: randomUUID(), date: '2026-10-07T18:00:00Z', exerciseId: 'bench', weightKg: 60, reps: 8 }));
    await post('/v1/me/logs', { logs }, tokens.accessToken);
    const headers = { authorization: `Bearer ${tokens.accessToken}`, 'accept-encoding': 'gzip' };
    const big = await app.inject({ method: 'GET', url: '/v1/me/logs', headers });
    expect(big.headers['content-encoding']).toBe('gzip');
    expect(JSON.parse(gunzipSync(big.rawPayload).toString()).logs).toHaveLength(40);
    const exp = await app.inject({ method: 'GET', url: '/v1/me/export', headers });
    expect(exp.headers['content-encoding']).toBe('gzip');
    expect(JSON.parse(gunzipSync(exp.rawPayload).toString()).logs).toHaveLength(40);
    expect((await app.inject({ method: 'GET', url: '/healthz', headers: { 'accept-encoding': 'gzip' } })).headers['content-encoding']).toBeUndefined();
    expect((await get('/v1/me/logs', tokens.accessToken)).headers['content-encoding']).toBeUndefined();
  });
});

describe('caching (#310)', () => {
  it('marks personal responses no-store, leaves public ones alone', async () => {
    const { tokens } = await signUp();
    expect((await get('/v1/me/profile', tokens.accessToken)).headers['cache-control']).toBe('no-store');
    expect((await app.inject({ method: 'GET', url: '/healthz' })).headers['cache-control']).toBeUndefined();
  });
});

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
  it('rejects bad credentials uniformly and locks the IP after 10 failures', async () => {
    await signUp();
    expect((await post('/v1/auth/login', { email: 'ghost@example.com', password: PW })).json().error).toBe('invalid_credentials');
    for (let i = 0; i < 10; i++) expect((await post('/v1/auth/login', { email: EMAIL, password: 'wrong-password!' })).statusCode).toBe(401);
    const locked = await post('/v1/auth/login', { email: EMAIL, password: PW });
    expect(locked.statusCode).toBe(429);
    expect(locked.json()).toMatchObject({ error: 'account_locked', lockedUntil: new Date(clock.getTime() + 15 * 60_000).toISOString() });
    advance(16 * 60_000);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(200);
  });

  // #432: a stranger's guesses lock only their own IP, not the owner's.
  const loginFrom = (ip: string, password: string) =>
    app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: EMAIL, password }, headers: { 'fly-client-ip': ip } });

  it('lockout from one IP leaves other IPs able to sign in', async () => {
    await signUp();
    for (let i = 0; i < 10; i++) expect((await loginFrom('203.0.113.9', 'wrong-password!')).statusCode).toBe(401);
    expect((await loginFrom('203.0.113.9', PW)).json().error).toBe('account_locked');
    expect((await loginFrom('198.51.100.7', PW)).statusCode).toBe(200);
  });

  it('100 failures a day across IPs lock password sign-in for a day; a reset reopens it', async () => {
    await signUp();
    for (let i = 0; i < 100; i++) expect((await loginFrom(`203.0.113.${i}`, 'wrong-password!')).statusCode).toBe(401);
    const r = await loginFrom('198.51.100.7', PW);
    expect(r.statusCode).toBe(429);
    expect(r.json()).toMatchObject({ error: 'account_locked', lockedUntil: new Date(clock.getTime() + 86_400_000).toISOString() });
    advance(86_400_000 + 1000);
    expect((await loginFrom('198.51.100.7', PW)).statusCode).toBe(200);
    for (let i = 0; i < 100; i++) await loginFrom(`203.0.113.${i}`, 'wrong-password!');
    expect((await loginFrom('198.51.100.7', PW)).json().error).toBe('account_locked');
    await post('/v1/auth/password/forgot', { email: EMAIL });
    const next = 'another-long-password';
    expect((await post('/v1/auth/password/reset', { email: EMAIL, code: lastCode(), newPassword: next })).statusCode).toBe(204);
    expect((await loginFrom('198.51.100.7', next)).statusCode).toBe(200);
  });

  it('rotates refresh tokens and revokes family on reuse', async () => {
    const { tokens } = await signUp();
    const r1 = await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(r1.statusCode).toBe(200);
    const t2 = r1.json().refreshToken as string;
    expect(t2).not.toBe(tokens.refreshToken);
    const r2 = await post('/v1/auth/refresh', { refreshToken: t2 });
    expect(r2.statusCode).toBe(200);
    // replay of old token once its replacement was used → family revoked
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: r2.json().refreshToken })).statusCode).toBe(401);
  });

  it('keeps the session when a refresh response was lost (#469)', async () => {
    const { tokens } = await signUp();
    const lost = (await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).json().refreshToken as string;
    advance(60_000);
    // the app never got `lost` and retries with its old token
    const retry = await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(retry.statusCode).toBe(200);
    const t3 = retry.json().refreshToken as string;
    advance(60_000);
    expect((await post('/v1/auth/refresh', { refreshToken: lost })).statusCode).toBe(401);
    // presenting the undelivered token revoked the family
    expect((await post('/v1/auth/refresh', { refreshToken: t3 })).statusCode).toBe(401);
  });

  it('lost response twice in a row still keeps the session (#469)', async () => {
    const { tokens } = await signUp();
    await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    advance(60_000);
    await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    advance(60_000);
    const r = await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(r.statusCode).toBe(200);
    expect((await post('/v1/auth/refresh', { refreshToken: r.json().refreshToken })).statusCode).toBe(200);
  });

  it('only treats a replay as a lost response shortly after rotation', async () => {
    const { tokens } = await signUp();
    const lost = (await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).json().refreshToken as string;
    advance(6 * 60_000);
    // an old rotated-away token is a replay, even though its replacement was never used
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: lost })).statusCode).toBe(401);
  });

  it('does not reissue for a replayed token past its own expiry', async () => {
    setup({ REFRESH_TTL_DAYS: '1' });
    const { tokens } = await signUp();
    advance(86_400_000 - 60_000);
    const lost = (await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).json().refreshToken as string;
    advance(2 * 60_000);
    expect((await post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: lost })).statusCode).toBe(401);
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

  it('lets apple-only users delete after confirming with Apple (#257)', async () => {
    appleIds.set('tok-del-identity-token', { sub: 'apple-3', email: 'x@privaterelay.appleid.com', emailVerified: true });
    const { tokens } = (await post('/v1/auth/apple', { identityToken: 'tok-del-identity-token' })).json();
    const auth = { authorization: `Bearer ${tokens.accessToken}` };
    const bare = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { confirm: 'DELETE' }, headers: auth });
    expect(bare.statusCode).toBe(403);
    expect(bare.json()).toMatchObject({ error: 'reauth_required', methods: ['apple', 'email_code'] });
    const { reauthToken } = (await post('/v1/me/reauth', { method: 'apple', identityToken: 'tok-del-identity-token' }, tokens.accessToken)).json();
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { confirm: 'DELETE' }, headers: { ...auth, 'x-reauth-token': reauthToken } });
    expect(del.statusCode).toBe(204);
  });

  // #432: a token with a nonce claim needs the matching raw nonce, once.
  it('checks the nonce claim and refuses its replay', async () => {
    const raw = 'n0nce-raw-value-1234567890';
    const hashed = createHash('sha256').update(raw).digest('hex');
    appleIds.set('tok-nonce-identity-token', { sub: 'apple-n', emailVerified: false, nonce: hashed });
    const bad = (b: object) => post('/v1/auth/apple', { identityToken: 'tok-nonce-identity-token', ...b });
    expect((await bad({})).json().error).toBe('invalid_apple_token');
    expect((await bad({ nonce: 'wrong-nonce-value-123456' })).json().error).toBe('invalid_apple_token');
    expect((await bad({ nonce: hashed })).json().error).toBe('invalid_apple_token');
    const ok = await bad({ nonce: raw });
    expect(ok.statusCode).toBe(200);
    expect((await bad({ nonce: raw })).json().error).toBe('invalid_apple_token');

    // Re-auth follows the same rule.
    const t = ok.json().tokens.accessToken as string;
    const raw2 = 'second-raw-nonce-abcdefgh';
    appleIds.set('tok-nonce-reauth-token', { sub: 'apple-n', emailVerified: false, nonce: createHash('sha256').update(raw2).digest('hex') });
    const reauth = (nonce?: string) => post('/v1/me/reauth', { method: 'apple', identityToken: 'tok-nonce-reauth-token', nonce }, t);
    expect((await reauth()).json().error).toBe('reauth_failed');
    expect((await reauth(raw2)).statusCode).toBe(200);
    expect((await reauth(raw2)).json().error).toBe('reauth_failed');
  });
});

describe('account deletion, data sync & export', () => {
  it('accepts logs of a workout added to the plan (long plan-insert session id, #404)', async () => {
    const t = (await signUp()).tokens.accessToken;
    const sessionId = `custom-${randomUUID()}~plan-${randomUUID()}`;
    expect(sessionId.length).toBeGreaterThan(64);
    const log = { id: randomUUID(), date: '2026-10-16T10:00:00Z', exerciseId: 'bench-press', sessionId, weightKg: 60, reps: 8, setIndex: 0 };
    expect((await post('/v1/me/logs', { logs: [log] }, t)).json().saved).toBe(1);
    expect((await get('/v1/me/logs', t)).json().logs[0].sessionId).toBe(sessionId);
  });

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

  it('streams the export as one JSON document, three times an hour at most', async () => {
    const t = (await signUp()).tokens.accessToken;
    const r = await get('/v1/me/export', t);
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-type']).toBe('application/json; charset=utf-8');
    expect(r.headers['content-disposition']).toBe('attachment; filename="gym-workout-export.json"');
    expect(r.headers['cache-control']).toBe('no-store');
    const exp = r.json();
    // same document as JSON.stringify of the whole object, key order kept
    expect(r.body).toBe(JSON.stringify(exp));
    expect(Object.keys(exp).slice(0, 4)).toEqual(['exportedAt', 'user', 'profile', 'logs']);
    expect((await get('/v1/me/export', t)).statusCode).toBe(200);
    expect((await get('/v1/me/export', t)).statusCode).toBe(200);
    const limited = await get('/v1/me/export', t);
    expect(limited.statusCode).toBe(429);
    expect(limited.json().error).toBe('rate_limited');
  });

  it('stores per-set fields (setIndex, rir) and keeps legacy logs working', async () => {
    const { tokens } = await signUp();
    const t = tokens.accessToken;
    const legacy = { id: randomUUID(), date: '2026-10-07T10:00:00Z', exerciseId: 'back-squat', weightKg: 80 };
    const set = { id: randomUUID(), date: '2026-10-07T10:05:00Z', exerciseId: 'back-squat', sessionId: 'w1s1', weightKg: 82.5, reps: 8, setIndex: 1, rir: 2 };
    expect((await post('/v1/me/logs', { logs: [legacy, set] }, t)).json().saved).toBe(2);
    const logs = (await get('/v1/me/logs', t)).json().logs as Record<string, unknown>[];
    const byId = new Map(logs.map((l) => [l.id, l]));
    expect(byId.get(set.id)).toMatchObject({ setIndex: 1, rir: 2, reps: 8, weightKg: 82.5 });
    expect(byId.get(legacy.id)).toMatchObject({ setIndex: null, rir: null, weightKg: 80 });
    // re-pushing without the new fields (old client) clears them like any other upsert
    await post('/v1/me/logs', { logs: [{ ...set, setIndex: undefined, rir: undefined }] }, t);
    const again = (await get('/v1/me/logs', t)).json().logs.find((l: { id: string }) => l.id === set.id);
    expect(again.setIndex).toBeNull();
    for (const bad of [{ setIndex: -1 }, { setIndex: 1.5 }, { rir: 11 }, { rir: -1 }]) {
      expect((await post('/v1/me/logs', { logs: [{ ...set, ...bad }] }, t)).statusCode).toBe(400);
    }
  });

  it('stores a separate lowering load (#792)', async () => {
    const { tokens } = await signUp();
    const t = tokens.accessToken;
    const set = { id: randomUUID(), date: '2026-10-26T10:00:00Z', exerciseId: 'leg-extension', sessionId: 's', weightKg: 26.25, lowerKg: 35, reps: 10, setIndex: 0 };
    const plain = { ...set, id: randomUUID(), lowerKg: undefined, setIndex: 1 };
    expect((await post('/v1/me/logs', { logs: [set, plain] }, t)).json().saved).toBe(2);
    const byId = new Map(((await get('/v1/me/logs', t)).json().logs as Record<string, unknown>[]).map((l) => [l.id, l]));
    expect(byId.get(set.id)).toMatchObject({ weightKg: 26.25, lowerKg: 35 });
    expect(byId.get(plain.id)).toMatchObject({ weightKg: 26.25, lowerKg: null });
    for (const bad of [{ lowerKg: -1 }, { lowerKg: 1001 }]) {
      expect((await post('/v1/me/logs', { logs: [{ ...set, ...bad }] }, t)).statusCode).toBe(400);
    }
  });

  it('validates log payloads', async () => {
    const { tokens } = await signUp();
    const bad = await post('/v1/me/logs', { logs: [{ id: 'x', date: 'nope', exerciseId: '' }] }, tokens.accessToken);
    expect(bad.statusCode).toBe(400);
  });
});

describe('workout history sync', () => {
  it('upserts, deltas, isolates, exports and deletes workouts', async () => {
    const { tokens } = await signUp();
    const t = tokens.accessToken;
    const id = randomUUID();
    const w = { id, startedAt: '2026-10-07T09:00:00Z', title: 'Lower body', durationSec: 3600, exercises: [{ id: 'back-squat', sets: 4 }] };
    expect((await post('/v1/me/workouts', { workouts: [w] }, t)).json().saved).toBe(1);
    const all = (await get('/v1/me/workouts', t)).json().workouts;
    expect(all).toHaveLength(1);
    expect(all[0]).toMatchObject({ id, title: 'Lower body', exercises: [{ id: 'back-squat', sets: 4 }] });

    advance(1000);
    const since = clock.toISOString();
    advance(1000);
    await post('/v1/me/workouts', { workouts: [{ ...w, durationSec: 3700 }] }, t);
    const delta = (await get(`/v1/me/workouts?since=${encodeURIComponent(since)}`, t)).json().workouts;
    expect(delta).toHaveLength(1);
    expect(delta[0].durationSec).toBe(3700);

    const other = await signUp('other@example.com');
    await post('/v1/me/workouts', { workouts: [{ ...w, title: 'hijack' }] }, other.tokens.accessToken);
    expect((await get('/v1/me/workouts', other.tokens.accessToken)).json().workouts).toHaveLength(0);
    expect((await get('/v1/me/workouts', t)).json().workouts[0].title).toBe('Lower body');

    expect((await get('/v1/me/export', t)).json().workouts).toHaveLength(1);
    expect((await app.inject({ method: 'DELETE', url: `/v1/me/workouts/${id}`, headers: { authorization: `Bearer ${t}` } })).statusCode).toBe(204);
    expect((await get('/v1/me/workouts', t)).json().workouts).toHaveLength(0);
  });

  it('rejects malformed workouts', async () => {
    const { tokens } = await signUp();
    expect((await post('/v1/me/workouts', { workouts: [{ id: 'nope', startedAt: 'x' }] }, tokens.accessToken)).statusCode).toBe(400);
  });
});

describe('Apple audience', () => {
  it('matches bundle ids case-insensitively and rejects others', () => {
    const ids = loadConfig({ NODE_ENV: 'test' }).appleBundleIds;
    expect(ids).toContain('Com.app.MonkeyWorkout');
    expect(audienceAllowed('com.app.monkeyworkout', ids)).toBe(true);
    expect(audienceAllowed(['other', 'Com.app.MonkeyWorkout.dev'], ids)).toBe(true);
    expect(audienceAllowed('com.evil.app', ids)).toBe(false);
    expect(audienceAllowed(undefined, ids)).toBe(false);
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

describe('abuse limits (#432)', () => {
  it('keys rate limits on Fly-Client-IP, not a spoofed X-Forwarded-For', async () => {
    await app.close();
    setup({ AUTH_RATE_LIMIT_PER_MIN: '3' });
    const codes = [];
    for (let i = 0; i < 4; i++)
      codes.push(
        (
          await app.inject({
            method: 'POST',
            url: '/v1/auth/password/forgot',
            payload: { email: EMAIL },
            headers: { 'x-forwarded-for': `10.0.0.${i}`, 'fly-client-ip': '203.0.113.9' },
          })
        ).statusCode,
      );
    expect(codes).toEqual([202, 202, 202, 429]);
  });

  it('does not replace a burned reset code at once and caps wrong guesses per account', async () => {
    await signUp();
    await post('/v1/auth/password/forgot', { email: EMAIL });
    const first = lastCode();
    const wrong = first === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) await post('/v1/auth/password/reset', { email: EMAIL, code: wrong, newPassword: 'another-good-passphrase' });
    const sent = mailer.outbox.length;
    await post('/v1/auth/password/forgot', { email: EMAIL });
    expect(mailer.outbox.length).toBe(sent); // still inside the resend window
    // 20 wrong guesses a day across fresh codes, then refused even with the right code.
    for (let round = 0; round < 3; round++) {
      advance(61_000);
      await post('/v1/auth/password/forgot', { email: EMAIL });
      for (let i = 0; i < 5; i++) await post('/v1/auth/password/reset', { email: EMAIL, code: wrong, newPassword: 'another-good-passphrase' });
    }
    advance(61_000);
    advance(3_600_000);
    await post('/v1/auth/password/forgot', { email: EMAIL });
    const r = await post('/v1/auth/password/reset', { email: EMAIL, code: lastCode(), newPassword: 'another-good-passphrase' });
    expect(r.statusCode).toBe(429);
    expect(r.json().error).toBe('too_many_attempts');
  });

  it('caps codes mailed per account per hour', async () => {
    await signUp();
    const before = mailer.outbox.length;
    for (let i = 0; i < 8; i++) {
      await post('/v1/auth/password/forgot', { email: EMAIL });
      advance(61_000);
    }
    expect(mailer.outbox.length - before).toBe(5);
  });

  it('caps "already have an account" mails per recipient', async () => {
    await signUp();
    const before = mailer.outbox.length;
    for (let i = 0; i < 6; i++) await post('/v1/auth/register', { email: EMAIL, password: PW, acceptedTerms: true });
    expect(mailer.outbox.length - before).toBe(3);
  });

  it('lets the inbox owner set the password at verification', async () => {
    await post('/v1/auth/register', { email: EMAIL, password: 'stranger-password-123', acceptedTerms: true });
    const r = await post('/v1/auth/verify-email', { email: EMAIL, code: lastCode(), password: PW });
    expect(r.statusCode).toBe(200);
    expect((await post('/v1/auth/login', { email: EMAIL, password: 'stranger-password-123' })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(200);
  });

  it('drops an unproven password when Apple links an unverified account', async () => {
    await post('/v1/auth/register', { email: EMAIL, password: 'stranger-password-123', acceptedTerms: true });
    appleIds.set('tok-victim-identity-token', { sub: 'apple-9', email: EMAIL, emailVerified: true });
    const a = await post('/v1/auth/apple', { identityToken: 'tok-victim-identity-token' });
    expect(a.json()).toMatchObject({ user: { hasPassword: false } });
    expect((await post('/v1/auth/login', { email: EMAIL, password: 'stranger-password-123' })).statusCode).toBe(401);
  });

  it('counts re-auth password guesses per account', async () => {
    const { tokens } = await signUp();
    for (let i = 0; i < 20; i++)
      expect((await post('/v1/me/reauth', { method: 'password', password: 'wrong-password-x' }, tokens.accessToken)).statusCode).toBe(401);
    expect((await post('/v1/me/reauth', { method: 'password', password: PW }, tokens.accessToken)).statusCode).toBe(429);
  });

  it('lets only one of two parallel refreshes rotate a token', async () => {
    const { tokens } = await signUp();
    const rs = await Promise.all([1, 2].map(() => post('/v1/auth/refresh', { refreshToken: tokens.refreshToken })));
    expect(rs.map((r) => r.statusCode).sort()).toEqual([200, 401]);
    // the losing request didn't revoke the winner's session
    const winner = rs.find((r) => r.statusCode === 200)!;
    expect((await post('/v1/auth/refresh', { refreshToken: winner.json().refreshToken })).statusCode).toBe(200);
  });
});
