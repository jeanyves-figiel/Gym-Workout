import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-23T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
  });
});
afterEach(() => app.close());

const headers = (t: string) => ({ authorization: `Bearer ${t}` });
const req = (method: 'GET' | 'POST' | 'PUT' | 'DELETE', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: headers(t), ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const body = res.json() as { tokens: { accessToken: string }; user: { id: string } };
  return { t: body.tokens.accessToken, id: body.user.id };
};

const member = async (email: string, nickname: string) => {
  const u = await signUp(email);
  expect((await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true })).statusCode).toBe(200);
  return u;
};

const plan = (name = 'Push Pull Legs', extra: object = {}) => ({
  name,
  about: 'Three days, big lifts first.',
  level: 'beginner',
  goal: 'strength',
  weeks: 8,
  sessionsPerWeek: 3,
  programme: { id: 'my-abc', name, tagline: 'Big lifts first', phases: [{ kind: 'base', weeks: 4 }], signatures: [] },
  ...extra,
});

type Program = { id: string; name: string; copies: number; copiedByMe: boolean; mine: boolean; author: { nickname: string }; programme: { tagline: string } };
const list = async (t: string, q = '') => (await req('GET', `/v1/community/programs${q}`, t)).json() as { programs: Program[] };

describe('shared plans (#666)', () => {
  it('needs a community profile', async () => {
    const u = await signUp('a@x.io');
    expect((await req('GET', '/v1/community/programs', u.t)).statusCode).toBe(403);
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, u.t, plan())).statusCode).toBe(403);
  });

  it('shares, lists to others, filters, updates and deletes', async () => {
    const a = await member('a@x.io', 'anna');
    const b = await member('b@x.io', 'ben');
    const id = randomUUID().toUpperCase();
    const put = await req('PUT', `/v1/community/programs/${id}`, a.t, plan());
    expect(put.statusCode).toBe(200);
    expect((put.json() as { program: Program }).program).toMatchObject({ id: id.toLowerCase(), name: 'Push Pull Legs', mine: true, copies: 0 });
    expect((await list(a.t)).programs).toEqual([]);
    expect((await list(a.t, '?mine=1')).programs).toHaveLength(1);
    const seen = (await list(b.t)).programs;
    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({ author: { nickname: 'anna' }, mine: false });
    expect(seen[0]!.programme.tagline).toBe('Big lifts first');
    expect((await list(b.t, '?q=legs')).programs).toHaveLength(1);
    expect((await list(b.t, '?level=advanced')).programs).toHaveLength(0);
    // Private: only the owner.
    await req('PUT', `/v1/community/programs/${id}`, a.t, plan('Push Pull Legs', { visibility: 'private' }));
    expect((await list(b.t)).programs).toEqual([]);
    expect((await req('GET', `/v1/community/programs/${id}`, b.t)).statusCode).toBe(404);
    // Someone else's id.
    expect((await req('PUT', `/v1/community/programs/${id}`, b.t, plan())).statusCode).toBe(409);
    expect((await req('DELETE', `/v1/community/programs/${id}`, a.t)).statusCode).toBe(204);
    expect((await list(a.t, '?mine=1')).programs).toEqual([]);
  });

  it('counts a copy once per member, not for the author', async () => {
    const a = await member('a@x.io', 'anna');
    const b = await member('b@x.io', 'ben');
    const id = randomUUID();
    await req('PUT', `/v1/community/programs/${id}`, a.t, plan());
    await req('POST', `/v1/community/programs/${id}/copy`, a.t);
    const c1 = (await req('POST', `/v1/community/programs/${id}/copy`, b.t)).json() as { program: Program };
    const c2 = (await req('POST', `/v1/community/programs/${id}/copy`, b.t)).json() as { program: Program };
    expect(c1.program).toMatchObject({ copies: 1, copiedByMe: true });
    expect(c2.program.copies).toBe(1);
  });

  it('refuses objectionable names and a missing programme', async () => {
    const a = await member('a@x.io', 'anna');
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, plan('shit day'))).statusCode).toBe(400);
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, plan('Fine', { programme: { name: 'Fine', tagline: 'shit day' } }))).statusCode).toBe(400);
    expect((await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, plan('Empty', { programme: undefined }))).statusCode).toBe(400);
  });

  it('hides blocked authors and goes when the member leaves', async () => {
    const a = await member('a@x.io', 'anna');
    const b = await member('b@x.io', 'ben');
    await req('PUT', `/v1/community/programs/${randomUUID()}`, a.t, plan());
    expect((await req('POST', '/v1/community/blocks', b.t, { userId: a.id })).statusCode).toBeLessThan(300);
    expect((await list(b.t)).programs).toEqual([]);
    expect((await req('DELETE', '/v1/community/me', a.t)).statusCode).toBe(204);
    expect((db.prepare('SELECT COUNT(*) AS n FROM community_programs').get() as { n: number }).n).toBe(0);
  });

  it('takes reports', async () => {
    const a = await member('a@x.io', 'anna');
    const b = await member('b@x.io', 'ben');
    const id = randomUUID();
    await req('PUT', `/v1/community/programs/${id}`, a.t, plan());
    const r = await req('POST', `/v1/community/programs/${id}/report`, b.t, { reason: 'spam' });
    expect(r.statusCode).toBe(202);
    expect((await req('POST', `/v1/community/programs/${id}/report`, a.t, { reason: 'spam' })).statusCode).toBe(400);
  });
});
