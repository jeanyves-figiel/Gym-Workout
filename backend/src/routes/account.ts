import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { EmailChangeService } from '../emailChange.ts';

const email = z.string().trim().toLowerCase().pipe(z.email().max(254));
const code = z.string().regex(/^\d{6}$/, 'Code must be 6 digits');

/** Authenticated account routes added for #12 (change email). Register inside the `/v1` authenticated scope. */
export const accountRoutes = (r: FastifyInstance, emailChange: EmailChangeService, ratePerMin: number) => {
  const limit = { config: { rateLimit: { max: ratePerMin, timeWindow: '1 minute' } } };

  r.post('/me/email', limit, async (req, reply) => {
    const b = z.object({ newEmail: email, password: z.string().min(1).max(256).optional() }).parse(req.body);
    await emailChange.request(req.userId!, b.newEmail, b.password);
    return reply.status(202).send({ status: 'verification_required', message: 'Check the new address for a 6-digit code.' });
  });

  r.post('/me/email/confirm', limit, async (req) => {
    const b = z.object({ code }).parse(req.body);
    return { user: await emailChange.confirm(req.userId!, b.code) };
  });
};
