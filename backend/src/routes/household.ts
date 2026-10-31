import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { isBlockedBetween } from '../community/moderation.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { PushService } from '../push/service.ts';
import { DAY, throttleTake } from '../throttle.ts';

/**
 * Fuel with a partner (#1014).
 *
 * Household: one meal plan and one grocery list shared live by up to `MAX_MEMBERS` members who both said yes (invite →
 * accept). The plan is an opaque blob the app writes with the household's revision (optimistic concurrency: a stale
 * write gets 409 and the current plan back); ticks in the shop are separate rows so two people in two aisles never
 * clash. Only what the app puts in `state` is shared (plan days, recipes used, plan settings): food logs, macros,
 * weight and What I have stay on each phone. Anyone leaves at any time; the last one out deletes the household.
 *
 * Send a copy: a one-off snapshot of a plan and/or grocery list to someone who follows the sender back (or shares
 * their household). Nothing stays linked; the copy expires after `SHARE_TTL_DAYS`.
 */

export const MAX_MEMBERS = 6;
export const MAX_PENDING_INVITES = 5;
export const MAX_STATE_BYTES = 256 * 1024;
export const MAX_SHARE_BYTES = 256 * 1024;
export const SHARE_TTL_DAYS = 30;
/** Copies a member may send a day. */
export const SHARES_PER_DAY = 20;

const userIdParam = z.object({ userId: z.string().min(1).max(64) });
const idParam = z.object({ id: z.uuid() });
const itemId = z.string().regex(/^[A-Za-z0-9._:-]{1,80}$/);

/** The shared plan: what the app writes, checked for shape and size, otherwise kept as is. */
const plannedMeal = z
  .object({
    day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    slot: z.string().min(1).max(40),
    kind: z.string().min(1).max(40),
    recipeId: z.string().min(1).max(120),
    servings: z.number().int().min(1).max(20),
    pinned: z.boolean(),
    leftover: z.boolean(),
  })
  .catchall(z.unknown());
const planState = z
  .object({
    plan: z.array(plannedMeal).max(1000),
    recipes: z.array(z.record(z.string(), z.unknown())).max(300).default([]),
    book: z.record(z.string(), z.unknown()).nullish(),
    people: z.number().int().min(1).max(20).optional(),
    budget: z.number().min(0).max(100_000).nullish(),
    lessWaste: z.boolean().optional(),
  })
  .catchall(z.unknown());
const groceryLine = z
  .object({ id: itemId, name: z.string().min(1).max(80), grams: z.number().min(0).max(1_000_000) })
  .catchall(z.unknown());

