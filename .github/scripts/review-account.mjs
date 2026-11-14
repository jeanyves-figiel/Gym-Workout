// App Review demo account (#1090). Piped to `node --input-type=module` on the Fly machine by the
// "Review account" workflow, which prepends REVIEW_EMAIL / REVIEW_PASSWORD (from the REVIEW_DEMO_* secrets)
// so neither appears in a command line or log. Idempotent: creates or updates one account with the email
// verified, terms accepted and the password set, then grants free Pro access (no end date).
/* global REVIEW_EMAIL, REVIEW_PASSWORD */
import { randomUUID } from 'node:crypto';
import { passwordProblem } from '/app/src/auth.ts';
import { loadConfig } from '/app/src/config.ts';
import { hashPassword } from '/app/src/crypto.ts';
import { openDb } from '/app/src/db.ts';
import { SubscriptionService } from '/app/src/subscriptions/service.ts';

const email = REVIEW_EMAIL.trim();
if (!/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(email)) throw new Error('REVIEW_DEMO_EMAIL is not a valid email');
const problem = passwordProblem(REVIEW_PASSWORD, email);
if (problem) throw new Error(`REVIEW_DEMO_PASSWORD: ${problem}`);

const config = loadConfig();
const db = openDb(config.dbPath);
const now = new Date().toISOString();
const hash = await hashPassword(REVIEW_PASSWORD);
const row = db.prepare('SELECT id FROM users WHERE email = ? COLLATE NOCASE').get(email);
let id = row?.id;
if (id) {
  db.prepare(
    `UPDATE users SET password_hash = ?, email_verified_at = COALESCE(email_verified_at, ?), terms_accepted_at = COALESCE(terms_accepted_at, ?),
     failed_logins = 0, locked_until = NULL, updated_at = ? WHERE id = ?`,
  ).run(hash, now, now, now, id);
  db.prepare("DELETE FROM throttle_hits WHERE key LIKE ?").run(`login%:${id}%`);
} else {
  id = randomUUID();
  db.prepare(
    'INSERT INTO users (id, email, password_hash, email_verified_at, name, terms_accepted_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  ).run(id, email, hash, now, 'App Review', now, now, now);
}
const subs = new SubscriptionService({
  db,
  decode: () => Promise.reject(new Error('unused')),
  now: () => new Date(),
  mode: config.subscriptions.mode,
  productIds: config.subscriptions.productIds,
  bundleIds: config.appleBundleIds,
  tests: config.subscriptions.tests,
  testEmails: config.subscriptions.testEmails,
});
subs.grant(id, undefined, 'app-review');
console.log(`Review account ${row ? 'updated' : 'created'}: verified, password set, free Pro.`, subs.entitlement(id));
