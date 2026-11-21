import { createCipheriv, createDecipheriv, createHash, type DecipherGCM, randomBytes, scrypt as scryptCb, type ScryptOptions } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { open, rm } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import type { ReadableStream as WebReadableStream } from 'node:stream/web';
import { promisify } from 'node:util';
import { createGunzip, createGzip, gunzip as gunzipCb, gzip as gzipCb } from 'node:zlib';
import { signV4 } from './ses.ts';

/**
 * Encrypted off-site copy of the daily backup (#313) in an S3-compatible bucket (Fly Tigris).
 * The backup is gzipped and encrypted here (AES-256-GCM, key from BACKUP_KEY via scrypt) before upload,
 * so the storage provider only ever holds ciphertext. Objects older than `keepDays` are deleted.
 * Upload and download stream (#923): file → gzip → cipher → temp file → multipart parts, and back, so memory stays
 * at about one part however large the database grows. The object format (MWB1) is unchanged.
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

/** Multipart part size (S3 minimum is 5 MiB except the last part); smaller objects go up in one PUT. */
export const PART_BYTES = 16 * 1024 * 1024;
const HEADER = 48;

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

/** Streams `src` into an MWB1 file at `dest` (same bytes as `encryptBackup`); returns its size. */
export const encryptBackupFile = async (src: string, dest: string, passphrase: string): Promise<number> => {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const key = await scrypt(passphrase, salt, 32, SCRYPT);
  const c = createCipheriv('aes-256-gcm', key, iv);
  // The GCM tag sits in the header but is known only at the end: write a placeholder, then patch it in place.
  await pipeline(
    createReadStream(src),
    createGzip(),
    c,
    async function* (body) {
      yield Buffer.concat([MAGIC, salt, iv, Buffer.alloc(16)]);
      yield* body;
    },
    createWriteStream(dest, { flags: 'wx', mode: 0o600 }),
  );
  const fh = await open(dest, 'r+');
  try {
    await fh.write(c.getAuthTag(), 0, 16, 32);
    return (await fh.stat()).size;
  } finally {
    await fh.close();
  }
};

/** Streams an MWB1 object into a new file at `dest` (never overwrites); a partial or unauthenticated file is removed. */
export const decryptBackupStream = async (source: Readable, dest: string, passphrase: string): Promise<void> => {
  const fh = await open(dest, 'wx', 0o600);
  try {
    await pipeline(
      source,
      async function* (chunks: AsyncIterable<Buffer>) {
        let head = Buffer.alloc(0);
        let d: DecipherGCM | undefined;
        for await (const chunk of chunks) {
          if (d) {
            yield d.update(chunk);
            continue;
          }
          head = Buffer.concat([head, chunk]);
          if (head.length < HEADER) continue;
          if (!head.subarray(0, 4).equals(MAGIC)) throw new Error('not an encrypted MonkeyWorkout backup');
          d = createDecipheriv('aes-256-gcm', await scrypt(passphrase, head.subarray(4, 20), 32, SCRYPT), head.subarray(20, 32));
          d.setAuthTag(head.subarray(32, HEADER));
          yield d.update(head.subarray(HEADER));
        }
        if (!d) throw new Error('not an encrypted MonkeyWorkout backup');
        yield d.final();
      },
      createGunzip(),
      fh.createWriteStream(),
    );
  } catch (e) {
    await fh.close().catch(() => {});
    await rm(dest, { force: true });
    throw e;
  }
};

/** A day (`YYYY-MM-DD`, daily copy) or an hour (`YYYY-MM-DDTHH`, hourly copy, #923). */
export const objectKey = (id: string) => (id.length > 10 ? `${HOURLY}app-${id}.db.enc` : `${PREFIX}app-${id}.db.enc`);

export class OffsiteStore {
  private readonly c: OffsiteConfig;
  private readonly fetchFn: Fetch;
  private readonly now: () => Date;
  private readonly partBytes: number;

