import type { Experience, Focus, Goal, Pattern } from '../domain/types';

export interface Dose {
  sets: number;
  reps: string;
  /** Rep count used for time estimates. */
  repsMid: number;
  restSec: number;
  rpe: number;
}

export interface Mix {
  power: number;
  strength: number;
  mobility: number;
  cardio: number;
}

export type CardioMode = 'zone2' | 'intervals' | 'threshold' | 'sprints';

export interface GoalConfig {
  label: string;
  blurb: string;
  /** Session minutes at 3×/week, intermediate. */
  baseMinutes: number;
  mix: Mix;
  main: Dose;
  accessory: Dose;
  /** Cardio mode rotation across the week's sessions. */
  cardio: CardioMode[];
}

export const GOALS: Record<Goal, GoalConfig> = {
  balanced: {
    label: 'Balanced athlete',
    blurb: 'Strength + definition, climber mobility, endurance and explosiveness in every session.',
    baseMinutes: 70,
    mix: { power: 0.12, strength: 0.5, mobility: 0.13, cardio: 0.25 },
    main: { sets: 4, reps: '5–8', repsMid: 6, restSec: 150, rpe: 8 },
    accessory: { sets: 3, reps: '8–12', repsMid: 10, restSec: 75, rpe: 8 },
    cardio: ['zone2', 'intervals', 'zone2', 'threshold'],
  },
  build: {
    label: 'Build & define',
    blurb: 'Hypertrophy-biased volume for a defined physique, cardio kept for leanness.',
    baseMinutes: 70,
    mix: { power: 0.07, strength: 0.65, mobility: 0.08, cardio: 0.2 },
    main: { sets: 4, reps: '6–10', repsMid: 8, restSec: 120, rpe: 8 },
    accessory: { sets: 3, reps: '10–15', repsMid: 12, restSec: 60, rpe: 9 },
    cardio: ['zone2', 'intervals'],
  },
  strength: {
    label: 'Max strength',
    blurb: 'Heavy compounds, long rests, minimal junk volume.',
    baseMinutes: 75,
    mix: { power: 0.12, strength: 0.68, mobility: 0.08, cardio: 0.12 },
    main: { sets: 5, reps: '3–5', repsMid: 4, restSec: 180, rpe: 8 },
    accessory: { sets: 3, reps: '6–8', repsMid: 7, restSec: 120, rpe: 8 },
    cardio: ['zone2'],
  },
  climbing: {
    label: 'Climbing performance',
    blurb: 'Strength-to-weight, antagonist & shoulder health, hip/shoulder mobility, power for dynos.',
    baseMinutes: 60,
    mix: { power: 0.15, strength: 0.4, mobility: 0.25, cardio: 0.2 },
    main: { sets: 4, reps: '4–6', repsMid: 5, restSec: 150, rpe: 8 },
    accessory: { sets: 3, reps: '8–10', repsMid: 9, restSec: 75, rpe: 8 },
    cardio: ['zone2', 'zone2', 'intervals'],
  },
  endurance: {
    label: 'Endurance',
    blurb: 'Aerobic engine first; strength maintained with lighter, faster circuits.',
    baseMinutes: 65,
    mix: { power: 0.05, strength: 0.35, mobility: 0.1, cardio: 0.5 },
    main: { sets: 3, reps: '8–12', repsMid: 10, restSec: 90, rpe: 7 },
    accessory: { sets: 3, reps: '12–15', repsMid: 13, restSec: 45, rpe: 7 },
    cardio: ['zone2', 'threshold', 'zone2', 'intervals'],
  },
  athletic: {
    label: 'Explosive / athletic',
    blurb: 'Jumps, throws and fast lifts with strength support.',
    baseMinutes: 65,
    mix: { power: 0.25, strength: 0.45, mobility: 0.1, cardio: 0.2 },
    main: { sets: 4, reps: '3–5', repsMid: 4, restSec: 150, rpe: 8 },
    accessory: { sets: 3, reps: '6–8', repsMid: 7, restSec: 90, rpe: 8 },
    cardio: ['sprints', 'zone2', 'intervals'],
  },
};

/** Fewer sessions → longer sessions; more sessions → shorter but more weekly volume. */
export const FREQUENCY_FACTOR: Record<number, number> = { 2: 1.2, 3: 1.0, 4: 0.9, 5: 0.82, 6: 0.75 };

export const EXPERIENCE_DELTA: Record<Experience, number> = { beginner: -10, intermediate: 0, advanced: 10 };
export const EXPERIENCE_LEVEL: Record<Experience, 1 | 2 | 3> = { beginner: 1, intermediate: 2, advanced: 3 };

export const MIN_SESSION = 35;
export const MAX_SESSION = 100;

export const SPLITS: Record<number, Focus[]> = {
  2: ['full-lower', 'full-upper'],
  3: ['full-lower', 'full-upper', 'full-power'],
  4: ['upper', 'lower', 'upper', 'lower'],
  5: ['upper', 'lower', 'conditioning', 'upper', 'lower'],
  6: ['push', 'pull', 'legs', 'push', 'pull', 'legs'],
};

