import { createRemoteJWKSet, jwtVerify } from 'jose';

export interface AppleIdentity {
  sub: string;
  email?: string;
  emailVerified: boolean;
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
    return {
      sub: payload.sub,
      email: typeof payload.email === 'string' ? payload.email.toLowerCase() : undefined,
      emailVerified: ev === true || ev === 'true',
    };
  };
};
