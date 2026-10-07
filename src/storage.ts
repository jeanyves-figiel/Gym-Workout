import type { Profile, SetLog, WeekPlan } from './domain/types';

export interface AppState {
  profile?: Profile;
  plan?: WeekPlan;
  /** Session ids completed for the current plan. */
  done: Record<string, boolean>;
  /** Planned-item uids ticked off. */
  ticked: Record<string, boolean>;
  logs: SetLog[];
}

const KEY = 'gym-workout:v1';
export const EMPTY: AppState = { done: {}, ticked: {}, logs: [] };

export const load = (): AppState => {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? { ...EMPTY, ...(JSON.parse(raw) as AppState) } : EMPTY;
  } catch {
    return EMPTY;
  }
};

export const save = (s: AppState): void => {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* storage unavailable — app still works in-memory */
  }
};

export const lastWeight = (logs: SetLog[], exerciseId: string): number | undefined => {
  for (let i = logs.length - 1; i >= 0; i--) {
    const l = logs[i]!;
    if (l.exerciseId === exerciseId && l.weightKg != null) return l.weightKg;
  }
  return undefined;
};
