import { argon2 as argon2Cb, createHash, createHmac, randomBytes, randomInt, scrypt as scryptCb, timingSafeEqual, type ScryptOptions } from 'node:crypto';
import { ApiError } from './errors.ts';

/**
 * Password hashes running at once: each holds ~32 MB and a libuv thread (the pool has 4), so a burst of sign-ins
 * queues here instead of starving file and zlib work or memory.
 */
const MAX_HASHES = 2;
/** Hashes allowed to wait (#927): beyond this a burst is refused with 503 instead of making every sign-in wait. */
export const MAX_WAITING = 64;
let running = 0;
const waiting: (() => void)[] = [];

/** Hashes running and queued (tests). */
export const hashSlots = () => ({ running, waiting: waiting.length });

const slot = async <T>(work: () => Promise<T>): Promise<T> => {
  if (running < MAX_HASHES) running++;
  else if (waiting.length >= MAX_WAITING) throw new ApiError(503, 'busy', 'Too many sign-ins right now. Try again in a moment.');
  else await new Promise<void>((go) => waiting.push(go)); // the finishing hash hands its slot over
  try {
    return await work();
  } finally {
    const next = waiting.shift();
    if (next) next();
    else running--;
  }
};

const scrypt = (pw: string, salt: Buffer, len: number, opts: ScryptOptions): Promise<Buffer> =>
  slot(() => new Promise<Buffer>((res, rej) => scryptCb(pw, salt, len, opts, (err, key) => (err ? rej(err) : res(key)))));

const argon2id = (pw: string, salt: Buffer, len: number, m: number, t: number, p: number): Promise<Buffer> =>
  slot(
    () =>
      new Promise<Buffer>((res, rej) =>
        argon2Cb('argon2id', { message: pw, nonce: salt, memory: m, passes: t, parallelism: p, tagLength: len }, (err, key) =>
          err ? rej(err) : res(key),
        ),
      ),
  );

// Argon2id, 32 MiB, 3 passes (above the OWASP minimum of 19 MiB × 2). Older scrypt hashes still verify and are
// replaced at the next sign-in (`needsRehash`).
const M = 32 * 1024;
const T = 3;
const P = 1;
const KEYLEN = 32;
const PREFIX = `$argon2id$v=19$m=${M},t=${T},p=${P}$`;
const MAXMEM = 64 * 1024 * 1024;
const b64 = (b: Buffer) => b.toString('base64').replace(/=+$/, '');

/** PHC string: `$argon2id$v=19$m=32768,t=3,p=1$<salt>$<hash>` (base64, no padding). */
export const hashPassword = async (pw: string): Promise<string> => {
  const salt = randomBytes(16);
  const key = await argon2id(pw.normalize('NFKC'), salt, KEYLEN, M, T, P);
  return `${PREFIX}${b64(salt)}$${b64(key)}`;
};

const ARGON = /^\$argon2id\$v=19\$m=(\d+),t=(\d+),p=(\d+)\$([A-Za-z0-9+/]+)\$([A-Za-z0-9+/]+)$/;

export const verifyPassword = async (pw: string, stored: string): Promise<boolean> => {
  const a = ARGON.exec(stored);
  if (a) {
    const expected = Buffer.from(a[5]!, 'base64');
    const key = await argon2id(pw.normalize('NFKC'), Buffer.from(a[4]!, 'base64'), expected.length, Number(a[1]), Number(a[2]), Number(a[3]));
    return timingSafeEqual(key, expected);
  }
  const [alg, n, r, p, saltB64, keyB64] = stored.split('$');
  if (alg !== 'scrypt' || !n || !r || !p || !saltB64 || !keyB64) return false;
  const expected = Buffer.from(keyB64, 'base64');
  const key = await scrypt(pw.normalize('NFKC'), Buffer.from(saltB64, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
    maxmem: MAXMEM,
  });
  return timingSafeEqual(key, expected);
};

/** True when a stored hash is not today's Argon2id cost and should be replaced after a successful check. */
export const needsRehash = (stored: string): boolean => !stored.startsWith(PREFIX);

/** Precomputed hash used to keep timing uniform for unknown accounts. */
let dummy: Promise<string> | undefined;
export const burnPasswordCheck = async (pw: string): Promise<void> => {
  dummy ??= hashPassword('dummy-password-for-timing');
  await verifyPassword(pw, await dummy);
};

export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');
export const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');
export const hmac = (secret: string, s: string): string => createHmac('sha256', secret).update(s).digest('hex');
export const sixDigitCode = (): string => String(randomInt(0, 1_000_000)).padStart(6, '0');

export const safeEqualHex = (a: string, b: string): boolean => {
  const ba = Buffer.from(a, 'hex');
  const bb = Buffer.from(b, 'hex');
  return ba.length === bb.length && timingSafeEqual(ba, bb);
};
