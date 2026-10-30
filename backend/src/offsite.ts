import { createCipheriv, createDecipheriv, createHash, randomBytes, scrypt as scryptCb, type ScryptOptions } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { gunzip as gunzipCb, gzip as gzipCb } from 'node:zlib';
import { signV4 } from './ses.ts';

/**
 * Encrypted off-site copy of the daily backup (#313) in an S3-compatible bucket (Fly Tigris).
 * The backup is gzipped and encrypted here (AES-256-GCM, key from BACKUP_KEY via scrypt) before upload,
 * so the storage provider only ever holds ciphertext. Objects older than `keepDays` are deleted.
 */

export interface OffsiteConfig {
  endpoint: string;
  bucket: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** Passphrase; also kept by the owner outside Fly (GitHub secret BACKUP_KEY) so copies stay readable. */
  passphrase: string;
  keepDays: number;
  /** Hourly copies (#923): how many hours to keep; 0 = no hourly copies. */
  keepHours: number;
}

type Fetch = (input: URL, init: RequestInit) => Promise<Response>;

const MAGIC = Buffer.from('MWB1');
const PREFIX = 'backups/';
const HOURLY = 'hourly/';

const SCRYPT = { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };
const scrypt = promisify(scryptCb) as (pw: string, salt: Buffer, len: number, opts: ScryptOptions) => Promise<Buffer>;
const gzip = promisify(gzipCb);
const gunzip = promisify(gunzipCb);

/** Key derivation and (de)compression run off the event loop (libuv pool), so the API keeps serving meanwhile. */
export const encryptBackup = async (plain: Buffer, passphrase: string): Promise<Buffer> => {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const key = await scrypt(passphrase, salt, 32, SCRYPT);
  const c = createCipheriv('aes-256-gcm', key, iv);
  const body = [c.update(await gzip(plain)), c.final()];
  return Buffer.concat([MAGIC, salt, iv, c.getAuthTag(), ...body]);
};

export const decryptBackup = async (blob: Buffer, passphrase: string): Promise<Buffer> => {
  if (!blob.subarray(0, 4).equals(MAGIC)) throw new Error('not an encrypted MonkeyWorkout backup');
  const salt = blob.subarray(4, 20);
  const iv = blob.subarray(20, 32);
  const tag = blob.subarray(32, 48);
  const key = await scrypt(passphrase, salt, 32, SCRYPT);
  const d = createDecipheriv('aes-256-gcm', key, iv);
  d.setAuthTag(tag);
  return gunzip(Buffer.concat([d.update(blob.subarray(48)), d.final()]));
};

/** A day (`YYYY-MM-DD`, daily copy) or an hour (`YYYY-MM-DDTHH`, hourly copy, #923). */
export const objectKey = (id: string) => (id.length > 10 ? `${HOURLY}app-${id}.db.enc` : `${PREFIX}app-${id}.db.enc`);

export class OffsiteStore {
  private readonly c: OffsiteConfig;
  private readonly fetchFn: Fetch;
  private readonly now: () => Date;

  constructor(c: OffsiteConfig, fetchFn: Fetch = (input, init) => globalThis.fetch(input, init), now: () => Date = () => new Date()) {
    this.c = c;
    this.fetchFn = fetchFn;
    this.now = now;
  }

  private async request(method: string, key: string, query: Record<string, string> = {}, body: Buffer = Buffer.alloc(0)) {
    const url = new URL(`${this.c.endpoint.replace(/\/$/, '')}/${this.c.bucket}/${key.split('/').map(encodeURIComponent).join('/')}`);
    for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
    const amzDate = this.now().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const hash = createHash('sha256').update(body).digest('hex');
    const headers: Record<string, string> = { host: url.host, 'x-amz-content-sha256': hash, 'x-amz-date': amzDate };
    const authorization = signV4({ method, url, headers, body, service: 's3', region: this.c.region, accessKeyId: this.c.accessKeyId, secretAccessKey: this.c.secretAccessKey, amzDate });
    const res = await this.fetchFn(url, {
      method,
      headers: { 'x-amz-content-sha256': hash, 'x-amz-date': amzDate, authorization },
      // A view over the same bytes, not a copy of a backup-sized buffer.
      body: method === 'PUT' ? new Uint8Array(body.buffer as ArrayBuffer, body.byteOffset, body.byteLength) : undefined,
      signal: AbortSignal.timeout(120_000),
    });
    if (!res.ok && !(method === 'DELETE' && res.status === 404)) {
      const xml = await res.text().catch(() => '');
      throw new Error(`offsite ${method} ${key}: HTTP ${res.status} ${xml.match(/<Code>([^<]+)<\/Code>/)?.[1] ?? ''}`.trim());
    }
    return res;
  }

  async list(prefix = PREFIX): Promise<{ key: string; day: string; bytes: number; modified: string }[]> {
    const res = await this.request('GET', '', { 'list-type': '2', prefix });
    const xml = await res.text();
    return [...xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)]
      .map((m) => ({
        key: m[1]!.match(/<Key>([^<]+)<\/Key>/)?.[1] ?? '',
        bytes: Number(m[1]!.match(/<Size>(\d+)<\/Size>/)?.[1] ?? 0),
        modified: m[1]!.match(/<LastModified>([^<]+)<\/LastModified>/)?.[1] ?? '',
      }))
      .map((o) => ({ ...o, day: /app-(\d{4}-\d{2}-\d{2}(?:T\d{2})?)\.db\.enc$/.exec(o.key)?.[1] ?? '' }))
      .filter((o) => o.day && o.key.startsWith(prefix))
      .sort((a, b) => b.day.localeCompare(a.day));
  }

  /** Hourly copies (#923), newest first; `day` is `YYYY-MM-DDTHH`. */
  listHourly() {
    return this.list(HOURLY);
  }

  /** Encrypts and uploads an hourly copy, then deletes hourly copies older than `keepHours`. */
  async uploadHourly(file: string, hour: string): Promise<{ key: string; bytes: number; pruned: number }> {
    const blob = await encryptBackup(await readFile(file), this.c.passphrase);
    const key = objectKey(hour);
    await this.request('PUT', key, {}, blob);
    const cutoff = new Date(this.now().getTime() - this.c.keepHours * 3_600_000).toISOString().slice(0, 13);
    let pruned = 0;
    for (const o of await this.listHourly())
      if (o.day < cutoff) {
        await this.request('DELETE', o.key);
        pruned++;
      }
    return { key, bytes: blob.length, pruned };
  }

  /** Encrypts and uploads a backup file, then deletes copies older than `keepDays`. */
  async upload(file: string, day: string): Promise<{ key: string; bytes: number; pruned: number }> {
    const blob = await encryptBackup(await readFile(file), this.c.passphrase);
    const key = objectKey(day);
    await this.request('PUT', key, {}, blob);
    const cutoff = new Date(this.now().getTime() - this.c.keepDays * 86_400_000).toISOString().slice(0, 10);
    let pruned = 0;
    for (const o of await this.list())
      if (o.day < cutoff) {
        await this.request('DELETE', o.key);
        pruned++;
      }
    return { key, bytes: blob.length, pruned };
  }

  /** Downloads and decrypts one day's (or hour's) copy to `dest`; refuses to overwrite an existing file. */
  async download(id: string, dest: string): Promise<void> {
    const res = await this.request('GET', objectKey(id));
    await writeFile(dest, await decryptBackup(Buffer.from(await res.arrayBuffer()), this.c.passphrase), { mode: 0o600, flag: 'wx' });
  }
}
