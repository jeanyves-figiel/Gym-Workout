import { EXERCISE_BY_ID, getExercise } from '../data/exercises';
import type {
  Block,
  Exercise,
  Focus,
  Muscle,
  Pattern,
  PlannedExercise,
  Prescription,
  Profile,
  Session,
  WeekPlan,
} from '../domain/types';
import {
  type CardioMode,
  type Dose,
  EXPERIENCE_DELTA,
  EXPERIENCE_LEVEL,
  FOCUS_LABEL,
  FOCUS_MIX,
  FOCUS_REGIONS,
  FREQUENCY_FACTOR,
  GOALS,
  LIGHT_PATTERNS,
  MAX_SESSION,
  MIN_SESSION,
  type Mix,
  POWER_PATTERNS,
  type Region,
  SPLITS,
  STRENGTH_SLOTS,
} from './config';
import { createRng, type Rng } from './rng';
import { candidates, select, type SelectCtx } from './select';

export const MESOCYCLE_WEEKS = 4;
const TRANSITION_SEC = 30;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const round5 = (v: number) => Math.round(v / 5) * 5;

export const isClimber = (p: Profile) => p.goal === 'climbing' || p.climbingDaysPerWeek >= 1;
export const sparesGrip = (p: Profile) => p.climbingDaysPerWeek >= 2;

/**
 * Session length from goal × weekly frequency × experience × climbing load, capped by user limit.
 * Fewer sessions → longer sessions; total weekly time still grows with frequency.
 */
export const sessionMinutes = (p: Profile): number => {
  const g = GOALS[p.goal];
  const raw =
    g.baseMinutes * (FREQUENCY_FACTOR[p.sessionsPerWeek] ?? 1) +
    EXPERIENCE_DELTA[p.experience] -
    2 * Math.max(0, p.climbingDaysPerWeek - 1);
  const cap = p.maxSessionMinutes ? Math.max(MIN_SESSION - 10, p.maxSessionMinutes) : MAX_SESSION;
  return Math.min(round5(clamp(raw, MIN_SESSION, MAX_SESSION)), cap);
};

export const weekLabel = (week: number): string =>
  ['Base · RPE −1', 'Build · target RPE', 'Peak · +1 set on main lifts', 'Deload · −40 % volume'][(week - 1) % MESOCYCLE_WEEKS]!;

interface Ctx extends SelectCtx {
  profile: Profile;
  week: number;
  deload: boolean;
  climber: boolean;
}

// ───────────────────────── helpers

const workSec = (e: Exercise, repsMid: number, holdSec = 40): number =>
  (e.unit === 'sec' ? holdSec : repsMid * (e.secPerRep ?? 3)) * (e.unilateral ? 2 : 1);

const itemSec = (e: Exercise, p: Prescription, repsMid: number, holdSec?: number): number =>
  p.sets * workSec(e, repsMid, holdSec) + Math.max(0, p.sets - 1) * p.restSec + TRANSITION_SEC;

const perSide = (e: Exercise) => (e.unilateral ? ' / side' : '');

const rpeFor = (ctx: Ctx, base: number): number => {
  if (ctx.deload) return base - 2;
  if (ctx.week % MESOCYCLE_WEEKS === 1) return base - 1;
  return base;
};

const normalise = (m: Mix): Mix => {
  const t = m.power + m.strength + m.mobility + m.cardio;
  return { power: m.power / t, strength: m.strength / t, mobility: m.mobility / t, cardio: m.cardio / t };
};

const sessionMix = (p: Profile, focus: Focus): Mix => {
  const base = { ...GOALS[p.goal].mix };
  const mod = FOCUS_MIX[focus] ?? {};
  (Object.keys(base) as (keyof Mix)[]).forEach((k) => (base[k] *= mod[k] ?? 1));
  if (p.goal !== 'climbing' && p.climbingDaysPerWeek >= 1) base.mobility *= 1.3;
  return normalise(base);
};

// ───────────────────────── warm-up

const RAISE_UPPER = ['rower', 'ski-erg', 'air-bike', 'elliptical'];
const RAISE_LOWER = ['bike', 'incline-walk', 'rower', 'elliptical', 'stair-climber'];

