import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Fetch } from '../appleTokens.ts';
import { ApiError } from '../errors.ts';

/**
 * Piste map (#1132): ski pistes and lifts from OpenStreetMap (`piste:type=downhill`, `aerialway=*`, ODbL), for the
 * iPhone's ski session map. The app asks for the box around a day's track only after the member said yes; this server
 * asks Overpass on its behalf so the member's IP never reaches a third party, and serves the same 0.1° tiles to
 * everyone from a cache (Overpass asks for light use). Nothing about the request is stored.
 *
 * `GET /v1/me/pistes?s=&w=&n=&e=` → `{pistes: [{name?, ref?, difficulty?, pts}], lifts: [{name?, kind, pts}], attribution}`,
 * `pts` = flat `[lat, lon, …]` with 5 decimals.
 */

export const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';
const TILE = 0.1;
/** Biggest box served: a resort, not a region (2 × 2 tiles of about 11 km). */
const MAX_TILES = 4;
const TTL_MS = 7 * 24 * 3600 * 1000;
const CACHE_MAX = 300;

export type PisteLine = { name?: string; ref?: string; difficulty?: string; pts: number[] };
export type LiftLine = { name?: string; kind: string; pts: number[] };
type Tile = { pistes: PisteLine[]; lifts: LiftLine[]; at: number };

const query = z.object({
  s: z.coerce.number().min(-90).max(90),
  w: z.coerce.number().min(-180).max(180),
  n: z.coerce.number().min(-90).max(90),
  e: z.coerce.number().min(-180).max(180),
});

const DIFFICULTIES = new Set(['novice', 'easy', 'intermediate', 'advanced', 'expert', 'freeride', 'extreme']);
const text = (v: unknown, max = 60) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : undefined);
const round = (v: number) => Math.round(v * 1e5) / 1e5;

/** Overpass `out geom` ways → compact pistes and lifts. Unknown shapes are skipped, never trusted. */
export const parseOverpass = (json: unknown): { pistes: PisteLine[]; lifts: LiftLine[] } => {
  const pistes: PisteLine[] = [];
  const lifts: LiftLine[] = [];
  const elements = (json as { elements?: unknown })?.elements;
  if (!Array.isArray(elements)) return { pistes, lifts };
  for (const el of elements) {
    const tags = (el as { tags?: Record<string, unknown> }).tags ?? {};
    const geom = (el as { geometry?: unknown }).geometry;
    if (!Array.isArray(geom) || geom.length < 2) continue;
    const pts: number[] = [];
    for (const g of geom) {
      const { lat, lon } = g as { lat?: unknown; lon?: unknown };
      if (typeof lat === 'number' && typeof lon === 'number') pts.push(round(lat), round(lon));
    }
    if (pts.length < 4) continue;
    const name = text(tags.name) ?? text(tags['piste:name']);
    if (tags['piste:type'] === 'downhill') {
      const d = text(tags['piste:difficulty'], 20);
      pistes.push({ name, ref: text(tags['piste:ref'] ?? tags.ref, 10), difficulty: d && DIFFICULTIES.has(d) ? d : undefined, pts });
    } else if (typeof tags.aerialway === 'string' && !['station', 'pylon', 'goods', 'zip_line'].includes(tags.aerialway)) {
      lifts.push({ name, kind: tags.aerialway.slice(0, 20), pts });
    }
  }
  return { pistes, lifts };
};

export const pisteRoutes = (r: FastifyInstance, fetch: Fetch, now: () => Date = () => new Date()) => {
  const cache = new Map<string, Tile>();

  const tile = async (lat: number, lon: number): Promise<Tile> => {
    const key = `${lat.toFixed(1)},${lon.toFixed(1)}`;
    const hit = cache.get(key);
    if (hit && now().getTime() - hit.at < TTL_MS) return hit;
    const box = `${lat.toFixed(1)},${lon.toFixed(1)},${(lat + TILE).toFixed(1)},${(lon + TILE).toFixed(1)}`;
    const q = `[out:json][timeout:25];(way["piste:type"="downhill"](${box});way["aerialway"](${box}););out geom tags;`;
    let res: Response;
    try {
      res = await fetch(OVERPASS_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'MonkeyWorkout piste map' },
        body: `data=${encodeURIComponent(q)}`,
        signal: AbortSignal.timeout(30_000),
      });
    } catch {
      throw new ApiError(502, 'map_unavailable', 'The piste map could not be loaded. Try again later.');
    }
    if (!res.ok) throw new ApiError(502, 'map_unavailable', 'The piste map could not be loaded. Try again later.');
    const t: Tile = { ...parseOverpass(await res.json().catch(() => null)), at: now().getTime() };
    cache.delete(key);
    cache.set(key, t);
    while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value as string);
    return t;
  };

  r.get('/me/pistes', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (req) => {
    const q = query.safeParse(req.query);
    if (!q.success || q.data.n < q.data.s || q.data.e < q.data.w) throw new ApiError(400, 'invalid_request', 'Give the box as s, w, n, e.');
    const s0 = Math.floor(q.data.s / TILE) * TILE;
    const w0 = Math.floor(q.data.w / TILE) * TILE;
    const rows = Math.floor(q.data.n / TILE) - Math.floor(q.data.s / TILE) + 1;
    const cols = Math.floor(q.data.e / TILE) - Math.floor(q.data.w / TILE) + 1;
    if (rows * cols > MAX_TILES) throw new ApiError(400, 'too_large', 'Pick a smaller area: one resort at a time.');
    const tiles: Tile[] = [];
    for (let i = 0; i < rows; i++) for (let j = 0; j < cols; j++) tiles.push(await tile(s0 + i * TILE, w0 + j * TILE));
    // A way crossing a tile edge comes back from both tiles: keep it once.
    const seen = new Set<string>();
    const once = <T extends { pts: number[] }>(l: T) => {
      const k = l.pts.slice(0, 4).join(',') + '|' + l.pts.length;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    };
    return {
      pistes: tiles.flatMap((t) => t.pistes).filter(once),
      lifts: tiles.flatMap((t) => t.lifts).filter(once),
      attribution: '© OpenStreetMap contributors (ODbL)',
    };
  });
};
