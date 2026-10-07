import { describe, expect, it } from 'vitest';
import { ALL_EQUIPMENT } from '../data/gyms';
import { EXERCISES, getExercise } from '../data/exercises';
import type { Equipment, Goal, Profile } from '../domain/types';
import { generateWeek, muscleLoad, sessionMinutes } from './generator';
import { alternatives } from './select';

const base: Profile = {
  goal: 'balanced',
  sessionsPerWeek: 3,
  experience: 'intermediate',
  climbingDaysPerWeek: 0,
  equipment: ALL_EQUIPMENT,
};
const goals: Goal[] = ['balanced', 'build', 'strength', 'climbing', 'endurance', 'athletic'];

describe('exercise data', () => {
  it('has unique ids', () => {
    expect(new Set(EXERCISES.map((e) => e.id)).size).toBe(EXERCISES.length);
  });
});

describe('sessionMinutes', () => {
  it('gets shorter per session as frequency rises, weekly total grows', () => {
    const mins = ([2, 3, 4, 5, 6] as const).map((n) => sessionMinutes({ ...base, sessionsPerWeek: n }));
    for (let i = 1; i < mins.length; i++) expect(mins[i]!).toBeLessThanOrEqual(mins[i - 1]!);
    const weekly = mins.map((m, i) => m * (i + 2));
    for (let i = 1; i < weekly.length; i++) expect(weekly[i]!).toBeGreaterThan(weekly[i - 1]!);
  });
  it('depends on goal', () => {
    expect(sessionMinutes({ ...base, goal: 'strength' })).toBeGreaterThan(sessionMinutes({ ...base, goal: 'climbing' }));
  });
  it('respects user cap and is a multiple of 5', () => {
    expect(sessionMinutes({ ...base, maxSessionMinutes: 45 })).toBeLessThanOrEqual(45);
    expect(sessionMinutes(base) % 5).toBe(0);
  });
});

describe('generateWeek', () => {
  it('is deterministic for a seed', () => {
    expect(generateWeek(base, { seed: 42 })).toEqual(generateWeek(base, { seed: 42 }));
  });

  it.each(goals)('fits session estimate to target (%s)', (goal) => {
    for (const n of [2, 3, 4, 5, 6] as const) {
      const plan = generateWeek({ ...base, goal, sessionsPerWeek: n }, { seed: 1 });
      expect(plan.sessions).toHaveLength(n);
      for (const s of plan.sessions) {
        expect(Math.abs(s.estMin - s.targetMin)).toBeLessThanOrEqual(Math.max(8, s.targetMin * 0.15));
      }
    }
  });

  it('always has warm-up, strength and cool-down; ordered', () => {
    const order = ['warmup', 'power', 'strength', 'mobility', 'cardio', 'cooldown'];
    for (const s of generateWeek(base, { seed: 3 }).sessions) {
      const kinds = s.blocks.map((b) => b.kind);
      expect(kinds[0]).toBe('warmup');
      expect(kinds).toContain('strength');
      expect(kinds.at(-1)).toBe('cooldown');
      const idx = kinds.map((k) => order.indexOf(k));
      expect([...idx].sort((a, b) => a - b)).toEqual(idx);
    }
  });

  it('balanced goal includes power, mobility and cardio', () => {
    for (const s of generateWeek(base, { seed: 5 }).sessions) {
      const kinds = s.blocks.map((b) => b.kind);
      expect(kinds).toEqual(expect.arrayContaining(['power', 'mobility', 'cardio']));
    }
  });

  it('only uses available equipment', () => {
    const equipment: Equipment[] = ['dumbbells', 'bench', 'cable', 'mat', 'bike', 'bands'];
    const plan = generateWeek({ ...base, equipment }, { seed: 9 });
    for (const s of plan.sessions)
      for (const b of s.blocks)
        for (const it of b.items) expect(getExercise(it.exerciseId).equipment.every((q) => equipment.includes(q))).toBe(true);
  });

  it('respects experience level', () => {
    const plan = generateWeek({ ...base, experience: 'beginner' }, { seed: 11 });
    for (const s of plan.sessions) for (const b of s.blocks) for (const it of b.items) expect(getExercise(it.exerciseId).level).toBe(1);
  });

  it('deload week reduces volume', () => {
    const w2 = generateWeek(base, { seed: 2, week: 2 });
    const w4 = generateWeek(base, { seed: 2, week: 4 });
    expect(w4.deload).toBe(true);
    expect(w4.sessionMinutes).toBeLessThan(w2.sessionMinutes);
    const main = (p: typeof w2) => p.sessions[0]!.blocks.find((b) => b.kind === 'strength')!.items[0]!.prescription.sets;
    expect(main(w4)).toBeLessThan(main(w2));
    for (const s of w4.sessions) for (const b of s.blocks) if (b.kind === 'cardio') expect(b.title).toContain('Zone 2');
  });

  it('climber gets shoulder health + forearm antagonist, fewer grip-heavy lifts', () => {
    const climber = generateWeek({ ...base, goal: 'climbing', climbingDaysPerWeek: 3, sessionsPerWeek: 4 }, { seed: 4 });
    const upper = climber.sessions.filter((s) => s.focus === 'upper');
    for (const s of upper) {
      const slots = s.blocks.find((b) => b.kind === 'strength')!.items.map((i) => i.slot);
      expect(slots).toContain('shoulder-health');
    }
    const ids = climber.sessions.flatMap((s) => s.blocks.flatMap((b) => b.items.map((i) => i.exerciseId)));
    expect(ids.some((id) => getExercise(id).pattern === 'forearm-antagonist')).toBe(true);
    const strengthIds = climber.sessions.flatMap((s) => s.blocks.filter((b) => b.kind === 'strength').flatMap((b) => b.items.map((i) => i.exerciseId)));
    const grip = strengthIds.filter((id) => getExercise(id).gripHeavy).length;
    expect(grip).toBeLessThanOrEqual(1);
  });

  it('cool-down stretches target the most-loaded muscles', () => {
    for (const s of generateWeek({ ...base, sessionsPerWeek: 4 }, { seed: 8 }).sessions) {
      const cd = s.blocks.find((b) => b.kind === 'cooldown')!;
      const load = muscleLoad(s.blocks);
      const top = [...load.entries()].sort((a, b) => b[1] - a[1])[0]![0];
      const stretched = cd.items.flatMap((i) => getExercise(i.exerciseId).primary);
      expect(stretched).toContain(top);
      expect(cd.items.at(-1)!.exerciseId).toBe('breathing');
    }
  });

  it('varies exercises across the week', () => {
    const plan = generateWeek({ ...base, sessionsPerWeek: 4 }, { seed: 12 });
    const mains = plan.sessions.map((s) => s.blocks.find((b) => b.kind === 'strength')!.items[0]!.exerciseId);
    expect(mains[0]).not.toBe(mains[2]);
    expect(mains[1]).not.toBe(mains[3]);
  });
});

describe('alternatives', () => {
  it('returns same-pattern, available options', () => {
    const alts = alternatives('back-squat', { level: 3, equipment: new Set(ALL_EQUIPMENT) });
    expect(alts.length).toBeGreaterThan(2);
    expect(alts.every((a) => a.pattern === 'squat')).toBe(true);
  });
});
