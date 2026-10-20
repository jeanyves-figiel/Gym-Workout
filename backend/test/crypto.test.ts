import { describe, expect, it } from 'vitest';
import { hashPassword, hashSlots, verifyPassword } from '../src/crypto.ts';

describe('password hashing', () => {
  it('runs at most 2 scrypt hashes at once and queues the rest', async () => {
    const all = Promise.all(Array.from({ length: 5 }, (_, i) => hashPassword(`password-${i}`)));
    expect(hashSlots()).toEqual({ running: 2, waiting: 3 });
    const hashes = await all;
    expect(hashSlots()).toEqual({ running: 0, waiting: 0 });
    expect(await verifyPassword('password-3', hashes[3]!)).toBe(true);
    expect(await verifyPassword('password-3', hashes[2]!)).toBe(false);
  });
});
