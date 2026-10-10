import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { assertClean, hasAcceptedGuidelines, VISIBILITIES } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';

/** User-built workouts (opaque app-defined records, like completed workouts). */
const customWorkout = z
  .object({
    id: z.uuid(),
    name: z.string().trim().min(1).max(100),
    items: z.array(z.object({ exerciseId: z.string().min(1).max(64) }).catchall(z.unknown())).max(100),
    /** Workout library (#62): who else can see it; absent = private. */
    visibility: z.enum(VISIBILITIES).optional(),
  })
  .catchall(z.unknown());

interface Row {
  data: string;
  updated_at: string;
  visibility: string;
  hidden_at: string | null;
  saves: number;
}

/** Stored JSON plus server-owned sharing state (the column is authoritative for visibility). */
const toWorkout = (r: Row) => ({
  ...(JSON.parse(r.data) as object),
  visibility: r.visibility,
  hidden: !!r.hidden_at,
  saves: r.saves,
  updatedAt: r.updated_at,
});

export const listCustomWorkouts = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db
          .prepare('SELECT data, updated_at, visibility, hidden_at, saves FROM custom_workouts WHERE user_id = ? AND updated_at > ? ORDER BY updated_at')
          .all(userId, since)
      : db.prepare('SELECT data, updated_at, visibility, hidden_at, saves FROM custom_workouts WHERE user_id = ? ORDER BY updated_at').all(userId)) as unknown as Row[]
  ).map(toWorkout);

export const customWorkoutRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/custom-workouts', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { workouts: listCustomWorkouts(db, req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/custom-workouts', async (req) => {
    const b = z.object({ workouts: z.array(customWorkout).max(100) }).parse(req.body);
    const userId = req.userId!;
    const shared = b.workouts.filter((w) => (w.visibility ?? 'private') !== 'private');
    if (shared.length) {
      // Same UGC rules as community posts (#61): guidelines accepted, objectionable names refused.
      if (!hasAcceptedGuidelines(db, userId)) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
      assertClean(...shared.map((w) => w.name));
    }
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO custom_workouts (id, user_id, data, updated_at, visibility, shared_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at, visibility = excluded.visibility,
         shared_at = CASE WHEN excluded.visibility = 'private' THEN NULL ELSE COALESCE(custom_workouts.shared_at, excluded.shared_at) END
       WHERE custom_workouts.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const w of b.workouts) {
        const visibility = w.visibility ?? 'private';
        const json = JSON.stringify({ ...w, visibility });
        if (json.length > 100_000) throw Object.assign(new Error('Workout too large'), { statusCode: 413 });
        up.run(w.id, userId, json, ts, visibility, visibility === 'private' ? null : ts);
      }
    });
    return { saved: b.workouts.length, serverTime: ts };
  });

  r.delete('/me/custom-workouts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM custom_workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });
};
