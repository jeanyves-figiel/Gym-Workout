import Anthropic from '@anthropic-ai/sdk';

/**
 * Workout chat (#381): the member says what they want today ("45 min, legs, sore shoulder") and Coach Monkey
 * answers with a short line plus generator settings. The app's own engine builds the workout from those settings,
 * so only known exercises that fit the member's gym ever come back. The model never sees an account id or email.
 */

export const MUSCLE_GROUPS = ['shoulders', 'chest', 'arms', 'back', 'core', 'hips', 'legs'] as const;
export const REST_STYLES = ['long', 'standard', 'short'] as const;
export const GROUPINGS = ['straight', 'supersets', 'circuits'] as const;

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
}

export type CoachModel = (turns: ChatTurn[], context: ChatContext) => Promise<CoachAnswer>;

export const COACH_MODEL_ID = 'claude-opus-5-5';

const SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. A member chats with you to get a workout for today.

Your job: turn what they say into settings for the app's workout generator, plus one short friendly reply.
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
- Anything unrelated to training: one friendly line steering back to today's workout, workout null.
- Pain that sounds like an injury: suggest seeing a professional and offer a workout that avoids that area.
- reply: max 2 short sentences, plain text, no markdown, in the member's language. name: 2 to 4 words for the workout.`;

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
  },
  required: ['reply', 'workout'],
  additionalProperties: false,
} as const;

const describe = (c: ChatContext) =>
  [
    c.goal && `Goal: ${c.goal}`,
    c.level && `Level: ${c.level}`,
    c.method && `Training method: ${c.method}`,
    c.sessionMinutes && `Usual session: ${c.sessionMinutes} min`,
    c.readiness && `Readiness today: ${c.readiness}`,
    c.todayPlanned && `Planned today: ${c.todayPlanned}`,
    c.equipment?.length && `Equipment ids: ${c.equipment.join(', ')}`,
  ]
    .filter(Boolean)
    .join('\n');

/** Keeps only settings the app can use; drops unknown values instead of failing the chat. */
export const clean = (a: CoachAnswer, context: ChatContext): CoachAnswer => {
  const reply = a.reply.trim().slice(0, 400) || "Let's train!";
  const w = a.workout;
  if (!w) return { reply, workout: null };
  const groups = [...new Set(w.groups.filter((g) => MUSCLE_GROUPS.includes(g)))];
  const avoidGroups = [...new Set(w.avoidGroups.filter((g) => MUSCLE_GROUPS.includes(g) && !groups.includes(g)))];
  if (groups.length === 0) return { reply, workout: null };
  const known = new Set(context.equipment ?? []);
  return {
    reply,
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
  return async (turns, context) => {
    const about = describe(context);
    const messages: Anthropic.Beta.BetaMessageParam[] = turns.map((t) => ({ role: t.role === 'member' ? 'user' : 'assistant', content: t.text }));
    const res = await client.beta.messages.create({
      model: COACH_MODEL_ID,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: about ? `${SYSTEM}\n\nAbout this member:\n${about}` : SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages,
    });
    if (res.stop_reason === 'refusal') return { reply: "I can't help with that one. Tell me what you'd like to train today!", workout: null };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return clean(JSON.parse(text) as CoachAnswer, context);
  };
};
