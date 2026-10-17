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

/** Gym Map (#406): your floor plans and "Taken?" taps, for the data export. */
export const gymMapExport = (db: DB, userId: string) => ({
  maps: (db.prepare('SELECT gym_id, name, layout, updated_at FROM gym_maps WHERE user_id = ? ORDER BY updated_at').all(userId) as unknown as MapRow[]).map(
    (r) => ({ gymId: r.gym_id, name: r.name, layout: JSON.parse(r.layout), updatedAt: r.updated_at }),
  ),
  busy: db.prepare('SELECT gym_id AS gymId, zone, at FROM gym_busy WHERE user_id = ? ORDER BY at').all(userId),
});

interface MapRow {
  user_id: string;
  gym_id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
  layout: string;
  updated_at: string;
}

const unit = z.number().min(0).max(1);
/** A member's floor plan (`GymLayout` in the app). */
export const layoutSchema = z.object({
  zones: z
    .array(
      z.object({
        id: z.string().min(1).max(64),
        name: z.string().trim().min(1).max(40),
        color: z.number().int().min(0).max(63),
        items: z.array(item).max(120),
        rect: z.object({ x: unit, y: unit, w: unit, h: unit }).nullish(),
      }),
    )
    .min(1)
    .max(12),
  door: z.object({ x: unit, y: unit }).nullish(),
  sizeM: z.object({ x: z.number().min(1).max(500), y: z.number().min(1).max(500) }).nullish(),
});
type Layout = z.infer<typeof layoutSchema>;

const zoneKey = (name: string) => name.trim().toLowerCase();

/** Share of the items both plans place where they sit in the same-named zone (1 = same everywhere). */
export const agreement = (a: Layout, b: Layout) => {
  const where = (l: Layout) => new Map(l.zones.flatMap((z) => z.items.map((i) => [i, zoneKey(z.name)] as const)));
  const wa = where(a);
  const wb = where(b);
  const shared = [...wa.keys()].filter((i) => wb.has(i));
  return shared.length ? shared.filter((i) => wa.get(i) === wb.get(i)).length / shared.length : 0;
};

/**
 * The plan members at a gym agree with most: each plan's average agreement with the others (the medoid); the latest
 * wins a tie. `agreement` is null with only one plan.
 */
export const consensus = (rows: { layout: Layout; updatedAt: string }[]) => {
  if (rows.length === 0) return null;
  if (rows.length === 1) return { layout: rows[0]!.layout, members: 1, agreement: null };
  let best = { i: 0, score: -1 };
  rows.forEach((r, i) => {
    const others = rows.filter((_, j) => j !== i);
    const score = others.reduce((s, o) => s + agreement(r.layout, o.layout), 0) / others.length;
    if (score > best.score || (score === best.score && r.updatedAt > rows[best.i]!.updatedAt)) best = { i, score };
  });
  return { layout: rows[best.i]!.layout, members: rows.length, agreement: Math.round(best.score * 100) };
};

/** "Around now" for the live crowd. */
const LIVE_MIN = 20;
const BUSY_KEEP_DAYS = 56;

