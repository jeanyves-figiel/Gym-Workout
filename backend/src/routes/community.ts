import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type HoldCategory, type Moderator, noModerator } from '../community/aiModeration.ts';
import { AVATAR_MAX_BYTES, sanitizeJpeg } from '../community/image.ts';
import {
  assertClean as checkClean,
  AUTO_HIDE_REPORTS,
  isBlockedBetween,
  memberNotHiddenSql,
  reportContent,
  REPORT_REASONS,
  type Visibility,
  VISIBILITIES,
  visibleToOthersSql,
} from '../community/moderation.ts';
import { type Gym, refreshMemberGym } from '../community/schema.ts';
import { type DB, tx } from '../db.ts';
import { nameKey } from '../gymSchema.ts';
import { ApiError } from '../errors.ts';
import type { Mailer } from '../mailer.ts';
import { DAY, throttleTake } from '../throttle.ts';
import { leaveLive, unpair } from './live.ts';
import { followReferralPair, referralOwner } from './referrals.ts';
import { beforeSql, pageCursor } from './sync.ts';

/** New community posts per member per day (updates of an existing post don't count). */
const POSTS_PER_DAY = 50;

/** Community (#61): profiles, shared progress posts, cheers, report + block. */

export const REACTIONS = ['like', 'strong', 'fire', 'clap', 'beast', 'banana'] as const;
const POST_KINDS = ['workout', 'badge', 'record', 'climb', 'note'] as const;

/** Social handles on the member profile (#745), stored without "@"; the app builds the links. */
export const SOCIALS_VISIBILITIES = ['everyone', 'following', 'nobody'] as const;
type SocialsVisibility = (typeof SOCIALS_VISIBILITIES)[number];
const handle = (re: RegExp) =>
  z.string().trim().transform((v) => v.replace(/^@/, '')).pipe(z.union([z.literal(''), z.string().regex(re)])).nullish();
const socialsBody = z.object({
  instagram: handle(/^[A-Za-z0-9._]{1,30}$/),
  tiktok: handle(/^[A-Za-z0-9._]{1,24}$/),
  strava: handle(/^[A-Za-z0-9_-]{1,40}$/),
  youtube: handle(/^[A-Za-z0-9._-]{1,30}$/),
});
type Socials = z.infer<typeof socialsBody>;
const parseSocials = (raw: string | null): Socials => {
  try {
    return raw ? (JSON.parse(raw) as Socials) : {};
  } catch {
    return {};
  }
};

interface ProfileRow {
  user_id: string;
  nickname: string;
  bio: string | null;
  avatar_id: string | null;
  default_visibility: Visibility;
  auto_share: number;
  show_gym: number;
  level: number | null;
  pronouns: string | null;
  gym_id: string | null;
  gym_name: string | null;
  gym_lat: number | null;
  gym_lon: number | null;
  socials: string | null;
  socials_visibility: SocialsVisibility;
  guidelines_accepted_at: string;
  created_at: string;
}

/** Account profile of a user who has not joined (#108). */
interface AccountRow {
  user_id: string;
  nickname: string | null;
  bio: string | null;
  avatar_id: string | null;
}

interface PostRow {
  id: string;
  user_id: string;
  kind: string;
  ref_id: string | null;
  visibility: Visibility;
  caption: string | null;
  payload: string;
  hidden_at: string | null;
  created_at: string;
  updated_at: string;
  nickname: string | null;
  avatar_id: string | null;
  level: number | null;
  pronouns: string | null;
}


/** Same place: same id, or same name within ~300 m (map-search ids are rounded coordinates, so they can differ). */
export const sameGym = (a: Gym, b: Gym) =>
  a.id === b.id ||
  (a.name.trim().toLowerCase() === b.name.trim().toLowerCase() &&
    a.latitude != null && a.longitude != null && b.latitude != null && b.longitude != null &&
    Math.abs(a.latitude - b.latitude) < 0.003 && Math.abs(a.longitude - b.longitude) < 0.004);

const avatarUrl = (id: string | null) => (id ? `/v1/community/avatars/${id}` : null);

const nickname = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9_.]{3,20}$/, 'Nickname: 3–20 letters, digits, _ or .');
const bio = z.string().trim().max(160);
const caption = z.string().trim().max(280);
const text = (max: number) => z.string().trim().max(max);

/** Display card for a post; the app builds it from a workout, badge, best or climb. */
const payload = z.object({
  title: text(80).min(1),
  subtitle: text(120).nullish(),
  /** Big number on the card, e.g. { value: "6.4", unit: "t lifted" }. */
  metric: z.object({ value: text(12).min(1), unit: text(20) }).nullish(),
  /** Category/goal key for the card gradient (app-defined). */
  style: text(24).nullish(),
  stats: z.array(z.object({ label: text(20).min(1), value: text(20).min(1) })).max(4).nullish(),
  /** Exercises of a shared workout (#779), so members can open the post and copy it: catalog id, name, sets done, reps and kg. */
  exercises: z
    .array(
      z.object({
        id: text(64).min(1),
        name: text(60).min(1),
        sets: z.number().int().min(0).max(50),
        reps: z.number().min(0).max(1000).nullish(),
        kg: z.number().min(0).max(1000).nullish(),
      }),
    )
    .max(40)
    .nullish(),
});

export const communityExport = (db: DB, userId: string) => ({
  accountProfile: db.prepare('SELECT nickname, bio, updated_at FROM user_profiles WHERE user_id = ?').get(userId) ?? null,
  profile: db
    .prepare('SELECT nickname, bio, default_visibility, auto_share, show_gym, level, pronouns, guidelines_accepted_at, created_at FROM community_profiles WHERE user_id = ?')
    .get(userId) ?? null,
  // The photo itself (#713), base64 JPEG, whether it sits on the community or the account profile.
  avatarJpegBase64: ((r) => (r ? Buffer.from(r.data).toString('base64') : null))(
    db.prepare('SELECT data FROM community_avatars WHERE user_id = ? ORDER BY created_at DESC LIMIT 1').get(userId) as { data: Uint8Array } | undefined,
  ),
  posts: (db.prepare('SELECT id, kind, ref_id, visibility, caption, payload, hidden_at, created_at FROM community_posts WHERE user_id = ? ORDER BY created_at').all(userId) as unknown as { payload: string }[]).map(
    (p) => ({ ...p, payload: JSON.parse(p.payload) as unknown }),
  ),
  reactionsGiven: db.prepare('SELECT post_id, kind, created_at FROM community_reactions WHERE user_id = ?').all(userId),
  blocked: db.prepare('SELECT blocked_id, created_at FROM community_blocks WHERE blocker_id = ?').all(userId),
  following: db.prepare('SELECT followed_id, created_at FROM community_follows WHERE follower_id = ?').all(userId),
});

