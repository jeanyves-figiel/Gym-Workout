import { Readable } from 'node:stream';
import type { FastifyReply } from 'fastify';
import { z } from 'zod';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';

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

/**
 * Client id of a synced item (#714), lower-cased on parse for uploads and `DELETE /me/<kind>/:id`: the app sends
 * `UUID.uuidString` (upper case) while other clients may not, and `id = ?` is case-sensitive, so one item could become
 * two rows or a delete could miss. Stored ids were lower-cased once (`ensureSchemaExtras`).
 */
export const syncId = z.uuid().transform((s) => s.toLowerCase());
export const syncIdParams = z.object({ id: syncId });

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

/**
 * One synced table as the pulls and the export read it (#712). `cols` are what `map` needs; `timeCol` is the
 * record's own instant (client text, any offset): the export sorts by it as a time, not as text (#714).
 */
export interface SyncTable<R = never> {
  table: string;
  cols: string;
  timeCol: string;
  map: (row: R) => unknown;
}

/** Rows read per query: a pull or export never holds every row in one array, nor a statement open between chunks. */
const CHUNK = 500;

interface Cursor {
  ts: string;
  id: string;
}

/**
 * Rows of `userId` changed at or after `since`, oldest change first by `(updated_at, id)` (the index the since pulls
 * use), from `after` on. Read in keyset chunks, so a full pull of a large account never sits in memory and no
 * statement stays open while the response streams (a pending read would make `VACUUM INTO` backups fail).
 */
export function* changedRows<R>(db: DB, t: SyncTable<R>, userId: string, since = '', after?: Cursor): Generator<R & Cursor> {
  let cur = after;
  for (;;) {
    const rows = db
      .prepare(
        `SELECT ${t.cols}, id AS _id, updated_at AS _ts FROM ${t.table} WHERE user_id = ? AND updated_at >= ?
         ${cur ? 'AND (updated_at > ? OR (updated_at = ? AND id > ?))' : ''} ORDER BY updated_at, id LIMIT ?`,
      )
      .all(userId, since, ...(cur ? [cur.ts, cur.ts, cur.id] : []), CHUNK) as unknown as (R & { _id: string; _ts: string })[];
    for (const r of rows) yield Object.assign(r, { ts: r._ts, id: r._id });
    if (rows.length < CHUNK) return;
    cur = { ts: rows.at(-1)!._ts, id: rows.at(-1)!._id };
  }
}

/** Every row of `userId` in the order of its own instant (`julianday(timeCol)`, indexed), for the export; mapped. */
export function* timeOrderedRows<R>(db: DB, t: SyncTable<R>, userId: string): Generator<unknown> {
  const key = `COALESCE(julianday(${t.timeCol}), 0)`;
  let cur: { k: number; id: string } | undefined;
  for (;;) {
    const rows = db
      .prepare(
        `SELECT ${t.cols}, id AS _id, ${key} AS _k FROM ${t.table} WHERE user_id = ?
         ${cur ? `AND (${key} > ? OR (${key} = ? AND id > ?))` : ''} ORDER BY ${key}, id LIMIT ?`,
      )
      .all(userId, ...(cur ? [cur.k, cur.k, cur.id] : []), CHUNK) as unknown as (R & { _id: string; _k: number })[];
    for (const r of rows) yield t.map(r);
    if (rows.length < CHUNK) return;
    cur = { k: rows.at(-1)!._k, id: rows.at(-1)!._id };
  }
}

/** `?since=` plus optional paging (#712): `limit` (1–1000) rows per page, `cursor` = the last page's `nextCursor`. */
export const pullQuery = z
  .object({
    since: z.iso.datetime({ offset: true }).optional(),
    limit: z.coerce.number().int().min(1).max(1000).optional(),
    cursor: z.string().max(200).optional(),
  })
  .transform((q) => {
    let after: Cursor | undefined;
    if (q.cursor) {
      const [ts, id] = Buffer.from(q.cursor, 'base64url').toString().split('|');
      if (!ts || !id) throw new ApiError(400, 'invalid_request', 'Invalid cursor.');
      after = { ts, id };
    }
    return { since: q.since === undefined ? undefined : new Date(q.since).toISOString(), limit: q.limit, after };
  });

const cursorOf = (c: Cursor) => Buffer.from(`${c.ts}|${c.id}`).toString('base64url');

/**
 * Answers `GET /me/<kind>` (#712): `{<key>: [...], deleted?, fullResync?, serverTime, nextCursor?}`.
 * With `limit`: one page in `(updated_at, id)` order and `nextCursor` (null on the last page); keep the first page's
 * `serverTime` as the next `since`. Without it (every app build so far): all rows, streamed as they are read, so the
 * answer is the same JSON as before without building it in memory.
 */
export const sendPull = <R>(
  reply: FastifyReply,
  db: DB,
  t: SyncTable<R>,
  opts: { key: string; kind: SyncKind; userId: string; query: unknown; now: () => Date },
) => {
  const q = pullQuery.parse(opts.query);
  const serverTime = opts.now().toISOString();
  const extra = { ...deletedField(db, opts.userId, opts.kind, q.since, opts.now()), serverTime };
  if (q.limit !== undefined) {
    const page: unknown[] = [];
    let last: Cursor | undefined;
    let more = false;
    for (const r of changedRows(db, t, opts.userId, q.since, q.after)) {
      if (page.length === q.limit) {
        more = true;
        break;
      }
      page.push(t.map(r));
      last = { ts: r.ts, id: r.id };
    }
    return reply.send({ [opts.key]: page, ...extra, nextCursor: more && last ? cursorOf(last) : null });
  }
  async function* body() {
    yield `{${JSON.stringify(opts.key)}:[`;
    let buf = '';
    let first = true;
    for (const r of changedRows(db, t, opts.userId, q.since)) {
      buf += (first ? '' : ',') + JSON.stringify(t.map(r));
      first = false;
      if (buf.length >= 64_000) {
        yield buf;
        buf = '';
      }
    }
    yield `${buf}]${JSON.stringify(extra).replace(/^\{/, ',')}`;
  }
  reply.type('application/json; charset=utf-8');
  return reply.send(Readable.from(body()));
};
