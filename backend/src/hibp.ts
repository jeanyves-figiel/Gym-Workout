import { createHash } from 'node:crypto';
import type { Fetch } from './appleTokens.ts';

export type BreachChecker = (password: string) => Promise<boolean>;

const RANGE_API = 'https://api.pwnedpasswords.com/range/';

/**
 * Have I Been Pwned k-anonymity check: only the first 5 hex chars of the SHA-1 leave the server,
 * responses are padded (`Add-Padding`). Fails open (returns false) on timeout / network / HTTP errors.
 */
export const createBreachChecker = (opts: { fetch: Fetch; timeoutMs?: number; log?: (msg: string) => void }): BreachChecker => {
  const timeoutMs = opts.timeoutMs ?? 2000;
  return async (password) => {
    const sha1 = createHash('sha1').update(password, 'utf8').digest('hex').toUpperCase();
    const prefix = sha1.slice(0, 5);
    const suffix = sha1.slice(5);
    try {
      const res = await opts.fetch(RANGE_API + prefix, {
        headers: { 'Add-Padding': 'true', 'User-Agent': 'MonkeyWorkout-API' },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!res.ok) {
        opts.log?.(`HIBP check skipped: HTTP ${res.status}`);
        return false;
      }
      for (const line of (await res.text()).split('\n')) {
        const [s, count] = line.trim().split(':');
        if (s === suffix && Number(count) > 0) return true; // padding rows have count 0
      }
      return false;
    } catch (e) {
      opts.log?.(`HIBP check skipped: ${(e as Error).name}`);
      return false;
    }
  };
};
