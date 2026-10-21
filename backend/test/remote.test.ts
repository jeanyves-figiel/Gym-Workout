import { generateKeyPairSync, verify } from 'node:crypto';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { loadRemoteContent } from '../src/remote.ts';

let app: FastifyInstance;
const make = (env: Record<string, string> = {}) =>
  (app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', ...env }),
    db: openDb(':memory:'),
    mailer: new ConsoleMailer(() => {}),
    apple: async () => {
      throw new Error('unused');
    },
  }));
afterEach(() => app?.close());

const folder = (config: unknown, packs: Record<string, unknown> = {}) => {
  const dir = mkdtempSync(join(tmpdir(), 'remote-'));
  writeFileSync(join(dir, 'config.json'), JSON.stringify(config));
  mkdirSync(join(dir, 'packs'));
  for (const [n, body] of Object.entries(packs)) writeFileSync(join(dir, 'packs', `${n}.json`), JSON.stringify(body));
  return dir;
};

describe('over-the-air content (#583)', () => {
  it('the content folder in the repository is valid', () => {
    expect(() => loadRemoteContent(loadConfig({ NODE_ENV: 'test' }).remote.dir)).not.toThrow();
  });

  it('serves config publicly with an etag and 304 on repeat', async () => {
    const dir = folder({ recommendedBuild: 60, update: { title: 'Build 60', body: 'Fixes' }, flags: { foodScan: { on: false, message: 'Paused' } }, values: { 'coach.max': 3 } });
    const a = make({ CONTENT_DIR: dir });
    const res = await a.inject({ method: 'GET', url: '/v1/app-config' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body).toMatchObject({ minimumBuild: 0, recommendedBuild: 60, flags: { foodScan: { on: false } }, values: { 'coach.max': 3 }, packs: [] });
    expect(res.headers.etag).toBe(`"${body.version}"`);
    const again = await a.inject({ method: 'GET', url: '/v1/app-config', headers: { 'if-none-match': res.headers.etag as string } });
    expect(again.statusCode).toBe(304);
  });

  it('lists packs by hash and serves them only under that hash', async () => {
    const recipes = [{ id: 'oats', name: 'Oats' }];
    const a = make({ CONTENT_DIR: folder({ packs: { recipes: { minBuild: 60 } } }, { recipes }) });
    const [p] = (await a.inject({ method: 'GET', url: '/v1/app-config' })).json().packs;
    expect(p).toMatchObject({ name: 'recipes', minBuild: 60, maxBuild: null });
    const got = await a.inject({ method: 'GET', url: p.url });
    expect(got.statusCode).toBe(200);
    expect(got.json()).toEqual(recipes);
    expect(got.headers['cache-control']).toContain('immutable');
    expect((await a.inject({ method: 'GET', url: '/v1/packs/recipes/0000' })).statusCode).toBe(404);
  });

  it('signs the exact body with CONTENT_SIGNING_KEY', async () => {
    const { privateKey, publicKey } = generateKeyPairSync('ed25519');
    const key = privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64');
    const res = await make({ CONTENT_DIR: folder({}), CONTENT_SIGNING_KEY: key }).inject({ method: 'GET', url: '/v1/app-config' });
    const sig = Buffer.from(res.headers['x-content-signature'] as string, 'base64');
    expect(verify(null, Buffer.from(res.body), publicKey, sig)).toBe(true);
  });

  it.each([
    [{ minimumBuild: 60 }, {}, 'update'],
    [{ packs: { foods: {} } }, {}, 'missing'],
    [{ packs: { recipes: {} } }, { recipes: [{ name: 'no id' }] }, 'Pack recipes'],
    [{ flags: { x: { on: 'yes' } } }, {}, ''],
    [{ packs: { scripts: {} } }, {}, ''],
  ])('rejects broken content %#', (config, packs, msg) => {
    expect(() => loadRemoteContent(folder(config, packs))).toThrow(msg);
  });

  it('broken content serves an empty config instead of failing the boot', async () => {
    const res = await make({ CONTENT_DIR: folder({ minimumBuild: 99 }) }).inject({ method: 'GET', url: '/v1/app-config' });
    expect(res.json()).toMatchObject({ minimumBuild: 0, flags: {}, packs: [] });
  });
});
