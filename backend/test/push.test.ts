import type { FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { type DB, openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import type { ApnsMessage, ApnsResult } from '../src/push/apns.ts';
import { inQuietHours, NotificationPrefs } from '../src/push/prefs.ts';

const PW = 'correct-horse-battery';
const TOKEN_A = 'a'.repeat(64);
const TOKEN_B = 'b'.repeat(64);

let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let db: DB;
let sent: ApnsMessage[];
let reply: (m: ApnsMessage) => ApnsResult;

beforeEach(() => {
  clock = new Date('2026-10-07T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  db = openDb(':memory:');
  sent = [];
  reply = () => ({ status: 200 });
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000' }),
    db,
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
    apns: async (m) => {
      sent.push(m);
      return reply(m);
    },
  });
});
afterEach(() => app.close());

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const put = (url: string, payload: object, token: string) => app.inject({ method: 'PUT', url, payload, headers: auth(token) });
const post = (url: string, token: string) => app.inject({ method: 'POST', url, payload: {}, headers: auth(token) });
const get = (url: string, token: string) => app.inject({ method: 'GET', url, headers: auth(token) });

const signUp = async (email: string) => {
  await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } });
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  const body = res.json() as { tokens: { accessToken: string }; user: { id: string } };
  return { token: body.tokens.accessToken, id: body.user.id };
};

const device = (token: string, tz = 'Europe/Zurich') => ({ token, env: 'production', topic: 'Com.app.MonkeyWorkout', tz });

