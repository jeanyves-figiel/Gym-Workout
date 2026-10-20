import { dirname, join } from 'node:path';
import type { OffsiteConfig } from './offsite.ts';

export interface Config {
  env: 'development' | 'test' | 'production';
  host: string;
  port: number;
  dbPath: string;
  jwtSecret: string;
  codePepper: string;
  appleBundleIds: string[];
  accessTtlSec: number;
  refreshTtlDays: number;
  mail: {
    transport: 'console' | 'smtp' | 'ses';
    smtpUrl?: string;
    /** SES HTTPS API (regions without an SMTP endpoint, e.g. eu-central-2). */
    ses?: { region: string; accessKeyId: string; secretAccessKey: string };
    from: string;
  };
  appName: string;
  authRateLimitPerMin: number;
  /** Sign in with Apple server-to-server (code exchange + token revocation). Unset → skipped. */
  /**
   * `twoStep` (APPLE_TWO_STEP=on): Sign in with Apple also asks for the authenticator code when the member turned 2-step
   * on. Off by default until the app handles `mfa_required` on the Apple path (it does on password sign-in).
   */
  appleSignIn: { teamId?: string; keyId?: string; privateKey?: string; clientId?: string; twoStep: boolean };
  /** Reject passwords found in Have I Been Pwned (k-anonymity range API). */
  hibpCheck: boolean;
  /** Interval of the expired codes / refresh tokens purge job (0 disables the timer). */
  purgeIntervalMin: number;
  /** Receives community reports (App Store 1.2). Unset → reports are stored only. */
  moderationEmail?: string;
  /** APNs token auth (.p8 with Apple Push Notifications service enabled). Unset → remote push skipped (#69). */
  apns: { teamId?: string; keyId?: string; privateKey?: string };
  /** Workout chat (#381): ANTHROPIC_API_KEY unset → the chat answers 503 and the app hides it. COACH_CHAT_DAILY_LIMIT messages per member per day. */
  coachChat: { apiKey?: string; workspaceId?: string; dailyLimit: number };
  /** AI_DAILY_LIMIT: paid model calls (coach chat + gym scan + food scan) across all members per UTC day. */
  aiDailyLimit: number;
  /**
   * Studio coach voices (#395): Amazon Polly neural. POLLY_ACCESS_KEY_ID/POLLY_SECRET_ACCESS_KEY, else the SES keys (the
   * IAM user needs polly:SynthesizeSpeech); POLLY_REGION (default eu-central-1). Recordings cached in `cacheDir`.
   */
  coachVoices: { polly?: { region: string; accessKeyId: string; secretAccessKey: string }; cacheDir?: string };
  /** In-app subscriptions (#126). SUBSCRIPTIONS=off|preview|enforced (default off: nothing shown or locked). */
  subscriptions: {
    mode: 'off' | 'preview' | 'enforced';
    productIds: string[];
    /** SUBSCRIPTION_TESTS=on (staging only): fake purchases without Apple and a per-account mode, for testing Pro. */
    tests: boolean;
    /** Sandbox / TestFlight purchases unlock Pro (#432). SUBSCRIPTION_SANDBOX=on|off; default off on production without tests. */
    sandbox: boolean;
  };
  /** Who runs the app, shown on /privacy, /terms and /support (#125). Unset → placeholder text the owner must fill. */
  /** Member problem reports (#467): also opened as GitHub issues when a token (Issues: write) is set. */
  reports: { githubToken?: string; githubRepo: string };
  legal: { operator?: string; address?: string; email?: string; law: string; venue?: string };
  /** Passkeys (#257): relying party = the API host the app has in its Associated Domains (webcredentials:). */
  webauthn: { rpId: string; origins: string[] };
  /** Apple team id, for /.well-known/apple-app-site-association (passkeys). */
  appleTeamId?: string;
  /** Daily SQLite backups (#310) in `dir` (default `<db dir>/backups` in production; BACKUP_DIR=off disables). */
  backup: { dir?: string; keepDays: number };
  /** Encrypted off-site copy (#313): Fly Tigris bucket (secrets set by `flyctl storage create`) + BACKUP_KEY. Unset → off. */
  offsite?: OffsiteConfig;
}

