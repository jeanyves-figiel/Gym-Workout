import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.ts';
import { type ChatContext, type ChatTurn, type CoachAnswer, type CoachModel, clean, cleanDo, describeMember } from '../src/coach/chat.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { modelTurns } from '../src/routes/coachChat.ts';

const PW = 'correct-horse-battery';
let app: FastifyInstance;
let mailer: ConsoleMailer;
let clock: Date;
let calls: { turns: ChatTurn[]; context: ChatContext; photo?: Buffer }[];

const legs: CoachAnswer = {
  reply: 'Legs it is, shoulder-safe.',
  workout: { name: 'Legs, shoulder-safe', minutes: 45, groups: ['legs', 'hips'], rest: 'standard', grouping: 'straight', avoidGroups: ['shoulders'], avoidEquipment: [], avoidKeywords: ['lunge'] },
};

const start = (opts: { coach?: CoachModel | null; env?: Record<string, string> } = {}) => {
  clock = new Date('2026-10-16T10:00:00Z');
  mailer = new ConsoleMailer(() => {});
  calls = [];
  const coach: CoachModel = async (turns, context, photo) => {
    calls.push({ turns, context, ...(photo ? { photo } : {}) });
    return legs;
  };
  app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', AUTH_RATE_LIMIT_PER_MIN: '1000', ...opts.env }),
    db: openDb(':memory:'),
    mailer,
    apple: async () => {
      throw new Error('unused');
    },
    now: () => clock,
    coach: opts.coach === null ? undefined : (opts.coach ?? coach),
  });
};
afterEach(() => app.close());

const signUp = async (email: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: PW, acceptedTerms: true } })).statusCode).toBe(202);
  const code = [...mailer.outbox].reverse().find((m) => /\d{6} is your code/.test(m.subject))!.subject.match(/(\d{6})/)![1]!;
  const res = await app.inject({ method: 'POST', url: '/v1/auth/verify-email', payload: { email, code } });
  return (res.json() as { tokens: { accessToken: string } }).tokens.accessToken;
};
const chat = (token: string, payload: object) =>
  app.inject({ method: 'POST', url: '/v1/me/coach-chat', payload, headers: { authorization: `Bearer ${token}` } });

