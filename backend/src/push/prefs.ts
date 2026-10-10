import { z } from 'zod';

/** Minutes after local midnight (0…1439). */
const minutes = z.number().int().min(0).max(1439);

/**
 * Per-user notification preferences (#69). The device owns them (local reminders are scheduled there);
 * the server keeps a copy to filter and quiet remote pushes. Unknown keys are dropped, missing ones defaulted.
 */
export const NotificationPrefs = z.object({
  sessionReminders: z.boolean().default(true),
  reminderMinutes: minutes.default(7 * 60 + 30),
  missedCheckIn: z.boolean().default(true),
  checkInMinutes: minutes.default(9 * 60),
  followAchievements: z.boolean().default(true),
  quietHours: z.boolean().default(true),
  quietStart: minutes.default(22 * 60),
  quietEnd: minutes.default(7 * 60),
});
export type NotificationPrefs = z.infer<typeof NotificationPrefs>;

export const defaultPrefs = (): NotificationPrefs => NotificationPrefs.parse({});

/** Local minutes after midnight of `at` in IANA zone `tz` (UTC when unknown/invalid). */
export const localMinutes = (at: Date, tz: string | null | undefined): number => {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat('en-GB', { timeZone: tz ?? 'UTC', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at);
  } catch {
    parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'UTC', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at);
  }
  const n = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? 0);
  return n('hour') * 60 + n('minute');
};

/** Quiet window [start, end) in local minutes; wraps midnight when start > end. Empty when start == end. */
export const inQuietHours = (p: NotificationPrefs, at: Date, tz: string | null | undefined): boolean => {
  if (!p.quietHours || p.quietStart === p.quietEnd) return false;
  const m = localMinutes(at, tz);
  return p.quietStart < p.quietEnd ? m >= p.quietStart && m < p.quietEnd : m >= p.quietStart || m < p.quietEnd;
};
