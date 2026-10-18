import type { AuthenticationResponseJSON, RegistrationResponseJSON } from '@simplewebauthn/server';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { SecurityService } from '../security.ts';

/** Header carrying the 5-minute grant from `POST /v1/me/reauth` (#257). */
export const reauthToken = (req: FastifyRequest) => (req.headers['x-reauth-token'] as string | undefined) || undefined;

const code = z.string().regex(/^\d{6}$/, 'Code must be 6 digits');
// WebAuthn JSON is verified by @simplewebauthn; only bound its size here.
const webauthnJson = z.record(z.string(), z.unknown()).refine((o) => JSON.stringify(o).length < 20_000, 'Too large');
const device = (req: FastifyRequest) => (req.headers['x-device-name'] as string | undefined) ?? req.headers['user-agent'];

/** Public: 2-step completion, passkey sign-in, Apple app-site association. */
export const securityPublicRoutes = (app: FastifyInstance, security: SecurityService, ratePerMin: number) => {
  const limit = { config: { rateLimit: { max: ratePerMin, timeWindow: '1 minute' } } };

  app.get('/.well-known/apple-app-site-association', async (_req, reply) => {
    const body = security.appSiteAssociation();
    if (!body) return reply.status(404).send({ error: 'not_found', message: 'Not configured.' });
    return reply.header('content-type', 'application/json').send(body);
  });

  app.register(
    async (r) => {
      r.post('/mfa', limit, async (req) => {
        const b = z
          .object({ mfaToken: z.string().min(10).max(200), code: code.optional(), recoveryCode: z.string().min(6).max(32).optional() })
          .refine((x) => !!x.code !== !!x.recoveryCode, 'Send either code or recoveryCode')
          .parse(req.body);
        return security.completeMfa(b.mfaToken, b);
      });

      r.post('/passkey/options', limit, async () => security.loginOptions());

      r.post('/passkey', limit, async (req) => {
        const b = z.object({ challengeId: z.uuid(), response: webauthnJson }).parse(req.body);
        return security.loginWithPasskey(b.challengeId, b.response as unknown as AuthenticationResponseJSON, device(req));
      });
    },
    { prefix: '/v1/auth' },
  );
};

/** Authenticated (inside `/v1`): re-auth, 2-step, passkeys. */
export const securityRoutes = (r: FastifyInstance, security: SecurityService, ratePerMin: number) => {
  const limit = { config: { rateLimit: { max: ratePerMin, timeWindow: '1 minute' } } };
  const sudo = async (req: FastifyRequest) => security.requireReauth(req.userId!, reauthToken(req));

  r.get('/me/security', async (req) => security.overview(req.userId!));

  r.post('/me/reauth/email-code', limit, async (req, reply) => {
    await security.sendReauthCode(req.userId!);
    return reply.status(202).send({ status: 'sent' });
  });

  r.post('/me/reauth/passkey-options', limit, async (req) => security.passkeyReauthOptions(req.userId!));

  r.post('/me/reauth', limit, async (req) => {
    const b = z
      .discriminatedUnion('method', [
        z.object({ method: z.literal('password'), password: z.string().min(1).max(256) }),
        z.object({ method: z.literal('apple'), identityToken: z.string().min(10).max(5000), nonce: z.string().min(16).max(128).optional() }),
        z.object({ method: z.literal('email_code'), code }),
        z.object({ method: z.literal('totp'), code }),
        z.object({ method: z.literal('passkey'), challengeId: z.uuid(), response: webauthnJson }),
      ])
      .parse(req.body);
    return security.reauth(
      req.userId!,
      b.method === 'passkey' ? { ...b, response: b.response as unknown as AuthenticationResponseJSON } : b,
    );
  });

  // 2-step
  r.post('/me/mfa/totp/setup', limit, async (req) => {
    await sudo(req);
    return security.totpSetup(req.userId!);
  });
  r.post('/me/mfa/totp/enable', limit, async (req) => {
    await sudo(req);
    return security.enableTotp(req.userId!, z.object({ code }).parse(req.body).code);
  });
  r.post('/me/mfa/recovery-codes', limit, async (req) => {
    await sudo(req);
    return security.regenerateRecoveryCodes(req.userId!);
  });
  r.delete('/me/mfa', limit, async (req, reply) => {
    await sudo(req);
    await security.disableTotp(req.userId!);
    return reply.status(204).send();
  });

  // passkeys
  r.get('/me/passkeys', async (req) => ({ passkeys: security.passkeys(req.userId!) }));
  r.post('/me/passkeys/options', limit, async (req) => {
    await sudo(req);
    return security.registrationOptions(req.userId!);
  });
  r.post('/me/passkeys', limit, async (req) => {
    await sudo(req);
    const b = z.object({ challengeId: z.uuid(), response: webauthnJson, name: z.string().trim().max(60).optional() }).parse(req.body);
    return { passkeys: await security.addPasskey(req.userId!, b.challengeId, b.response as unknown as RegistrationResponseJSON, b.name) };
  });
  r.patch('/me/passkeys/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1).max(512) }).parse(req.params);
    const b = z.object({ name: z.string().trim().min(1).max(60) }).parse(req.body);
    return { passkeys: security.renamePasskey(req.userId!, id, b.name) };
  });
  r.delete('/me/passkeys/:id', limit, async (req) => {
    await sudo(req);
    const { id } = z.object({ id: z.string().min(1).max(512) }).parse(req.params);
    return { passkeys: await security.deletePasskey(req.userId!, id) };
  });
};
