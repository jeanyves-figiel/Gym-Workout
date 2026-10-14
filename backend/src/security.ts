import { createCipheriv, createDecipheriv, hkdfSync, randomBytes, randomUUID } from 'node:crypto';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type AuthenticatorTransportFuture,
  type RegistrationResponseJSON,
} from '@simplewebauthn/server';
import type { AppleVerifier } from './apple.ts';
import type { AuthService, PublicUser, TokenPair, UserRow } from './auth.ts';
import { publicUser } from './auth.ts';
import type { Config } from './config.ts';
import { hmac, randomToken, safeEqualHex, sha256, sixDigitCode, verifyPassword } from './crypto.ts';
import { type DB, tx } from './db.ts';
import { ApiError } from './errors.ts';
import type { Mailer } from './mailer.ts';
import { newTotpSecret, otpauthUrl, verifyTotp } from './totp.ts';

/**
 * Account security (#257):
 * - re-auth ("confirm it's you"): a 5-minute grant needed before changing password, email, 2-step, passkeys or deleting;
 * - optional 2-step sign-in (TOTP authenticator + recovery codes), asked after password login only;
 * - passkeys (WebAuthn) for sign-in and re-auth. Apple and passkey sign-ins skip 2-step.
 */

export type ReauthMethod = 'passkey' | 'apple' | 'password' | 'totp' | 'email_code';

const GRANT_TTL_MS = 5 * 60_000;
const CHALLENGE_TTL_MS = 5 * 60_000;
const CODE_TTL_MS = 15 * 60_000;
const MAX_ATTEMPTS = 5;
const RESEND_MS = 60_000;
const RECOVERY_CODES = 10;
const MAX_PASSKEYS = 20;

