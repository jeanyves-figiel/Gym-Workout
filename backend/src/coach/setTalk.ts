import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS, CACHED, tracked } from './models.ts';

/**
 * Talk to Coach mid-set (#874): the member asks about the set on screen ("too heavy?", "felt it in my lower back") and
 * Coach answers in one or two spoken sentences with up to two fixes the app applies in a tap: a weight for the coming
 * set, a swap from the app's own list, or a rest. The app answers common questions itself and asks the on-device model
 * first; this is the fallback. No identifiers besides exercise ids are sent.
 */
export const ACTION_KINDS = ['weight', 'swap', 'rest'] as const;
export type ActionKind = (typeof ACTION_KINDS)[number];

export interface SetContext {
  exercise: string;
  set: number;
  sets: number;
  kg?: number;
  reps?: number;
  step: number;
  done: { kg: number; reps: number; rir?: number }[];
  lastTime?: string;
  restSec?: number;
  swaps: { id: string; name: string }[];
}

export interface SetAction {
  kind: ActionKind;
  kg?: number | null;
  exerciseId?: string | null;
  sec?: number | null;
}

export interface SetAnswer {
  answer: string;
  actions: SetAction[];
}

export type SetTalkModel = (question: string, context: SetContext) => Promise<SetAnswer>;

const SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. The member is mid-workout, between sets, and asks you something out loud. Your answer is spoken back to them.

You get the exercise, the coming set, the sets already done today (with reps in reserve when logged), last time and the swaps the app can make.

Answer:
- answer: one or two short spoken sentences, max 30 words, concrete numbers from the data. Plain text, no emoji, no lists, no markdown.
- actions: 0 to 2 fixes the member can tap, only when they help:
  - weight: kg for the coming set, a multiple of the weight step, between 60 % and 130 % of the coming set.
  - swap: exerciseId copied exactly from the swaps list.
  - rest: sec between 30 and 600.
- Too heavy, slow reps or 0 reps in reserve: lighter. Easy with 3+ reps in reserve: a little heavier.
- Pain or a body part that feels wrong: lighter or a swap, and tell them to stop if it is sharp pain and get it checked. Never diagnose, never give medical advice.`;

const schema = {
  type: 'object',
  properties: {
    answer: { type: 'string' },
    actions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: [...ACTION_KINDS] },
          kg: { anyOf: [{ type: 'null' }, { type: 'number' }] },
          exerciseId: { anyOf: [{ type: 'null' }, { type: 'string' }] },
          sec: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
        },
        required: ['kind', 'kg', 'exerciseId', 'sec'],
        additionalProperties: false,
      },
    },
  },
  required: ['answer', 'actions'],
  additionalProperties: false,
} as const;

const kg = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1));

/** The set as lines for the model. */
export const describeSet = (c: SetContext) =>
  [
    `Exercise: ${c.exercise}, set ${c.set} of ${c.sets}`,
    c.kg != null ? `Coming set: ${kg(c.kg)} kg${c.reps != null ? ` × ${c.reps}` : ''}` : c.reps != null && `Coming set: ${c.reps} reps`,
    ...c.done.map((d, i) => `Set ${i + 1} done: ${kg(d.kg)} kg × ${d.reps}${d.rir != null ? `, ${d.rir} reps in reserve` : ''}`),
    c.lastTime && `Last time: ${c.lastTime}`,
    c.restSec != null && `Planned rest: ${c.restSec} s`,
    c.swaps.length > 0 && `Swaps: ${c.swaps.map((s) => `${s.name} (id ${s.id})`).join(', ')}`,
    `Weight step: ${kg(c.step)} kg`,
  ]
    .filter(Boolean)
    .join('\n');

/** Keeps fixes that fit the set (the app checks them again): one per kind, at most two. */
export const cleanSetAnswer = (a: SetAnswer, c: SetContext): SetAnswer => {
  const actions: SetAction[] = [];
  const kinds = new Set<string>();
  for (const x of a.actions ?? []) {
    if (actions.length === 2 || kinds.has(x.kind)) continue;
    if (x.kind === 'weight') {
      if (x.kg == null || c.kg == null || c.kg <= 0) continue;
      const r = Math.round(x.kg / c.step) * c.step;
      if (r < c.kg * 0.6 || r > c.kg * 1.3 || r === c.kg) continue;
      actions.push({ kind: 'weight', kg: r });
    } else if (x.kind === 'swap') {
      if (!c.swaps.some((s) => s.id === x.exerciseId)) continue;
      actions.push({ kind: 'swap', exerciseId: x.exerciseId });
    } else if (x.kind === 'rest') {
      if (x.sec == null) continue;
      actions.push({ kind: 'rest', sec: Math.min(600, Math.max(30, Math.floor(x.sec / 15) * 15)) });
    } else continue;
    kinds.add(x.kind);
  }
  return { answer: (a.answer ?? '').trim().slice(0, 240), actions };
};

/** Top model (#866), low effort: the member is waiting under the bar. */
export const claudeSetTalk = (apiKey: string, workspaceId?: string, model = AI_MODELS.chat): SetTalkModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 20_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (question, context) => {
    const res = await tracked('set-talk', model, () => client.beta.messages.create({
      model,
      max_tokens: 1500,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: [{ type: 'text', text: SYSTEM, cache_control: CACHED }],
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: `${describeSet(context)}\n\nMember says: ${question}` }],
    }));
    if (res.stop_reason === 'refusal') return { answer: 'Keep it light and safe. If something hurts, stop this one.', actions: [] };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return cleanSetAnswer(JSON.parse(text) as SetAnswer, context);
  };
};
