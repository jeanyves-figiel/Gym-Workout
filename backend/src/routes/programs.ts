import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AUTO_HIDE_REPORTS, assertClean, hasAcceptedGuidelines, REPORT_REASONS, reportContent, VISIBILITIES, visibleToOthersSql } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { Mailer } from '../mailer.ts';
import { DAY, throttleTake } from '../throttle.ts';
import { beforeSql, pageCursor } from './sync.ts';

/**
 * Shared plans (#666): a member-made programme (weeks, phases, signature workouts) that other members browse in
 * Community → Plans and copy into their own programmes. Same moderation as posts and shared workouts (#61).
 */

const LEVELS = ['beginner', 'intermediate', 'advanced'] as const;
const PROGRAMS_PER_DAY = 20;

const text = (max: number) => z.string().trim().max(max);
const program = z.object({
  name: text(60).min(1),
  about: text(200).nullish(),
  level: z.enum(LEVELS),
  /** App-defined goal key for the card gradient and filters, e.g. "strength", "climbing", "hybrid". */
  goal: text(24).nullish(),
  weeks: z.number().int().min(1).max(52),
  sessionsPerWeek: z.number().int().min(1).max(14),
  /** The app's programme record (phases, split, method, signature workouts); opaque to the server. */
  programme: z.object({ name: text(100).min(1) }).catchall(z.unknown()),
});

interface Row {
  id: string;
  user_id: string;
  data: string;
  visibility: string;
  copies: number;
  hidden_at: string | null;
  created_at: string;
  updated_at: string;
  nickname: string | null;
  avatar_id: string | null;
  level: number | null;
}

const SELECT = `SELECT p.*, cp.nickname, cp.avatar_id, cp.level FROM community_programs p LEFT JOIN community_profiles cp ON cp.user_id = p.user_id`;
const VISIBLE = `cp.user_id IS NOT NULL AND ${visibleToOthersSql('p.user_id', 'p.visibility', 'p.hidden_at')}`;

export const programExport = (db: DB, userId: string) =>
  (db.prepare('SELECT id, data, visibility, copies, created_at, updated_at FROM community_programs WHERE user_id = ? ORDER BY created_at').all(userId) as {
    data: string;
  }[]).map((r) => ({ ...r, data: JSON.parse(r.data) as unknown }));

