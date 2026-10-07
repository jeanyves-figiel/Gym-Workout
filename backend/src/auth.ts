import { randomUUID } from 'node:crypto';
import { jwtVerify, SignJWT } from 'jose';
import type { AppleVerifier } from './apple.ts';
import type { Config } from './config.ts';
import { burnPasswordCheck, hashPassword, hmac, randomToken, safeEqualHex, sha256, sixDigitCode, verifyPassword } from './crypto.ts';
import { type DB, tx } from './db.ts';
import { ApiError } from './errors.ts';
import type { Mailer } from './mailer.ts';

export interface UserRow {
  id: string;
  email: string | null;
  password_hash: string | null;
  email_verified_at: string | null;
  name: string | null;
  apple_sub: string | null;
  terms_accepted_at: string | null;
  failed_logins: number;
  locked_until: string | null;
  created_at: string;
  updated_at: string;
}

export interface TokenPair {
  tokenType: 'Bearer';
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  refreshTokenExpiresAt: string;
}

export interface PublicUser {
  id: string;
  email: string | null;
  name: string | null;
  emailVerified: boolean;
  hasPassword: boolean;
  appleLinked: boolean;
  createdAt: string;
}

type Purpose = 'verify_email' | 'reset_password';

const CODE_TTL_MIN = 15;
const CODE_MAX_ATTEMPTS = 5;
const CODE_RESEND_SEC = 60;
const LOCK_AFTER = 10;
const LOCK_MIN = 15;

export const publicUser = (u: UserRow): PublicUser => ({
  id: u.id,
  email: u.email,
  name: u.name,
  emailVerified: !!u.email_verified_at,
  hasPassword: !!u.password_hash,
  appleLinked: !!u.apple_sub,
  createdAt: u.created_at,
});

const COMMON = new Set(['password123', 'password1234', '1234567890', 'qwertyuiop', 'iloveyou12', 'letmein123', 'welcome123', 'passwort123']);

export const passwordProblem = (pw: string, email?: string | null): string | undefined => {
  if (pw.length < 10) return 'Password must be at least 10 characters.';
  if (pw.length > 128) return 'Password must be at most 128 characters.';
  if (/^(.)\1+$/.test(pw)) return 'Password is too repetitive.';
  if (COMMON.has(pw.toLowerCase())) return 'Password is too common.';
  if (email && pw.toLowerCase().includes(email.split('@')[0]!.toLowerCase()) && email.split('@')[0]!.length >= 4)
    return 'Password must not contain your email name.';
  return undefined;
};

export interface AuthDeps {
  db: DB;
  config: Config;
  mailer: Mailer;
  apple: AppleVerifier;
  now: () => Date;
}

export class AuthService {
  private readonly key: Uint8Array;
  private readonly d: AuthDeps;
  constructor(d: AuthDeps) {
    this.d = d;
    this.key = new TextEncoder().encode(d.config.jwtSecret);
  }

  private iso(offsetMs = 0) {
    return new Date(this.d.now().getTime() + offsetMs).toISOString();
  }

  // ───────────── users

  userById(id: string): UserRow | undefined {
    return this.d.db.prepare('SELECT * FROM users WHERE id = ?').get(id) as UserRow | undefined;
  }
  userByEmail(email: string): UserRow | undefined {
    return this.d.db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRow | undefined;
  }

  private assertPassword(pw: string, email?: string | null) {
    const p = passwordProblem(pw, email);
    if (p) throw new ApiError(400, 'weak_password', p);
  }

  // ───────────── registration & verification

