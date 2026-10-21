/**
 * Writes the generated API and data references under `docs/reference/` (#586):
 * `routes.json` (every registered route), `schema.sql` (the SQLite schema after all migrations) and `openapi.json`
 * (from `docs/api/endpoints.md`).
 * `test/docs.test.ts` fails when they or `docs/api/endpoints.md` drift from the code.
 * Run: `npm run docs`.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { collectRoutes, dumpSchema, openApi, parseEndpoints } from '../src/docsReference.ts';

const out = (name: string) => fileURLToPath(new URL(`../../docs/reference/${name}`, import.meta.url));
writeFileSync(out('routes.json'), `${JSON.stringify(await collectRoutes(), null, 2)}\n`);
writeFileSync(out('schema.sql'), dumpSchema());
const md = readFileSync(fileURLToPath(new URL('../../docs/api/endpoints.md', import.meta.url)), 'utf8');
writeFileSync(out('openapi.json'), `${JSON.stringify(openApi(parseEndpoints(md)), null, 2)}\n`);
console.log('docs/reference updated');
