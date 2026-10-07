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
  mail: { transport: 'console' | 'smtp'; smtpUrl?: string; from: string };
  appName: string;
  authRateLimitPerMin: number;
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
  const transport = (env.MAIL_TRANSPORT ?? (prod ? 'smtp' : 'console')) as 'console' | 'smtp';
  if (transport === 'smtp' && !env.SMTP_URL) throw new Error('MAIL_TRANSPORT=smtp requires SMTP_URL');
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
    mail: { transport, smtpUrl: env.SMTP_URL, from: env.MAIL_FROM ?? 'MonkeyWorkout <no-reply@localhost>' },
    appName: env.APP_NAME ?? 'MonkeyWorkout',
    authRateLimitPerMin: Number(env.AUTH_RATE_LIMIT_PER_MIN ?? 10),
  };
};
