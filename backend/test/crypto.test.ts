import { describe, expect, it } from 'vitest';
import { scryptSync } from 'node:crypto';
import { hashPassword, hashSlots, needsRehash, verifyPassword } from '../src/crypto.ts';

describe('password hashing', () => {
  it('runs at most 2 scrypt hashes at once and queues the rest', async () => {
    const all = Promise.all(Array.from({ length: 5 }, (_, i) => hashPassword(`password-${i}`)));
    expect(hashSlots()).toEqual({ running: 2, waiting: 3 });
    const hashes = await all;
    expect(hashSlots()).toEqual({ running: 0, waiting: 0 });
    expect(await verifyPassword('password-3', hashes[3]!)).toBe(true);
    expect(await verifyPassword('password-3', hashes[2]!)).toBe(false);
  });

  it('hashes with Argon2id and flags older scrypt hashes for upgrade', async () => {
    const now = await hashPassword('correct horse battery');
    expect(now).toMatch(/^\$argon2id\$v=19\$m=32768,t=3,p=1\$[A-Za-z0-9+/]{22}\$[A-Za-z0-9+/]{43}$/);
    expect(await verifyPassword('correct horse battery', now)).toBe(true);
    expect(await verifyPassword('wrong horse battery', now)).toBe(false);
    expect(needsRehash(now)).toBe(false);
    const salt = Buffer.alloc(16, 7);
    const key = scryptSync('correct horse battery', salt, 64, { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
    const old = `scrypt$32768$8$1$${salt.toString('base64')}$${key.toString('base64')}`;
    expect(await verifyPassword('correct horse battery', old)).toBe(true);
    expect(needsRehash(old)).toBe(true);
  });
});
