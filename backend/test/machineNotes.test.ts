import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-15T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
  });
});
afterEach(() => app.close());

const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const post = (url: string, payload: object, token: string) => app.inject({ method: 'POST', url, payload, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });
const del = (url: string, token: string) => app.inject({ method: 'DELETE', url, headers: auth(token) });
const putJpeg = (url: string, body: Buffer, token: string) =>
  app.inject({ method: 'PUT', url, payload: body, headers: { ...auth(token), 'content-type': 'image/jpeg' } });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

/** Minimal valid JPEG header (SOI, APP1 EXIF, SOF0 64×64, SOS, EOI) for the sanitizer. */
const jpeg = () => {
  const exif = Buffer.from([0xff, 0xe1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
  const sof = Buffer.from([0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x40, 0x00, 0x40, 0x01, 0x01, 0x11, 0x00]);
  const sos = Buffer.from([0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x12, 0x34, 0xff, 0xd9]);
  return Buffer.concat([Buffer.from([0xff, 0xd8]), exif, sof, sos]);
};

const sample = (id: string = randomUUID().toUpperCase()) => ({
  id,
  gymId: 'place:abc',
  gymName: 'Fitnesspark Schlieren',
  exerciseId: 'leg-curl',
  equipment: 'leg-curl',
  fields: [
    { label: 'Seat', value: '4' },
    { label: 'Pad', value: '2' },
  ],
  text: 'Pad just above heels',
});

describe('machine setup notes (#355)', () => {
  it('upserts, deltas, photos, isolates, exports and deletes; account delete removes them', async () => {
    const t = await signUp('lifter@example.com');
    const other = await signUp('other@example.com');
    const n = sample();
    expect((await post('/v1/me/machine-notes', { notes: [n] }, t)).statusCode).toBe(200);
    const list = (await get('/v1/me/machine-notes', t)).json() as { notes: { id: string; fields: unknown[]; photoId: string | null }[]; serverTime: string };
    expect(list.notes).toHaveLength(1);
    expect(list.notes[0]!.fields).toHaveLength(2);
    expect(list.notes[0]!.photoId).toBeNull();
    expect(((await get('/v1/me/machine-notes', other)).json() as { notes: unknown[] }).notes).toHaveLength(0);

    // Another member can't overwrite it or attach a photo.
    await post('/v1/me/machine-notes', { notes: [{ ...n, text: 'hijack' }] }, other);
    expect(((await get('/v1/me/machine-notes', t)).json() as { notes: { text: string }[] }).notes[0]!.text).toBe('Pad just above heels');
    expect((await putJpeg(`/v1/me/machine-notes/${n.id}/photo`, jpeg(), other)).statusCode).toBe(404);

    advance(1000);
    const since = list.serverTime;
    const up = await putJpeg(`/v1/me/machine-notes/${n.id}/photo`, jpeg(), t);
    expect(up.statusCode).toBe(200);
    const photoId = (up.json() as { photoId: string }).photoId;
    const delta = (await get(`/v1/me/machine-notes?since=${encodeURIComponent(since)}`, t)).json() as { notes: { photoId: string }[] };
    expect(delta.notes[0]!.photoId).toBe(photoId);
    // Re-syncing the note keeps its photo.
    await post('/v1/me/machine-notes', { notes: [{ ...n, photoId: null }] }, t);
    expect(((await get('/v1/me/machine-notes', t)).json() as { notes: { photoId: string }[] }).notes[0]!.photoId).toBe(photoId);

    const img = await get(`/v1/me/machine-notes/photos/${photoId}`, t);
    expect(img.statusCode).toBe(200);
    expect(img.headers['cache-control']).toContain('private');
    expect(img.rawPayload.includes(Buffer.from('Exif'))).toBe(false);
    expect((await get(`/v1/me/machine-notes/photos/${photoId}`, other)).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/v1/me/machine-notes/photos/${photoId}` })).statusCode).toBe(401);

    const exp = (await get('/v1/me/export', t)).json() as { machineNotes: { photoJpegBase64: string | null }[] };
    expect(exp.machineNotes).toHaveLength(1);
    expect(exp.machineNotes[0]!.photoJpegBase64).toBeTruthy();

    expect((await del(`/v1/me/machine-notes/${n.id}/photo`, t)).statusCode).toBe(200);
    expect((await get(`/v1/me/machine-notes/photos/${photoId}`, t)).statusCode).toBe(404);

    const n2 = sample();
    await post('/v1/me/machine-notes', { notes: [n2] }, t);
    await putJpeg(`/v1/me/machine-notes/${n2.id}/photo`, jpeg(), t);
    expect((await del(`/v1/me/machine-notes/${n.id}`, t)).statusCode).toBe(204);
    expect(((await get('/v1/me/machine-notes', t)).json() as { notes: unknown[] }).notes).toHaveLength(1);

    const res = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(t), payload: { password: PW, confirm: 'DELETE' } });
    expect(res.statusCode).toBe(204);
    expect((db.prepare('SELECT COUNT(*) AS c FROM machine_notes').get() as { c: number }).c).toBe(0);
    expect((db.prepare('SELECT COUNT(*) AS c FROM machine_note_photos').get() as { c: number }).c).toBe(0);
  });

  it('rejects oversized notes', async () => {
    const t = await signUp('big@example.com');
    const many = Array.from({ length: 9 }, (_, i) => ({ label: `F${i}`, value: '1' }));
    expect((await post('/v1/me/machine-notes', { notes: [{ ...sample(), fields: many }] }, t)).statusCode).toBe(400);
    expect((await post('/v1/me/machine-notes', { notes: [{ ...sample(), text: 'x'.repeat(1001) }] }, t)).statusCode).toBe(400);
  });
});