describe('workout chat (#381)', () => {
  it('answers with the coach line, settings and messages left', async () => {
    start({ env: { COACH_CHAT_DAILY_LIMIT: '5' } });
    const t = await signUp('a@example.com');
    const res = await chat(t, {
      turns: [
        { role: 'coach', text: 'What do you feel like today?' },
        { role: 'member', text: '45 min legs, sore shoulder' },
      ],
      context: { goal: 'strength', sessionMinutes: 60, equipment: ['barbell', 'rack'] },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ reply: legs.reply, workout: { groups: ['legs', 'hips'] }, remainingToday: 4 });
    // The greeting is dropped: the model's history starts with the member; no account data is passed.
    expect(calls[0]!.turns).toEqual([{ role: 'member', text: '45 min legs, sore shoulder' }]);
    expect(calls[0]!.context).toEqual({ goal: 'strength', sessionMinutes: 60, equipment: ['barbell', 'rack'] });
    const status = await app.inject({ method: 'GET', url: '/v1/me/coach-chat', headers: { authorization: `Bearer ${t}` } });
    expect(status.json()).toEqual({ available: true, remainingToday: 4 });
  });

  it('caps messages per member per day, resets the next day', async () => {
    start({ env: { COACH_CHAT_DAILY_LIMIT: '2', ACCESS_TTL_SEC: '172800' } });
    const t = await signUp('b@example.com');
    const turns = [{ role: 'member', text: 'legs' }];
    expect((await chat(t, { turns })).statusCode).toBe(200);
    expect((await chat(t, { turns })).statusCode).toBe(200);
    const capped = await chat(t, { turns });
    expect(capped.statusCode).toBe(429);
    expect(capped.json().error).toBe('daily_limit');
    expect(calls).toHaveLength(2);
    clock = new Date('2026-10-17T00:01:00Z');
    expect((await chat(t, { turns })).statusCode).toBe(200);
  });

  it('a failed model call answers 502 and does not use up a message', async () => {
    start({
      coach: async () => {
        throw new Error('overloaded');
      },
      env: { COACH_CHAT_DAILY_LIMIT: '1' },
    });
    const t = await signUp('c@example.com');
    const res = await chat(t, { turns: [{ role: 'member', text: 'arms' }] });
    expect(res.statusCode).toBe(502);
    const status = await app.inject({ method: 'GET', url: '/v1/me/coach-chat', headers: { authorization: `Bearer ${t}` } });
    expect(status.json().remainingToday).toBe(1);
  });

  it('parallel messages cannot pass the daily cap, and 2 run at once at most (#432)', async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    let running = 0;
    start({
      coach: async () => {
        running++;
        await gate;
        return legs;
      },
      env: { COACH_CHAT_DAILY_LIMIT: '1' },
    });
    const t = await signUp('p@example.com');
    const turns = [{ role: 'member', text: 'legs' }];
    const first = chat(t, { turns });
    const second = chat(t, { turns });
    await new Promise((r) => setTimeout(r, 50));
    release();
    const codes = (await Promise.all([first, second])).map((r) => r.statusCode).sort();
    expect(codes).toEqual([200, 429]);
    expect(running).toBe(1);

    let release2!: () => void;
    const gate2 = new Promise<void>((r) => (release2 = r));
    await app.close();
    start({ coach: async () => (await gate2, legs), env: { COACH_CHAT_DAILY_LIMIT: '10' } });
    const u = await signUp('q@example.com');
    const three = [chat(u, { turns }), chat(u, { turns }), chat(u, { turns })];
    await new Promise((r) => setTimeout(r, 50));
    release2();
    const res = await Promise.all(three);
    expect(res.map((r) => r.statusCode).sort()).toEqual([200, 200, 429]);
    expect(res.find((r) => r.statusCode === 429)!.json().error).toBe('busy');
    const status = await app.inject({ method: 'GET', url: '/v1/me/coach-chat', headers: { authorization: `Bearer ${u}` } });
    expect(status.json().remainingToday).toBe(8);
  });

  it('is off without an API key', async () => {
    start({ coach: null });
    const t = await signUp('d@example.com');
    expect((await chat(t, { turns: [{ role: 'member', text: 'legs' }] })).statusCode).toBe(503);
    const status = await app.inject({ method: 'GET', url: '/v1/me/coach-chat', headers: { authorization: `Bearer ${t}` } });
    expect(status.json().available).toBe(false);
  });

  it('is Pro once subscriptions are enforced', async () => {
    start({ env: { SUBSCRIPTIONS: 'enforced' } });
    const t = await signUp('e@example.com');
    const res = await chat(t, { turns: [{ role: 'member', text: 'legs' }] });
    expect(res.statusCode).toBe(402);
    expect(calls).toHaveLength(0);
  });

  it('rejects signed-out callers, a last coach turn and long messages', async () => {
    start();
    expect((await app.inject({ method: 'POST', url: '/v1/me/coach-chat', payload: { turns: [{ role: 'member', text: 'x' }] } })).statusCode).toBe(401);
    const t = await signUp('f@example.com');
    expect((await chat(t, { turns: [{ role: 'member', text: 'legs' }, { role: 'coach', text: 'ok' }] })).statusCode).toBe(400);
    expect((await chat(t, { turns: [{ role: 'member', text: 'x'.repeat(601) }] })).statusCode).toBe(400);
  });
});

describe('modelTurns', () => {
  it('keeps the last 12, starts with the member, merges same-role turns', () => {
    const turns: ChatTurn[] = [
      { role: 'coach', text: 'hi' },
      { role: 'member', text: 'legs' },
      { role: 'member', text: '30 min' },
      { role: 'coach', text: 'done' },
    ];
    expect(modelTurns(turns)).toEqual([
      { role: 'member', text: 'legs\n30 min' },
      { role: 'coach', text: 'done' },
    ]);
    const many = Array.from({ length: 20 }, (_, i): ChatTurn => ({ role: i % 2 ? 'coach' : 'member', text: `${i}` }));
    expect(modelTurns(many)[0]).toEqual({ role: 'member', text: '8' });
  });
});

describe('clean', () => {
  it('drops unknown values, avoided groups that are trained, and clamps minutes', () => {
    const a = clean(
      {
        reply: '  Go!  ',
        workout: {
          name: '',
          minutes: 500,
          groups: ['legs', 'legs', 'wings' as 'legs'],
          rest: 'forever' as 'long',
          grouping: 'straight',
          avoidGroups: ['legs', 'shoulders'],
          avoidEquipment: ['rack', 'spaceship'],
          avoidKeywords: [' Lunge ', 'x'],
        },
      },
      { equipment: ['rack'] },
    );
    expect(a).toEqual({
      reply: 'Go!',
      action: null,
      exercises: [],
      suggestions: [],
      protect: null,
      measurement: null,
      doActions: [],
      workout: { name: 'Coach workout', minutes: 120, groups: ['legs'], rest: 'standard', grouping: 'straight', avoidGroups: ['shoulders'], avoidEquipment: ['rack'], avoidKeywords: ['lunge'] },
    });
    expect(clean({ reply: 'Which muscles?', workout: { ...a.workout!, groups: [] } }, {}).workout).toBeNull();
  });
});

