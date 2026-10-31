import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS, CACHED, tracked } from './models.ts';

/**
 * Workout chat (#381): the member says what they want today ("45 min, legs, sore shoulder") and Coach Monkey
 * answers with a short line plus generator settings. The app's own engine builds the workout from those settings,
 * so only known exercises that fit the member's gym ever come back. The model never sees an account id or email.
 */

export const MUSCLE_GROUPS = ['shoulders', 'chest', 'arms', 'back', 'core', 'hips', 'legs'] as const;
export const REST_STYLES = ['long', 'standard', 'short'] as const;
export const GROUPINGS = ['straight', 'supersets', 'circuits'] as const;
/** Screens Coach can send the member to (#412); 'exercise' also needs the exercise name. */
export const OPEN_TARGETS = ['progress', 'calendar', 'explore', 'fuel', 'settings', 'exercise'] as const;
/** Train around pain (#870): where it hurts, which side, how bad. The app's engine picks the swaps. */
export const PAIN_AREAS = ['neck', 'shoulder', 'elbow', 'wrist', 'lower-back', 'hip', 'knee', 'ankle'] as const;
export const PAIN_SIDES = ['left', 'right', 'both'] as const;
export const PAIN_LEVELS = ['mild', 'loaded', 'sharp'] as const;
/** Tape sites Coach can log (#1000), as the app keys them (GirthSite). */
export const GIRTH_SITES = ['neck', 'shoulders', 'chest', 'waist', 'hips', 'upperArm', 'forearm', 'thigh', 'calf'] as const;
export const GIRTH_SIDES = ['left', 'right', 'none'] as const;
/**
 * What Coach may do for the member (#999), the whole allowlist. Logs (water, food, mood) are done at once with Undo;
 * plan changes (move, skip, swap) wait for the member's tap; two or more come as one checklist. Never account,
 * payment, deleting data, community posts, sharing or privacy settings: those have no kind here.
 */
export const DO_KINDS = ['water', 'food', 'mood', 'move', 'skip', 'swap', 'done', 'reminder', 'voice'] as const;
/** voice: when Coach reads answers aloud, as the app's Ask Coach setting. */
export const DO_VOICE = ['whenTalking', 'always', 'never'] as const;
export const DO_MEALS = ['breakfast', 'lunch', 'dinner', 'snack'] as const;
/** Most actions in one answer (#999). */
export const MAX_DO = 5;

export interface ChatTurn {
  role: 'member' | 'coach';
  text: string;
}

/** What the app knows about the member, sent with each message (no identifiers). */
export interface ChatContext {
  goal?: string;
  level?: string;
  sessionMinutes?: number;
  equipment?: string[];
  readiness?: string;
  todayPlanned?: string;
  method?: string;
  /** Where the member asked from (#412): 'train', 'exercise', 'progress', 'calendar', … */
  screen?: string;
  /** What that screen shows: an exercise name, a chart and its numbers, a calendar day. */
  focus?: string;
  /** The member's pronouns (#415), e.g. "she/her"; unset = neutral wording. */
  pronouns?: string;
  /** What the member likes to be called (#415): a first name, "Champ", "Queen"… */
  callName?: string;
  /** What the coach remembers about the member (#495): goal, likes, the member's own notes. */
  memory?: string[];
  /** Exercise names Coach may suggest from (#856 freestyle, #934 picker): the app's catalog at the member's level. */
  exercises?: string[];
  /** Today's workout exercises (#999), so Coach can swap one by name. */
  todayExercises?: string[];
  /** Today's weekday, 1 = Monday … 7 = Sunday (#999), for "move it to Saturday". */
  weekday?: number;
}

export interface CoachAction {
  target: (typeof OPEN_TARGETS)[number];
  /** Exercise name when target is 'exercise'. */
  exercise: string | null;
  /** Button label, 2 to 4 words. */
  label: string;
}

export interface CoachWorkout {
  name: string;
  minutes: number;
  groups: (typeof MUSCLE_GROUPS)[number][];
  rest: (typeof REST_STYLES)[number];
  grouping: (typeof GROUPINGS)[number];
  avoidGroups: (typeof MUSCLE_GROUPS)[number][];
  avoidEquipment: string[];
  avoidKeywords: string[];
}