export const FOCUS_LABEL: Record<Focus, string> = {
  'full-lower': 'Full body · lower emphasis',
  'full-upper': 'Full body · upper emphasis',
  'full-power': 'Full body · power',
  upper: 'Upper body',
  lower: 'Lower body',
  push: 'Push',
  pull: 'Pull',
  legs: 'Legs',
  conditioning: 'Conditioning & mobility',
};

/** Strength slots by priority; index 0 is the main lift. Variant B used for the 2nd occurrence. */
export const STRENGTH_SLOTS: Record<Focus, [Pattern[], Pattern[]]> = {
  'full-lower': [
    ['squat', 'h-pull', 'hinge', 'h-push', 'single-leg', 'core-anti-rot', 'shoulder-health', 'calves'],
    ['squat', 'h-pull', 'hinge', 'h-push', 'single-leg', 'core-anti-rot', 'shoulder-health', 'calves'],
  ],
  'full-upper': [
    ['h-push', 'v-pull', 'hinge', 'v-push', 'single-leg', 'core-anti-ext', 'shoulder-health', 'arms-flex', 'arms-ext'],
    ['h-push', 'v-pull', 'hinge', 'v-push', 'single-leg', 'core-anti-ext', 'shoulder-health', 'arms-flex', 'arms-ext'],
  ],
  'full-power': [
    ['hinge', 'v-push', 'h-pull', 'single-leg', 'core-flex', 'carry', 'lateral-raise'],
    ['hinge', 'v-push', 'h-pull', 'single-leg', 'core-flex', 'carry', 'lateral-raise'],
  ],
  upper: [
    ['h-push', 'v-pull', 'v-push', 'h-pull', 'shoulder-health', 'lateral-raise', 'arms-ext', 'arms-flex', 'forearm-antagonist'],
    ['v-push', 'h-pull', 'h-push', 'v-pull', 'shoulder-health', 'lateral-raise', 'arms-flex', 'arms-ext', 'forearm-antagonist'],
  ],
  lower: [
    ['squat', 'hinge', 'single-leg', 'knee-flex', 'core-anti-ext', 'calves', 'carry'],
    ['hinge', 'single-leg', 'squat', 'knee-ext', 'core-anti-rot', 'calves', 'core-flex'],
  ],
  push: [
    ['h-push', 'v-push', 'h-push', 'lateral-raise', 'arms-ext', 'shoulder-health', 'core-anti-ext'],
    ['v-push', 'h-push', 'h-push', 'lateral-raise', 'arms-ext', 'shoulder-health', 'core-anti-rot'],
  ],
  pull: [
    ['v-pull', 'h-pull', 'hinge', 'shoulder-health', 'arms-flex', 'core-flex', 'forearm-antagonist'],
    ['h-pull', 'v-pull', 'hinge', 'shoulder-health', 'arms-flex', 'core-flex', 'forearm-antagonist'],
  ],
  legs: [
    ['squat', 'hinge', 'single-leg', 'knee-flex', 'knee-ext', 'calves', 'core-anti-rot'],
    ['hinge', 'squat', 'single-leg', 'knee-ext', 'knee-flex', 'calves', 'core-anti-ext'],
  ],
  conditioning: [
    ['single-leg', 'carry', 'core-anti-ext', 'shoulder-health', 'core-anti-rot'],
    ['single-leg', 'carry', 'core-anti-rot', 'shoulder-health', 'core-anti-ext'],
  ],
};

export const POWER_PATTERNS: Record<Focus, Pattern[]> = {
  'full-lower': ['jump', 'throw'],
  'full-upper': ['upper-plyo', 'jump'],
  'full-power': ['jump', 'ballistic', 'throw', 'upper-plyo'],
  upper: ['upper-plyo', 'throw'],
  lower: ['jump', 'ballistic'],
  push: ['throw', 'upper-plyo'],
  pull: ['upper-plyo', 'ballistic'],
  legs: ['jump', 'ballistic'],
  conditioning: ['ballistic', 'throw', 'jump'],
};

export type Region = 'hips' | 'shoulders' | 'thoracic' | 'wrists' | 'ankles' | 'spine';

export const FOCUS_REGIONS: Record<Focus, Region[]> = {
  'full-lower': ['hips', 'ankles', 'thoracic', 'shoulders'],
  'full-upper': ['shoulders', 'thoracic', 'hips', 'wrists'],
  'full-power': ['hips', 'shoulders', 'ankles', 'thoracic'],
  upper: ['shoulders', 'thoracic', 'wrists'],
  lower: ['hips', 'ankles', 'spine'],
  push: ['shoulders', 'thoracic', 'wrists'],
  pull: ['shoulders', 'thoracic', 'wrists', 'spine'],
  legs: ['hips', 'ankles', 'spine'],
  conditioning: ['hips', 'shoulders', 'thoracic', 'ankles', 'wrists'],
};

/** Session-type adjustment of the goal mix. */
export const FOCUS_MIX: Partial<Record<Focus, Partial<Mix>>> = {
  'full-power': { power: 1.6, cardio: 1.1 },
  conditioning: { power: 1.4, strength: 0.4, mobility: 1.4, cardio: 1.8 },
};

/** Light accessory dosing for prehab-type slots. */
export const LIGHT_PATTERNS: Pattern[] = ['shoulder-health', 'forearm-antagonist', 'calves', 'core-anti-ext', 'core-anti-rot', 'core-flex', 'carry'];
