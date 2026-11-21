import { createDecipheriv, randomBytes, scryptSync } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.ts';
import { decryptBackup, encryptBackup, encryptBackupFile, OffsiteStore } from '../src/offsite.ts';

let root: string;
beforeEach(() => (root = mkdtempSync(join(tmpdir(), 'offsite-'))));
afterEach(() => rmSync(root, { recursive: true, force: true }));

/** In-memory S3: PUT/GET/DELETE objects, ListObjectsV2, multipart uploads; records requests. */
const fakeS3 = (opts: { failPart?: number } = {}) => {
  const objects = new Map<string, { body: Buffer; modified: string }>();
  const uploads = new Map<string, Map<number, Buffer>>();
  const requests: { method: string; url: string; headers: Record<string, string> }[] = [];
  const fetchFn = async (url: URL, init: RequestInit) => {
    const method = init.method!;
    requests.push({ method, url: url.toString(), headers: init.headers as Record<string, string> });
    const key = decodeURIComponent(url.pathname.replace(/^\/bucket\/?/, ''));
    const uploadId = url.searchParams.get('uploadId');
    if (method === 'POST' && url.searchParams.has('uploads')) {
      const id = `up-${uploads.size + 1}`;
      uploads.set(id, new Map());
      return new Response(`<InitiateMultipartUploadResult><UploadId>${id}</UploadId></InitiateMultipartUploadResult>`);
    }
    if (method === 'PUT' && uploadId) {
      const n = Number(url.searchParams.get('partNumber'));
      if (n === opts.failPart) return new Response('<Code>InternalError</Code>', { status: 500 });
      uploads.get(uploadId)!.set(n, Buffer.from(init.body as Uint8Array));
      return new Response('', { headers: { etag: `"etag-${n}"` } });
    }
    if (method === 'POST' && uploadId) {
      const xml = Buffer.from(init.body as Uint8Array).toString();
      const nums = [...xml.matchAll(/<PartNumber>(\d+)<\/PartNumber><ETag>"etag-(\d+)"<\/ETag>/g)].map((m) => Number(m[1]));
      const parts = uploads.get(uploadId)!;
      objects.set(key, { body: Buffer.concat(nums.map((n) => parts.get(n)!)), modified: '2026-10-15T03:00:00Z' });
      uploads.delete(uploadId);
      return new Response('<CompleteMultipartUploadResult/>');
    }
    if (method === 'DELETE' && uploadId) {
      uploads.delete(uploadId);
      return new Response('', { status: 204 });
    }
    if (method === 'PUT') objects.set(key, { body: Buffer.from(init.body as Uint8Array), modified: '2026-10-15T03:00:00Z' });
    if (method === 'DELETE') objects.delete(key);
    if (method === 'GET' && url.searchParams.get('list-type') === '2') {
      const xml = [...objects].map(([k, o]) => `<Contents><Key>${k}</Key><LastModified>${o.modified}</LastModified><Size>${o.body.length}</Size></Contents>`).join('');
      return new Response(`<ListBucketResult>${xml}</ListBucketResult>`);
    }
    if (method === 'GET') {
      const o = objects.get(key);
      return o ? new Response(new Uint8Array(o.body)) : new Response('<Code>NoSuchKey</Code>', { status: 404 });
    }
    return new Response('');
  };
  return { objects, uploads, requests, fetchFn };
};

const config = { endpoint: 'https://fly.storage.tigris.dev', bucket: 'bucket', region: 'auto', accessKeyId: 'AK', secretAccessKey: 'SK', passphrase: 'correct horse battery staple', keepDays: 30, keepHours: 48 };