/** A knee-friendly (shoulder-, back-…) plan to offer (#870); the app swaps moves across the plan from its catalog. */
export interface CoachProtect {
  area: (typeof PAIN_AREAS)[number];
  side: (typeof PAIN_SIDES)[number];
  level: (typeof PAIN_LEVELS)[number];
  /** Red flags (swelling, numbness, a fall, pain at rest or at night): the app shows a "see a doctor" line. */
  seeDoctor: boolean;
}

/** Body measurements the member told Coach to save (#1000); the app logs them on today's entry with Undo. */
export interface CoachMeasurement {
  weightKg: number | null;
  bodyFatPct: number | null;
  girths: { site: (typeof GIRTH_SITES)[number]; side: (typeof GIRTH_SIDES)[number]; cm: number }[];
}

/** One thing Coach does for the member (#999); only the fields its kind uses are set, the rest null. */
export interface CoachDo {
  kind: (typeof DO_KINDS)[number];
  /** water: glasses to add, 1 to 10. */
  glasses: number | null;
  /** food: what they ate, in their words ("oats with banana"); the app finds the foods in its catalog. */
  foods: string | null;
  /** food: the meal, else the app's next meal of the day. */
  meal: (typeof DO_MEALS)[number] | null;
  /** mood: 1 drained … 5 amazing. */
  mood: number | null;
  /** move: day to move today's workout to, 1 = Monday … 7 = Sunday. */
  weekday: number | null;
  /** swap: exercise of today's workout to replace, and the one to put in (names). */
  from: string | null;
  to: string | null;
  /** reminder: time of the morning workout reminder, minutes after midnight (0 to 1439). */
  minutes: number | null;
  /** reminder: false turns it off. */
  on: boolean | null;
  /** voice: whenTalking, always or never. */
  value: (typeof DO_VOICE)[number] | null;
}

export interface CoachAnswer {
  reply: string;
  /** Settings for the engine; null while the coach still asks something. */
  workout: CoachWorkout | null;
  /** Optional button that opens a screen (#412). */
  action?: CoachAction | null;
  /** Up to 3 short follow-up questions the member can tap (#412). */
  suggestions?: string[];
  /** Exercises to add right now (#856, freestyle): exact names from the context list, best first. */
  exercises?: string[];
  /** Train around pain (#870): offer a plan that protects this spot; null otherwise. */
  protect?: CoachProtect | null;
  /** Log body measurements (#1000): values in kg, % and cm; null when nothing to log. */
  measurement?: CoachMeasurement | null;
  /** Things to do for the member (#999), checked against DO_KINDS and their limits. */
  doActions?: CoachDo[];
}

/** `photo`: a JPEG of the machine in front of the member (#856), with the last message. */
export type CoachModel = (turns: ChatTurn[], context: ChatContext, photo?: Buffer) => Promise<CoachAnswer>;

/** Most exercises Coach hands back at once (#856). */
export const MAX_EXERCISES = 4;

/** Stands for the member's first name, which stays on the device (#415). */
export const NAME_SLOT = '{name}';

const SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. Members ask you from any screen of the app, by text or by voice: to get a workout for today, or about an exercise, their form, their progress, their plan, recovery or how the app works.