  constructor(
    c: OffsiteConfig,
    fetchFn: Fetch = (input, init) => globalThis.fetch(input, init),
    now: () => Date = () => new Date(),
    partBytes = PART_BYTES,
  ) {
    this.c = c;
    this.fetchFn = fetchFn;
    this.now = now;
    this.partBytes = partBytes;
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
      body: method === 'PUT' || body.length ? new Uint8Array(body.buffer as ArrayBuffer, body.byteOffset, body.byteLength) : undefined,
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
    const key = objectKey(hour);
    const bytes = await this.put(file, key);
    const cutoff = new Date(this.now().getTime() - this.c.keepHours * 3_600_000).toISOString().slice(0, 13);
    let pruned = 0;
    for (const o of await this.listHourly())
      if (o.day < cutoff) {
        await this.request('DELETE', o.key);
        pruned++;
      }
    return { key, bytes, pruned };
  }

  /** Encrypts and uploads a backup file, then deletes copies older than `keepDays`. */
  async upload(file: string, day: string): Promise<{ key: string; bytes: number; pruned: number }> {
    const key = objectKey(day);
    const bytes = await this.put(file, key);
    const cutoff = new Date(this.now().getTime() - this.c.keepDays * 86_400_000).toISOString().slice(0, 10);
    let pruned = 0;
    for (const o of await this.list())
      if (o.day < cutoff) {
        await this.request('DELETE', o.key);
        pruned++;
      }
    return { key, bytes, pruned };
  }

  /** Encrypts `file` to a temp file beside it, then uploads that in parts (one PUT when small). Returns the object size. */
  private async put(file: string, key: string): Promise<number> {
    const tmp = `${file}.enc.tmp`;
    await rm(tmp, { force: true });
    try {
      const size = await encryptBackupFile(file, tmp, this.c.passphrase);
      const fh = await open(tmp, 'r');
      try {
        const part = async (i: number) => {
          const buf = Buffer.alloc(Math.min(this.partBytes, size - i * this.partBytes));
          await fh.read(buf, 0, buf.length, i * this.partBytes);
          return buf;
        };
        if (size <= this.partBytes) {
          await this.request('PUT', key, {}, await part(0));
          return size;
        }
        const init = await (await this.request('POST', key, { uploads: '' })).text();
        const uploadId = init.match(/<UploadId>([^<]+)<\/UploadId>/)?.[1];
        if (!uploadId) throw new Error(`offsite multipart ${key}: no UploadId`);
        try {
          const etags: string[] = [];
          for (let i = 0; i * this.partBytes < size; i++) {
            const res = await this.request('PUT', key, { partNumber: String(i + 1), uploadId }, await part(i));
            const etag = res.headers.get('etag');
            if (!etag) throw new Error(`offsite multipart ${key}: part ${i + 1} has no ETag`);
            etags.push(etag);
          }
          const xml = `<CompleteMultipartUpload>${etags.map((e, i) => `<Part><PartNumber>${i + 1}</PartNumber><ETag>${e.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</ETag></Part>`).join('')}</CompleteMultipartUpload>`;
          const done = await (await this.request('POST', key, { uploadId }, Buffer.from(xml))).text();
          // S3 can answer 200 with an <Error> body when completion fails.
          if (/<Error>/.test(done)) throw new Error(`offsite multipart ${key}: ${done.match(/<Code>([^<]+)<\/Code>/)?.[1] ?? 'complete failed'}`);
        } catch (e) {
          await this.request('DELETE', key, { uploadId }).catch(() => {});
          throw e;
        }
        return size;
      } finally {
        await fh.close();
      }
    } finally {
      await rm(tmp, { force: true });
    }
  }

  /** Downloads and decrypts one day's (or hour's) copy to `dest`; refuses to overwrite an existing file. */
  async download(id: string, dest: string): Promise<void> {
    const res = await this.request('GET', objectKey(id));
    if (!res.body) throw new Error(`offsite GET ${objectKey(id)}: empty body`);
    await decryptBackupStream(Readable.fromWeb(res.body as WebReadableStream<Uint8Array>), dest, this.c.passphrase);
  }
}