describe('ask from any screen (#412)', () => {
  it('passes the screen and what the member looks at to the coach', async () => {
    start();
    const t = await signUp('s@example.com');
    const res = await chat(t, {
      turns: [{ role: 'member', text: 'My shoulder clicks on this one' }],
      context: { screen: 'exercise', focus: 'Bench press · chest, triceps' },
    });
    expect(res.statusCode).toBe(200);
    expect(calls[0]!.context).toEqual({ screen: 'exercise', focus: 'Bench press · chest, triceps' });
  });

  it('keeps a valid open button and follow-ups, drops bad ones', () => {
    const ok = clean(
      { reply: 'Try neutral grip.', workout: null, action: { target: 'exercise', exercise: ' Dumbbell bench press ', label: 'Open DB press' }, suggestions: ['Form cues?', 'Form cues?', 'Lighter?', 'x', 'y'] },
      {},
    );
    expect(ok.action).toEqual({ target: 'exercise', exercise: 'Dumbbell bench press', label: 'Open DB press' });
    expect(ok.suggestions).toEqual(['Form cues?', 'Lighter?', 'x']);
    expect(clean({ reply: 'a', workout: null, action: { target: 'exercise', exercise: null, label: 'Open' } }, {}).action).toBeNull();
    expect(clean({ reply: 'a', workout: null, action: { target: 'moon' as 'progress', exercise: null, label: 'Go' } }, {}).action).toBeNull();
    expect(clean({ reply: 'a', workout: null, action: { target: 'progress', exercise: 'x', label: 'See progress' } }, {}).action).toEqual({
      target: 'progress',
      exercise: null,
      label: 'See progress',
    });
  });
});

describe('train around pain (#870)', () => {
  it('keeps logged measurements in range, drops odd ones, null when nothing is left (#1000)', () => {
    const ok = clean({ reply: 'Logged: 66 kilos.', workout: null, measurement: { weightKg: 66.04, bodyFatPct: null, girths: [
      { site: 'waist', side: 'none', cm: 82 },
      { site: 'upperArm', side: 'left', cm: 35.55 },
      { site: 'upperArm', side: 'left', cm: 40 },
      { site: 'ear' as 'neck', side: 'none', cm: 30 },
      { site: 'calf', side: 'up' as 'left', cm: 1000 },
    ] } }, {});
    expect(ok.measurement).toEqual({ weightKg: 66, bodyFatPct: null, girths: [{ site: 'waist', side: 'none', cm: 82 }, { site: 'upperArm', side: 'left', cm: 35.6 }] });
    expect(clean({ reply: 'a', workout: null, measurement: { weightKg: 900, bodyFatPct: 1, girths: [] } }, {}).measurement).toBeNull();
    expect(clean({ reply: 'a', workout: null }, {}).measurement).toBeNull();
  });

  it('keeps a valid protect, defaults side and level, drops unknown areas', () => {
    const ok = clean({ reply: 'I will protect it.', workout: null, protect: { area: 'knee', side: 'right', level: 'loaded', seeDoctor: false } }, {});
    expect(ok.protect).toEqual({ area: 'knee', side: 'right', level: 'loaded', seeDoctor: false });
    const odd = clean({ reply: 'a', workout: null, protect: { area: 'shoulder', side: 'up' as 'left', level: 'meh' as 'mild', seeDoctor: 'yes' as unknown as boolean } }, {});
    expect(odd.protect).toEqual({ area: 'shoulder', side: 'both', level: 'loaded', seeDoctor: false });
    expect(clean({ reply: 'a', workout: null, protect: { area: 'heart' as 'knee', side: 'both', level: 'sharp', seeDoctor: true } }, {}).protect).toBeNull();
    expect(clean({ reply: 'a', workout: null }, {}).protect).toBeNull();
  });
});

