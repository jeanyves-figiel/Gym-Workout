import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type Moderator, noModerator } from '../community/aiModeration.ts';
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
  saves: number;
}

/** Shared workouts' saves counted from `library_saves` (#714), so a deleted saver no longer counts. */
const SAVES = '(SELECT COUNT(*) FROM library_saves s WHERE s.workout_id = custom_workouts.id) AS saves';

/** Stored JSON plus server-owned sharing state (the column is authoritative for visibility). */
const toWorkout = (r: Row) => ({
  ...(JSON.parse(r.data) as object),
  visibility: r.visibility,
  hidden: !!r.hidden_at,
  saves: r.saves,
  updatedAt: r.updated_at,
});

export const customWorkoutTable: SyncTable<Row> = {
  table: 'custom_workouts',
  cols: `data, updated_at, visibility, hidden_at, ${SAVES}`,
  timeCol: 'updated_at',
  map: toWorkout,
};

/** Shared workout names new to the library (new, renamed or just shared): the ones the AI check (#871) still has to see. */
const freshNames = (db: DB, userId: string, shared: { id: string; name: string }[]) =>
  shared
    .filter((w) => {
      const row = db.prepare('SELECT data, visibility FROM custom_workouts WHERE id = ? AND user_id = ?').get(w.id, userId) as { data: string; visibility: string } | undefined;
      return !row || row.visibility === 'private' || (JSON.parse(row.data) as { name?: string }).name !== w.name;
    })
    .map((w) => w.name);

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
      await mod.assertAllowed({ userId, texts: freshNames(db, userId, shared) });
    }
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
