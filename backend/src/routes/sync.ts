import { z } from 'zod';
import type { DB } from '../db.ts';

/**
 * `?since=` of the sync pulls (#432), as stored `updated_at` text (`…T10:00:00.000Z`): compared as strings, a
 * `…T10:00:00Z` or `+02:00` since would skip rows of that second. Rows at exactly `since` are sent too (`>=`); the
 * apps merge by id.
 */
export const sinceQuery = z
  .object({ since: z.iso.datetime({ offset: true }).optional() })
  .transform((q) => ({ since: q.since === undefined ? undefined : new Date(q.since).toISOString() }));

/**
 * Keyset cursor for newest-first pages (#432): `before` alone (older apps) skips rows sharing the last timestamp of a
 * full page; with `beforeId` (the page's `nextBeforeId`) ties continue by id. Order by `col DESC, id DESC`.
 */
export const pageCursor = { before: z.iso.datetime({ offset: true }).optional(), beforeId: z.string().min(1).max(64).optional() };

export const beforeSql = (col: string, idCol: string, q: { before?: string; beforeId?: string }): { sql: string; args: string[] } => {
  if (!q.before) return { sql: `${col} < ?`, args: ['9999'] };
  const before = new Date(q.before).toISOString();
  return q.beforeId ? { sql: `(${col} < ? OR (${col} = ? AND ${idCol} < ?))`, args: [before, before, q.beforeId] } : { sql: `${col} < ?`, args: [before] };
};


/** Synced item kinds that keep tombstones (#432); one per `/v1/me/<kind>` route. */
export type SyncKind =
  | 'logs'
  | 'workouts'
  | 'climbs'
  | 'sports'
  | 'pr-attempts'
  | 'body-measurements'
  | 'custom-workouts'
  | 'custom-exercises'
  | 'machine-notes';

/** Tombstones are kept this long; a device offline for longer can upload a deleted item back. */
export const TOMBSTONE_KEEP_DAYS = 180;

/** Records that the member deleted `id` (even when the server never had it: another device may still upload it). */
export const recordTombstone = (db: DB, userId: string, kind: SyncKind, id: string, at: string): void => {
  db.prepare(
    `INSERT INTO sync_tombstones (user_id, kind, item_id, deleted_at) VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id, kind, item_id) DO UPDATE SET deleted_at = excluded.deleted_at`,
  ).run(userId, kind, id, at);
};

/** Ids deleted at or after `since` (already normalised by `sinceQuery`). */
export const deletedSince = (db: DB, userId: string, kind: SyncKind, since: string): string[] =>
  (
    db.prepare('SELECT item_id FROM sync_tombstones WHERE user_id = ? AND kind = ? AND deleted_at >= ? ORDER BY deleted_at').all(userId, kind, since) as {
      item_id: string;
    }[]
  ).map((r) => r.item_id);

/** `deleted` for a since pull: always present (maybe empty) when `since` was given, absent on a full pull. */
export const deletedField = (db: DB, userId: string, kind: SyncKind, since: string | undefined): { deleted?: string[] } =>
  since === undefined ? {} : { deleted: deletedSince(db, userId, kind, since) };

/** Items of an upload whose id the member hasn't deleted: a stale device must not bring a deleted item back. */
export const notDeleted = <T extends { id: string }>(db: DB, userId: string, kind: SyncKind, items: T[]): T[] => {
  const dead = db.prepare('SELECT 1 FROM sync_tombstones WHERE user_id = ? AND kind = ? AND item_id = ?');
  return items.filter((i) => !dead.get(userId, kind, i.id));
};
