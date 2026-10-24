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
  clock = new Date('2026-10-10T10:00:00Z');
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

const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
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

const workout = (visibility?: string, name = 'Pull strength') => ({
  id: randomUUID(),
  name,
  createdAt: '2026-10-10T09:00:00Z',
  items: [{ id: randomUUID(), exerciseId: 'pull-up', sets: 4, reps: 6, restSec: 120 }],
  ...(visibility ? { visibility } : {}),
});

type Shared = { id: string; name: string; author: { nickname: string }; saves: number; items: unknown[] };
const shared = async (t: string, q = '') => (await req('GET', `/v1/library/shared${q}`, t)).json() as { workouts: Shared[] };

describe('workout library', () => {
  it('pages through workouts shared at the same moment with beforeId (#432)', async () => {
    const a = await member('a@example.com', 'alice');
    const b = await member('b@example.com', 'bob');
    await req('POST', '/v1/me/custom-workouts', a.t, { workouts: Array.from({ length: 5 }, () => workout('members')) });
    const seen: string[] = [];
    let url = '/v1/library/shared?limit=2';
    for (let i = 0; i < 5 && url; i++) {
      const page = (await req('GET', url, b.t)).json() as { workouts: Shared[]; nextBefore: string | null; nextBeforeId: string | null };
      seen.push(...page.workouts.map((w) => w.id));
      url = page.nextBefore ? `/v1/library/shared?limit=2&before=${encodeURIComponent(page.nextBefore)}&beforeId=${page.nextBeforeId}` : '';
    }
    expect(new Set(seen).size).toBe(5);
    expect(seen).toHaveLength(5);
  });

  it('leaving the community makes shared workouts private again (#432)', async () => {
    const a = await member('a@example.com', 'alice');
    const b = await member('b@example.com', 'bob');
    const w = workout('public');
    await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [w] });
    expect((await shared(b.t)).workouts).toHaveLength(1);
    expect((await req('DELETE', '/v1/community/me', a.t)).statusCode).toBe(204);
    expect((await shared(b.t)).workouts).toHaveLength(0);
    expect((await req('GET', `/v1/library/shared/${w.id}`, b.t)).statusCode).toBe(404);
    const own = (await req('GET', '/v1/me/custom-workouts', a.t)).json() as { workouts: { id: string; visibility: string }[] };
    expect(own.workouts.map((x) => x.visibility)).toEqual(['private']);
  });

  it('shares members/public workouts, hides private ones and own ones', async () => {
    const a = await member('a@example.com', 'alice');
    const b = await member('b@example.com', 'bob');
    const priv = workout();
    const mem = workout('members', 'Engine builder');
    const pub = workout('public');
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [priv, mem, pub] })).statusCode).toBe(200);

    const seen = await shared(b.t);
    expect(seen.workouts.map((w) => w.id).sort()).toEqual([mem.id, pub.id].sort());
    expect(seen.workouts[0]!.author.nickname).toBe('alice');
    expect(seen.workouts[0]!.items).toHaveLength(1);
    expect((await shared(a.t)).workouts).toHaveLength(0);
    expect((await shared(b.t, '?q=engine')).workouts.map((w) => w.id)).toEqual([mem.id]);

    // Own list carries server visibility.
    const own = (await req('GET', '/v1/me/custom-workouts', a.t)).json() as { workouts: { id: string; visibility: string }[] };
    expect(own.workouts.find((w) => w.id === mem.id)!.visibility).toBe('members');

    // Back to private: gone from the library.
    advance(1000);
    await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [{ ...mem, visibility: 'private' }] });
    expect((await shared(b.t)).workouts.map((w) => w.id)).toEqual([pub.id]);
    expect((await req('GET', `/v1/library/shared/${mem.id}`, b.t)).statusCode).toBe(404);
    expect((await req('GET', `/v1/library/shared/${pub.id.toLowerCase()}`, b.t)).statusCode).toBe(200);
  });

  it('returns the session flow blocks of a shared workout (#198)', async () => {
    const a = await member('a@example.com', 'alice');
    const b = await member('b@example.com', 'bob');
    const flow = [{ kind: 'warmup', title: 'Warm-up', targetMin: 6, items: [] }];
    const withFlow = { ...workout('members', 'With flow'), flow };
    const plain = workout('members', 'Plain');
    expect((await req('POST', '/v1/me/custom-workouts', a.t, { workouts: [withFlow, plain] })).statusCode).toBe(200);
    const seen = (await shared(b.t)).workouts as (Shared & { flow?: unknown })[];
    expect(seen.find((w) => w.id === withFlow.id)!.flow).toEqual(flow);
    expect(seen.find((w) => w.id === plain.id)!.flow).toBeUndefined();
  });

  it('requires a community profile to share or browse, and filters names', async () => {
    const u = await signUp('c@example.com');
    expect((await req('POST', '/v1/me/custom-workouts', u.t, { workouts: [workout()] })).statusCode).toBe(200);
    const r = await req('POST', '/v1/me/custom-workouts', u.t, { workouts: [workout('members')] });
    expect(r.statusCode).toBe(403);
    expect(r.json().error).toBe('community_profile_required');
    expect((await req('GET', '/v1/library/shared', u.t)).statusCode).toBe(403);

    const m = await member('d@example.com', 'dora');
    const bad = await req('POST', '/v1/me/custom-workouts', m.t, { workouts: [workout('members', 'fuck this')] });
    expect(bad.statusCode).toBe(400);
  });

  it('counts saves, honours blocks and auto-hides after reports', async () => {
    const owner = await member('o@example.com', 'owner');
    const w = workout('members');
    await req('POST', '/v1/me/custom-workouts', owner.t, { workouts: [w] });
    const viewers = [await member('v1@example.com', 'viewer1'), await member('v2@example.com', 'viewer2'), await member('v3@example.com', 'viewer3')];

    expect(((await req('POST', `/v1/library/shared/${w.id}/save`, viewers[0]!.t)).json() as { workout: Shared }).workout.saves).toBe(1);
    // saving again (another tap, a retry) doesn't count twice; another member does
    expect(((await req('POST', `/v1/library/shared/${w.id}/save`, viewers[0]!.t)).json() as { workout: Shared }).workout.saves).toBe(1);
    expect(((await req('POST', `/v1/library/shared/${w.id}/save`, viewers[1]!.t)).json() as { workout: Shared }).workout.saves).toBe(2);

    expect((await req('POST', '/v1/community/blocks', viewers[0]!.t, { userId: owner.id })).statusCode).toBeLessThan(300);
    expect((await shared(viewers[0]!.t)).workouts).toHaveLength(0);
    expect((await shared(viewers[1]!.t)).workouts).toHaveLength(1);

    expect((await req('POST', `/v1/library/shared/${w.id}/report`, owner.t, { reason: 'spam' })).statusCode).toBe(404);
    db.prepare("UPDATE users SET created_at = '2026-01-01T00:00:00.000Z'").run(); // reporters' accounts ≥ 7 days old (#432)
    for (const v of viewers.slice(1)) {
      const r = await req('POST', `/v1/library/shared/${w.id}/report`, v.t, { reason: 'spam' });
      expect(r.statusCode).toBe(202);
      expect(r.json().hidden).toBe(false);
    }
    // Third distinct reporter (a new member) hides it.
    const v4 = await member('v4@example.com', 'viewer4');
    db.prepare("UPDATE users SET created_at = '2026-01-01T00:00:00.000Z'").run();
    expect((await req('POST', `/v1/library/shared/${w.id}/report`, v4.t, { reason: 'hate' })).json().hidden).toBe(true);
    expect((await shared(viewers[1]!.t)).workouts).toHaveLength(0);
    // Owner still sees it, flagged hidden.
    const own = (await req('GET', '/v1/me/custom-workouts', owner.t)).json() as { workouts: { hidden: boolean }[] };
    expect(own.workouts[0]!.hidden).toBe(true);
  });
});
