import { randomUUID } from 'node:crypto';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { containsObjectionable } from './filter.ts';

export { containsObjectionable };

/**
 * Reusable sharing + moderation building blocks (#61) for any member-shared item
 * (community posts today; shared workouts next). Item types are app-defined strings.
 */

export const VISIBILITIES = ['private', 'members', 'public'] as const;
export type Visibility = (typeof VISIBILITIES)[number];
export const REPORT_REASONS = ['spam', 'harassment', 'hate', 'sexual', 'violence', 'other'] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];
/** Distinct open reports after which an item should be hidden pending review. */
export const AUTO_HIDE_REPORTS = 3;

/** 400 objectionable_content when any text trips the filter. */
export const assertClean = (...texts: (string | null | undefined)[]) => {
  if (texts.some(containsObjectionable))
    throw new ApiError(400, 'objectionable_content', 'Please keep it friendly: that text is not allowed in the community.');
};

/** Either member blocked the other. */
export const isBlockedBetween = (db: DB, a: string, b: string) =>
  !!db.prepare('SELECT 1 FROM community_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)').get(a, b, b, a);

/**
 * SQL predicate: `ownerCol`'s item is visible to a viewer who is not its owner (shared, not hidden,
 * no block either way). Binds the viewer id twice.
 */
export const visibleToOthersSql = (ownerCol: string, visibilityCol: string, hiddenCol: string) =>
  `${hiddenCol} IS NULL AND ${visibilityCol} IN ('members', 'public')
   AND NOT EXISTS (SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ? AND b.blocked_id = ${ownerCol}) OR (b.blocker_id = ${ownerCol} AND b.blocked_id = ?))`;

/**
 * Members following `userId` who may be told about their shared wins: still in the community and
 * no block either way. For push fan-out (notifications).
 */
export const followerIds = (db: DB, userId: string): string[] =>
  (
    db
      .prepare(
        `SELECT f.follower_id AS id FROM community_follows f JOIN community_profiles cp ON cp.user_id = f.follower_id
         WHERE f.followed_id = ? AND NOT EXISTS (SELECT 1 FROM community_blocks b
           WHERE (b.blocker_id = f.follower_id AND b.blocked_id = ?) OR (b.blocker_id = ? AND b.blocked_id = f.follower_id))`,
      )
      .all(userId, userId, userId) as { id: string }[]
  ).map((r) => r.id);

/** Member created a community profile, which requires accepting the community guidelines. */
export const hasAcceptedGuidelines = (db: DB, userId: string) =>
  !!db.prepare('SELECT 1 FROM community_profiles WHERE user_id = ?').get(userId);

export interface ReportInput {
  reporterId: string;
  /** e.g. 'post', 'workout'; null with targetId null for a report about a member only. */
  targetType: string | null;
  targetId: string | null;
  /** Owner of the reported item, or the reported member. */
  targetUserId: string | null;
  reason: ReportReason;
  details?: string | null;
  /** ISO timestamp; defaults to now. */
  at?: string;
}

/** Stores a report; returns the number of distinct open reporters on that target (0 for member-only reports). */
export const reportContent = (db: DB, r: ReportInput): number => {
  if (r.targetUserId === r.reporterId) throw new ApiError(400, 'own_content', 'You cannot report yourself.');
  db.prepare(
    'INSERT INTO community_reports (id, reporter_id, target_type, target_id, target_user_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  ).run(randomUUID(), r.reporterId, r.targetType, r.targetId, r.targetUserId, r.reason, r.details || null, r.at ?? new Date().toISOString());
  return r.targetType && r.targetId ? openReporters(db, r.targetType, r.targetId) : 0;
};

const openReporters = (db: DB, targetType: string, targetId: string) =>
  (
    db
      .prepare('SELECT COUNT(DISTINCT reporter_id) AS n FROM community_reports WHERE target_type = ? AND target_id = ? AND resolved_at IS NULL')
      .get(targetType, targetId) as { n: number }
  ).n;

/** Hidden pending review: at least AUTO_HIDE_REPORTS distinct members reported it (open reports). */
export const isHidden = (db: DB, targetType: string, targetId: string) => openReporters(db, targetType, targetId) >= AUTO_HIDE_REPORTS;
