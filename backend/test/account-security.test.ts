import { createHash, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { exportPKCS8, exportSPKI, generateKeyPair, importSPKI, jwtVerify } from 'jose';
import { afterEach, describe, expect, it } from 'vitest';
import type { AppleIdentity } from '../src/apple.ts';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { createBreachChecker } from '../src/hibp.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { purgeExpired, startPurgeJob } from '../src/purge.ts';

const PW = 'correct-horse-battery';
const EMAIL = 'climber@example.com';

interface Call {
  url: string;
  init?: RequestInit;
}

let app: FastifyInstance;
let db: DB;
let mailer: ConsoleMailer;
let clock: Date;
let calls: Call[];
let respond: (url: string, init?: RequestInit) => Response | Promise<Response>;
const appleIds = new Map<string, AppleIdentity>();

const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  calls.push({ url, init });
  return respond(url, init);
}) as typeof fetch;

const setup = (env: Record<string, string> = {}) => {
  clock = new Date('2026-10-07T10:00:00Z');
  calls = [];
  respond = () => new Response('not found', { status: 404 });
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...env }),
    db,
    mailer,
    apple: async (t) => {
      const id = appleIds.get(t);
      if (!id) throw new Error('bad token');
      return id;
    },
    now: () => clock,
    fetch: fakeFetch,
  });
};
const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));

const post = (url: string, payload: object, token?: string) =>
  app.inject({ method: 'POST', url, payload, headers: token ? { authorization: `Bearer ${token}` } : {} });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${token}` } });
const del = (payload: object, token: string) =>
  app.inject({ method: 'DELETE', url: '/v1/me', payload, headers: { authorization: `Bearer ${token}` } });
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

afterEach(() => app.close());

describe('HIBP breached-password check', () => {
  const sha1 = (s: string) => createHash('sha1').update(s).digest('hex').toUpperCase();
  const BREACHED = 'breached-but-long-enough';
  const rangeBody = (pw: string, count: number) => `${sha1(pw).slice(5)}:${count}\r\n0018A45C4D1DEF81644B54AB7F969B88D65:0\r\n`;

  it('is off by default in tests', async () => {
    setup();
    await signUp();
    expect(calls).toHaveLength(0);
  });

  it('rejects breached passwords at sign-up, reset and change; sends only a 5-char prefix', async () => {
    setup({ HIBP_CHECK: '1' });
    respond = (url) => new Response(url.endsWith(sha1(BREACHED).slice(0, 5)) ? rangeBody(BREACHED, 42) : rangeBody('other-pass', 3));

    const r = await post('/v1/auth/register', { email: EMAIL, password: BREACHED, acceptedTerms: true });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('breached_password');
    expect(calls[0]!.url).toBe(`https://api.pwnedpasswords.com/range/${sha1(BREACHED).slice(0, 5)}`);
    expect(new Headers(calls[0]!.init?.headers).get('add-padding')).toBe('true');
    expect(JSON.stringify(calls)).not.toContain(sha1(BREACHED));

    const { tokens } = await signUp();
    const change = await post('/v1/me/password', { currentPassword: PW, newPassword: BREACHED }, tokens.accessToken);
    expect(change.json().error).toBe('breached_password');

    await post('/v1/auth/password/forgot', { email: EMAIL });
    const code = lastCode();
    expect((await post('/v1/auth/password/reset', { email: EMAIL, code, newPassword: BREACHED })).json().error).toBe('breached_password');
    // code not burnt by the rejected attempt
    expect((await post('/v1/auth/password/reset', { email: EMAIL, code, newPassword: 'brand-new-secret-9' })).statusCode).toBe(204);
  });

  it('ignores padding rows and fails open on errors', async () => {
    setup();
    calls = [];
    respond = () => new Response(rangeBody(BREACHED, 0));
    expect(await createBreachChecker({ fetch: fakeFetch })(BREACHED)).toBe(false);
    respond = () => new Response(rangeBody(BREACHED, 7));
    expect(await createBreachChecker({ fetch: fakeFetch })(BREACHED)).toBe(true);
    respond = () => new Response('down', { status: 503 });
    expect(await createBreachChecker({ fetch: fakeFetch })(BREACHED)).toBe(false);
    respond = () => Promise.reject(new TypeError('fetch failed'));
    expect(await createBreachChecker({ fetch: fakeFetch })(BREACHED)).toBe(false);
    respond = (_, init) =>
      new Promise((_res, rej) => init?.signal?.addEventListener('abort', () => rej(init.signal!.reason)));
    expect(await createBreachChecker({ fetch: fakeFetch, timeoutMs: 20 })(BREACHED)).toBe(false);
  });
});

