import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { DB } from '../db.ts';
import { sameGym } from './community.ts';

/** Gym memory (#162): see `ensureGymSchema`. Only counts are shared, never who reported. */
interface ReportRow {
  user_id: string;
  gym_id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
  equipment: string;
  unsure: string;
  updated_at: string;
}

const item = z.string().regex(/^[a-z0-9-]{1,32}$/);
const gymRef = z.object({
  id: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(120),
  latitude: z.number().min(-90).max(90).nullish(),
  longitude: z.number().min(-180).max(180).nullish(),
});

/** Words that don't make two gyms the same chain on their own. */
const GENERIC = new Set(['the', 'gym', 'fitness', 'fit', 'sport', 'sports', 'club', 'center', 'centre', 'studio', 'health', 'training', 'crossfit']);

const words = (name: string) => name.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, ' ').split(/\s+/).filter(Boolean);

/**
 * Chain name shared by two gyms at different places: their common leading words ("Holmes Place Europaallee" and
 * "Holmes Place Bern" → "holmes place"), when it is more than generic words.
 */
export const chainOf = (a: string, b: string): string | null => {
  const wa = words(a);
  const wb = words(b);
  const common: string[] = [];
  for (let i = 0; i < Math.min(wa.length, wb.length) && wa[i] === wb[i]; i++) common.push(wa[i]!);
  if (common.length === Math.max(wa.length, wb.length)) return null; // same name: a place match, not a chain
  const key = common.join(' ');
  return key.length >= 4 && common.some((w) => !GENERIC.has(w)) ? key : null;
};

/** Members' answers combined: how many reported, yes-votes per item, and the items at least half of them have. */
export const tally = (rows: ReportRow[]) => {
  const votes: Record<string, number> = {};
  for (const r of rows) {
    const unsure = new Set(JSON.parse(r.unsure) as string[]);
    for (const e of JSON.parse(r.equipment) as string[]) if (!unsure.has(e)) votes[e] = (votes[e] ?? 0) + 1;
  }
  const members = rows.length;
  const equipment = Object.keys(votes).filter((e) => votes[e]! * 2 >= members).sort();
  return { members, votes, equipment };
};

export const gymExport = (db: DB, userId: string) =>
  (db.prepare('SELECT gym_id, name, equipment, unsure, updated_at FROM gym_reports WHERE user_id = ? ORDER BY updated_at').all(userId) as unknown as ReportRow[]).map(
    (r) => ({ gymId: r.gym_id, name: r.name, equipment: JSON.parse(r.equipment), unsure: JSON.parse(r.unsure), updatedAt: r.updated_at }),
  );

export const gymRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  /** Your list for a gym; replaces your earlier one. */
  r.put('/gyms/reports', async (req) => {
    const b = z
      .object({ gym: gymRef, equipment: z.array(item).max(80), unsure: z.array(item).max(80).optional() })
      .parse(req.body);
    const ts = now().toISOString();
    db.prepare(
      `INSERT INTO gym_reports (user_id, gym_id, name, latitude, longitude, equipment, unsure, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, gym_id) DO UPDATE SET name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude,
         equipment = excluded.equipment, unsure = excluded.unsure, updated_at = excluded.updated_at`,
    ).run(req.userId!, b.gym.id, b.gym.name, b.gym.latitude ?? null, b.gym.longitude ?? null,
      JSON.stringify([...new Set(b.equipment)]), JSON.stringify([...new Set(b.unsure ?? [])]), ts);
    return { saved: true };
  });

  r.delete('/gyms/reports', async (req, reply) => {
    const q = z.object({ id: z.string().min(1).max(80) }).parse(req.query);
    db.prepare('DELETE FROM gym_reports WHERE user_id = ? AND gym_id = ?').run(req.userId!, q.id);
    return reply.status(204).send();
  });

  /**
   * What other members found at a gym: `place` from reports at the same place (same id, or same name within ~300 m),
   * `chain` from other branches of the same chain. Each is null when nobody reported. Your own report isn't counted.
   */
  r.get('/gyms/known', async (req) => {
    const q = z
      .object({
        id: z.string().min(1).max(80),
        name: z.string().trim().min(1).max(120),
        lat: z.coerce.number().min(-90).max(90).optional(),
        lng: z.coerce.number().min(-180).max(180).optional(),
      })
      .parse(req.query);
    const me = { id: q.id, name: q.name, latitude: q.lat ?? null, longitude: q.lng ?? null };
    const first = words(q.name)[0] ?? '';
    const rows = db
      .prepare('SELECT * FROM gym_reports WHERE user_id != ? AND (gym_id = ? OR lower(name) LIKE ?)')
      .all(req.userId!, q.id, `${first}%`) as unknown as ReportRow[];
    const at = (r: ReportRow) => ({ id: r.gym_id, name: r.name, latitude: r.latitude, longitude: r.longitude });
    const place = rows.filter((r) => sameGym(at(r), me));
    const chainRows = rows.filter((r) => !place.includes(r) && chainOf(r.name, q.name) != null);
    // One vote per member: a member with several branches counts with the latest.
    const latest = new Map<string, ReportRow>();
    for (const r of chainRows) if ((latest.get(r.user_id)?.updated_at ?? '') < r.updated_at) latest.set(r.user_id, r);
    const chain = [...latest.values()];
    return {
      place: place.length ? tally(place) : null,
      chain: chain.length ? { ...tally(chain), name: chainOf(chain[0]!.name, q.name), gyms: new Set(chain.map((r) => r.gym_id)).size } : null,
    };
  });
};
