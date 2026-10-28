import Anthropic from '@anthropic-ai/sdk';
import { COACH_MODEL_ID } from './chat.ts';
import type { ScanItem } from './gymScan.ts';

/**
 * Meal ideas (#869, epic #865): "What can I eat?" on the Fuel day. The member's pantry foods (ids and names), what is
 * left of today's protein and carbs and the meal in; three quick meals out, each made only of pantry foods with grams
 * and short steps. The app adds up the macros from its own food list, so numbers never come from the model. No
 * identifiers are sent.
 */
export const MEALS = ['breakfast', 'lunch', 'dinner', 'snack'] as const;
export type Meal = (typeof MEALS)[number];

export interface MealIdeasAsk {
  pantry: ScanItem[];
  meal: Meal;
  /** Grams still to eat today. */
  left: { protein: number; carbs: number };
  diet?: string;
  avoid: string[];
}

export interface MealIdea {
  name: string;
  minutes: number;
  foods: { id: string; grams: number }[];
  steps: string[];
}

export type MealIdeasModel = (ask: MealIdeasAsk) => Promise<MealIdea[]>;

const SYSTEM = `You suggest quick home meals made from what someone already has.
- Give 3 different meals for the meal asked, each using only foods from their list (by id). Basics like salt, pepper, spices, water and a little oil may be used without listing them.
- Aim the 3 meals at what is left of the day: together protein near the protein left for one meal (dinner or the last meal can take most of it; a snack a small share). Never go far above.
- Grams are realistic raw/as-bought amounts for one person. 2 to 6 foods per meal.
- "name" is short and appetising (max 40 characters); "minutes" total time; "steps" 1 to 5 short imperative steps (max 90 characters each).
- Respect the diet and foods to avoid. If the list cannot make a sensible meal, return fewer meals.`;

const schema = {
  type: 'object',
  properties: {
    ideas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          minutes: { type: 'integer' },
          foods: {
            type: 'array',
            items: { type: 'object', properties: { id: { type: 'string' }, grams: { type: 'number' } }, required: ['id', 'grams'], additionalProperties: false },
          },
          steps: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'minutes', 'foods', 'steps'],
        additionalProperties: false,
      },
    },
  },
  required: ['ideas'],
  additionalProperties: false,
} as const;

const line = (s: unknown, max: number) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, max);

/** At most 3 ideas; foods only from the pantry (one entry per id, 1–1000 g); an idea without a food is dropped. */
export const cleanMealIdeas = (raw: Partial<MealIdea>[], pantry: ScanItem[]): MealIdea[] => {
  const known = new Set(pantry.map((p) => p.id));
  const out: MealIdea[] = [];
  for (const r of raw) {
    const seen = new Set<string>();
    const foods = (Array.isArray(r.foods) ? r.foods : []).flatMap((f) => {
      if (!f || !known.has(f.id) || seen.has(f.id) || typeof f.grams !== 'number' || !Number.isFinite(f.grams) || f.grams <= 0) return [];
      seen.add(f.id);
      return [{ id: f.id, grams: Math.round(Math.min(1000, Math.max(1, f.grams))) }];
    });
    const name = line(r.name, 40);
    if (!name || foods.length === 0) continue;
    const minutes = typeof r.minutes === 'number' && Number.isFinite(r.minutes) ? Math.round(Math.min(180, Math.max(1, r.minutes))) : 15;
    const steps = (Array.isArray(r.steps) ? r.steps : []).map((s) => line(s, 90)).filter(Boolean).slice(0, 5);
    out.push({ name, minutes, foods: foods.slice(0, 8), steps });
    if (out.length === 3) break;
  }
  return out;
};

/** One structured text call, same model and account as the coach; [] on a refusal. */
export const claudeMealIdeas = (apiKey: string, workspaceId?: string): MealIdeasModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 60_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (ask) => {
    const prefs = [ask.diet ? `Diet: ${ask.diet}` : '', ask.avoid.length ? `Avoid: ${ask.avoid.join(', ')}` : ''].filter(Boolean).join('\n');
    const res = await client.beta.messages.create({
      model: COACH_MODEL_ID,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages: [
        {
          role: 'user',
          content: `Meal: ${ask.meal}\nLeft today: ${ask.left.protein} g protein, ${ask.left.carbs} g carbs\n${prefs}\nFoods I have (id: name):\n${ask.pantry
            .map((p) => `${p.id}: ${p.label}`)
            .join('\n')}`,
        },
      ],
    });
    if (res.stop_reason === 'refusal') return [];
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    const raw = JSON.parse(text) as { ideas?: Partial<MealIdea>[] };
    return cleanMealIdeas(raw.ideas ?? [], ask.pantry);
  };
};