export const ensureHouseholdSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS households (
      id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      rev INTEGER NOT NULL DEFAULT 0,
      state TEXT,
      updated_at TEXT,
      updated_by TEXT REFERENCES users(id) ON DELETE SET NULL
    );
    CREATE TABLE IF NOT EXISTS household_members (
      household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
      joined_at TEXT NOT NULL,
      PRIMARY KEY (household_id, user_id)
    );
    CREATE TABLE IF NOT EXISTS household_invites (
      id TEXT PRIMARY KEY,
      household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
      from_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      UNIQUE (household_id, to_id)
    );
    CREATE INDEX IF NOT EXISTS household_invites_to ON household_invites(to_id);
    CREATE TABLE IF NOT EXISTS household_bought (
      household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL,
      user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
      at TEXT NOT NULL,
      PRIMARY KEY (household_id, item_id)
    );
    -- The last member out (leave, account deleted) takes the household and its plan with them.
    CREATE TRIGGER IF NOT EXISTS household_last_out AFTER DELETE ON household_members
    WHEN NOT EXISTS (SELECT 1 FROM household_members WHERE household_id = OLD.household_id)
    BEGIN DELETE FROM households WHERE id = OLD.household_id; END;
    CREATE TABLE IF NOT EXISTS fuel_shares (
      id TEXT PRIMARY KEY,
      from_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('plan', 'groceries', 'both')),
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS fuel_shares_to ON fuel_shares(to_id, created_at);
    CREATE INDEX IF NOT EXISTS fuel_shares_from ON fuel_shares(from_id);
  `);
};

const householdOf = (db: DB, userId: string) =>
  (db.prepare('SELECT household_id FROM household_members WHERE user_id = ?').get(userId) as { household_id: string } | undefined)?.household_id ?? null;

const nicknameOf = (db: DB, userId: string) =>
  (
    (db.prepare('SELECT nickname FROM community_profiles WHERE user_id = ?').get(userId) ??
      db.prepare('SELECT nickname FROM user_profiles WHERE user_id = ?').get(userId)) as { nickname: string | null } | undefined
  )?.nickname ?? 'Member';

/** A block between two members ends what they share: invites, copies, and the blocker leaves a shared household. */
export const householdOnBlock = (db: DB, blocker: string, blocked: string): void => {
  db.prepare('DELETE FROM household_invites WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)').run(blocker, blocked, blocked, blocker);
  db.prepare('DELETE FROM fuel_shares WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)').run(blocker, blocked, blocked, blocker);
  const h = householdOf(db, blocker);
  if (h && householdOf(db, blocked) === h) db.prepare('DELETE FROM household_members WHERE user_id = ?').run(blocker);
};

export const householdExport = (db: DB, userId: string) => {
  const h = householdOf(db, userId);
  const row = h ? (db.prepare('SELECT created_at, rev, state, updated_at FROM households WHERE id = ?').get(h) as Record<string, unknown> | undefined) : undefined;
  return {
    household: row
      ? {
          createdAt: row.created_at,
          rev: row.rev,
          state: typeof row.state === 'string' ? JSON.parse(row.state) : null,
          updatedAt: row.updated_at,
          members: (db.prepare('SELECT user_id, joined_at FROM household_members WHERE household_id = ?').all(h) as { user_id: string; joined_at: string }[]).map(
            (m) => ({ userId: m.user_id, joinedAt: m.joined_at }),
          ),
          myTicks: db.prepare('SELECT item_id, at FROM household_bought WHERE household_id = ? AND user_id = ?').all(h, userId),
        }
      : null,
    invitesSent: db.prepare('SELECT to_id, created_at FROM household_invites WHERE from_id = ?').all(userId),
    invitesReceived: db.prepare('SELECT from_id, created_at FROM household_invites WHERE to_id = ?').all(userId),
    copiesSent: (db.prepare('SELECT to_id, kind, payload, created_at FROM fuel_shares WHERE from_id = ?').all(userId) as { payload: string }[]).map((s) => ({
      ...s,
      payload: JSON.parse(s.payload),
    })),
    copiesReceived: (db.prepare('SELECT from_id, kind, payload, created_at FROM fuel_shares WHERE to_id = ?').all(userId) as { payload: string }[]).map((s) => ({
      ...s,
      payload: JSON.parse(s.payload),
    })),
  };
};

export const householdRoutes = (r: FastifyInstance, db: DB, now: () => Date, push?: PushService) => {
  const isSocialMember = (userId: string) => !!db.prepare('SELECT 1 FROM community_profiles WHERE user_id = ?').get(userId);
  const follows = (a: string, b: string) => !!db.prepare('SELECT 1 FROM community_follows WHERE follower_id = ? AND followed_id = ?').get(a, b);
  const memberCount = (h: string) => (db.prepare('SELECT COUNT(*) AS n FROM household_members WHERE household_id = ?').get(h) as { n: number }).n;
  const person = (userId: string | null) => (userId ? { userId, nickname: nicknameOf(db, userId) } : null);

  const view = (me: string) => {
    const h = householdOf(db, me);
    const row = h
      ? (db.prepare('SELECT id, rev, state, updated_at, updated_by FROM households WHERE id = ?').get(h) as
          | { id: string; rev: number; state: string | null; updated_at: string | null; updated_by: string | null }
          | undefined)
      : undefined;
    const incoming = db
      .prepare('SELECT id, household_id, from_id, created_at FROM household_invites WHERE to_id = ? ORDER BY created_at DESC')
      .all(me) as { id: string; household_id: string; from_id: string; created_at: string }[];
    const outgoing = db
      .prepare('SELECT id, to_id, created_at FROM household_invites WHERE from_id = ? ORDER BY created_at DESC')
      .all(me) as { id: string; to_id: string; created_at: string }[];
    return {
      household: row
        ? {
            id: row.id,
            rev: row.rev,
            state: row.state ? JSON.parse(row.state) : null,
            updatedAt: row.updated_at,
            updatedBy: person(row.updated_by),
            /** Me first, then by joining. */
            members: (
              db.prepare('SELECT user_id, joined_at FROM household_members WHERE household_id = ? ORDER BY user_id = ? DESC, joined_at, user_id').all(row.id, me) as { user_id: string; joined_at: string }[]
            ).map((m) => ({ ...person(m.user_id)!, joinedAt: m.joined_at, me: m.user_id === me })),
            bought: (
              db.prepare('SELECT item_id, user_id, at FROM household_bought WHERE household_id = ? ORDER BY at, item_id').all(row.id) as { item_id: string; user_id: string | null; at: string }[]
            ).map((b) => ({ itemId: b.item_id, by: person(b.user_id), at: b.at })),
          }
        : null,
      invites: {
        incoming: incoming.map((i) => ({ id: i.id, from: person(i.from_id)!, members: memberCount(i.household_id), createdAt: i.created_at })),
        outgoing: outgoing.map((i) => ({ id: i.id, to: person(i.to_id)!, createdAt: i.created_at })),
      },
    };
  };

  const notify = (to: string, from: string, title: string, body: string, key: string) => {
    if (!push || !throttleTake(db, `household-push:${key}:${from}:${to}`, 1, DAY, now())) return;
    push.notifyLater(to, 'household', {
      title,
      body,
      data: { kind: 'household', actorId: from, actorName: nicknameOf(db, from) },
      collapseId: `household-${from}`.slice(0, 64),
    });
  };

  r.get('/household', async (req) => view(req.userId!));

  /** Invite a Social member to share my plan; makes my household on first invite. */
  r.post('/household/invites', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req) => {
    const { userId } = userIdParam.parse(req.body);
    const me = req.userId!;
    if (userId === me) throw new ApiError(400, 'own_content', 'You cannot invite yourself.');
    if (!isSocialMember(me)) throw new ApiError(403, 'community_profile_required', 'Join Social first to find your partner.');
    if (!isSocialMember(userId) || isBlockedBetween(db, me, userId)) throw new ApiError(404, 'not_found', 'Member not found.');
    const ts = now().toISOString();
    tx(db, () => {
      let h = householdOf(db, me);
      if (!h) {
        h = randomUUID();
        db.prepare('INSERT INTO households (id, created_at) VALUES (?, ?)').run(h, ts);
        db.prepare('INSERT INTO household_members (household_id, user_id, joined_at) VALUES (?, ?, ?)').run(h, me, ts);
      }
      if (householdOf(db, userId) === h) throw new ApiError(409, 'already_member', 'Already sharing with you.');
      const pending = (db.prepare('SELECT COUNT(*) AS n FROM household_invites WHERE household_id = ?').get(h) as { n: number }).n;
      if (memberCount(h) + pending >= MAX_MEMBERS) throw new ApiError(400, 'household_full', `Up to ${MAX_MEMBERS} people share a plan.`);
      if (pending >= MAX_PENDING_INVITES) throw new ApiError(400, 'too_many_invites', 'Wait for an answer to your other invites.');
      db.prepare('INSERT OR IGNORE INTO household_invites (id, household_id, from_id, to_id, created_at) VALUES (?, ?, ?, ?, ?)').run(randomUUID(), h, me, userId, ts);
    });
    notify(userId, me, 'Share meals? 🍽️', `${nicknameOf(db, me)} wants to share a meal plan and grocery list with you.`, 'invite');
    return view(me);
  });

  /** Accept: join their household (leaving mine needs `leaveCurrent`, so nobody loses a plan by accident). */
  r.post('/household/invites/:id/accept', async (req) => {
    const { id } = idParam.parse(req.params);
    const { leaveCurrent } = z.object({ leaveCurrent: z.boolean().default(false) }).parse(req.body ?? {});
    const me = req.userId!;
    const inv = db.prepare('SELECT household_id, from_id FROM household_invites WHERE id = ? AND to_id = ?').get(id, me) as
      | { household_id: string; from_id: string }
      | undefined;
    if (!inv || isBlockedBetween(db, me, inv.from_id)) throw new ApiError(404, 'not_found', 'Invite not found.');
    tx(db, () => {
      const current = householdOf(db, me);
      if (current && current !== inv.household_id) {
        if (!leaveCurrent && memberCount(current) > 1) throw new ApiError(409, 'in_household', 'You already share a plan. Leave it to join this one.');
        db.prepare('DELETE FROM household_members WHERE user_id = ?').run(me);
      }
      if (memberCount(inv.household_id) >= MAX_MEMBERS) throw new ApiError(400, 'household_full', `Up to ${MAX_MEMBERS} people share a plan.`);
      db.prepare('INSERT OR IGNORE INTO household_members (household_id, user_id, joined_at) VALUES (?, ?, ?)').run(inv.household_id, me, now().toISOString());
      db.prepare('DELETE FROM household_invites WHERE id = ?').run(id);
    });
    notify(inv.from_id, me, 'Meals shared 🍽️', `${nicknameOf(db, me)} said yes: you now share a meal plan and groceries.`, 'accept');
    return view(me);
  });

  /** Decline (invitee) or cancel (inviter). */
  r.delete('/household/invites/:id', async (req, reply) => {
    const { id } = idParam.parse(req.params);
    const me = req.userId!;
    const n = Number(db.prepare('DELETE FROM household_invites WHERE id = ? AND (to_id = ? OR from_id = ?)').run(id, me, me).changes);
    if (!n) throw new ApiError(404, 'not_found', 'Invite not found.');
    return reply.status(204).send();
  });

  /** Write the shared plan; `rev` must be the one last read, otherwise 409 `stale` with the current household. */
  r.put('/household/state', { bodyLimit: MAX_STATE_BYTES + 4096 }, async (req) => {
    const b = z.object({ rev: z.number().int().min(0), state: planState }).parse(req.body);
    const me = req.userId!;
    const h = householdOf(db, me);
    if (!h) throw new ApiError(404, 'no_household', 'You are not sharing a plan.');
    const json = JSON.stringify(b.state);
    if (Buffer.byteLength(json) > MAX_STATE_BYTES) throw new ApiError(413, 'too_large', 'That plan is too big to share.');
    const ts = now().toISOString();
    const n = Number(db.prepare('UPDATE households SET state = ?, rev = rev + 1, updated_at = ?, updated_by = ? WHERE id = ? AND rev = ?').run(json, ts, me, h, b.rev).changes);
    if (!n) throw new ApiError(409, 'stale', 'Your partner changed the plan. Showing theirs.', view(me));
    return { rev: b.rev + 1, updatedAt: ts };
  });

  /** Tick or untick grocery lines in the shop (who ticked shows on the other phone). */
  r.put('/household/bought', async (req) => {
    const b = z.object({ itemIds: z.array(itemId).min(1).max(500), bought: z.boolean() }).parse(req.body);
    const me = req.userId!;
    const h = householdOf(db, me);
    if (!h) throw new ApiError(404, 'no_household', 'You are not sharing a plan.');
    const ts = now().toISOString();
    tx(db, () => {
      const put = db.prepare('INSERT OR IGNORE INTO household_bought (household_id, item_id, user_id, at) VALUES (?, ?, ?, ?)');
      const del = db.prepare('DELETE FROM household_bought WHERE household_id = ? AND item_id = ?');
      for (const i of b.itemIds) b.bought ? put.run(h, i, me, ts) : del.run(h, i);
    });
    return { bought: view(me).household!.bought };
  });

  /** Leave: my phone keeps its copy of the plan; the last one out deletes the household. */
  r.delete('/household/me', async (req, reply) => {
    db.prepare('DELETE FROM household_members WHERE user_id = ?').run(req.userId!);
    return reply.status(204).send();
  });

  // ───────────── Send a copy

  const shareBody = z.object({
    toUserId: z.string().min(1).max(64),
    kind: z.enum(['plan', 'groceries', 'both']),
    payload: z
      .object({
        plan: planState.nullish(),
        groceries: z.array(groceryLine).max(500).nullish(),
        note: z.string().trim().max(200).nullish(),
      })
      .catchall(z.unknown()),
  });

  r.post('/fuel-shares', { bodyLimit: MAX_SHARE_BYTES + 4096, config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req, reply) => {
    const b = shareBody.parse(req.body);
    const me = req.userId!;
    if (b.toUserId === me) throw new ApiError(400, 'own_content', 'You cannot send to yourself.');
    if ((b.kind !== 'groceries' && !b.payload.plan) || (b.kind !== 'plan' && !b.payload.groceries))
      throw new ApiError(400, 'invalid_share', 'Nothing to send.');
    const sameHousehold = !!householdOf(db, me) && householdOf(db, me) === householdOf(db, b.toUserId);
    // Copies go only to people who follow me back (or share my plan): no unsolicited content.
    const allowed = sameHousehold || (follows(me, b.toUserId) && follows(b.toUserId, me));
    if (!allowed || isBlockedBetween(db, me, b.toUserId)) throw new ApiError(404, 'not_found', 'Send to friends who follow you back.');
    const json = JSON.stringify(b.payload);
    if (Buffer.byteLength(json) > MAX_SHARE_BYTES) throw new ApiError(413, 'too_large', 'That is too big to send.');
    if (!throttleTake(db, `fuel-share:${me}`, SHARES_PER_DAY, DAY, now())) throw new ApiError(429, 'daily_limit', 'That is enough sending for today.');
    const id = randomUUID();
    db.prepare('INSERT INTO fuel_shares (id, from_id, to_id, kind, payload, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, me, b.toUserId, b.kind, json, now().toISOString());
    const what = b.kind === 'plan' ? 'a meal plan' : b.kind === 'groceries' ? 'a grocery list' : 'a meal plan and grocery list';
    if (push)
      push.notifyLater(b.toUserId, 'household', {
        title: `${nicknameOf(db, me)} sent you ${what} 🛒`,
        body: 'Open Fuel to use it or add it to yours.',
        data: { kind: 'fuel_share', actorId: me, actorName: nicknameOf(db, me) },
        collapseId: `fuel-share-${me}`.slice(0, 64),
      });
    return reply.status(201).send({ id });
  });

  /** Copies sent to me in the last `SHARE_TTL_DAYS` (older ones are deleted on read). */
  r.get('/fuel-shares', async (req) => {
    const me = req.userId!;
    const cutoff = new Date(now().getTime() - SHARE_TTL_DAYS * DAY).toISOString();
    db.prepare('DELETE FROM fuel_shares WHERE created_at < ?').run(cutoff);
    const rows = db.prepare('SELECT id, from_id, kind, payload, created_at FROM fuel_shares WHERE to_id = ? ORDER BY created_at DESC LIMIT 50').all(me) as {
      id: string;
      from_id: string;
      kind: string;
      payload: string;
      created_at: string;
    }[];
    return { shares: rows.map((s) => ({ id: s.id, from: person(s.from_id)!, kind: s.kind, payload: JSON.parse(s.payload), createdAt: s.created_at })) };
  });

  /** Dismiss (recipient) or unsend (sender). */
  r.delete('/fuel-shares/:id', async (req, reply) => {
    const { id } = idParam.parse(req.params);
    const me = req.userId!;
    const n = Number(db.prepare('DELETE FROM fuel_shares WHERE id = ? AND (to_id = ? OR from_id = ?)').run(id, me, me).changes);
    if (!n) throw new ApiError(404, 'not_found', 'Not found.');
    return reply.status(204).send();
  });
};
