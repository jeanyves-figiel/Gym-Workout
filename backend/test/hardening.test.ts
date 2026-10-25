import { randomUUID, scryptSync } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { ensureSchemaExtras } from '../src/schemaExtras.ts';

/** Backend hardening (#712): sessions end everywhere at once, re-auth grants are spent, stored ids migrate. */
const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-07T10:00:00Z');
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

const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
const req = (method: 'GET' | 'POST' | 'DELETE', url: string, token?: string, payload?: object, grant?: string) =>
  app.inject({
    method,
    url,
    payload,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(grant ? { 'x-reauth-token': grant } : {}) },
  });
const lastCode = () => [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;

const signUp = async (email = 'lifter@example.com') => {
  expect((await req('POST', '/v1/auth/register', undefined, { email, password: PW, acceptedTerms: true })).statusCode).toBe(202);
  const res = await req('POST', '/v1/auth/verify-email', undefined, { email, code: lastCode() });
  expect(res.statusCode).toBe(200);
  return res.json().tokens as { accessToken: string; refreshToken: string };
};
const grant = async (t: string) => (await req('POST', '/v1/me/reauth', t, { method: 'password', password: PW })).json().reauthToken as string;

describe('access tokens end with the sessions (#712)', () => {
  it('sign out everywhere refuses access tokens issued before it, even within the same second', async () => {
    const a = await signUp();
    advance(300);
    const login = (await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: PW })).json().tokens;
    advance(300);
    expect((await req('POST', '/v1/me/logout-all', login.accessToken)).statusCode).toBe(204);
    for (const t of [a.accessToken, login.accessToken]) expect((await req('GET', '/v1/me', t)).json().error).toBe('invalid_token');
    advance(100);
    const again = (await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: PW })).json().tokens;
    expect((await req('GET', '/v1/me', again.accessToken)).statusCode).toBe(200);
  });

  it('a password change keeps only the tokens it returns; a reset ends every one', async () => {
    const a = await signUp();
    advance(500);
    const r = await req('POST', '/v1/me/password', a.accessToken, { newPassword: 'another-good-secret-7' }, await grant(a.accessToken));
    expect(r.statusCode).toBe(200);
    expect((await req('GET', '/v1/me', a.accessToken)).statusCode).toBe(401);
    const fresh = r.json().tokens.accessToken as string;
    expect((await req('GET', '/v1/me', fresh)).statusCode).toBe(200);

    advance(1000);
    await req('POST', '/v1/auth/password/forgot', undefined, { email: 'lifter@example.com' });
    advance(1000);
    expect((await req('POST', '/v1/auth/password/reset', undefined, { email: 'lifter@example.com', code: lastCode(), newPassword: 'third-good-secret-88' })).statusCode).toBe(204);
    expect((await req('GET', '/v1/me', fresh)).statusCode).toBe(401);
  });
});

describe('re-auth grants (#712)', () => {
  it('a grant is spent by a password change, an email change or a delete', async () => {
    const a = await signUp();
    const g = await grant(a.accessToken);
    expect((await req('POST', '/v1/me/email', a.accessToken, { newEmail: 'new@example.com' }, g)).statusCode).toBe(202);
    expect((await req('POST', '/v1/me/email', a.accessToken, { newEmail: 'other@example.com' }, g)).json().error).toBe('reauth_required');
    expect((await req('DELETE', '/v1/me', a.accessToken, { confirm: 'DELETE' }, g)).json().error).toBe('reauth_required');
    // Other sensitive steps (2-step, passkeys) still share one grant for their two calls.
    const g2 = await grant(a.accessToken);
    expect((await req('POST', '/v1/me/mfa/totp/setup', a.accessToken, {}, g2)).statusCode).toBe(200);
    expect((await req('POST', '/v1/me/mfa/totp/setup', a.accessToken, {}, g2)).statusCode).toBe(200);
  });

  it('a refused change gives the grant back; logout-all drops open grants', async () => {
    const a = await signUp();
    const g = await grant(a.accessToken);
    expect((await req('POST', '/v1/me/password', a.accessToken, { newPassword: 'short' }, g)).json().error).toBe('weak_password');
    const ok = await req('POST', '/v1/me/password', a.accessToken, { newPassword: 'another-good-secret-7' }, g);
    expect(ok.statusCode).toBe(200);
    const t = ok.json().tokens.accessToken as string;
    expect((await req('POST', '/v1/me/password', t, { newPassword: 'third-good-secret-88' }, g)).json().error).toBe('reauth_required');

    advance(1000);
    const login = (await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: 'another-good-secret-7' })).json().tokens;
    const open = (await req('POST', '/v1/me/reauth', login.accessToken, { method: 'password', password: 'another-good-secret-7' })).json().reauthToken;
    expect((await req('POST', '/v1/me/logout-all', login.accessToken)).statusCode).toBe(204);
    expect(db.prepare('SELECT COUNT(*) AS n FROM reauth_grants').get()).toEqual({ n: 0 });
    expect(open).toBeTruthy();
  });
});

