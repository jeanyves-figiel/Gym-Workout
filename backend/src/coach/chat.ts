import Anthropic from '@anthropic-ai/sdk';

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
  /** Exercise names Coach may suggest from (#856, freestyle): the app's catalog at the member's level. */
  exercises?: string[];
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
}

/** `photo`: a JPEG of the machine in front of the member (#856), with the last message. */
export type CoachModel = (turns: ChatTurn[], context: ChatContext, photo?: Buffer) => Promise<CoachAnswer>;

/** Most exercises Coach hands back at once (#856). */
export const MAX_EXERCISES = 4;

/** Stands for the member's first name, which stays on the device (#415). */
export const NAME_SLOT = '{name}';

export const COACH_MODEL_ID = 'claude-opus-5-5';

const SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. Members ask you from any screen of the app, by text or by voice: to get a workout for today, or about an exercise, their form, their progress, their plan, recovery or how the app works.

Answering questions (#412):
- "Screen" and "Looking at" below tell you what the member sees. Questions like "why is it down?" or "is this right for me?" are about that.
- Answer in max 3 short sentences, practical, from their data when you have it. Never make up numbers you weren't given.
- action: a button to open a screen when it truly helps ("progress", "calendar", "explore", "fuel", "settings", or "exercise" with the exact exercise name, e.g. a safer alternative). Else null.
- suggestions: up to 3 short follow-up questions the member might tap next (max 5 words each), in their language.
- Food (Fuel, #496): give general pointers on eating around training, using the day's training and the targets in "Looking at" when given (protein, carbs, water, meals). Suggest simple meals. Never prescribe diets, calorie restriction or supplements as treatment; for a medical condition, pregnancy or an eating disorder suggest a doctor or dietitian.
- Freestyle (#856, Screen "freestyle"): the member is at the gym building the workout as they go. When they ask what to do, name a muscle, name or describe a machine, or send a photo of one, put up to 4 exercises in "exercises", best first, using exact names from "Exercises in the app" only. For a photo or description, say in the reply which machine it is and one setup tip. workout null. Elsewhere exercises is an empty list.
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
  },
  required: ['reply', 'workout', 'action', 'suggestions', 'exercises'],
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

export const clean = (a: CoachAnswer, context: ChatContext): CoachAnswer => {
  const reply = a.reply.trim().slice(0, 600) || "Let's train!";
  const action = cleanAction(a.action);
  const suggestions = [...new Set((a.suggestions ?? []).map((q) => q.trim().slice(0, 50)).filter(Boolean))].slice(0, 3);
  const exercises = cleanExercises(a.exercises, context);
  const w = a.workout;
  if (!w) return { reply, workout: null, action, suggestions, exercises };
  const groups = [...new Set(w.groups.filter((g) => MUSCLE_GROUPS.includes(g)))];
  const avoidGroups = [...new Set(w.avoidGroups.filter((g) => MUSCLE_GROUPS.includes(g) && !groups.includes(g)))];
  if (groups.length === 0) return { reply, workout: null, action, suggestions, exercises };
  const known = new Set(context.equipment ?? []);
  return {
    reply,
    action,
    suggestions,
    exercises,
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
export const claudeCoach = (apiKey: string, workspaceId?: string): CoachModel => {
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
    const res = await client.beta.messages.create({
      model: COACH_MODEL_ID,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: about ? `${SYSTEM}\n\nAbout this member:\n${about}` : SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages,
    });
    if (res.stop_reason === 'refusal') return { reply: "I can't help with that one. Ask me about your training!", workout: null, action: null, suggestions: [], exercises: [] };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return clean(JSON.parse(text) as CoachAnswer, context);
  };
};
