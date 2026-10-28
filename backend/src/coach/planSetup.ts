import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS, CACHED, tracked } from './models.ts';

/**
 * Set up the plan by talking to Coach (#873, design B + C from `ai-epic/a3.png`).
 * - Say it once: the member's own sentence ("lose weight and build muscle, 4 days, bad knee") → the plan form's values,
 *   which the app shows as tiles to fix before it builds the plan.
 * - Not sure? Ask Coach: one form step's options and the answers so far → a short answer and, when it fits, the option
 *   Coach would pick.
 * Only form values go out; no account data.
 */
export const GOALS = ['balanced', 'build', 'strength', 'climbing', 'endurance', 'athletic'] as const;
export const LEVELS = ['beginner', 'intermediate', 'advanced'] as const;
export const MINUTES = [45, 60, 75, 90] as const;

export interface PlanDraft {
  goal: (typeof GOALS)[number];
  experience: (typeof LEVELS)[number];
  sessions: number;
  weekdays: number[];
  minutes: number | null;
  climbs: boolean;
  climbDays: number | null;
  protect: string | null;
  summary: string;
}

export interface HelpAsk {
  step: string;
  options: { id: string; label: string }[];
  so: string[];
  question?: string;
}

export interface HelpAnswer {
  answer: string;
  pick: string | null;
}

export interface PlanSetupModel {
  plan: (text: string) => Promise<PlanDraft>;
  help: (ask: HelpAsk) => Promise<HelpAnswer>;
}

const PLAN_SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. A new member tells you in their own words what they want from training. Turn it into the values of the plan form.

- goal: balanced (a bit of everything, general fitness), build (muscle size, toning, look better), strength (lift heavier), climbing (stronger for climbing), endurance (fitness, running, stamina, weight loss with cardio), athletic (power, speed, sport). "Lose weight and build muscle" is build. Not said: balanced.
- experience: beginner unless they mention years of training or lifting numbers; advanced only for clear long experience.
- sessions: gym days a week, 2 to 6. Not said: 3 for beginners, else 4.
- weekdays: only the weekdays they name (1 = Monday … 7 = Sunday), else empty. At most as many as sessions.
- minutes: 45, 60, 75 or 90 when they give a session length (round to the nearest), else null.
- climbs: true when they climb or boulder besides the gym. climbDays: climbing days a week (1 to 4) when said, else null.
- protect: the body part they want to spare (pain, old injury, "bad knee"), in 1 to 3 words like "left knee" or "lower back", else null. Never diagnose.
- summary: one short warm sentence saying what you set up, plain text, no emoji, like "Muscle and fat loss, 4 days, sparing your knee."
Only use what they said; when unsure pick the safe default.`;

const HELP_SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. A new member is filling in the plan form and is not sure what to pick on one step. You get the step, its options (id and label), the answers so far and maybe their question.

Answer:
- answer: at most 2 short sentences, plain text, no emoji: what the options mean for them and which fits, from the answers so far.
- pick: the id of the option you would choose, copied exactly from the options, or null when it really depends on taste.
Never give medical advice; for pain suggest a doctor or physio.`;

const planSchema = {
  type: 'object',
  properties: {
    goal: { type: 'string', enum: [...GOALS] },
    experience: { type: 'string', enum: [...LEVELS] },
    sessions: { type: 'integer' },
    weekdays: { type: 'array', items: { type: 'integer' } },
    minutes: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
    climbs: { type: 'boolean' },
    climbDays: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
    protect: { anyOf: [{ type: 'null' }, { type: 'string' }] },
    summary: { type: 'string' },
  },
  required: ['goal', 'experience', 'sessions', 'weekdays', 'minutes', 'climbs', 'climbDays', 'protect', 'summary'],
  additionalProperties: false,
} as const;

const helpSchema = {
  type: 'object',
  properties: {
    answer: { type: 'string' },
    pick: { anyOf: [{ type: 'null' }, { type: 'string' }] },
  },
  required: ['answer', 'pick'],
  additionalProperties: false,
} as const;

/** Keeps the draft inside the form's choices; the app checks it again. */
export const cleanPlan = (d: Partial<PlanDraft>): PlanDraft => {
  const sessions = Math.min(6, Math.max(2, Math.round(Number(d.sessions) || 3)));
  const weekdays = [...new Set((d.weekdays ?? []).filter((w) => Number.isInteger(w) && w >= 1 && w <= 7))].sort((a, b) => a - b).slice(0, sessions);
  const m = Number(d.minutes);
  const minutes = d.minutes == null || !m ? null : MINUTES.reduce((a, b) => (Math.abs(b - m) < Math.abs(a - m) ? b : a));
  const climbs = d.climbs === true || d.goal === 'climbing';
  const cd = Number(d.climbDays);
  return {
    goal: GOALS.includes(d.goal!) ? d.goal! : 'balanced',
    experience: LEVELS.includes(d.experience!) ? d.experience! : 'beginner',
    sessions,
    weekdays,
    minutes,
    climbs,
    climbDays: climbs && cd ? Math.min(4, Math.max(1, Math.round(cd))) : null,
    protect: d.protect?.trim().slice(0, 30) || null,
    summary: d.summary?.trim().slice(0, 200) || 'Here is what I set up. Tap a tile to change it.',
  };
};

/** A pick only from the step's options. */
export const cleanHelp = (a: Partial<HelpAnswer>, ask: HelpAsk): HelpAnswer => ({
  answer: a.answer?.trim().slice(0, 300) || 'Both work. Pick the one you would enjoy most, you can change it any time.',
  pick: ask.options.some((o) => o.id === a.pick) ? a.pick! : null,
});

export const describeHelp = (ask: HelpAsk) =>
  [
    `Step: ${ask.step}`,
    'Options:',
    ...ask.options.map((o) => `- ${o.id}: ${o.label}`),
    ask.so.length > 0 && `So far: ${ask.so.join('; ')}`,
    ask.question && `Their question: ${ask.question}`,
  ]
    .filter(Boolean)
    .join('\n');

/** Top model (#866), low effort: short answers while the member waits on the form. */
export const claudePlanSetup = (apiKey: string, workspaceId?: string, model = AI_MODELS.chat): PlanSetupModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 30_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  const ask = async <T>(feature: string, system: string, schema: { [key: string]: unknown }, content: string): Promise<T | undefined> => {
    const res = await tracked(feature, model, () => client.beta.messages.create({
      model,
      max_tokens: 2000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: [{ type: 'text', text: system, cache_control: CACHED }],
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content }],
    }));
    if (res.stop_reason === 'refusal') return undefined;
    return JSON.parse(res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('')) as T;
  };
  return {
    plan: async (text) => cleanPlan((await ask<PlanDraft>('plan-setup', PLAN_SYSTEM, planSchema, text)) ?? {}),
    help: async (h) => cleanHelp((await ask<HelpAnswer>('plan-help', HELP_SYSTEM, helpSchema, describeHelp(h))) ?? {}, h),
  };
};
