import { randomUUID } from 'node:crypto';
import { publicUser, type PublicUser, type UserRow } from './auth.ts';
import type { Config } from './config.ts';
import { hmac, safeEqualHex, sixDigitCode, verifyPassword } from './crypto.ts';
import { type DB, tx } from './db.ts';
import { ApiError } from './errors.ts';
import type { Mailer } from './mailer.ts';

const CODE_TTL_MIN = 15;
const CODE_MAX_ATTEMPTS = 5;
const RESEND_SEC = 60;

export interface EmailChangeDeps {
  db: DB;
  config: Config;
  mailer: Mailer;
  now: () => Date;
}

/** Masks `climber@example.com` → `cl•••@example.com` for notices sent to the old address. */
export const maskEmail = (email: string): string => {
  const [local = '', domain = ''] = email.split('@');
  return `${local.slice(0, 2)}•••@${domain}`;
};

/**
 * Change of account email (#12): request sends a 6-digit code to the new address, confirm swaps it
 * and notifies the old address. Enumeration-safe: an address owned by another account gets a notice,
 * never a code, and the caller sees the same 202.
 */
export class EmailChangeService {
  private readonly d: EmailChangeDeps;
  constructor(d: EmailChangeDeps) {
    this.d = d;
  }

  private iso(offsetMs = 0) {
    return new Date(this.d.now().getTime() + offsetMs).toISOString();
  }

  private user(id: string) {
    return this.d.db.prepare('SELECT * FROM users WHERE id = ?').get(id) as UserRow | undefined;
  }

  private codeHash(userId: string, newEmail: string, code: string) {
    return hmac(this.d.config.codePepper, `${userId}:change_email:${newEmail.toLowerCase()}:${code}`);
  }

  async request(userId: string, newEmail: string, password: string | undefined): Promise<void> {
    const u = this.user(userId)!;
    if (u.password_hash && (!password || !(await verifyPassword(password, u.password_hash))))
      throw new ApiError(401, 'invalid_credentials', 'Password is incorrect.');
    if (u.email && u.email.toLowerCase() === newEmail) throw new ApiError(400, 'same_email', 'That is already your email.');

    const owner = this.d.db.prepare('SELECT id FROM users WHERE email = ?').get(newEmail) as { id: string } | undefined;
    if (owner) {
      await this.d.mailer.send({
        to: newEmail,
        subject: `${this.d.config.appName}: email change attempt`,
        text: `Someone tried to move another ${this.d.config.appName} account to this email address.\nThis address already has an account, so nothing changed. If this wasn't you, you can ignore this email.`,
      });
      return;
    }

    const last = this.d.db
      .prepare('SELECT new_email, created_at FROM email_changes WHERE user_id = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1')
      .get(userId) as { new_email: string; created_at: string } | undefined;
    if (last && last.new_email.toLowerCase() === newEmail && last.created_at > this.iso(-RESEND_SEC * 1000)) return; // throttle resends

    const code = sixDigitCode();
    const now = this.iso();
    tx(this.d.db, () => {
      this.d.db.prepare('UPDATE email_changes SET consumed_at = ? WHERE user_id = ? AND consumed_at IS NULL').run(now, userId);
      this.d.db
        .prepare('INSERT INTO email_changes (id, user_id, new_email, code_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .run(randomUUID(), userId, newEmail, this.codeHash(userId, newEmail, code), this.iso(CODE_TTL_MIN * 60_000), now);
    });
    await this.d.mailer.send({
      to: newEmail,
      subject: `${this.d.config.appName}: ${code} is your code`,
      text: `Use this code to confirm your new email address: ${code}\nIt expires in ${CODE_TTL_MIN} minutes.\nIf you didn't request it, ignore this email.`,
    });
  }

  async confirm(userId: string, code: string): Promise<PublicUser> {
    const row = this.d.db
      .prepare(
        'SELECT id, new_email, code_hash, attempts, expires_at FROM email_changes WHERE user_id = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1',
      )
      .get(userId) as { id: string; new_email: string; code_hash: string; attempts: number; expires_at: string } | undefined;
    const invalid = new ApiError(400, 'invalid_code', 'Invalid or expired code.');
    if (!row || row.expires_at <= this.iso()) throw invalid;
    if (!safeEqualHex(row.code_hash, this.codeHash(userId, row.new_email, code))) {
      const attempts = row.attempts + 1;
      if (attempts >= CODE_MAX_ATTEMPTS) {
        this.d.db.prepare('UPDATE email_changes SET attempts = ?, consumed_at = ? WHERE id = ?').run(attempts, this.iso(), row.id);
        throw new ApiError(400, 'too_many_attempts', 'Too many wrong codes. Request a new one.');
      }
      this.d.db.prepare('UPDATE email_changes SET attempts = ? WHERE id = ?').run(attempts, row.id);
      throw invalid;
    }

    const old = this.user(userId)!.email;
    const now = this.iso();
    tx(this.d.db, () => {
      this.d.db.prepare('UPDATE email_changes SET consumed_at = ? WHERE id = ?').run(now, row.id);
      const taken = this.d.db.prepare('SELECT id FROM users WHERE email = ? AND id <> ?').get(row.new_email, userId);
      if (taken) throw new ApiError(409, 'email_taken', 'This email is already used by another account.');
      this.d.db.prepare('UPDATE users SET email = ?, email_verified_at = ?, updated_at = ? WHERE id = ?').run(row.new_email, now, now, userId);
      // Codes mailed to the old address (verification / reset) must not outlive the change.
      this.d.db.prepare('UPDATE codes SET consumed_at = ? WHERE user_id = ? AND consumed_at IS NULL').run(now, userId);
    });

    if (old && old.toLowerCase() !== row.new_email.toLowerCase())
      await this.d.mailer.send({
        to: old,
        subject: `${this.d.config.appName}: your email was changed`,
        text: `The email of your ${this.d.config.appName} account was changed to ${maskEmail(row.new_email)}.\nIf this wasn't you, someone has access to your account: reset your password and sign out all devices.`,
      });
    return publicUser(this.user(userId)!);
  }
}
