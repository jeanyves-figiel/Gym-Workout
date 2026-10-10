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
  appleSignIn: { teamId?: string; keyId?: string; privateKey?: string; clientId?: string };
  /** Reject passwords found in Have I Been Pwned (k-anonymity range API). */
  hibpCheck: boolean;
  /** Interval of the expired codes / refresh tokens purge job (0 disables the timer). */
  purgeIntervalMin: number;
  /** Receives community reports (App Store 1.2). Unset → reports are stored only. */
  moderationEmail?: string;
}

const required = (name: string, env: NodeJS.ProcessEnv, prod: boolean, dev: string): string => {
  const v = env[name];
  if (v) return v;
  if (prod) throw new Error(`Missing required env ${name}`);
  return dev;
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
    },
    // On by default, off in tests; HIBP_CHECK=0 disables, HIBP_CHECK=1 forces on.
    hibpCheck: env.HIBP_CHECK !== undefined ? !['0', 'false', 'off', 'no'].includes(env.HIBP_CHECK.toLowerCase()) : mode !== 'test',
    purgeIntervalMin: Number(env.PURGE_INTERVAL_MIN ?? 60),
    moderationEmail: env.MODERATION_EMAIL || undefined,
  };
};