export const ensureSecuritySchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS reauth_grants (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      method TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS reauth_codes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code_hash TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      expires_at TEXT NOT NULL,
      consumed_at TEXT,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS totp_secrets (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      secret_enc TEXT NOT NULL,
      enabled_at TEXT,
      last_step INTEGER NOT NULL DEFAULT -1,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS recovery_codes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code_hash TEXT NOT NULL,
      used_at TEXT
    );
    CREATE INDEX IF NOT EXISTS recovery_codes_user ON recovery_codes(user_id);
    CREATE TABLE IF NOT EXISTS mfa_challenges (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      device TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      expires_at TEXT NOT NULL,
      consumed_at TEXT
    );
    CREATE TABLE IF NOT EXISTS passkeys (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      public_key TEXT NOT NULL,
      counter INTEGER NOT NULL DEFAULT 0,
      transports TEXT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_used_at TEXT
    );
    CREATE INDEX IF NOT EXISTS passkeys_user ON passkeys(user_id);
    CREATE TABLE IF NOT EXISTS webauthn_challenges (
      id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      purpose TEXT NOT NULL,
      challenge TEXT NOT NULL,
      expires_at TEXT NOT NULL
    );
  `);
};

/** WebAuthn verification, injectable so tests don't need a real authenticator. */
export interface WebAuthnVerifier {
  verifyRegistration: typeof verifyRegistrationResponse;
  verifyAuthentication: typeof verifyAuthenticationResponse;
}
const defaultVerifier: WebAuthnVerifier = {
  verifyRegistration: verifyRegistrationResponse,
  verifyAuthentication: verifyAuthenticationResponse,
};

export interface SecurityDeps {
  db: DB;
  config: Config;
  mailer: Mailer;
  apple: AppleVerifier;
  auth: AuthService;
  now: () => Date;
  webauthn?: WebAuthnVerifier;
}

interface PasskeyRow {
  id: string;
  user_id: string;
  public_key: string;
  counter: number;
  transports: string | null;
  name: string;
  created_at: string;
  last_used_at: string | null;
}

export class SecurityService {
  private readonly d: SecurityDeps;
  private readonly encKey: Buffer;
  private readonly wa: WebAuthnVerifier;
  constructor(d: SecurityDeps) {
    this.d = d;
    this.wa = d.webauthn ?? defaultVerifier;
    this.encKey = Buffer.from(hkdfSync('sha256', d.config.codePepper, 'totp-secret', 'v1', 32));
    d.auth.setSecondFactorGate((userId, device) => this.gateLogin(userId, device));
  }

  private iso(offsetMs = 0) {
    return new Date(this.d.now().getTime() + offsetMs).toISOString();
  }
  private user(id: string) {
    return this.d.auth.userById(id);
  }

  // ───────────── overview

  mfaEnabled(userId: string): boolean {
    return !!this.d.db.prepare('SELECT 1 FROM totp_secrets WHERE user_id = ? AND enabled_at IS NOT NULL').get(userId);
  }

  /** What the Security page shows. */
  overview(userId: string) {
    const u = this.user(userId)!;
    const left = this.d.db.prepare('SELECT COUNT(*) AS n FROM recovery_codes WHERE user_id = ? AND used_at IS NULL').get(userId) as { n: number };
    return {
      hasPassword: !!u.password_hash,
      appleLinked: !!u.apple_sub,
      mfaEnabled: this.mfaEnabled(userId),
      recoveryCodesLeft: left.n,
      passkeys: this.passkeys(userId),
      reauthMethods: this.reauthMethods(u),
    };
  }

  /** Strongest first: what the "Confirm it's you" sheet offers. */
  reauthMethods(u: UserRow): ReauthMethod[] {
    const m: ReauthMethod[] = [];
    if (this.passkeyRows(u.id).length) m.push('passkey');
    if (u.apple_sub) m.push('apple');
    if (u.password_hash) m.push('password');
    if (this.mfaEnabled(u.id)) m.push('totp');
    if (u.email && u.email_verified_at) m.push('email_code');
    return m;
  }

  // ───────────── re-auth

  async sendReauthCode(userId: string): Promise<void> {
    const u = this.user(userId)!;
    if (!u.email || !u.email_verified_at) throw new ApiError(400, 'no_verified_email', 'This account has no verified email.');
    const last = this.d.db
      .prepare('SELECT created_at FROM reauth_codes WHERE user_id = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1')
      .get(userId) as { created_at: string } | undefined;
    if (last && last.created_at > this.iso(-RESEND_MS)) return;
    const code = sixDigitCode();
    const now = this.iso();
    tx(this.d.db, () => {
      this.d.db.prepare('UPDATE reauth_codes SET consumed_at = ? WHERE user_id = ? AND consumed_at IS NULL').run(now, userId);
      this.d.db
        .prepare('INSERT INTO reauth_codes (id, user_id, code_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)')
        .run(randomUUID(), userId, this.codeHash(userId, code), this.iso(CODE_TTL_MS), now);
    });
    await this.d.mailer.send({
      to: u.email,
      subject: `${this.d.config.appName}: ${code} is your code`,
      text: `Use this code to confirm it's you before changing your sign-in or security settings: ${code}\nIt expires in 15 minutes.\nIf you didn't request it, someone may be using your signed-in device: sign out all devices.`,
    });
  }

  private codeHash(userId: string, code: string) {
    return hmac(this.d.config.codePepper, `${userId}:reauth:${code}`);
  }

  private consumeReauthCode(userId: string, code: string) {
    const row = this.d.db
      .prepare('SELECT id, code_hash, attempts, expires_at FROM reauth_codes WHERE user_id = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1')
      .get(userId) as { id: string; code_hash: string; attempts: number; expires_at: string } | undefined;
    const invalid = new ApiError(400, 'invalid_code', 'Invalid or expired code.');
    if (!row || row.expires_at <= this.iso()) throw invalid;
    if (!safeEqualHex(row.code_hash, this.codeHash(userId, code))) {
      const attempts = row.attempts + 1;
      const burn = attempts >= MAX_ATTEMPTS;
      this.d.db.prepare('UPDATE reauth_codes SET attempts = ?, consumed_at = ? WHERE id = ?').run(attempts, burn ? this.iso() : null, row.id);
      if (burn) throw new ApiError(400, 'too_many_attempts', 'Too many wrong codes. Request a new one.');
      throw invalid;
    }
    this.d.db.prepare('UPDATE reauth_codes SET consumed_at = ? WHERE id = ?').run(this.iso(), row.id);
  }

  passkeyReauthOptions(userId: string) {
    const rows = this.passkeyRows(userId);
    if (!rows.length) throw new ApiError(400, 'no_passkeys', 'This account has no passkeys.');
    return this.authOptions('reauth', userId, rows);
  }

  async reauth(
    userId: string,
    b:
      | { method: 'password'; password: string }
      | { method: 'apple'; identityToken: string }
      | { method: 'email_code' | 'totp'; code: string }
      | { method: 'passkey'; challengeId: string; response: AuthenticationResponseJSON },
  ): Promise<{ reauthToken: string; expiresIn: number }> {
    const u = this.user(userId)!;
    const fail = (msg: string) => new ApiError(401, 'reauth_failed', msg);
    switch (b.method) {
      case 'password':
        if (!u.password_hash || !(await verifyPassword(b.password, u.password_hash))) throw fail('Password is incorrect.');
        break;
      case 'apple': {
        let sub: string | undefined;
        try {
          sub = (await this.d.apple(b.identityToken)).sub;
        } catch {
          /* fallthrough */
        }
        if (!u.apple_sub || sub !== u.apple_sub) throw fail('Apple sign-in did not match this account.');
        break;
      }
      case 'email_code':
        this.consumeReauthCode(userId, b.code);
        break;
      case 'totp':
        if (!this.checkTotp(userId, b.code)) throw fail('Wrong 2-step code.');
        break;
      case 'passkey':
        if ((await this.verifyPasskey('reauth', b.challengeId, b.response)) !== userId) throw fail('Passkey did not match this account.');
        break;
    }
    const token = randomToken(32);
    this.d.db.prepare('DELETE FROM reauth_grants WHERE user_id = ? AND expires_at <= ?').run(userId, this.iso());
    this.d.db
      .prepare('INSERT INTO reauth_grants (token_hash, user_id, method, expires_at, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(sha256(token), userId, b.method, this.iso(GRANT_TTL_MS), this.iso());
    return { reauthToken: token, expiresIn: GRANT_TTL_MS / 1000 };
  }

  /**
   * Gate for sensitive changes. Accepts a live re-auth grant, or (older app builds) the current password.
   * Accounts without a password (Apple-only) must always re-auth: a session token alone is not enough.
   */
  async requireReauth(userId: string, token: string | undefined, legacyPassword?: string): Promise<void> {
    if (token) {
      const row = this.d.db.prepare('SELECT user_id FROM reauth_grants WHERE token_hash = ? AND expires_at > ?').get(sha256(token), this.iso()) as
        | { user_id: string }
        | undefined;
      if (row?.user_id === userId) return;
    }
    const u = this.user(userId)!;
    if (legacyPassword !== undefined && u.password_hash) {
      if (await verifyPassword(legacyPassword, u.password_hash)) return;
      throw new ApiError(401, 'invalid_credentials', 'Password is incorrect.');
    }
    throw new ApiError(403, 'reauth_required', "Confirm it's you first.", { methods: this.reauthMethods(u) });
  }

  // ───────────── 2-step (TOTP)

  private encrypt(plain: string): string {
    const iv = randomBytes(12);
    const c = createCipheriv('aes-256-gcm', this.encKey, iv);
    const ct = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return ['v1', iv.toString('base64url'), c.getAuthTag().toString('base64url'), ct.toString('base64url')].join(':');
  }
  private decrypt(stored: string): string {
    const [, iv, tag, ct] = stored.split(':');
    const d = createDecipheriv('aes-256-gcm', this.encKey, Buffer.from(iv!, 'base64url'));
    d.setAuthTag(Buffer.from(tag!, 'base64url'));
    return Buffer.concat([d.update(Buffer.from(ct!, 'base64url')), d.final()]).toString('utf8');
  }

  /** Starts (or restarts) enrolment. Nothing changes for sign-in until `enableTotp` confirms a code. */
  totpSetup(userId: string) {
    if (this.mfaEnabled(userId)) throw new ApiError(409, 'mfa_already_enabled', '2-step is already on.');
    const u = this.user(userId)!;
    const secret = newTotpSecret();
    this.d.db
      .prepare(
        `INSERT INTO totp_secrets (user_id, secret_enc, created_at) VALUES (?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET secret_enc = excluded.secret_enc, enabled_at = NULL, last_step = -1, created_at = excluded.created_at`,
      )
      .run(userId, this.encrypt(secret), this.iso());
    return { secret, otpauthUrl: otpauthUrl(secret, u.email ?? u.name ?? 'member', this.d.config.appName) };
  }

  async enableTotp(userId: string, code: string): Promise<{ recoveryCodes: string[] }> {
    const row = this.d.db.prepare('SELECT secret_enc, enabled_at FROM totp_secrets WHERE user_id = ?').get(userId) as
      | { secret_enc: string; enabled_at: string | null }
      | undefined;
    if (!row) throw new ApiError(400, 'mfa_not_started', 'Start 2-step setup first.');
    if (row.enabled_at) throw new ApiError(409, 'mfa_already_enabled', '2-step is already on.');
    const step = verifyTotp(this.decrypt(row.secret_enc), code, this.d.now());
    if (step === undefined) throw new ApiError(400, 'invalid_code', 'Wrong code. Check the time on your phone and try again.');
    const codes = tx(this.d.db, () => {
      this.d.db.prepare('UPDATE totp_secrets SET enabled_at = ?, last_step = ? WHERE user_id = ?').run(this.iso(), step, userId);
      return this.replaceRecoveryCodes(userId);
    });
    await this.notify(userId, '2-step sign-in turned on', 'Two-step sign-in was turned on for your account.');
    return { recoveryCodes: codes };
  }

  async disableTotp(userId: string): Promise<void> {
    if (!this.mfaEnabled(userId)) return;
    tx(this.d.db, () => {
      this.d.db.prepare('DELETE FROM totp_secrets WHERE user_id = ?').run(userId);
      this.d.db.prepare('DELETE FROM recovery_codes WHERE user_id = ?').run(userId);
    });
    await this.notify(userId, '2-step sign-in turned off', 'Two-step sign-in was turned off for your account.');
  }

  regenerateRecoveryCodes(userId: string): { recoveryCodes: string[] } {
    if (!this.mfaEnabled(userId)) throw new ApiError(400, 'mfa_not_enabled', '2-step is off.');
    return { recoveryCodes: tx(this.d.db, () => this.replaceRecoveryCodes(userId)) };
  }

  private recoveryHash(userId: string, code: string) {
    return hmac(this.d.config.codePepper, `${userId}:recovery:${code.toLowerCase().replace(/[^a-z0-9]/g, '')}`);
  }

  private replaceRecoveryCodes(userId: string): string[] {
    this.d.db.prepare('DELETE FROM recovery_codes WHERE user_id = ?').run(userId);
    const ins = this.d.db.prepare('INSERT INTO recovery_codes (id, user_id, code_hash) VALUES (?, ?, ?)');
    return Array.from({ length: RECOVERY_CODES }, () => {
      const raw = randomBytes(5).toString('hex');
      const code = `${raw.slice(0, 5)}-${raw.slice(5)}`;
      ins.run(randomUUID(), userId, this.recoveryHash(userId, code));
      return code;
    });
  }

  private checkTotp(userId: string, code: string): boolean {
    const row = this.d.db.prepare('SELECT secret_enc, last_step FROM totp_secrets WHERE user_id = ? AND enabled_at IS NOT NULL').get(userId) as
      | { secret_enc: string; last_step: number }
      | undefined;
    if (!row) return false;
    const step = verifyTotp(this.decrypt(row.secret_enc), code, this.d.now(), row.last_step);
    if (step === undefined) return false;
    this.d.db.prepare('UPDATE totp_secrets SET last_step = ? WHERE user_id = ?').run(step, userId);
    return true;
  }

  private useRecoveryCode(userId: string, code: string): boolean {
    const r = this.d.db
      .prepare('UPDATE recovery_codes SET used_at = ? WHERE user_id = ? AND code_hash = ? AND used_at IS NULL')
      .run(this.iso(), userId, this.recoveryHash(userId, code));
    return Number(r.changes) > 0;
  }

  /** Called by password login after the password checks out: no tokens until the second step. */
  private gateLogin(userId: string, device?: string): void {
    if (!this.mfaEnabled(userId)) return;
    const token = randomToken(32);
    this.d.db
      .prepare('INSERT INTO mfa_challenges (token_hash, user_id, device, expires_at) VALUES (?, ?, ?, ?)')
      .run(sha256(token), userId, device?.slice(0, 120) ?? null, this.iso(CHALLENGE_TTL_MS));
    throw new ApiError(403, 'mfa_required', 'Enter the 6-digit code from your authenticator app.', { mfaToken: token, methods: ['totp', 'recovery'] });
  }

  async completeMfa(mfaToken: string, b: { code?: string; recoveryCode?: string }): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const row = this.d.db.prepare('SELECT * FROM mfa_challenges WHERE token_hash = ?').get(sha256(mfaToken)) as
      | { token_hash: string; user_id: string; device: string | null; attempts: number; expires_at: string; consumed_at: string | null }
      | undefined;
    if (!row || row.consumed_at || row.expires_at <= this.iso())
      throw new ApiError(401, 'mfa_expired', 'Sign-in timed out. Enter your email and password again.');
    const ok = b.code ? this.checkTotp(row.user_id, b.code) : b.recoveryCode ? this.useRecoveryCode(row.user_id, b.recoveryCode) : false;
    if (!ok) {
      const attempts = row.attempts + 1;
      this.d.db
        .prepare('UPDATE mfa_challenges SET attempts = ?, consumed_at = ? WHERE token_hash = ?')
        .run(attempts, attempts >= MAX_ATTEMPTS ? this.iso() : null, row.token_hash);
      if (attempts >= MAX_ATTEMPTS) throw new ApiError(401, 'mfa_expired', 'Too many wrong codes. Sign in again.');
      throw new ApiError(401, 'invalid_code', 'Wrong code.');
    }
    this.d.db.prepare('UPDATE mfa_challenges SET consumed_at = ? WHERE token_hash = ?').run(this.iso(), row.token_hash);
    if (b.recoveryCode) {
      const left = (this.d.db.prepare('SELECT COUNT(*) AS n FROM recovery_codes WHERE user_id = ? AND used_at IS NULL').get(row.user_id) as { n: number }).n;
      await this.notify(row.user_id, 'recovery code used', `A recovery code was used to sign in. ${left} left.`);
    }
    return { user: publicUser(this.user(row.user_id)!), tokens: await this.d.auth.issueTokens(row.user_id, row.device ?? undefined) };
  }

  // ───────────── passkeys

  private passkeyRows(userId: string): PasskeyRow[] {
    return this.d.db.prepare('SELECT * FROM passkeys WHERE user_id = ? ORDER BY created_at').all(userId) as unknown as PasskeyRow[];
  }

  passkeys(userId: string) {
    return this.passkeyRows(userId).map((p) => ({ id: p.id, name: p.name, createdAt: p.created_at, lastUsedAt: p.last_used_at }));
  }

  private saveChallenge(purpose: string, userId: string | null, challenge: string): string {
    const id = randomUUID();
    this.d.db.prepare('DELETE FROM webauthn_challenges WHERE expires_at <= ?').run(this.iso());
    this.d.db
      .prepare('INSERT INTO webauthn_challenges (id, user_id, purpose, challenge, expires_at) VALUES (?, ?, ?, ?, ?)')
      .run(id, userId, purpose, challenge, this.iso(CHALLENGE_TTL_MS));
    return id;
  }

  private takeChallenge(id: string, purpose: string): { user_id: string | null; challenge: string } {
    const row = this.d.db.prepare('SELECT * FROM webauthn_challenges WHERE id = ? AND purpose = ?').get(id, purpose) as
      | { user_id: string | null; challenge: string; expires_at: string }
      | undefined;
    this.d.db.prepare('DELETE FROM webauthn_challenges WHERE id = ?').run(id);
    if (!row || row.expires_at <= this.iso()) throw new ApiError(400, 'challenge_expired', 'Passkey request timed out. Try again.');
    return row;
  }

  async registrationOptions(userId: string) {
    const u = this.user(userId)!;
    const rows = this.passkeyRows(userId);
    if (rows.length >= MAX_PASSKEYS) throw new ApiError(400, 'too_many_passkeys', `You can have up to ${MAX_PASSKEYS} passkeys.`);
    const options = await generateRegistrationOptions({
      rpName: this.d.config.appName,
      rpID: this.d.config.webauthn.rpId,
      userName: u.email ?? u.name ?? 'member',
      userDisplayName: u.name ?? u.email ?? 'MonkeyWorkout member',
      userID: new TextEncoder().encode(userId),
      attestationType: 'none',
      excludeCredentials: rows.map((r) => ({ id: r.id, transports: this.transports(r) })),
      authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
    });
    return { challengeId: this.saveChallenge('register', userId, options.challenge), options };
  }

  async addPasskey(userId: string, challengeId: string, response: RegistrationResponseJSON, name?: string) {
    const ch = this.takeChallenge(challengeId, 'register');
    if (ch.user_id !== userId) throw new ApiError(400, 'challenge_expired', 'Passkey request timed out. Try again.');
    let info;
    try {
      const v = await this.wa.verifyRegistration({
        response,
        expectedChallenge: ch.challenge,
        expectedOrigin: this.d.config.webauthn.origins,
        expectedRPID: this.d.config.webauthn.rpId,
        requireUserVerification: true,
      });
      if (!v.verified) throw new Error('not verified');
      info = v.registrationInfo!;
    } catch {
      throw new ApiError(400, 'passkey_invalid', 'The passkey could not be verified.');
    }
    const cred = info.credential;
    if (this.d.db.prepare('SELECT 1 FROM passkeys WHERE id = ?').get(cred.id)) throw new ApiError(409, 'passkey_exists', 'This passkey is already added.');
    const label = name?.trim() || `Passkey ${this.passkeyRows(userId).length + 1}`;
    this.d.db
      .prepare('INSERT INTO passkeys (id, user_id, public_key, counter, transports, name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(cred.id, userId, Buffer.from(cred.publicKey).toString('base64url'), cred.counter, JSON.stringify(cred.transports ?? []), label.slice(0, 60), this.iso());
    await this.notify(userId, 'passkey added', `A passkey "${label}" was added to your account.`);
    return this.passkeys(userId);
  }

  renamePasskey(userId: string, id: string, name: string) {
    const r = this.d.db.prepare('UPDATE passkeys SET name = ? WHERE id = ? AND user_id = ?').run(name.trim().slice(0, 60), id, userId);
    if (!Number(r.changes)) throw new ApiError(404, 'not_found', 'Passkey not found.');
    return this.passkeys(userId);
  }

  async deletePasskey(userId: string, id: string) {
    const row = this.d.db.prepare('SELECT name FROM passkeys WHERE id = ? AND user_id = ?').get(id, userId) as { name: string } | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Passkey not found.');
    this.d.db.prepare('DELETE FROM passkeys WHERE id = ?').run(id);
    await this.notify(userId, 'passkey removed', `The passkey "${row.name}" was removed from your account.`);
    return this.passkeys(userId);
  }

  private transports(r: PasskeyRow): AuthenticatorTransportFuture[] | undefined {
    try {
      return r.transports ? (JSON.parse(r.transports) as AuthenticatorTransportFuture[]) : undefined;
    } catch {
      return undefined;
    }
  }

  private async authOptions(purpose: 'login' | 'reauth', userId: string | null, rows: PasskeyRow[]) {
    const options = await generateAuthenticationOptions({
      rpID: this.d.config.webauthn.rpId,
      userVerification: 'required',
      allowCredentials: rows.map((r) => ({ id: r.id, transports: this.transports(r) })),
    });
    return { challengeId: this.saveChallenge(purpose, userId, options.challenge), options };
  }

  /** Sign-in options: discoverable credentials, so no email needed. */
  loginOptions() {
    return this.authOptions('login', null, []);
  }

  /** Verifies an assertion; returns the owner's user id. */
  private async verifyPasskey(purpose: 'login' | 'reauth', challengeId: string, response: AuthenticationResponseJSON): Promise<string> {
    const ch = this.takeChallenge(challengeId, purpose);
    const bad = new ApiError(401, 'passkey_invalid', 'The passkey could not be verified.');
    const row = this.d.db.prepare('SELECT * FROM passkeys WHERE id = ?').get(response.id) as PasskeyRow | undefined;
    if (!row || (ch.user_id && ch.user_id !== row.user_id)) throw bad;
    let newCounter: number;
    try {
      const v = await this.wa.verifyAuthentication({
        response,
        expectedChallenge: ch.challenge,
        expectedOrigin: this.d.config.webauthn.origins,
        expectedRPID: this.d.config.webauthn.rpId,
        credential: { id: row.id, publicKey: Buffer.from(row.public_key, 'base64url'), counter: row.counter, transports: this.transports(row) },
        requireUserVerification: true,
      });
      if (!v.verified) throw new Error('not verified');
      newCounter = v.authenticationInfo.newCounter;
    } catch {
      throw bad;
    }
    this.d.db.prepare('UPDATE passkeys SET counter = ?, last_used_at = ? WHERE id = ?').run(newCounter, this.iso(), row.id);
    return row.user_id;
  }

  /** Passkey sign-in: possession + Face ID, so 2-step is skipped. */
  async loginWithPasskey(challengeId: string, response: AuthenticationResponseJSON, device?: string): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const userId = await this.verifyPasskey('login', challengeId, response);
    return { user: publicUser(this.user(userId)!), tokens: await this.d.auth.issueTokens(userId, device) };
  }

  /** `/.well-known/apple-app-site-association`: lets the iOS app use passkeys for this host. */
  appSiteAssociation() {
    const team = this.d.config.appleTeamId;
    if (!team) return undefined;
    return { webcredentials: { apps: this.d.config.appleBundleIds.map((b) => `${team}.${b}`) } };
  }

  private async notify(userId: string, what: string, text: string) {
    const u = this.user(userId);
    if (!u?.email || !u.email_verified_at) return;
    await this.d.mailer.send({
      to: u.email,
      subject: `${this.d.config.appName}: ${what}`,
      text: `${text}\nIf this wasn't you, reset your password and sign out all devices.`,
    });
  }
}