describe('deleting an account forgets its throttles (#713)', () => {
  it('drops the hit keys that hold the user id or the email, and only those', async () => {
    const a = await signUp('lifter_1@example.com');
    const me = (await req('GET', '/v1/me', a.accessToken)).json().user.id as string;
    const hit = db.prepare('INSERT INTO throttle_hits (key, at, expires_at) VALUES (?, ?, ?)');
    for (const key of [`coach:${me}`, 'login:lifter_1@example.com', 'login:lifterX1@example.com', 'login:someone@example.com'])
      hit.run(key, clock.toISOString(), '2099-01-01T00:00:00.000Z');
    const g = await grant(a.accessToken);
    expect((await req('DELETE', '/v1/me', a.accessToken, { confirm: 'DELETE' }, g)).statusCode).toBe(204);
    const left = (db.prepare('SELECT key FROM throttle_hits').all() as { key: string }[]).map((r) => r.key);
    expect(left.some((k) => k.includes(me) || k.includes('lifter_1@example.com'))).toBe(false);
    // `_` is escaped: a look-alike address keeps its hits.
    expect(left).toEqual(expect.arrayContaining(['login:lifterX1@example.com', 'login:someone@example.com']));
  });
});

describe('stored sync ids are lower-cased once (#714)', () => {
  it('renames upper-case ids, keeps the newer of two spellings and moves library saves along', () => {
    const now = '2026-10-07T10:00:00.000Z';
    db.prepare("INSERT INTO users (id, email, created_at, updated_at) VALUES ('u1', 'a@example.com', ?, ?)").run(now, now);
    db.prepare("INSERT INTO users (id, email, created_at, updated_at) VALUES ('u2', 'b@example.com', ?, ?)").run(now, now);
    const up = randomUUID().toUpperCase();
    const twin = randomUUID().toUpperCase();
    const ins = db.prepare('INSERT INTO climbs (id, user_id, start, data, updated_at) VALUES (?, ?, ?, ?, ?)');
    ins.run(up, 'u1', now, '{"v":"up"}', now);
    ins.run(twin, 'u1', now, '{"v":"old"}', '2026-10-01T00:00:00.000Z');
    ins.run(twin.toLowerCase(), 'u1', now, '{"v":"new"}', now);
    const w = randomUUID().toUpperCase();
    db.prepare("INSERT INTO custom_workouts (id, user_id, data, updated_at, visibility) VALUES (?, 'u1', '{}', ?, 'members')").run(w, now);
    db.prepare("INSERT INTO library_saves (user_id, workout_id, created_at) VALUES ('u2', ?, ?)").run(w, now);
    db.prepare("DELETE FROM schema_fixes WHERE name = 'lowercase-sync-ids'").run();
    ensureSchemaExtras(db);
    ensureSchemaExtras(db);
    expect(db.prepare('SELECT id, data FROM climbs ORDER BY data').all()).toEqual([
      { id: twin.toLowerCase(), data: '{"v":"new"}' },
      { id: up.toLowerCase(), data: '{"v":"up"}' },
    ]);
    expect(db.prepare('SELECT workout_id FROM library_saves').all()).toEqual([{ workout_id: w.toLowerCase() }]);
  });
});

describe('password hashes upgrade at sign-in (#762)', () => {
  it('replaces a scrypt hash with Argon2id after a correct password, keeps it on a wrong one', async () => {
    await signUp();
    const salt = Buffer.alloc(16, 3);
    const key = scryptSync(PW, salt, 64, { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
    const old = `scrypt$32768$8$1$${salt.toString('base64')}$${key.toString('base64')}`;
    db.prepare('UPDATE users SET password_hash = ? WHERE email = ?').run(old, 'lifter@example.com');
    const hash = () => (db.prepare('SELECT password_hash FROM users WHERE email = ?').get('lifter@example.com') as { password_hash: string }).password_hash;
    expect((await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: 'wrong-password-123' })).statusCode).toBe(401);
    expect(hash()).toBe(old);
    expect((await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: PW })).statusCode).toBe(200);
    expect(hash()).toMatch(/^\$argon2id\$v=19\$m=32768,t=3,p=1\$/);
    expect((await req('POST', '/v1/auth/login', undefined, { email: 'lifter@example.com', password: PW })).statusCode).toBe(200);
  });
});
