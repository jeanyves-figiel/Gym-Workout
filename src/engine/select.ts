import { EXERCISES } from '../data/exercises';
import type { Category, Equipment, Exercise, Pattern } from '../domain/types';
import type { Region } from './config';
import type { Rng } from './rng';

export interface SelectCtx {
  rng: Rng;
  level: 1 | 2 | 3;
  equipment: ReadonlySet<Equipment>;
  /** Prefer exercises without heavy grip (frequent climber). */
  spareGrip: boolean;
  usedWeek: Set<string>;
  usedSession: Set<string>;
}

export interface Query {
  category: Category;
  pattern?: Pattern;
  regions?: Region[];
  main?: boolean;
  prefer?: string[];
}

export const isAvailable = (e: Exercise, equipment: ReadonlySet<Equipment>): boolean =>
  e.equipment.every((q) => equipment.has(q));

export const candidates = (ctx: Pick<SelectCtx, 'level' | 'equipment'>, q: Query): Exercise[] =>
  EXERCISES.filter(
    (e) =>
      e.category === q.category &&
      (!q.pattern || e.pattern === q.pattern) &&
      (!q.regions || (e.regions ?? []).some((r) => q.regions!.includes(r))) &&
      e.level <= ctx.level &&
      isAvailable(e, ctx.equipment),
  );

/** Picks best-scoring candidate, random tie-break. Marks it used. */
export const select = (ctx: SelectCtx, q: Query): Exercise | undefined => {
  const pool = candidates(ctx, q).filter((e) => !ctx.usedSession.has(e.id));
  if (pool.length === 0) return undefined;
  const score = (e: Exercise): number => {
    let s = 0;
    if (q.main && e.main) s += 8;
    // Intermediate+ main lifts: favour free-weight compounds over machines.
    if (q.main && ctx.level >= 2 && e.level >= 2) s += 1.5;
    if (q.prefer) {
      const i = q.prefer.indexOf(e.id);
      if (i >= 0) s += 4 - Math.min(3, i) * 0.5;
    }
    if (ctx.spareGrip && !e.gripHeavy) s += 2;
    if (!ctx.usedWeek.has(e.id)) s += 1;
    if (q.regions && e.regions) s += 0.5 * e.regions.filter((r) => q.regions!.includes(r)).length;
    return s;
  };
  const best = Math.max(...pool.map(score));
  const top = pool.filter((e) => score(e) >= best - 1e-9);
  const pick = ctx.rng.pick(top);
  ctx.usedSession.add(pick.id);
  ctx.usedWeek.add(pick.id);
  return pick;
};

/** Swap options: same role (pattern / target muscle / region), available, level-appropriate. */
export const alternatives = (
  exerciseId: string,
  ctx: Pick<SelectCtx, 'level' | 'equipment'>,
): Exercise[] => {
  const cur = EXERCISES.find((e) => e.id === exerciseId);
  if (!cur) return [];
  const pool = candidates(ctx, { category: cur.category }).filter((e) => e.id !== exerciseId);
  switch (cur.category) {
    case 'strength':
    case 'power':
      return pool.filter((e) => e.pattern === cur.pattern);
    case 'stretch':
      return pool.filter((e) => e.primary.some((m) => cur.primary.includes(m)));
    case 'mobility':
    case 'warmup':
      return pool.filter((e) => (e.regions ?? []).some((r) => (cur.regions ?? []).includes(r)));
    default:
      return pool;
  }
};
