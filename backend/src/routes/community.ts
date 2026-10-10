import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { isObjectionable } from '../community/filter.ts';
import { AVATAR_MAX_BYTES, sanitizeJpeg } from '../community/image.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { Mailer } from '../mailer.ts';

/** Community (#61): profiles, shared progress posts, cheers, report + block. */

export const VISIBILITIES = ['private', 'members', 'public'] as const;
export const REACTIONS = ['like', 'strong', 'fire', 'clap'] as const;
const POST_KINDS = ['workout', 'badge', 'record', 'climb', 'note'] as const;
const REPORT_REASONS = ['spam', 'harassment', 'hate', 'sexual', 'violence', 'other'] as const;
/** Distinct reporters after which a post is hidden pending review. */
export const AUTO_HIDE_REPORTS = 3;

type Visibility = (typeof VISIBILITIES)[number];

interface ProfileRow {
  user_id: string;
  nickname: string;
  bio: string | null;
  avatar_id: string | null;
  default_visibility: Visibility;
  auto_share: number;
  guidelines_accepted_at: string;
  created_at: string;
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
}

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
});

const checkClean = (...texts: (string | null | undefined)[]) => {
  if (texts.some(isObjectionable))
    throw new ApiError(400, 'objectionable_content', 'Please keep it friendly: that text is not allowed in the community.');
};

export const communityExport = (db: DB, userId: string) => ({
  profile: (db.prepare('SELECT nickname, bio, default_visibility, auto_share, guidelines_accepted_at, created_at FROM community_profiles WHERE user_id = ?').get(userId) ?? null),
  posts: (db.prepare('SELECT id, kind, ref_id, visibility, caption, payload, hidden_at, created_at FROM community_posts WHERE user_id = ? ORDER BY created_at').all(userId) as unknown as { payload: string }[]).map(
    (p) => ({ ...p, payload: JSON.parse(p.payload) as unknown }),
  ),
  reactionsGiven: db.prepare('SELECT post_id, kind, created_at FROM community_reactions WHERE user_id = ?').all(userId),
  blocked: db.prepare('SELECT blocked_id, created_at FROM community_blocks WHERE blocker_id = ?').all(userId),
});