const buildWarmup = (ctx: Ctx, focus: Focus, minutes: number, uidBase: string): Block => {
  const upper = ['upper', 'push', 'pull', 'full-upper'].includes(focus);
  const raiseMin = minutes >= 9 ? 5 : 4;
  const raise = select(ctx, { category: 'cardio', prefer: upper ? RAISE_UPPER : RAISE_LOWER });
  const items: PlannedExercise[] = [];
  if (raise) {
    items.push({
      uid: `${uidBase}-0`,
      exerciseId: raise.id,
      slot: 'general',
      prescription: { sets: 1, reps: `${raiseMin} min`, restSec: 0, intensity: 'Easy → moderate · RPE 3–5' },
      estSec: raiseMin * 60,
    });
  }
  const regions = [...FOCUS_REGIONS[focus]];
  if (ctx.climber && !regions.includes('wrists')) regions.push('wrists');
  const drillCount = clamp(Math.round((minutes - raiseMin) / 0.9), 3, 6);
  for (let i = 0; i < drillCount; i++) {
    const region = regions[i % regions.length]!;
    const d = select(ctx, { category: 'warmup', regions: [region] });
    if (!d) continue;
    items.push({
      uid: `${uidBase}-${items.length}`,
      exerciseId: d.id,
      slot: 'general',
      prescription: { sets: 1, reps: d.unilateral ? '6 / side' : '8–10', restSec: 0 },
      estSec: 50,
    });
  }
  return {
    kind: 'warmup',
    title: 'Warm-up',
    targetMin: minutes,
    items,
    note: 'Raise heart rate, then move through today\'s ranges. Ramp-up sets on the first lift are done in the strength block.',
  };
};

// ───────────────────────── power

const buildPower = (ctx: Ctx, focus: Focus, minutes: number, uidBase: string): Block | undefined => {
  if (minutes < 4) return undefined;
  const budget = minutes * 60;
  const items: PlannedExercise[] = [];
  let used = 0;
  const patterns = POWER_PATTERNS[focus];
  for (let i = 0; i < patterns.length * 2 && used < budget * 0.9; i++) {
    const e = select(ctx, { category: 'power', pattern: patterns[i % patterns.length]! });
    if (!e) continue;
    const baseSets = ctx.profile.goal === 'athletic' && ctx.profile.experience !== 'beginner' ? 4 : 3;
    const sets = ctx.deload ? baseSets - 1 : baseSets;
    const isSec = e.unit === 'sec';
    const presc: Prescription = {
      sets,
      reps: isSec ? '15 s' : `${e.id === 'kb-swing' ? '8–10' : '3–5'}${perSide(e)}`,
      restSec: isSec ? 75 : 60,
      intensity: 'Max intent · stop before speed drops',
    };
    const est = itemSec(e, presc, e.id === 'kb-swing' ? 9 : 4, 15);
    if (items.length > 0 && used + est > budget * 1.1) break;
    items.push({ uid: `${uidBase}-${items.length}`, exerciseId: e.id, slot: e.pattern, prescription: presc, estSec: est });
    used += est;
  }
  if (items.length === 0) return undefined;
  return {
    kind: 'power',
    title: 'Explosive',
    targetMin: minutes,
    items,
    note: 'Done fresh, before strength work. Alternate exercises (A1/A2) so each gets full recovery; quality reps only.',
  };
};

// ───────────────────────── strength

const climberSlots = (slots: Pattern[], focus: Focus, ctx: Ctx): Pattern[] => {
  if (!ctx.climber) return slots;
  let out = [...slots];
  const upperish = !['lower', 'legs'].includes(focus);
  if (upperish) {
    // Prehab right after the main lift so it survives short sessions.
    out = out.filter((s) => s !== 'shoulder-health' && s !== 'forearm-antagonist');
    out.splice(1, 0, 'shoulder-health');
    out.splice(Math.min(3, out.length), 0, 'forearm-antagonist');
  }
  if (ctx.spareGrip) out = out.filter((s) => s !== 'arms-flex');
  return out;
};

