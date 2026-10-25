import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  addWeeks,
  CHALLENGE_DECK,
  CHALLENGE_MOVES,
  CHALLENGE_TIERS,
  type ChallengeTier,
  type ChallengeWod,
  challengeScore,
  checkSuggestion,
  deckWod,
  finalists,
  isMemberWeek,
  MAX_PENDING_SUGGESTIONS,
  type SuggestionRow,
  suggestionBody,
  suggestionWod,
  thursdayOf,
} from '../community/challenges.ts';
import { assertClean, isBlockedBetween, memberNotHiddenSql } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { PushService } from '../push/service.ts';
import { DAY, throttleTake } from '../throttle.ts';

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

/** Weeks in ISO year `y`: 53 when 28 December falls in week 53. */
export const weeksInYear = (y: number) => (isoWeek(new Date(Date.UTC(y, 11, 28))).endsWith('W53') ? 53 : 52);

/** `YYYY-Www` with a week that exists in that year (#714): W00, W54 or W53 of a 52-week year are refused. */
const week = z
  .string()
  .regex(/^\d{4}-W\d{2}$/)
  .refine((w) => {
    const n = Number(w.slice(6));
    return n >= 1 && n <= weeksInYear(Number(w.slice(0, 4)));
  }, 'No such ISO week');

/**
 * SQL predicate (#714): `alias`'s row counts for viewer `?`: their own, or another member's with no block either way
 * who isn't hidden by reports. Binds the viewer id three times. Ranks, `joined` and `training` use it too, so a
 * blocked or hidden member doesn't push the viewer down the board.
 */
const countsFor = (alias: string) =>
  `(${alias}.user_id = ? OR (NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = ${alias}.user_id)
     OR (b.blocker_id = ${alias}.user_id AND b.blocked_id = ?)) AND ${memberNotHiddenSql(`${alias}.user_id`)}))`;
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
  // #748: votes and suggestions that haven't run go too; a member week that ran keeps its WOD.
  db.prepare('DELETE FROM community_challenge_votes WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM community_challenge_suggestions WHERE user_id = ? AND week IS NULL').run(userId);
};

/** A block ends the pair both ways. */
export const unpair = (db: DB, a: string, b: string) =>
  db.prepare('DELETE FROM community_buddies WHERE (user_id = ? AND buddy_id = ?) OR (user_id = ? AND buddy_id = ?)').run(a, b, b, a);

export const liveExport = (db: DB, userId: string) => ({
  buddies: db.prepare('SELECT buddy_id, share_live, created_at FROM community_buddies WHERE user_id = ?').all(userId),
  challengeScores: db.prepare('SELECT week, rounds, reps, seconds, tier, updated_at FROM community_challenge_scores WHERE user_id = ? ORDER BY week').all(userId),
  challengeSuggestions: db
    .prepare('SELECT name, format, minutes, moves, status, week, created_at FROM community_challenge_suggestions WHERE user_id = ? ORDER BY created_at')
    .all(userId),
  challengeVotes: db.prepare('SELECT week, suggestion_id, created_at FROM community_challenge_votes WHERE user_id = ? ORDER BY week').all(userId),
});

