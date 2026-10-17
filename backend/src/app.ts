import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { z, ZodError } from 'zod';
import type { AppleVerifier } from './apple.ts';
import { AppleTokenService, type Fetch } from './appleTokens.ts';
import { AuthService, publicUser } from './auth.ts';
import type { Config } from './config.ts';
import type { DB } from './db.ts';
import { EmailChangeService } from './emailChange.ts';
import { ApiError } from './errors.ts';
import { createBreachChecker } from './hibp.ts';
import type { Mailer } from './mailer.ts';
import { type ApnsSender, createApnsSender } from './push/apns.ts';
import { PushService } from './push/service.ts';
import { accountRoutes } from './routes/account.ts';
import { followerIds } from './community/moderation.ts';
import { communityPublicRoutes, communityRoutes } from './routes/community.ts';
import { type CoachModel, claudeCoach } from './coach/chat.ts';
import { coachChatRoutes } from './routes/coachChat.ts';
import { type GymScanModel, claudeGymScan } from './coach/gymScan.ts';
import { gymScanRoutes } from './routes/gymScan.ts';
import { coachVoiceRoutes } from './routes/coachVoices.ts';
import { pollySynthesizer, type Synthesize } from './coach/polly.ts';
import { customExerciseRoutes } from './routes/customExercises.ts';
import { customWorkoutRoutes } from './routes/customWorkouts.ts';
import { bodyMeasurementRoutes } from './routes/bodyMeasurements.ts';
import { climbRoutes } from './routes/climbs.ts';
import { sportRoutes, watchSportRoutes } from './routes/sports.ts';
import { machineNoteRoutes } from './routes/machineNotes.ts';
import { prAttemptRoutes } from './routes/prAttempts.ts';
import { dataRoutes } from './routes/data.ts';
import { gymRoutes } from './routes/gyms.ts';
import { pushRoutes } from './routes/push.ts';
import { libraryRoutes } from './routes/library.ts';
import { appStoreNotificationRoutes, subscriptionRoutes } from './routes/subscriptions.ts';
import { type AppStoreDecoder, createAppStoreDecoder } from './subscriptions/appStore.ts';
import { SubscriptionService } from './subscriptions/service.ts';
import { legalRoutes } from './routes/legal.ts';
import { reauthToken, securityPublicRoutes, securityRoutes } from './routes/security.ts';
import { SecurityService, type WebAuthnVerifier } from './security.ts';

declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
  }
  interface FastifyInstance {
    /** Remote push (#69). Other features call `app.push.notifyFollowers(...)`. */
    push: PushService;
  }
}

export interface AppDeps {
  config: Config;
  db: DB;
  mailer: Mailer;
  apple: AppleVerifier;
  now?: () => Date;
  logger?: boolean;
  /** Outbound HTTP (Apple token endpoints, HIBP); injectable for tests. */
  fetch?: Fetch;
  /** APNs transport; defaults to HTTP/2 when APNS_* is configured. Injectable for tests. */
  apns?: ApnsSender;
  /** Verifies App Store signed payloads (#126); defaults to the Apple Root CA - G3 chain check. Injectable for tests. */
  appStore?: AppStoreDecoder;
  /** WebAuthn verification (#257); injectable for tests. */
  webauthn?: WebAuthnVerifier;
  /** Workout chat model (#381); defaults to Claude when ANTHROPIC_API_KEY is set. Injectable for tests. */
  coach?: CoachModel;
  /** Gym scan photo model (#406); defaults to Claude when ANTHROPIC_API_KEY is set. Injectable for tests. */
  gymScan?: GymScanModel;
  /** Studio coach voices (#395); defaults to Polly when credentials are configured. Injectable for tests. */
  synth?: Synthesize;
}

const email = z.string().trim().toLowerCase().pipe(z.email().max(254));
const password = z.string().min(1).max(256);
const code = z.string().regex(/^\d{6}$/, 'Code must be 6 digits');
const name = z.string().trim().min(1).max(80);

const device = (req: FastifyRequest) => (req.headers['x-device-name'] as string | undefined) ?? req.headers['user-agent'];

