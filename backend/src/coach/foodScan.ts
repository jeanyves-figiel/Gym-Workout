import Anthropic from '@anthropic-ai/sdk';
import { COACH_MODEL_ID } from './chat.ts';
import { type ScanItem, cleanScan } from './gymScan.ts';

/**
 * Food scan (#496): a photo of the member's fridge, cupboard, shopping or a receipt in, the foods on it out, picked only
 * from the app's own food list. The photo is passed through and never kept; no identifiers are sent.
 */
export type FoodScanModel = (jpeg: Buffer, catalog: ScanItem[]) => Promise<string[]>;

const SYSTEM = `You look at a photo of food someone has at home: an open fridge, a cupboard, shopping on a table, packaging or a supermarket receipt.
- List the foods that are clearly there, answering only with ids from the list you are given. Never invent ids.
- On a receipt or packaging, read the product names (any language) and map each to the closest id.
- Pick the most specific id that fits (e.g. "greek-yogurt" over "yogurt" when the label says Greek). Several of the same food count once.
- Skip things that are not food, and anything you are unsure about.
- If the photo shows no food, return an empty list.`;

const schema = {
  type: 'object',
  properties: { items: { type: 'array', items: { type: 'string' } } },
  required: ['items'],
  additionalProperties: false,
} as const;

/** Claude Opus 5.5 vision with structured output, low effort. */
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
      max_tokens: 3000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
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
    return cleanScan((JSON.parse(text) as { items: string[] }).items, catalog);
  };
};