  async register(email: string, password: string, name: string | undefined, acceptedTerms: boolean): Promise<void> {
    if (!acceptedTerms) throw new ApiError(400, 'terms_required', 'You must accept the terms and privacy policy.');
    this.assertPassword(password, email);
    const hash = await hashPassword(password);
    const existing = this.userByEmail(email);
    const now = this.iso();

    if (existing && (existing.email_verified_at || existing.apple_sub)) {
      // Enumeration-safe: same response, owner gets a heads-up instead of a code.
      await this.d.mailer.send({
        to: email,
        subject: `${this.d.config.appName}: you already have an account`,
        text: `Someone (hopefully you) tried to register with this email.\nYou already have an account — sign in, or use "Forgot password" to reset it.\nIf this wasn't you, ignore this email.`,
      });
      return;
    }
    let userId: string;
    if (existing) {
      userId = existing.id;
      this.d.db
        .prepare('UPDATE users SET password_hash = ?, name = COALESCE(?, name), terms_accepted_at = ?, updated_at = ? WHERE id = ?')
        .run(hash, name ?? null, now, now, userId);
    } else {
      userId = randomUUID();
      this.d.db
        .prepare(
          'INSERT INTO users (id, email, password_hash, name, terms_accepted_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        )
        .run(userId, email, hash, name ?? null, now, now, now);
    }
    await this.sendCode(userId, email, 'verify_email', true);
  }

  async resendVerification(email: string): Promise<void> {
    const u = this.userByEmail(email);
    if (!u || u.email_verified_at || !u.email) return;
    await this.sendCode(u.id, u.email, 'verify_email', false);
  }

  async verifyEmail(email: string, code: string, device?: string): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const u = this.userByEmail(email);
    if (!u) throw new ApiError(400, 'invalid_code', 'Invalid or expired code.');
    this.consumeCode(u.id, 'verify_email', code);
    const now = this.iso();
    this.d.db.prepare('UPDATE users SET email_verified_at = COALESCE(email_verified_at, ?), updated_at = ? WHERE id = ?').run(now, now, u.id);
    return { user: publicUser(this.userById(u.id)!), tokens: await this.issueTokens(u.id, device) };
  }

  // ───────────── login

  async login(email: string, password: string, device?: string): Promise<{ user: PublicUser; tokens: TokenPair }> {
    const u = this.userByEmail(email);
    if (!u || !u.password_hash) {
      await burnPasswordCheck(password);
      throw new ApiError(401, 'invalid_credentials', 'Email or password is incorrect.');
    }
    if (u.locked_until && u.locked_until > this.iso()) {
      throw new ApiError(429, 'account_locked', 'Too many failed attempts. Try again later or reset your password.', {
        lockedUntil: u.locked_until,
      });
    }
    if (!(await verifyPassword(password, u.password_hash))) {
      const fails = u.failed_logins + 1;
      const lock = fails >= LOCK_AFTER ? this.iso(LOCK_MIN * 60_000) : null;
      this.d.db
        .prepare('UPDATE users SET failed_logins = ?, locked_until = ? WHERE id = ?')
        .run(lock ? 0 : fails, lock, u.id);
      throw new ApiError(401, 'invalid_credentials', 'Email or password is incorrect.');
    }
    this.d.db.prepare('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ?').run(u.id);
    if (!u.email_verified_at) {
      await this.sendCode(u.id, u.email!, 'verify_email', false);
      throw new ApiError(403, 'email_not_verified', 'Verify your email first. We sent you a new code.');
    }
    return { user: publicUser(u), tokens: await this.issueTokens(u.id, device) };
  }