/** Whole number ≥ 1, else `dflt`: a typo must not turn into NaN days and prune every backup (#432). */
export const positiveInt = (v: string | undefined, dflt: number): number => {
  const n = Number(v);
  return v !== undefined && v.trim() !== '' && Number.isInteger(n) && n >= 1 ? n : dflt;
};

const required = (name: string, env: NodeJS.ProcessEnv, prod: boolean, dev: string): string => {
  const v = env[name];
  if (v) return v;
  if (prod) throw new Error(`Missing required env ${name}`);
  return dev;
};

const subscriptionMode = (v?: string): Config['subscriptions']['mode'] => {
  const m = (v ?? 'off').toLowerCase();
  if (m !== 'off' && m !== 'preview' && m !== 'enforced') throw new Error('SUBSCRIPTIONS must be off, preview or enforced');
  return m;
};

const backupDir = (env: NodeJS.ProcessEnv, prod: boolean, dbPath: string): string | undefined => {
  const v = env.BACKUP_DIR;
  if (v && ['off', '0', 'false', 'no'].includes(v.toLowerCase())) return undefined;
  if (v) return v;
  return prod && dbPath !== ':memory:' ? join(dirname(dbPath), 'backups') : undefined;
};

const pollyCreds = (env: NodeJS.ProcessEnv) => {
  if (['off', '0', 'false', 'no'].includes((env.POLLY ?? '').toLowerCase())) return undefined;
  const accessKeyId = env.POLLY_ACCESS_KEY_ID || env.SES_ACCESS_KEY_ID;
  const secretAccessKey = env.POLLY_SECRET_ACCESS_KEY || env.SES_SECRET_ACCESS_KEY;
  return accessKeyId && secretAccessKey ? { region: env.POLLY_REGION ?? 'eu-central-1', accessKeyId, secretAccessKey } : undefined;
};

