import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { collectRoutes, dumpSchema, openApi, parseEndpoints } from '../src/docsReference.ts';

/** Docs stay in step with the code (#586): `npm run docs` regenerates `docs/reference/`. */
const doc = (path: string) => readFileSync(new URL(`../../docs/${path}`, import.meta.url), 'utf8');
const key = (r: { method: string; path: string }) => `${r.method} ${r.path}`;

describe('documentation (#586)', () => {
  it('docs/api/endpoints.md lists every route, and only routes that exist', async () => {
    const routes = (await collectRoutes()).map(key);
    const documented = parseEndpoints(doc('api/endpoints.md')).map(key);
    expect(documented.filter((d) => !routes.includes(d))).toEqual([]);
    expect(routes.filter((r) => !documented.includes(r))).toEqual([]);
    expect(new Set(documented).size).toBe(documented.length);
  });

  it('every documented route has a known auth kind', () => {
    const kinds = new Set(['–', 'Bearer', 'Bearer + re-auth', 'X-Watch-Key', 'X-Garmin-Token', 'Apple JWS']);
    expect(parseEndpoints(doc('api/endpoints.md')).filter((d) => !kinds.has(d.auth))).toEqual([]);
  });

  it('generated references are current (run `npm run docs`)', async () => {
    expect(JSON.parse(doc('reference/routes.json'))).toEqual(await collectRoutes());
    expect(doc('reference/schema.sql')).toBe(dumpSchema());
    expect(JSON.parse(doc('reference/openapi.json'))).toEqual(openApi(parseEndpoints(doc('api/endpoints.md'))));
  });
});
