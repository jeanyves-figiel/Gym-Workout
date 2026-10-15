import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.ts';
import { decryptBackup, encryptBackup, OffsiteStore } from '../src/offsite.ts';

let root: string;
beforeEach(() => (root = mkdtempSync(join(tmpdir(), 'offsite-'))));
afterEach(() => rmSync(root, { recursive: true, force: true }));

/** In-memory S3: PUT/GET/DELETE objects, ListObjectsV2; records requests. */
const fakeS3 = () => {
  const objects = new Map<string, { body: Buffer; modified: string }>();
  const requests: { method: string; url: string; headers: Record<string, string> }[] = [];
  const fetchFn = async (url: URL, init: RequestInit) => {
    const method = init.method!;
    requests.push({ method, url: url.toString(), headers: init.headers as Record<string, string> });
    const key = decodeURIComponent(url.pathname.replace(/^\/bucket\/?/, ''));
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
  return { objects, requests, fetchFn };
};

const config = { endpoint: 'https://fly.storage.tigris.dev', bucket: 'bucket', region: 'auto', accessKeyId: 'AK', secretAccessKey: 'SK', passphrase: 'correct horse battery staple', keepDays: 30 };

describe('encrypted off-site copy (#313)', () => {
  it('encrypts so the bucket never sees plaintext, and only the passphrase opens it', () => {
    const plain = Buffer.from('SQLite format 3\0 secret member data '.repeat(50));
    const blob = encryptBackup(plain, 'pw');
    expect(blob.includes(Buffer.from('secret member data'))).toBe(false);
    expect(decryptBackup(blob, 'pw').equals(plain)).toBe(true);
    expect(() => decryptBackup(blob, 'wrong')).toThrow();
    const tampered = Buffer.from(blob);
    tampered[tampered.length - 1]! ^= 1;
    expect(() => decryptBackup(tampered, 'pw')).toThrow();
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
  });

  it('is off unless the bucket secrets and BACKUP_KEY are all set', () => {
    const env = { NODE_ENV: 'test', AWS_ENDPOINT_URL_S3: 'https://fly.storage.tigris.dev', BUCKET_NAME: 'b', AWS_ACCESS_KEY_ID: 'a', AWS_SECRET_ACCESS_KEY: 's' };
    expect(loadConfig(env).offsite).toBeUndefined();
    expect(loadConfig({ ...env, BACKUP_KEY: 'k' }).offsite).toMatchObject({ bucket: 'b', region: 'auto', keepDays: 30 });
  });
});
