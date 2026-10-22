import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { assertClean, isBlockedBetween, memberNotHiddenSql } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';

/**
 * Live group sessions (#626, designs B + C): gym buddies see each other's sets live and cheer from the Watch, and
 * a weekly challenge room keeps one WOD all week with a live leaderboard. No SharePlay: the app polls while it
 * trains. Members only; blocks apply both ways.
 */

/** A live row older than this is not live any more (the app sends one per set and at least every 2′). */
export const LIVE_TTL_MS = 10 * 60_000;
/** Cheers waiting longer than this are dropped; the Watch only shows fresh ones. */
const CHEER_TTL_MS = 10 * 60_000;
/** Buddies per member (invites and pairs). */
export const MAX_BUDDIES = 20;
/** Leaderboard rows returned (plus the member's own row). */
const BOARD = 20;

export const LIVE_CHEERS = ['fire', 'banana', 'beast'] as const;
const LIVE_STATES = ['set', 'rest', 'done'] as const;

/** ISO 8601 week of `d` in UTC, e.g. "2026-W43". The app keys the week's WOD on the same string. */
export const isoWeek = (d: Date) => {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const y = t.getUTCFullYear();
  const w = Math.ceil(((t.getTime() - Date.UTC(y, 0, 1)) / 86_400_000 + 1) / 7);
  return `${y}-W${String(w).padStart(2, '0')}`;
};

/** Weeks a score may be sent for: this one, plus the neighbours a member's own time zone can still be in. */
const openWeeks = (now: Date) => new Set([isoWeek(new Date(now.getTime() - 36 * 3_600_000)), isoWeek(now), isoWeek(new Date(now.getTime() + 14 * 3_600_000))]);

const week = z.string().regex(/^\d{4}-W\d{2}$/);
const userIdParam = z.object({ userId: z.string().min(1).max(64) });
const avatarUrl = (id: string | null) => (id ? `/v1/community/avatars/${id}` : null);

interface LiveRow {
  user_id: string;
  title: string;
  exercise: string;
  detail: string | null;
  state: (typeof LIVE_STATES)[number];
  challenge_week: string | null;
  updated_at: string;
}

/** Leaving the community ends pairs, the live row, cheers and scores. */
export const leaveLive = (db: DB, userId: string) => {
  db.prepare('DELETE FROM community_buddies WHERE user_id = ? OR buddy_id = ?').run(userId, userId);
  db.prepare('DELETE FROM community_live WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM community_live_cheers WHERE to_id = ? OR from_id = ?').run(userId, userId);
  db.prepare('DELETE FROM community_challenge_scores WHERE user_id = ?').run(userId);
};

/** A block ends the pair both ways. */
export const unpair = (db: DB, a: string, b: string) =>
  db.prepare('DELETE FROM community_buddies WHERE (user_id = ? AND buddy_id = ?) OR (user_id = ? AND buddy_id = ?)').run(a, b, b, a);

export const liveExport = (db: DB, userId: string) => ({
  buddies: db.prepare('SELECT buddy_id, created_at FROM community_buddies WHERE user_id = ?').all(userId),
  challengeScores: db.prepare('SELECT week, rounds, reps, updated_at FROM community_challenge_scores WHERE user_id = ? ORDER BY week').all(userId),
});

