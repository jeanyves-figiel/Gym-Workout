import { X509Certificate } from 'node:crypto';
import { compactVerify, importX509 } from 'jose';

/** SHA-256 fingerprint of Apple Root CA - G3, the root of every App Store signed JWS (StoreKit 2, Server Notifications V2). */
export const APPLE_ROOT_CA_G3_FINGERPRINT =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

// Apple marker extensions (DER-encoded OIDs): leaf 1.2.840.113635.100.6.11.1, intermediate 1.2.840.113635.100.6.2.1.
const LEAF_OID = Buffer.from('060a2a864886f76364060b01', 'hex');
const INTERMEDIATE_OID = Buffer.from('060a2a864886f76364060201', 'hex');

/** Decodes an App Store signed payload after verifying its x5c chain up to the pinned Apple root. */
export type AppStoreDecoder = <T>(jws: string) => Promise<T>;

export const createAppStoreDecoder = (opts: { rootFingerprint?: string; checkOids?: boolean; now?: () => Date } = {}): AppStoreDecoder => {
  const root = opts.rootFingerprint ?? APPLE_ROOT_CA_G3_FINGERPRINT;
  const checkOids = opts.checkOids ?? true;
  const now = opts.now ?? (() => new Date());
  return async <T>(jws: string) => {
    const { payload } = await compactVerify(jws, async (header) => {
      if (header.alg !== 'ES256') throw new Error('Unexpected App Store JWS alg');
      const pems = (header.x5c ?? []).map((c) => `-----BEGIN CERTIFICATE-----\n${c}\n-----END CERTIFICATE-----`);
      if (pems.length !== 3) throw new Error('App Store JWS needs a 3-certificate chain');
      const [leaf, mid, top] = pems.map((p) => new X509Certificate(p)) as [X509Certificate, X509Certificate, X509Certificate];
      const t = now();
      for (const c of [leaf, mid, top]) if (!(new Date(c.validFrom) <= t && t <= new Date(c.validTo))) throw new Error('App Store certificate outside validity');
      if (top.fingerprint256 !== root) throw new Error('App Store JWS not rooted in Apple Root CA - G3');
      if (!top.verify(top.publicKey) || !mid.checkIssued(top) || !mid.verify(top.publicKey) || !leaf.checkIssued(mid) || !leaf.verify(mid.publicKey))
        throw new Error('App Store certificate chain invalid');
      if (!mid.ca) throw new Error('App Store intermediate is not a CA');
      if (checkOids && (!leaf.raw.includes(LEAF_OID) || !mid.raw.includes(INTERMEDIATE_OID))) throw new Error('App Store certificate markers missing');
      return importX509(pems[0]!, 'ES256');
    });
    return JSON.parse(new TextDecoder().decode(payload)) as T;
  };
};

/** JWSTransactionDecodedPayload (subset). Dates are ms since epoch. */
export interface AppStoreTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  signedDate?: number;
  appAccountToken?: string;
  /** 1 = introductory offer (free trial), 2 = promotional, 3 = offer code, 4 = win-back. */
  offerType?: number;
  offerDiscountType?: string;
  environment?: 'Production' | 'Sandbox' | 'Xcode' | 'LocalTesting';
  type?: string;
  inAppOwnershipType?: 'PURCHASED' | 'FAMILY_SHARED';
}

/** JWSRenewalInfoDecodedPayload (subset). */
export interface AppStoreRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: 0 | 1;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
  signedDate?: number;
}

/** responseBodyV2DecodedPayload (subset). */
export interface AppStoreNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  signedDate?: number;
  data?: { bundleId?: string; environment?: string; signedTransactionInfo?: string; signedRenewalInfo?: string };
}