const doseFor = (
  ctx: Ctx,
  isMain: boolean,
  circuit: boolean,
  pattern: Pattern,
  e: Exercise,
): { presc: Prescription; repsMid: number } => {
  const g = GOALS[ctx.profile.goal];
  const beginner = ctx.profile.experience === 'beginner';
  const light = LIGHT_PATTERNS.includes(pattern);
  let d: Dose;
  if (isMain) d = g.main;
  else if (light) d = { sets: beginner ? 2 : 3, reps: e.unit === 'sec' ? '30–45 s' : '12–15', repsMid: 13, restSec: 45, rpe: 7 };
  else d = g.accessory;
  if (circuit) d = { ...d, sets: 3, restSec: 30, rpe: 7 };

  let sets = d.sets - (beginner && !light && !circuit ? 1 : 0);
  if (isMain && ctx.week % MESOCYCLE_WEEKS === 3 && !beginner) sets += 1;
  const notes: string[] = [];
  if (ctx.spareGrip && (pattern === 'v-pull' || pattern === 'h-pull')) {
    sets = Math.max(2, sets - 1);
    notes.push('Reduced: climbing already loads pulling');
  }
  if (ctx.deload) sets = Math.max(1, Math.round(sets * 0.6));
  if (isMain) notes.unshift('2–3 ramp-up sets first');

  const reps = pattern === 'carry' ? '40 s' : e.unit === 'sec' && !light ? '30–45 s' : d.reps;
  return {
    presc: {
      sets,
      reps: `${reps}${perSide(e)}`,
      restSec: d.restSec,
      intensity: `RPE ${rpeFor(ctx, d.rpe)}`,
      note: notes.join(' · ') || undefined,
    },
    repsMid: d.repsMid,
  };
};

const buildStrength = (
  ctx: Ctx,
  focus: Focus,
  variant: 0 | 1,
  minutes: number,
  uidBase: string,
  pairRegions: Region[],
): Block => {
  const budget = minutes * 60;
  const circuit = focus === 'conditioning';
  const slots = climberSlots(STRENGTH_SLOTS[focus][variant], focus, ctx);
  const items: PlannedExercise[] = [];
  const pairUsed = new Set<string>();
  let used = 0;

  slots.forEach((pattern, i) => {
    if (items.length >= 2 && used >= budget * 1.05) return;
    const isMain = items.length === 0 && !circuit;
    const e = select(ctx, { category: 'strength', pattern, main: isMain });
    if (!e) return;
    const { presc, repsMid } = doseFor(ctx, isMain, circuit, pattern, e);

    // Light prehab/core work is supersetted into the rest of the last heavy exercise.
    const light = LIGHT_PATTERNS.includes(pattern) && !circuit;
    const host = light ? [...items].reverse().find((it) => !LIGHT_PATTERNS.includes(it.slot)) : undefined;
    const superset = !!host && !items.some((it) => it.supersetWith === host.uid) && host.prescription.restSec >= 75;

    let est = superset
      ? presc.sets * workSec(e, repsMid, 40) + TRANSITION_SEC
      : itemSec(e, presc, repsMid, 40);
    if (isMain) est += 180; // ramp-up sets
    if (items.length >= 2 && used + est > budget * 1.1) {
      ctx.usedSession.delete(e.id);
      ctx.usedWeek.delete(e.id);
      return;
    }

    let pairedWith: string | undefined;
    if (superset && host) {
      host.pairedWith = undefined; // rest now used by the superset
      presc.note = [`Superset: do in rest of ${getExercise(host.exerciseId).name}`, presc.note].filter(Boolean).join(' · ');
    } else if (presc.restSec >= 90) {
      const region = pairRegions[(items.length + i) % pairRegions.length]!;
      const m = candidates(ctx, { category: 'mobility', regions: [region] }).filter(
        (x) => !pairUsed.has(x.id) && !ctx.usedSession.has(x.id),
      );
      if (m.length) {
        const pick = ctx.rng.pick(m);
        pairUsed.add(pick.id);
        pairedWith = pick.id;
      }
    }
    items.push({
      uid: `${uidBase}-${items.length}`,
      exerciseId: e.id,
      slot: pattern,
      prescription: presc,
      estSec: est,
      pairedWith,
      supersetWith: superset ? host!.uid : undefined,
    });
    used += est;
  });

  return {
    kind: 'strength',
    title: circuit ? 'Strength circuit' : 'Strength',
    targetMin: minutes,
    items,
    note: circuit
      ? 'Circuit: move straight between exercises, 30 s transition. Rest 60–90 s after each round.'
      : 'Leave 1–3 reps in reserve per RPE. Paired mobility drills and supersets happen during rest — no extra time.',
  };
};