describe('Sign in with Apple token exchange & revocation', () => {
  const appleEnv = async () => {
    const { privateKey, publicKey } = await generateKeyPair('ES256', { extractable: true });
    return {
      env: { APPLE_TEAM_ID: 'TEAM123456', APPLE_KEY_ID: 'KEY1234567', APPLE_PRIVATE_KEY: (await exportPKCS8(privateKey)).replace(/\n/g, '\\n') },
      spki: await exportSPKI(publicKey),
    };
  };

  it('exchanges the authorization code, stores the token encrypted and revokes it on deletion', async () => {
    const { env, spki } = await appleEnv();
    setup(env);
    respond = (url) =>
      url.endsWith('/auth/token') ? Response.json({ access_token: 'a', refresh_token: 'apple-refresh-secret', id_token: 'x' }) : new Response('');
    appleIds.set('tok-apple-exchange', { sub: 'apple-x1', email: 'x1@privaterelay.appleid.com', emailVerified: true, audience: 'Com.app.MonkeyWorkout' });

    const res = await post('/v1/auth/apple', { identityToken: 'tok-apple-exchange', authorizationCode: 'c0de' });
    expect(res.statusCode).toBe(200);
    expect(calls[0]!.url).toBe('https://appleid.apple.com/auth/token');
    const form = new URLSearchParams(String(calls[0]!.init!.body));
    expect(form.get('grant_type')).toBe('authorization_code');
    expect(form.get('code')).toBe('c0de');
    expect(form.get('client_id')).toBe('Com.app.MonkeyWorkout');
    const { payload, protectedHeader } = await jwtVerify(form.get('client_secret')!, await importSPKI(spki, 'ES256'), {
      issuer: 'TEAM123456',
      audience: 'https://appleid.apple.com',
      subject: 'Com.app.MonkeyWorkout',
      currentDate: clock,
    });
    expect(protectedHeader).toMatchObject({ alg: 'ES256', kid: 'KEY1234567' });
    expect(payload.exp! - payload.iat!).toBeLessThanOrEqual(300);

    const stored = db.prepare('SELECT refresh_token_enc FROM apple_tokens').get() as { refresh_token_enc: string };
    expect(stored.refresh_token_enc).not.toContain('apple-refresh-secret');

    expect((await del({ confirm: 'DELETE' }, res.json().tokens.accessToken)).statusCode).toBe(204);
    const revoke = calls.at(-1)!;
    expect(revoke.url).toBe('https://appleid.apple.com/auth/revoke');
    const rf = new URLSearchParams(String(revoke.init!.body));
    expect(rf.get('token')).toBe('apple-refresh-secret');
    expect(rf.get('token_type_hint')).toBe('refresh_token');
    expect(rf.get('client_id')).toBe('Com.app.MonkeyWorkout');
    expect(db.prepare('SELECT COUNT(*) AS n FROM apple_tokens').get()).toEqual({ n: 0 });
  });

  it('never blocks sign-in or deletion when Apple fails', async () => {
    const { env } = await appleEnv();
    setup(env);
    let tokenCalls = 0;
    respond = (url) => {
      if (url.endsWith('/auth/token')) return ++tokenCalls === 1 ? new Response('bad', { status: 400 }) : Response.json({ refresh_token: 'rt' });
      return Promise.reject(new TypeError('network down'));
    };
    appleIds.set('tok-apple-fail', { sub: 'apple-x2', emailVerified: false });
    expect((await post('/v1/auth/apple', { identityToken: 'tok-apple-fail', authorizationCode: 'c1' })).statusCode).toBe(200);
    const again = await post('/v1/auth/apple', { identityToken: 'tok-apple-fail', authorizationCode: 'c2' });
    expect(again.statusCode).toBe(200);
    expect(new URLSearchParams(String(calls[1]!.init!.body)).get('client_id')).toBe('Com.app.MonkeyWorkout'); // fallback client id
    expect((await del({ confirm: 'DELETE' }, again.json().tokens.accessToken)).statusCode).toBe(204);
    expect(calls.at(-1)!.url).toBe('https://appleid.apple.com/auth/revoke');
  });

  it('skips Apple calls silently when not configured', async () => {
    setup();
    appleIds.set('tok-apple-noconf', { sub: 'apple-x3', emailVerified: false });
    const r = await post('/v1/auth/apple', { identityToken: 'tok-apple-noconf', authorizationCode: 'c3' });
    expect(r.statusCode).toBe(200);
    expect((await del({ confirm: 'DELETE' }, r.json().tokens.accessToken)).statusCode).toBe(204);
    expect(calls).toHaveLength(0);
  });
});