describe('encrypted off-site copy (#313)', () => {
  it('encrypts so the bucket never sees plaintext, and only the passphrase opens it', async () => {
    const plain = Buffer.from('SQLite format 3\0 secret member data '.repeat(50));
    const blob = await encryptBackup(plain, 'pw');
    expect(blob.includes(Buffer.from('secret member data'))).toBe(false);
    expect((await decryptBackup(blob, 'pw')).equals(plain)).toBe(true);
    await expect(decryptBackup(blob, 'wrong')).rejects.toThrow();
    const tampered = Buffer.from(blob);
    tampered[tampered.length - 1]! ^= 1;
    await expect(decryptBackup(tampered, 'pw')).rejects.toThrow();
  });

  it('keeps the MWB1 format: magic, scrypt salt, GCM iv and tag, then gzip ciphertext', async () => {
    const plain = Buffer.from('backup bytes');
    const blob = await encryptBackup(plain, 'pw');
    expect(blob.subarray(0, 4).toString()).toBe('MWB1');
    // decrypt by hand the way the pre-async code (and any external restore tool) does
    const key = scryptSync('pw', blob.subarray(4, 20), 32, { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
    const d = createDecipheriv('aes-256-gcm', key, blob.subarray(20, 32));
    d.setAuthTag(blob.subarray(32, 48));
    expect(gunzipSync(Buffer.concat([d.update(blob.subarray(48)), d.final()])).equals(plain)).toBe(true);
  });

  it('uploads signed, prunes copies older than 30 days, and downloads back', async () => {
    const s3 = fakeS3();
    let clock = new Date('2026-09-10T03:00:00Z');
    const store = new OffsiteStore(config, s3.fetchFn, () => clock);
    const file = join(root, 'app.db');
    writeFileSync(file, 'backup bytes');
    await store.upload(file, '2026-09-10');
    clock = new Date('2026-10-15T03:00:00Z');
    const r = await store.upload(file, '2026-10-15');
    expect(r.pruned).toBe(1);
    expect([...s3.objects.keys()]).toEqual(['backups/app-2026-10-15.db.enc']);
    const put = s3.requests.find((q) => q.method === 'PUT')!;
    expect(put.url).toBe('https://fly.storage.tigris.dev/bucket/backups/app-2026-09-10.db.enc');
    expect(put.headers.authorization).toMatch(/^AWS4-HMAC-SHA256 Credential=AK\/\d{8}\/auto\/s3\/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=[0-9a-f]{64}$/);
    expect((await store.list()).map((o) => o.day)).toEqual(['2026-10-15']);
    const dest = join(root, 'restored.db');
    await store.download('2026-10-15', dest);
    expect(readFileSync(dest, 'utf8')).toBe('backup bytes');
    // Never overwrites a file already there (#432).
    await expect(store.download('2026-10-15', dest)).rejects.toThrow(/EEXIST/);
  });

  it('is off unless the bucket secrets and BACKUP_KEY are all set', () => {
    const env = { NODE_ENV: 'test', AWS_ENDPOINT_URL_S3: 'https://fly.storage.tigris.dev', BUCKET_NAME: 'b', AWS_ACCESS_KEY_ID: 'a', AWS_SECRET_ACCESS_KEY: 's' };
    expect(loadConfig(env).offsite).toBeUndefined();
    expect(loadConfig({ ...env, BACKUP_KEY: 'k' }).offsite).toMatchObject({ bucket: 'b', region: 'auto', keepDays: 30 });
  });

  it('hourly copies (#923): own prefix, pruned after 48 hours, fetched by hour; daily copies untouched', async () => {
    const s3 = fakeS3();
    let clock = new Date('2026-10-28T09:10:00Z');
    const store = new OffsiteStore(config, s3.fetchFn, () => clock);
    const file = join(root, 'app.db');
    writeFileSync(file, 'hour bytes');
    await store.upload(file, '2026-10-28');
    await store.uploadHourly(file, '2026-10-28T09');
    clock = new Date('2026-10-30T10:10:00Z');
    const r = await store.uploadHourly(file, '2026-10-30T10');
    expect(r).toMatchObject({ key: 'hourly/app-2026-10-30T10.db.enc', pruned: 1 });
    expect((await store.listHourly()).map((o) => o.day)).toEqual(['2026-10-30T10']);
    expect((await store.list()).map((o) => o.day)).toEqual(['2026-10-28']);
    const dest = join(root, 'hour.db');
    await store.download('2026-10-30T10', dest);
    expect(readFileSync(dest, 'utf8')).toBe('hour bytes');
    expect(s3.objects.get('hourly/app-2026-10-30T10.db.enc')!.body.includes(Buffer.from('hour bytes'))).toBe(false);
  });

  it('hourly copies default to 48 hours, 0 turns them off', () => {
    const env = { AWS_ENDPOINT_URL_S3: 'https://e', BUCKET_NAME: 'b', AWS_ACCESS_KEY_ID: 'a', AWS_SECRET_ACCESS_KEY: 's', BACKUP_KEY: 'k' };
    expect(loadConfig(env).offsite?.keepHours).toBe(48);
    expect(loadConfig({ ...env, BACKUP_OFFSITE_HOURS: '0' }).offsite?.keepHours).toBe(0);
  });

  it('streams large backups up in parts (#923): same MWB1 object, restorable, temp file removed', async () => {
    const s3 = fakeS3();
    const store = new OffsiteStore(config, s3.fetchFn, () => new Date('2026-10-15T03:00:00Z'), 64 * 1024);
    const file = join(root, 'app.db');
    const plain = randomBytes(300 * 1024); // incompressible: about 5 parts
    writeFileSync(file, plain);
    const r = await store.upload(file, '2026-10-15');
    const parts = s3.requests.filter((q) => q.method === 'PUT' && q.url.includes('partNumber='));
    expect(parts.length).toBe(5);
    for (const p of parts) expect(p.headers.authorization).toMatch(/^AWS4-HMAC-SHA256 /);
    const blob = s3.objects.get('backups/app-2026-10-15.db.enc')!.body;
    expect(r.bytes).toBe(blob.length);
    expect((await decryptBackup(blob, config.passphrase)).equals(plain)).toBe(true);
    expect(readdirSync(root)).toEqual(['app.db']);
    const dest = join(root, 'restored.db');
    await store.download('2026-10-15', dest);
    expect(readFileSync(dest).equals(plain)).toBe(true);
  });

  it('aborts a failed multipart upload and leaves no temp file', async () => {
    const s3 = fakeS3({ failPart: 2 });
    const store = new OffsiteStore(config, s3.fetchFn, () => new Date('2026-10-15T03:00:00Z'), 64 * 1024);
    const file = join(root, 'app.db');
    writeFileSync(file, randomBytes(200 * 1024));
    await expect(store.upload(file, '2026-10-15')).rejects.toThrow(/HTTP 500/);
    expect(s3.requests.at(-1)).toMatchObject({ method: 'DELETE' });
    expect(s3.requests.at(-1)!.url).toContain('uploadId=up-1');
    expect(s3.uploads.size).toBe(0);
    expect(s3.objects.size).toBe(0);
    expect(readdirSync(root)).toEqual(['app.db']);
  });

  it('the streamed file matches encryptBackup, and a tampered download leaves no file', async () => {
    const file = join(root, 'app.db');
    writeFileSync(file, 'SQLite format 3\0 streamed '.repeat(1000));
    const enc = join(root, 'app.enc');
    const size = await encryptBackupFile(file, enc, 'pw');
    const blob = readFileSync(enc);
    expect(blob.length).toBe(size);
    expect(blob.subarray(0, 4).toString()).toBe('MWB1');
    expect((await decryptBackup(blob, 'pw')).equals(readFileSync(file))).toBe(true);

    const s3 = fakeS3();
    const tampered = Buffer.from(blob);
    tampered[tampered.length - 1]! ^= 1;
    s3.objects.set('backups/app-2026-10-15.db.enc', { body: tampered, modified: '2026-10-15T03:00:00Z' });
    const store = new OffsiteStore({ ...config, passphrase: 'pw' }, s3.fetchFn);
    const dest = join(root, 'restored.db');
    await expect(store.download('2026-10-15', dest)).rejects.toThrow();
    expect(existsSync(dest)).toBe(false);
  });
});
