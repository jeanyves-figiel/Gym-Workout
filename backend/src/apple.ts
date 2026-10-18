import { createRemoteJWKSet, jwtVerify } from 'jose';
import { sha256 } from './crypto.ts';
import type { DB } from './db.ts';
import { throttleTake } from './throttle.ts';

export interface AppleIdentity {
  sub: string;
  email?: string;
  emailVerified: boolean;
  /** Bundle id the token was issued to (`aud`); used as client_id for code exchange / revocation. */
  audience?: string;
  /** `nonce` claim: SHA-256 hex of the raw nonce the app passed to the Apple request (#432). */
  nonce?: string;
}

export type AppleVerifier = (identityToken: string) => Promise<AppleIdentity>;

const APPLE_ISSUER = 'https://appleid.apple.com';

/** Bundle IDs are case-insensitive (e.g. `Com.app.MonkeyWorkout`), so compare audiences case-insensitively. */
export const audienceAllowed = (aud: string | string[] | undefined, bundleIds: string[]): boolean => {
  const allowed = new Set(bundleIds.map((b) => b.toLowerCase()));
  return (Array.isArray(aud) ? aud : aud ? [aud] : []).some((a) => allowed.has(a.toLowerCase()));
};

/** Verifies a Sign in with Apple identity token (RS256, Apple JWKS, audience = app bundle id). */
export const createAppleVerifier = (bundleIds: string[]): AppleVerifier => {
  const jwks = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));
  return async (token) => {
    const { payload } = await jwtVerify(token, jwks, { issuer: APPLE_ISSUER, algorithms: ['RS256'] });
    if (!audienceAllowed(payload.aud, bundleIds)) throw new Error('Apple token audience mismatch');
    if (typeof payload.sub !== 'string') throw new Error('Apple token without sub');
    const ev = payload.email_verified;
    const auds = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];
    return {
      audience: auds.find((a) => audienceAllowed(a, bundleIds)),
      sub: payload.sub,
      email: typeof payload.email === 'string' ? payload.email.toLowerCase() : undefined,
      emailVerified: ev === true || ev === 'true',
      nonce: typeof payload.nonce === 'string' ? payload.nonce : undefined,
    };
  };
};

/** Apple identity tokens live 10 minutes; a nonce stays spent a little longer than that. */
const NONCE_WINDOW_MS = 15 * 60_000;

/**
 * Replay guard (#432): when the token carries a `nonce` claim, the request must send the raw nonce whose
 * lowercase SHA-256 hex matches it, and each claim is accepted once. Tokens without the claim (app builds
 * before the nonce) are still accepted so older installs can sign in.
 */
export const appleNonceOk = (db: DB, identity: AppleIdentity, rawNonce: string | undefined, now: Date): boolean => {
  if (identity.nonce === undefined) return true;
  if (rawNonce === undefined || sha256(rawNonce) !== identity.nonce) return false;
  return throttleTake(db, `apple-nonce:${identity.nonce}`, 1, NONCE_WINDOW_MS, now);
};
