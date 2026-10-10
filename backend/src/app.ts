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
import { accountRoutes } from './routes/account.ts';
import { communityPublicRoutes, communityRoutes } from './routes/community.ts';
import { customWorkoutRoutes } from './routes/customWorkouts.ts';
import { prAttemptRoutes } from './routes/prAttempts.ts';
import { dataRoutes } from './routes/data.ts';

declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
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
  const emailChange = new EmailChangeService({ db: deps.db, config: deps.config, mailer: deps.mailer, now });

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

  // Mail transport is exposed so the staging smoke test can tell real delivery from console logging.
  app.get('/healthz', async () => ({ ok: true, mail: deps.config.mail.transport }));

  communityPublicRoutes(app, deps.db, deps.config.appName);

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

      r.post('/me/password', async (req) => {
        const b = z.object({ currentPassword: password.optional(), newPassword: password }).parse(req.body);
        return { tokens: await auth.changePassword(req.userId!, b.currentPassword, b.newPassword, device(req)) };
      });

      r.get('/me/sessions', async (req) => ({ sessions: auth.sessions(req.userId!) }));

      r.post('/me/logout-all', async (req, reply) => {
        auth.revokeAll(req.userId!);
        return reply.status(204).send();
      });

      r.delete('/me', async (req, reply) => {
        const b = z.object({ password: password.optional(), confirm: z.literal('DELETE') }).parse(req.body ?? {});
        await auth.deleteAccount(req.userId!, b.password);
        return reply.status(204).send();
      });

      dataRoutes(r, deps.db, deps.now ?? (() => new Date()), auth);
      accountRoutes(r, emailChange, deps.config.authRateLimitPerMin);
      customWorkoutRoutes(r, deps.db, deps.now ?? (() => new Date()));
      communityRoutes(r, deps.db, now, deps.mailer, deps.config.moderationEmail);
      prAttemptRoutes(r, deps.db, deps.now ?? (() => new Date()));
    },
    { prefix: '/v1' },
  );

  return app;
};
