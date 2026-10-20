import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import type { Synthesize } from '../coach/polly.ts';
import { CALL_NAME, type CoachStyle, STUDIO_VOICES, STYLES, type VoiceLine, callLine, ssml, voiceLines } from '../coach/voiceLines.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { DAY, throttleCount, throttleHit, throttleTake } from '../throttle.ts';

/** Different call names a member may have recorded per day (#432): each new name is a paid Polly run. */
const CALL_NAMES_PER_DAY = 20;
/** Recordings kept in memory when there is no cache dir. */
const MEMORY_MAX = 200;

/**
 * Studio coach voices (#395). GET /v1/me/coach-voices lists the voices and every line (id, text, hash);
 * GET /v1/me/coach-voices/:voice/:line returns the MP3. Each recording is made once with Polly and kept on the volume
 * (`<cacheDir>/<voice>/<hash>.mp3`), so a voice pack costs one Polly run per voice for every member together.
 * GET /v1/me/coach-voices/:voice/call/:style with `X-Call-Name: Alex` (or `?name=Alex`) returns the short call said
 * before key lines (#415).
 */
export const coachVoiceRoutes = (
  r: FastifyInstance,
  synth: Synthesize | undefined,
  cacheDir: string | undefined,
  opts: { warm?: boolean; retryMs?: number; db?: DB; now?: () => Date } = {},
) => {
  const lines = voiceLines();
  const byId = new Map(lines.map((l) => [l.id, l]));
  const voices = new Set(STUDIO_VOICES.map((v) => v.id));
  const inFlight = new Map<string, Promise<Buffer>>();
  const memory = new Map<string, Buffer>();

  // Polly throttles bursts ("Rate exceeded", #402): two recordings at a time, retried with backoff when throttled.
  const retryMs = opts.retryMs ?? 400;
  let running = 0;
  const waiting: (() => void)[] = [];
  const polly = async (text: string, voice: string): Promise<Buffer> => {
    // `while`: a slot freed by a finishing call can be taken by a new caller before the woken one runs.
    while (running >= 2) await new Promise<void>((go) => waiting.push(go));
    running += 1;
    try {
      for (let attempt = 0; ; attempt += 1) {
        try {
          return await synth!(text, voice);
        } catch (e) {
          if (attempt >= 5 || !/rate exceeded|throttl|HTTP 429/i.test((e as Error).message)) throw e;
          await new Promise((wait) => setTimeout(wait, retryMs * 2 ** attempt));
        }
      }
    } finally {
      running -= 1;
      waiting.shift()?.();
    }
  };

  const record = async (voice: string, lineId: string | VoiceLine): Promise<Buffer> => {
    const line = typeof lineId === 'string' ? byId.get(lineId)! : lineId;
    const key = `${voice}/${line.hash}`;
    const hit = memory.get(key);
    if (hit) {
      memory.delete(key);
      memory.set(key, hit);
      return hit;
    }
    const file = cacheDir ? join(cacheDir, voice, `${line.hash}.mp3`) : undefined;
    if (file) {
      const cached = await readFile(file).catch(() => undefined);
      if (cached) return cached;
    }
    let p = inFlight.get(key);
    if (!p) {
      p = (async () => {
        const mp3 = await polly(ssml(line), voice);
        if (file) {
          await mkdir(join(cacheDir!, voice), { recursive: true });
          await writeFile(`${file}.tmp`, mp3);
          await rename(`${file}.tmp`, file);
        } else {
          memory.set(key, mp3);
          if (memory.size > MEMORY_MAX) memory.delete(memory.keys().next().value!);
        }
        return mp3;
      })().finally(() => inFlight.delete(key));
      inFlight.set(key, p);
    }
    return p;
  };

  // Production: record every voice ahead in the background, so a member's download is files from the volume.
  if (opts.warm && synth && cacheDir) {
    const timer = setTimeout(async () => {
      for (const v of STUDIO_VOICES) for (const l of lines) await record(v.id, l.id).catch((err) => r.log.warn({ err, voice: v.id, line: l.id }, 'coach voice warm-up'));
    }, 20_000);
    timer.unref();
  }

  r.get('/me/coach-voices', async () => ({
    available: !!synth,
    voices: STUDIO_VOICES.map(({ id, name, gender, accent, label }) => ({ id, name, gender, accent, label })),
    lines: lines.map(({ id, text, hash }) => ({ id, text, hash })),
  }));

  r.get('/me/coach-voices/:voice/:line', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { voice, line } = req.params as { voice: string; line: string };
    const id = line.replace(/\.mp3$/, '');
    if (!voices.has(voice) || !byId.has(id)) throw new ApiError(404, 'not_found', 'No such voice line.');
    if (!synth) throw new ApiError(503, 'voices_unavailable', 'Studio voices are not available right now.');
    try {
      const mp3 = await record(voice, id);
      return reply.header('content-type', 'audio/mpeg').header('cache-control', 'private, max-age=31536000, immutable').send(mp3);
    } catch (e) {
      req.log.error({ err: e, voice, line: id }, 'coach voice failed');
      throw new ApiError(502, 'voice_failed', 'Could not record this line right now.');
    }
  });

  r.get('/me/coach-voices/:voice/call/:style', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { voice, style } = req.params as { voice: string; style: string };
    const s = style.replace(/\.mp3$/, '') as CoachStyle;
    // `X-Call-Name` (percent-encoded UTF-8) keeps the name out of URLs; `?name=` still works for older apps.
    const header = req.headers['x-call-name'];
    let name = String((req.query as { name?: unknown }).name ?? '').trim();
    if (typeof header === 'string' && header) {
      try {
        name = decodeURIComponent(header).trim();
      } catch {
        name = '';
      }
    }
    if (!voices.has(voice) || !STYLES.includes(s)) throw new ApiError(404, 'not_found', 'No such voice line.');
    if (!CALL_NAME.test(name)) throw new ApiError(400, 'bad_name', 'Letters only, up to 24 characters.');
    if (!synth) throw new ApiError(503, 'voices_unavailable', 'Studio voices are not available right now.');
    if (opts.db) {
      const db = opts.db;
      const at = opts.now?.() ?? new Date();
      const nameKey = `voicecall:${req.userId!}:${name.toLowerCase()}`;
      if (throttleCount(db, nameKey, DAY, at) === 0) {
        if (!throttleTake(db, `voicecall:${req.userId!}`, CALL_NAMES_PER_DAY, DAY, at))
          throw new ApiError(429, 'daily_limit', 'That is a lot of names today. Try again tomorrow!');
        throttleHit(db, nameKey, DAY, at);
      }
    }
    try {
      const mp3 = await record(voice, callLine(name, s));
      return reply.header('content-type', 'audio/mpeg').header('cache-control', 'private, max-age=31536000, immutable').send(mp3);
    } catch (e) {
      req.log.error({ err: e, voice }, 'coach call failed');
      throw new ApiError(502, 'voice_failed', 'Could not record this line right now.');
    }
  });
};
