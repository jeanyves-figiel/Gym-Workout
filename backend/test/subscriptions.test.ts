import { execFileSync } from 'node:child_process';
import { createPrivateKey, X509Certificate } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { CompactSign } from 'jose';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { createAppStoreDecoder } from '../src/subscriptions/appStore.ts';
import { SubscriptionService } from '../src/subscriptions/service.ts';

const PW = 'correct-horse-battery';
const DAY = 86_400_000;

// A throwaway CA chain shaped like Apple's (root → intermediate with marker OID → leaf with marker OID), made with openssl.
let chain: { x5c: string[]; key: ReturnType<typeof createPrivateKey>; rootFp: string; otherX5c: string[] };
const makeChain = (dir: string, tag: string) => {
  const ssl = (...a: string[]) => execFileSync('openssl', a, { cwd: dir, stdio: 'pipe' });
  const ext = (name: string, body: string) => writeFileSync(join(dir, name), body);
  for (const n of ['root', 'mid', 'leaf']) ssl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${tag}${n}.key`);
  ssl('req', '-x509', '-new', '-key', `${tag}root.key`, '-subj', `/CN=Test Root ${tag}`, '-days', '3650', '-out', `${tag}root.pem`,
    '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign');
  ext('mid.ext', 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n1.2.840.113635.100.6.2.1=ASN1:NULL\n');
  ext('leaf.ext', 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n1.2.840.113635.100.6.11.1=ASN1:NULL\n');
  ssl('req', '-new', '-key', `${tag}mid.key`, '-subj', `/CN=Test Mid ${tag}`, '-out', `${tag}mid.csr`);
  ssl('x509', '-req', '-in', `${tag}mid.csr`, '-CA', `${tag}root.pem`, '-CAkey', `${tag}root.key`, '-CAcreateserial', '-days', '3650', '-extfile', 'mid.ext', '-out', `${tag}mid.pem`);
  ssl('req', '-new', '-key', `${tag}leaf.key`, '-subj', `/CN=Test Leaf ${tag}`, '-out', `${tag}leaf.csr`);
  ssl('x509', '-req', '-in', `${tag}leaf.csr`, '-CA', `${tag}mid.pem`, '-CAkey', `${tag}mid.key`, '-CAcreateserial', '-days', '3650', '-extfile', 'leaf.ext', '-out', `${tag}leaf.pem`);
  const b64 = (f: string) => new X509Certificate(readFileSync(join(dir, f))).raw.toString('base64');
  return {
    x5c: [b64(`${tag}leaf.pem`), b64(`${tag}mid.pem`), b64(`${tag}root.pem`)],
    key: createPrivateKey(readFileSync(join(dir, `${tag}leaf.key`))),
    rootFp: new X509Certificate(readFileSync(join(dir, `${tag}root.pem`))).fingerprint256,
  };
};

beforeAll(() => {
  const dir = mkdtempSync(join(tmpdir(), 'appstore-'));
  const a = makeChain(dir, 'a');
  const b = makeChain(dir, 'b');
  chain = { ...a, otherX5c: b.x5c };
});

const sign = async (payload: object, x5c = chain.x5c) =>
  new CompactSign(new TextEncoder().encode(JSON.stringify(payload))).setProtectedHeader({ alg: 'ES256', x5c }).sign(chain.key);

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

const start = (env: Record<string, string> = {}) => {
  clock = new Date(Math.floor(Date.now() / 1000) * 1000 + 60_000); // after the test chain's notBefore
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ACCESS_TTL_SEC: '31536000', ...env }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
    appStore: createAppStoreDecoder({ rootFingerprint: chain.rootFp, now: () => clock }),
  });
};
afterEach(() => app?.close());

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const body = res.json() as { tokens: { accessToken: string }; user: { id: string } };
  return { token: body.tokens.accessToken, id: body.user.id };
};
const entitlement = async (token: string) => (await app.inject({ method: 'GET', url: '/v1/me/entitlement', headers: auth(token) })).json();
const postTx = (token: string, signedTransaction: string, signedRenewalInfo?: string) =>
  app.inject({ method: 'POST', url: '/v1/me/subscriptions/transactions', headers: auth(token), payload: { signedTransaction, signedRenewalInfo } });
const notify = async (payload: object) => app.inject({ method: 'POST', url: '/v1/app-store/notifications', payload: { signedPayload: await sign(payload) } });

const txn = (userId: string, over: object = {}) => ({
  transactionId: '2000000001',
  originalTransactionId: '2000000000',
  bundleId: 'Com.app.MonkeyWorkout',
  productId: 'monkeyworkout.pro.monthly',
  purchaseDate: clock.getTime(),
  expiresDate: clock.getTime() + 7 * DAY,
  signedDate: clock.getTime(),
  appAccountToken: userId,
  offerType: 1,
  environment: 'Sandbox',
  ...over,
});

describe('in-app subscriptions', () => {
  it('is off and grants access by default, enforced mode locks without Pro', async () => {
    start();
    const u = await signUp('a@example.com');
    expect(await entitlement(u.token)).toMatchObject({ mode: 'off', pro: false, access: true, source: 'none', products: expect.arrayContaining(['monkeyworkout.pro.weekly']) });
    await app.close();
    start({ SUBSCRIPTIONS: 'enforced' });
    const v = await signUp('b@example.com');
    expect(await entitlement(v.token)).toMatchObject({ mode: 'enforced', pro: false, access: false });
  });

  it('verifies a StoreKit transaction (trial), then renewal and expiry', async () => {
    start({ SUBSCRIPTIONS: 'enforced' });
    const u = await signUp('a@example.com');
    const first = await sign(txn(u.id));
    const res = await postTx(u.token, first, await sign({ originalTransactionId: '2000000000', autoRenewStatus: 1 }));
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ pro: true, access: true, source: 'subscription', trial: true, willRenew: true, productId: 'monkeyworkout.pro.monthly' });

    // Renewal arrives by server notification: paid month, no trial.
    clock = new Date(clock.getTime() + 7 * DAY);
    const renewed = txn(u.id, { transactionId: '2000000002', offerType: undefined, purchaseDate: clock.getTime(), expiresDate: clock.getTime() + 30 * DAY, signedDate: clock.getTime() });
    expect((await notify({ notificationType: 'DID_RENEW', notificationUUID: 'n1', data: { bundleId: 'Com.app.MonkeyWorkout', signedTransactionInfo: await sign(renewed) } })).statusCode).toBe(200);
    expect(await entitlement(u.token)).toMatchObject({ pro: true, trial: false });

    // An older transaction replayed afterwards does not shorten it.
    await postTx(u.token, first);
    expect((await entitlement(u.token)).expiresAt).toBe(new Date(clock.getTime() + 30 * DAY).toISOString());

    clock = new Date(clock.getTime() + 31 * DAY);
    expect(await entitlement(u.token)).toMatchObject({ pro: false, access: false, source: 'none' });
  });

  it('honours grace period and refunds', async () => {
    start();
    const u = await signUp('a@example.com');
    await postTx(u.token, await sign(txn(u.id)), await sign({ originalTransactionId: '2000000000', autoRenewStatus: 1, gracePeriodExpiresDate: clock.getTime() + 10 * DAY }));
    clock = new Date(clock.getTime() + 8 * DAY);
    expect(await entitlement(u.token)).toMatchObject({ pro: true });
    const refunded = txn(u.id, { revocationDate: clock.getTime(), signedDate: clock.getTime() });
    await notify({ notificationType: 'REFUND', notificationUUID: 'n2', data: { bundleId: 'Com.app.MonkeyWorkout', signedTransactionInfo: await sign(refunded) } });
    expect(await entitlement(u.token)).toMatchObject({ pro: false });
  });

  it('rejects forged, foreign and cross-account transactions', async () => {
    start();
    const u = await signUp('a@example.com');
    const other = await signUp('b@example.com');
    expect((await postTx(u.token, await sign(txn(u.id), chain.otherX5c))).statusCode).toBe(400); // chain not under the pinned root
    expect((await postTx(u.token, await sign(txn(u.id, { bundleId: 'com.other.app' })))).json().error).toBe('invalid_transaction');
    expect((await postTx(u.token, await sign(txn(u.id, { productId: 'x' })))).json().error).toBe('unknown_product');
    expect((await postTx(other.token, await sign(txn(u.id)))).statusCode).toBe(403);
    expect((await postTx(u.token, await sign(txn(u.id)))).statusCode).toBe(200);
    expect((await postTx(other.token, await sign(txn(other.id, { appAccountToken: undefined })))).statusCode).toBe(409);
    const bad = await app.inject({ method: 'POST', url: '/v1/app-store/notifications', payload: { signedPayload: await sign({ notificationType: 'TEST', notificationUUID: 'x' }, chain.otherX5c) } });
    expect(bad.statusCode).toBe(400);
  });

  it('links a notification to the account by appAccountToken, deduplicates, and exports', async () => {
    start();
    const u = await signUp('a@example.com');
    const n = { notificationType: 'SUBSCRIBED', subtype: 'INITIAL_BUY', notificationUUID: 'n3', data: { bundleId: 'Com.app.MonkeyWorkout', signedTransactionInfo: await sign(txn(u.id)) } };
    expect((await notify(n)).statusCode).toBe(200);
    expect((await notify(n)).statusCode).toBe(200);
    expect(await entitlement(u.token)).toMatchObject({ pro: true, environment: 'Sandbox' });
    const exp = (await app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(u.token) })).json();
    expect(exp.subscriptions.subscriptions).toHaveLength(1);
  });

  it('free access grants: owner grant, end date, revoke', async () => {
    start({ SUBSCRIPTIONS: 'enforced' });
    const u = await signUp('friend@example.com');
    const subs = new SubscriptionService({ db, decode: () => Promise.reject(new Error('unused')), now: () => clock, mode: 'enforced', productIds: [], bundleIds: [] });
    subs.grant(u.id, undefined, 'coach');
    expect(await entitlement(u.token)).toMatchObject({ pro: true, access: true, source: 'grant', grant: {} });
    subs.grant(u.id, new Date(clock.getTime() + DAY));
    clock = new Date(clock.getTime() + 2 * DAY);
    expect(await entitlement(u.token)).toMatchObject({ pro: false, access: false });
    subs.grant(u.id);
    expect(subs.grants()).toMatchObject([{ email: 'friend@example.com', expires_at: null }]);
    expect(subs.revoke(u.id)).toBe(true);
    expect(await entitlement(u.token)).toMatchObject({ source: 'none' });
  });

  it('Lifetime purchase never expires, refund removes it', async () => {
    start({ SUBSCRIPTIONS: 'enforced' });
    const u = await signUp('a@example.com');
    const life = txn(u.id, { productId: 'monkeyworkout.pro.lifetime', expiresDate: undefined, offerType: undefined, type: 'Non-Consumable' });
    expect((await postTx(u.token, await sign(life))).json()).toMatchObject({ pro: true, lifetime: true, productId: 'monkeyworkout.pro.lifetime' });
    clock = new Date(clock.getTime() + 300 * DAY);
    expect(await entitlement(u.token)).toMatchObject({ pro: true, lifetime: true });
    await notify({ notificationType: 'REFUND', notificationUUID: 'n9', data: { bundleId: 'Com.app.MonkeyWorkout', signedTransactionInfo: await sign({ ...life, revocationDate: clock.getTime(), signedDate: clock.getTime() }) } });
    expect(await entitlement(u.token)).toMatchObject({ pro: false, access: false });
  });

  it('grants free access to every existing account (early testers)', async () => {
    start({ SUBSCRIPTIONS: 'enforced' });
    const a = await signUp('a@example.com');
    const subs = new SubscriptionService({ db, decode: () => Promise.reject(new Error('unused')), now: () => clock, mode: 'enforced', productIds: [], bundleIds: [] });
    subs.grant(a.id, undefined, 'friend');
    clock = new Date(clock.getTime() + DAY);
    const b = await signUp('b@example.com');
    expect(subs.grantAllExisting(new Date(clock.getTime() + 1000), new Date(clock.getTime() + 30 * DAY))).toBe(1);
    expect(await entitlement(a.token)).toMatchObject({ source: 'grant', grant: {} }); // kept: no end date
    expect(await entitlement(b.token)).toMatchObject({ source: 'grant', grant: { until: new Date(clock.getTime() + 30 * DAY).toISOString() } });
  });

  it('staging test mode: per-account mode, fake purchase, cancel and end; 404 when off', async () => {
    start();
    const u = await signUp('test@example.com');
    const put = (token: string, url: string, payload: object, method: 'PUT' | 'POST' = 'POST') =>
      app.inject({ method, url, headers: auth(token), payload });
    expect((await put(u.token, '/v1/me/subscriptions/test/purchase', { productId: 'monkeyworkout.pro.yearly' })).statusCode).toBe(404);
    expect(await entitlement(u.token)).not.toHaveProperty('test');
    await app.close();

    start({ SUBSCRIPTION_TESTS: 'on' });
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    expect(await entitlement(a.token)).toMatchObject({ mode: 'off', access: true, test: {} });
    expect((await put(a.token, '/v1/me/subscriptions/test', { mode: 'enforced' }, 'PUT')).json()).toMatchObject({ mode: 'enforced', access: false, test: { mode: 'enforced' } });
    expect(await entitlement(b.token)).toMatchObject({ mode: 'off', access: true }); // other accounts unchanged
    expect((await put(a.token, '/v1/me/subscriptions/test/purchase', { productId: 'nope' })).statusCode).toBe(400);
    expect((await put(a.token, '/v1/me/subscriptions/test/purchase', { productId: 'monkeyworkout.pro.monthly' })).json()).toMatchObject({
      pro: true, access: true, trial: true, willRenew: true, environment: 'Test', expiresAt: new Date(clock.getTime() + 7 * DAY).toISOString(),
    });
    expect((await put(a.token, '/v1/me/subscriptions/test/cancel', {})).json()).toMatchObject({ pro: true, willRenew: false });
    expect((await put(a.token, '/v1/me/subscriptions/test/purchase', { productId: 'monkeyworkout.pro.lifetime' })).json()).toMatchObject({ pro: true, lifetime: true });
    expect((await put(a.token, '/v1/me/subscriptions/test/cancel', { end: true })).json()).toMatchObject({ pro: false, access: false });
    expect((await put(a.token, '/v1/me/subscriptions/test', { mode: null }, 'PUT')).json()).toMatchObject({ mode: 'off', access: true, test: {} });
  });
});

describe('sandbox purchases and notification retries (#432)', () => {
  it('production refuses Sandbox transactions and notifications unless allowed', async () => {
    const prod = { NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(32), CODE_PEPPER: 'p', MAIL_TRANSPORT: 'console', BACKUP_DIR: 'off' };
    expect(loadConfig(prod).subscriptions.sandbox).toBe(false);
    expect(loadConfig({ ...prod, SUBSCRIPTION_TESTS: 'on' }).subscriptions.sandbox).toBe(true);
    expect(loadConfig({ ...prod, SUBSCRIPTION_SANDBOX: 'on' }).subscriptions.sandbox).toBe(true);
    expect(loadConfig({ NODE_ENV: 'test' }).subscriptions.sandbox).toBe(true);

    start({ SUBSCRIPTIONS: 'enforced', SUBSCRIPTION_SANDBOX: 'off' });
    const u = await signUp('a@example.com');
    const res = await postTx(u.token, await sign(txn(u.id)));
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('sandbox_transaction');
    const n = { notificationType: 'SUBSCRIBED', notificationUUID: 'sb1', data: { bundleId: 'Com.app.MonkeyWorkout', environment: 'Sandbox', signedTransactionInfo: await sign(txn(u.id)) } };
    expect((await notify(n)).statusCode).toBe(200);
    expect(await entitlement(u.token)).toMatchObject({ pro: false });
    expect((await postTx(u.token, await sign(txn(u.id, { environment: 'Production' })))).json()).toMatchObject({ pro: true, environment: 'Production' });
  });

  it('marks a notification seen only once handled, so a retry after a failure is processed', async () => {
    const db = openDb(':memory:');
    let fail = true;
    const subs = new SubscriptionService({
      db,
      decode: async <T,>(jws: string) => {
        if (jws === 'txn' && fail) throw new Error('disk full');
        return (jws === 'txn' ? {} : { notificationType: 'DID_RENEW', notificationUUID: 'r1', data: { bundleId: 'b', signedTransactionInfo: 'txn' } }) as T;
      },
      now: () => new Date(),
      mode: 'enforced',
      productIds: [],
      bundleIds: ['b'],
    });
    const seen = () => (db.prepare("SELECT COUNT(*) AS n FROM app_store_notifications WHERE uuid = 'r1'").get() as { n: number }).n;
    await expect(subs.handleNotification('payload')).rejects.toThrow('disk full');
    expect(seen()).toBe(0);
    fail = false;
    expect(await subs.handleNotification('payload')).toBe(true);
    expect(seen()).toBe(1);
  });
});
