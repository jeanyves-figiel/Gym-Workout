import { z } from 'zod';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { assertClean, memberNotHiddenSql } from './moderation.ts';

/**
 * Week challenge deck + member weeks (#748, design C from `week-challenges/proposals.png`). The server owns the
 * week's WOD: a deck of 60 kit-free WODs in 4 formats, shuffled per year so none repeats inside a year. The last
 * ISO week of each month is a member week: the approved member suggestion with the most votes runs (deck if none).
 * Suggestions use moves from one kit-free list with sane reps (the automatic Coach check), then the owner approves
 * them (`admin.ts challenge-approve`).
 */

export const CHALLENGE_FORMATS = ['amrap', 'emom', 'fortime', 'tabata'] as const;
export type ChallengeFormat = (typeof CHALLENGE_FORMATS)[number];
export const CHALLENGE_TIERS = ['easy', 'rx', 'beast'] as const;
export type ChallengeTier = (typeof CHALLENGE_TIERS)[number];

/** Kit-free moves a WOD may use (deck and suggestions); counted in reps. */
export const CHALLENGE_MOVES = [
  'air squats', 'bear crawl steps', 'bicycle crunches', 'broad jumps', 'burpee broad jumps', 'burpees', 'chair dips',
  'cossack squats', 'crab toe touches', 'decline push-ups', 'diamond push-ups', 'flutter kicks', 'frog jumps',
  'glute bridges', 'hand-release push-ups', 'high knees', 'hollow rocks', 'inchworms', 'jump squats', 'jumping jacks',
  'jumping lunges', 'lateral lunges', 'leg raises', 'lunges', 'mountain climbers', 'pike push-ups',
  'plank shoulder taps', 'pulse squats', 'push-ups', 'reverse lunges', 'russian twists', 'single-leg glute bridges',
  'sit-ups', 'skater jumps', 'sprawls', 'squat thrusts', 'star jumps', 'sumo squats', 'superman lifts', 'toe touches',
  'tuck jumps', 'tuck-ups', 'v-ups', 'walking lunges', 'wide push-ups',
] as const;

export interface ChallengeWod {
  name: string;
  format: ChallengeFormat;
  /** AMRAP / For time: the cap; EMOM: one minute per round; Tabata: 4′ per move (8 × 20″ / 10″). */
  minutes: number;
  /** "12 air squats"; Tabata: the move only. */
  moves: string[];
}

