import type { DB } from '../db.ts';

/**
 * Export sections for data kept outside the synced kinds (#713): Garmin watches, reports a member filed, saves and
 * copies of others' workouts and plans, and sign-in settings. Secrets never leave: passkeys by id and name only,
 * 2-step and the Watch key as on/off.
 */
export const accountExport = (db: DB, userId: string): [string, () => unknown][] => [
  [
    'garmin',
    () => ({
      devices: db.prepare('SELECT id, model, created_at AS pairedAt, last_seen AS lastSeen FROM garmin_devices WHERE user_id = ? ORDER BY created_at').all(userId),
      snapshot: ((r) => (r ? { data: JSON.parse(r.data) as unknown, updatedAt: r.updated_at } : null))(
        db.prepare('SELECT data, updated_at FROM garmin_snapshots WHERE user_id = ?').get(userId) as { data: string; updated_at: string } | undefined,
      ),
      inbox: (db.prepare('SELECT id, device_id, data, created_at FROM garmin_inbox WHERE user_id = ? ORDER BY created_at, rowid').all(userId) as {
        id: string;
        device_id: string;
        data: string;
        created_at: string;
      }[]).map((e) => ({ id: e.id, deviceId: e.device_id, event: JSON.parse(e.data) as unknown, receivedAt: e.created_at })),
    }),
  ],
  [
    'communityReportsFiled',
    () =>
      db
        .prepare(
          `SELECT target_type AS targetType, target_id AS targetId, target_user_id AS targetUserId, reason, details, created_at AS createdAt,
             resolved_at AS resolvedAt FROM community_reports WHERE reporter_id = ? ORDER BY created_at`,
        )
        .all(userId),
  ],
  ['librarySaves', () => db.prepare('SELECT workout_id AS workoutId, created_at AS savedAt FROM library_saves WHERE user_id = ? ORDER BY created_at').all(userId)],
  [
    'programCopies',
    () => db.prepare('SELECT program_id AS programId, created_at AS copiedAt FROM community_program_copies WHERE user_id = ? ORDER BY created_at').all(userId),
  ],
  [
    'security',
    () => ({
      passkeys: db.prepare('SELECT id, name, created_at AS createdAt, last_used_at AS lastUsedAt FROM passkeys WHERE user_id = ? ORDER BY created_at').all(userId),
      twoStep: !!db.prepare('SELECT 1 FROM totp_secrets WHERE user_id = ? AND enabled_at IS NOT NULL').get(userId),
      watchKey: !!db.prepare('SELECT 1 FROM watch_keys WHERE user_id = ?').get(userId),
    }),
  ],
];
