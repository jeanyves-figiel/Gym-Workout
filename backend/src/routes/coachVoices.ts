import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import type { Synthesize } from '../coach/polly.ts';
import { STUDIO_VOICES, ssml, voiceLines } from '../coach/voiceLines.ts';
import { ApiError } from '../errors.ts';

/**
 * Studio coach voices (#395). GET /v1/me/coach-voices lists the voices and every line (id, text, hash);
 * GET /v1/me/coach-voices/:voice/:line returns the MP3. Each recording is made once with Polly and kept on the volume
 * (`<cacheDir>/<voice>/<hash>.mp3`), so a voice pack costs one Polly run per voice for every member together.
 */
export const coachVoiceRoutes = (
  r: FastifyInstance,
  synth: Synthesize | undefined,
  cacheDir: string | undefined,
  opts: { warm?: boolean; retryMs?: number } = {},
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
    if (running >= 2) await new Promise<void>((go) => waiting.push(go));
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

  const record = async (voice: string, lineId: string): Promise<Buffer> => {
    const line = byId.get(lineId)!;
    const key = `${voice}/${line.hash}`;
    const hit = memory.get(key);
    if (hit) return hit;
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
};
