import { z } from 'zod';

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