Answering questions (#412):
- "Screen" and "Looking at" below tell you what the member sees. Questions like "why is it down?" or "is this right for me?" are about that.
- Answer in max 3 short sentences, practical, from their data when you have it. Never make up numbers you weren't given.
- action: a button to open a screen when it truly helps ("progress", "calendar", "explore", "fuel", "settings", or "exercise" with the exact exercise name, e.g. a safer alternative). Else null.
- suggestions: up to 3 short follow-up questions the member might tap next (max 5 words each), in their language.
- Food (Fuel, #496): give general pointers on eating around training, using the day's training and the targets in "Looking at" when given (protein, carbs, water, meals). Suggest simple meals. Never prescribe diets, calorie restriction or supplements as treatment; for a medical condition, pregnancy or an eating disorder suggest a doctor or dietitian.
- Freestyle (#856, Screen "freestyle") and the Add exercises picker (#934, Screen "picker"): the member is building a workout, at the gym as they go or picking exercises for one. When they ask what to do, name a muscle, name or describe a machine, or send a photo of one, put up to 4 exercises in "exercises", best first, using exact names from "Exercises in the app" only. For a photo or description, say in the reply which machine it is and one setup tip. workout null. Elsewhere exercises is an empty list.
- Logging body measurements (#1000): when the member tells you their body weight, body fat or a tape measurement to save ("weight is now 66", "log my waist 82", "I'm 145 pounds today"), put it in "measurement": weightKg, bodyFatPct, girths (site, side "left"/"right" for one limb, else "none", cm). Convert pounds and inches. Only values the member gave; a bare weight number is kilos. The app saves it on today's entry at once with an Undo button: the reply confirms in one short line ("Logged: 66 kilos.") and may add one encouraging word about the trend in "Looking at". Never say you can't log it. measurement null when they only ask about it.
- Doing things for the member (#999): you can act, not only advise. Never say "you can do it yourself" or "I can't do that" for anything below; put it in "doActions" instead (one entry per thing, max 5), and the reply says in one short line what you did or will do:
  - water: they drank water ("had 2 glasses") → glasses 1 to 10.
  - food: they ate or drank something to log ("had oats and a banana for breakfast") → foods in their words, meal when they say it.
  - mood: they say how they feel today ("feeling great", "drained") → mood 1 drained, 2 meh, 3 good, 4 great, 5 amazing.
  - move: move today's workout to another day ("move it to Saturday", "do it tomorrow") → weekday 1 Monday to 7 Sunday, using "Today is" below. Never a day before today.
  - skip: skip today's workout ("skip today", "not training today").
  - swap: replace one exercise of today's workout ("swap squats for leg press") → from = exact name from "Today's exercises", to = the exercise they want.
  - done: they did an earlier workout of this week but didn't log it ("I did Tuesday's workout") → weekday of that day, before today. It is logged as planned.
  - reminder: the morning reminder of a workout day ("remind me at 6:30", "stop the workout reminders") → minutes after midnight (6:30 = 390) and on true, or on false to turn it off.
  - voice: whether you read answers aloud ("talk to me", "stop talking", "only when I speak") → value always, never or whenTalking.
  Logs (water, food, mood) are saved at once with Undo, so the reply says "Done" ("Added two glasses."). Move, skip, swap, done, reminder and voice wait for the member's tap on a card, so the reply asks ("Want me to move it to Saturday?"). Only what the member asked for. Fields a kind doesn't use are null.
  You can't do anything else (account, email, password, payment, subscription, deleting data, community posts, sharing, privacy or AI settings). For those say kindly where it is in the app and add the matching "action" button. Never pretend you did something you can't.
- Replies may be read aloud: no lists, no symbols, no emoji, write units in words when short ("kilos", "minutes").

Building a workout: only when the member wants one. Turn what they say into settings for the app's workout generator.
- The generator picks the exercises itself from the member's equipment and level. You never list or invent exercises.
- Make a workout as soon as you can. Ask one short question only when you truly can't guess (for example no hint at all about what to train). Otherwise pick sensible defaults and say which in the reply.
- minutes: total session length the member wants, 15 to 120. Default: their usual session length.
- groups: muscle groups to train. "Full body" = all seven. "Upper" = shoulders, chest, arms, back. "Lower" = hips, legs (+ core). "Push" = chest, shoulders, arms. "Pull" = back, arms.
- avoidGroups: groups that hurt or are sore today (sore shoulder → shoulders; sore knee → legs only if they ask to skip legs, otherwise use avoidKeywords like "lunge", "jump"). Never put a group in both groups and avoidGroups.
- avoidEquipment: equipment ids from their list they don't want or can't use today (busy rack → "rack", no barbell → "barbell").
- avoidKeywords: lowercase words of exercise names to skip ("lunge", "deadlift", "burpee").
- rest: "short" for quick or sweaty sessions, "long" for heavy strength, else "standard".
- grouping: "supersets" or "circuits" when time is short or they want intensity, else "straight".
- When the member asks to change the last workout (shorter, harder, swap something), return the full updated settings.
- Low readiness or tiredness: keep it shorter and lighter, and say so kindly.
- Anything unrelated to training, fitness, health habits or the app: one friendly line steering back to training, workout null.
- Pain that sounds like an injury: suggest seeing a professional and offer a workout that avoids that area.

Training around pain (#870): when the member says a joint or spot hurts (knee, shoulder, lower back, wrist, elbow, hip, ankle, neck):
- If you can't tell how bad it is, ask exactly one short question first ("Sharp, or more of an ache?") with protect null.
- Then set protect: area, side ("both" when unclear or not one-sided), level ("mild" = a niggle, "loaded" = hurts when they load it, "sharp" = sharp or stabbing). The app swaps the risky moves across the whole plan from its own catalog until they say it feels better; in the reply say you'll protect it for the next couple of weeks, never list exercises.
- seeDoctor true for red flags: swelling, numbness or tingling, it gave way, after a fall or a pop, pain at rest or at night, sharp pain that keeps coming back. Then the reply says plainly to see a doctor or physio first.
- You are not a doctor: never diagnose or name an injury, and keep protect null for chest pain, dizziness, head injuries or anything that isn't a joint or muscle (tell them to get medical help).
- workout stays null when you set protect, unless they also asked for today's workout.
- workout null when the member only asks a question.
- reply: plain text, no markdown, in the member's language. name: 2 to 4 words for the workout.`;

const schema = {
  type: 'object',
  properties: {
    reply: { type: 'string' },
    workout: {
      anyOf: [
        { type: 'null' },
        {
          type: 'object',
          properties: {
            name: { type: 'string' },
            minutes: { type: 'integer' },
            groups: { type: 'array', items: { type: 'string', enum: [...MUSCLE_GROUPS] } },
            rest: { type: 'string', enum: [...REST_STYLES] },
            grouping: { type: 'string', enum: [...GROUPINGS] },
            avoidGroups: { type: 'array', items: { type: 'string', enum: [...MUSCLE_GROUPS] } },
            avoidEquipment: { type: 'array', items: { type: 'string' } },
            avoidKeywords: { type: 'array', items: { type: 'string' } },
          },
          required: ['name', 'minutes', 'groups', 'rest', 'grouping', 'avoidGroups', 'avoidEquipment', 'avoidKeywords'],
          additionalProperties: false,
        },
      ],
    },
    action: {
      anyOf: [
        { type: 'null' },
        {
          type: 'object',
          properties: {
            target: { type: 'string', enum: [...OPEN_TARGETS] },
            exercise: { anyOf: [{ type: 'null' }, { type: 'string' }] },
            label: { type: 'string' },
          },
          required: ['target', 'exercise', 'label'],
          additionalProperties: false,
        },
      ],
    },
    suggestions: { type: 'array', items: { type: 'string' } },
    exercises: { type: 'array', items: { type: 'string' } },
    protect: {
      anyOf: [
        { type: 'null' },
        {
          type: 'object',
          properties: {
            area: { type: 'string', enum: [...PAIN_AREAS] },
            side: { type: 'string', enum: [...PAIN_SIDES] },
            level: { type: 'string', enum: [...PAIN_LEVELS] },
            seeDoctor: { type: 'boolean' },
          },
          required: ['area', 'side', 'level', 'seeDoctor'],
          additionalProperties: false,
        },
      ],
    },
    measurement: {
      anyOf: [
        { type: 'null' },
        {
          type: 'object',
          properties: {
            weightKg: { anyOf: [{ type: 'null' }, { type: 'number' }] },
            bodyFatPct: { anyOf: [{ type: 'null' }, { type: 'number' }] },
            girths: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  site: { type: 'string', enum: [...GIRTH_SITES] },
                  side: { type: 'string', enum: [...GIRTH_SIDES] },
                  cm: { type: 'number' },
                },
                required: ['site', 'side', 'cm'],
                additionalProperties: false,
              },
            },
          },
          required: ['weightKg', 'bodyFatPct', 'girths'],
          additionalProperties: false,
        },
      ],
    },
    doActions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: [...DO_KINDS] },
          glasses: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
          foods: { anyOf: [{ type: 'null' }, { type: 'string' }] },
          meal: { anyOf: [{ type: 'null' }, { type: 'string', enum: [...DO_MEALS] }] },
          mood: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
          weekday: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
          from: { anyOf: [{ type: 'null' }, { type: 'string' }] },
          to: { anyOf: [{ type: 'null' }, { type: 'string' }] },
          minutes: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
          on: { anyOf: [{ type: 'null' }, { type: 'boolean' }] },
          value: { anyOf: [{ type: 'null' }, { type: 'string', enum: [...DO_VOICE] }] },
        },
        required: ['kind', 'glasses', 'foods', 'meal', 'mood', 'weekday', 'from', 'to', 'minutes', 'on', 'value'],
        additionalProperties: false,
      },
    },
  },
  required: ['reply', 'workout', 'action', 'suggestions', 'exercises', 'protect', 'measurement', 'doActions'],
  additionalProperties: false,
} as const;