export const liveRoutes = (r: FastifyInstance, db: DB, now: () => Date, push?: PushService) => {
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
  /** `userId`'s live set, for `viewer` unless `userId` keeps it from them (#675). */
  const liveOf = (userId: string, viewer: string) => {
    const share = db.prepare('SELECT share_live FROM community_buddies WHERE user_id = ? AND buddy_id = ?').get(userId, viewer) as { share_live: number } | undefined;
    if (share?.share_live === 0) return null;
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
           EXISTS (SELECT 1 FROM community_buddies x WHERE x.user_id = cp.user_id AND x.buddy_id = ?) AS theirs,
           COALESCE((SELECT x.share_live FROM community_buddies x WHERE x.user_id = ? AND x.buddy_id = cp.user_id), 1) AS share_live
         FROM community_profiles cp
         WHERE cp.user_id IN (SELECT buddy_id FROM community_buddies WHERE user_id = ? UNION SELECT user_id FROM community_buddies WHERE buddy_id = ?)
           AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = cp.user_id) OR (b.blocker_id = cp.user_id AND b.blocked_id = ?))
         ORDER BY cp.nickname`,
      )
      .all(me, me, me, me, me, me, me) as { user_id: string; nickname: string; avatar_id: string | null; level: number | null; mine: number; theirs: number; share_live: number }[];
    return {
      buddies: rows.map((b) => {
        const status = b.mine && b.theirs ? 'paired' : b.mine ? 'invited' : 'invites_you';
        return {
          userId: b.user_id,
          nickname: b.nickname,
          avatarUrl: avatarUrl(b.avatar_id),
          level: b.level ?? null,
          status,
          live: status === 'paired' ? liveOf(b.user_id, me) : null,
          shareLive: b.share_live !== 0,
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
    const added = Number(db.prepare('INSERT OR IGNORE INTO community_buddies (user_id, buddy_id, created_at) VALUES (?, ?, ?)').run(me, userId, now().toISOString()).changes) > 0;
    const status = paired(me, userId) ? 'paired' : 'invited';
    // Push (#626): the invite to them, or "paired" back to who invited. Once per new row, and once a day per pair (#712):
    // invite, cancel, invite again doesn't ring their phone each time. Taps open my page.
    if (added && push && throttleTake(db, `buddy-push:${me}:${userId}`, 1, DAY, now())) {
      const name = member(me)!.nickname;
      push.notifyLater(userId, 'buddy_invite', {
        title: status === 'paired' ? `${name} is your gym buddy 🤝` : 'Gym buddy invite 🤝',
        body: status === 'paired' ? 'You see each other\'s sets live and can cheer from your Watch.' : `${name} wants to train with you. Open to pair.`,
        data: { kind: 'buddy_invite', actorId: me, actorName: name },
        collapseId: `buddy-${me}`.slice(0, 64),
      });
    }
    return { status };
  });

  /** Who sees my live set (#675): keep it from one buddy, or share it again. */
  r.patch('/community/buddies/:userId', async (req) => {
    const { userId } = userIdParam.parse(req.params);
    const { shareLive } = z.object({ shareLive: z.boolean() }).parse(req.body);
    const me = req.userId!;
    const changed = Number(db.prepare('UPDATE community_buddies SET share_live = ? WHERE user_id = ? AND buddy_id = ?').run(shareLive ? 1 : 0, me, userId).changes);
    if (!changed) throw new ApiError(404, 'not_found', 'Not your gym buddy.');
    return { shareLive };
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

  // ───────────── C: weekly challenge room (#748: server deck, member weeks, suggestions)

  /** The week has started somewhere (members up to 14 h ahead of UTC). */
  const started = (wk: string) => wk <= isoWeek(new Date(now().getTime() + 14 * 3_600_000));
  type Pin = { wod: string | null; user_id: string | null; nickname: string | null };
  const pinOf = (wk: string) =>
    db
      .prepare(
        `SELECT w.wod, s.user_id, cp.nickname FROM community_challenge_weeks w
         LEFT JOIN community_challenge_suggestions s ON s.id = w.suggestion_id LEFT JOIN community_profiles cp ON cp.user_id = s.user_id
         WHERE w.week = ?`,
      )
      .get(wk) as Pin | undefined;
  /** A member week that started: the finalist with the most votes runs (oldest approval wins ties), pinned for the week. */
  const pick = (wk: string) =>
    tx(db, () => {
      if (pinOf(wk)) return;
      const votes = db.prepare('SELECT suggestion_id, COUNT(*) AS n FROM community_challenge_votes WHERE week = ? GROUP BY suggestion_id').all(wk) as { suggestion_id: string; n: number }[];
      const count = (id: string) => votes.find((v) => v.suggestion_id === id)?.n ?? 0;
      const winner = finalists(db).reduce<SuggestionRow | undefined>((best, f) => (!best || count(f.id) > count(best.id) ? f : best), undefined);
      db.prepare('INSERT INTO community_challenge_weeks (week, suggestion_id, wod, picked_at) VALUES (?, ?, ?, ?)').run(
        wk,
        winner?.id ?? null,
        winner ? JSON.stringify(suggestionWod(winner)) : null,
        now().toISOString(),
      );
      if (winner) db.prepare('UPDATE community_challenge_suggestions SET week = ? WHERE id = ?').run(wk, winner.id);
    });
  /** The WOD of week `wk`: the year's deck card, or on a member week the members' winner (deck when there's none). */
  const weekWod = (wk: string) => {
    const deck = deckWod(wk);
    const plain = { ...deck.wod, by: null as { userId: string; nickname: string } | null, memberWeek: false, card: deck.card as number | null, deckSize: CHALLENGE_DECK.length };
    if (!isMemberWeek(wk, isoWeek)) return plain;
    if (!pinOf(wk) && started(wk) && openWeeks(now()).has(wk)) pick(wk);
    const pin = pinOf(wk);
    if (!pin?.wod) return { ...plain, memberWeek: true };
    return {
      ...(JSON.parse(pin.wod) as ChallengeWod),
      by: pin.user_id && pin.nickname ? { userId: pin.user_id, nickname: pin.nickname } : null,
      memberWeek: true,
      card: null,
      deckSize: CHALLENGE_DECK.length,
    };
  };
  /** The next member week to vote for: after this week and not picked yet (the earliest time zone starting it picks). */
  const voteWeek = () => {
    let wk = isoWeek(now());
    do wk = addWeeks(wk, 1, isoWeek);
    while (!isMemberWeek(wk, isoWeek) || pinOf(wk));
    return wk;
  };
  const rankOf = (wk: string, score: number, me: string) =>
    (db.prepare(`SELECT COUNT(*) AS n FROM community_challenge_scores s WHERE s.week = ? AND s.score > ? AND ${countsFor('s')}`).get(wk, score, me, me, me) as { n: number }).n + 1;

  r.get('/community/challenge', async (req) => {
    const q = z.object({ week: week.optional() }).parse(req.query);
    const me = req.userId!;
    requireMember(me);
    const wk = q.week ?? isoWeek(now());
    // First: a member week that starts now picks its winner before the vote is shown.
    const wod = weekWod(wk);
    const select = `SELECT s.user_id, s.rounds, s.reps, s.seconds, s.tier, s.score, cp.nickname, cp.avatar_id, cp.level,
        (SELECT COUNT(*) FROM community_challenge_scores o WHERE o.week = s.week AND o.score > s.score AND ${countsFor('o')}) + 1 AS rank,
        l.updated_at AS live_at, l.challenge_week
      FROM community_challenge_scores s JOIN community_profiles cp ON cp.user_id = s.user_id
      LEFT JOIN community_live l ON l.user_id = s.user_id`;
    type Row = {
      user_id: string;
      rounds: number;
      reps: number;
      seconds: number | null;
      tier: ChallengeTier;
      score: number;
      nickname: string;
      avatar_id: string | null;
      level: number | null;
      rank: number;
      live_at: string | null;
      challenge_week: string | null;
    };
    const top = db
      .prepare(`${select} WHERE s.week = ? AND ${countsFor('s')} ORDER BY s.score DESC, s.updated_at LIMIT ?`)
      .all(me, me, me, wk, me, me, me, BOARD) as Row[];
    const mine = db.prepare(`${select} WHERE s.week = ? AND s.user_id = ?`).get(me, me, me, wk, me) as Row | undefined;
    const entry = (x: Row) => ({
      rank: x.rank,
      userId: x.user_id,
      nickname: x.nickname,
      avatarUrl: avatarUrl(x.avatar_id),
      level: x.level ?? null,
      rounds: x.rounds,
      reps: x.reps,
      seconds: x.seconds ?? null,
      tier: x.tier,
      live: x.challenge_week === wk && fresh(x.live_at ? { updated_at: x.live_at } : undefined),
      me: x.user_id === me,
    });
    const joined = (db.prepare(`SELECT COUNT(*) AS n FROM community_challenge_scores s WHERE s.week = ? AND ${countsFor('s')}`).get(wk, me, me, me) as { n: number }).n;
    const since = new Date(now().getTime() - LIVE_TTL_MS).toISOString();
    const training = (
      db
        .prepare(`SELECT COUNT(*) AS n FROM community_live l WHERE l.challenge_week = ? AND l.updated_at >= ? AND l.state != 'done' AND ${countsFor('l')}`)
        .get(wk, since, me, me, me) as { n: number }
    ).n;
    // Next week: a teaser (format, time, how many moves), or the member week.
    const nextWk = addWeeks(wk, 1, isoWeek);
    const nextDeck = deckWod(nextWk).wod;
    const next = isMemberWeek(nextWk, isoWeek)
      ? { week: nextWk, memberWeek: true, format: null, minutes: null, moveCount: null }
      : { week: nextWk, memberWeek: false, format: nextDeck.format, minutes: nextDeck.minutes, moveCount: nextDeck.moves.length };
    // The member's last 4 weeks.
    const history = [1, 2, 3, 4].map((k) => {
      const w = addWeeks(wk, -k, isoWeek);
      const s = db.prepare('SELECT score FROM community_challenge_scores WHERE week = ? AND user_id = ?').get(w, me) as { score: number } | undefined;
      return { week: w, name: weekWod(w).name, rank: s ? rankOf(w, s.score, me) : null };
    });
    const vw = voteWeek();
    const tally = db.prepare('SELECT COUNT(*) AS n FROM community_challenge_votes WHERE week = ? AND suggestion_id = ?');
    const myVote = (db.prepare('SELECT suggestion_id FROM community_challenge_votes WHERE week = ? AND user_id = ?').get(vw, me) as { suggestion_id: string } | undefined)?.suggestion_id;
    const vote = {
      week: vw,
      // Monday 00:00 where it starts first (UTC+14).
      endsAt: new Date(thursdayOf(vw).getTime() - 3 * 86_400_000 - 14 * 3_600_000).toISOString(),
      finalists: finalists(db).map((f) => ({
        id: f.id,
        ...suggestionWod(f),
        by: { userId: f.user_id, nickname: f.nickname },
        votes: (tally.get(vw, f.id) as { n: number }).n,
        mine: f.id === myVote,
      })),
    };
    return { week: wk, wod, next, history, vote, joined, training, leaderboard: top.map(entry), me: mine ? entry(mine) : null };
  });

  /**
   * The week's score, the best one stays. AMRAP / EMOM: rounds + reps; Tabata: reps; For time: seconds when
   * finished under the cap, else reps done. Tier ranks first (Beast, Rx, Easy).
   */
  r.put('/community/challenge/score', async (req) => {
    const b = z
      .object({
        week,
        rounds: z.number().int().min(0).max(200).default(0),
        reps: z.number().int().min(0).max(999).default(0),
        seconds: z.number().int().min(1).max(25 * 60).nullish(),
        tier: z.enum(CHALLENGE_TIERS).default('rx'),
      })
      .parse(req.body);
    const me = req.userId!;
    requireMember(me);
    if (!openWeeks(now()).has(b.week)) throw new ApiError(400, 'week_closed', 'That challenge week is over.');
    const wod = weekWod(b.week);
    const seconds = wod.format === 'fortime' ? (b.seconds ?? null) : null;
    if (seconds != null && seconds > wod.minutes * 60) throw new ApiError(400, 'over_cap', `The cap is ${wod.minutes}′.`);
    if (!seconds && b.rounds === 0 && b.reps === 0) throw new ApiError(400, 'invalid_request', 'Enter a score.');
    const score = challengeScore(wod, b.tier, { rounds: b.rounds, reps: b.reps, seconds });
    const ts = now().toISOString();
    db.prepare(
      `INSERT INTO community_challenge_scores (week, user_id, rounds, reps, seconds, tier, score, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(week, user_id) DO UPDATE SET rounds = excluded.rounds, reps = excluded.reps, seconds = excluded.seconds, tier = excluded.tier,
         score = excluded.score, updated_at = excluded.updated_at
       WHERE excluded.score > community_challenge_scores.score`,
    ).run(b.week, me, b.rounds, b.reps, seconds, b.tier, score, ts);
    const row = db.prepare('SELECT rounds, reps, seconds, tier, score FROM community_challenge_scores WHERE week = ? AND user_id = ?').get(b.week, me) as {
      rounds: number;
      reps: number;
      seconds: number | null;
      tier: ChallengeTier;
      score: number;
    };
    return { week: b.week, rounds: row.rounds, reps: row.reps, seconds: row.seconds, tier: row.tier, rank: rankOf(b.week, row.score, me), best: row.score === score };
  });

  // Member suggestions: the Coach check on send, the owner approves (admin.ts), members vote 3 finalists.

  const suggestionOut = (s: SuggestionRow) => ({ id: s.id, ...suggestionWod(s), status: s.status, week: s.week, createdAt: s.created_at });

  r.get('/community/challenge/suggestions', async (req) => {
    const me = req.userId!;
    requireMember(me);
    const rows = db.prepare('SELECT * FROM community_challenge_suggestions WHERE user_id = ? ORDER BY created_at DESC').all(me) as SuggestionRow[];
    return { suggestions: rows.map(suggestionOut), moves: CHALLENGE_MOVES };
  });

  r.post('/community/challenge/suggestions', async (req, reply) => {
    const me = req.userId!;
    requireMember(me);
    const wod = checkSuggestion(suggestionBody.parse(req.body));
    const pending = (db.prepare("SELECT COUNT(*) AS n FROM community_challenge_suggestions WHERE user_id = ? AND status = 'pending'").get(me) as { n: number }).n;
    if (pending >= MAX_PENDING_SUGGESTIONS) throw new ApiError(409, 'too_many_pending', `Up to ${MAX_PENDING_SUGGESTIONS} suggestions wait for review at once.`);
    const id = randomUUID();
    db.prepare('INSERT INTO community_challenge_suggestions (id, user_id, name, format, minutes, moves, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
      id,
      me,
      wod.name,
      wod.format,
      wod.minutes,
      JSON.stringify(wod.moves),
      now().toISOString(),
    );
    reply.code(201);
    return { suggestion: suggestionOut(db.prepare('SELECT * FROM community_challenge_suggestions WHERE id = ?').get(id) as SuggestionRow) };
  });

  /** Withdraw one that hasn't run yet. */
  r.delete('/community/challenge/suggestions/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string().min(1).max(64) }).parse(req.params);
    const me = req.userId!;
    const gone = db.prepare('DELETE FROM community_challenge_suggestions WHERE id = ? AND user_id = ? AND week IS NULL').run(id, me).changes;
    if (!gone) throw new ApiError(404, 'not_found', 'No such suggestion.');
    reply.code(204);
  });

  /** One vote per member for the next member week, changeable until it starts. */
  r.put('/community/challenge/vote', async (req) => {
    const b = z.object({ suggestionId: z.string().min(1).max(64) }).parse(req.body);
    const me = req.userId!;
    requireMember(me);
    if (!finalists(db).some((f) => f.id === b.suggestionId)) throw new ApiError(400, 'not_finalist', 'That one is not in the vote.');
    const vw = voteWeek();
    db.prepare(
      `INSERT INTO community_challenge_votes (week, user_id, suggestion_id, created_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(week, user_id) DO UPDATE SET suggestion_id = excluded.suggestion_id, created_at = excluded.created_at`,
    ).run(vw, me, b.suggestionId, now().toISOString());
    return { week: vw, suggestionId: b.suggestionId };
  });
};
