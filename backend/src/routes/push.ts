import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ApiError } from '../errors.ts';
import { NotificationPrefs } from '../push/prefs.ts';
import type { PushService } from '../push/service.ts';

const token = z.string().regex(/^[0-9a-fA-F]{32,200}$/, 'Invalid device token').transform((s) => s.toLowerCase());

/** Push device registration + notification preferences (#69). */
export const pushRoutes = (r: FastifyInstance, push: PushService, topics: string[], nameOf: (userId: string) => string | null) => {
  /** Achievements unlocked on the device (badges, PRs). Followers get a push for each one, once. */
  r.post('/me/achievements', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req) => {
    const b = z
      .object({
        achievements: z
          .array(z.object({ id: z.string().min(1).max(100), type: z.string().min(1).max(40), text: z.string().trim().min(1).max(140) }))
          .max(30),
      })
      .parse(req.body);
    const announced = await push.announce(req.userId!, nameOf(req.userId!) ?? 'Someone you follow', b.achievements);
    return { announced };
  });

  r.put('/me/push-device', async (req) => {
    const b = z
      .object({ token, env: z.enum(['sandbox', 'production']), topic: z.string().max(200), tz: z.string().max(64).optional() })
      .parse(req.body);
    if (!topics.some((t) => t.toLowerCase() === b.topic.toLowerCase())) throw new ApiError(400, 'invalid_topic', 'Unknown app bundle id.');
    push.registerDevice(req.userId!, b.token, b.env, b.topic, b.tz);
    return { ok: true, pushConfigured: push.configured };
  });

  r.delete('/me/push-device/:token', async (req, reply) => {
    const { token: t } = z.object({ token }).parse(req.params);
    push.unregisterDevice(req.userId!, t);
    return reply.status(204).send();
  });

  r.get('/me/notification-prefs', async (req) => ({ prefs: push.prefs(req.userId!), pushConfigured: push.configured }));

  r.put('/me/notification-prefs', async (req) => {
    const b = z.object({ prefs: NotificationPrefs }).parse(req.body);
    return { prefs: push.savePrefs(req.userId!, b.prefs) };
  });

  /** Sends a test push to the caller's devices (Settings → Send test). */
  r.post('/me/push-test', { config: { rateLimit: { max: 5, timeWindow: '1 minute' } } }, async (req) => {
    const devices = push.deviceCount(req.userId!);
    const sent = await push.notifyUser(req.userId!, 'test', { title: 'MonkeyWorkout', body: 'Push notifications work 💪', data: { kind: 'test' } });
    return { devices, sent, pushConfigured: push.configured };
  });
};
