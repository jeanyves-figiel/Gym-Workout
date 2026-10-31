import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

/** Fuel with a partner (#1014): household invite/accept/leave, shared plan with revisions, ticks, copies, blocks, export. */

const PW = 'correct-horse-battery';

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;

beforeEach(() => {
  clock = new Date('2026-10-25T10:00:00Z');
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

const req = (method: 'GET' | 'POST' | 'PUT' | 'DELETE', url: string, t: string, payload?: object) =>
  app.inject({ method, url, headers: { authorization: `Bearer ${t}` }, ...(payload ? { payload } : {}) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const j = res.json() as { user: { id: string }; tokens: { accessToken: string } };
  return { t: j.tokens.accessToken, id: j.user.id };
};

const join = async (email: string, nickname: string) => {
  const u = await signUp(email);
  expect((await req('PUT', '/v1/community/me', u.t, { nickname, acceptGuidelines: true })).statusCode).toBe(200);
  return u;
};

const meal = (day: string) => ({ day, slot: 'dinner', kind: 'dinner', recipeId: 'lean-bolognese', servings: 2, pinned: false, leftover: false });
const state = (days: string[]) => ({ plan: days.map(meal), recipes: [], people: 2, lessWaste: true });

describe('household (#1014)', () => {
  it('invite → accept → shared plan, stale write, ticks, leave', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Sam');
    expect((await req('GET', '/v1/household', a.t)).json()).toEqual({ household: null, invites: { incoming: [], outgoing: [] } });
    // Nothing is shared before the partner says yes.
    const inv = await req('POST', '/v1/household/invites', a.t, { userId: b.id });
    expect(inv.statusCode).toBe(200);
    expect(inv.json().household.members).toHaveLength(1);
    expect(inv.json().invites.outgoing[0].to.nickname).toBe('Sam');
    expect((await req('PUT', '/v1/household/state', b.t, { rev: 0, state: state(['2026-11-01']) })).statusCode).toBe(404);
    const incoming = (await req('GET', '/v1/household', b.t)).json().invites.incoming;
    expect(incoming[0]).toMatchObject({ from: { nickname: 'Djy' }, members: 1 });

    const acc = await req('POST', `/v1/household/invites/${incoming[0].id}/accept`, b.t, {});
    expect(acc.statusCode).toBe(200);
    expect(acc.json().household.members.map((m: { nickname: string }) => m.nickname)).toEqual(['Sam', 'Djy']);

    const w = await req('PUT', '/v1/household/state', a.t, { rev: 0, state: state(['2026-11-01']) });
    expect(w.json().rev).toBe(1);
    const stale = await req('PUT', '/v1/household/state', b.t, { rev: 0, state: state(['2026-11-02']) });
    expect(stale.statusCode).toBe(409);
    expect(stale.json().error).toBe('stale');
    expect(stale.json().household.state.plan[0].day).toBe('2026-11-01');
    expect((await req('PUT', '/v1/household/state', b.t, { rev: 1, state: state(['2026-11-02']) })).json().rev).toBe(2);
    const seen = (await req('GET', '/v1/household', a.t)).json().household;
    expect(seen).toMatchObject({ rev: 2, updatedBy: { nickname: 'Sam' } });

    const t = await req('PUT', '/v1/household/bought', b.t, { itemIds: ['rice', 'chicken-breast'], bought: true });
    expect(t.json().bought.map((x: { itemId: string; by: { nickname: string } }) => [x.itemId, x.by.nickname])).toEqual([
      ['chicken-breast', 'Sam'],
      ['rice', 'Sam'],
    ]);
    await req('PUT', '/v1/household/bought', a.t, { itemIds: ['rice'], bought: false });
    expect((await req('GET', '/v1/household', a.t)).json().household.bought).toHaveLength(1);

    expect((await req('DELETE', '/v1/household/me', b.t)).statusCode).toBe(204);
    expect((await req('GET', '/v1/household', b.t)).json().household).toBeNull();
    expect((await req('GET', '/v1/household', a.t)).json().household.members).toHaveLength(1);
    await req('DELETE', '/v1/household/me', a.t);
    expect((db.prepare('SELECT COUNT(*) AS n FROM households').get() as { n: number }).n).toBe(0);
  });

  it('decline, cancel, own, unknown, already in another household, too big', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Sam');
    const c = await join('c@example.com', 'Kim');
    const outsider = await signUp('d@example.com');
    expect((await req('POST', '/v1/household/invites', a.t, { userId: a.id })).statusCode).toBe(400);
    expect((await req('POST', '/v1/household/invites', a.t, { userId: outsider.id })).statusCode).toBe(404);
    expect((await req('POST', '/v1/household/invites', outsider.t, { userId: a.id })).statusCode).toBe(403);

    await req('POST', '/v1/household/invites', a.t, { userId: b.id });
    const id = (await req('GET', '/v1/household', b.t)).json().invites.incoming[0].id;
    expect((await req('DELETE', `/v1/household/invites/${id}`, c.t)).statusCode).toBe(404);
    expect((await req('DELETE', `/v1/household/invites/${id}`, b.t)).statusCode).toBe(204);

    // b shares with c; a's invite needs leaveCurrent.
    await req('POST', '/v1/household/invites', b.t, { userId: c.id });
    await req('POST', `/v1/household/invites/${(await req('GET', '/v1/household', c.t)).json().invites.incoming[0].id}/accept`, c.t, {});
    await req('POST', '/v1/household/invites', a.t, { userId: b.id });
    const id2 = (await req('GET', '/v1/household', b.t)).json().invites.incoming[0].id;
    expect((await req('POST', `/v1/household/invites/${id2}/accept`, b.t, {})).json().error).toBe('in_household');
    const moved = await req('POST', `/v1/household/invites/${id2}/accept`, b.t, { leaveCurrent: true });
    expect(moved.json().household.members.map((m: { nickname: string }) => m.nickname)).toEqual(['Sam', 'Djy']);
    expect((await req('GET', '/v1/household', c.t)).json().household.members).toHaveLength(1);

    const huge = { plan: [meal('2026-11-01')], recipes: [], blob: 'x'.repeat(300_000) };
    expect((await req('PUT', '/v1/household/state', a.t, { rev: 0, state: huge })).statusCode).toBe(413);
  });

  it('a block ends the shared plan and invites', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Sam');
    await req('POST', '/v1/household/invites', a.t, { userId: b.id });
    await req('POST', `/v1/household/invites/${(await req('GET', '/v1/household', b.t)).json().invites.incoming[0].id}/accept`, b.t, {});
    expect((await req('POST', '/v1/community/blocks', b.t, { userId: a.id })).statusCode).toBe(204);
    expect((await req('GET', '/v1/household', b.t)).json().household).toBeNull();
    expect((await req('POST', '/v1/household/invites', a.t, { userId: b.id })).statusCode).toBe(404);
  });
});