export const describeMember = (c: ChatContext) =>
  [
    c.goal && `Goal: ${c.goal}`,
    c.level && `Level: ${c.level}`,
    c.method && `Training method: ${c.method}`,
    c.sessionMinutes && `Usual session: ${c.sessionMinutes} min`,
    c.readiness && `Readiness today: ${c.readiness}`,
    c.todayPlanned && `Planned today: ${c.todayPlanned}`,
    c.equipment?.length && `Equipment ids: ${c.equipment.join(', ')}`,
    c.screen && `Screen: ${c.screen}`,
    c.focus && `Looking at: ${c.focus}`,
    c.pronouns && `Pronouns: ${c.pronouns} (when you refer to the member, use these; talk to them as "you")`,
    !c.pronouns && 'Pronouns: not set (use neutral wording; never guess a gender)',
    c.callName === NAME_SLOT && `Likes to be called by first name: write ${NAME_SLOT} where you use it, the app fills it in (now and then, not in every reply)`,
    c.callName && c.callName !== NAME_SLOT && `Likes to be called: ${c.callName} (use it now and then, not in every reply)`,
    c.weekday && c.weekday >= 1 && c.weekday <= 7 && `Today is: ${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][c.weekday - 1]} (${c.weekday})`,
    c.todayExercises?.length && `Today's exercises (for swap "from"): ${c.todayExercises.join('; ')}`,
    c.exercises?.length && `Exercises in the app (use these exact names in "exercises"): ${c.exercises.join('; ')}`,
    c.memory?.length && `What you remember about the member (use it when it helps, never recite the list): ${c.memory.join('; ')}`,
  ]
    .filter(Boolean)
    .join('\n');