export const programRoutes = (r: FastifyInstance, db: DB, now: () => Date, mailer: Mailer, moderationEmail?: string) => {
  const requireProfile = (userId: string) => {
    if (!hasAcceptedGuidelines(db, userId)) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
  };

  const toProgram = (p: Row, viewer: string) => ({
    id: p.id,
    ...(JSON.parse(p.data) as object),
    author: { userId: p.user_id, nickname: p.nickname ?? 'member', avatarUrl: p.avatar_id ? `/v1/community/avatars/${p.avatar_id}` : null, level: p.level ?? null },
    mine: p.user_id === viewer,
    visibility: p.visibility,
    copies: p.copies,
    copiedByMe: !!db.prepare('SELECT 1 FROM community_program_copies WHERE program_id = ? AND user_id = ?').get(p.id, viewer),
    hidden: !!p.hidden_at,
    createdAt: p.created_at,
    updatedAt: p.updated_at,
  });

  const visible = (id: string, viewer: string) => {
    const row = db.prepare(`${SELECT} WHERE p.id = ? AND (p.user_id = ? OR (${VISIBLE}))`).get(id.toLowerCase(), viewer, viewer, viewer) as Row | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Plan not found.');
    return row;
  };

  /** Members' plans newest first (`?mine=1`: your own, private included); `q` matches name, `level` filters. */
  r.get('/community/programs', async (req) => {
    const q = z
      .object({
        ...pageCursor,
        limit: z.coerce.number().int().min(1).max(50).default(30),
        q: z.string().trim().max(60).optional(),
        level: z.enum(LEVELS).optional(),
        mine: z.enum(['0', '1']).optional(),
      })
      .parse(req.query);
    const viewer = req.userId!;
    requireProfile(viewer);
    const like = q.q ? `%${q.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : '%';
    const page = beforeSql('p.updated_at', 'p.id', q);
    const who = q.mine === '1' ? 'p.user_id = ?' : `p.user_id != ? AND ${VISIBLE}`;
    const whoArgs = q.mine === '1' ? [viewer] : [viewer, viewer, viewer];
    const rows = db
      .prepare(
        `${SELECT} WHERE ${who} AND ${page.sql} AND json_extract(p.data, '$.name') LIKE ? ESCAPE '\\'
         AND (? IS NULL OR json_extract(p.data, '$.level') = ?) ORDER BY p.updated_at DESC, p.id DESC LIMIT ?`,
      )
      .all(...whoArgs, ...page.args, like, q.level ?? null, q.level ?? null, q.limit) as unknown as Row[];
    const last = rows.length === q.limit ? rows.at(-1)! : undefined;
    return { programs: rows.map((p) => toProgram(p, viewer)), nextBefore: last?.updated_at ?? null, nextBeforeId: last?.id ?? null };
  });

  r.get('/community/programs/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    requireProfile(req.userId!);
    return { program: toProgram(visible(id, req.userId!), req.userId!) };
  });

  /** Create or update your plan (the app picks the id). */
  r.put('/community/programs/:id', async (req) => {
    const { id: raw } = z.object({ id: z.uuid() }).parse(req.params);
    const b = program.extend({ visibility: z.enum(VISIBILITIES).default('members') }).parse(req.body);
    const uid = req.userId!;
    requireProfile(uid);
    assertClean(b.name, b.about, b.goal, b.programme.name, ...['tagline', 'summary'].map((k) => (typeof b.programme[k] === 'string' ? (b.programme[k] as string) : null)));
    const id = raw.toLowerCase();
    const owner = db.prepare('SELECT user_id FROM community_programs WHERE id = ?').get(id) as { user_id: string } | undefined;
    if (owner && owner.user_id !== uid) throw new ApiError(409, 'conflict', 'Plan id already used.');
    const { visibility, ...data } = b;
    const json = JSON.stringify(data);
    if (json.length > 100_000) throw new ApiError(413, 'too_large', 'That plan is too large.');
    const ts = now().toISOString();
    if (owner) {
      db.prepare('UPDATE community_programs SET data = ?, visibility = ?, updated_at = ? WHERE id = ?').run(json, visibility, ts, id);
    } else {
      if (!throttleTake(db, `program:${uid}`, PROGRAMS_PER_DAY, DAY, now()))
        throw new ApiError(429, 'daily_limit', `That's ${PROGRAMS_PER_DAY} plans today. Share more tomorrow!`);
      db.prepare('INSERT INTO community_programs (id, user_id, data, visibility, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, uid, json, visibility, ts, ts);
    }
    return { program: toProgram(visible(id, uid), uid) };
  });

  r.delete('/community/programs/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM community_programs WHERE id = ? AND user_id = ?').run(id.toLowerCase(), req.userId!);
    return reply.status(204).send();
  });

  /** Counts a copy into the member's programmes (the app saves the copy itself), once per member and plan. */
  r.post('/community/programs/:id/copy', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const uid = req.userId!;
    requireProfile(uid);
    const row = visible(id, uid);
    if (row.user_id !== uid)
      tx(db, () => {
        const fresh = Number(db.prepare('INSERT OR IGNORE INTO community_program_copies (program_id, user_id, created_at) VALUES (?, ?, ?)').run(row.id, uid, now().toISOString()).changes);
        if (fresh) db.prepare('UPDATE community_programs SET copies = copies + 1 WHERE id = ?').run(row.id);
      });
    return { program: toProgram(visible(id, uid), uid) };
  });

  r.post('/community/programs/:id/report', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const b = z.object({ reason: z.enum(REPORT_REASONS), details: z.string().trim().max(500).nullish() }).parse(req.body);
    const reporter = req.userId!;
    requireProfile(reporter);
    const row = visible(id, reporter);
    const ts = now().toISOString();
    let hidden = false;
    tx(db, () => {
      const n = reportContent(db, { reporterId: reporter, targetType: 'program', targetId: row.id, targetUserId: row.user_id, reason: b.reason, details: b.details, at: ts });
      if (n >= AUTO_HIDE_REPORTS)
        hidden = Number(db.prepare('UPDATE community_programs SET hidden_at = ? WHERE id = ? AND hidden_at IS NULL').run(ts, row.id).changes) > 0;
    });
    if (moderationEmail)
      mailer
        .send({
          to: moderationEmail,
          subject: `Plan report: ${b.reason}${hidden ? ' (plan auto-hidden)' : ''}`,
          text: [`Reporter: ${reporter}`, `Member: ${row.user_id}`, `Plan: ${row.id}`, `Reason: ${b.reason}`, `Details: ${b.details ?? '-'}`, `At: ${ts}`].join('\n'),
        })
        .catch((e: unknown) => req.log.warn(`moderation mail failed: ${String(e)}`));
    return reply.status(202).send({ status: 'received', hidden });
  });
};