export const liveRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  const member = (userId: string) =>
    db.prepare('SELECT user_id, nickname, avatar_id, level FROM community_profiles WHERE user_id = ?').get(userId) as
      | { user_id: string; nickname: string; avatar_id: string | null; level: number | null }
      | undefined;
  const requireMember = (userId: string) => {
    if (!member(userId)) throw new ApiError(403, 'community_profile_required', 'Join the community first.');
  };
  const paired = (a: string, b: string) =>
    (db.prepare('SELECT COUNT(*) AS n FROM community_buddies WHERE (user_id = ? AND buddy_id = ?) OR (user_id = ? AND buddy_id = ?)').get(a, b, b, a) as { n: number }).n === 2;
  const fresh = (row: { updated_at: string } | undefined) => !!row && now().getTime() - Date.parse(row.updated_at) < LIVE_TTL_MS;
  const liveOf = (userId: string) => {
    const row = db.prepare('SELECT * FROM community_live WHERE user_id = ?').get(userId) as LiveRow | undefined;
    return fresh(row) ? { title: row!.title, exercise: row!.exercise, detail: row!.detail, state: row!.state, updatedAt: row!.updated_at } : null;
  };

  // ───────────── B: gym buddies

  r.get('/community/buddies', async (req) => {
    const me = req.userId!;
    requireMember(me);
    const rows = db
      .prepare(
        `SELECT cp.user_id, cp.nickname, cp.avatar_id, cp.level,
           EXISTS (SELECT 1 FROM community_buddies x WHERE x.user_id = ? AND x.buddy_id = cp.user_id) AS mine,
           EXISTS (SELECT 1 FROM community_buddies x WHERE x.user_id = cp.user_id AND x.buddy_id = ?) AS theirs
         FROM community_profiles cp
         WHERE cp.user_id IN (SELECT buddy_id FROM community_buddies WHERE user_id = ? UNION SELECT user_id FROM community_buddies WHERE buddy_id = ?)
           AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = cp.user_id) OR (b.blocker_id = cp.user_id AND b.blocked_id = ?))
         ORDER BY cp.nickname`,
      )
      .all(me, me, me, me, me, me) as { user_id: string; nickname: string; avatar_id: string | null; level: number | null; mine: number; theirs: number }[];
    return {
      buddies: rows.map((b) => {
        const status = b.mine && b.theirs ? 'paired' : b.mine ? 'invited' : 'invites_you';
        return {
          userId: b.user_id,
          nickname: b.nickname,
          avatarUrl: avatarUrl(b.avatar_id),
          level: b.level ?? null,
          status,
          live: status === 'paired' ? liveOf(b.user_id) : null,
        };
      }),
    };
  });

  /** Invite, or accept an invite: paired once both sides put. */
  r.put('/community/buddies/:userId', async (req) => {
    const { userId } = userIdParam.parse(req.params);
    const me = req.userId!;
    requireMember(me);
    if (userId === me) throw new ApiError(400, 'own_content', 'You cannot buddy yourself.');
    if (!member(userId) || isBlockedBetween(db, me, userId)) throw new ApiError(404, 'not_found', 'Member not found.');
    const count = (db.prepare('SELECT COUNT(*) AS n FROM community_buddies WHERE user_id = ?').get(me) as { n: number }).n;
    const exists = !!db.prepare('SELECT 1 FROM community_buddies WHERE user_id = ? AND buddy_id = ?').get(me, userId);
    if (!exists && count >= MAX_BUDDIES) throw new ApiError(400, 'too_many_buddies', `Up to ${MAX_BUDDIES} gym buddies.`);
    db.prepare('INSERT OR IGNORE INTO community_buddies (user_id, buddy_id, created_at) VALUES (?, ?, ?)').run(me, userId, now().toISOString());
    return { status: paired(me, userId) ? 'paired' : 'invited' };
  });

  /** Unpair, cancel an invite or decline one. */
  r.delete('/community/buddies/:userId', async (req, reply) => {
    const { userId } = userIdParam.parse(req.params);
    unpair(db, req.userId!, userId);
    return reply.status(204).send();
  });

  r.post('/community/buddies/:userId/cheers', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { userId } = userIdParam.parse(req.params);
    const { kind } = z.object({ kind: z.enum(LIVE_CHEERS) }).parse(req.body);
    const me = req.userId!;
    if (!paired(me, userId) || isBlockedBetween(db, me, userId)) throw new ApiError(404, 'not_found', 'Not your gym buddy.');
    const at = now();
    tx(db, () => {
      db.prepare('DELETE FROM community_live_cheers WHERE to_id = ? AND created_at < ?').run(userId, new Date(at.getTime() - CHEER_TTL_MS).toISOString());
      db.prepare('INSERT INTO community_live_cheers (to_id, from_id, kind, created_at) VALUES (?, ?, ?, ?)').run(userId, me, kind, at.toISOString());
    });
    return reply.status(204).send();
  });

  // ───────────── live state (one row per member, replaced per set)

  r.put('/community/live', async (req, reply) => {
    const b = z
      .object({
        title: z.string().trim().min(1).max(60),
        exercise: z.string().trim().min(1).max(60),
        detail: z.string().trim().max(40).nullish(),
        state: z.enum(LIVE_STATES),
        challengeWeek: week.nullish(),
      })
      .parse(req.body);
    const me = req.userId!;
    requireMember(me);
    assertClean(b.title, b.exercise, b.detail);
    db.prepare(
      `INSERT INTO community_live (user_id, title, exercise, detail, state, challenge_week, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET title = excluded.title, exercise = excluded.exercise, detail = excluded.detail,
         state = excluded.state, challenge_week = excluded.challenge_week, updated_at = excluded.updated_at`,
    ).run(me, b.title, b.exercise, b.detail ?? null, b.state, b.challengeWeek ?? null, now().toISOString());
    return reply.status(204).send();
  });

  r.delete('/community/live', async (req, reply) => {
    db.prepare('DELETE FROM community_live WHERE user_id = ?').run(req.userId!);
    return reply.status(204).send();
  });

  /** Cheers from paired buddies after `after` (the last id seen), fresh ones only. */
  r.get('/community/live/cheers', async (req) => {
    const { after } = z.object({ after: z.coerce.number().int().min(0).default(0) }).parse(req.query);
    const me = req.userId!;
    const since = new Date(now().getTime() - CHEER_TTL_MS).toISOString();
    const rows = db
      .prepare(
        `SELECT c.id, c.from_id, c.kind, c.created_at, cp.nickname FROM community_live_cheers c
         JOIN community_profiles cp ON cp.user_id = c.from_id
         WHERE c.to_id = ? AND c.id > ? AND c.created_at >= ?
           AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = c.from_id) OR (b.blocker_id = c.from_id AND b.blocked_id = ?))
         ORDER BY c.id LIMIT 50`,
      )
      .all(me, after, since, me, me) as { id: number; from_id: string; kind: string; created_at: string; nickname: string }[];
    return {
      cheers: rows.map((c) => ({ id: c.id, from: { userId: c.from_id, nickname: c.nickname }, kind: c.kind, at: c.created_at })),
      last: rows.at(-1)?.id ?? after,
    };
  });

  // ───────────── C: weekly challenge room

  r.get('/community/challenge', async (req) => {
    const q = z.object({ week: week.optional() }).parse(req.query);
    const me = req.userId!;
    requireMember(me);
    const wk = q.week ?? isoWeek(now());
    const visible = `NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = s.user_id) OR (b.blocker_id = s.user_id AND b.blocked_id = ?))
      AND (s.user_id = ? OR ${memberNotHiddenSql('s.user_id')})`;
    const select = `SELECT s.user_id, s.rounds, s.reps, s.score, cp.nickname, cp.avatar_id, cp.level,
        (SELECT COUNT(*) FROM community_challenge_scores o WHERE o.week = s.week AND o.score > s.score) + 1 AS rank,
        l.updated_at AS live_at, l.challenge_week
      FROM community_challenge_scores s JOIN community_profiles cp ON cp.user_id = s.user_id
      LEFT JOIN community_live l ON l.user_id = s.user_id`;
    type Row = { user_id: string; rounds: number; reps: number; score: number; nickname: string; avatar_id: string | null; level: number | null; rank: number; live_at: string | null; challenge_week: string | null };
    const top = db.prepare(`${select} WHERE s.week = ? AND ${visible} ORDER BY s.score DESC, s.updated_at LIMIT ?`).all(wk, me, me, me, BOARD) as Row[];
    const mine = db.prepare(`${select} WHERE s.week = ? AND s.user_id = ?`).get(wk, me) as Row | undefined;
    const entry = (x: Row) => ({
      rank: x.rank,
      userId: x.user_id,
      nickname: x.nickname,
      avatarUrl: avatarUrl(x.avatar_id),
      level: x.level ?? null,
      rounds: x.rounds,
      reps: x.reps,
      live: x.challenge_week === wk && fresh(x.live_at ? { updated_at: x.live_at } : undefined),
      me: x.user_id === me,
    });
    const joined = (db.prepare('SELECT COUNT(*) AS n FROM community_challenge_scores WHERE week = ?').get(wk) as { n: number }).n;
    const since = new Date(now().getTime() - LIVE_TTL_MS).toISOString();
    const training = (db.prepare("SELECT COUNT(*) AS n FROM community_live WHERE challenge_week = ? AND updated_at >= ? AND state != 'done'").get(wk, since) as { n: number }).n;
    return { week: wk, joined, training, leaderboard: top.map(entry), me: mine ? entry(mine) : null };
  });

  /** Rounds + reps of the week's AMRAP; the best one stays. */
  r.put('/community/challenge/score', async (req) => {
    const b = z.object({ week, rounds: z.number().int().min(0).max(200), reps: z.number().int().min(0).max(999) }).parse(req.body);
    const me = req.userId!;
    requireMember(me);
    if (!openWeeks(now()).has(b.week)) throw new ApiError(400, 'week_closed', 'That challenge week is over.');
    const score = b.rounds * 1000 + b.reps;
    const ts = now().toISOString();
    db.prepare(
      `INSERT INTO community_challenge_scores (week, user_id, rounds, reps, score, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(week, user_id) DO UPDATE SET rounds = excluded.rounds, reps = excluded.reps, score = excluded.score, updated_at = excluded.updated_at
       WHERE excluded.score > community_challenge_scores.score`,
    ).run(b.week, me, b.rounds, b.reps, score, ts);
    const row = db.prepare('SELECT rounds, reps, score FROM community_challenge_scores WHERE week = ? AND user_id = ?').get(b.week, me) as { rounds: number; reps: number; score: number };
    const rank = (db.prepare('SELECT COUNT(*) AS n FROM community_challenge_scores WHERE week = ? AND score > ?').get(b.week, row.score) as { n: number }).n + 1;
    return { week: b.week, rounds: row.rounds, reps: row.reps, rank, best: row.score === score };
  });
};
