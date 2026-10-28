import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type HoldCategory, type Moderator, noModerator } from '../community/aiModeration.ts';
import { assertClean, hasAcceptedGuidelines, VISIBILITIES } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts } from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';
import { ApiError } from '../errors.ts';

/** User-built workouts (opaque app-defined records, like completed workouts). */
const customWorkout = z
  .object({
    id: syncId,
    baseUpdatedAt,
    name: z.string().trim().min(1).max(100),
    items: z.array(z.object({ exerciseId: z.string().min(1).max(128) }).catchall(z.unknown())).max(100),
    /** Workout library (#62): who else can see it; absent = private. */
    visibility: z.enum(VISIBILITIES).optional(),
  })
  .catchall(z.unknown());

interface Row {
  data: string;
  updated_at: string;
  visibility: string;
  hidden_at: string | null;
  in_review: number;
  saves: number;
}

/** Shared workouts' saves counted from `library_saves` (#714), so a deleted saver no longer counts. */
const SAVES = '(SELECT COUNT(*) FROM library_saves s WHERE s.workout_id = custom_workouts.id) AS saves';
/** Shared name held by AI moderation (#871). */
const IN_REVIEW = `EXISTS (SELECT 1 FROM moderation_holds h WHERE h.target_type = 'workout' AND h.target_id = custom_workouts.id AND h.resolved_at IS NULL) AS in_review`;

/** Stored JSON plus server-owned sharing state (the column is authoritative for visibility). */
const toWorkout = (r: Row) => ({
  ...(JSON.parse(r.data) as object),
  visibility: r.visibility,
  hidden: !!r.hidden_at,
  inReview: !!r.in_review,
  saves: r.saves,
  updatedAt: r.updated_at,
});

export const customWorkoutTable: SyncTable<Row> = {
  table: 'custom_workouts',
  cols: `data, updated_at, visibility, hidden_at, ${IN_REVIEW}, ${SAVES}`,
  timeCol: 'updated_at',
  map: toWorkout,
};

/**
 * AI check (#871) of shared workout names that are new to the library (new, renamed or just shared). One call for the
 * batch; when it flags, each name alone, so only the offending workouts are held. Ids to hold, with their category.
 */
const flaggedNames = async (db: DB, mod: Moderator, userId: string, shared: { id: string; name: string }[]) => {
  const fresh = shared.filter((w) => {
    const row = db.prepare('SELECT data, visibility FROM custom_workouts WHERE id = ? AND user_id = ?').get(w.id, userId) as { data: string; visibility: string } | undefined;
    return !row || row.visibility === 'private' || (JSON.parse(row.data) as { name?: string }).name !== w.name;
  });
  const out = new Map<string, HoldCategory>();
  const all = await mod.check({ texts: fresh.map((w) => w.name) });
  if (!all) return out;
  if (fresh.length === 1) return out.set(fresh[0]!.id, all);
  for (const w of fresh) {
    const c = await mod.check({ texts: [w.name] });
    if (c) out.set(w.id, c);
  }
  return out;
};

export const customWorkoutRoutes = (r: FastifyInstance, db: DB, now: () => Date, mod: Moderator = noModerator()) => {
  r.get('/me/custom-workouts', async (req, reply) =>
    sendPull(reply, db, customWorkoutTable, { key: 'workouts', kind: 'custom-workouts', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/custom-workouts', async (req) => {
    const b = z.object({ workouts: z.array(customWorkout).max(100) }).parse(req.body);
    const userId = req.userId!;
    const shared = b.workouts.filter((w) => (w.visibility ?? 'private') !== 'private');
    if (shared.length) {
      // Same UGC rules as community posts (#61): guidelines accepted, objectionable names refused.
      if (!hasAcceptedGuidelines(db, userId)) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
      assertClean(...shared.map((w) => w.name));
    }
    const held = shared.length ? await flaggedNames(db, mod, userId, shared) : new Map<string, HoldCategory>();
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO custom_workouts (id, user_id, data, updated_at, visibility, shared_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at, visibility = excluded.visibility,
         shared_at = CASE WHEN excluded.visibility = 'private' THEN NULL ELSE COALESCE(custom_workouts.shared_at, excluded.shared_at) END
       WHERE custom_workouts.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'custom_workouts', userId, b.workouts, (row: Row & { id: string }) =>
        toWorkout({ ...row, saves: (db.prepare(`SELECT ${SAVES} FROM custom_workouts WHERE id = ?`).get(row.id) as { saves: number }).saves }),
      );
      const workouts = reviveUploaded(db, userId, 'custom-workouts', fresh);
      const jsons = workouts.map((w) => JSON.stringify({ ...w, visibility: w.visibility ?? 'private' }));
      for (const j of jsons) assertItemSize(j, 64_000, 'Workout');
      assertRowQuota(db, 'custom_workouts', userId, workouts.map((w) => w.id));
      assertByteQuota(db, 'custom_workouts', userId, workouts.map((w, i) => ({ id: w.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      workouts.forEach((w, i) => {
        const visibility = w.visibility ?? 'private';
        count += Number(up.run(w.id, userId, jsons[i]!, ts, visibility, visibility === 'private' ? null : ts).changes);
      });
      // Held names stay out of the library until reviewed; the owner keeps the workout as is.
      for (const [id, category] of held)
        if (Number(db.prepare('UPDATE custom_workouts SET hidden_at = COALESCE(hidden_at, ?) WHERE id = ? AND user_id = ?').run(ts, id, userId).changes))
          mod.hold({ userId, type: 'workout', id, category, texts: [shared.find((w) => w.id === id)?.name] });
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/custom-workouts/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM custom_workouts WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'custom-workouts', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};