type Row = [string, ChallengeFormat, number, string];
// prettier-ignore
const ROWS: Row[] = [
  ['Monkey Mile', 'amrap', 12, '10 burpees|15 air squats|20 mountain climbers'],
  ['Banana Split', 'amrap', 12, '8 push-ups|12 lunges|16 sit-ups'],
  ['Jungle Gym', 'amrap', 12, '5 burpees|10 jump squats|15 v-ups'],
  ['Silverback', 'amrap', 15, '10 push-ups|20 walking lunges|20 plank shoulder taps'],
  ['Vine Swing', 'amrap', 12, '12 jumping lunges|12 pike push-ups|12 tuck-ups'],
  ['Canopy Climb', 'amrap', 12, '6 burpee broad jumps|12 air squats|18 bicycle crunches'],
  ['Treetop', 'amrap', 14, '10 skater jumps|10 hand-release push-ups|10 hollow rocks'],
  ['Big Ape', 'amrap', 12, '7 burpees|14 jump squats|21 flutter kicks'],
  ['Mango Rush', 'amrap', 10, '5 sprawls|10 jumping jacks|15 sumo squats'],
  ['Howler', 'amrap', 16, '8 tuck jumps|16 reverse lunges|24 high knees'],
  ['Baboon Burner', 'amrap', 12, '6 squat thrusts|12 wide push-ups|18 russian twists'],
  ['Lemur Loop', 'amrap', 15, '10 star jumps|10 cossack squats|10 superman lifts'],
  ['Gibbon Glide', 'amrap', 12, '5 inchworms|10 lateral lunges|15 leg raises'],
  ['Orangutan Grind', 'amrap', 18, '10 diamond push-ups|20 glute bridges|30 mountain climbers'],
  ['Coconut Crusher', 'amrap', 12, '9 burpees|12 pulse squats|15 toe touches'],
  ['Mandrill', 'amrap', 14, '6 frog jumps|12 decline push-ups|18 crab toe touches'],
  ['Rainforest Run', 'amrap', 20, '20 high knees|10 push-ups|20 air squats|10 sit-ups'],
  ['Tamarin Twister', 'amrap', 10, '8 broad jumps|12 chair dips|16 bicycle crunches'],
  ['Kong Klimb', 'amrap', 15, '5 burpee broad jumps|10 pike push-ups|15 jump squats|20 flutter kicks'],
  ['Chimp Chaser', 'amrap', 12, '10 bear crawl steps|10 jumping lunges|10 v-ups'],
  ['Swinging Vines', 'amrap', 12, '12 skater jumps|8 hand-release push-ups|12 single-leg glute bridges'],
  ['Spider Monkey', 'amrap', 14, '6 sprawls|12 plank shoulder taps|18 sumo squats'],
  ['Capuchin Combo', 'amrap', 12, '7 tuck jumps|7 push-ups|7 tuck-ups|7 lunges'],
  ['Proboscis', 'amrap', 16, '15 jumping jacks|10 wide push-ups|15 reverse lunges|10 hollow rocks'],
  ['Minute Monkey', 'emom', 12, '12 air squats|8 push-ups|15 sit-ups'],
  ['Banana Clock', 'emom', 10, '6 burpees|12 jumping lunges'],
  ['Every Branch', 'emom', 14, '10 jump squats|10 hand-release push-ups'],
  ['Tick Tock Troop', 'emom', 12, '15 mountain climbers|10 sumo squats|8 v-ups'],
  ['Hour of the Ape', 'emom', 16, '5 burpee broad jumps|12 plank shoulder taps|10 lunges|10 hollow rocks'],
  ['Jungle Metronome', 'emom', 10, '8 squat thrusts|20 high knees'],
  ['Vine Timer', 'emom', 12, '10 skater jumps|8 pike push-ups|12 russian twists'],
  ['Primate Pulse', 'emom', 14, '6 tuck jumps|10 diamond push-ups'],
  ['Monsoon Minutes', 'emom', 12, '12 reverse lunges|12 superman lifts|12 flutter kicks'],
  ['Clockwork Kong', 'emom', 16, '7 sprawls|14 cossack squats|10 wide push-ups|14 bicycle crunches'],
  ['Gorilla Gears', 'emom', 10, '10 star jumps|12 glute bridges'],
  ['Sunrise Swing', 'emom', 12, '10 jumping jacks|10 inchworms|10 leg raises'],
  ['Pendulum', 'emom', 14, '8 burpees|16 lateral lunges'],
  ['Night Howl', 'emom', 12, '6 frog jumps|10 chair dips|20 crab toe touches'],
  ['Banana Chipper', 'fortime', 15, '50 air squats|40 sit-ups|30 push-ups|20 burpees'],
  ['Jungle Ladder', 'fortime', 12, '10 burpees|20 jump squats|30 mountain climbers|40 jumping jacks'],
  ['Ape Escape', 'fortime', 18, '100 high knees|50 lunges|25 push-ups|50 v-ups'],
  ['Grand Canopy', 'fortime', 20, '30 burpee broad jumps|60 air squats|90 flutter kicks'],
  ['King of the Swingers', 'fortime', 15, '40 skater jumps|30 hand-release push-ups|20 tuck-ups|10 burpees'],
  ['Kilimanjaro', 'fortime', 20, '100 jumping jacks|80 sumo squats|60 bicycle crunches|40 pike push-ups'],
  ['Hundred Bananas', 'fortime', 12, '100 air squats'],
  ['Troop Trek', 'fortime', 15, '50 walking lunges|50 plank shoulder taps|50 glute bridges'],
  ['Tree Sprint', 'fortime', 10, '20 tuck jumps|30 push-ups|40 sit-ups'],
  ['Long Vine', 'fortime', 20, '50 burpees|50 jump squats|50 hollow rocks'],
  ['Simian Six', 'fortime', 14, '60 mountain climbers|50 reverse lunges|40 russian twists|30 wide push-ups|20 sprawls|10 tuck jumps'],
  ['Fruit Run', 'fortime', 12, '30 star jumps|30 cossack squats|30 superman lifts'],
  ['Tabata Tree', 'tabata', 12, 'jump squats|push-ups|hollow rocks'],
  ['Twenty-Ten Troop', 'tabata', 8, 'burpees|mountain climbers'],
  ['Howler Intervals', 'tabata', 12, 'jumping lunges|plank shoulder taps|v-ups'],
  ['Jungle Fever', 'tabata', 16, 'high knees|air squats|wide push-ups|flutter kicks'],
  ['Primate Pulses', 'tabata', 8, 'skater jumps|sit-ups'],
  ['Banana Bursts', 'tabata', 12, 'tuck jumps|diamond push-ups|bicycle crunches'],
  ['Storm Season', 'tabata', 12, 'sprawls|sumo squats|russian twists'],
  ['Vine Breaker', 'tabata', 8, 'star jumps|reverse lunges'],
  ['Monkey Mayhem', 'tabata', 16, 'burpees|jump squats|hand-release push-ups|leg raises'],
  ['Last Banana', 'tabata', 12, 'jumping jacks|glute bridges|superman lifts'],
];

