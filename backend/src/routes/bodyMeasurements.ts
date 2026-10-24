import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, opaqueCopy, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts } from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';

/** Body measurements (#185): one dated entry of girths (cm), weight and body fat; extra app fields kept as is. */
const cm = z.number().min(5).max(300);
const bodyMeasurement = z
  .object({
    id: syncId,
    baseUpdatedAt,
    date: z.iso.datetime({ offset: true }),
    girthsCm: z.record(z.string().min(1).max(32), cm).optional(),
    weightKg: z.number().min(20).max(400).optional(),
    bodyFatPct: z.number().min(2).max(75).optional(),
  })
  .catchall(z.unknown());

export const bodyMeasurementTable: SyncTable<{ data: string; updated_at: string }> = {
  table: 'body_measurements',
  cols: 'data, updated_at',
  timeCol: 'date',
  map: opaqueCopy,
};

export const bodyMeasurementRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/me/body-measurements', async (req, reply) =>
    sendPull(reply, db, bodyMeasurementTable, { key: 'measurements', kind: 'body-measurements', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/body-measurements', async (req) => {
    const b = z.object({ measurements: z.array(bodyMeasurement).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO body_measurements (id, user_id, date, data, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET date = excluded.date, data = excluded.data, updated_at = excluded.updated_at
       WHERE body_measurements.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'body_measurements', req.userId!, b.measurements, opaqueCopy);
      const measurements = reviveUploaded(db, req.userId!, 'body-measurements', fresh);
      const jsons = measurements.map((m) => JSON.stringify(m));
      for (const j of jsons) assertItemSize(j, 5_000, 'Measurement');
      assertRowQuota(db, 'body_measurements', req.userId!, measurements.map((m) => m.id));
      assertByteQuota(db, 'body_measurements', req.userId!, measurements.map((m, i) => ({ id: m.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      measurements.forEach((m, i) => (count += Number(up.run(m.id, req.userId!, m.date, jsons[i]!, ts).changes)));
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/body-measurements/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM body_measurements WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'body-measurements', id, now().toISOString());
    });
    return reply.status(204).send();
  });
};