// ───────────────────────── mobility

const buildMobility = (ctx: Ctx, focus: Focus, minutes: number, uidBase: string): Block | undefined => {
  if (minutes < 3) return undefined;
  const regions: Region[] = ctx.climber
    ? Array.from(new Set<Region>(['hips', 'shoulders', ...FOCUS_REGIONS[focus], 'wrists']))
    : FOCUS_REGIONS[focus];
  const count = clamp(Math.floor(minutes / 2), 2, 8);
  const items: PlannedExercise[] = [];
  for (let i = 0; i < count; i++) {
    const e =
      select(ctx, { category: 'mobility', regions: [regions[i % regions.length]!] }) ??
      select(ctx, { category: 'mobility', regions });
    if (!e) continue;
    const presc: Prescription = {
      sets: 2,
      reps: e.unit === 'sec' ? `45 s${perSide(e)}` : `6–8${perSide(e)}`,
      restSec: 0,
      intensity: 'Slow · end-range control',
    };
    items.push({ uid: `${uidBase}-${items.length}`, exerciseId: e.id, slot: 'general', prescription: presc, estSec: 120 });
  }
  if (!items.length) return undefined;
  return {
    kind: 'mobility',
    title: ctx.climber ? 'Climber mobility' : 'Mobility',
    targetMin: minutes,
    items,
    note: ctx.climber
      ? 'Active range for high-steps, drop-knees, heel hooks and overhead reaches.'
      : 'Active end-range work — own the range you trained.',
  };
};

// ───────────────────────── cardio

const CARDIO_PREF: Record<CardioMode, string[]> = {
  zone2: ['rower', 'bike', 'incline-walk', 'elliptical', 'stair-climber', 'treadmill-run', 'ski-erg'],
  intervals: ['air-bike', 'rower', 'ski-erg', 'bike'],
  threshold: ['rower', 'treadmill-run', 'ski-erg', 'bike', 'stair-climber'],
  sprints: ['air-bike', 'ski-erg', 'rower'],
};

const cardioPresc = (mode: CardioMode, minutes: number): Prescription => {
  switch (mode) {
    case 'zone2':
      return { sets: 1, reps: `${minutes} min`, restSec: 0, intensity: 'Zone 2 · RPE 3–4 · can talk in full sentences' };
    case 'intervals': {
      const n = Math.max(3, Math.floor((minutes - 3) / 2));
      return { sets: n, reps: '1 min hard / 1 min easy', restSec: 0, intensity: 'Hard = RPE 8', note: '3 min easy before' };
    }
    case 'threshold': {
      const long = minutes >= 24;
      const work = long ? 4 : 3;
      const rest = long ? 3 : 2;
      const n = Math.max(2, Math.floor((minutes - 3) / (work + rest)));
      return { sets: n, reps: `${work} min on / ${rest} min easy`, restSec: 0, intensity: 'On = RPE 7–8 · controlled breathing', note: '3 min easy before' };
    }
    case 'sprints': {
      const n = clamp(Math.floor((minutes - 3) / 1), 5, 10);
      return { sets: n, reps: '15 s all-out / 45 s easy', restSec: 0, intensity: 'All-out', note: '3 min easy before' };
    }
  }
};

