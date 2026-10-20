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


/** Optional on each uploaded item: the server `updatedAt` the device's edit started from (conflict detection). */
export const baseUpdatedAt = z.iso.datetime({ offset: true }).nullish();

/** Server copy of an opaque synced record, as the pulls send it: stored JSON plus `updatedAt`. */
export const opaqueCopy = (row: { data: string; updated_at: string }) => ({ ...(JSON.parse(row.data) as object), updatedAt: row.updated_at });

/**
 * Optimistic concurrency on uploads: an item with `baseUpdatedAt` is only written when the member's server row isn't
 * newer; otherwise it's left out and its server copy returned in `conflicts` for the app to merge. Items without it
 * overwrite as before. `baseUpdatedAt` is stripped so it never lands in stored JSON. Call inside the upsert's transaction.
 */
export const takeConflicts = <T extends { id: string; baseUpdatedAt?: string | null }, R extends { updated_at: string }>(
  db: DB,
  table: string,
  userId: string,
  items: T[],
  serverCopy: (row: R) => unknown,
): { fresh: T[]; conflicts: unknown[] } => {
  const get = db.prepare(`SELECT * FROM ${table} WHERE id = ? AND user_id = ?`);
  const fresh: T[] = [];
  const conflicts: unknown[] = [];
  for (const { baseUpdatedAt: base, ...item } of items) {
    const row = base ? (get.get(item.id, userId) as R | undefined) : undefined;
    if (row && row.updated_at > new Date(base!).toISOString()) conflicts.push(serverCopy(row));
    else fresh.push(item as T);
  }
  return { fresh, conflicts };
};

/** `conflicts` on an upload answer, only when there are some (older apps never send `baseUpdatedAt`). */
export const conflictsField = (conflicts: unknown[]): { conflicts?: unknown[] } => (conflicts.length ? { conflicts } : {});

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

/**
 * `deleted` for a since pull: always present (maybe empty) when `since` was given, absent on a full pull. With a
 * `since` older than the tombstone retention, deletes may have been purged: `fullResync: true` tells the app to pull
 * everything again (additive; older apps ignore it).
 */
export const deletedField = (
  db: DB,
  userId: string,
  kind: SyncKind,
  since: string | undefined,
  now: Date,
): { deleted?: string[]; fullResync?: true } => {
  if (since === undefined) return {};
  const horizon = new Date(now.getTime() - TOMBSTONE_KEEP_DAYS * 86_400_000).toISOString();
  return { deleted: deletedSince(db, userId, kind, since), ...(since < horizon ? { fullResync: true as const } : {}) };
};

/**
 * An upload of a deleted id brings it back (Undo in the app re-saves the same id): its tombstone goes, so the
 * next since pull of other devices no longer lists it as deleted. Returns the items unchanged.
 */
export const reviveUploaded = <T extends { id: string }>(db: DB, userId: string, kind: SyncKind, items: T[]): T[] => {
  const revive = db.prepare('DELETE FROM sync_tombstones WHERE user_id = ? AND kind = ? AND item_id = ?');
  for (const i of items) revive.run(userId, kind, i.id);
  return items;
};
