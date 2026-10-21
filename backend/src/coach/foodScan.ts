import Anthropic from '@anthropic-ai/sdk';
import { COACH_MODEL_ID } from './chat.ts';
import type { ScanItem } from './gymScan.ts';

/**
 * Food scan (#496): a photo of the member's fridge, cupboard, shopping or a receipt in, the foods on it out. Foods on the
 * app's own list come back with their id; anything else (#573) comes back as a new food with its own name, group and
 * values per 100 g, never forced onto the nearest id. Each item says whether the model is sure. The photo is passed
 * through and never kept; no identifiers are sent.
 */
export const FOOD_GROUPS = ['protein', 'dairy', 'grain', 'legume', 'veg', 'fruit', 'fat', 'sauce', 'snack', 'drink'] as const;

export interface FoodSeen {
  /** Catalog id, only when the item really is that food. */
  id?: string;
  name: string;
  group: (typeof FOOD_GROUPS)[number];
  sure: boolean;
  alcohol: boolean;
  per100: { protein: number; carbs: number; fat: number; kcal: number };
}

export type FoodScanModel = (jpeg: Buffer, catalog: ScanItem[]) => Promise<FoodSeen[]>;

const SYSTEM = `You look at a photo of food or drinks someone has at home: an open fridge, a cupboard, shopping on a table, a bottle or package, or a supermarket receipt.
- List every distinct food or drink that is there. Several of the same count once.
- First identify what each item really is: read the labels, brands and any text (any language), and look at the shape of the container. A brown glass bottle with a crown cap is a drink; "Bier", "Lager", "% vol" mean beer; brand or region names (e.g. Appenzeller, Emmentaler) can be a beer, a liqueur or a cheese, so decide from the package, not the word.
- Then match: give "id" from the list only when the item is that same food (same kind, e.g. "beer" for any beer, "greek-yogurt" for Greek yogurt). Pick the most specific id. If nothing on the list is that food, give "id": "" and a short plain name (brand allowed, max 40 characters); never use the id of a different food that merely looks or sounds similar.
- Drinks, including alcohol (beer, wine, cider, spirits), are food here: list them like anything else, without judgement.
- "group" is the closest group; "per100" your best estimate per 100 g (per 100 ml for drinks); "alcohol" true for alcoholic drinks.
- "sure" is false when the item is partly hidden, blurry, or you are guessing between foods.
- Skip things that are not food or drink. If the photo shows none, return an empty list.`;

const schema = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          name: { type: 'string' },
          group: { type: 'string', enum: [...FOOD_GROUPS] },
          sure: { type: 'boolean' },
          alcohol: { type: 'boolean' },
          per100: {
            type: 'object',
            properties: { protein: { type: 'number' }, carbs: { type: 'number' }, fat: { type: 'number' }, kcal: { type: 'number' } },
            required: ['protein', 'carbs', 'fat', 'kcal'],
            additionalProperties: false,
          },
        },
        required: ['id', 'name', 'group', 'sure', 'alcohol', 'per100'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
} as const;

const clamp = (n: unknown, max: number) => (typeof n === 'number' && Number.isFinite(n) ? Math.round(Math.min(max, Math.max(0, n)) * 10) / 10 : 0);

/** Known ids stay only when on the catalog; unknown items keep a cleaned name; one entry per id or name. */
export const cleanFoodScan = (raw: Partial<FoodSeen>[], catalog: ScanItem[]): FoodSeen[] => {
  const known = new Map(catalog.map((c) => [c.id, c.label]));
  const out: FoodSeen[] = [];
  const seen = new Set<string>();
  for (const r of raw) {
    const id = r.id && known.has(r.id) ? r.id : undefined;
    const name = (id ? known.get(id)! : String(r.name ?? '')).replace(/\s+/g, ' ').trim().slice(0, 40);
    const key = id ?? name.toLowerCase();
    if (!name || seen.has(key)) continue;
    seen.add(key);
    const p = r.per100 ?? { protein: 0, carbs: 0, fat: 0, kcal: 0 };
    out.push({
      ...(id ? { id } : {}),
      name,
      group: FOOD_GROUPS.includes(r.group as FoodSeen['group']) ? (r.group as FoodSeen['group']) : 'snack',
      sure: r.sure !== false,
      alcohol: r.alcohol === true,
      per100: { protein: clamp(p.protein, 100), carbs: clamp(p.carbs, 100), fat: clamp(p.fat, 100), kcal: clamp(p.kcal, 900) },
    });
    if (out.length >= 40) break;
  }
  return out;
};

/** Claude Opus 5.5 vision with structured output, medium effort (low mixed up look-alikes, #573). */
export const claudeFoodScan = (apiKey: string, workspaceId?: string): FoodScanModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 60_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (jpeg, catalog) => {
    const res = await client.beta.messages.create({
      model: COACH_MODEL_ID,
      max_tokens: 6000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SYSTEM,
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: jpeg.toString('base64') } },
            { type: 'text', text: `Food ids (id: name):\n${catalog.map((c) => `${c.id}: ${c.label}`).join('\n')}` },
          ],
        },
      ],
    });
    if (res.stop_reason === 'refusal') return [];
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return cleanFoodScan((JSON.parse(text) as { items: Partial<FoodSeen>[] }).items, catalog);
  };
};
