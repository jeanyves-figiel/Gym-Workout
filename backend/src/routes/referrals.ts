import { randomInt } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';

/**
 * Invite a friend (#745): every account has a short code; a new account enters a friend's code once. The app shows a
 * reward ladder from the counts (joined, subscribed). Subscribed = a paid (not trial, not revoked) App Store
 * subscription, so trials can't farm the Pro reward. Pro months go out as App Store offer codes, never server-side Pro.
 */

/** No 0/O, 1/I/L: codes are read aloud and typed. */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 7;
/** A code can only be entered by an account this new: referrals are for people who just got the app. */
export const REDEEM_WINDOW_DAYS = 14;

const codeParam = z.string().trim().toUpperCase().regex(/^[A-Z0-9]{4,12}$/);

export const ensureReferralSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS referral_codes (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      code TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS referrals (
      invitee_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      referrer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS referrals_referrer ON referrals(referrer_id);
  `);
};

const newCode = () => Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');

/** The member's code, made on first use. */
export const referralCode = (db: DB, userId: string, now: Date): string => {
  const row = db.prepare('SELECT code FROM referral_codes WHERE user_id = ?').get(userId) as { code: string } | undefined;
  if (row) return row.code;
  for (;;) {
    const code = newCode();
    const r = db.prepare('INSERT INTO referral_codes (user_id, code, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING').run(userId, code, now.toISOString());
    if (r.changes) return code;
    const again = db.prepare('SELECT code FROM referral_codes WHERE user_id = ?').get(userId) as { code: string } | undefined;
    if (again) return again.code;
  }
};

const nicknameOf = (db: DB, userId: string) =>
  (
    (db.prepare('SELECT nickname FROM community_profiles WHERE user_id = ?').get(userId) ??
      db.prepare('SELECT nickname FROM user_profiles WHERE user_id = ?').get(userId)) as { nickname: string | null } | undefined
  )?.nickname ?? null;

const PAID = `EXISTS (SELECT 1 FROM app_store_subscriptions s WHERE s.user_id = r.invitee_id AND s.trial = 0 AND s.revoked_at IS NULL)`;

export const referralRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  const summary = (userId: string) => {
    const code = referralCode(db, userId, now());
    const counts = db
      .prepare(`SELECT COUNT(*) AS joined, COALESCE(SUM(${PAID}), 0) AS subscribed FROM referrals r WHERE r.referrer_id = ?`)
      .get(userId) as { joined: number; subscribed: number };
    const by = db.prepare('SELECT referrer_id, created_at FROM referrals WHERE invitee_id = ?').get(userId) as
      | { referrer_id: string; created_at: string }
      | undefined;
    const user = db.prepare('SELECT created_at FROM users WHERE id = ?').get(userId) as { created_at: string };
    const age = now().getTime() - Date.parse(user.created_at);
    return {
      code,
      // Server-relative like avatars; the app resolves it against its API host.
      path: `/i/${code}`,
      joined: Number(counts.joined),
      subscribed: Number(counts.subscribed),
      invitedBy: by ? { nickname: nicknameOf(db, by.referrer_id), at: by.created_at } : null,
      canRedeem: !by && age <= REDEEM_WINDOW_DAYS * 86_400_000,
    };
  };

  r.get('/referrals/me', async (req) => summary(req.userId!));

  r.post('/referrals/redeem', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (req) => {
    const b = z.object({ code: codeParam }).parse(req.body);
    const me = req.userId!;
    const owner = db.prepare('SELECT user_id FROM referral_codes WHERE code = ?').get(b.code) as { user_id: string } | undefined;
    if (!owner) throw new ApiError(404, 'invalid_code', 'No invite with that code.');
    if (owner.user_id === me) throw new ApiError(400, 'own_code', "That's your own code.");
    const s = summary(me);
    if (s.invitedBy) throw new ApiError(409, 'already_redeemed', 'You already used an invite code.');
    if (!s.canRedeem) throw new ApiError(400, 'account_too_old', `Invite codes work in your first ${REDEEM_WINDOW_DAYS} days.`);
    // Two accounts can't invite each other.
    if (db.prepare('SELECT 1 FROM referrals WHERE invitee_id = ? AND referrer_id = ?').get(owner.user_id, me))
      throw new ApiError(400, 'referral_cycle', 'You invited this member.');
    db.prepare('INSERT INTO referrals (invitee_id, referrer_id, created_at) VALUES (?, ?, ?)').run(me, owner.user_id, now().toISOString());
    return summary(me);
  });
};

/** Data export: own code, who invited you, and when your invitees joined (not who they are). */
export const referralExport = (db: DB, userId: string) => ({
  code: (db.prepare('SELECT code FROM referral_codes WHERE user_id = ?').get(userId) as { code: string } | undefined)?.code ?? null,
  invitedAt: (db.prepare('SELECT created_at FROM referrals WHERE invitee_id = ?').get(userId) as { created_at: string } | undefined)?.created_at ?? null,
  invitesJoinedAt: (db.prepare('SELECT created_at FROM referrals WHERE referrer_id = ? ORDER BY created_at').all(userId) as { created_at: string }[]).map((r) => r.created_at),
});

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** Unauthenticated invite page behind the shared link: the code, and where to get the app. */
export const referralPublicRoutes = (app: FastifyInstance, db: DB, appName: string, appUrl: string) => {
  app.get('/i/:code', async (req, reply) => {
    const parsed = codeParam.safeParse((req.params as { code?: string }).code);
    const row = parsed.success
      ? (db.prepare('SELECT user_id FROM referral_codes WHERE code = ?').get(parsed.data) as { user_id: string } | undefined)
      : undefined;
    reply.header('Content-Type', 'text/html; charset=utf-8').header('X-Content-Type-Options', 'nosniff')
      .header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'");
    if (!row || !parsed.success) return reply.status(404).send(`<!doctype html><meta charset="utf-8"><title>${esc(appName)}</title><p>This invite doesn't exist.</p>`);
    const who = nicknameOf(db, row.user_id);
    const title = who ? `${who} invites you to ${appName}` : `You're invited to ${appName}`;
    return reply.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta property="og:title" content="${esc(title)}"><meta property="og:description" content="Train together. Use code ${esc(parsed.data)}.">
<style>body{margin:0;background:#090a0e;color:#fff;font-family:-apple-system,system-ui,sans-serif;display:flex;justify-content:center;padding:24px}
.c{max-width:420px;width:100%;border-radius:28px;padding:24px;background:linear-gradient(135deg,#FF2D87,#FF9A3C)}
h1{font-size:32px;font-weight:900;margin:6px 0 10px;line-height:1.05}.k{font-size:11px;letter-spacing:2px;font-weight:800;opacity:.85}
.code{font:900 34px Menlo,monospace;letter-spacing:4px;background:#0003;border-radius:16px;padding:12px;text-align:center;margin:16px 0}
a{display:block;text-align:center;background:#C8FF3C;color:#111;font-weight:900;border-radius:16px;padding:14px;text-decoration:none}
p{opacity:.92}</style></head>
<body><div class="c"><div class="k">GIVE 1 · GET 1</div><h1>${esc(title)}</h1>
<p>Get the app, then enter this code in Social → Invite. You both unlock rewards as you train together.</p>
<div class="code">${esc(parsed.data)}</div><a href="${esc(appUrl)}">Get ${esc(appName)}</a></div></body></html>`);
  });
};
