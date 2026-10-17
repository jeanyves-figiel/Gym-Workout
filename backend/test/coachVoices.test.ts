import { mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { pollySynthesizer, type Synthesize } from '../src/coach/polly.ts';
import { KINDS, STUDIO_VOICES, STYLES, VOICE_LINES, voiceLines } from '../src/coach/voiceLines.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';
let app: FastifyInstance;
let mailer: ConsoleMailer;
let calls: { ssml: string; voice: string }[];

const start = (opts: { synth?: Synthesize | null; dir?: string } = {}) => {
  mailer = new ConsoleMailer(() => {});
  calls = [];
  const synth: Synthesize = async (ssml, voice) => {
    calls.push({ ssml, voice });
    return Buffer.from(`mp3:${voice}`);
  };
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...(opts.dir ? { COACH_VOICE_DIR: opts.dir } : {}) }),
    db: openDb(':memory:'),
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    synth: opts.synth === null ? undefined : (opts.synth ?? synth),
  });
};
afterEach(() => app?.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};
const get = (token: string, url: string) => app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${token}` } });

describe('studio coach voices (#395)', () => {
  it('every style has lines for every kind, without numbers', () => {
    for (const s of STYLES) for (const k of KINDS) expect(VOICE_LINES[s][k].length).toBeGreaterThanOrEqual(2);
    for (const l of voiceLines()) expect(l.text).not.toMatch(/\d/);
    expect(new Set(voiceLines().map((l) => l.id)).size).toBe(voiceLines().length);
    expect(STUDIO_VOICES.some((v) => v.gender === 'male')).toBe(true);
  });

  it('lists voices and lines; needs sign-in', async () => {
    start();
    expect((await app.inject({ method: 'GET', url: '/v1/me/coach-voices' })).statusCode).toBe(401);
    const t = await signUp('a@example.com');
    const res = await get(t, '/v1/me/coach-voices');
    expect(res.statusCode).toBe(200);
    const body = res.json() as { available: boolean; voices: { id: string }[]; lines: { id: string; hash: string }[] };
    expect(body.available).toBe(true);
    expect(body.voices.map((v) => v.id)).toContain('Matthew');
    expect(body.lines.find((l) => l.id === 'hype-final-0')?.hash).toMatch(/^[0-9a-f]{16}$/);
  });

  it('records a line once, caches it on disk, rejects unknown lines', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'voices-'));
    start({ dir });
    const t = await signUp('b@example.com');
    const a = await get(t, '/v1/me/coach-voices/Arthur/hype-final-0.mp3');
    expect(a.statusCode).toBe(200);
    expect(a.headers['content-type']).toBe('audio/mpeg');
    expect(a.body).toBe('mp3:Arthur');
    expect(calls[0]!.ssml).toBe('<speak><prosody rate="108%">Last set! Make it count!</prosody></speak>');
    expect((await get(t, '/v1/me/coach-voices/Arthur/hype-final-0.mp3')).statusCode).toBe(200);
    expect(calls).toHaveLength(1);
    expect(readdirSync(join(dir, 'Arthur'))).toHaveLength(1);
    expect((await get(t, '/v1/me/coach-voices/Arthur/free-text')).statusCode).toBe(404);
    expect((await get(t, '/v1/me/coach-voices/Nobody/hype-final-0')).statusCode).toBe(404);
  });

  it('records two at a time and retries when Polly throttles (#402)', async () => {
    let running = 0;
    let peak = 0;
    const tried = new Set<string>();
    start({
      synth: async (ssml, voice) => {
        running += 1;
        peak = Math.max(peak, running);
        await new Promise((r) => setTimeout(r, 5));
        running -= 1;
        if (!tried.has(ssml)) {
          tried.add(ssml);
          throw new Error('Polly SynthesizeSpeech failed: HTTP 400 {"message":"Rate exceeded"}');
        }
        return Buffer.from(`mp3:${voice}`);
      },
    });
    const t = await signUp('d@example.com');
    const ids = ['hype-start-0', 'hype-start-1', 'hype-set-0', 'hype-set-1', 'chill-rest-0', 'drill-finish-0'];
    const res = await Promise.all(ids.map((id) => get(t, `/v1/me/coach-voices/Stephen/${id}.mp3`)));
    expect(res.map((r) => r.statusCode)).toEqual(ids.map(() => 200));
    expect(peak).toBeLessThanOrEqual(2);
  });

  it('answers 503 without Polly', async () => {
    start({ synth: null });
    const t = await signUp('c@example.com');
    expect((await get(t, '/v1/me/coach-voices')).json()).toMatchObject({ available: false });
    expect((await get(t, '/v1/me/coach-voices/Amy/chill-start-0')).statusCode).toBe(503);
  });

  it('signs a Polly request', async () => {
    let seen: { url: string; init: RequestInit } | undefined;
    const synth = pollySynthesizer({ region: 'eu-central-1', accessKeyId: 'AKID', secretAccessKey: 'secret' }, async (url, init) => {
      seen = { url: String(url), init: init! };
      return new Response(new Uint8Array([1, 2, 3]));
    }, () => new Date('2026-10-16T20:00:00Z'));
    const mp3 = await synth('<speak>Hi</speak>', 'Amy');
    expect([...mp3]).toEqual([1, 2, 3]);
    expect(seen!.url).toBe('https://polly.eu-central-1.amazonaws.com/v1/speech');
    expect(JSON.parse(String(seen!.init.body))).toMatchObject({ Engine: 'neural', VoiceId: 'Amy', TextType: 'ssml' });
    expect((seen!.init.headers as Record<string, string>).authorization).toMatch(/^AWS4-HMAC-SHA256 Credential=AKID\/20261016\/eu-central-1\/polly\/aws4_request/);
  });
});
