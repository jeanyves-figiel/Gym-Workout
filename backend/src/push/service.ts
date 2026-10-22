import type { DB } from '../db.ts';
import type { ApnsEnv, ApnsSender } from './apns.ts';
import { defaultPrefs, inQuietHours, NotificationPrefs } from './prefs.ts';

/** Kinds of remote notifications. Each maps to a preference toggle. */
export type PushKind = 'follow_achievement' | 'buddy_invite' | 'test';

/** Pushes to followers in flight at once per fan-out, so a member with many followers can't flood APNs or the loop. */
const FAN_OUT_CONCURRENCY = 5;
/** Devices kept per member; registering another drops the least recently registered. */
export const MAX_DEVICES = 10;

/** Runs `fn` over `items` with at most `limit` running at once. */
const forEachLimit = async <T>(items: readonly T[], limit: number, fn: (item: T) => Promise<void>): Promise<void> => {
  let next = 0;
  const worker = async () => {
    while (next < items.length) await fn(items[next++]!);
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
};

export interface Achievement {
  /** Stable id of the achievement (dedupes repeated sends, used as collapse id). */
  id: string;
  /** e.g. "pr", "streak", "milestone". */
  type: string;
  /** Short line, e.g. "New PR: Bench press 100 kg × 3". */
  text: string;
}

interface DeviceRow {
  token: string;
  env: ApnsEnv;
  topic: string;
  tz: string | null;
}

export interface PushServiceDeps {
  db: DB;
  now: () => Date;
  /** Undefined → APNs not configured: sends are skipped (logged once). */
  sender?: ApnsSender;
  log: (msg: string) => void;
  /**
   * Users following `userId`. The follow model lives in Community (#66); until it is wired via
   * `setFollowersProvider`, nobody follows anybody and follow pushes are no-ops.
   */
  followersOf?: (userId: string) => string[];
}

/**
 * Remote push (#69): device registry, preference filter, quiet hours (delivered silently as a passive
 * notification instead of dropped), dead-token cleanup. Never throws to callers: push is best effort.
 */
export class PushService {
  private readonly d: PushServiceDeps;
  private followersOf: (userId: string) => string[];
  private warned = false;
  private readonly pending = new Set<Promise<void>>();

  constructor(d: PushServiceDeps) {
    this.d = d;
    this.followersOf = d.followersOf ?? (() => []);
  }

  get configured(): boolean {
    return !!this.d.sender;
  }

  setFollowersProvider(fn: (userId: string) => string[]): void {
    this.followersOf = fn;
  }

  registerDevice(userId: string, token: string, env: ApnsEnv, topic: string, tz: string | undefined): void {
    const ts = this.d.now().toISOString();
    // A token belongs to one install; a new sign-in on that install takes it over.
    this.d.db
      .prepare(
        `INSERT INTO push_devices (token, user_id, env, topic, tz, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, env = excluded.env, topic = excluded.topic, tz = excluded.tz, updated_at = excluded.updated_at`,
      )
      .run(token, userId, env, topic, tz ?? null, ts, ts);
    this.d.db
      .prepare(
        `DELETE FROM push_devices WHERE user_id = ? AND token NOT IN
           (SELECT token FROM push_devices WHERE user_id = ? ORDER BY updated_at DESC, created_at DESC, token LIMIT ?)`,
      )
      .run(userId, userId, MAX_DEVICES);
  }

  unregisterDevice(userId: string, token: string): void {
    this.d.db.prepare('DELETE FROM push_devices WHERE token = ? AND user_id = ?').run(token, userId);
  }

  deviceCount(userId: string): number {
    return (this.d.db.prepare('SELECT COUNT(*) AS n FROM push_devices WHERE user_id = ?').get(userId) as { n: number }).n;
  }

  prefs(userId: string): NotificationPrefs {
    const row = this.d.db.prepare('SELECT data FROM notification_prefs WHERE user_id = ?').get(userId) as { data: string } | undefined;
    if (!row) return defaultPrefs();
    const parsed = NotificationPrefs.safeParse(JSON.parse(row.data));
    return parsed.success ? parsed.data : defaultPrefs();
  }

  savePrefs(userId: string, p: NotificationPrefs): NotificationPrefs {
    this.d.db
      .prepare(
        'INSERT INTO notification_prefs (user_id, data, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at',
      )
      .run(userId, JSON.stringify(p), this.d.now().toISOString());
    return p;
  }

  /** Resolves once the background fan-outs started so far are done (tests, shutdown). */
  async idle(): Promise<void> {
    while (this.pending.size) await Promise.all([...this.pending]);
  }

  /**
   * Announces achievements the device just unlocked (each id once per user) to followers.
   * Returns the ids that were new at once; the pushes go out in the background (see `idle`).
   */
  announce(actorId: string, actorName: string, list: Achievement[]): string[] {
    const fresh: Achievement[] = [];
    const ts = this.d.now().toISOString();
    for (const a of list) {
      const r = this.d.db
        .prepare('INSERT OR IGNORE INTO achievement_announcements (user_id, achievement_id, created_at) VALUES (?, ?, ?)')
        .run(actorId, a.id, ts);
      if (Number(r.changes) > 0) fresh.push(a);
    }
    if (fresh.length) {
      const job = (async () => {
        for (const a of fresh) await this.notifyFollowers(actorId, actorName, a);
      })()
        .catch((e: Error) => this.d.log(`push: announce failed: ${e.message}`))
        .finally(() => this.pending.delete(job));
      this.pending.add(job);
    }
    return fresh.map((a) => a.id);
  }

  /** `notifyUser` in the background (tracked by `idle`), so the request doesn't wait on APNs. */
  notifyLater(userId: string, kind: PushKind, m: { title: string; body: string; data?: Record<string, string>; collapseId?: string }): void {
    const job = this.notifyUser(userId, kind, m)
      .then(() => undefined)
      .catch((e: Error) => this.d.log(`push: ${kind} failed: ${e.message}`))
      .finally(() => this.pending.delete(job));
    this.pending.add(job);
  }

  /** Tells everyone following `actorId` (who enabled follow alerts) about an achievement. Returns devices reached. */
  async notifyFollowers(actorId: string, actorName: string, a: Achievement): Promise<number> {
    let followers: string[];
    try {
      followers = this.followersOf(actorId).filter((u) => u !== actorId);
    } catch (e) {
      this.d.log(`push: followers lookup failed: ${(e as Error).message}`);
      return 0;
    }
    let sent = 0;
    await forEachLimit(followers, FAN_OUT_CONCURRENCY, async (f) => {
      try {
        sent += await this.notifyUser(f, 'follow_achievement', {
          title: `${actorName} 🏆`,
          body: a.text,
          data: { kind: 'follow_achievement', actorId, actorName, achievementId: a.id, type: a.type },
          collapseId: `ach-${a.id}`.slice(0, 64),
        });
      } catch (e) {
        this.d.log(`push: follower notify failed: ${(e as Error).message}`);
      }
    });
    return sent;
  }

  /** Sends to every device of `userId` unless the matching preference is off. Returns devices reached. */
  async notifyUser(
    userId: string,
    kind: PushKind,
    m: { title: string; body: string; data?: Record<string, string>; collapseId?: string },
  ): Promise<number> {
    const p = this.prefs(userId);
    if (kind === 'follow_achievement' && !p.followAchievements) return 0;
    if (!this.d.sender) {
      if (!this.warned) {
        this.warned = true;
        this.d.log('push: APNs not configured (APNS_KEY_ID / APNS_PRIVATE_KEY not set); skipping remote notifications.');
      }
      return 0;
    }
    const devices = this.d.db.prepare('SELECT token, env, topic, tz FROM push_devices WHERE user_id = ?').all(userId) as unknown as DeviceRow[];
    let sent = 0;
    for (const dev of devices) {
      const quiet = kind !== 'test' && inQuietHours(p, this.d.now(), dev.tz);
      const aps: Record<string, unknown> = {
        alert: { title: m.title, body: m.body },
        'thread-id': kind,
        ...(quiet ? { 'interruption-level': 'passive' } : { sound: 'default' }),
      };
      try {
        const r = await this.d.sender({ token: dev.token, env: dev.env, topic: dev.topic, payload: { aps, ...m.data }, collapseId: m.collapseId });
        if (r.status === 200) sent++;
        else if (r.status === 410 || (r.status === 400 && (r.reason === 'BadDeviceToken' || r.reason === 'DeviceTokenNotForTopic'))) {
          this.d.db.prepare('DELETE FROM push_devices WHERE token = ?').run(dev.token);
        } else this.d.log(`push: APNs ${r.status} ${r.reason ?? ''}`.trim());
      } catch (e) {
        this.d.log(`push: send failed: ${(e as Error).message}`);
      }
    }
    return sent;
  }
}
