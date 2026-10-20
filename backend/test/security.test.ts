import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import type { AppleIdentity } from '../src/apple.ts';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import type { WebAuthnVerifier } from '../src/security.ts';
import { base32Decode, base32Encode, stepAt, totpAt } from '../src/totp.ts';

const PW = 'correct-horse-battery';
const EMAIL = 'climber@example.com';

let app: FastifyInstance;
let db: DB;
let mailer: ConsoleMailer;
let clock: Date;
const appleIds = new Map<string, AppleIdentity>();
/** Fake authenticator: a response "verifies" when it echoes the expected challenge. */
const webauthn = {
  verifyRegistration: async (o: { response: { id: string; challenge?: string }; expectedChallenge: string }) =>
    o.response.challenge === o.expectedChallenge
      ? { verified: true, registrationInfo: { credential: { id: o.response.id, publicKey: new Uint8Array([1, 2, 3]), counter: 0, transports: ['internal'] } } }
      : { verified: false },
  verifyAuthentication: async (o: { response: { challenge?: string }; expectedChallenge: string; credential: { counter: number } }) => ({
    verified: o.response.challenge === o.expectedChallenge,
    authenticationInfo: { newCounter: o.credential.counter + 1 },
  }),
} as unknown as WebAuthnVerifier;

const setup = (env: Record<string, string> = {}) => {
  clock = new Date('2026-10-13T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', APPLE_TEAM_ID: 'TEAM123456', WEBAUTHN_RP_ID: 'workout.example.com', ...env }),
    db,
    mailer,
    apple: async (t) => {
      const id = appleIds.get(t);
      if (!id) throw new Error('bad token');
      return id;
    },
    now: () => clock,
    webauthn,
  });
};
const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
afterEach(() => app?.close());

const req = (method: 'GET' | 'POST' | 'DELETE' | 'PATCH', url: string, payload?: object, token?: string, grant?: string) =>
  app.inject({
    method,
    url,
    payload,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(grant ? { 'x-reauth-token': grant } : {}) },
  });
const lastCode = () => {
  const m = [...mailer.outbox].reverse().find((x) => /\d{6} is your code/.test(x.subject));
  return m!.subject.match(/(\d{6})/)![1]!;
};
const signUp = async () => {
  await req('POST', '/v1/auth/register', { email: EMAIL, password: PW, acceptedTerms: true });
  return (await req('POST', '/v1/auth/verify-email', { email: EMAIL, code: lastCode() })).json().tokens.accessToken as string;
};
const passwordGrant = async (t: string) => (await req('POST', '/v1/me/reauth', { method: 'password', password: PW }, t)).json().reauthToken as string;

describe('totp', () => {
  it('matches RFC 6238 SHA-1 test vectors', () => {
    const secret = base32Encode(Buffer.from('12345678901234567890'));
    expect(base32Decode(secret).toString()).toBe('12345678901234567890');
    expect(totpAt(secret, Math.floor(59 / 30))).toBe('287082');
    expect(totpAt(secret, Math.floor(1111111109 / 30))).toBe('081804');
    expect(totpAt(secret, Math.floor(2000000000 / 30))).toBe('279037');
  });
});

