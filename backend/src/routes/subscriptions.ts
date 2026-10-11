import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { SubscriptionService } from '../subscriptions/service.ts';

const jws = z.string().min(20).max(20_000);

/** In-app subscriptions (#126): entitlement for the signed-in account + StoreKit 2 transactions from the app. */
export const subscriptionRoutes = (r: FastifyInstance, subs: SubscriptionService) => {
  r.get('/me/entitlement', async (req) => subs.entitlement(req.userId!));

  r.post('/me/subscriptions/transactions', async (req) => {
    const b = z.object({ signedTransaction: jws, signedRenewalInfo: jws.optional() }).parse(req.body);
    return subs.recordFromApp(req.userId!, b.signedTransaction, b.signedRenewalInfo);
  });
};

/** App Store Server Notifications V2. Public: authenticity comes from the Apple-signed payload. */
export const appStoreNotificationRoutes = (app: FastifyInstance, subs: SubscriptionService) => {
  app.post('/v1/app-store/notifications', { config: { rateLimit: { max: 300, timeWindow: '1 minute' } } }, async (req, reply) => {
    const b = z.object({ signedPayload: z.string().min(20).max(100_000) }).parse(req.body);
    // 200 tells Apple to stop retrying; an unverifiable payload gets 400 (Apple retries real ones).
    return reply.status((await subs.handleNotification(b.signedPayload)) ? 200 : 400).send();
  });
};
