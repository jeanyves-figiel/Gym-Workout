import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';
import { importPKCS8, SignJWT } from 'jose';
import type { Config } from './config.ts';
import type { DB } from './db.ts';

export type Fetch = typeof fetch;

const APPLE = 'https://appleid.apple.com';
const TIMEOUT_MS = 5000;

export interface StoredAppleToken {
  clientId: string;
  refreshToken: string;
}

export interface AppleTokenDeps {
  config: Config;
  db: DB;
  fetch: Fetch;
  now: () => Date;
  log: (msg: string) => void;
}

/**
 * Sign in with Apple server-to-server calls (issue #13):
 * - at sign-in, exchange the app's `authorizationCode` for an Apple refresh token (stored AES-256-GCM encrypted);
 * - at account deletion, revoke that token (`/auth/revoke`) so the app disappears from the user's Apple ID.
 * Without APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY everything is skipped (logged once).
 * Never throws: Apple being down must not block sign-in or account deletion.
 */
export class AppleTokenService {
  private readonly d: AppleTokenDeps;
  private readonly encKey: Buffer;
  private warned = false;
  private signingKey?: Promise<CryptoKey>;

  constructor(d: AppleTokenDeps) {
    this.d = d;
    this.encKey = Buffer.from(hkdfSync('sha256', d.config.codePepper, 'apple-refresh-token', 'v1', 32));
  }

  get configured(): boolean {
    const a = this.d.config.appleSignIn;
    return !!(a.teamId && a.keyId && a.privateKey);
  }

  private skip(): boolean {
    if (this.configured) return false;
    if (!this.warned) {
      this.warned = true;
      this.d.log('Sign in with Apple token exchange/revocation disabled (APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY not set).');
    }
    return true;
  }

  /** ES256 client secret JWT (valid 5 min) as required by Apple's token endpoints. */
  async clientSecret(clientId: string): Promise<string> {
    const a = this.d.config.appleSignIn;
    this.signingKey ??= importPKCS8(a.privateKey!, 'ES256');
    const iat = Math.floor(this.d.now().getTime() / 1000);
    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: a.keyId! })
      .setIssuer(a.teamId!)
      .setSubject(clientId)
      .setAudience(APPLE)
      .setIssuedAt(iat)
      .setExpirationTime(iat + 300)
      .sign(await this.signingKey);
  }

  private resolveClientId(audience?: string): string | undefined {
    return audience ?? this.d.config.appleSignIn.clientId ?? this.d.config.appleBundleIds[0];
  }

  private async post(path: string, form: Record<string, string>): Promise<Response> {
    return this.d.fetch(`${APPLE}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(form).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  }

  /** Exchanges the authorization code and stores the refresh token for later revocation. */
  async storeFromCode(userId: string, code: string, audience?: string): Promise<void> {
    if (this.skip()) return;
    const clientId = this.resolveClientId(audience);
    if (!clientId) return;
    try {
      const res = await this.post('/auth/token', {
        client_id: clientId,
        client_secret: await this.clientSecret(clientId),
        code,
        grant_type: 'authorization_code',
      });
      if (!res.ok) {
        this.d.log(`Apple code exchange failed: HTTP ${res.status}`);
        return;
      }
      const body = (await res.json()) as { refresh_token?: unknown };
      if (typeof body.refresh_token !== 'string' || !body.refresh_token) {
        this.d.log('Apple code exchange returned no refresh token');
        return;
      }
      const now = this.d.now().toISOString();
      this.d.db
        .prepare(
          `INSERT INTO apple_tokens (user_id, client_id, refresh_token_enc, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(user_id) DO UPDATE SET client_id = excluded.client_id, refresh_token_enc = excluded.refresh_token_enc, updated_at = excluded.updated_at`,
        )
        .run(userId, clientId, this.encrypt(body.refresh_token), now, now);
    } catch (e) {
      this.d.log(`Apple code exchange error: ${(e as Error).name}`);
    }
  }

  tokenFor(userId: string): StoredAppleToken | undefined {
    const row = this.d.db.prepare('SELECT client_id, refresh_token_enc FROM apple_tokens WHERE user_id = ?').get(userId) as
      | { client_id: string; refresh_token_enc: string }
      | undefined;
    if (!row) return undefined;
    const refreshToken = this.decrypt(row.refresh_token_enc);
    return refreshToken ? { clientId: row.client_id, refreshToken } : undefined;
  }

  /** Revokes the user's Apple refresh token. Returns false on any failure (never throws). */
  async revoke(t: StoredAppleToken): Promise<boolean> {
    if (this.skip()) return false;
    try {
      const res = await this.post('/auth/revoke', {
        client_id: t.clientId,
        client_secret: await this.clientSecret(t.clientId),
        token: t.refreshToken,
        token_type_hint: 'refresh_token',
      });
      if (!res.ok) this.d.log(`Apple token revocation failed: HTTP ${res.status}`);
      return res.ok;
    } catch (e) {
      this.d.log(`Apple token revocation error: ${(e as Error).name}`);
      return false;
    }
  }

  private encrypt(plain: string): string {
    const iv = randomBytes(12);
    const c = createCipheriv('aes-256-gcm', this.encKey, iv);
    const ct = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return ['v1', iv.toString('base64url'), c.getAuthTag().toString('base64url'), ct.toString('base64url')].join(':');
  }

  private decrypt(stored: string): string | undefined {
    try {
      const [v, iv, tag, ct] = stored.split(':');
      if (v !== 'v1' || !iv || !tag || !ct) return undefined;
      const d = createDecipheriv('aes-256-gcm', this.encKey, Buffer.from(iv, 'base64url'));
      d.setAuthTag(Buffer.from(tag, 'base64url'));
      return Buffer.concat([d.update(Buffer.from(ct, 'base64url')), d.final()]).toString('utf8');
    } catch {
      return undefined; // pepper rotated / corrupted → cannot revoke, but never block deletion
    }
  }
}