describe('re-auth before sensitive changes (#257)', () => {
  it('Apple-only member cannot set a password with a bare session; Apple, email code work; grant expires after 5 min', async () => {
    setup();
    appleIds.set('tok-apple-aaaa', { sub: 'apple-1', email: 'a@privaterelay.appleid.com', emailVerified: true });
    appleIds.set('tok-apple-other', { sub: 'apple-2', emailVerified: false });
    const t = (await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-aaaa' })).json().tokens.accessToken;

    const bare = await req('POST', '/v1/me/password', { newPassword: 'brand-new-secret-9' }, t);
    expect(bare.statusCode).toBe(403);
    expect(bare.json()).toMatchObject({ error: 'reauth_required', methods: ['apple', 'email_code'] });

    expect((await req('POST', '/v1/me/reauth', { method: 'apple', identityToken: 'tok-apple-other' }, t)).json().error).toBe('reauth_failed');
    expect((await req('POST', '/v1/me/reauth', { method: 'password', password: PW }, t)).json().error).toBe('reauth_failed');

    const g = await req('POST', '/v1/me/reauth', { method: 'apple', identityToken: 'tok-apple-aaaa' }, t);
    expect(g.json()).toMatchObject({ expiresIn: 300 });
    advance(5 * 60_000 + 1);
    expect((await req('POST', '/v1/me/password', { newPassword: 'brand-new-secret-9' }, t, g.json().reauthToken)).statusCode).toBe(403);

    expect((await req('POST', '/v1/me/reauth/email-code', {}, t)).statusCode).toBe(202);
    expect(mailer.outbox.at(-1)!.to).toBe('a@privaterelay.appleid.com');
    const code = lastCode();
    expect((await req('POST', '/v1/me/reauth', { method: 'email_code', code: code === '000000' ? '111111' : '000000' }, t)).json().error).toBe('invalid_code');
    const grant = (await req('POST', '/v1/me/reauth', { method: 'email_code', code }, t)).json().reauthToken;
    expect((await req('POST', '/v1/me/reauth', { method: 'email_code', code }, t)).statusCode).toBe(400); // single use
    const ok = await req('POST', '/v1/me/password', { newPassword: 'brand-new-secret-9' }, t, grant);
    expect(ok.statusCode).toBe(200);
    expect((await req('POST', '/v1/auth/login', { email: 'a@privaterelay.appleid.com', password: 'brand-new-secret-9' })).statusCode).toBe(200);
  });

  it("a grant is bound to its member", async () => {
    setup();
    const t = await signUp();
    appleIds.set('tok-apple-bbbb', { sub: 'apple-b', emailVerified: false });
    const other = (await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-bbbb' })).json().tokens.accessToken;
    const grant = await passwordGrant(t);
    expect((await req('POST', '/v1/me/mfa/totp/setup', {}, other, grant)).statusCode).toBe(403);
  });
});

describe('2-step sign-in (TOTP)', () => {
  const codeFor = (secret: string, at = clock) => totpAt(secret, stepAt(at));

  it('enrols, then password login needs the code; Apple sign-in skips it; recovery code works once', async () => {
    setup();
    const t = await signUp();
    expect((await req('POST', '/v1/me/mfa/totp/setup', {}, t)).json().error).toBe('reauth_required');
    const grant = await passwordGrant(t);
    const setupRes = (await req('POST', '/v1/me/mfa/totp/setup', {}, t, grant)).json();
    expect(setupRes.otpauthUrl).toContain('otpauth://totp/MonkeyWorkout:climber%40example.com?secret=');
    const secret = setupRes.secret as string;

    expect((await req('POST', '/v1/me/mfa/totp/enable', { code: codeFor(secret) === '000000' ? '111111' : '000000' }, t, grant)).statusCode).toBe(400);
    const en = (await req('POST', '/v1/me/mfa/totp/enable', { code: codeFor(secret) }, t, grant)).json();
    expect(en.recoveryCodes).toHaveLength(10);
    expect(mailer.outbox.at(-1)!.subject).toContain('2-step sign-in turned on');
    expect((await req('GET', '/v1/me/security', undefined, t)).json()).toMatchObject({ mfaEnabled: true, recoveryCodesLeft: 10, reauthMethods: ['password', 'totp', 'email_code'] });

    const login = await req('POST', '/v1/auth/login', { email: EMAIL, password: PW });
    expect(login.statusCode).toBe(403);
    expect(login.json()).toMatchObject({ error: 'mfa_required', methods: ['totp', 'recovery'] });
    expect(login.json().tokens).toBeUndefined();
    const mfaToken = login.json().mfaToken;

    // same 30 s step as enrolment → replay refused
    expect((await req('POST', '/v1/auth/mfa', { mfaToken, code: codeFor(secret) })).json().error).toBe('invalid_code');
    advance(30_000);
    const done = await req('POST', '/v1/auth/mfa', { mfaToken, code: codeFor(secret) });
    expect(done.statusCode).toBe(200);
    expect(done.json().tokens.accessToken).toBeTruthy();
    expect((await req('POST', '/v1/auth/mfa', { mfaToken, code: codeFor(secret) })).json().error).toBe('mfa_expired');

    const l2 = (await req('POST', '/v1/auth/login', { email: EMAIL, password: PW })).json().mfaToken;
    const rc = en.recoveryCodes[0].toUpperCase();
    expect((await req('POST', '/v1/auth/mfa', { mfaToken: l2, recoveryCode: rc })).statusCode).toBe(200);
    expect(mailer.outbox.at(-1)!.text).toContain('9 left');
    const l3 = (await req('POST', '/v1/auth/login', { email: EMAIL, password: PW })).json().mfaToken;
    expect((await req('POST', '/v1/auth/mfa', { mfaToken: l3, recoveryCode: rc })).statusCode).toBe(401);

    // Apple sign-in on the same account: no second step
    appleIds.set('tok-apple-cccc', { sub: 'apple-c', email: EMAIL, emailVerified: true });
    expect((await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-cccc' })).json().tokens).toBeTruthy();

    // turning it off needs re-auth (TOTP itself is a method)
    advance(30_000);
    expect((await req('DELETE', '/v1/me/mfa', undefined, t)).statusCode).toBe(403);
    const g2 = (await req('POST', '/v1/me/reauth', { method: 'totp', code: codeFor(secret) }, t)).json().reauthToken;
    expect((await req('DELETE', '/v1/me/mfa', undefined, t, g2)).statusCode).toBe(204);
    expect((await req('POST', '/v1/auth/login', { email: EMAIL, password: PW })).statusCode).toBe(200);
  });

  it('with APPLE_TWO_STEP=on, Apple sign-in asks for the code only when 2-step is on', async () => {
    setup({ APPLE_TWO_STEP: 'on' });
    appleIds.set('tok-apple-dddd', { sub: 'apple-d', email: 'apple-only@privaterelay.appleid.com', emailVerified: true });
    expect((await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-dddd' })).statusCode).toBe(200);
    const t = await signUp();
    const grant = await passwordGrant(t);
    const secret = (await req('POST', '/v1/me/mfa/totp/setup', {}, t, grant)).json().secret as string;
    expect((await req('POST', '/v1/me/mfa/totp/enable', { code: codeFor(secret) }, t, grant)).statusCode).toBe(200);
    appleIds.set('tok-apple-eeee', { sub: 'apple-e', email: EMAIL, emailVerified: true });
    const r = await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-eeee' });
    expect(r.statusCode).toBe(403);
    expect(r.json()).toMatchObject({ error: 'mfa_required', methods: ['totp', 'recovery'] });
    expect(r.json().tokens).toBeUndefined();
    advance(30_000);
    expect((await req('POST', '/v1/auth/mfa', { mfaToken: r.json().mfaToken, code: codeFor(secret) })).statusCode).toBe(200);
    // the Apple-only account (no 2-step) still signs straight in
    expect((await req('POST', '/v1/auth/apple', { identityToken: 'tok-apple-dddd' })).statusCode).toBe(200);
  });

  it('burns the challenge after 5 wrong codes', async () => {
    setup();
    const t = await signUp();
    const grant = await passwordGrant(t);
    const { secret } = (await req('POST', '/v1/me/mfa/totp/setup', {}, t, grant)).json();
    await req('POST', '/v1/me/mfa/totp/enable', { code: codeFor(secret) }, t, grant);
    const mfaToken = (await req('POST', '/v1/auth/login', { email: EMAIL, password: PW })).json().mfaToken;
    const bad = codeFor(secret) === '123456' ? '654321' : '123456';
    for (let i = 0; i < 4; i++) expect((await req('POST', '/v1/auth/mfa', { mfaToken, code: bad })).json().error).toBe('invalid_code');
    expect((await req('POST', '/v1/auth/mfa', { mfaToken, code: bad })).json().error).toBe('mfa_expired');
  });
});

describe('passkeys', () => {
  it('adds a passkey after re-auth, signs in with it (no 2-step), re-auths with it, removes it', async () => {
    setup();
    const t = await signUp();
    expect((await req('POST', '/v1/me/passkeys/options', {}, t)).statusCode).toBe(403);
    const grant = await passwordGrant(t);
    const reg = (await req('POST', '/v1/me/passkeys/options', {}, t, grant)).json();
    expect(reg.options.rp).toMatchObject({ id: 'workout.example.com', name: 'MonkeyWorkout' });
    expect(reg.options.authenticatorSelection).toMatchObject({ residentKey: 'required', userVerification: 'required' });

    const bad = await req('POST', '/v1/me/passkeys', { challengeId: reg.challengeId, response: { id: 'cred-1', challenge: 'nope' } }, t, grant);
    expect(bad.json().error).toBe('passkey_invalid');
    const reg2 = (await req('POST', '/v1/me/passkeys/options', {}, t, grant)).json();
    const added = await req('POST', '/v1/me/passkeys', { challengeId: reg2.challengeId, response: { id: 'cred-1', challenge: reg2.options.challenge }, name: 'iPhone' }, t, grant);
    expect(added.json().passkeys).toMatchObject([{ id: 'cred-1', name: 'iPhone' }]);
    expect(mailer.outbox.at(-1)!.subject).toContain('passkey added');

    const login = (await req('POST', '/v1/auth/passkey/options', {})).json();
    expect(login.options.rpId).toBe('workout.example.com');
    const signedIn = await req('POST', '/v1/auth/passkey', { challengeId: login.challengeId, response: { id: 'cred-1', challenge: login.options.challenge } });
    expect(signedIn.statusCode).toBe(200);
    expect(signedIn.json().user.email).toBe(EMAIL);
    // challenge is single use
    expect((await req('POST', '/v1/auth/passkey', { challengeId: login.challengeId, response: { id: 'cred-1', challenge: login.options.challenge } })).statusCode).toBe(400);

    const ro = (await req('POST', '/v1/me/reauth/passkey-options', {}, t)).json();
    expect(ro.options.allowCredentials).toMatchObject([{ id: 'cred-1' }]);
    const g = (await req('POST', '/v1/me/reauth', { method: 'passkey', challengeId: ro.challengeId, response: { id: 'cred-1', challenge: ro.options.challenge } }, t)).json();
    expect(g.reauthToken).toBeTruthy();
    expect((await req('GET', '/v1/me/security', undefined, t)).json().reauthMethods[0]).toBe('passkey');

    expect((await req('PATCH', '/v1/me/passkeys/cred-1', { name: 'Work phone' }, t)).json().passkeys[0].name).toBe('Work phone');
    expect((await req('DELETE', '/v1/me/passkeys/cred-1', undefined, t, g.reauthToken)).json().passkeys).toEqual([]);
  });

  it('serves the Apple app-site association for webcredentials', async () => {
    setup();
    const r = await app.inject({ method: 'GET', url: '/.well-known/apple-app-site-association' });
    expect(r.headers['content-type']).toContain('application/json');
    expect(r.json()).toEqual({ webcredentials: { apps: ['TEAM123456.Com.app.MonkeyWorkout', 'TEAM123456.Com.app.MonkeyWorkout.dev'] } });
  });
});