const buildCardio = (ctx: Ctx, mode: CardioMode, minutes: number, uidBase: string): Block | undefined => {
  if (minutes < 6) return undefined;
  const m: CardioMode = ctx.deload ? 'zone2' : minutes < 10 && mode === 'threshold' ? 'intervals' : mode;
  const prefer = ctx.climber && m === 'zone2' ? ['incline-walk', 'stair-climber', ...CARDIO_PREF.zone2] : CARDIO_PREF[m];
  const e = select(ctx, { category: 'cardio', prefer });
  if (!e) return undefined;
  const titles: Record<CardioMode, string> = {
    zone2: 'Cardio · Zone 2',
    intervals: 'Cardio · Intervals',
    threshold: 'Cardio · Threshold',
    sprints: 'Cardio · Sprints',
  };
  return {
    kind: 'cardio',
    title: titles[m],
    targetMin: minutes,
    items: [{ uid: `${uidBase}-0`, exerciseId: e.id, slot: 'general', prescription: cardioPresc(m, minutes), estSec: minutes * 60 }],
  };
};

// ───────────────────────── cool-down (derived from session load)

export const muscleLoad = (blocks: Block[]): Map<Muscle, number> => {
  const load = new Map<Muscle, number>();
  const add = (m: Muscle, v: number) => load.set(m, (load.get(m) ?? 0) + v);
  for (const b of blocks) {
    if (b.kind === 'warmup' || b.kind === 'mobility' || b.kind === 'cooldown') continue;
    for (const it of b.items) {
      const e = getExercise(it.exerciseId);
      const vol = b.kind === 'cardio' ? it.estSec / 300 : it.prescription.sets;
      e.primary.forEach((m) => add(m, vol));
      (e.secondary ?? []).forEach((m) => add(m, vol * 0.5));
      if (e.gripHeavy) add('forearms', vol * 0.5);
    }
  }
  return load;
};

const buildCooldown = (ctx: Ctx, minutes: number, prior: Block[], uidBase: string): Block => {
  const budget = minutes * 60;
  const load = muscleLoad(prior);
  if (ctx.climber) load.set('forearms', (load.get('forearms') ?? 0) + 2);
  const items: PlannedExercise[] = [];
  let used = 0;

  const cardio = prior.find((b) => b.kind === 'cardio');
  const hardCardio = cardio && !cardio.title.includes('Zone 2');
  if (hardCardio && cardio.items[0]) {
    items.push({
      uid: `${uidBase}-flush`,
      exerciseId: cardio.items[0].exerciseId,
      slot: 'general',
      prescription: { sets: 1, reps: '2 min', restSec: 0, intensity: 'Very easy · bring HR down' },
      estSec: 120,
    });
    used += 120;
  }

  const breathingSec = 90;
  const stretches = candidates(ctx, { category: 'stretch' }).filter((e) => e.id !== 'breathing');
  const remaining = new Map(load);
  const chosen = new Set<string>();
  while (used + breathingSec < budget) {
    let best: Exercise | undefined;
    let bestScore = 0;
    for (const s of stretches) {
      if (chosen.has(s.id)) continue;
      const sc = s.primary.reduce((acc, m) => acc + (remaining.get(m) ?? 0), 0);
      if (sc > bestScore + 1e-9) {
        bestScore = sc;
        best = s;
      }
    }
    if (!best) break;
    const est = (best.unilateral ? 90 : 45) + 15;
    if (used + est + breathingSec > budget * 1.1) break;
    chosen.add(best.id);
    best.primary.forEach((m) => remaining.set(m, (remaining.get(m) ?? 0) * 0.25));
    items.push({
      uid: `${uidBase}-${items.length}`,
      exerciseId: best.id,
      slot: 'general',
      prescription: { sets: 1, reps: `45 s${perSide(best)}`, restSec: 0, intensity: 'Relaxed · long exhales' },
      estSec: est,
    });
    used += est;
  }
  if (EXERCISE_BY_ID.breathing) {
    items.push({
      uid: `${uidBase}-breath`,
      exerciseId: 'breathing',
      slot: 'general',
      prescription: { sets: 1, reps: '90 s', restSec: 0 },
      estSec: breathingSec,
    });
  }

  const top = [...load.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([m]) => m);
  return {
    kind: 'cooldown',
    title: 'Cool-down',
    targetMin: minutes,
    items,
    note: `Targets today's most-loaded muscles: ${top.join(', ')}.`,
  };
};

