import { z } from 'zod';

/**
 * `?since=` of the sync pulls (#432), as stored `updated_at` text (`…T10:00:00.000Z`): compared as strings, a
 * `…T10:00:00Z` or `+02:00` since would skip rows of that second. Rows at exactly `since` are sent too (`>=`); the
 * apps merge by id.
 */
export const sinceQuery = z
  .object({ since: z.iso.datetime({ offset: true }).optional() })
  .transform((q) => ({ since: q.since === undefined ? undefined : new Date(q.since).toISOString() }));

