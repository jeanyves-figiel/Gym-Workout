import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.ts';
import { sanitizeJpeg } from '../src/community/image.ts';
import { loadConfig } from '../src/config.ts';
import { hashPassword, MAX_WAITING } from '../src/crypto.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { purgeExpired, UNVERIFIED_KEEP_DAYS } from '../src/purge.ts';
import { LINK } from '../src/routes/push.ts';

/** Security audit 2026-10-29 (#922, #925, #927, #928, #929). */

const sof = Buffer.from([0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x40, 0x00, 0x40, 0x01, 0x01, 0x11, 0x00]);
const sos = Buffer.from([0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]);
const exif = Buffer.from([0xff, 0xe1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
const scan = Buffer.from([0x12, 0xff, 0x00, 0x34, 0xff, 0xd0, 0x56]);
const eoi = Buffer.from([0xff, 0xd9]);
const soi = Buffer.from([0xff, 0xd8]);

describe('JPEG sanitizer (#929)', () => {
  it('drops bytes after the end of image', () => {
    const out = sanitizeJpeg(Buffer.concat([soi, sof, sos, scan, eoi, Buffer.from('PK\x03\x04 hidden zip')])).data;
    expect(out.subarray(-2)).toEqual(eoi);
    expect(out.toString('latin1')).not.toContain('hidden');
  });

  it('keeps scan data with stuffing and restarts, drops metadata between progressive scans', () => {
    const out = sanitizeJpeg(Buffer.concat([soi, sof, sos, scan, exif, sos, scan, eoi])).data;
    expect(out).toEqual(Buffer.concat([soi, sof, sos, scan, sos, scan, eoi]));
  });

  it('still refuses an end of image before any scan', () => {
    expect(() => sanitizeJpeg(Buffer.concat([soi, sof, eoi]))).toThrow();
  });
});

describe('achievement push text (#922)', () => {
  it('spots links and domains, not normal lines', () => {
    for (const bad of ['verify at https://x.io', 'go to www.example', 'login at evil.example', 'evil(dot)com']) expect(LINK.test(bad)).toBe(true);
    for (const ok of ['New PR: Bench press 100 kg × 3', '7-day streak. Keep going', 'Squat 102.5 kg']) expect(LINK.test(ok)).toBe(false);
  });
});

describe('unverified sign-ups (#928)', () => {
  it('are deleted after a week; verified and Apple accounts stay', () => {
    const db = openDb(':memory:');
    const now = new Date('2026-10-29T12:00:00Z');
    const old = new Date(now.getTime() - (UNVERIFIED_KEEP_DAYS + 1) * 86_400_000).toISOString();
    const add = (id: string, created: string, verified: string | null, apple: string | null) =>
      db.prepare('INSERT INTO users (id, email, email_verified_at, apple_sub, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, `${id}@x.co`, verified, apple, created, created);
    add('stale', old, null, null);
    add('fresh', now.toISOString(), null, null);
    add('verified', old, old, null);
    add('apple', old, null, 'sub');
    purgeExpired(db, now);
    expect((db.prepare('SELECT id FROM users ORDER BY id').all() as { id: string }[]).map((r) => r.id)).toEqual(['apple', 'fresh', 'verified']);
  });
});

describe('password hash queue (#927)', () => {
  it('refuses a burst beyond the queue with 503 busy', async () => {
    const results = await Promise.allSettled(Array.from({ length: MAX_WAITING + 10 }, () => hashPassword('a-long-password')));
    const busy = results.filter((r) => r.status === 'rejected' && (r.reason as { status?: number }).status === 503);
    expect(busy.length).toBeGreaterThan(0);
    expect(results.filter((r) => r.status === 'fulfilled').length).toBeGreaterThanOrEqual(MAX_WAITING);
  }, 60_000);
});

describe('security headers (#925)', () => {
  let app: FastifyInstance;
  afterEach(() => app.close());
  it('sends HSTS over HTTPS and nosniff + no-referrer everywhere', async () => {
    app = buildApp({
      config: loadConfig({ NODE_ENV: 'test' }),
      db: openDb(':memory:'),
      mailer: new ConsoleMailer(() => {}),
      apple: async () => {
        throw new Error('unused');
      },
    });
    const https = await app.inject({ method: 'GET', url: '/healthz', headers: { 'x-forwarded-proto': 'https' } });
    expect(https.headers['strict-transport-security']).toBe('max-age=31536000');
    const http = await app.inject({ method: 'GET', url: '/healthz' });
    expect(http.headers['strict-transport-security']).toBeUndefined();
    expect(http.headers['x-content-type-options']).toBe('nosniff');
    expect(http.headers['referrer-policy']).toBe('no-referrer');
  });
});
