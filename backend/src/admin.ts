/**
 * Owner tools, run on the server (Fly: "Free access" workflow, or `fly ssh console -C "node src/admin.ts …"`).
 *
 *   node src/admin.ts grant <email> [--until YYYY-MM-DD] [--note "text"]   free Pro access (#126), no end date by default
 *   node src/admin.ts revoke <email>
 *   node src/admin.ts grant-all --until YYYY-MM-DD [--before YYYY-MM-DD]   free access for every existing account (early testers)
 *   node src/admin.ts list
 *   node src/admin.ts challenges                      week challenge suggestions waiting for review (#748)
 *   node src/admin.ts challenge-approve <id>          into the member-week vote
 *   node src/admin.ts challenge-reject <id>
 *   node src/admin.ts holds                           shared items held by AI moderation (#871), oldest first
 *   node src/admin.ts hold-release <id>               put it live (unless reports still hide it)
 *   node src/admin.ts hold-reject <id>                keep it hidden (a held photo is deleted)
 */
import { parseArgs } from 'node:util';
import { openHolds, resolveHold } from './community/aiModeration.ts';
import { pendingSuggestions, reviewSuggestion } from './community/challenges.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { maskEmail } from './emailChange.ts';
import { SubscriptionService } from './subscriptions/service.ts';

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { until: { type: 'string' }, before: { type: 'string' }, note: { type: 'string' } },
});
const [cmd, email] = positionals;
const config = loadConfig();
const db = openDb(config.dbPath);
const subs = new SubscriptionService({
  db,
  decode: () => Promise.reject(new Error('unused')),
  now: () => new Date(),
  mode: config.subscriptions.mode,
  productIds: config.subscriptions.productIds,
  bundleIds: config.appleBundleIds,
});

const fail = (m: string): never => {
  console.error(m);
  process.exit(1);
};
const userId = () => {
  if (!email) fail('Email required');
  const row = db.prepare('SELECT id FROM users WHERE email = ? COLLATE NOCASE').get(email!.trim()) as { id: string } | undefined;
  return row?.id ?? fail(`No account with email ${email}`);
};

switch (cmd) {
  case 'grant': {
    const until = values.until ? new Date(`${values.until}T23:59:59Z`) : undefined;
    if (until && Number.isNaN(until.getTime())) fail('--until must be YYYY-MM-DD');
    const id = userId();
    subs.grant(id, until, values.note);
    console.log(`Granted free access to ${email}${until ? ` until ${values.until}` : ' (no end date)'}.`, subs.entitlement(id));
    break;
  }
  case 'grant-all': {
    if (!values.until) fail('--until YYYY-MM-DD required');
    const until = new Date(`${values.until}T23:59:59Z`);
    const before = values.before ? new Date(`${values.before}T00:00:00Z`) : new Date();
    if (Number.isNaN(until.getTime()) || Number.isNaN(before.getTime())) fail('Dates must be YYYY-MM-DD');
    const n = subs.grantAllExisting(before, until, values.note ?? 'early tester');
    console.log(`Granted free access until ${values.until} to ${n} account(s) created before ${before.toISOString().slice(0, 10)}.`);
    break;
  }
  case 'revoke':
    console.log(subs.revoke(userId()) ? `Revoked free access for ${email}.` : `${email} had no free access.`);
    break;
  case 'list':
    // Masked: the workflow log is public (#432).
    console.table(subs.grants().map((g) => ({ ...g, email: g.email ? maskEmail(g.email) : null })));
    break;
  case 'challenges':
    // Nicknames only, no emails: the workflow log is public (#432).
    console.table(pendingSuggestions(db).map((p) => ({ id: p.id, name: p.name, format: p.format, minutes: p.minutes, moves: (JSON.parse(p.moves) as string[]).join(' · '), by: p.nickname })));
    break;
  case 'challenge-approve':
  case 'challenge-reject': {
    if (!email) fail('Suggestion id required');
    const status = cmd === 'challenge-approve' ? 'approved' : 'rejected';
    console.log(reviewSuggestion(db, email!.trim(), status, new Date()) ? `Suggestion ${email} ${status}.` : `No pending suggestion ${email}.`);
    break;
  }
  case 'holds':
    // Ids, category and nickname only, never the content: the workflow log is public (#432). Content is in the moderation mail.
    console.table(openHolds(db).map((h) => ({ id: h.id, type: h.target_type, category: h.category, by: h.nickname, at: h.created_at })));
    break;
  case 'hold-release':
  case 'hold-reject': {
    if (!email) fail('Hold id required');
    const decision = cmd === 'hold-release' ? 'released' : 'rejected';
    console.log(resolveHold(db, email!.trim(), decision, new Date()) ? `Hold ${email} ${decision}.` : `No open hold ${email}.`);
    break;
  }
  default:
    fail('Usage: node src/admin.ts grant <email> [--until YYYY-MM-DD] [--note text] | grant-all --until YYYY-MM-DD [--before YYYY-MM-DD] | revoke <email> | list | challenges | challenge-approve <id> | challenge-reject <id> | holds | hold-release <id> | hold-reject <id>');
}
db.close();