describe('send a copy (#1014)', () => {
  const groceries = [{ id: 'rice', name: 'Rice', grams: 1000 }];
  it('only to friends who follow back; list, dismiss, export, expiry', async () => {
    const a = await join('a@example.com', 'Djy');
    const b = await join('b@example.com', 'Sam');
    const send = () => req('POST', '/v1/fuel-shares', a.t, { toUserId: b.id, kind: 'both', payload: { plan: state(['2026-11-01']), groceries } });
    expect((await send()).statusCode).toBe(404);
    await req('PUT', `/v1/community/follows/${b.id}`, a.t);
    expect((await send()).statusCode).toBe(404);
    await req('PUT', `/v1/community/follows/${a.id}`, b.t);
    expect((await req('POST', '/v1/fuel-shares', a.t, { toUserId: b.id, kind: 'plan', payload: { groceries } })).statusCode).toBe(400);
    const s = await send();
    expect(s.statusCode).toBe(201);

    const list = (await req('GET', '/v1/fuel-shares', b.t)).json().shares;
    expect(list[0]).toMatchObject({ from: { nickname: 'Djy' }, kind: 'both', payload: { groceries } });
    expect((await req('GET', '/v1/fuel-shares', a.t)).json().shares).toEqual([]);
    const exp = (await req('GET', '/v1/me/export', a.t)).json();
    expect(exp.fuelSharing.copiesSent).toHaveLength(1);

    expect((await req('DELETE', `/v1/fuel-shares/${s.json().id}`, b.t)).statusCode).toBe(204);
    await send();
    db.prepare("UPDATE fuel_shares SET created_at = '2026-09-01T00:00:00.000Z'").run();
    expect((await req('GET', '/v1/fuel-shares', b.t)).json().shares).toEqual([]);
  });
});
