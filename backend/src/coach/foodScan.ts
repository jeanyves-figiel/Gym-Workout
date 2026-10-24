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

/** One food on a cooked plate (#723): like `FoodSeen`, with the grams on the plate and caffeine per 100 g. */
export interface PlateFood extends FoodSeen {
  grams: number;
  caffeine: number;
}

export interface PlateSeen {
  /** Short dish name ("Chicken teriyaki bowl"), empty when the plate is just separate foods. */
  dish: string;
  items: PlateFood[];
}

export type PlateScanModel = (jpeg: Buffer, catalog: ScanItem[]) => Promise<PlateSeen>;

/** Magic Snap (#733): one photo, sorted. `meal` = something about to be eaten (logged), `stock` = food kept at home,
 * shopping or a receipt (added to What I have). */
export type SnapKind = 'meal' | 'stock';
export interface SnapSeen extends PlateSeen {
  kind: SnapKind;
}
export type SnapScanModel = (jpeg: Buffer, catalog: ScanItem[]) => Promise<SnapSeen>;

const PLATE_SYSTEM = `You look at a photo of a meal someone is about to eat or a drink they have: a plate, a bowl, a lunch box, a sandwich, a mug.
- Name the dish in a few plain words (max 40 characters), e.g. "Chicken teriyaki bowl". Use "" when it is not one dish.
- List each component you can see or that the dish clearly contains (rice, chicken, sauce, oil for frying, cheese on top). Several pieces of the same count once.
- "grams": your best estimate of how much of it is on the plate, cooked weight as served (ml for drinks). Use the plate, cutlery, hands and packaging for scale. A dinner plate is about 26 cm wide.
- Then match: give "id" from the list only when the component is that same food in the same state (cooked rice is not dry rice; use "" and a plain name like "Rice, cooked" instead). If nothing on the list fits, give "id": "" and a short plain name (max 40 characters).
- "per100": your best estimate per 100 g as served; "caffeine" mg per 100 g (coffee about 40, tea about 20, else 0); "alcohol" true for alcoholic drinks.
- "group" is the closest group. "sure" is false when the component is partly hidden or you are guessing what or how much it is.
- If the photo shows no food or drink, return an empty list.`;

const plateSchema = {
  type: 'object',
  properties: {
    dish: { type: 'string' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          ...schema.properties.items.items.properties,
          grams: { type: 'number' },
          caffeine: { type: 'number' },
        },
        required: [...schema.properties.items.items.required, 'grams', 'caffeine'],
        additionalProperties: false,
      },
    },
  },
  required: ['dish', 'items'],
  additionalProperties: false,
} as const;

const SNAP_SYSTEM = `First decide what the photo shows:
- "meal": food or a drink someone is about to eat or have now (a served plate, a bowl, a lunch box, a sandwich in hand, a mug, a shake).
- "stock": food kept or bought (an open fridge, a cupboard, shopping on a table, closed packages, a supermarket receipt).
Give that as "kind", then answer as below. For "stock", "grams" is the amount you can see (0 when unknown) and "dish" is "".

${PLATE_SYSTEM}`;

const snapSchema = {
  ...plateSchema,
  properties: { kind: { type: 'string', enum: ['meal', 'stock'] }, ...plateSchema.properties },
  required: ['kind', ...plateSchema.required],
} as const;

/** Same clean-up as the fridge scan, plus grams (1 g–2 kg) and caffeine; the same id twice adds up its grams. */
export const cleanPlateScan = (raw: { dish?: unknown; items?: Partial<PlateFood>[] }, catalog: ScanItem[]): PlateSeen => {
  const items = raw.items ?? [];
  const grams = new Map<string, number>();
  const caffeine = new Map<string, number>();
  const known = new Set(catalog.map((c) => c.id));
  for (const r of items) {
    const key = r.id && known.has(r.id) ? r.id : String(r.name ?? '').replace(/\s+/g, ' ').trim().slice(0, 40).toLowerCase();
    grams.set(key, (grams.get(key) ?? 0) + clamp(r.grams, 2000));
    if (!caffeine.has(key)) caffeine.set(key, clamp(r.caffeine, 400));
  }
  const out = cleanFoodScan(items, catalog).map((f) => {
    const key = f.id ?? f.name.toLowerCase();
    return { ...f, grams: Math.max(1, Math.round(Math.min(2000, grams.get(key) ?? 0))), caffeine: caffeine.get(key) ?? 0 };
  });
  return { dish: String(raw.dish ?? '').replace(/\s+/g, ' ').trim().slice(0, 40), items: out };
};

/** Plate clean-up plus the kind; anything but "stock" counts as a meal, and a stock photo has no dish. */
export const cleanSnapScan = (raw: { kind?: unknown; dish?: unknown; items?: Partial<PlateFood>[] }, catalog: ScanItem[]): SnapSeen => {
  const kind: SnapKind = raw.kind === 'stock' ? 'stock' : 'meal';
  const plate = cleanPlateScan(raw, catalog);
  return { kind, ...plate, dish: kind === 'stock' ? '' : plate.dish };
};

/** Plate scan (#723): same model and settings as the fridge scan, its own prompt and schema. */
export const claudePlateScan = (apiKey: string, workspaceId?: string): PlateScanModel => {
  const ask = visionCall(apiKey, workspaceId, PLATE_SYSTEM, plateSchema);
  return async (jpeg, catalog) => {
    const raw = await ask(jpeg, catalog);
    return raw ? cleanPlateScan(raw as { dish?: unknown; items?: Partial<PlateFood>[] }, catalog) : { dish: '', items: [] };
  };
};

/** Magic Snap (#733): plate prompt and schema with the kind first. */
export const claudeSnapScan = (apiKey: string, workspaceId?: string): SnapScanModel => {
  const ask = visionCall(apiKey, workspaceId, SNAP_SYSTEM, snapSchema);
  return async (jpeg, catalog) => {
    const raw = await ask(jpeg, catalog);
    return raw ? cleanSnapScan(raw as { kind?: unknown; dish?: unknown; items?: Partial<PlateFood>[] }, catalog) : { kind: 'meal', dish: '', items: [] };
  };
};

/** One structured vision call; undefined on a refusal. */
const visionCall = (apiKey: string, workspaceId: string | undefined, system: string, outSchema: { [key: string]: unknown }) => {
  const client = new Anthropic({
    apiKey,
    timeout: 60_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (jpeg: Buffer, catalog: ScanItem[]) => {
    const res = await client.beta.messages.create({
      model: COACH_MODEL_ID,
      max_tokens: 6000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system,
      output_config: { effort: 'medium', format: { type: 'json_schema', schema: outSchema } },
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
    if (res.stop_reason === 'refusal') return undefined;
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return JSON.parse(text) as unknown;
  };
};