export const communityRoutes = (r: FastifyInstance, db: DB, now: () => Date, mailer: Mailer, moderationEmail?: string) => {
  r.addContentTypeParser('image/jpeg', { parseAs: 'buffer', bodyLimit: AVATAR_MAX_BYTES + 1024 }, (_req, body, done) => done(null, body));

  const profileRow = (userId: string) =>
    db.prepare('SELECT * FROM community_profiles WHERE user_id = ?').get(userId) as ProfileRow | undefined;

  const requireProfile = (userId: string) => {
    const p = profileRow(userId);
    if (!p) throw new ApiError(403, 'community_profile_required', 'Create your community profile first.');
    return p;
  };

  /** Either side blocked the other. */
  const blockedBetween = (a: string, b: string) =>
    !!db.prepare('SELECT 1 FROM community_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)').get(a, b, b, a);

  const stats = (userId: string) => {
    const s = db
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM community_posts WHERE user_id = ? AND hidden_at IS NULL AND visibility != 'private') AS shared,
           (SELECT COUNT(*) FROM community_reactions cr JOIN community_posts p ON p.id = cr.post_id WHERE p.user_id = ?) AS cheers`,
      )
      .get(userId, userId) as { shared: number; cheers: number };
    return { sharedPosts: s.shared, cheersReceived: s.cheers };
  };

  const ownProfile = (p: ProfileRow) => ({
    userId: p.user_id,
    nickname: p.nickname,
    bio: p.bio,
    avatarUrl: avatarUrl(p.avatar_id),
    defaultVisibility: p.default_visibility,
    autoShare: !!p.auto_share,
    guidelinesAcceptedAt: p.guidelines_accepted_at,
    ...stats(p.user_id),
  });

  const memberProfile = (p: ProfileRow) => ({
    userId: p.user_id,
    nickname: p.nickname,
    bio: p.bio,
    avatarUrl: avatarUrl(p.avatar_id),
    createdAt: p.created_at,
    ...stats(p.user_id),
  });

  const SELECT_POSTS = `SELECT p.*, cp.nickname, cp.avatar_id FROM community_posts p LEFT JOIN community_profiles cp ON cp.user_id = p.user_id`;
  /** Posts `viewer` may see that are not their own. */
  const VISIBLE_TO_OTHERS = `p.hidden_at IS NULL AND p.visibility IN ('members', 'public') AND cp.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = p.user_id) OR (b.blocker_id = p.user_id AND b.blocked_id = ?))`;

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
        author: { userId: p.user_id, nickname: p.nickname ?? 'member', avatarUrl: avatarUrl(p.avatar_id) },
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

  // ───────────── profile

  r.get('/community/me', async (req) => {
    const p = profileRow(req.userId!);
    return { profile: p ? ownProfile(p) : null };
  });

  r.put('/community/me', async (req) => {
    const b = z
      .object({
        nickname,
        bio: bio.nullish(),
        defaultVisibility: z.enum(VISIBILITIES).optional(),
        autoShare: z.boolean().optional(),
        acceptGuidelines: z.boolean().optional(),
      })
      .parse(req.body);
    checkClean(b.nickname, b.bio);
    const existing = profileRow(req.userId!);
    if (!existing && b.acceptGuidelines !== true)
      throw new ApiError(400, 'guidelines_required', 'Accept the community guidelines to join.');
    const taken = db.prepare('SELECT user_id FROM community_profiles WHERE nickname = ? AND user_id != ?').get(b.nickname, req.userId!);
    if (taken) throw new ApiError(409, 'nickname_taken', 'That nickname is taken.');
    const ts = now().toISOString();
    if (existing) {
      db.prepare(
        'UPDATE community_profiles SET nickname = ?, bio = ?, default_visibility = ?, auto_share = ?, updated_at = ? WHERE user_id = ?',
      ).run(
        b.nickname,
        b.bio === undefined ? existing.bio : (b.bio || null),
        b.defaultVisibility ?? existing.default_visibility,
        b.autoShare === undefined ? existing.auto_share : Number(b.autoShare),
        ts,
        req.userId!,
      );
    } else {
      db.prepare(
        `INSERT INTO community_profiles (user_id, nickname, bio, default_visibility, auto_share, guidelines_accepted_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(req.userId!, b.nickname, b.bio || null, b.defaultVisibility ?? 'private', Number(b.autoShare ?? false), ts, ts, ts);
    }
    return { profile: ownProfile(profileRow(req.userId!)!) };
  });

  /** Leave the community: profile, photo, posts and cheers given are deleted. Blocks are kept. */
  r.delete('/community/me', async (req, reply) => {
    tx(db, () => {
      db.prepare('DELETE FROM community_posts WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_reactions WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(req.userId!);
      db.prepare('DELETE FROM community_profiles WHERE user_id = ?').run(req.userId!);
    });
    return reply.status(204).send();
  });

  r.put('/community/me/avatar', async (req) => {
    requireProfile(req.userId!);
    if (!Buffer.isBuffer(req.body)) throw new ApiError(415, 'unsupported_media_type', 'Send the photo as image/jpeg.');
    const img = sanitizeJpeg(req.body);
    const id = randomUUID();
    tx(db, () => {
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(req.userId!);
      db.prepare('INSERT INTO community_avatars (id, user_id, data, created_at) VALUES (?, ?, ?, ?)').run(id, req.userId!, img.data, now().toISOString());
      db.prepare('UPDATE community_profiles SET avatar_id = ?, updated_at = ? WHERE user_id = ?').run(id, now().toISOString(), req.userId!);
    });
    return { profile: ownProfile(profileRow(req.userId!)!) };
  });

  r.delete('/community/me/avatar', async (req) => {
    requireProfile(req.userId!);
    tx(db, () => {
      db.prepare('DELETE FROM community_avatars WHERE user_id = ?').run(req.userId!);
      db.prepare('UPDATE community_profiles SET avatar_id = NULL, updated_at = ? WHERE user_id = ?').run(now().toISOString(), req.userId!);
    });
    return { profile: ownProfile(profileRow(req.userId!)!) };
  });

  // ───────────── feed & posts

  r.get('/community/feed', async (req) => {
    const q = z
      .object({
        scope: z.enum(['members', 'mine']).default('members'),
        before: z.iso.datetime({ offset: true }).optional(),
        limit: z.coerce.number().int().min(1).max(50).default(20),
      })
      .parse(req.query);
    const viewer = req.userId!;
    requireProfile(viewer);
    const before = q.before ?? '9999';
    const rows = (
      q.scope === 'mine'
        ? db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`).all(viewer, before, q.limit)
        : db
            .prepare(`${SELECT_POSTS} WHERE (p.user_id = ? AND p.visibility != 'private' OR (${VISIBLE_TO_OTHERS})) AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`)
            .all(viewer, viewer, viewer, before, q.limit)
    ) as unknown as PostRow[];
    return { posts: toPosts(rows, viewer), nextBefore: rows.length === q.limit ? rows.at(-1)!.created_at : null };
  });

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
    checkClean(b.caption, b.payload.title, b.payload.subtitle, b.payload.metric?.unit, ...(b.payload.stats ?? []).flatMap((s) => [s.label, s.value]));
    const id = b.id.toLowerCase();
    const owner = db.prepare('SELECT user_id FROM community_posts WHERE id = ?').get(id) as { user_id: string } | undefined;
    if (owner && owner.user_id !== req.userId) throw new ApiError(409, 'conflict', 'Post id already used.');
    const ts = now().toISOString();
    const vis = b.visibility ?? prof.default_visibility;
    const json = JSON.stringify(b.payload);
    // Same workout/badge shared twice → update the existing post instead of duplicating it.
    const dup = b.refId
      ? (db.prepare('SELECT id FROM community_posts WHERE user_id = ? AND kind = ? AND ref_id = ?').get(req.userId!, b.kind, b.refId) as { id: string } | undefined)
      : undefined;
    const target = dup?.id ?? id;
    if (dup || owner) {
      db.prepare('UPDATE community_posts SET visibility = ?, caption = ?, payload = ?, updated_at = ? WHERE id = ?').run(vis, b.caption || null, json, ts, target);
    } else {
      db.prepare(
        `INSERT INTO community_posts (id, user_id, kind, ref_id, visibility, caption, payload, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(id, req.userId!, b.kind, b.refId ?? null, vis, b.caption || null, json, ts, ts);
    }
    return { post: toPosts([visiblePost(target, req.userId!)], req.userId!)[0] };
  });

  r.patch('/community/posts/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const b = z.object({ visibility: z.enum(VISIBILITIES).optional(), caption: caption.nullish() }).parse(req.body);
    checkClean(b.caption);
    const row = db.prepare('SELECT * FROM community_posts WHERE id = ? AND user_id = ?').get(id.toLowerCase(), req.userId!) as PostRow | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Post not found.');
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
    db.prepare('DELETE FROM community_reactions WHERE post_id = ? AND user_id = ? AND kind = ?').run(p.id.toLowerCase(), req.userId!, p.kind);
    return { post: toPosts([visiblePost(p.id.toLowerCase(), req.userId!)], req.userId!)[0] };
  });

  // ───────────── members

  r.get('/community/members/:userId', async (req) => {
    const { userId } = z.object({ userId: z.string().min(1).max(64) }).parse(req.params);
    const viewer = req.userId!;
    requireProfile(viewer);
    const p = profileRow(userId);
    if (!p || (userId !== viewer && blockedBetween(viewer, userId))) throw new ApiError(404, 'not_found', 'Member not found.');
    const rows = (
      userId === viewer
        ? db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? ORDER BY p.created_at DESC LIMIT 30`).all(viewer)
        : db.prepare(`${SELECT_POSTS} WHERE p.user_id = ? AND ${VISIBLE_TO_OTHERS} ORDER BY p.created_at DESC LIMIT 30`).all(userId, viewer, viewer)
    ) as unknown as PostRow[];
    const blocked = !!db.prepare('SELECT 1 FROM community_blocks WHERE blocker_id = ? AND blocked_id = ?').get(viewer, userId);
    return { member: memberProfile(p), posts: toPosts(rows, viewer), blockedByMe: blocked };
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
    if (target === reporter) throw new ApiError(400, 'own_content', 'You cannot report yourself.');
    const ts = now().toISOString();
    let hidden = false;
    tx(db, () => {
      db.prepare('INSERT INTO community_reports (id, reporter_id, post_id, target_user_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
        randomUUID(), reporter, postId, target, b.reason, b.details || null, ts,
      );
      if (postId) {
        const n = (db.prepare('SELECT COUNT(DISTINCT reporter_id) AS n FROM community_reports WHERE post_id = ? AND resolved_at IS NULL').get(postId) as { n: number }).n;
        if (n >= AUTO_HIDE_REPORTS) hidden = Number(db.prepare('UPDATE community_posts SET hidden_at = ? WHERE id = ? AND hidden_at IS NULL').run(ts, postId).changes) > 0;
      }
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
    db.prepare('INSERT OR IGNORE INTO community_blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)').run(req.userId!, b.userId, now().toISOString());
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
         WHERE p.id = ? AND p.visibility = 'public' AND p.hidden_at IS NULL`,
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
