import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createAppleVerifier } from '../apple.ts';
import { AppleTokenService } from '../appleTokens.ts';
import { AuthService } from '../auth.ts';
import { loadConfig } from '../config.ts';
import { type DB, openDb } from '../db.ts';
import { createMailer } from '../mailer.ts';

/**
 * Deletes a member's account on request by email (#315), for members who can't use the app.
 * Same path as Account → Delete account: every row goes (ON DELETE CASCADE), Sign in with Apple is
 * revoked, the member gets the "account deleted" email. Dry run lists what would go.
 * Run via the "Fly backups" workflow (action member-delete); apply needs `confirm` = the member's email.
 */
export const memberFootprint = (db: DB, userId: string): Record<string, number> => {
  const out: Record<string, number> = {};
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as { name: string }[];
  for (const { name } of tables) {
    const cols = (db.prepare(`PRAGMA table_info(${name})`).all() as { name: string }[]).map((c) => c.name);
    if (!cols.includes('user_id')) continue;
    const n = Number((db.prepare(`SELECT COUNT(*) AS n FROM ${name} WHERE user_id = ?`).get(userId) as { n: number }).n);
    if (n) out[name] = n;
  }
  return out;
};

// CLI: node src/admin/deleteMember.ts <email> [<confirm email>]
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [email, confirm] = process.argv.slice(2);
  if (!email) {
    console.error('usage: deleteMember.ts <email> [<same email again to delete>]');
    process.exit(2);
  }
  const config = loadConfig();
  const db = openDb(config.dbPath);
  const u = db.prepare('SELECT id, email, created_at FROM users WHERE email = ? COLLATE NOCASE').get(email.trim()) as
    | { id: string; email: string; created_at: string }
    | undefined;
  if (!u) {
    console.log(JSON.stringify({ found: false }, null, 2));
  } else if (confirm?.trim().toLowerCase() !== u.email.toLowerCase()) {
    console.log(JSON.stringify({ dryRun: true, userId: u.id, createdAt: u.created_at, rows: memberFootprint(db, u.id) }, null, 2));
  } else {
    const now = () => new Date();
    const auth = new AuthService({
      db,
      config,
      mailer: createMailer(config),
      apple: createAppleVerifier(config.appleBundleIds),
      now,
      appleTokens: new AppleTokenService({ config, db, fetch: (i, init) => globalThis.fetch(i, init), now, log: console.warn }),
    });
    const rows = memberFootprint(db, u.id);
    await auth.deleteAccount(u.id);
    console.log(JSON.stringify({ deleted: true, userId: u.id, rows, left: memberFootprint(db, u.id) }, null, 2));
  }
  db.close();
}
