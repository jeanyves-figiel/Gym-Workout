import type { DB } from '../db.ts';

/**
 * In-app subscriptions (#126). One row per App Store subscription (original transaction), linked to the account
 * whose id was the purchase's appAccountToken. `access_grants` holds free access given by the owner (admin CLI).
 */
export const ensureSubscriptionSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS app_store_subscriptions (
      original_transaction_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      last_transaction_id TEXT NOT NULL,
      environment TEXT NOT NULL,
      purchased_at TEXT,
      expires_at TEXT,
      revoked_at TEXT,
      trial INTEGER NOT NULL DEFAULT 0,
      auto_renew INTEGER,
      grace_expires_at TEXT,
      signed_at TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS app_store_subscriptions_user ON app_store_subscriptions(user_id);
    CREATE TABLE IF NOT EXISTS app_store_notifications (
      uuid TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      received_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS access_grants (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      expires_at TEXT,
      note TEXT,
      created_at TEXT NOT NULL
    );
    -- Staging test mode (SUBSCRIPTION_TESTS=on): per-account Pro mode override.
    CREATE TABLE IF NOT EXISTS subscription_tests (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      mode TEXT,
      updated_at TEXT NOT NULL
    );
  `);
};