const placeQuery = z.object({
  id: z.string().min(1).max(80),
  name: z.string().trim().min(1).max(120),
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
});

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

  /** Your floor plan for a gym (#406); replaces your earlier one. Only plans with blocks drawn are shared. */
  r.put('/gyms/maps', async (req) => {
    const b = z.object({ gym: gymRef, layout: layoutSchema }).parse(req.body);
    db.prepare(
      `INSERT INTO gym_maps (user_id, gym_id, name, latitude, longitude, layout, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, gym_id) DO UPDATE SET name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude,
         layout = excluded.layout, updated_at = excluded.updated_at`,
    ).run(req.userId!, b.gym.id, b.gym.name, b.gym.latitude ?? null, b.gym.longitude ?? null, JSON.stringify(b.layout), now().toISOString());
    return { saved: true };
  });

  /** The plan other members at this place agree with most (yours not counted); `map` null when nobody mapped it. */
  r.get('/gyms/maps', async (req) => {
    const q = placeQuery.parse(req.query);
    const me = { id: q.id, name: q.name, latitude: q.lat ?? null, longitude: q.lng ?? null };
    const first = words(q.name)[0] ?? '';
    const rows = (db
      .prepare('SELECT * FROM gym_maps WHERE user_id != ? AND (gym_id = ? OR lower(name) LIKE ?)')
      .all(req.userId!, q.id, `${first}%`) as unknown as MapRow[])
      .filter((r) => sameGym({ id: r.gym_id, name: r.name, latitude: r.latitude, longitude: r.longitude }, me))
      .map((r) => ({ layout: JSON.parse(r.layout) as Layout, updatedAt: r.updated_at }))
      .filter((r) => r.layout.zones.some((z) => z.rect));
    return { map: consensus(rows) };
  });

  /** "Taken?" (#406): a zone was busy just now. One tap per member, gym and zone every 5 minutes. */
  r.post('/gyms/busy', async (req) => {
    const b = z.object({ gym: z.object({ id: gymRef.shape.id }), zone: z.string().trim().min(1).max(40) }).parse(req.body);
    const t = now();
    const zone = zoneKey(b.zone);
    const recent = db
      .prepare('SELECT 1 FROM gym_busy WHERE user_id = ? AND gym_id = ? AND zone = ? AND at > ?')
      .get(req.userId!, b.gym.id, zone, new Date(t.getTime() - 5 * 60_000).toISOString());
    if (!recent) db.prepare('INSERT INTO gym_busy (user_id, gym_id, zone, at) VALUES (?, ?, ?, ?)').run(req.userId!, b.gym.id, zone, t.toISOString());
    db.prepare('DELETE FROM gym_busy WHERE at < ?').run(new Date(t.getTime() - BUSY_KEEP_DAYS * 86_400_000).toISOString());
    return { saved: true };
  });

  /**
   * Live crowd (#406): members who found each zone busy in the last 20 minutes, and per zone the rush hours on this
   * weekday (taps per local hour over 8 weeks, one per member and day). `tz`: the member's UTC offset in minutes.
   * Counts only, never who.
   */
  r.get('/gyms/crowd', async (req) => {
    const q = z.object({ id: gymRef.shape.id, tz: z.coerce.number().int().min(-840).max(840).default(0) }).parse(req.query);
    const t = now();
    const rows = db
      .prepare('SELECT user_id, zone, at FROM gym_busy WHERE gym_id = ? AND at > ?')
      .all(q.id, new Date(t.getTime() - BUSY_KEEP_DAYS * 86_400_000).toISOString()) as { user_id: string; zone: string; at: string }[];
    const live = new Map<string, Set<string>>();
    const since = new Date(t.getTime() - LIVE_MIN * 60_000).toISOString();
    const local = (iso: string) => new Date(new Date(iso).getTime() + q.tz * 60_000);
    const today = local(t.toISOString()).getUTCDay();
    const hours = new Map<string, Map<string, number>>(); // zone → "user|day|hour" → hour
    for (const r of rows) {
      if (r.at > since) live.set(r.zone, (live.get(r.zone) ?? new Set()).add(r.user_id));
      const d = local(r.at);
      if (d.getUTCDay() !== today) continue;
      const m = hours.get(r.zone) ?? new Map<string, number>();
      m.set(`${r.user_id}|${d.toISOString().slice(0, 10)}|${d.getUTCHours()}`, d.getUTCHours());
      hours.set(r.zone, m);
    }
    return {
      now: [...live].map(([zone, users]) => ({ zone, reports: users.size })).sort((a, b) => b.reports - a.reports),
      forecast: [...hours].map(([zone, m]) => {
        const h = Array<number>(24).fill(0);
        for (const hour of m.values()) h[hour]! += 1;
        return { zone, hours: h };
      }),
    };
  });

  /**
   * What other members found at a gym: `place` from reports at the same place (same id, or same name within ~300 m),
   * `chain` from other branches of the same chain. Each is null when nobody reported. Your own report isn't counted.
   */
  r.get('/gyms/known', async (req) => {
    const q = placeQuery.parse(req.query);
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
