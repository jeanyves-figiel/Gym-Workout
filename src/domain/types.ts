export type Goal =
  | 'balanced' // strength + definition + mobility + cardio + power (default mix)
  | 'build' // muscle definition / hypertrophy
  | 'strength' // max strength
  | 'climbing' // climbing performance support
  | 'endurance' // aerobic capacity
  | 'athletic'; // explosiveness / power

export type Experience = 'beginner' | 'intermediate' | 'advanced';

export type Muscle =
  | 'chest'
  | 'front-delts'
  | 'side-delts'
  | 'rear-delts'
  | 'rotator-cuff'
  | 'triceps'
  | 'biceps'
  | 'forearms'
  | 'lats'
  | 'upper-back'
  | 'lower-back'
  | 'abs'
  | 'obliques'
  | 'glutes'
  | 'hip-flexors'
  | 'adductors'
  | 'quads'
  | 'hamstrings'
  | 'calves';

export type Equipment =
  | 'barbell'
  | 'trap-bar'
  | 'rack'
  | 'bench'
  | 'dumbbells'
  | 'kettlebells'
  | 'cable'
  | 'smith'
  | 'leg-press'
  | 'hack-squat'
  | 'leg-curl'
  | 'leg-extension'
  | 'lat-pulldown'
  | 'seated-row'
  | 'chest-press'
  | 'pec-deck'
  | 'hip-thrust-machine'
  | 'back-extension'
  | 'pullup-bar'
  | 'dip-station'
  | 'rings'
  | 'trx'
  | 'landmine'
  | 'plyo-box'
  | 'med-ball'
  | 'slam-ball'
  | 'sled'
  | 'battle-rope'
  | 'ab-wheel'
  | 'bands'
  | 'foam-roller'
  | 'mat'
  | 'treadmill'
  | 'bike'
  | 'air-bike'
  | 'rower'
  | 'ski-erg'
  | 'stair-climber'
  | 'elliptical';

export type Category = 'warmup' | 'power' | 'strength' | 'mobility' | 'cardio' | 'stretch';

export type Pattern =
  // strength
  | 'squat'
  | 'hinge'
  | 'single-leg'
  | 'h-push'
  | 'v-push'
  | 'h-pull'
  | 'v-pull'
  | 'core-anti-ext'
  | 'core-anti-rot'
  | 'core-flex'
  | 'carry'
  | 'arms-flex'
  | 'arms-ext'
  | 'shoulder-health' // rotator cuff / scapular / rear delt
  | 'calves'
  | 'forearm-antagonist'
  | 'knee-flex'
  | 'knee-ext'
  | 'lateral-raise'
  // power
  | 'jump'
  | 'throw'
  | 'ballistic'
  | 'upper-plyo'
  // other
  | 'general';

export type Level = 1 | 2 | 3;

export interface Exercise {
  id: string;
  name: string;
  category: Category;
  pattern: Pattern;
  primary: Muscle[];
  secondary?: Muscle[];
  /** All required. Empty = bodyweight. */
  equipment: Equipment[];
  /** Minimum experience: 1 beginner, 2 intermediate, 3 advanced. */
  level: Level;
  unilateral?: boolean;
  /** Seconds per rep (incl. tempo) for time estimates. */
  secPerRep?: number;
  /** Uses heavy grip; trimmed for climbers to spare fingers/forearms. */
  gripHeavy?: boolean;
  /** Main compound lift eligible as first exercise of a strength block. */
  main?: boolean;
  /** Mobility/stretch: hold or reps prescription unit. */
  unit?: 'reps' | 'sec';
  /** Mobility focus regions, e.g. for climber hips/shoulders. */
  regions?: Array<'hips' | 'shoulders' | 'thoracic' | 'wrists' | 'ankles' | 'spine'>;
  cues: string[];
}

export interface Profile {
  name?: string;
  goal: Goal;
  sessionsPerWeek: 2 | 3 | 4 | 5 | 6;
  experience: Experience;
  /** Outdoor/indoor climbing sessions per week (fatigue + antagonist logic). */
  climbingDaysPerWeek: number;
  /** Optional hard cap on session minutes. */
  maxSessionMinutes?: number;
  /** Equipment available at the gym. */
  equipment: Equipment[];
}

export type Focus = 'full-lower' | 'full-upper' | 'full-power' | 'upper' | 'lower' | 'push' | 'pull' | 'legs' | 'conditioning';

export type BlockKind = 'warmup' | 'power' | 'strength' | 'mobility' | 'cardio' | 'cooldown';

export interface Prescription {
  sets: number;
  /** e.g. "5", "8–10", "30 s", "20 min" */
  reps: string;
  restSec: number;
  /** Target effort, e.g. "RPE 8" or "Zone 2". */
  intensity?: string;
  note?: string;
}

export interface PlannedExercise {
  uid: string;
  exerciseId: string;
  slot: Pattern;
  prescription: Prescription;
  /** Mobility drill done during rest of this exercise. */
  pairedWith?: string;
  /** uid of the exercise in whose rest this one is performed. */
  supersetWith?: string;
  estSec: number;
}

export interface Block {
  kind: BlockKind;
  title: string;
  targetMin: number;
  items: PlannedExercise[];
  note?: string;
}

export interface Session {
  id: string;
  index: number;
  focus: Focus;
  title: string;
  targetMin: number;
  estMin: number;
  blocks: Block[];
}

export interface WeekPlan {
  week: number; // 1..4 within mesocycle
  deload: boolean;
  seed: number;
  sessionMinutes: number;
  sessions: Session[];
}

export interface SetLog {
  date: string; // ISO
  exerciseId: string;
  weightKg?: number;
  reps?: number;
}
