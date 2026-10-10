import type { DB } from './db.ts';

export interface PurgeResult {
  codes: number;
  emailChanges: number;
  refreshTokens: number;
}

/** Revoked refresh tokens are kept this long so replay detection can still revoke a live family. */
const REVOKED_GRACE_MS = 24 * 3_600_000;

/**
 * Deletes expired email codes, expired pending email changes, expired refresh tokens, and revoked
 * refresh tokens whose family has no live token left (nothing to protect any more).
 */
export const purgeExpired = (db: DB, now: Date = new Date()): PurgeResult => {
  const iso = now.toISOString();
  const cutoff = new Date(now.getTime() - REVOKED_GRACE_MS).toISOString();
  const codes = Number(db.prepare('DELETE FROM codes WHERE expires_at <= ?').run(iso).changes);
  const emailChanges = Number(db.prepare('DELETE FROM email_changes WHERE expires_at <= ?').run(iso).changes);
  const refreshTokens = Number(
    db
      .prepare(
        `DELETE FROM refresh_tokens
         WHERE expires_at <= ?
            OR (revoked_at IS NOT NULL AND revoked_at <= ?
                AND family_id NOT IN (SELECT family_id FROM refresh_tokens WHERE revoked_at IS NULL AND expires_at > ?))`,
      )
      .run(iso, cutoff, iso).changes,
  );
  return { codes, emailChanges, refreshTokens };
};

/** Runs `purgeExpired` now and then every `intervalMs` (0 → only once). Returns a stop function. */
export const startPurgeJob = (
  db: DB,
  opts: { intervalMs: number; now?: () => Date; log?: (msg: string) => void },
): (() => void) => {
  const run = () => {
    try {
      const r = purgeExpired(db, opts.now?.() ?? new Date());
      if (r.codes || r.emailChanges || r.refreshTokens)
        opts.log?.(`purge: ${r.codes} codes, ${r.emailChanges} email changes, ${r.refreshTokens} refresh tokens`);
    } catch (e) {
      opts.log?.(`purge failed: ${(e as Error).message}`);
    }
  };
  run();
  if (!(opts.intervalMs > 0)) return () => {};
  const timer = setInterval(run, opts.intervalMs);
  timer.unref();
  return () => clearInterval(timer);
};
