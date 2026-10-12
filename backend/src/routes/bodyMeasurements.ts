import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';

/** Body measurements (#185): one dated entry of girths (cm), weight and body fat; extra app fields kept as is. */
const cm = z.number().min(5).max(300);
const bodyMeasurement = z
  .object({
    id: z.uuid(),
    date: z.iso.datetime({ offset: true }),
    girthsCm: z.record(z.string().min(1).max(32), cm).optional(),
    weightKg: z.number().min(20).max(400).optional(),
    bodyFatPct: z.number().min(2).max(75).optional(),
  })
  .catchall(z.unknown());

export const listBodyMeasurements = (db: DB, userId: string, since?: string) =>
  (
    (since
      ? db.prepare('SELECT data, updated_at FROM body_measurements WHERE user_id = ? AND updated_at > ? ORDER BY date').all(userId, since)
      : db.prepare('SELECT data, updated_at FROM body_measurements WHERE user_id = ? ORDER BY date').all(userId)) as unknown as {
      data: string;
      updated_at: string;
    }[]
  ).map((r) => ({ ...(JSON.parse(r.data) as object), updatedAt: r.updated_at }));

export const bodyMeasurementRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/body-measurements', async (req) => {
    const q = z.object({ since: z.iso.datetime({ offset: true }).optional() }).parse(req.query);
    return { measurements: listBodyMeasurements(db, req.userId!, q.since), serverTime: now().toISOString() };
  });

  r.post('/me/body-measurements', async (req) => {
    const b = z.object({ measurements: z.array(bodyMeasurement).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO body_measurements (id, user_id, date, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET date = excluded.date, data = excluded.data, updated_at = excluded.updated_at
       WHERE body_measurements.user_id = excluded.user_id`,
    );
    tx(db, () => {
      for (const m of b.measurements) {
        const json = JSON.stringify(m);
        if (json.length > 5_000) throw Object.assign(new Error('Measurement too large'), { statusCode: 413 });
        up.run(m.id, req.userId!, m.date, json, ts);
      }
    });
    return { saved: b.measurements.length, serverTime: ts };
  });

  r.delete('/me/body-measurements/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    db.prepare('DELETE FROM body_measurements WHERE id = ? AND user_id = ?').run(id, req.userId!);
    return reply.status(204).send();
  });
};