/** Keeps only settings the app can use; drops unknown values instead of failing the chat. */
const cleanAction = (a: CoachAction | null | undefined): CoachAction | null => {
  if (!a || !OPEN_TARGETS.includes(a.target)) return null;
  const exercise = a.exercise?.trim().slice(0, 60) || null;
  if (a.target === 'exercise' && !exercise) return null;
  const label = a.label?.trim().slice(0, 30) || (exercise ? `Open ${exercise}`.slice(0, 30) : 'Open');
  return { target: a.target, exercise: a.target === 'exercise' ? exercise : null, label };
};

/** Exercises only from the list the app sent, spelled as the app spells them (#856); none without a list. */
const cleanExercises = (names: string[] | undefined, context: ChatContext): string[] => {
  if (!context.exercises?.length) return [];
  const known = new Map(context.exercises.map((n) => [n.trim().toLowerCase(), n]));
  const out = (names ?? []).flatMap((n) => {
    const hit = known.get(n.trim().toLowerCase());
    return hit ? [hit] : [];
  });
  return [...new Set(out)].slice(0, MAX_EXERCISES);
};

const cleanProtect = (p: CoachProtect | null | undefined): CoachProtect | null => {
  if (!p || !PAIN_AREAS.includes(p.area)) return null;
  return {
    area: p.area,
    side: PAIN_SIDES.includes(p.side) ? p.side : 'both',
    level: PAIN_LEVELS.includes(p.level) ? p.level : 'loaded',
    seeDoctor: p.seeDoctor === true,
  };
};