export const communityRoutes = (r: FastifyInstance, db: DB, now: () => Date, mailer: Mailer, moderationEmail?: string, mod: Moderator = noModerator()) => {
  r.addContentTypeParser('image/jpeg', { parseAs: 'buffer', bodyLimit: AVATAR_MAX_BYTES + 1024 }, (_req, body, done) => done(null, body));

  const profileRow = (userId: string) =>
    db.prepare('SELECT * FROM community_profiles WHERE user_id = ?').get(userId) as ProfileRow | undefined;

  const accountRow = (userId: string) => db.prepare('SELECT * FROM user_profiles WHERE user_id = ?').get(userId) as AccountRow | undefined;

  /**
   * Nickname, photo and about shown on Account and in Community (#108). One record per user: the
   * community profile once joined, else the account-only row. Joining moves it in, leaving moves it back.
   */
  const accountProfile = (userId: string) => {
    const p = profileRow(userId);
    if (p) return { nickname: p.nickname, bio: p.bio, avatarUrl: avatarUrl(p.avatar_id), member: true };
    const a = accountRow(userId);
    return { nickname: a?.nickname ?? null, bio: a?.bio ?? null, avatarUrl: avatarUrl(a?.avatar_id ?? null), member: false };
  };

  /** Nicknames are unique across members and account-only profiles. */
  const assertNicknameFree = (nick: string, userId: string) => {
    const taken = db
      .prepare('SELECT 1 FROM community_profiles WHERE nickname = ? AND user_id != ? UNION ALL SELECT 1 FROM user_profiles WHERE nickname = ? AND user_id != ?')
      .get(nick, userId, nick, userId);
    if (taken) throw new ApiError(409, 'nickname_taken', 'That nickname is taken.');
  };

  const setAvatarId = (userId: string, id: string | null) => {
    const ts = now().toISOString();
    if (profileRow(userId)) db.prepare('UPDATE community_profiles SET avatar_id = ?, updated_at = ? WHERE user_id = ?').run(id, ts, userId);
    else
      db.prepare(
        `INSERT INTO user_profiles (user_id, avatar_id, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET avatar_id = excluded.avatar_id, updated_at = excluded.updated_at`,
      ).run(userId, id, ts);
  };

  /** True when the photo was held by AI moderation (#871): kept aside, the current photo stays until it is released. */
  const storeAvatar = async (userId: string, body: unknown) => {
    if (!Buffer.isBuffer(body)) throw new ApiError(415, 'unsupported_media_type', 'Send the photo as image/jpeg.');
    const img = sanitizeJpeg(body);
    const id = randomUUID();
    const category = await mod.check({ texts: [], jpeg: img.data });
    if (category) {
      db.prepare('INSERT INTO community_avatars (id, user_id, data, created_at) VALUES (?, ?, ?, ?)').run(id, userId, img.data, now().toISOString());
      mod.hold({ userId, type: 'avatar', id, category, jpeg: img.data });
      return true;
    }
    tx(db, () => {
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(userId);
      db.prepare('INSERT INTO community_avatars (id, user_id, data, created_at) VALUES (?, ?, ?, ?)').run(id, userId, img.data, now().toISOString());
      setAvatarId(userId, id);
    });
    return false;
  };

  /** AI check (#871) of a nickname / about that changed: refused like the word filter, since a profile can't wait for review. */
  const assertProfileClean = async (before: { nickname?: string | null; bio?: string | null }, nick: string | null | undefined, bioText: string | null | undefined) => {
    const changed = [nick !== before.nickname ? nick : null, bioText !== before.bio ? bioText : null];
    if (await mod.check({ texts: changed })) throw new ApiError(400, 'objectionable_content', 'Please keep it friendly: that text is not allowed in the community.');
  };

  const clearAvatar = (userId: string) =>
    tx(db, () => {
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(userId);
      setAvatarId(userId, null);
    });

  const requireProfile = (userId: string) => {
    const p = profileRow(userId);
    if (!p) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
    return p;
  };

  /** Either side blocked the other. */
  const blockedBetween = (a: string, b: string) => isBlockedBetween(db, a, b);

  const stats = (userId: string) => {
    const s = db
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM community_posts WHERE user_id = ? AND hidden_at IS NULL AND visibility != 'private') AS shared,
           (SELECT COUNT(*) FROM community_reactions cr JOIN community_posts p ON p.id = cr.post_id WHERE p.user_id = ?) AS cheers,
           (SELECT COUNT(*) FROM community_follows WHERE followed_id = ?) AS followers,
           (SELECT COUNT(*) FROM community_follows WHERE follower_id = ?) AS following`,
      )
      .get(userId, userId, userId, userId) as { shared: number; cheers: number; followers: number; following: number };
    return { sharedPosts: s.shared, cheersReceived: s.cheers, followers: s.followers, following: s.following };
  };

  /** Training-profile gym, from the community profile's columns (#715, `refreshMemberGym`). */
  const gymOf = (p: ProfileRow): Gym | null =>
    p.gym_id && p.gym_name ? { id: p.gym_id, name: p.gym_name, latitude: p.gym_lat, longitude: p.gym_lon } : null;
  const sharedGym = (p: ProfileRow) => (p.show_gym ? gymOf(p) : null);

  const ownProfile = (p: ProfileRow) => ({
    userId: p.user_id,
    nickname: p.nickname,
    bio: p.bio,
    avatarUrl: avatarUrl(p.avatar_id),
    defaultVisibility: p.default_visibility,
    autoShare: !!p.auto_share,
    showGym: !!p.show_gym,
    level: p.level ?? null,
    pronouns: p.pronouns ?? null,
    gym: gymOf(p)?.name ?? null,
    socials: parseSocials(p.socials),
    socialsVisibility: p.socials_visibility,
    guidelinesAcceptedAt: p.guidelines_accepted_at,
    ...stats(p.user_id),
  });

  /** Socials the viewer may see: own, everyone, or followers of the member. */
  const visibleSocials = (p: ProfileRow, viewer: string): Socials | null => {
    const show =
      p.user_id === viewer ||
      p.socials_visibility === 'everyone' ||
      (p.socials_visibility === 'following' && !!db.prepare('SELECT 1 FROM community_follows WHERE follower_id = ? AND followed_id = ?').get(viewer, p.user_id));
    return show ? parseSocials(p.socials) : null;
  };

  const memberProfile = (p: ProfileRow, viewer: string) => ({
    userId: p.user_id,
    nickname: p.nickname,
    bio: p.bio,
    avatarUrl: avatarUrl(p.avatar_id),
    level: p.level ?? null,
    pronouns: p.pronouns ?? null,
    socials: visibleSocials(p, viewer),
    gym: sharedGym(p)?.name ?? null,
    createdAt: p.created_at,
    ...stats(p.user_id),
  });

  /** Rows in Find members and Following lists (#152); counts read in three queries for the whole list (#715). */
  const memberSummaries = (rows: ProfileRow[], viewer: string) => {
    if (!rows.length) return [];
    const ids = rows.map((r) => r.user_id);
    const marks = ids.map(() => '?').join(',');
    const count = (sql: string, ...args: string[]) =>
      new Map((db.prepare(sql).all(...args, ...ids) as { id: string; n: number }[]).map((r) => [r.id, r.n]));
    const shared = count(
      `SELECT user_id AS id, COUNT(*) AS n FROM community_posts WHERE hidden_at IS NULL AND visibility != 'private' AND user_id IN (${marks}) GROUP BY user_id`,
    );
    const followers = count(`SELECT followed_id AS id, COUNT(*) AS n FROM community_follows WHERE followed_id IN (${marks}) GROUP BY followed_id`);
    const mine = count(`SELECT followed_id AS id, 1 AS n FROM community_follows WHERE follower_id = ? AND followed_id IN (${marks})`, viewer);
    return rows.map((p) => ({
      userId: p.user_id,
      nickname: p.nickname,
      bio: p.bio,
      avatarUrl: avatarUrl(p.avatar_id),
      level: p.level ?? null,
      pronouns: p.pronouns ?? null,
      gym: sharedGym(p)?.name ?? null,
      sharedPosts: shared.get(p.user_id) ?? 0,
      followers: followers.get(p.user_id) ?? 0,
      followedByMe: mine.has(p.user_id),
    }));
  };

  const SELECT_POSTS = `SELECT p.*, cp.nickname, cp.avatar_id, cp.level, cp.pronouns FROM community_posts p LEFT JOIN community_profiles cp ON cp.user_id = p.user_id`;
  /** Posts `viewer` may see that are not their own; none from a member hidden by reports (#819, as their page and search). */
  const VISIBLE_TO_OTHERS = `cp.user_id IS NOT NULL AND ${visibleToOthersSql('p.user_id', 'p.visibility', 'p.hidden_at')} AND ${memberNotHiddenSql('p.user_id')}`;

  const toPosts = (rows: PostRow[], viewer: string) => {
    if (!rows.length) return [];
    const ids = rows.map((r) => r.id);
    const marks = ids.map(() => '?').join(',');
    const counts = db
      .prepare(`SELECT post_id, kind, COUNT(*) AS n, MAX(user_id = ?) AS mine FROM community_reactions WHERE post_id IN (${marks}) GROUP BY post_id, kind`)
      .all(viewer, ...ids) as { post_id: string; kind: string; n: number; mine: number }[];
    return rows.map((p) => {
      const rs = counts.filter((c) => c.post_id === p.id);
      return {
        id: p.id,
        author: { userId: p.user_id, nickname: p.nickname ?? 'member', avatarUrl: avatarUrl(p.avatar_id), level: p.level ?? null, pronouns: p.pronouns ?? null },
        mine: p.user_id === viewer,
        kind: p.kind,
        refId: p.ref_id,
        visibility: p.visibility,
        caption: p.caption,
        payload: JSON.parse(p.payload) as unknown,
        hidden: !!p.hidden_at,
        createdAt: p.created_at,
        reactions: Object.fromEntries(REACTIONS.map((k) => [k, rs.find((c) => c.kind === k)?.n ?? 0])),
        myReactions: rs.filter((c) => c.mine).map((c) => c.kind),
      };
    });
  };

  const visiblePost = (id: string, viewer: string) => {
    const row = db.prepare(`${SELECT_POSTS} WHERE p.id = ? AND (p.user_id = ? OR (${VISIBLE_TO_OTHERS}))`).get(id, viewer, viewer, viewer) as
      | PostRow
      | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Post not found.');
    return row;
  };

  // ───────────── account profile (#108): same nickname, photo and about, joined or not

  r.get('/me/public-profile', async (req) => ({ profile: accountProfile(req.userId!) }));

  /** Omitted fields are kept; empty or null clears (a member's nickname cannot be cleared). */
  r.put('/me/public-profile', async (req) => {
    const b = z.object({ nickname: z.string().trim().max(40).nullish(), bio: bio.nullish() }).parse(req.body);
    const uid = req.userId!;
    const nick = b.nickname === undefined ? undefined : b.nickname ? nickname.parse(b.nickname) : null;
    checkClean(nick, b.bio);
    if (nick) assertNicknameFree(nick, uid);
    await assertProfileClean(accountProfile(uid), nick, b.bio);
    const ts = now().toISOString();
    const member = profileRow(uid);
    if (member) {
      if (nick === null) throw new ApiError(400, 'nickname_required', 'Members need a nickname.');
      db.prepare('UPDATE community_profiles SET nickname = ?, bio = ?, updated_at = ? WHERE user_id = ?').run(
        nick ?? member.nickname, b.bio === undefined ? member.bio : (b.bio || null), ts, uid,
      );
    } else {
      const a = accountRow(uid);
      db.prepare(
        `INSERT INTO user_profiles (user_id, nickname, bio, avatar_id, updated_at) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET nickname = excluded.nickname, bio = excluded.bio, updated_at = excluded.updated_at`,
      ).run(uid, nick === undefined ? (a?.nickname ?? null) : nick, b.bio === undefined ? (a?.bio ?? null) : (b.bio || null), a?.avatar_id ?? null, ts);
    }
    return { profile: accountProfile(uid) };
  });

  r.put('/me/public-profile/avatar', async (req) => {
    const held = await storeAvatar(req.userId!, req.body);
    return { profile: accountProfile(req.userId!), held };
  });

  r.delete('/me/public-profile/avatar', async (req) => {
    clearAvatar(req.userId!);
    return { profile: accountProfile(req.userId!) };
  });

  // ───────────── profile

  r.get('/community/me', async (req) => {
    const p = profileRow(req.userId!);
    return { profile: p ? ownProfile(p) : null };
  });

  r.put('/community/me', async (req) => {
    const b = z
      .object({
        // Optional when the Account profile already has one (#108).
        nickname: nickname.optional(),
        bio: bio.nullish(),
        defaultVisibility: z.enum(VISIBILITIES).optional(),
        autoShare: z.boolean().optional(),
        showGym: z.boolean().optional(),
        acceptGuidelines: z.boolean().optional(),
      })
      .parse(req.body);
    checkClean(b.nickname, b.bio);
    const existing = profileRow(req.userId!);
    if (!existing && b.acceptGuidelines !== true)
      throw new ApiError(400, 'guidelines_required', 'Accept the community guidelines to join.');
    const account = existing ? undefined : accountRow(req.userId!);
    const nick = b.nickname ?? existing?.nickname ?? account?.nickname;
    if (!nick) throw new ApiError(400, 'nickname_required', 'Choose a nickname.');
    assertNicknameFree(nick, req.userId!);
    await assertProfileClean(existing ?? account ?? {}, nick, b.bio);
    const ts = now().toISOString();
    if (existing) {
      db.prepare(
        'UPDATE community_profiles SET nickname = ?, bio = ?, default_visibility = ?, auto_share = ?, show_gym = ?, updated_at = ? WHERE user_id = ?',
      ).run(
        nick,
        b.bio === undefined ? existing.bio : (b.bio || null),
        b.defaultVisibility ?? existing.default_visibility,
        b.autoShare === undefined ? existing.auto_share : Number(b.autoShare),
        b.showGym === undefined ? existing.show_gym : Number(b.showGym),
        ts,
        req.userId!,
      );
    } else {
      // New members share wins with members unless they pick otherwise, so followers get achievement pushes (#90).
      // The column default stays 'private'; existing profiles are left as they are.
      // The Account profile (#108) moves into the community profile: photo, and about unless sent.
      const about = b.bio === undefined ? (account?.bio ?? null) : (b.bio || null);
      tx(db, () => {
        db.prepare('DELETE FROM user_profiles WHERE user_id = ?').run(req.userId!);
        db.prepare(
          `INSERT INTO community_profiles (user_id, nickname, bio, avatar_id, default_visibility, auto_share, show_gym, guidelines_accepted_at, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).run(req.userId!, nick, about, account?.avatar_id ?? null, b.defaultVisibility ?? 'members', Number(b.autoShare ?? false), Number(b.showGym ?? false), ts, ts, ts);
        refreshMemberGym(db, req.userId!);
        followReferralPair(db, req.userId!, now());
      });
    }
    return { profile: ownProfile(profileRow(req.userId!)!) };
  });

  /**
   * Leave the community: posts, cheers given, follows, reports filed and the photo are deleted, shared workouts go back
   * to private (#432, #713). Blocks are kept. Nickname and about stay on Account (#108).
   */
  r.delete('/community/me', async (req, reply) => {
    const ts = now().toISOString();
    tx(db, () => {
      db.prepare(
        `INSERT INTO user_profiles (user_id, nickname, bio, avatar_id, updated_at)
         SELECT user_id, nickname, bio, NULL, ? FROM community_profiles WHERE user_id = ?
         ON CONFLICT(user_id) DO UPDATE SET nickname = excluded.nickname, bio = excluded.bio, avatar_id = NULL, updated_at = excluded.updated_at`,
      ).run(ts, req.userId!);
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_reports WHERE reporter_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_posts WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_programs WHERE user_id = ?').run(req.userId!);
      db.prepare("UPDATE custom_workouts SET visibility = 'private', shared_at = NULL, updated_at = ? WHERE user_id = ? AND visibility != 'private'").run(ts, req.userId!);
      db.prepare('DELETE FROM community_reactions WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_follows WHERE follower_id = ? OR followed_id = ?').run(req.userId!, req.userId!);
      leaveLive(db, req.userId!);
      db.prepare('DELETE FROM community_profiles WHERE user_id = ?').run(req.userId!);
    });
    return reply.status(204).send();
  });

  /** Game level (#242), computed on the device from workout history. */
  r.put('/community/me/level', async (req) => {
    const b = z.object({ level: z.number().int().min(1).max(999) }).parse(req.body);
    const p = profileRow(req.userId!);
    if (!p) throw new ApiError(404, 'not_member', 'Join the community first.');
    if (p.level !== b.level) db.prepare('UPDATE community_profiles SET level = ? WHERE user_id = ?').run(b.level, req.userId!);
    return { level: b.level };
  });

  /** Pronouns next to the nickname (#415); null hides them. The app sends them only when the member turns it on. */
  r.put('/community/me/pronouns', async (req) => {
    const b = z.object({ pronouns: z.string().trim().max(24).nullable() }).parse(req.body);
    const p = profileRow(req.userId!);
    if (!p) throw new ApiError(404, 'not_member', 'Join the community first.');
    const pronouns = b.pronouns || null;
    if (pronouns) checkClean(pronouns, null);
    db.prepare('UPDATE community_profiles SET pronouns = ? WHERE user_id = ?').run(pronouns, req.userId!);
    return { pronouns };
  });

  /** Social handles (#745): null or empty removes one; `visibility` everyone | following | nobody. */
  r.put('/community/me/socials', async (req) => {
    const b = z.object({ socials: socialsBody, visibility: z.enum(SOCIALS_VISIBILITIES).optional() }).parse(req.body);
    const p = profileRow(req.userId!);
    if (!p) throw new ApiError(404, 'not_member', 'Join the community first.');
    const socials = Object.fromEntries(Object.entries(b.socials).filter(([, v]) => v)) as Socials;
    db.prepare('UPDATE community_profiles SET socials = ?, socials_visibility = ?, updated_at = ? WHERE user_id = ?').run(
      Object.keys(socials).length ? JSON.stringify(socials) : null,
      b.visibility ?? p.socials_visibility,
      now().toISOString(),
      req.userId!,
    );
    return { socials, visibility: b.visibility ?? p.socials_visibility };
  });

  r.put('/community/me/avatar', async (req) => {
    requireProfile(req.userId!);
    const held = await storeAvatar(req.userId!, req.body);
    return { profile: ownProfile(profileRow(req.userId!)!), held };
  });

  r.delete('/community/me/avatar', async (req) => {
    requireProfile(req.userId!);
    clearAvatar(req.userId!);
    return { profile: ownProfile(profileRow(req.userId!)!) };
  });

  // ───────────── feed & posts

  r.get('/community/feed', async (req) => {
    const q = z
      .object({
        scope: z.enum(['members', 'mine', 'following']).default('members'),
        ...pageCursor,
        limit: z.coerce.number().int().min(1).max(50).default(20),
      })
      .parse(req.query);
    const viewer = req.userId!;
    requireProfile(viewer);
    const page = beforeSql('p.created_at', 'p.id', q);
    const order = `${page.sql} ORDER BY p.created_at DESC, p.id DESC LIMIT ?`;
    const rows = (
      q.scope === 'mine'
        ? db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? AND ${order}`).all(viewer, ...page.args, q.limit)
        : q.scope === 'following'
          ? db
              .prepare(
                `${SELECT_POSTS} WHERE p.user_id IN (SELECT followed_id FROM community_follows WHERE follower_id = ?) AND ${VISIBLE_TO_OTHERS}
                 AND ${order}`,
              )
              .all(viewer, viewer, viewer, ...page.args, q.limit)
          : db
            .prepare(`${SELECT_POSTS} WHERE (p.user_id = ? AND p.visibility != 'private' OR (${VISIBLE_TO_OTHERS})) AND ${order}`)
            .all(viewer, viewer, viewer, ...page.args, q.limit)
    ) as unknown as PostRow[];
    const last = rows.length === q.limit ? rows.at(-1)! : undefined;
    return { posts: toPosts(rows, viewer), nextBefore: last?.created_at ?? null, nextBeforeId: last?.id ?? null };
  });

  /** Hidden from others until reviewed (#871); the owner still sees it, marked hidden. */
  const holdPost = (userId: string, postId: string, category: HoldCategory, texts: (string | null | undefined)[]) => {
    db.prepare('UPDATE community_posts SET hidden_at = COALESCE(hidden_at, ?) WHERE id = ?').run(now().toISOString(), postId);
    mod.hold({ userId, type: 'post', id: postId, category, texts });
  };

  r.post('/community/posts', async (req) => {
    const b = z
      .object({
        id: z.uuid(),
        kind: z.enum(POST_KINDS),
        refId: text(64).min(1).nullish(),
        visibility: z.enum(VISIBILITIES).optional(),
        caption: caption.nullish(),
        payload,
      })
      .parse(req.body);
    const prof = requireProfile(req.userId!);
    const shownTexts = [b.caption, b.payload.title, b.payload.subtitle, ...(b.payload.exercises ?? []).map((e) => e.name)];
    checkClean(...shownTexts, b.payload.metric?.unit, ...(b.payload.stats ?? []).flatMap((s) => [s.label, s.value]));
    const id = b.id.toLowerCase();
    const owner = db.prepare('SELECT user_id FROM community_posts WHERE id = ?').get(id) as { user_id: string } | undefined;
    if (owner && owner.user_id !== req.userId) throw new ApiError(409, 'conflict', 'Post id already used.');
    const ts = now().toISOString();
    const json = JSON.stringify(b.payload);
    // Same workout/badge shared twice → update the existing post instead of duplicating it.
    const dup = b.refId
      ? (db.prepare('SELECT id FROM community_posts WHERE user_id = ? AND kind = ? AND ref_id = ?').get(req.userId!, b.kind, b.refId) as { id: string } | undefined)
      : undefined;
    const target = dup?.id ?? id;
    const existing = dup || owner
      ? (db.prepare('SELECT visibility, caption, payload FROM community_posts WHERE id = ?').get(target) as { visibility: Visibility; caption: string | null; payload: string })
      : undefined;
    const vis = b.visibility ?? existing?.visibility ?? prof.default_visibility;
    // AI check (#871) of what members read, only when it is new: an auto re-share of the same workout costs nothing.
    const old = existing ? (JSON.parse(existing.payload) as typeof b.payload) : undefined;
    const seen = new Set(old ? [existing!.caption, old.title, old.subtitle, ...(old.exercises ?? []).map((e) => e.name)] : []);
    const category = vis === 'private' ? null : await mod.check({ texts: shownTexts.filter((t) => !seen.has(t ?? null)) });
    if (existing) {
      // An update keeps the caption and visibility it doesn't send (#714): re-sharing a workout doesn't wipe the caption.
      const cap = b.caption === undefined ? existing.caption : b.caption || null;
      db.prepare('UPDATE community_posts SET visibility = ?, caption = ?, payload = ?, updated_at = ? WHERE id = ?').run(vis, cap, json, ts, target);
    } else {
      if (!throttleTake(db, `post:${req.userId!}`, POSTS_PER_DAY, DAY, now()))
        throw new ApiError(429, 'daily_limit', `That's ${POSTS_PER_DAY} posts today. Share more tomorrow!`);
      db.prepare(
        `INSERT INTO community_posts (id, user_id, kind, ref_id, visibility, caption, payload, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(id, req.userId!, b.kind, b.refId ?? null, vis, b.caption || null, json, ts, ts);
    }
    if (category) holdPost(req.userId!, target, category, shownTexts);
    return { post: toPosts([visiblePost(target, req.userId!)], req.userId!)[0] };
  });

  r.patch('/community/posts/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const b = z.object({ visibility: z.enum(VISIBILITIES).optional(), caption: caption.nullish() }).parse(req.body);
    checkClean(b.caption);
    const row = db.prepare('SELECT * FROM community_posts WHERE id = ? AND user_id = ?').get(id.toLowerCase(), req.userId!) as PostRow | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Post not found.');
    const category = b.caption && b.caption !== row.caption && (b.visibility ?? row.visibility) !== 'private' ? await mod.check({ texts: [b.caption] }) : null;
    if (category) holdPost(row.user_id, row.id, category, [b.caption]);
    db.prepare('UPDATE community_posts SET visibility = ?, caption = ?, updated_at = ? WHERE id = ?').run(
      b.visibility ?? row.visibility,
      b.caption === undefined ? row.caption : (b.caption || null),
      now().toISOString(),
      row.id,
    );
    return { post: toPosts([visiblePost(row.id, req.userId!)], req.userId!)[0] };
  });

  r.delete('/community/posts/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const owner = db.prepare('SELECT user_id FROM community_posts WHERE id = ?').get(id.toLowerCase()) as { user_id: string } | undefined;
    // Someone else's post is not found (#714); one already gone is (retries stay 204).
    if (owner && owner.user_id !== req.userId) throw new ApiError(404, 'not_found', 'Post not found.');
    db.prepare('DELETE FROM community_posts WHERE id = ? AND user_id = ?').run(id.toLowerCase(), req.userId!);
    return reply.status(204).send();
  });

  const reactionParams = z.object({ id: z.uuid(), kind: z.enum(REACTIONS) });

  r.put('/community/posts/:id/reactions/:kind', async (req) => {
    const p = reactionParams.parse(req.params);
    requireProfile(req.userId!);
    const row = visiblePost(p.id.toLowerCase(), req.userId!);
    if (row.user_id === req.userId) throw new ApiError(400, 'own_post', 'Cheer for others: you cannot react to your own post.');
    db.prepare('INSERT OR IGNORE INTO community_reactions (post_id, user_id, kind, created_at) VALUES (?, ?, ?, ?)').run(row.id, req.userId!, p.kind, now().toISOString());
    return { post: toPosts([row], req.userId!)[0] };
  });

  r.delete('/community/posts/:id/reactions/:kind', async (req) => {
    const p = reactionParams.parse(req.params);
    // A post the member can't see (hidden, blocked) answers 404 before anything changes (#714).
    const row = visiblePost(p.id.toLowerCase(), req.userId!);
    db.prepare('DELETE FROM community_reactions WHERE post_id = ? AND user_id = ? AND kind = ?').run(row.id, req.userId!, p.kind);
    return { post: toPosts([row], req.userId!)[0] };
  });

  // ───────────── members

  /**
   * Find members (#152): by nickname or shown gym name, members at your gym (`gym=mine`), or suggestions when `q` is empty.
   * Never yourself, anyone blocked either way, or a member hidden by reports.
   */
  r.get('/community/members', async (req) => {
    const p = z
      .object({
        q: z.string().trim().max(40).default(''),
        gym: z.enum(['mine']).optional(),
        limit: z.coerce.number().int().min(1).max(50).default(25),
      })
      .parse(req.query);
    const viewer = req.userId!;
    const me = requireProfile(viewer);
    const base = `FROM community_profiles cp
      WHERE cp.user_id != ? AND ${memberNotHiddenSql('cp.user_id')}
        AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = cp.user_id) OR (b.blocker_id = cp.user_id AND b.blocked_id = ?))`;
    const list = (rows: unknown) => ({ members: memberSummaries((rows as ProfileRow[]).slice(0, p.limit), viewer) });

    // Members at your gym: only those who show theirs, and only if you show yours. Same id or same name (indexed, #715);
    // sameGym checks the distance.
    if (p.gym === 'mine') {
      const mine = me.show_gym ? gymOf(me) : null;
      if (!mine) return { members: [] };
      const rows = db
        .prepare(`SELECT cp.* ${base} AND cp.show_gym = 1 AND (cp.gym_id = ? OR cp.gym_key = ?) ORDER BY cp.nickname`)
        .all(viewer, viewer, viewer, mine.id, nameKey(mine.name)) as unknown as ProfileRow[];
      return list(rows.filter((r) => { const g = gymOf(r); return !!g && sameGym(g, mine); }));
    }

    const q = p.q.toLowerCase();
    const nick = q.replace(/[^a-z0-9_.]/g, '');
    const likeNick = nick.replace(/[\\%_]/g, (c) => `\\${c}`);
    if (q) {
      // Nickname contains (prefix first, then shortest), then members who show a gym whose name contains the text.
      const byNick = nick
        ? db
            .prepare(
              `SELECT cp.* ${base} AND cp.nickname LIKE ? ESCAPE '\\'
               ORDER BY (cp.nickname LIKE ? ESCAPE '\\') DESC, length(cp.nickname), cp.nickname LIMIT ?`,
            )
            .all(viewer, viewer, viewer, `%${likeNick}%`, `${likeNick}%`, p.limit)
        : [];
      const seen = new Set((byNick as unknown as ProfileRow[]).map((r) => r.user_id));
      const gymText = nameKey(q);
      const byGym = gymText
        ? (db
            .prepare(`SELECT cp.* ${base} AND cp.show_gym = 1 AND instr(cp.gym_key, ?) > 0 ORDER BY cp.nickname LIMIT ?`)
            .all(viewer, viewer, viewer, gymText, p.limit + seen.size) as unknown as ProfileRow[]).filter((r) => !seen.has(r.user_id))
        : [];
      return list([...(byNick as unknown as ProfileRow[]), ...byGym]);
    }

    // Suggestions: not followed yet, most followed, then most shared.
    return list(
      db
        .prepare(
          `SELECT cp.* ${base}
             AND NOT EXISTS (SELECT 1 FROM community_follows f WHERE f.follower_id = ? AND f.followed_id = cp.user_id)
           ORDER BY (SELECT COUNT(*) FROM community_follows f WHERE f.followed_id = cp.user_id) DESC,
             (SELECT COUNT(*) FROM community_posts x WHERE x.user_id = cp.user_id AND x.hidden_at IS NULL AND x.visibility != 'private') DESC,
             cp.created_at DESC LIMIT ?`,
        )
        .all(viewer, viewer, viewer, viewer, p.limit),
    );
  });

  /**
   * Add a friend by their invite code (#747). 404 not_joined when the code is real but its owner hasn't joined Social,
   * so the app can say why instead of "not found". Same exclusions as search.
   */
  r.get('/community/members/by-code/:code', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req) => {
    const { code } = z.object({ code: z.string().trim().regex(/^[A-Za-z0-9]{4,12}$/) }).parse(req.params);
    const viewer = req.userId!;
    requireProfile(viewer);
    const owner = referralOwner(db, code);
    if (!owner) throw new ApiError(404, 'invalid_code', 'No member with that code.');
    if (owner === viewer) throw new ApiError(400, 'own_code', "That's your own code.");
    const row = db
      .prepare(`SELECT cp.* FROM community_profiles cp WHERE cp.user_id = ? AND ${memberNotHiddenSql('cp.user_id')}`)
      .get(owner) as ProfileRow | undefined;
    if (!row) throw new ApiError(404, 'not_joined', "Your friend hasn't joined Social yet. Ask them to open Social and tap Join.");
    if (blockedBetween(viewer, owner)) throw new ApiError(404, 'invalid_code', 'No member with that code.');
    return { member: memberSummaries([row], viewer)[0] };
  });

  r.get('/community/members/:userId', async (req) => {
    const { userId } = z.object({ userId: z.string().min(1).max(64) }).parse(req.params);
    const viewer = req.userId!;
    requireProfile(viewer);
    const p = profileRow(userId);
    // Hidden by reports (#713): their page is gone for others, as in search; the member still sees their own.
    const hidden = () => !db.prepare(`SELECT 1 WHERE ${memberNotHiddenSql('?')}`).get(userId);
    if (!p || (userId !== viewer && (blockedBetween(viewer, userId) || hidden()))) throw new ApiError(404, 'not_found', 'Member not found.');
    const rows = (
      userId === viewer
        ? db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? ORDER BY p.created_at DESC LIMIT 30`).all(viewer)
        : db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? AND ${VISIBLE_TO_OTHERS} ORDER BY p.created_at DESC LIMIT 30`).all(userId, viewer, viewer)
    ) as unknown as PostRow[];
    const blocked = !!db.prepare('SELECT 1 FROM community_blocks WHERE blocker_id = ? AND blocked_id = ?').get(viewer, userId);
    const following = !!db.prepare('SELECT 1 FROM community_follows WHERE follower_id = ? AND followed_id = ?').get(viewer, userId);
    return { member: memberProfile(p, viewer), posts: toPosts(rows, viewer), blockedByMe: blocked, followedByMe: following };
  });

  // ───────────── follows

  /**
   * Members you follow, by nickname (#715): `limit` (default and max 500) per page, `after` = the last page's
   * `nextAfter` (null on the last page). Apps that send neither get the first 500, as one list as before.
   */
  r.get('/community/follows', async (req) => {
    const q = z.object({ limit: z.coerce.number().int().min(1).max(500).default(500), after: nickname.optional() }).parse(req.query);
    const rows = db
      .prepare(
        `SELECT cp.* FROM community_follows f JOIN community_profiles cp ON cp.user_id = f.followed_id
         WHERE f.follower_id = ? AND (? IS NULL OR cp.nickname > ?) ORDER BY cp.nickname LIMIT ?`,
      )
      .all(req.userId!, q.after ?? null, q.after ?? null, q.limit + 1) as unknown as ProfileRow[];
    const page = rows.slice(0, q.limit);
    return { following: memberSummaries(page, req.userId!), nextAfter: rows.length > q.limit ? page.at(-1)!.nickname : null };
  });

  r.put('/community/follows/:userId', async (req, reply) => {
    const { userId } = z.object({ userId: z.string().min(1).max(64) }).parse(req.params);
    requireProfile(req.userId!);
    if (userId === req.userId) throw new ApiError(400, 'own_content', 'You cannot follow yourself.');
    if (!profileRow(userId) || blockedBetween(req.userId!, userId)) throw new ApiError(404, 'not_found', 'Member not found.');
    db.prepare('INSERT OR IGNORE INTO community_follows (follower_id, followed_id, created_at) VALUES (?, ?, ?)').run(req.userId!, userId, now().toISOString());
    return reply.status(204).send();
  });

  r.delete('/community/follows/:userId', async (req, reply) => {
    const { userId } = z.object({ userId: z.string().min(1).max(64) }).parse(req.params);
    db.prepare('DELETE FROM community_follows WHERE follower_id = ? AND followed_id = ?').run(req.userId!, userId);
    return reply.status(204).send();
  });

  // ───────────── moderation: report & block

  r.post('/community/reports', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req, reply) => {
    const b = z
      .object({ postId: z.uuid().optional(), userId: z.string().min(1).max(64).optional(), reason: z.enum(REPORT_REASONS), details: text(500).nullish() })
      .refine((x) => x.postId || x.userId, 'postId or userId required')
      .parse(req.body);
    const reporter = req.userId!;
    let target = b.userId ?? null;
    let postId: string | null = null;
    if (b.postId) {
      const row = visiblePost(b.postId.toLowerCase(), reporter);
      postId = row.id;
      target = row.user_id;
    } else if (!profileRow(b.userId!)) throw new ApiError(404, 'not_found', 'Member not found.');
    const ts = now().toISOString();
    let hidden = false;
    tx(db, () => {
      const n = reportContent(db, { reporterId: reporter, targetType: postId ? 'post' : null, targetId: postId, targetUserId: target, reason: b.reason, details: b.details, at: ts });
      if (postId && n >= AUTO_HIDE_REPORTS)
        hidden = Number(db.prepare('UPDATE community_posts SET hidden_at = ? WHERE id = ? AND hidden_at IS NULL').run(ts, postId).changes) > 0;
    });
    if (moderationEmail)
      mailer
        .send({
          to: moderationEmail,
          subject: `Community report: ${b.reason}${hidden ? ' (post auto-hidden)' : ''}`,
          text: [`Reporter: ${reporter}`, `Member: ${target}`, `Post: ${postId ?? '-'}`, `Reason: ${b.reason}`, `Details: ${b.details ?? '-'}`, `At: ${ts}`].join('\n'),
        })
        .catch((e: unknown) => req.log.warn(`moderation mail failed: ${String(e)}`));
    return reply.status(202).send({ status: 'received', hidden });
  });

  r.get('/community/blocks', async (req) => ({
    blocked: db
      .prepare(
        `SELECT b.blocked_id AS userId, cp.nickname, cp.avatar_id, b.created_at AS blockedAt FROM community_blocks b
         LEFT JOIN community_profiles cp ON cp.user_id = b.blocked_id WHERE b.blocker_id = ? ORDER BY b.created_at DESC`,
      )
      .all(req.userId!)
      .map((x) => {
        const r = x as { userId: string; nickname: string | null; avatar_id: string | null; blockedAt: string };
        return { userId: r.userId, nickname: r.nickname ?? 'member', avatarUrl: avatarUrl(r.avatar_id), blockedAt: r.blockedAt };
      }),
  }));

  r.post('/community/blocks', async (req, reply) => {
    const b = z.object({ userId: z.string().min(1).max(64) }).parse(req.body);
    if (b.userId === req.userId) throw new ApiError(400, 'own_content', 'You cannot block yourself.');
    if (!db.prepare('SELECT 1 FROM users WHERE id = ?').get(b.userId)) throw new ApiError(404, 'not_found', 'Member not found.');
    tx(db, () => {
      db.prepare('INSERT OR IGNORE INTO community_blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)').run(req.userId!, b.userId, now().toISOString());
      db.prepare('DELETE FROM community_follows WHERE (follower_id = ? AND followed_id = ?) OR (follower_id = ? AND followed_id = ?)').run(
        req.userId!, b.userId, b.userId, req.userId!,
      );
      unpair(db, req.userId!, b.userId);
    });
    return reply.status(204).send();
  });

  r.delete('/community/blocks/:userId', async (req, reply) => {
    const { userId } = z.object({ userId: z.string().min(1).max(64) }).parse(req.params);
    db.prepare('DELETE FROM community_blocks WHERE blocker_id = ? AND blocked_id = ?').run(req.userId!, userId);
    return reply.status(204).send();
  });
};

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** Unauthenticated: avatars (unguessable ids) and the share page of public posts. */
export const communityPublicRoutes = (app: FastifyInstance, db: DB, appName: string) => {
  app.get('/v1/community/avatars/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const row = db.prepare('SELECT data FROM community_avatars WHERE id = ?').get(id) as { data: Uint8Array } | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Not found.');
    return reply
      .header('Content-Type', 'image/jpeg')
      .header('Cache-Control', 'public, max-age=31536000, immutable')
      .header('X-Content-Type-Options', 'nosniff')
      .send(Buffer.from(row.data));
  });

  app.get('/share/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const p = db
      .prepare(
        `SELECT p.caption, p.payload, p.created_at, cp.nickname, cp.avatar_id FROM community_posts p JOIN community_profiles cp ON cp.user_id = p.user_id
         WHERE p.id = ? AND p.visibility = 'public' AND p.hidden_at IS NULL AND ${memberNotHiddenSql('p.user_id')}`,
      )
      .get(id.toLowerCase()) as { caption: string | null; payload: string; created_at: string; nickname: string; avatar_id: string | null } | undefined;
    reply.header('Content-Type', 'text/html; charset=utf-8').header('X-Content-Type-Options', 'nosniff')
      .header('Content-Security-Policy', "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'");
    if (!p) return reply.status(404).send(`<!doctype html><meta charset="utf-8"><title>${esc(appName)}</title><p>This post is not public.</p>`);
    const d = JSON.parse(p.payload) as z.infer<typeof payload>;
    const avatar = p.avatar_id ? `<img src="/v1/community/avatars/${p.avatar_id}" alt="">` : '';
    const stats = (d.stats ?? []).map((s) => `<span><b>${esc(s.value)}</b> ${esc(s.label)}</span>`).join('');
    return reply.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(p.nickname)} on ${esc(appName)}</title><meta property="og:title" content="${esc(p.nickname)}: ${esc(d.title)}">
<style>body{margin:0;background:#090a0e;color:#fff;font-family:-apple-system,system-ui,sans-serif;display:flex;justify-content:center;padding:24px}
.c{max-width:420px;width:100%;border-radius:28px;padding:22px;background:linear-gradient(135deg,#2F6BFF,#8A4DFF)}
.a{display:flex;align-items:center;gap:10px;font-weight:800}.a img{width:40px;height:40px;border-radius:50%;border:2px solid #fff}
h1{font-size:34px;font-weight:900;margin:14px 0 4px;line-height:1}.m{font-size:48px;font-weight:900}.m small{font-size:13px;letter-spacing:1px;text-transform:uppercase;opacity:.85}
.s{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}.s span{background:#ffffff2e;border-radius:14px;padding:6px 10px;font-size:13px}
p{opacity:.92}footer{margin-top:18px;font-size:12px;opacity:.7}</style></head>
<body><div class="c"><div class="a">${avatar}${esc(p.nickname)}</div><h1>${esc(d.title)}</h1>${d.subtitle ? `<div>${esc(d.subtitle)}</div>` : ''}
${d.metric ? `<div class="m">${esc(d.metric.value)} <small>${esc(d.metric.unit)}</small></div>` : ''}<div class="s">${stats}</div>
${p.caption ? `<p>${esc(p.caption)}</p>` : ''}<footer>${esc(appName)} · ${esc(p.created_at.slice(0, 10))}</footer></div></body></html>`);
  });
};