describe('pronouns and call name (#415)', () => {
  it('passes them to the coach and into the prompt', async () => {
    start();
    const t = await signUp('p@example.com');
    const res = await chat(t, { turns: [{ role: 'member', text: 'How am I doing?' }], context: { pronouns: 'she/her', callName: 'Queen' } });
    expect(res.statusCode).toBe(200);
    expect(calls[0]!.context).toEqual({ pronouns: 'she/her', callName: 'Queen' });
    const about = describeMember({ pronouns: 'she/her', callName: 'Queen' });
    expect(about).toContain('Pronouns: she/her');
    expect(about).toContain('Likes to be called: Queen');
    expect(describeMember({ callName: '{name}' })).toContain('write {name} where you use it');
  });

  it('passes what the coach remembers into the prompt (#495)', async () => {
    start();
    const t = await signUp('m@example.com');
    const memory = ['Working toward Barbell bench press 80 kg est. 1RM', 'Left knee: no deep lunges'];
    const res = await chat(t, { turns: [{ role: 'member', text: 'Leg day ideas?' }], context: { memory } });
    expect(res.statusCode).toBe(200);
    expect(calls[0]!.context).toEqual({ memory });
    expect(describeMember({ memory })).toContain('Left knee: no deep lunges');
    expect(describeMember({}).includes('remember')).toBe(false);
  });

  it('asks for neutral wording when pronouns are not set', () => {
    expect(describeMember({})).toContain('use neutral wording');
    expect(describeMember({}).includes('Likes to be called')).toBe(false);
  });

  it('rejects overlong values', async () => {
    start();
    const t = await signUp('q@example.com');
    const res = await chat(t, { turns: [{ role: 'member', text: 'Hi' }], context: { pronouns: 'x'.repeat(31) } });
    expect(res.statusCode).toBe(400);
  });
});

describe('freestyle: Coach adds exercises (#856)', () => {
  const list = ['Rope triceps pushdown', 'Overhead rope extension', 'Face pull'];

  it('keeps only names from the app list, spelled as the app spells them, max 4', () => {
    const a = clean({ reply: 'Cable with a rope.', workout: null, exercises: ['rope TRICEPS pushdown', 'Made-up curl', 'Face pull', 'Face pull'] }, { exercises: list });
    expect(a.exercises).toEqual(['Rope triceps pushdown', 'Face pull']);
    expect(clean({ reply: 'x', workout: null, exercises: ['Face pull'] }, {}).exercises).toEqual([]);
    expect(describeMember({ exercises: list })).toContain('Exercises in the app');
  });

  it('passes a machine photo with the last message, rejects a non-JPEG', async () => {
    start();
    const t = await signUp('f@example.com');
    const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(200, 7)]);
    const ok = await chat(t, { turns: [{ role: 'member', text: 'What can I do on this?' }], context: { screen: 'freestyle', exercises: list }, photo: jpeg.toString('base64') });
    expect(ok.statusCode).toBe(200);
    expect(calls[0]!.photo?.equals(jpeg)).toBe(true);
    expect(calls[0]!.context.exercises).toEqual(list);
    const bad = await chat(t, { turns: [{ role: 'member', text: 'This?' }], photo: Buffer.alloc(200, 1).toString('base64') });
    expect(bad.statusCode).toBe(400);
  });
});

describe('Coach can act (#999)', () => {
  const none = { glasses: null, foods: null, meal: null, mood: null, weekday: null, from: null, to: null };
  const ctx: ChatContext = { weekday: 5, todayExercises: ['Back squat', 'Leg press'] };

  it('keeps allowlisted actions in range, drops the rest', () => {
    const out = cleanDo([
      { ...none, kind: 'water', glasses: 2 },
      { ...none, kind: 'water', glasses: 40 },
      { ...none, kind: 'food', foods: '  oats and a banana ', meal: 'breakfast' },
      { ...none, kind: 'mood', mood: 9 },
      { ...none, kind: 'move', weekday: 3 },
      { ...none, kind: 'move', weekday: 6 },
      { ...none, kind: 'skip' },
      { ...none, kind: 'swap', from: 'back SQUAT', to: 'Hack squat' },
      { ...none, kind: 'swap', from: 'Deadlift', to: 'Hack squat' },
      { ...none, kind: 'delete-account' as never },
    ], ctx);
    expect(out).toEqual([
      { ...none, kind: 'water', glasses: 2 },
      { ...none, kind: 'food', foods: 'oats and a banana', meal: 'breakfast' },
      { ...none, kind: 'move', weekday: 6 },
      { ...none, kind: 'swap', from: 'Back squat', to: 'Hack squat' },
    ]);
  });

  it('caps at five, null-safe', () => {
    expect(cleanDo(Array(9).fill({ ...none, kind: 'water', glasses: 1 }), {})).toHaveLength(5);
    expect(cleanDo(undefined, {})).toEqual([]);
    expect(clean({ reply: 'a', workout: null }, {}).doActions).toEqual([]);
  });

  it('tells Coach the day and today\'s exercises', () => {
    const d = describeMember(ctx);
    expect(d).toContain('Today is: Friday (5)');
    expect(d).toContain("Today's exercises (for swap \"from\"): Back squat; Leg press");
  });
});