const inRange = (v: number | null | undefined, lo: number, hi: number) =>
  typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi ? Math.round(v * 10) / 10 : null;

/** Same ranges as the measurements API (#185); anything outside is dropped, nothing left = null (#1000). */
const cleanMeasurement = (m: CoachMeasurement | null | undefined): CoachMeasurement | null => {
  if (!m) return null;
  const seen = new Set<string>();
  const girths = (m.girths ?? []).flatMap((g) => {
    const cm = inRange(g.cm, 5, 300);
    if (cm === null || !GIRTH_SITES.includes(g.site)) return [];
    const side = GIRTH_SIDES.includes(g.side) ? g.side : 'none';
    const key = `${g.site}:${side}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ site: g.site, side, cm }];
  }).slice(0, 18);
  const out = { weightKg: inRange(m.weightKg, 20, 400), bodyFatPct: inRange(m.bodyFatPct, 2, 75), girths };
  return out.weightKg === null && out.bodyFatPct === null && girths.length === 0 ? null : out;
};

const text = (v: string | null | undefined, max: number) => (typeof v === 'string' ? v.trim().slice(0, max) : '') || null;
const int = (v: number | null | undefined, lo: number, hi: number) =>
  typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi ? v : null;

/**
 * The allowlist (#999): unknown kinds, missing or out-of-range values are dropped, never guessed. A move goes only to
 * today or later; a swap's "from" must be one of today's exercises when the app sent them. One skip, one move at most.
 */
export const cleanDo = (list: CoachDo[] | null | undefined, context: ChatContext): CoachDo[] => {
  const none = { glasses: null, foods: null, meal: null, mood: null, weekday: null, from: null, to: null, minutes: null, on: null, value: null };
  const today = int(context.weekday, 1, 7);
  const todays = new Map((context.todayExercises ?? []).map((n) => [n.trim().toLowerCase(), n]));
  const out: CoachDo[] = [];
  for (const d of Array.isArray(list) ? list : []) {
    if (!d || !DO_KINDS.includes(d.kind)) continue;
    let c: CoachDo | null = null;
    switch (d.kind) {
      case 'water': {
        const glasses = int(d.glasses, 1, 10);
        if (glasses) c = { ...none, kind: 'water', glasses };
        break;
      }
      case 'food': {
        const foods = text(d.foods, 120);
        if (foods) c = { ...none, kind: 'food', foods, meal: d.meal && DO_MEALS.includes(d.meal) ? d.meal : null };
        break;
      }
      case 'mood': {
        const mood = int(d.mood, 1, 5);
        if (mood) c = { ...none, kind: 'mood', mood };
        break;
      }
      case 'move': {
        const weekday = int(d.weekday, 1, 7);
        if (weekday && (!today || (weekday > today))) c = { ...none, kind: 'move', weekday };
        break;
      }
      case 'skip':
        c = { ...none, kind: 'skip' };
        break;
      case 'swap': {
        const from = text(d.from, 60);
        const to = text(d.to, 60);
        const known = from && todays.size ? todays.get(from.toLowerCase()) ?? null : from;
        if (known && to && known.toLowerCase() !== to.toLowerCase()) c = { ...none, kind: 'swap', from: known, to };
        break;
      }
      case 'done': {
        const weekday = int(d.weekday, 1, 7);
        if (weekday && (!today || weekday < today)) c = { ...none, kind: 'done', weekday };
        break;
      }
      case 'reminder': {
        if (d.on === false) c = { ...none, kind: 'reminder', on: false };
        else {
          const minutes = int(d.minutes, 0, 1439);
          if (minutes !== null) c = { ...none, kind: 'reminder', on: true, minutes };
        }
        break;
      }
      case 'voice':
        if (d.value && DO_VOICE.includes(d.value)) c = { ...none, kind: 'voice', value: d.value };
        break;
    }
    if (!c) continue;
    // Skip and move both change today's workout: only the first of them counts. One reminder, one voice, one per day logged.
    if ((c.kind === 'skip' || c.kind === 'move') && out.some((o) => o.kind === 'skip' || o.kind === 'move')) continue;
    if ((c.kind === 'reminder' || c.kind === 'voice') && out.some((o) => o.kind === c!.kind)) continue;
    if (c.kind === 'done' && out.some((o) => o.kind === 'done' && o.weekday === c!.weekday)) continue;
    out.push(c);
    if (out.length >= MAX_DO) break;
  }
  return out;
};

export const clean = (a: CoachAnswer, context: ChatContext): CoachAnswer => {
  const reply = a.reply.trim().slice(0, 600) || "Let's train!";
  const action = cleanAction(a.action);
  const suggestions = [...new Set((a.suggestions ?? []).map((q) => q.trim().slice(0, 50)).filter(Boolean))].slice(0, 3);
  const exercises = cleanExercises(a.exercises, context);
  const protect = cleanProtect(a.protect);
  const measurement = cleanMeasurement(a.measurement);
  const doActions = cleanDo(a.doActions, context);
  const w = a.workout;
  if (!w) return { reply, workout: null, action, suggestions, exercises, protect, measurement, doActions };
  const groups = [...new Set(w.groups.filter((g) => MUSCLE_GROUPS.includes(g)))];
  const avoidGroups = [...new Set(w.avoidGroups.filter((g) => MUSCLE_GROUPS.includes(g) && !groups.includes(g)))];
  if (groups.length === 0) return { reply, workout: null, action, suggestions, exercises, protect, measurement, doActions };
  const known = new Set(context.equipment ?? []);
  return {
    reply,
    action,
    suggestions,
    exercises,
    protect,
    measurement,
    doActions,
    workout: {
      name: w.name.trim().slice(0, 40) || 'Coach workout',
      minutes: Math.min(120, Math.max(15, Math.round(w.minutes || context.sessionMinutes || 45))),
      groups,
      rest: REST_STYLES.includes(w.rest) ? w.rest : 'standard',
      grouping: GROUPINGS.includes(w.grouping) ? w.grouping : 'straight',
      avoidGroups,
      avoidEquipment: [...new Set(w.avoidEquipment.filter((e) => known.has(e)))].slice(0, 20),
      avoidKeywords: [...new Set(w.avoidKeywords.map((k) => k.trim().toLowerCase()).filter((k) => k.length >= 3))].slice(0, 10),
    },
  };
};

/** Claude Opus 5.5 with structured output; low effort keeps each message quick and cheap (~1–2 US¢). */
/** `workspaceId`: needed when the API key is not scoped to a workspace (sent as anthropic-workspace-id). */
export const claudeCoach = (apiKey: string, workspaceId?: string, model = AI_MODELS.chat): CoachModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 45_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (turns, context, photo) => {
    const about = describeMember(context);
    const messages: Anthropic.Beta.BetaMessageParam[] = turns.map((t, i) => ({
      role: t.role === 'member' ? 'user' : 'assistant',
      // The machine photo (#856) goes with the member's last message.
      content:
        photo && i === turns.length - 1
          ? [
              { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: photo.toString('base64') } },
              { type: 'text', text: t.text },
            ]
          : t.text,
    }));
    const res = await tracked('chat', model, () => client.beta.messages.create({
      model,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      // Same Coach rules for everyone, cached; the member's own lines come after the cache mark (#866).
      system: [{ type: 'text', text: SYSTEM, cache_control: CACHED }, ...(about ? [{ type: 'text' as const, text: `About this member:\n${about}` }] : [])],
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages,
    }));
    if (res.stop_reason === 'refusal') return { reply: "I can't help with that one. Ask me about your training!", workout: null, action: null, suggestions: [], exercises: [], protect: null, measurement: null, doActions: [] };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return clean(JSON.parse(text) as CoachAnswer, context);
  };
};