describe('push devices and prefs', () => {
  it('registers devices, validates topic and token, sends test push', async () => {
    const u = await signUp('push@example.com');
    expect((await put('/v1/me/push-device', device(TOKEN_A), u.token)).json()).toEqual({ ok: true, pushConfigured: true });
    expect((await put('/v1/me/push-device', { ...device(TOKEN_B), topic: 'com.evil.app' }, u.token)).statusCode).toBe(400);
    expect((await put('/v1/me/push-device', { ...device('nothex'), topic: 'Com.app.MonkeyWorkout' }, u.token)).statusCode).toBe(400);
    const r = (await post('/v1/me/push-test', u.token)).json();
    expect(r).toMatchObject({ devices: 1, sent: 1 });
    expect(sent[0]).toMatchObject({ token: TOKEN_A, env: 'production', topic: 'Com.app.MonkeyWorkout' });
    expect((await app.inject({ method: 'DELETE', url: `/v1/me/push-device/${TOKEN_A}`, headers: auth(u.token) })).statusCode).toBe(204);
    expect((await post('/v1/me/push-test', u.token)).json()).toMatchObject({ devices: 0, sent: 0 });
  });

  it('moves a token to the account that registered it last', async () => {
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    await put('/v1/me/push-device', device(TOKEN_A), a.token);
    await put('/v1/me/push-device', device(TOKEN_A), b.token);
    expect((await post('/v1/me/push-test', a.token)).json()).toMatchObject({ devices: 0 });
    expect((await post('/v1/me/push-test', b.token)).json()).toMatchObject({ devices: 1 });
  });

  it('defaults, saves and validates prefs', async () => {
    const u = await signUp('prefs@example.com');
    const d = (await get('/v1/me/notification-prefs', u.token)).json();
    expect(d.prefs).toMatchObject({ sessionReminders: true, missedCheckIn: true, followAchievements: true, quietStart: 1320, quietEnd: 420 });
    const saved = (await put('/v1/me/notification-prefs', { prefs: { ...d.prefs, followAchievements: false, extra: 1 } }, u.token)).json();
    expect(saved.prefs.followAchievements).toBe(false);
    expect(saved.prefs.extra).toBeUndefined();
    expect((await put('/v1/me/notification-prefs', { prefs: { quietStart: 2000 } }, u.token)).statusCode).toBe(400);
    expect((await get('/v1/me/notification-prefs', u.token)).json().prefs.followAchievements).toBe(false);
  });

  it('notifies followers, honours the toggle, quiet hours and drops dead tokens', async () => {
    const actor = await signUp('actor@example.com');
    const fan = await signUp('fan@example.com');
    const muted = await signUp('muted@example.com');
    app.push.setFollowersProvider((id) => (id === actor.id ? [fan.id, muted.id, actor.id] : []));
    await put('/v1/me/push-device', device(TOKEN_A), fan.token);
    await put('/v1/me/push-device', device(TOKEN_B), muted.token);
    const prefs = (await get('/v1/me/notification-prefs', muted.token)).json().prefs;
    await put('/v1/me/notification-prefs', { prefs: { ...prefs, followAchievements: false } }, muted.token);

    // 10:00 UTC = 12:00 Zurich: normal alert with sound.
    expect(await app.push.notifyFollowers(actor.id, 'Sam', { id: 'pr-1', type: 'pr', text: 'New PR: Bench press 100 kg × 3' })).toBe(1);
    expect(sent).toHaveLength(1);
    const p = sent[0]!.payload as { aps: Record<string, unknown>; kind: string; actorId: string };
    expect(p.aps.alert).toEqual({ title: 'Sam 🏆', body: 'New PR: Bench press 100 kg × 3' });
    expect(p.aps.sound).toBe('default');
    expect(p).toMatchObject({ kind: 'follow_achievement', actorId: actor.id });

    // 21:30 UTC = 23:30 Zurich: inside default quiet hours → passive, no sound.
    clock = new Date('2026-10-07T21:30:00Z');
    await app.push.notifyFollowers(actor.id, 'Sam', { id: 'pr-2', type: 'pr', text: 'x' });
    const q = sent[1]!.payload as { aps: Record<string, unknown> };
    expect(q.aps['interruption-level']).toBe('passive');
    expect(q.aps.sound).toBeUndefined();

    // Apple says the token is gone → removed.
    reply = () => ({ status: 410, reason: 'Unregistered' });
    await app.push.notifyFollowers(actor.id, 'Sam', { id: 'pr-3', type: 'pr', text: 'x' });
    expect(db.prepare('SELECT COUNT(*) AS n FROM push_devices WHERE user_id = ?').get(fan.id)).toEqual({ n: 0 });
  });

  it('announces each achievement once to followers', async () => {
    const actor = await signUp('ann@example.com');
    const fan = await signUp('fan2@example.com');
    await app.inject({ method: 'PATCH', url: '/v1/me', payload: { name: 'Ann' }, headers: auth(actor.token) });
    app.push.setFollowersProvider((id) => (id === actor.id ? [fan.id] : []));
    await put('/v1/me/push-device', device(TOKEN_A), fan.token);
    const body = { achievements: [{ id: 'w10', type: 'badge', text: 'Unlocked Committed: 10 sessions' }] };
    const first = await app.inject({ method: 'POST', url: '/v1/me/achievements', payload: body, headers: auth(actor.token) });
    expect(first.json()).toEqual({ announced: ['w10'] });
    expect((sent[0]!.payload as { aps: { alert: { title: string } } }).aps.alert.title).toBe('Ann 🏆');
    const again = await app.inject({ method: 'POST', url: '/v1/me/achievements', payload: body, headers: auth(actor.token) });
    expect(again.json()).toEqual({ announced: [] });
    expect(sent).toHaveLength(1);
  });

  it('deletes devices and prefs with the account', async () => {
    const u = await signUp('gone@example.com');
    await put('/v1/me/push-device', device(TOKEN_A), u.token);
    await put('/v1/me/notification-prefs', { prefs: {} }, u.token);
    const res = await app.inject({ method: 'DELETE', url: '/v1/me', payload: { password: PW, confirm: 'DELETE' }, headers: auth(u.token) });
    expect(res.statusCode).toBe(204);
    expect(db.prepare('SELECT COUNT(*) AS n FROM push_devices').get()).toEqual({ n: 0 });
    expect(db.prepare('SELECT COUNT(*) AS n FROM notification_prefs').get()).toEqual({ n: 0 });
  });
});

describe('quiet hours', () => {
  const p = NotificationPrefs.parse({});
  it('wraps midnight and respects the zone', () => {
    expect(inQuietHours(p, new Date('2026-10-07T21:30:00Z'), 'Europe/Zurich')).toBe(true); // 23:30
    expect(inQuietHours(p, new Date('2026-10-07T04:30:00Z'), 'Europe/Zurich')).toBe(true); // 06:30
    expect(inQuietHours(p, new Date('2026-10-07T05:00:00Z'), 'Europe/Zurich')).toBe(false); // 07:00
    expect(inQuietHours(p, new Date('2026-10-07T12:00:00Z'), 'Bogus/Zone')).toBe(false); // UTC fallback
    expect(inQuietHours({ ...p, quietStart: 13 * 60, quietEnd: 14 * 60 }, new Date('2026-10-07T13:15:00Z'), 'UTC')).toBe(true);
    expect(inQuietHours({ ...p, quietHours: false }, new Date('2026-10-07T21:30:00Z'), 'Europe/Zurich')).toBe(false);
  });
});
