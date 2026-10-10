import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AUTO_HIDE_REPORTS, hasAcceptedGuidelines, REPORT_REASONS, reportContent, visibleToOthersSql } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { Mailer } from '../mailer.ts';

/**
 * Workout library (#62): custom workouts other members shared (visibility members/public), with the
 * community's moderation (#61): blocks either way hide them, reports auto-hide after AUTO_HIDE_REPORTS.
 */

interface SharedRow {
  id: string;
  user_id: string;
  data: string;
  visibility: string;
  shared_at: string;
  saves: number;
  nickname: string | null;
  avatar_id: string | null;
}

const SELECT_SHARED = `SELECT w.id, w.user_id, w.data, w.visibility, w.shared_at, w.saves, cp.nickname, cp.avatar_id
  FROM custom_workouts w LEFT JOIN community_profiles cp ON cp.user_id = w.user_id`;
const VISIBLE = visibleToOthersSql('w.user_id', 'w.visibility', 'w.hidden_at');

const toShared = (r: SharedRow) => {
  const d = JSON.parse(r.data) as { name?: string; items?: unknown[]; createdAt?: string };
  return {
    id: r.id,
    name: d.name ?? 'Workout',
    items: d.items ?? [],
    createdAt: d.createdAt ?? r.shared_at,
    visibility: r.visibility,
    sharedAt: r.shared_at,
    saves: r.saves,
    author: { userId: r.user_id, nickname: r.nickname ?? 'member', avatarUrl: r.avatar_id ? `/v1/community/avatars/${r.avatar_id}` : null },
  };
};

export const libraryRoutes = (r: FastifyInstance, db: DB, now: () => Date, mailer: Mailer, moderationEmail?: string) => {
  const requireProfile = (userId: string) => {
    if (!hasAcceptedGuidelines(db, userId)) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
  };

  const visibleWorkout = (id: string, viewer: string) => {
    const row = db.prepare(`${SELECT_SHARED} WHERE lower(w.id) = lower(?) AND w.user_id != ? AND ${VISIBLE}`).get(id, viewer, viewer, viewer) as
      | SharedRow
      | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Workout not found.');
    return row;
  };

  /** Newest shared first; `q` matches the name. */
  r.get('/library/shared', async (req) => {
    const q = z
      .object({
        before: z.iso.datetime({ offset: true }).optional(),
        limit: z.coerce.number().int().min(1).max(50).default(30),
        q: z.string().trim().max(60).optional(),
      })
      .parse(req.query);
    const viewer = req.userId!;
    requireProfile(viewer);
    const like = q.q ? `%${q.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : '%';
    const rows = db
      .prepare(
        `${SELECT_SHARED} WHERE w.user_id != ? AND ${VISIBLE} AND w.shared_at < ?
         AND json_extract(w.data, '$.name') LIKE ? ESCAPE '\\' ORDER BY w.shared_at DESC LIMIT ?`,
      )
      .all(viewer, viewer, viewer, q.before ?? '9999', like, q.limit) as unknown as SharedRow[];
    return { workouts: rows.map(toShared), nextBefore: rows.length === q.limit ? rows.at(-1)!.shared_at : null };
  });

  r.get('/library/shared/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    requireProfile(req.userId!);
    return { workout: toShared(visibleWorkout(id, req.userId!)) };
  });

  /** Counts a copy into "My workouts" (the app creates the copy itself). */
  r.post('/library/shared/:id/save', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    requireProfile(req.userId!);
    const row = visibleWorkout(id, req.userId!);
    db.prepare('UPDATE custom_workouts SET saves = saves + 1 WHERE id = ?').run(row.id);
    return { workout: toShared({ ...row, saves: row.saves + 1 }) };
  });

  r.post('/library/shared/:id/report', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const b = z.object({ reason: z.enum(REPORT_REASONS), details: z.string().trim().max(500).nullish() }).parse(req.body);
    const reporter = req.userId!;
    requireProfile(reporter);
    const row = visibleWorkout(id, reporter);
    const ts = now().toISOString();
    let hidden = false;
    tx(db, () => {
      const n = reportContent(db, { reporterId: reporter, targetType: 'workout', targetId: row.id, targetUserId: row.user_id, reason: b.reason, details: b.details, at: ts });
      if (n >= AUTO_HIDE_REPORTS)
        hidden = Number(db.prepare('UPDATE custom_workouts SET hidden_at = ? WHERE id = ? AND hidden_at IS NULL').run(ts, row.id).changes) > 0;
    });
    if (moderationEmail)
      mailer
        .send({
          to: moderationEmail,
          subject: `Workout report: ${b.reason}${hidden ? ' (workout auto-hidden)' : ''}`,
          text: [`Reporter: ${reporter}`, `Member: ${row.user_id}`, `Workout: ${row.id}`, `Reason: ${b.reason}`, `Details: ${b.details ?? '-'}`, `At: ${ts}`].join('\n'),
        })
        .catch((e: unknown) => req.log.warn(`moderation mail failed: ${String(e)}`));
    return reply.status(202).send({ status: 'received', hidden });
  });
};