export const CHALLENGE_DECK: ChallengeWod[] = ROWS.map(([name, format, minutes, moves]) => ({ name, format, minutes, moves: moves.split('|') }));

// ───────────── weeks

const parseWeek = (w: string) => ({ year: Number(w.slice(0, 4)), n: Number(w.slice(6)) });

/** Thursday of ISO week `w` (UTC): it decides the week's year and month. */
export const thursdayOf = (w: string) => {
  const { year, n } = parseWeek(w);
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const monday1 = Date.UTC(year, 0, 4 - ((jan4.getUTCDay() || 7) - 1));
  return new Date(monday1 + ((n - 1) * 7 + 3) * 86_400_000);
};

export const addWeeks = (w: string, k: number, isoWeek: (d: Date) => string) => isoWeek(new Date(thursdayOf(w).getTime() + k * 7 * 86_400_000));

/** Last ISO week of a month: the next week's Thursday is in another month. */
export const isMemberWeek = (w: string, isoWeek: (d: Date) => string) =>
  thursdayOf(w).getUTCMonth() !== thursdayOf(addWeeks(w, 1, isoWeek)).getUTCMonth();

/** Seeded Fisher–Yates of the deck for `year`: week n gets card n of the year's order, so none repeats in a year. */
const orderCache = new Map<number, number[]>();
export const deckOrder = (year: number) => {
  const hit = orderCache.get(year);
  if (hit) return hit;
  let s = (year * 2654435761) >>> 0;
  const rand = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
  const order = CHALLENGE_DECK.map((_, i) => i);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    const t = order[i]!;
    order[i] = order[j]!;
    order[j] = t;
  }
  orderCache.set(year, order);
  return order;
};

/** The deck card of week `w`, 1-based, and its WOD. */
export const deckWod = (w: string) => {
  const { year, n } = parseWeek(w);
  const order = deckOrder(year);
  const card = (n - 1) % order.length;
  return { card: card + 1, wod: CHALLENGE_DECK[order[card]!]! };
};

// ───────────── scores

/**
 * One number, higher is better: tier first (Beast above Rx above Easy), then AMRAP / EMOM rounds + reps, Tabata
 * reps, For time finishers by time left under the cap (above anyone who didn't finish, ranked by reps).
 */
export const challengeScore = (wod: ChallengeWod, tier: ChallengeTier, s: { rounds: number; reps: number; seconds: number | null }) => {
  const base =
    wod.format === 'fortime'
      ? s.seconds != null && s.seconds > 0
        ? 100_000 + Math.max(0, wod.minutes * 60 - s.seconds)
        : s.reps
      : wod.format === 'tabata'
        ? s.reps
        : s.rounds * 1000 + s.reps;
  return CHALLENGE_TIERS.indexOf(tier) * 10_000_000 + base;
};

// ───────────── suggestions

