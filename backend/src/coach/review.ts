import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS, CACHED, tracked } from './models.ts';

/**
 * Weekly Coach review (#867): the app sends a digest of the week just done (workouts, bests, sleep, HRV, mood) and the
 * coming week's workouts; Coach answers a score, a short summary and up to 3 changes the app can apply itself (move,
 * skip, lighter, +1 set). Changes may only name workouts and lifts from the digest. No identifiers are sent.
 */
export const CHANGE_KINDS = ['move', 'skip', 'lighter', 'addSet'] as const;
export type ChangeKind = (typeof CHANGE_KINDS)[number];

export interface ReviewDigest {
  weekOf: string;
  goal?: string;
  level?: string;
  days: { weekday: number; title: string; done: boolean; minutes?: number }[];
  bests: string[];
  sleepHours?: number;
  hrv?: string;
  mood?: number;
  moodAbout: string[];
  next: { id: string; weekday: number; title: string; lifts: { uid: string; name: string; sets: number }[] }[];
  offDays: number[];
}

export interface ReviewChange {
  kind: ChangeKind;
  sessionId: string;
  weekday?: number | null;
  uid?: string | null;
  label: string;
}

export interface WeekReview {
  weekOf: string;
  score: number;
  headline: string;
  summary: string;
  changes: ReviewChange[];
}

export type ReviewModel = (digest: ReviewDigest) => Promise<WeekReview>;

const DAYS = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const SYSTEM = `You are Coach Monkey, the upbeat coach inside the MonkeyWorkout gym app. Once a week you look back at the member's week and set up the next one.

You get the week just done (workouts planned and done, bests, sleep, HRV, mood) and the coming week's workouts with their ids, weekdays and lifts.

Answer:
- score: 0 to 100 for how the week went against the plan, recovery and mood. 80+ only for a strong, balanced week.
- headline: max 40 characters, facts only, like "4 of 5 done · 2 PRs · sleep down".
- summary: 2 or 3 short sentences, warm and concrete, from the data only. Never make up numbers. Plain text, no emoji, no lists.
- changes: 0 to 3 changes for the coming week, the most useful first, only when the data gives a reason:
  - move: a workout to another weekday (weekday 1 = Monday … 7 = Sunday) when the member keeps missing that day. Only to a day with no workout and not in "days off".
  - skip: drop one workout when the member is clearly run down (very low sleep or HRV, several low moods).
  - lighter: one set fewer on every lift of a workout, for low recovery.
  - addSet: one set more on one lift (its uid) that is improving or lagging behind its goal.
  - sessionId and uid must be copied exactly from the coming week. label: max 40 characters, says what and why, like "Legs to Tue (you skip Thu)".
- If the week was fine and nothing needs to change, return no changes and say so.
- Never give medical advice. If sleep or mood look very poor for a long time, suggest talking to a doctor in the summary.`;

const schema = {
  type: 'object',
  properties: {
    score: { type: 'integer' },
    headline: { type: 'string' },
    summary: { type: 'string' },
    changes: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: [...CHANGE_KINDS] },
          sessionId: { type: 'string' },
          weekday: { anyOf: [{ type: 'null' }, { type: 'integer' }] },
          uid: { anyOf: [{ type: 'null' }, { type: 'string' }] },
          label: { type: 'string' },
        },
        required: ['kind', 'sessionId', 'weekday', 'uid', 'label'],
        additionalProperties: false,
      },
    },
  },
  required: ['score', 'headline', 'summary', 'changes'],
  additionalProperties: false,
} as const;

/** The digest as lines for the model. */
export const describeWeek = (d: ReviewDigest) =>
  [
    d.goal && `Goal: ${d.goal}`,
    d.level && `Level: ${d.level}`,
    `Week of ${d.weekOf}: ${d.days.filter((x) => x.done).length} of ${d.days.length} workouts done`,
    ...d.days.map((x) => `- ${DAYS[x.weekday] ?? x.weekday} ${x.title}: ${x.done ? `done${x.minutes ? `, ${x.minutes} min` : ''}` : 'missed'}`),
    d.bests.length > 0 && `Bests: ${d.bests.join('; ')}`,
    d.sleepHours != null && `Sleep: ${d.sleepHours.toFixed(1)} h last night`,
    d.hrv && `HRV: ${d.hrv}`,
    d.mood != null && `Mood: ${d.mood.toFixed(1)} of 5 on average${d.moodAbout.length ? `, mostly about ${d.moodAbout.join(', ')}` : ''}`,
    'Coming week:',
    ...d.next.map(
      (s) => `- id ${s.id}, ${DAYS[s.weekday] ?? s.weekday} (weekday ${s.weekday}), ${s.title}: ${s.lifts.map((l) => `${l.name} ${l.sets} sets (uid ${l.uid})`).join(', ')}`,
    ),
    d.offDays.length > 0 && `Days off next week: ${d.offDays.map((w) => DAYS[w] ?? w).join(', ')}`,
  ]
    .filter(Boolean)
    .join('\n');

/** Keeps only changes on the digest's coming week; the app checks them again before showing them. */
export const cleanReview = (r: Omit<WeekReview, 'weekOf'>, d: ReviewDigest): WeekReview => {
  const changes: ReviewChange[] = [];
  for (const c of r.changes ?? []) {
    const s = d.next.find((n) => n.id === c.sessionId);
    if (!s || !CHANGE_KINDS.includes(c.kind)) continue;
    const label = c.label?.trim().slice(0, 60);
    if (!label) continue;
    if (c.kind === 'move' && !(Number.isInteger(c.weekday) && c.weekday! >= 1 && c.weekday! <= 7 && c.weekday !== s.weekday)) continue;
    if (c.kind === 'addSet' && !s.lifts.some((l) => l.uid === c.uid)) continue;
    changes.push({
      kind: c.kind,
      sessionId: c.sessionId,
      weekday: c.kind === 'move' ? c.weekday : null,
      uid: c.kind === 'addSet' ? c.uid : null,
      label,
    });
    if (changes.length === 3) break;
  }
  return {
    weekOf: d.weekOf,
    score: Math.min(100, Math.max(0, Math.round(r.score || 0))),
    headline: r.headline?.trim().slice(0, 60) || 'Your week',
    summary: r.summary?.trim().slice(0, 400) || '',
    changes,
  };
};

/** Top model (#866), medium effort: once a week per member, worth the thought. */
export const claudeWeekReview = (apiKey: string, workspaceId?: string, model = AI_MODELS.chat): ReviewModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 60_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (digest) => {
    const res = await tracked('review', model, () => client.beta.messages.create({
      model,
      max_tokens: 6000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: [{ type: 'text', text: SYSTEM, cache_control: CACHED }],
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: describeWeek(digest) }],
    }));
    if (res.stop_reason === 'refusal') return { weekOf: digest.weekOf, score: 0, headline: 'Your week', summary: '', changes: [] };
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return cleanReview(JSON.parse(text) as Omit<WeekReview, 'weekOf'>, digest);
  };
};