export const buildApp = (deps: AppDeps): FastifyInstance => {
  const app = Fastify({ logger: deps.logger ?? false, trustProxy: true, bodyLimit: 1_000_000 });
  const now = deps.now ?? (() => new Date());
  const outbound: Fetch = deps.fetch ?? ((input, init) => globalThis.fetch(input, init));
  const warn = (msg: string) => app.log.warn(msg);
  const auth = new AuthService({
    ...deps,
    now,
    breached: deps.config.hibpCheck ? createBreachChecker({ fetch: outbound, log: warn }) : undefined,
    appleTokens: new AppleTokenService({ config: deps.config, db: deps.db, fetch: outbound, now, log: warn }),
  });
  const security = new SecurityService({ db: deps.db, config: deps.config, mailer: deps.mailer, apple: deps.apple, auth, now, webauthn: deps.webauthn });
  const emailChange = new EmailChangeService({ db: deps.db, config: deps.config, mailer: deps.mailer, now });
  const k = deps.config.apns;
  const push = new PushService({
    db: deps.db,
    now,
    log: warn,
    sender: deps.apns ?? (k.teamId && k.keyId && k.privateKey ? createApnsSender({ teamId: k.teamId, keyId: k.keyId, privateKey: k.privateKey }, now) : undefined),
  });
  // Followers from Community (#61). Only members who share (default visibility not private) announce wins.
  const sharing = (id: string) =>
    deps.db.prepare("SELECT nickname FROM community_profiles WHERE user_id = ? AND default_visibility != 'private'").get(id) as
      | { nickname: string }
      | undefined;
  push.setFollowersProvider((id) => (sharing(id) ? followerIds(deps.db, id) : []));
  app.decorate('push', push);
  const subscriptions = new SubscriptionService({
    db: deps.db,
    decode: deps.appStore ?? createAppStoreDecoder({ now }),
    now,
    mode: deps.config.subscriptions.mode,
    productIds: deps.config.subscriptions.productIds,
    tests: deps.config.subscriptions.tests,
    bundleIds: deps.config.appleBundleIds,
    log: warn,
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ApiError) return reply.status(err.status).send({ error: err.code, message: err.message, ...err.extra });
    if (err instanceof ZodError)
      return reply.status(400).send({ error: 'invalid_request', message: err.issues[0]?.message ?? 'Invalid request', issues: err.issues });
    const e = err as { statusCode?: number; code?: string; message: string };
    if (e.statusCode === 429) return reply.status(429).send({ error: 'rate_limited', message: 'Too many requests. Slow down.' });
    if (e.statusCode && e.statusCode < 500) return reply.status(e.statusCode).send({ error: 'bad_request', message: e.message });
    req.log.error(err);
    return reply.status(500).send({ error: 'internal', message: 'Something went wrong.' });
  });

  app.register(rateLimit, { global: false });

  // Personal data must not land in HTTP caches on the device or in between (#310).
  app.addHook('onSend', async (req, reply) => {
    if (req.headers.authorization && !reply.hasHeader('cache-control')) reply.header('cache-control', 'no-store');
  });

  // Mail transport is exposed so the staging smoke test can tell real delivery from console logging.
  app.get('/healthz', async () => ({ ok: true, mail: deps.config.mail.transport }));

  communityPublicRoutes(app, deps.db, deps.config.appName);
  appStoreNotificationRoutes(app, subscriptions);
  legalRoutes(app, deps.config);
  securityPublicRoutes(app, security, deps.config.authRateLimitPerMin);
  watchSportRoutes(app, deps.db, deps.now ?? (() => new Date()));

  const authenticate = async (req: FastifyRequest) => {
    const h = req.headers.authorization;
    if (!h?.startsWith('Bearer ')) throw new ApiError(401, 'invalid_token', 'Missing bearer token.');
    const userId = await auth.verifyAccess(h.slice(7));
    if (!auth.userById(userId)) throw new ApiError(401, 'invalid_token', 'Account no longer exists.');
    req.userId = userId;
  };

  // ───────────── public auth routes (rate limited per IP)
  app.register(
    async (r) => {
      const limit = { config: { rateLimit: { max: deps.config.authRateLimitPerMin, timeWindow: '1 minute' } } };

      r.post('/register', limit, async (req, reply) => {
        const b = z.object({ email, password, name: name.optional(), acceptedTerms: z.boolean() }).parse(req.body);
        await auth.register(b.email, b.password, b.name, b.acceptedTerms);
        return reply.status(202).send({ status: 'verification_required', message: 'Check your email for a 6-digit code.' });
      });

      r.post('/verify-email', limit, async (req) => {
        const b = z.object({ email, code }).parse(req.body);
        return auth.verifyEmail(b.email, b.code, device(req));
      });

      r.post('/resend-verification', limit, async (req, reply) => {
        const b = z.object({ email }).parse(req.body);
        await auth.resendVerification(b.email);
        return reply.status(202).send({ status: 'sent_if_pending' });
      });

      r.post('/login', limit, async (req) => {
        const b = z.object({ email, password }).parse(req.body);
        return auth.login(b.email, b.password, device(req));
      });

      r.post('/apple', limit, async (req) => {
        const b = z
          .object({ identityToken: z.string().min(10).max(5000), authorizationCode: z.string().min(1).max(2000).optional(), name: name.optional() })
          .parse(req.body);
        return auth.signInWithApple(b.identityToken, b.name, device(req), b.authorizationCode);
      });

      r.post('/refresh', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req) => {
        const b = z.object({ refreshToken: z.string().min(10).max(200) }).parse(req.body);
        return auth.refresh(b.refreshToken, device(req));
      });

      r.post('/logout', async (req, reply) => {
        const b = z.object({ refreshToken: z.string().min(10).max(200) }).parse(req.body);
        auth.logout(b.refreshToken);
        return reply.status(204).send();
      });

      r.post('/password/forgot', limit, async (req, reply) => {
        const b = z.object({ email }).parse(req.body);
        await auth.forgotPassword(b.email);
        return reply.status(202).send({ status: 'sent_if_exists', message: 'If an account exists, a code is on its way.' });
      });

      r.post('/password/reset', limit, async (req, reply) => {
        const b = z.object({ email, code, newPassword: password }).parse(req.body);
        await auth.resetPassword(b.email, b.code, b.newPassword);
        return reply.status(204).send();
      });
    },
    { prefix: '/v1/auth' },
  );

  // ───────────── authenticated account routes
  app.register(
    async (r) => {
      r.addHook('preHandler', authenticate);

      r.get('/me', async (req) => ({ user: publicUser(auth.userById(req.userId!)!) }));

      r.patch('/me', async (req) => {
        const b = z.object({ name: name.nullable() }).parse(req.body);
        return { user: auth.updateName(req.userId!, b.name) };
      });

      // Re-auth (#257): grant header, or the current password from older app builds.
      r.post('/me/password', async (req) => {
        const b = z.object({ currentPassword: password.optional(), newPassword: password }).parse(req.body);
        await security.requireReauth(req.userId!, reauthToken(req), b.currentPassword);
        return { tokens: await auth.changePassword(req.userId!, b.newPassword, device(req)) };
      });

      r.get('/me/sessions', async (req) => ({ sessions: auth.sessions(req.userId!) }));

      r.post('/me/logout-all', async (req, reply) => {
        auth.revokeAll(req.userId!);
        return reply.status(204).send();
      });

      r.delete('/me', async (req, reply) => {
        const b = z.object({ password: password.optional(), confirm: z.literal('DELETE') }).parse(req.body ?? {});
        await security.requireReauth(req.userId!, reauthToken(req), b.password);
        await auth.deleteAccount(req.userId!);
        return reply.status(204).send();
      });

      dataRoutes(r, deps.db, deps.now ?? (() => new Date()), auth, (id) => subscriptions.export(id));
      accountRoutes(r, emailChange, security, deps.config.authRateLimitPerMin);
      securityRoutes(r, security, deps.config.authRateLimitPerMin);
      customWorkoutRoutes(r, deps.db, deps.now ?? (() => new Date()));
      communityRoutes(r, deps.db, now, deps.mailer, deps.config.moderationEmail);
      customExerciseRoutes(r, deps.db, deps.now ?? (() => new Date()));
      prAttemptRoutes(r, deps.db, deps.now ?? (() => new Date()));
      climbRoutes(r, deps.db, deps.now ?? (() => new Date()));
      sportRoutes(r, deps.db, deps.now ?? (() => new Date()));
      machineNoteRoutes(r, deps.db, deps.now ?? (() => new Date()));
      bodyMeasurementRoutes(r, deps.db, deps.now ?? (() => new Date()));
      pushRoutes(r, push, deps.config.appleBundleIds, (id) => sharing(id)?.nickname ?? null);
      libraryRoutes(r, deps.db, now, deps.mailer, deps.config.moderationEmail);
      subscriptionRoutes(r, subscriptions);
      gymRoutes(r, deps.db, now);
      const coach = deps.coach ?? (deps.config.coachChat.apiKey ? claudeCoach(deps.config.coachChat.apiKey, deps.config.coachChat.workspaceId) : undefined);
      coachChatRoutes(r, deps.db, now, coach, deps.config.coachChat.dailyLimit, (id) => subscriptions.entitlement(id).access);
      const gymScan = deps.gymScan ?? (deps.config.coachChat.apiKey ? claudeGymScan(deps.config.coachChat.apiKey, deps.config.coachChat.workspaceId) : undefined);
      gymScanRoutes(r, deps.db, now, gymScan, 30, (id) => subscriptions.entitlement(id).access);
      const voices = deps.config.coachVoices;
      coachVoiceRoutes(r, deps.synth ?? (voices.polly ? pollySynthesizer(voices.polly, outbound, now) : undefined), voices.cacheDir, {
        warm: deps.config.env === 'production',
      });
    },
    { prefix: '/v1' },
  );

  return app;
};
