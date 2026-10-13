import type { DB } from '../db.ts';

/** Community tables (#61). Idempotent like schemaExtras; every row cascades with its user. */
export const ensureCommunitySchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS community_profiles (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      nickname TEXT NOT NULL UNIQUE COLLATE NOCASE,
      bio TEXT,
      avatar_id TEXT,
      default_visibility TEXT NOT NULL DEFAULT 'private' CHECK (default_visibility IN ('private', 'members', 'public')),
      auto_share INTEGER NOT NULL DEFAULT 0,
      guidelines_accepted_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    -- Account profile (#108) of users who have not joined the community. Members keep it in community_profiles;
    -- joining moves it there, leaving moves it back, so nickname, photo and about are set once for both screens.
    CREATE TABLE IF NOT EXISTS user_profiles (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      nickname TEXT UNIQUE COLLATE NOCASE,
      bio TEXT,
      avatar_id TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS community_avatars (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      data BLOB NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS community_avatars_user ON community_avatars(user_id);
    CREATE TABLE IF NOT EXISTS community_posts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('workout', 'badge', 'record', 'climb', 'note')),
      ref_id TEXT,
      visibility TEXT NOT NULL CHECK (visibility IN ('private', 'members', 'public')),
      caption TEXT,
      payload TEXT NOT NULL,
      hidden_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS community_posts_created ON community_posts(created_at);
    CREATE INDEX IF NOT EXISTS community_posts_user ON community_posts(user_id, created_at);
    CREATE UNIQUE INDEX IF NOT EXISTS community_posts_ref ON community_posts(user_id, kind, ref_id) WHERE ref_id IS NOT NULL;
    CREATE TABLE IF NOT EXISTS community_reactions (
      post_id TEXT NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('like', 'strong', 'fire', 'clap')),
      created_at TEXT NOT NULL,
      PRIMARY KEY (post_id, user_id, kind)
    );
    CREATE TABLE IF NOT EXISTS community_blocks (
      blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (blocker_id, blocked_id)
    );
    CREATE TABLE IF NOT EXISTS community_follows (
      follower_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      followed_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (follower_id, followed_id)
    );
    CREATE INDEX IF NOT EXISTS community_follows_followed ON community_follows(followed_id);
    CREATE TABLE IF NOT EXISTS community_reports (
      id TEXT PRIMARY KEY,
      reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      target_type TEXT,
      target_id TEXT,
      target_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
      reason TEXT NOT NULL,
      details TEXT,
      created_at TEXT NOT NULL,
      resolved_at TEXT
    );
    CREATE INDEX IF NOT EXISTS community_reports_target ON community_reports(target_type, target_id);
  `);
  // Show my gym (#152): members opt in to being found by the gym they train at.
  const cols = db.prepare('PRAGMA table_info(community_profiles)').all() as { name: string }[];
  if (!cols.some((c) => c.name === 'show_gym')) db.exec('ALTER TABLE community_profiles ADD COLUMN show_gym INTEGER NOT NULL DEFAULT 0');
  // Game level (#242): the app reports it so members see each other's rank title (Regular+) and Legend badge.
  if (!cols.some((c) => c.name === 'level')) db.exec('ALTER TABLE community_profiles ADD COLUMN level INTEGER');
};