export const loadConfig = (env: NodeJS.ProcessEnv = process.env): Config => {
  const mode = (env.NODE_ENV ?? 'development') as Config['env'];
  const prod = mode === 'production';
  const sesCreds =
    env.SES_ACCESS_KEY_ID && env.SES_SECRET_ACCESS_KEY
      ? { region: env.SES_REGION ?? 'eu-central-2', accessKeyId: env.SES_ACCESS_KEY_ID, secretAccessKey: env.SES_SECRET_ACCESS_KEY }
      : undefined;
  const transport = (env.MAIL_TRANSPORT ?? (sesCreds ? 'ses' : prod ? 'smtp' : 'console')) as Config['mail']['transport'];
  if (transport === 'smtp' && !env.SMTP_URL) throw new Error('MAIL_TRANSPORT=smtp requires SMTP_URL');
  if (transport === 'ses' && !sesCreds) throw new Error('MAIL_TRANSPORT=ses requires SES_ACCESS_KEY_ID and SES_SECRET_ACCESS_KEY');
  const jwtSecret = required('JWT_SECRET', env, prod, 'dev-only-jwt-secret-change-me-0123456789');
  if (prod && jwtSecret.length < 32) throw new Error('JWT_SECRET must be ≥ 32 chars');
  return {
    env: mode,
    host: env.HOST ?? '0.0.0.0',
    port: Number(env.PORT ?? 8080),
    dbPath: env.DB_PATH ?? (prod ? '/data/app.db' : './data/dev.db'),
    jwtSecret,
    codePepper: required('CODE_PEPPER', env, prod, 'dev-only-code-pepper'),
    appleBundleIds: (env.APPLE_BUNDLE_IDS ?? 'Com.app.MonkeyWorkout,Com.app.MonkeyWorkout.dev')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    accessTtlSec: Number(env.ACCESS_TTL_SEC ?? 900),
    refreshTtlDays: Number(env.REFRESH_TTL_DAYS ?? 60),
    mail: { transport, smtpUrl: env.SMTP_URL, ses: sesCreds, from: env.MAIL_FROM ?? 'MonkeyWorkout <no-reply@localhost>' },
    appName: env.APP_NAME ?? 'MonkeyWorkout',
    authRateLimitPerMin: Number(env.AUTH_RATE_LIMIT_PER_MIN ?? 10),
    appleSignIn: {
      teamId: env.APPLE_TEAM_ID || undefined,
      keyId: env.APPLE_KEY_ID || undefined,
      // .p8 contents; literal "\n" sequences (single-line secrets) are turned back into newlines.
      privateKey: env.APPLE_PRIVATE_KEY ? env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n') : undefined,
      clientId: env.APPLE_CLIENT_ID || undefined,
      twoStep: env.APPLE_TWO_STEP === 'on',
    },
    // On by default, off in tests; HIBP_CHECK=0 disables, HIBP_CHECK=1 forces on.
    hibpCheck: env.HIBP_CHECK !== undefined ? !['0', 'false', 'off', 'no'].includes(env.HIBP_CHECK.toLowerCase()) : mode !== 'test',
    purgeIntervalMin: Number(env.PURGE_INTERVAL_MIN ?? 60),
    moderationEmail: env.MODERATION_EMAIL || undefined,
    apns: {
      teamId: env.APNS_TEAM_ID || env.APPLE_TEAM_ID || undefined,
      keyId: env.APNS_KEY_ID || undefined,
      privateKey: env.APNS_PRIVATE_KEY ? env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n') : undefined,
    },
    coachVoices: {
      polly: pollyCreds(env),
      cacheDir: env.COACH_VOICE_DIR || (prod && (env.DB_PATH ?? '/data/app.db') !== ':memory:' ? join(dirname(env.DB_PATH ?? '/data/app.db'), 'coach-voices') : undefined),
    },
    coachChat: {
      apiKey: env.ANTHROPIC_API_KEY || undefined,
      workspaceId: env.ANTHROPIC_WORKSPACE_ID || undefined,
      dailyLimit: Number(env.COACH_CHAT_DAILY_LIMIT ?? 20),
    },
    aiDailyLimit: Number(env.AI_DAILY_LIMIT ?? 500),
    subscriptions: {
      mode: subscriptionMode(env.SUBSCRIPTIONS),
      productIds: (env.SUBSCRIPTION_PRODUCT_IDS ?? 'monkeyworkout.pro.weekly,monkeyworkout.pro.monthly,monkeyworkout.pro.yearly,monkeyworkout.pro.lifetime')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
      tests: env.SUBSCRIPTION_TESTS === 'on',
      sandbox: env.SUBSCRIPTION_SANDBOX ? env.SUBSCRIPTION_SANDBOX === 'on' : !prod || env.SUBSCRIPTION_TESTS === 'on',
    },
    reports: {
      githubToken: env.GITHUB_REPORTS_TOKEN || undefined,
      githubRepo: env.GITHUB_REPORTS_REPO || 'jeanyves-figiel/Gym-Workout',
    },
    legal: {
      operator: env.LEGAL_OPERATOR || undefined,
      address: env.LEGAL_ADDRESS || undefined,
      email: env.LEGAL_EMAIL || env.MODERATION_EMAIL || undefined,
      law: env.LEGAL_LAW || 'Switzerland',
      venue: env.LEGAL_VENUE || undefined,
    },
    webauthn: {
      rpId: env.WEBAUTHN_RP_ID || 'localhost',
      origins: (env.WEBAUTHN_ORIGINS || `https://${env.WEBAUTHN_RP_ID || 'localhost'}${env.WEBAUTHN_RP_ID ? '' : ',http://localhost:7443'}`)
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    },
    appleTeamId: env.APPLE_TEAM_ID || undefined,
    backup: {
      dir: backupDir(env, prod, env.DB_PATH ?? (prod ? '/data/app.db' : './data/dev.db')),
      keepDays: positiveInt(env.BACKUP_KEEP_DAYS, 7),
    },
    offsite:
      env.AWS_ENDPOINT_URL_S3 && env.BUCKET_NAME && env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY && env.BACKUP_KEY
        ? {
            endpoint: env.AWS_ENDPOINT_URL_S3,
            bucket: env.BUCKET_NAME,
            region: env.AWS_REGION || 'auto',
            accessKeyId: env.AWS_ACCESS_KEY_ID,
            secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
            passphrase: env.BACKUP_KEY,
            keepDays: positiveInt(env.BACKUP_OFFSITE_DAYS, 30),
          }
        : undefined,
  };
};