describe('change email', () => {
  it('sends a code to the new address, swaps on confirm and notifies the old address', async () => {
    setup();
    const { tokens } = await signUp();
    const t = tokens.accessToken;
    expect((await post('/v1/me/email', { newEmail: 'new@example.com' }, t)).json().error).toBe('invalid_credentials');
    expect((await post('/v1/me/email', { newEmail: EMAIL, password: PW }, t)).json().error).toBe('same_email');

    const r = await post('/v1/me/email', { newEmail: ' New@Example.com ', password: PW }, t);
    expect(r.statusCode).toBe(202);
    expect(mailer.outbox.at(-1)!.to).toBe('new@example.com');
    const code = lastCode();

    expect((await post('/v1/me/email/confirm', { code: code === '000000' ? '111111' : '000000' }, t)).json().error).toBe('invalid_code');
    const ok = await post('/v1/me/email/confirm', { code }, t);
    expect(ok.statusCode).toBe(200);
    expect(ok.json().user).toMatchObject({ email: 'new@example.com', emailVerified: true });
    const notice = mailer.outbox.at(-1)!;
    expect(notice.to).toBe(EMAIL);
    expect(notice.subject).toContain('email was changed');
    expect(notice.text).toContain('ne•••@example.com');

    expect((await post('/v1/me/email/confirm', { code }, t)).statusCode).toBe(400); // single use
    expect((await post('/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(401);
    expect((await post('/v1/auth/login', { email: 'new@example.com', password: PW })).statusCode).toBe(200);
  });

  it('is enumeration-safe for addresses owned by another account', async () => {
    setup();
    await signUp('taken@example.com');
    const { tokens } = await signUp();
    const n = mailer.outbox.length;
    expect((await post('/v1/me/email', { newEmail: 'taken@example.com', password: PW }, tokens.accessToken)).statusCode).toBe(202);
    expect(mailer.outbox).toHaveLength(n + 1);
    expect(mailer.outbox.at(-1)!.subject).toContain('email change attempt');
    expect((await post('/v1/me/email/confirm', { code: '123456' }, tokens.accessToken)).statusCode).toBe(400);
  });

  it('expires codes, burns after 5 wrong attempts and lets Apple-only users change without password', async () => {
    setup();
    appleIds.set('tok-apple-email', { sub: 'apple-e1', email: 'e1@privaterelay.appleid.com', emailVerified: true });
    const signIn = async () => (await post('/v1/auth/apple', { identityToken: 'tok-apple-email' })).json().tokens.accessToken as string;
    let t = await signIn();
    expect((await post('/v1/me/email', { newEmail: 'real@example.com' }, t)).statusCode).toBe(202);
    const good = lastCode();
    const bad = good === '123456' ? '654321' : '123456';
    for (let i = 0; i < 4; i++) expect((await post('/v1/me/email/confirm', { code: bad }, t)).json().error).toBe('invalid_code');
    expect((await post('/v1/me/email/confirm', { code: bad }, t)).json().error).toBe('too_many_attempts');
    expect((await post('/v1/me/email/confirm', { code: good }, t)).statusCode).toBe(400);

    await post('/v1/me/email', { newEmail: 'real@example.com' }, t);
    const fresh = lastCode();
    advance(16 * 60_000);
    t = await signIn(); // access token expired too
    expect((await post('/v1/me/email/confirm', { code: fresh }, t)).json().error).toBe('invalid_code');

    await post('/v1/me/email', { newEmail: 'real@example.com' }, t);
    const ok = await post('/v1/me/email/confirm', { code: lastCode() }, t);
    expect(ok.json().user).toMatchObject({ email: 'real@example.com', appleLinked: true });
    expect((await get('/v1/me', t)).json().user.email).toBe('real@example.com');
  });
});

describe('purge job', () => {
  it('deletes expired codes, expired and dead revoked refresh tokens, keeps live families', async () => {
    setup();
    const a = await signUp();
    await post('/v1/auth/register', { email: 'pending@example.com', password: PW, acceptedTerms: true }); // live code
    // family 1: rotated once → old token revoked, new one live (must be kept for replay detection)
    const rotated = (await post('/v1/auth/refresh', { refreshToken: a.tokens.refreshToken })).json();
    // family 2: logged out → fully revoked
    const b = (await post('/v1/auth/login', { email: EMAIL, password: PW })).json();
    await post('/v1/auth/logout', { refreshToken: b.tokens.refreshToken });

    const count = (table: string) => (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
    expect(purgeExpired(db, clock)).toEqual({ codes: 0, emailChanges: 0, refreshTokens: 0 }); // inside grace period
    advance(2 * 86_400_000);
    const r = purgeExpired(db, clock);
    expect(r.codes).toBe(2); // the verification code + the pending sign-up code, both > 15 min old
    expect(r.refreshTokens).toBe(1); // logged-out family only
    expect(count('refresh_tokens')).toBe(2);
    // replay of the rotated-away token still revokes the live family
    expect((await post('/v1/auth/refresh', { refreshToken: a.tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('/v1/auth/refresh', { refreshToken: rotated.refreshToken })).statusCode).toBe(401);

    advance(61 * 86_400_000);
    purgeExpired(db, clock);
    expect(count('refresh_tokens')).toBe(0);
    expect(count('codes')).toBe(0);
  });

  it('purges expired email changes and runs from the timer', async () => {
    setup();
    const now = clock.toISOString();
    db.prepare(
      "INSERT INTO users (id, email, created_at, updated_at) VALUES ('u1', 'p@example.com', ?, ?)",
    ).run(now, now);
    db.prepare(
      "INSERT INTO email_changes (id, user_id, new_email, code_hash, expires_at, created_at) VALUES (?, 'u1', 'q@example.com', 'x', ?, ?)",
    ).run(randomUUID(), new Date(clock.getTime() - 1000).toISOString(), now);
    const logs: string[] = [];
    const stop = startPurgeJob(db, { intervalMs: 0, now: () => clock, log: (m) => logs.push(m) });
    stop();
    expect(logs[0]).toContain('1 email changes');
  });
});
