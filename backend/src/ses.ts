import { createHash, createHmac } from 'node:crypto';
import type { Mail, Mailer } from './mailer.ts';

/**
 * Amazon SES over its HTTPS API (v1 `SendRawEmail`, SigV4-signed).
 * Needed because some regions (eu-central-2 / Zurich) have no SES SMTP endpoint.
 * IAM: `ses:SendRawEmail` only.
 */

export interface SesCredentials {
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
}

const sha256 = (s: string | Buffer) => createHash('sha256').update(s).digest('hex');
const hmac = (k: string | Buffer, s: string) => createHmac('sha256', k).update(s).digest();

/** RFC 3986 encoding as SigV4 expects. */
const uriEncode = (s: string) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

export interface SignInput {
  method: string;
  url: URL;
  headers: Record<string, string>;
  body: string;
  service: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** e.g. 20150830T123600Z */
  amzDate: string;
}

/** AWS Signature Version 4. Returns the Authorization header value. Headers must include host and x-amz-date. */
export const signV4 = (i: SignInput): string => {
  const date = i.amzDate.slice(0, 8);
  const names = Object.keys(i.headers)
    .map((h) => h.toLowerCase())
    .sort();
  const lower = Object.fromEntries(Object.entries(i.headers).map(([k, v]) => [k.toLowerCase(), v.trim().replace(/\s+/g, ' ')]));
  const query = [...i.url.searchParams.entries()]
    .map(([k, v]) => [uriEncode(k), uriEncode(v)] as const)
    .sort(([a, av], [b, bv]) => (a === b ? (av < bv ? -1 : 1) : a < b ? -1 : 1))
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  const canonical = [
    i.method,
    i.url.pathname || '/',
    query,
    names.map((n) => `${n}:${lower[n]}\n`).join(''),
    names.join(';'),
    sha256(i.body),
  ].join('\n');
  const scope = `${date}/${i.region}/${i.service}/aws4_request`;
  const toSign = ['AWS4-HMAC-SHA256', i.amzDate, scope, sha256(canonical)].join('\n');
  let key: Buffer = hmac(`AWS4${i.secretAccessKey}`, date);
  for (const part of [i.region, i.service, 'aws4_request']) key = hmac(key, part);
  const signature = createHmac('sha256', key).update(toSign).digest('hex');
  return `AWS4-HMAC-SHA256 Credential=${i.accessKeyId}/${scope}, SignedHeaders=${names.join(';')}, Signature=${signature}`;
};

const encodeHeader = (s: string) => (/^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${Buffer.from(s, 'utf8').toString('base64')}?=`);

/** Minimal text/plain MIME message. */
export const buildMime = (from: string, mail: Mail, date = new Date()): string => {
  const body = Buffer.from(mail.text, 'utf8')
    .toString('base64')
    .replace(/.{76}/g, '$&\r\n');
  return [
    `From: ${from}`,
    `To: ${mail.to}`,
    `Subject: ${encodeHeader(mail.subject)}`,
    `Date: ${date.toUTCString()}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    body,
  ].join('\r\n');
};

export class SesMailer implements Mailer {
  private readonly creds: SesCredentials;
  private readonly from: string;
  private readonly fetchFn: typeof fetch;
  private readonly now: () => Date;

  constructor(
    creds: SesCredentials,
    from: string,
    fetchFn: typeof fetch = (input, init) => globalThis.fetch(input, init),
    now: () => Date = () => new Date(),
  ) {
    this.creds = creds;
    this.from = from;
    this.fetchFn = fetchFn;
    this.now = now;
  }

  async send(mail: Mail): Promise<void> {
    const url = new URL(`https://email.${this.creds.region}.amazonaws.com/`);
    const body = new URLSearchParams({
      Action: 'SendRawEmail',
      Version: '2010-12-01',
      'RawMessage.Data': Buffer.from(buildMime(this.from, mail, this.now()), 'utf8').toString('base64'),
    }).toString();
    const amzDate = this.now().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const headers: Record<string, string> = {
      'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      host: url.host,
      'x-amz-date': amzDate,
    };
    const authorization = signV4({ method: 'POST', url, headers, body, service: 'ses', region: this.creds.region, accessKeyId: this.creds.accessKeyId, secretAccessKey: this.creds.secretAccessKey, amzDate });
    const res = await this.fetchFn(url, {
      method: 'POST',
      headers: { 'content-type': headers['content-type']!, 'x-amz-date': amzDate, authorization },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      const xml = await res.text().catch(() => '');
      const code = xml.match(/<Code>([^<]+)<\/Code>/)?.[1] ?? 'unknown';
      const message = xml.match(/<Message>([^<]+)<\/Message>/)?.[1] ?? '';
      throw new Error(`SES SendRawEmail failed: HTTP ${res.status} ${code} ${message}`.trim());
    }
  }
}
