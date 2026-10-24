import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { sanitizeJpeg } from '../community/image.ts';
import { type DB, tx } from '../db.ts';
import { baseUpdatedAt, conflictsField, reviveUploaded, recordTombstone, sendPull, type SyncTable, syncId, syncIdParams, takeConflicts, timeOrderedRows } from './sync.ts';
import { assertByteQuota, assertItemSize, assertRowQuota } from '../quota.ts';
import { ApiError } from '../errors.ts';

/**
 * Machine setup notes (#355): a member's settings for one exercise at one gym (seat 4, pad 2…), quick fields + text
 * + one photo. Private: never shown to other members; photos are served only to their owner. Synced like climbs.
 */
const note = z
  .object({
    id: syncId,
    baseUpdatedAt,
    gymId: z.string().min(1).max(200),
    gymName: z.string().max(120),
    exerciseId: z.string().min(1).max(128),
    equipment: z.string().max(40).nullish(),
    fields: z.array(z.object({ label: z.string().min(1).max(24), value: z.string().max(24) })).max(8),
    text: z.string().max(1000).nullish(),
  })
  .catchall(z.unknown());

interface Row {
  data: string;
  photo_id: string | null;
  updated_at: string;
}

const toNote = (r: Row) => ({ ...(JSON.parse(r.data) as object), photoId: r.photo_id, updatedAt: r.updated_at });

const noteTable: SyncTable<Row> = { table: 'machine_notes', cols: 'data, photo_id, updated_at', timeCol: 'updated_at', map: toNote };

/** Export: notes with their photos inline (base64 JPEG), one at a time. */
export function* machineNoteExport(db: DB, userId: string): Generator<unknown> {
  const photo = db.prepare('SELECT data FROM machine_note_photos WHERE id = ? AND user_id = ?');
  for (const n of timeOrderedRows(db, noteTable, userId) as Generator<ReturnType<typeof toNote>>) {
    const p = n.photoId ? (photo.get(n.photoId, userId) as { data: Uint8Array } | undefined) : undefined;
    yield { ...n, photoJpegBase64: p ? Buffer.from(p.data).toString('base64') : null };
  }
}

export const machineNoteRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  const owned = (id: string, userId: string) =>
    db.prepare('SELECT photo_id FROM machine_notes WHERE id = ? AND user_id = ?').get(id, userId) as { photo_id: string | null } | undefined;

  r.get('/me/machine-notes', async (req, reply) =>
    sendPull(reply, db, noteTable, { key: 'notes', kind: 'machine-notes', userId: req.userId!, query: req.query, now }),
  );

  r.post('/me/machine-notes', async (req) => {
    const b = z.object({ notes: z.array(note).max(200) }).parse(req.body);
    const ts = now().toISOString();
    const up = db.prepare(
      `INSERT INTO machine_notes (id, user_id, gym_id, exercise_id, data, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET gym_id = excluded.gym_id, exercise_id = excluded.exercise_id, data = excluded.data, updated_at = excluded.updated_at
       WHERE machine_notes.user_id = excluded.user_id`,
    );
    const { saved, conflicts } = tx(db, () => {
      const { fresh, conflicts } = takeConflicts(db, 'machine_notes', req.userId!, b.notes, toNote);
      const notes = reviveUploaded(db, req.userId!, 'machine-notes', fresh);
      const jsons = notes.map((n) => {
        const { photoId: _p, updatedAt: _u, ...rest } = n as typeof n & { photoId?: unknown; updatedAt?: unknown };
        return JSON.stringify(rest);
      });
      for (const j of jsons) assertItemSize(j, 10_000, 'Note');
      assertRowQuota(db, 'machine_notes', req.userId!, notes.map((n) => n.id));
      assertByteQuota(db, 'machine_notes', req.userId!, notes.map((n, i) => ({ id: n.id, bytes: Buffer.byteLength(jsons[i]!) })));
      let count = 0;
      notes.forEach((n, i) => (count += Number(up.run(n.id, req.userId!, n.gymId, n.exerciseId, jsons[i]!, ts).changes)));
      return { saved: count, conflicts };
    });
    return { saved, serverTime: ts, ...conflictsField(conflicts) };
  });

  r.delete('/me/machine-notes/:id', async (req, reply) => {
    const { id } = syncIdParams.parse(req.params);
    tx(db, () => {
      db.prepare('DELETE FROM machine_note_photos WHERE note_id = ? AND user_id = ?').run(id, req.userId!);
      db.prepare('DELETE FROM machine_notes WHERE id = ? AND user_id = ?').run(id, req.userId!);
      recordTombstone(db, req.userId!, 'machine-notes', id, now().toISOString());
    });
    return reply.status(204).send();
  });

  /** Replaces the note's photo (JPEG, EXIF stripped); the note must be synced first. */
  r.put('/me/machine-notes/:id/photo', async (req) => {
    const { id } = syncIdParams.parse(req.params);
    if (!owned(id, req.userId!)) throw new ApiError(404, 'not_found', 'Not found.');
    if (!Buffer.isBuffer(req.body)) throw new ApiError(415, 'unsupported_media_type', 'Send the photo as image/jpeg.');
    const img = sanitizeJpeg(req.body);
    const photoId = randomUUID();
    const ts = now().toISOString();
    tx(db, () => {
      assertByteQuota(db, 'machine_note_photos', req.userId!, [{ id, bytes: img.data.length }]);
      db.prepare('DELETE FROM machine_note_photos WHERE note_id = ? AND user_id = ?').run(id, req.userId!);
      db.prepare('INSERT INTO machine_note_photos (id, user_id, note_id, data, created_at) VALUES (?, ?, ?, ?, ?)').run(photoId, req.userId!, id, img.data, ts);
      db.prepare('UPDATE machine_notes SET photo_id = ?, updated_at = ? WHERE id = ? AND user_id = ?').run(photoId, ts, id, req.userId!);
    });
    return { photoId, updatedAt: ts };
  });

  r.delete('/me/machine-notes/:id/photo', async (req) => {
    const { id } = syncIdParams.parse(req.params);
    if (!owned(id, req.userId!)) throw new ApiError(404, 'not_found', 'Not found.');
    const ts = now().toISOString();
    tx(db, () => {
      db.prepare('DELETE FROM machine_note_photos WHERE note_id = ? AND user_id = ?').run(id, req.userId!);
      db.prepare('UPDATE machine_notes SET photo_id = NULL, updated_at = ? WHERE id = ? AND user_id = ?').run(ts, id, req.userId!);
    });
    return { photoId: null, updatedAt: ts };
  });

  /** Owner only: photos of a member's gym are never public. */
  r.get('/me/machine-notes/photos/:photoId', async (req, reply) => {
    const { photoId } = z.object({ photoId: z.uuid() }).parse(req.params);
    const row = db.prepare('SELECT data FROM machine_note_photos WHERE id = ? AND user_id = ?').get(photoId, req.userId!) as { data: Uint8Array } | undefined;
    if (!row) throw new ApiError(404, 'not_found', 'Not found.');
    return reply
      .header('Content-Type', 'image/jpeg')
      .header('Cache-Control', 'private, max-age=31536000, immutable')
      .header('X-Content-Type-Options', 'nosniff')
      .send(Buffer.from(row.data));
  });
};