const MINUTES: Record<ChallengeFormat, [number, number]> = { amrap: [5, 20], emom: [6, 20], fortime: [5, 25], tabata: [4, 20] };
const MAX_REPS: Record<ChallengeFormat, number> = { amrap: 50, emom: 30, fortime: 100, tabata: 0 };
/** Pending suggestions per member. */
export const MAX_PENDING_SUGGESTIONS = 3;
/** Finalists a member week's vote shows. */
export const FINALISTS = 3;

const moveName = (m: string) => m.replace(/^\d+\s+/, '').trim().toLowerCase();

export const suggestionBody = z.object({
  name: z.string().trim().min(2).max(32),
  format: z.enum(CHALLENGE_FORMATS),
  minutes: z.number().int().min(4).max(25),
  moves: z.array(z.string().trim().min(2).max(40)).min(2).max(5),
});

/** The automatic Coach check: moves from the kit-free list, sane reps, a time that fits the format. */
export const checkSuggestion = (b: z.infer<typeof suggestionBody>): ChallengeWod => {
  assertClean(b.name);
  const [lo, hi] = MINUTES[b.format];
  if (b.minutes < lo || b.minutes > hi) throw new ApiError(400, 'challenge_unsafe', `${b.format.toUpperCase()} runs ${lo}–${hi} minutes.`);
  const moves = b.moves.map((m) => {
    const name = moveName(m);
    if (!(CHALLENGE_MOVES as readonly string[]).includes(name)) throw new ApiError(400, 'challenge_unsafe', `"${m}" isn't on the move list.`);
    if (b.format === 'tabata') return name;
    const reps = Number(/^(\d+)\s/.exec(m)?.[1]);
    if (!reps || reps > MAX_REPS[b.format]) throw new ApiError(400, 'challenge_unsafe', `Reps for ${name}: 1–${MAX_REPS[b.format]}.`);
    return `${reps} ${name}`;
  });
  if (new Set(moves.map(moveName)).size !== moves.length) throw new ApiError(400, 'challenge_unsafe', 'Each move once.');
  // Tabata: 4′ per move.
  const minutes = b.format === 'tabata' ? moves.length * 4 : b.minutes;
  return { name: b.name, format: b.format, minutes, moves };
};

export type SuggestionRow = {
  id: string;
  user_id: string;
  name: string;
  format: ChallengeFormat;
  minutes: number;
  moves: string;
  status: 'pending' | 'approved' | 'rejected';
  week: string | null;
  created_at: string;
  reviewed_at: string | null;
};

export const suggestionWod = (s: Pick<SuggestionRow, 'name' | 'format' | 'minutes' | 'moves'>): ChallengeWod => ({
  name: s.name,
  format: s.format,
  minutes: s.minutes,
  moves: JSON.parse(s.moves) as string[],
});

/** Approved, not run yet, author not hidden: oldest approvals first. */
export const finalists = (db: DB) =>
  db
    .prepare(
      `SELECT s.*, cp.nickname FROM community_challenge_suggestions s JOIN community_profiles cp ON cp.user_id = s.user_id
       WHERE s.status = 'approved' AND s.week IS NULL AND ${memberNotHiddenSql('s.user_id')}
       ORDER BY s.reviewed_at, s.created_at LIMIT ?`,
    )
    .all(FINALISTS) as (SuggestionRow & { nickname: string })[];

/** Owner review (`admin.ts`). */
export const reviewSuggestion = (db: DB, id: string, status: 'approved' | 'rejected', at: Date) =>
  db.prepare("UPDATE community_challenge_suggestions SET status = ?, reviewed_at = ? WHERE id = ? AND status = 'pending'").run(status, at.toISOString(), id).changes > 0;

export const pendingSuggestions = (db: DB) =>
  db
    .prepare(
      `SELECT s.id, s.name, s.format, s.minutes, s.moves, s.created_at, cp.nickname FROM community_challenge_suggestions s
       LEFT JOIN community_profiles cp ON cp.user_id = s.user_id WHERE s.status = 'pending' ORDER BY s.created_at`,
    )
    .all() as { id: string; name: string; format: string; minutes: number; moves: string; created_at: string; nickname: string | null }[];