// ───────────────────────── session & week

export interface GenerateOptions {
  week?: number;
  seed?: number;
}

const blockMinutes = (b: Block) => b.items.reduce((s, i) => s + i.estSec, 0) / 60;

export const generateSession = (
  ctx: Ctx,
  focus: Focus,
  variant: 0 | 1,
  index: number,
  minutes: number,
  cardioMode: CardioMode,
): Session => {
  const id = `w${ctx.week}s${index + 1}`;
  ctx.usedSession = new Set();
  const warm = clamp(Math.round(minutes * 0.12), 6, 10);
  const cool = clamp(Math.round(minutes * 0.1), 5, 10);
  const work = minutes - warm - cool;
  const mix = sessionMix(ctx.profile, focus);

  let powerMin = Math.round(work * mix.power);
  let mobilityMin = Math.round(work * mix.mobility);
  let cardioMin = Math.round(work * mix.cardio);
  if (powerMin < 4) powerMin = 0;
  if (mobilityMin < 3) mobilityMin = 0;
  if (cardioMin < 6) cardioMin = 0;
  const strengthMin = work - powerMin - mobilityMin - cardioMin;

  const regions = ctx.climber
    ? Array.from(new Set<Region>([...FOCUS_REGIONS[focus], 'hips', 'shoulders']))
    : FOCUS_REGIONS[focus];

  const blocks: Block[] = [buildWarmup(ctx, focus, warm, `${id}-wu`)];
  const power = buildPower(ctx, focus, powerMin, `${id}-pw`);
  if (power) blocks.push(power);
  const powerLeft = power ? Math.max(0, powerMin - Math.round(blockMinutes(power))) : powerMin;
  blocks.push(buildStrength(ctx, focus, variant, strengthMin + powerLeft, `${id}-st`, regions));
  const mob = buildMobility(ctx, focus, mobilityMin, `${id}-mo`);
  if (mob) blocks.push(mob);
  const cardio = buildCardio(ctx, cardioMode, cardioMin, `${id}-ca`);
  if (cardio) blocks.push(cardio);
  blocks.push(buildCooldown(ctx, cool, blocks, `${id}-cd`));

  const est = Math.round(blocks.reduce((s, b) => s + blockMinutes(b), 0));
  return {
    id,
    index,
    focus,
    title: `Day ${index + 1} · ${FOCUS_LABEL[focus]}`,
    targetMin: minutes,
    estMin: est,
    blocks,
  };
};

export const generateWeek = (profile: Profile, opts: GenerateOptions = {}): WeekPlan => {
  const week = clamp(opts.week ?? 1, 1, MESOCYCLE_WEEKS);
  const seed = (opts.seed ?? Date.now()) >>> 0;
  const rng: Rng = createRng(seed + week * 7919);
  const deload = week === MESOCYCLE_WEEKS;
  const base = sessionMinutes(profile);
  const minutes = deload ? Math.max(MIN_SESSION - 5, round5(base * 0.8)) : base;
  const ctx: Ctx = {
    rng,
    level: EXPERIENCE_LEVEL[profile.experience],
    equipment: new Set(profile.equipment),
    spareGrip: sparesGrip(profile),
    usedWeek: new Set(),
    usedSession: new Set(),
    profile,
    week,
    deload,
    climber: isClimber(profile),
  };
  const split = SPLITS[profile.sessionsPerWeek] ?? SPLITS[3]!;
  const seen = new Map<Focus, number>();
  const cardioRot = GOALS[profile.goal].cardio;
  const sessions = split.map((focus, i) => {
    const n = seen.get(focus) ?? 0;
    seen.set(focus, n + 1);
    const mode = focus === 'conditioning' ? 'intervals' : cardioRot[i % cardioRot.length]!;
    return generateSession(ctx, focus, (n % 2) as 0 | 1, i, minutes, mode);
  });
  return { week, deload, seed, sessionMinutes: minutes, sessions };
};