  async signInWithApple(
    identityToken: string,
    name: string | undefined,
    device?: string,
  ): Promise<{ user: PublicUser; tokens: TokenPair; created: boolean }> {
    let identity;
    try {
      identity = await this.d.apple(identityToken);
    } catch {
      throw new ApiError(401, 'invalid_apple_token', 'Apple sign-in could not be verified.');
    }
    const now = this.iso();
    let created = false;
    const userId = tx(this.d.db, () => {
      const bySub = this.d.db.prepare('SELECT * FROM users WHERE apple_sub = ?').get(identity.sub) as UserRow | undefined;
      if (bySub) return bySub.id;
      const byEmail = identity.email && identity.emailVerified ? this.userByEmail(identity.email) : undefined;
      if (byEmail) {
        this.d.db
          .prepare(
            'UPDATE users SET apple_sub = ?, email_verified_at = COALESCE(email_verified_at, ?), name = COALESCE(name, ?), updated_at = ? WHERE id = ?',
          )
          .run(identity.sub, now, name ?? null, now, byEmail.id);
        return byEmail.id;
      }
      const id = randomUUID();
      created = true;
      this.d.db
        .prepare(
          'INSERT INTO users (id, email, email_verified_at, name, apple_sub, terms_accepted_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        )
        .run(id, identity.email ?? null, identity.email ? now : null, name ?? null, identity.sub, now, now, now);
      return id;
    });
    return { user: publicUser(this.userById(userId)!), tokens: await this.issueTokens(userId, device), created };
  }

  // ───────────── password reset / change

  async forgotPassword(email: string): Promise<void> {
    const u = this.userByEmail(email);
    if (!u || !u.email) return;
    await this.sendCode(u.id, u.email, 'reset_password', false);
  }

  async resetPassword(email: string, code: string, newPassword: string): Promise<void> {
    const u = this.userByEmail(email);
    if (!u) throw new ApiError(400, 'invalid_code', 'Invalid or expired code.');
    this.assertPassword(newPassword, email);
    this.consumeCode(u.id, 'reset_password', code);
    const hash = await hashPassword(newPassword);
    const now = this.iso();
    this.d.db
      .prepare(
        'UPDATE users SET password_hash = ?, email_verified_at = COALESCE(email_verified_at, ?), failed_logins = 0, locked_until = NULL, updated_at = ? WHERE id = ?',
      )
      .run(hash, now, now, u.id);
    this.revokeAll(u.id);
    await this.notifyPasswordChanged(email);
  }

  async changePassword(userId: string, current: string | undefined, next: string, device?: string): Promise<TokenPair> {
    const u = this.userById(userId)!;
    if (u.password_hash) {
      if (!current || !(await verifyPassword(current, u.password_hash)))
        throw new ApiError(401, 'invalid_credentials', 'Current password is incorrect.');
    }
    this.assertPassword(next, u.email);
    const now = this.iso();
    this.d.db.prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?').run(await hashPassword(next), now, userId);
    this.revokeAll(userId);
    if (u.email) await this.notifyPasswordChanged(u.email);
    return this.issueTokens(userId, device);
  }

  private notifyPasswordChanged(email: string) {
    return this.d.mailer.send({
      to: email,
      subject: `${this.d.config.appName}: password changed`,
      text: `Your password was changed and all devices were signed out.\nIf this wasn't you, reset your password immediately.`,
    });
  }

  // ───────────── account

  updateName(userId: string, name: string | null): PublicUser {
    this.d.db.prepare('UPDATE users SET name = ?, updated_at = ? WHERE id = ?').run(name, this.iso(), userId);
    return publicUser(this.userById(userId)!);
  }

  async deleteAccount(userId: string, password: string | undefined): Promise<void> {
    const u = this.userById(userId)!;
    if (u.password_hash && (!password || !(await verifyPassword(password, u.password_hash))))
      throw new ApiError(401, 'invalid_credentials', 'Password is incorrect.');
    this.d.db.prepare('DELETE FROM users WHERE id = ?').run(userId);
    if (u.email && u.email_verified_at)
      await this.d.mailer.send({
        to: u.email,
        subject: `${this.d.config.appName}: account deleted`,
        text: 'Your account and all associated data have been permanently deleted.',
      });
  }

  // ───────────── codes

  private async sendCode(userId: string, email: string, purpose: Purpose, force: boolean): Promise<void> {
    const last = this.d.db
      .prepare('SELECT created_at FROM codes WHERE user_id = ? AND purpose = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1')
      .get(userId, purpose) as { created_at: string } | undefined;
    if (!force && last && last.created_at > this.iso(-CODE_RESEND_SEC * 1000)) return; // throttle
    const code = sixDigitCode();
    const now = this.iso();
    tx(this.d.db, () => {
      this.d.db.prepare('UPDATE codes SET consumed_at = ? WHERE user_id = ? AND purpose = ? AND consumed_at IS NULL').run(now, userId, purpose);
      this.d.db
        .prepare('INSERT INTO codes (id, user_id, purpose, code_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .run(randomUUID(), userId, purpose, this.codeHash(userId, purpose, code), this.iso(CODE_TTL_MIN * 60_000), now);
    });
    const what = purpose === 'verify_email' ? 'verify your email' : 'reset your password';
    await this.d.mailer.send({
      to: email,
      subject: `${this.d.config.appName}: ${code} is your code`,
      text: `Use this code to ${what}: ${code}\nIt expires in ${CODE_TTL_MIN} minutes.\nIf you didn't request it, ignore this email.`,
    });
  }

  private codeHash(userId: string, purpose: Purpose, code: string) {
    return hmac(this.d.config.codePepper, `${userId}:${purpose}:${code}`);
  }

  private consumeCode(userId: string, purpose: Purpose, code: string): void {
    const row = this.d.db
      .prepare(
        'SELECT id, code_hash, attempts, expires_at FROM codes WHERE user_id = ? AND purpose = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1',
      )
      .get(userId, purpose) as { id: string; code_hash: string; attempts: number; expires_at: string } | undefined;
    const invalid = new ApiError(400, 'invalid_code', 'Invalid or expired code.');
    if (!row || row.expires_at <= this.iso()) throw invalid;
    if (!safeEqualHex(row.code_hash, this.codeHash(userId, purpose, code))) {
      const attempts = row.attempts + 1;
      if (attempts >= CODE_MAX_ATTEMPTS) {
        this.d.db.prepare('UPDATE codes SET attempts = ?, consumed_at = ? WHERE id = ?').run(attempts, this.iso(), row.id);
        throw new ApiError(400, 'too_many_attempts', 'Too many wrong codes. Request a new one.');
      }
      this.d.db.prepare('UPDATE codes SET attempts = ? WHERE id = ?').run(attempts, row.id);
      throw invalid;
    }
    this.d.db.prepare('UPDATE codes SET consumed_at = ? WHERE id = ?').run(this.iso(), row.id);
  }

  // ───────────── tokens

  async issueTokens(userId: string, device?: string, familyId: string = randomUUID()): Promise<TokenPair> {
    const now = this.d.now();
    const accessToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuer('gym-workout')
      .setAudience('gym-workout-app')
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(now.getTime() / 1000) + this.d.config.accessTtlSec)
      .setJti(randomUUID())
      .sign(this.key);
    const refreshToken = randomToken(32);
    const expiresAt = this.iso(this.d.config.refreshTtlDays * 86_400_000);
    this.d.db
      .prepare(
        'INSERT INTO refresh_tokens (id, user_id, family_id, token_hash, device, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      )
      .run(randomUUID(), userId, familyId, sha256(refreshToken), device?.slice(0, 120) ?? null, expiresAt, now.toISOString());
    return {
      tokenType: 'Bearer',
      accessToken,
      accessTokenExpiresIn: this.d.config.accessTtlSec,
      refreshToken,
      refreshTokenExpiresAt: expiresAt,
    };
  }

  async verifyAccess(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        issuer: 'gym-workout',
        audience: 'gym-workout-app',
        currentDate: this.d.now(),
        algorithms: ['HS256'],
      });
      if (!payload.sub) throw new Error('no sub');
      return payload.sub;
    } catch {
      throw new ApiError(401, 'invalid_token', 'Access token invalid or expired.');
    }
  }

  /** Rotating refresh: each token is single-use; replaying a used token revokes the whole family. */
  async refresh(raw: string, device?: string): Promise<TokenPair> {
    const row = this.d.db.prepare('SELECT * FROM refresh_tokens WHERE token_hash = ?').get(sha256(raw)) as
      | { id: string; user_id: string; family_id: string; expires_at: string; revoked_at: string | null }
      | undefined;
    const invalid = new ApiError(401, 'invalid_refresh_token', 'Session expired. Sign in again.');
    if (!row) throw invalid;
    const now = this.iso();
    if (row.revoked_at) {
      this.d.db.prepare('UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, ?) WHERE family_id = ?').run(now, row.family_id);
      throw invalid;
    }
    if (row.expires_at <= now) throw invalid;
    const pair = await this.issueTokens(row.user_id, device, row.family_id);
    const newId = (this.d.db.prepare('SELECT id FROM refresh_tokens WHERE token_hash = ?').get(sha256(pair.refreshToken)) as { id: string }).id;
    this.d.db.prepare('UPDATE refresh_tokens SET revoked_at = ?, replaced_by = ? WHERE id = ?').run(now, newId, row.id);
    return pair;
  }

  logout(raw: string): void {
    const row = this.d.db.prepare('SELECT family_id FROM refresh_tokens WHERE token_hash = ?').get(sha256(raw)) as
      | { family_id: string }
      | undefined;
    if (row) this.d.db.prepare('UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, ?) WHERE family_id = ?').run(this.iso(), row.family_id);
  }

  revokeAll(userId: string): void {
    this.d.db.prepare('UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, ?) WHERE user_id = ?').run(this.iso(), userId);
  }

  sessions(userId: string) {
    return this.d.db
      .prepare(
        'SELECT device, created_at AS createdAt, expires_at AS expiresAt FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY created_at DESC',
      )
      .all(userId, this.iso());
  }
}
