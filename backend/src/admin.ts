/**
 * Owner tools, run on the server (Fly: "Free access" workflow, or `fly ssh console -C "node src/admin.ts …"`).
 *
 *   node src/admin.ts grant <email> [--until YYYY-MM-DD] [--note "text"]   free Pro access (#126), no end date by default
 *   node src/admin.ts revoke <email>
 *   node src/admin.ts grant-all --until YYYY-MM-DD [--before YYYY-MM-DD]   free access for every existing account (early testers)
 *   node src/admin.ts list
 */
import { parseArgs } from 'node:util';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';
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
    console.table(subs.grants());
    break;
  default:
    fail('Usage: node src/admin.ts grant <email> [--until YYYY-MM-DD] [--note text] | grant-all --until YYYY-MM-DD [--before YYYY-MM-DD] | revoke <email> | list');
}
db.close();
