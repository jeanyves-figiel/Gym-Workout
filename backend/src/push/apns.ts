import { connect, type ClientHttp2Session } from 'node:http2';
import { importPKCS8, SignJWT } from 'jose';

export type ApnsEnv = 'sandbox' | 'production';

export interface ApnsMessage {
  token: string;
  env: ApnsEnv;
  topic: string;
  payload: object;
  /** `alert` (default) or `background`. */
  pushType?: 'alert' | 'background';
  collapseId?: string;
}

export interface ApnsResult {
  status: number;
  /** Apple's `reason` on failure (e.g. BadDeviceToken, Unregistered). */
  reason?: string;
}

/** Sends one notification. Injectable so tests and unconfigured servers never touch the network. */
export type ApnsSender = (m: ApnsMessage) => Promise<ApnsResult>;

export interface ApnsKey {
  teamId: string;
  keyId: string;
  privateKey: string;
}

const HOSTS: Record<ApnsEnv, string> = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};
const TIMEOUT_MS = 10_000;

/**
 * APNs HTTP/2 provider API with token (.p8) auth. One HTTP/2 connection per environment, reopened on error.
 * The provider JWT is reused for 50 min (Apple rejects tokens older than 1 h and refreshes more often than every 20 min).
 */
export const createApnsSender = (
  key: ApnsKey,
  now: () => Date = () => new Date(),
  /** Test hook: per-environment origin (e.g. a local h2c server). */
  hosts: Record<ApnsEnv, string> = HOSTS,
): ApnsSender => {
  const sessions = new Map<ApnsEnv, ClientHttp2Session>();
  let signing: Promise<CryptoKey> | undefined;
  let jwt: { value: string; iat: number } | undefined;

  const token = async () => {
    const t = Math.floor(now().getTime() / 1000);
    if (jwt && t - jwt.iat < 50 * 60) return jwt.value;
    signing ??= importPKCS8(key.privateKey, 'ES256');
    const value = await new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: key.keyId }).setIssuer(key.teamId).setIssuedAt(t).sign(await signing);
    jwt = { value, iat: t };
    return value;
  };

  const session = (env: ApnsEnv) => {
    const s = sessions.get(env);
    if (s && !s.closed && !s.destroyed) return s;
    const fresh = connect(hosts[env]);
    fresh.on('error', () => sessions.delete(env));
    fresh.on('close', () => sessions.delete(env));
    fresh.unref();
    sessions.set(env, fresh);
    return fresh;
  };

  return async (m) => {
    const bearer = await token();
    return new Promise<ApnsResult>((resolve, reject) => {
      const req = session(m.env).request({
        ':method': 'POST',
        ':path': `/3/device/${m.token}`,
        authorization: `bearer ${bearer}`,
        'apns-topic': m.topic,
        'apns-push-type': m.pushType ?? 'alert',
        'apns-priority': m.pushType === 'background' ? '5' : '10',
        ...(m.collapseId ? { 'apns-collapse-id': m.collapseId } : {}),
        'content-type': 'application/json',
      });
      let status = 0;
      let body = '';
      req.setTimeout(TIMEOUT_MS, () => req.close());
      req.on('response', (h) => (status = Number(h[':status'] ?? 0)));
      req.setEncoding('utf8');
      req.on('data', (c: string) => (body += c));
      req.on('end', () => {
        let reason: string | undefined;
        try {
          reason = body ? (JSON.parse(body) as { reason?: string }).reason : undefined;
        } catch {
          /* non-JSON body */
        }
        resolve({ status, reason });
      });
      req.on('error', reject);
      req.end(JSON.stringify(m.payload));
    });
  };
};
