import type { DB } from '../db.ts';
import { nameKey } from '../gymSchema.ts';

export interface Gym {
  id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
}

/** The app's default gym when a training profile has none (`Gym.puls5` in WorkoutEngine). */
export const DEFAULT_GYM: Gym = { id: 'fitnesspark-puls5', name: 'Fitnesspark Puls 5', latitude: null, longitude: null };

/**
 * Gym from a training profile (`profile.gym`, app-owned JSON). No gym saved = the app's default scoped gym.
 * Null without a training profile, or when it can't be read.
 */
export const gymFromProfile = (data: string | undefined): Gym | null => {
  if (data === undefined) return null;
  try {
    const g = (JSON.parse(data) as { profile?: { gym?: Partial<Gym> | null } }).profile?.gym;
    return g?.id && g.name ? { id: g.id, name: g.name, latitude: g.latitude ?? null, longitude: g.longitude ?? null } : DEFAULT_GYM;
  } catch {
    return null;
  }
};

/**
 * Copies the member's training-profile gym onto their community profile (#715), so member search and "at your gym"
 * read indexed columns instead of every member's profile JSON. Called when either profile is saved.
 */
export const refreshMemberGym = (db: DB, userId: string): void => {
  const g = gymFromProfile((db.prepare('SELECT data FROM profiles WHERE user_id = ?').get(userId) as { data: string } | undefined)?.data);
  db.prepare('UPDATE community_profiles SET gym_id = ?, gym_name = ?, gym_key = ?, gym_lat = ?, gym_lon = ? WHERE user_id = ?').run(
    g?.id ?? null, g?.name ?? null, g ? nameKey(g.name) : null, g?.latitude ?? null, g?.longitude ?? null, userId,
  );
};

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
      kind TEXT NOT NULL CHECK (kind IN ('like', 'strong', 'fire', 'clap', 'beast', 'banana')),
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
    -- Member search hides members with open reports about them as a person (memberNotHiddenSql).
    CREATE INDEX IF NOT EXISTS community_reports_target_user ON community_reports(target_user_id, target_type);
    -- Shared plans (#666): member-made programmes others browse and copy into their own programmes.
    CREATE TABLE IF NOT EXISTS community_programs (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      data TEXT NOT NULL,
      visibility TEXT NOT NULL CHECK (visibility IN ('private', 'members', 'public')),
      copies INTEGER NOT NULL DEFAULT 0,
      hidden_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS community_programs_updated ON community_programs(updated_at);
    CREATE INDEX IF NOT EXISTS community_programs_user ON community_programs(user_id);
    CREATE TABLE IF NOT EXISTS community_program_copies (
      program_id TEXT NOT NULL REFERENCES community_programs(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (program_id, user_id)
    );
  `);
  // Show my gym (#152): members opt in to being found by the gym they train at.
  const cols = db.prepare('PRAGMA table_info(community_profiles)').all() as { name: string }[];
  if (!cols.some((c) => c.name === 'show_gym')) db.exec('ALTER TABLE community_profiles ADD COLUMN show_gym INTEGER NOT NULL DEFAULT 0');
  // Game level (#242): the app reports it so members see each other's rank title (Regular+) and Legend badge.
  if (!cols.some((c) => c.name === 'level')) db.exec('ALTER TABLE community_profiles ADD COLUMN level INTEGER');
  // Pronouns (#415): shown next to the nickname only when the member turns it on in the app.
  if (!cols.some((c) => c.name === 'pronouns')) db.exec('ALTER TABLE community_profiles ADD COLUMN pronouns TEXT');
  // Gym columns (#715): the training-profile gym, kept in step by refreshMemberGym; filled once for existing members.
  if (!cols.some((c) => c.name === 'gym_id')) {
    db.exec(`
      ALTER TABLE community_profiles ADD COLUMN gym_id TEXT;
      ALTER TABLE community_profiles ADD COLUMN gym_name TEXT;
      ALTER TABLE community_profiles ADD COLUMN gym_key TEXT;
      ALTER TABLE community_profiles ADD COLUMN gym_lat REAL;
      ALTER TABLE community_profiles ADD COLUMN gym_lon REAL;
    `);
    for (const { user_id } of db.prepare('SELECT user_id FROM community_profiles').all() as { user_id: string }[]) refreshMemberGym(db, user_id);
  }
  // Beast and Banana cheers (#566): the kind CHECK is rebuilt once on databases made before them.
  const reactions = db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'community_reactions'").get() as { sql: string } | undefined;
  if (reactions && !reactions.sql.includes("'banana'")) {
    db.exec(`
      BEGIN;
      CREATE TABLE community_reactions_new (
        post_id TEXT NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK (kind IN ('like', 'strong', 'fire', 'clap', 'beast', 'banana')),
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, user_id, kind)
      );
      INSERT INTO community_reactions_new SELECT post_id, user_id, kind, created_at FROM community_reactions;
      DROP TABLE community_reactions;
      ALTER TABLE community_reactions_new RENAME TO community_reactions;
      COMMIT;
    `);
  }
  db.exec(`
    CREATE INDEX IF NOT EXISTS community_profiles_gym ON community_profiles(gym_id);
    CREATE INDEX IF NOT EXISTS community_profiles_gym_key ON community_profiles(show_gym, gym_key);
    -- Per-member look-ups (#715): leaving the community, the export, and report clean-up (after the rebuild above, which drops indexes).
    CREATE INDEX IF NOT EXISTS community_reactions_user ON community_reactions(user_id);
    CREATE INDEX IF NOT EXISTS community_reports_reporter ON community_reports(reporter_id);
  `);
};

/** Live group sessions (#626): gym buddies, live sets, cheers and the weekly challenge room. */
export const ensureLiveSchema = (db: DB): void => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS community_buddies (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      buddy_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, buddy_id)
    );
    CREATE INDEX IF NOT EXISTS community_buddies_buddy ON community_buddies(buddy_id);
    CREATE TABLE IF NOT EXISTS community_live (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      exercise TEXT NOT NULL,
      detail TEXT,
      state TEXT NOT NULL CHECK (state IN ('set', 'rest', 'done')),
      challenge_week TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS community_live_cheers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      to_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      from_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('fire', 'banana', 'beast')),
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS community_live_cheers_to ON community_live_cheers(to_id, id);
    CREATE TABLE IF NOT EXISTS community_challenge_scores (
      week TEXT NOT NULL,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rounds INTEGER NOT NULL,
      reps INTEGER NOT NULL,
      score INTEGER NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (week, user_id)
    );
    CREATE INDEX IF NOT EXISTS community_challenge_board ON community_challenge_scores(week, score DESC);
  `);
  db.exec(`
    CREATE INDEX IF NOT EXISTS community_live_cheers_from ON community_live_cheers(from_id);
    CREATE INDEX IF NOT EXISTS community_challenge_scores_user ON community_challenge_scores(user_id);
  `);
  // #675: a member can keep their live set from one buddy (their row toward that buddy).
  const cols = db.prepare('PRAGMA table_info(community_buddies)').all() as { name: string }[];
  if (!cols.some((c) => c.name === 'share_live')) db.exec('ALTER TABLE community_buddies ADD COLUMN share_live INTEGER NOT NULL DEFAULT 1');
};
