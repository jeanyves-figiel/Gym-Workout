import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { OVERPASS_URL, parseOverpass } from '../src/routes/pistes.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let asked: { url: string; body: string }[];
let fail = false;

const overpass = {
  elements: [
    { type: 'way', tags: { 'piste:type': 'downhill', 'piste:difficulty': 'intermediate', name: 'Standard', 'piste:ref': '12' },
      geometry: [{ lat: 46.512345678, lon: 7.912345678 }, { lat: 46.505, lon: 7.915 }] },
    { type: 'way', tags: { aerialway: 'gondola', name: 'Gondola Alpha' }, geometry: [{ lat: 46.5, lon: 7.91 }, { lat: 46.52, lon: 7.9 }] },
    { type: 'way', tags: { aerialway: 'pylon' }, geometry: [{ lat: 46.5, lon: 7.91 }, { lat: 46.51, lon: 7.91 }] },
    { type: 'way', tags: { 'piste:type': 'nordic' }, geometry: [{ lat: 46.5, lon: 7.91 }, { lat: 46.51, lon: 7.91 }] },
    { type: 'way', tags: { 'piste:type': 'downhill', 'piste:difficulty': '<script>' }, geometry: [{ lat: 46.5, lon: 7.91 }, { lat: 46.51, lon: 7.92 }] },
    { type: 'way', tags: { 'piste:type': 'downhill' }, geometry: [{ lat: 46.5 }] },
  ],
};

beforeEach(() => {
  mailer = new ConsoleMailer(() => {});
  asked = [];
  fail = false;
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db: openDb(':memory:'),
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    fetch: (async (url: string, init?: RequestInit) => {
      asked.push({ url: String(url), body: String(init?.body ?? '') });
      return fail ? new Response('busy', { status: 429 }) : new Response(JSON.stringify(overpass), { status: 200 });
    }) as typeof fetch,
  });
});
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  expect(res.statusCode).toBe(200);
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};

const pistes = (token: string, q: string) => app.inject({ method: 'GET', url: `/v1/me/pistes?${q}`, headers: { authorization: `Bearer ${token}` } });

describe('piste map (#1132)', () => {
  it('parses pistes and lifts, drops junk', () => {
    const p = parseOverpass(overpass);
    expect(p.pistes).toHaveLength(2);
    expect(p.pistes[0]).toEqual({ name: 'Standard', ref: '12', difficulty: 'intermediate', pts: [46.51235, 7.91235, 46.505, 7.915] });
    expect(p.pistes[1]!.difficulty).toBeUndefined();
    expect(p.lifts).toEqual([{ name: 'Gondola Alpha', kind: 'gondola', pts: [46.5, 7.91, 46.52, 7.9] }]);
    expect(parseOverpass(null)).toEqual({ pistes: [], lifts: [] });
  });

  it('reads hiking, MTB and cross-country trails (#1133)', () => {
    const geometry = [{ lat: 46.5, lon: 7.9 }, { lat: 46.51, lon: 7.91 }];
    const trails = {
      elements: [
        { tags: { sac_scale: 'demanding_mountain_hiking', name: 'Gratweg' }, geometry },
        { tags: { 'mtb:scale': '2+', name: 'Flowtrail' }, geometry },
        { tags: { 'piste:type': 'nordic', 'piste:difficulty': 'easy', name: 'Loipe Goms' }, geometry },
        { tags: { aerialway: 'chair_lift' }, geometry },
      ],
    };
    expect(parseOverpass(trails, 'hike')).toEqual({ pistes: [{ name: 'Gratweg', difficulty: 'T3', pts: [46.5, 7.9, 46.51, 7.91] }], lifts: [] });
    expect(parseOverpass(trails, 'mtb').pistes.map((p) => p.difficulty)).toEqual(['S2']);
    expect(parseOverpass(trails, 'nordic').pistes.map((p) => p.name)).toEqual(['Loipe Goms']);
    expect(parseOverpass(trails, 'downhill').lifts).toHaveLength(1);
  });

  it('asks Overpass for the kind of trail, cached per kind', async () => {
    const t = await signUp('hike@example.com');
    expect((await pistes(t, 's=46.51&w=7.91&n=46.53&e=7.95&kind=hike')).statusCode).toBe(200);
    expect(decodeURIComponent(asked[0]!.body)).toContain('way["sac_scale"]');
    expect(decodeURIComponent(asked[0]!.body)).not.toContain('aerialway');
    expect((await pistes(t, 's=46.51&w=7.91&n=46.53&e=7.95')).statusCode).toBe(200);
    expect(asked).toHaveLength(2);
    expect((await pistes(t, 's=46.51&w=7.91&n=46.53&e=7.95&kind=golf')).statusCode).toBe(400);
  });

  it('needs sign-in', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/me/pistes?s=46.5&w=7.9&n=46.52&e=7.95' })).statusCode).toBe(401);
  });

  it('serves a box from cached 0.1° tiles, asked of Overpass once', async () => {
    const t = await signUp('ski@example.com');
    const res = await pistes(t, 's=46.51&w=7.91&n=46.53&e=7.95');
    expect(res.statusCode).toBe(200);
    const body = res.json() as { pistes: unknown[]; lifts: unknown[]; attribution: string };
    expect(body.pistes).toHaveLength(2);
    expect(body.lifts).toHaveLength(1);
    expect(body.attribution).toContain('OpenStreetMap');
    expect(asked).toHaveLength(1);
    expect(asked[0]!.url).toBe(OVERPASS_URL);
    // The tile, never the member's own box.
    expect(decodeURIComponent(asked[0]!.body)).toContain('(46.5,7.9,46.6,8.0)');
    expect((await pistes(t, 's=46.52&w=7.92&n=46.54&e=7.96')).statusCode).toBe(200);
    expect(asked).toHaveLength(1);
    // Two tiles wide: the same ways come back once.
    const wide = await pistes(t, 's=46.51&w=7.91&n=46.53&e=8.05');
    expect(asked).toHaveLength(2);
    expect((wide.json() as { pistes: unknown[] }).pistes).toHaveLength(2);
  });

  it('refuses a region or a bad box, and says when the map is down', async () => {
    const t = await signUp('ski2@example.com');
    expect((await pistes(t, 's=46&w=7&n=47&e=8')).json()).toMatchObject({ error: 'too_large' });
    expect((await pistes(t, 's=47&w=7&n=46&e=8')).statusCode).toBe(400);
    expect((await pistes(t, 's=x')).statusCode).toBe(400);
    fail = true;
    const res = await pistes(t, 's=10.01&w=10.01&n=10.02&e=10.02');
    expect(res.statusCode).toBe(502);
    expect(res.json()).toMatchObject({ error: 'map_unavailable' });
  });
});
