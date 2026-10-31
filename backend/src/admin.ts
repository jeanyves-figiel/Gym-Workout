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
 *   node src/admin.ts recipe-flags                    recipes whose numbers members flagged in reviews (#1017)
 *   node src/admin.ts ai-usage [--days N]              paid AI calls per day and feature: calls, failures, tokens, cost (#877)
 *   node src/admin.ts tester-add <email|account id> [--note text]  staging only: allow Pro test mode (#924)
 *   node src/admin.ts tester-remove <email> | testers | accounts      accounts: ids, masked emails, nicknames
 */
import { parseArgs } from 'node:util';
import { aiUsageReport } from './aiUsage.ts';
import { pendingSuggestions, reviewSuggestion } from './community/challenges.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
import { recipeFlags } from './routes/recipeReviews.ts';
import { maskEmail } from './emailChange.ts';
import { SubscriptionService } from './subscriptions/service.ts';

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { until: { type: 'string' }, before: { type: 'string' }, note: { type: 'string' }, days: { type: 'string' } },
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
  tests: config.subscriptions.tests,
  testEmails: config.subscriptions.testEmails,
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
  case 'recipe-flags':
    // Recipe ids and counts only, no member data.
    console.table(recipeFlags(db));
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
  // Staging test-mode testers (#924). Refused where test mode is off, so production never gets a list.
  case 'tester-add':
  case 'tester-remove':
  case 'testers':
  case 'accounts': {
    if (!config.subscriptions.tests) fail('Test mode is off on this server (SUBSCRIPTION_TESTS): staging only.');
    if (cmd === 'accounts') {
      // Pick a tester: id, masked email, nickname, sign-up date, newest first.
      const rows = db
        .prepare(
          `SELECT u.id, u.email, p.nickname, substr(u.created_at, 1, 10) AS created, u.email_verified_at IS NOT NULL AS verified,
             EXISTS (SELECT 1 FROM subscription_testers t WHERE t.email = u.email) AS tester
           FROM users u LEFT JOIN community_profiles p ON p.user_id = u.id ORDER BY u.created_at DESC LIMIT 200`,
        )
        .all() as { id: string; email: string | null; nickname: string | null; created: string; verified: number; tester: number }[];
      console.table(rows.map((r) => ({ ...r, email: r.email ? maskEmail(r.email) : '(Apple, no email)', verified: !!r.verified, tester: !!r.tester })));
      break;
    }
    if (cmd === 'tester-add') {
      // An email, or an account id from `accounts` (the log only shows masked emails).
      const byId = email && (db.prepare('SELECT email FROM users WHERE id = ?').get(email.trim()) as { email: string | null } | undefined)?.email;
      const target = byId || email?.trim();
      if (!target || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(target)) fail('Valid email or account id required');
      subs.addTester(target!, values.note);
      console.log(`Added ${maskEmail(target!)} to staging testers.`);
    } else if (cmd === 'tester-remove') {
      if (!email) fail('Email required');
      console.log(subs.removeTester(email!) ? `Removed ${maskEmail(email!.trim())}.` : `${maskEmail(email!.trim())} was not a tester.`);
    }
    // Masked: the workflow log is public (#432).
    console.table(subs.testers().map((t) => ({ ...t, email: maskEmail(t.email), account: t.account ? 'yes' : 'not signed up yet' })));
    break;
  }
  case 'ai-usage': {
    const days = Number(values.days ?? 7);
    if (!Number.isInteger(days) || days < 1 || days > 90) fail('--days must be 1 to 90');
    const r = aiUsageReport(db, days, new Date(), config.aiDailyLimit);
    const usd = (v: number) => `$${v.toFixed(2)}`;
    console.log(`AI usage, last ${days} day(s): ${usd(r.totalUsd)}`);
    console.table(r.days.map((d) => ({ day: d.day, calls: d.calls, failures: d.failures, cost: usd(d.costUsd), cap: `${d.capUsed} / ${d.cap}` })));
    console.table(
      r.rows.map((x) => ({
        day: x.day, feature: x.feature, model: x.model, calls: x.calls, failures: x.failures, input: x.input, output: x.output,
        cacheHit: `${Math.round(x.cacheHit * 100)} %`, cost: usd(x.costUsd),
      })),
    );
    break;
  }
  default:
    fail('Usage: node src/admin.ts grant <email> [--until YYYY-MM-DD] [--note text] | grant-all --until YYYY-MM-DD [--before YYYY-MM-DD] | revoke <email> | list | challenges | challenge-approve <id> | challenge-reject <id> | ai-usage [--days N] | tester-add <email|id> [--note text] | tester-remove <email> | testers | accounts');
}
db.close();
