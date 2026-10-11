import type { DB } from '../db.ts';
import { tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { AppStoreDecoder, AppStoreNotification, AppStoreRenewalInfo, AppStoreTransaction } from './appStore.ts';

export type SubscriptionMode = 'off' | 'preview' | 'enforced';

export interface Entitlement {
  /** off: nothing shown; preview: paywall/Account visible, nothing locked; enforced: Pro features need `pro`. */
  mode: SubscriptionMode;
  /** Active subscription (incl. trial, grace period) or owner grant. */
  pro: boolean;
  /** What the app may use: `pro`, or everything unless enforced. */
  access: boolean;
  source: 'subscription' | 'grant' | 'none';
  productId?: string;
  expiresAt?: string;
  trial?: boolean;
  /** One-time Lifetime purchase (CHF 100): no expiry, all future updates included. */
  lifetime?: boolean;
  willRenew?: boolean;
  environment?: string;
  /** Free access given by the owner; `until` absent = no end date. */
  grant?: { until?: string };
  /** Product ids the app offers (CHF 2/week, 6/month, 60/year). */
  products: string[];
}

interface SubRow {
  original_transaction_id: string;
  user_id: string;
  product_id: string;
  environment: string;
  expires_at: string | null;
  revoked_at: string | null;
  trial: number;
  auto_renew: number | null;
  grace_expires_at: string | null;
  signed_at: string | null;
}

const iso = (ms?: number) => (ms ? new Date(ms).toISOString() : null);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface SubscriptionDeps {
  db: DB;
  decode: AppStoreDecoder;
  now: () => Date;
  mode: SubscriptionMode;
  productIds: string[];
  bundleIds: string[];
  log?: (m: string) => void;
}

export class SubscriptionService {
  private readonly d: SubscriptionDeps;
  constructor(deps: SubscriptionDeps) {
    this.d = deps;
  }

  private bundleOk(id?: string) {
    return !!id && this.d.bundleIds.some((b) => b.toLowerCase() === id.toLowerCase());
  }

  entitlement(userId: string): Entitlement {
    const now = this.d.now().toISOString();
    const base = { mode: this.d.mode, products: this.d.productIds };
    const grant = this.d.db.prepare('SELECT expires_at FROM access_grants WHERE user_id = ?').get(userId) as { expires_at: string | null } | undefined;
    const subs = this.d.db
      .prepare('SELECT * FROM app_store_subscriptions WHERE user_id = ? AND revoked_at IS NULL')
      .all(userId) as unknown as SubRow[];
    // A non-consumable (Lifetime) has no expiry: it sorts after every date.
    const until = (s: SubRow) => (s.expires_at ? ([s.expires_at, s.grace_expires_at].filter(Boolean).sort().at(-1) ?? '') : '9999');
    const active = subs.filter((s) => until(s) > now).sort((a, b) => until(b).localeCompare(until(a)))[0];
    if (active?.expires_at === null)
      return { ...base, pro: true, access: true, source: 'subscription', productId: active.product_id, lifetime: true, environment: active.environment };
    if (active)
      return {
        ...base,
        pro: true,
        access: true,
        source: 'subscription',
        productId: active.product_id,
        expiresAt: until(active),
        trial: active.trial === 1,
        willRenew: active.auto_renew === null ? undefined : active.auto_renew === 1,
        environment: active.environment,
        ...(grant && (!grant.expires_at || grant.expires_at > now) ? { grant: { until: grant.expires_at ?? undefined } } : {}),
      };
    if (grant && (!grant.expires_at || grant.expires_at > now))
      return { ...base, pro: true, access: true, source: 'grant', grant: { until: grant.expires_at ?? undefined }, expiresAt: grant.expires_at ?? undefined };
    return { ...base, pro: false, access: this.d.mode !== 'enforced', source: 'none' };
  }

  /** A StoreKit 2 transaction the app sent after a purchase / restore / Transaction.updates. */
  async recordFromApp(userId: string, signedTransaction: string, signedRenewalInfo?: string): Promise<Entitlement> {
    let t: AppStoreTransaction;
    let r: AppStoreRenewalInfo | undefined;
    try {
      t = await this.d.decode<AppStoreTransaction>(signedTransaction);
      r = signedRenewalInfo ? await this.d.decode<AppStoreRenewalInfo>(signedRenewalInfo) : undefined;
    } catch (e) {
      this.d.log?.(`app store jws rejected: ${(e as Error).message}`);
      throw new ApiError(400, 'invalid_transaction', 'Transaction could not be verified.');
    }
    if (!this.bundleOk(t.bundleId)) throw new ApiError(400, 'invalid_transaction', 'Transaction is for another app.');
    if (!this.d.productIds.includes(t.productId)) throw new ApiError(400, 'unknown_product', 'Unknown product.');
    if (r && r.originalTransactionId !== t.originalTransactionId) throw new ApiError(400, 'invalid_transaction', 'Renewal info mismatch.');
    if (t.appAccountToken && t.appAccountToken.toLowerCase() !== userId.toLowerCase())
      throw new ApiError(403, 'subscription_other_account', 'This purchase belongs to another MonkeyWorkout account.');
    const owner = this.ownerOf(t.originalTransactionId);
    if (owner && owner !== userId) throw new ApiError(409, 'subscription_other_account', 'This subscription is linked to another MonkeyWorkout account.');
    this.upsert(userId, t, r);
    return this.entitlement(userId);
  }

  /** App Store Server Notifications V2 (`{ signedPayload }`). Returns false when the payload can't be verified. */
  async handleNotification(signedPayload: string): Promise<boolean> {
    let n: AppStoreNotification;
    try {
      n = await this.d.decode<AppStoreNotification>(signedPayload);
    } catch (e) {
      this.d.log?.(`app store notification rejected: ${(e as Error).message}`);
      return false;
    }
    const seen = this.d.db
      .prepare('INSERT INTO app_store_notifications (uuid, type, received_at) VALUES (?, ?, ?) ON CONFLICT(uuid) DO NOTHING')
      .run(n.notificationUUID, [n.notificationType, n.subtype].filter(Boolean).join('/'), this.d.now().toISOString());
    if (seen.changes === 0) return true;
    if (!n.data?.signedTransactionInfo || !this.bundleOk(n.data.bundleId)) return true;
    const t = await this.d.decode<AppStoreTransaction>(n.data.signedTransactionInfo);
    const r = n.data.signedRenewalInfo ? await this.d.decode<AppStoreRenewalInfo>(n.data.signedRenewalInfo) : undefined;
    if (!this.bundleOk(t.bundleId) || !this.d.productIds.includes(t.productId)) return true;
    const owner = this.ownerOf(t.originalTransactionId);
    const token = t.appAccountToken && UUID.test(t.appAccountToken) ? t.appAccountToken.toLowerCase() : undefined;
    const userId = owner ?? (token && this.d.db.prepare('SELECT id FROM users WHERE lower(id) = ?').get(token) ? token : undefined);
    if (!userId) return true; // not (yet) linked: the app posts the transaction on next launch
    // REFUND / REVOKE carry revocationDate on the transaction; EXPIRED / DID_RENEW update expiresDate.
    this.upsert(userId, t, r);
    return true;
  }

  private ownerOf(originalTransactionId: string) {
    return (
      this.d.db.prepare('SELECT user_id FROM app_store_subscriptions WHERE original_transaction_id = ?').get(originalTransactionId) as
        | { user_id: string }
        | undefined
    )?.user_id;
  }

  private upsert(userId: string, t: AppStoreTransaction, r?: AppStoreRenewalInfo) {
    const now = this.d.now().toISOString();
    const signed = iso(t.signedDate) ?? now;
    tx(this.d.db, () => {
      const prev = this.d.db.prepare('SELECT signed_at FROM app_store_subscriptions WHERE original_transaction_id = ?').get(t.originalTransactionId) as
        | { signed_at: string | null }
        | undefined;
      const renewal = r ? [r.autoRenewStatus ?? null, iso(r.gracePeriodExpiresDate)] : undefined;
      // Out-of-order delivery: an older transaction never overwrites a newer one (revocations always apply).
      if (prev?.signed_at && signed < prev.signed_at && !t.revocationDate) {
        if (renewal)
          this.d.db
            .prepare('UPDATE app_store_subscriptions SET auto_renew = ?, grace_expires_at = ?, updated_at = ? WHERE original_transaction_id = ?')
            .run(...renewal, now, t.originalTransactionId);
        return;
      }
      this.d.db
        .prepare(
          `INSERT INTO app_store_subscriptions (original_transaction_id, user_id, product_id, last_transaction_id, environment, purchased_at,
             expires_at, revoked_at, trial, auto_renew, grace_expires_at, signed_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(original_transaction_id) DO UPDATE SET product_id = excluded.product_id, last_transaction_id = excluded.last_transaction_id,
             environment = excluded.environment, purchased_at = excluded.purchased_at, expires_at = excluded.expires_at,
             revoked_at = excluded.revoked_at, trial = excluded.trial, signed_at = excluded.signed_at, updated_at = excluded.updated_at
             ${renewal ? ', auto_renew = excluded.auto_renew, grace_expires_at = excluded.grace_expires_at' : ''}`,
        )
        .run(
          t.originalTransactionId,
          userId,
          t.productId,
          t.transactionId,
          t.environment ?? 'Production',
          iso(t.purchaseDate),
          iso(t.expiresDate),
          iso(t.revocationDate),
          t.offerType === 1 ? 1 : 0,
          renewal?.[0] ?? null,
          renewal?.[1] ?? null,
          signed,
          now,
        );
    });
  }

  // ───────────── owner tools (admin CLI): free access for selected accounts

  grant(userId: string, until?: Date, note?: string) {
    this.d.db
      .prepare(
        `INSERT INTO access_grants (user_id, expires_at, note, created_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET expires_at = excluded.expires_at, note = excluded.note`,
      )
      .run(userId, until?.toISOString() ?? null, note ?? null, this.d.now().toISOString());
  }

  revoke(userId: string) {
    return this.d.db.prepare('DELETE FROM access_grants WHERE user_id = ?').run(userId).changes > 0;
  }

  grants() {
    return this.d.db
      .prepare('SELECT u.email, g.user_id, g.expires_at, g.note, g.created_at FROM access_grants g JOIN users u ON u.id = g.user_id ORDER BY g.created_at')
      .all() as { email: string | null; user_id: string; expires_at: string | null; note: string | null; created_at: string }[];
  }

  /** Free access for every account created before `before` (early testers at launch). Existing grants are kept. */
  grantAllExisting(before: Date, until?: Date, note?: string) {
    return this.d.db
      .prepare(
        `INSERT INTO access_grants (user_id, expires_at, note, created_at)
         SELECT id, ?, ?, ? FROM users WHERE created_at < ? ON CONFLICT(user_id) DO NOTHING`,
      )
      .run(until?.toISOString() ?? null, note ?? null, this.d.now().toISOString(), before.toISOString()).changes;
  }

  /** For the data export: what is stored about the account's subscriptions. */
  export(userId: string) {
    return {
      entitlement: this.entitlement(userId),
      subscriptions: this.d.db
        .prepare('SELECT product_id, environment, purchased_at, expires_at, revoked_at, trial, auto_renew FROM app_store_subscriptions WHERE user_id = ?')
        .all(userId),
    };
  }
}
