import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { chatSchema } from '../src/coach/chat.ts';

/** Claude API structured outputs: at most 16 parameters with union types (anyOf / type arrays) per schema (#1060). */
const LIMIT = 16;

const unions = (node: unknown): number => {
  if (Array.isArray(node)) return node.reduce((n, v) => n + unions(v), 0);
  if (!node || typeof node !== 'object') return 0;
  const o = node as Record<string, unknown>;
  const self = Array.isArray(o.anyOf) || Array.isArray(o.type) ? 1 : 0;
  return self + Object.values(o).reduce<number>((n, v) => n + unions(v), 0);
};

const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(join(dir, e.name)) : e.name.endsWith('.ts') ? [join(dir, e.name)] : []));

describe('AI schema union limit (#1060)', () => {
  it('Coach chat schema stays within the API limit', () => {
    expect(unions(chatSchema)).toBeLessThanOrEqual(LIMIT);
  });

  it('no source file holds more union params than one schema may (upper bound for every AI schema)', () => {
    for (const f of files(join(import.meta.dirname, '../src'))) {
      const n = (readFileSync(f, 'utf8').match(/anyOf:|type: \[/g) ?? []).length;
      expect(n, f).toBeLessThanOrEqual(LIMIT);
    }
  });
});
