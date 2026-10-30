import Anthropic from '@anthropic-ai/sdk';
import { AI_MODELS, CACHED, tracked } from './models.ts';

/**
 * Gym scan (#406): a photo of one area of the member's gym in, the equipment on it out, picked only from the app's
 * own equipment list. The photo is passed through and never kept; no identifiers are sent.
 */
export interface ScanItem {
  id: string;
  label: string;
}

export type GymScanModel = (jpeg: Buffer, catalog: ScanItem[]) => Promise<string[]>;

const SYSTEM = `You look at a photo taken inside a gym and list the training equipment that is clearly visible.
- Answer only with ids from the list you are given. Never invent ids.
- Include an id only when you can actually see that kind of equipment in the photo (a rack, a bench, a cable tower, a rower...).
- Plates on a barbell count as "barbell". Several of the same thing count once.
- If the photo is not a gym or nothing matches, return an empty list.`;

const schema = {
  type: 'object',
  properties: { items: { type: 'array', items: { type: 'string' } } },
  required: ['items'],
  additionalProperties: false,
} as const;

/** Keeps known ids only, once each, in catalog order. */
export const cleanScan = (items: string[], catalog: ScanItem[]) => {
  const found = new Set(items);
  return catalog.map((c) => c.id).filter((id) => found.has(id));
};

/** Scan model (#866) vision with structured output, low effort. */
export const claudeGymScan = (apiKey: string, workspaceId?: string, model = AI_MODELS.scan): GymScanModel => {
  const client = new Anthropic({
    apiKey,
    timeout: 60_000,
    maxRetries: 1,
    defaultHeaders: workspaceId ? { 'anthropic-workspace-id': workspaceId } : undefined,
  });
  return async (jpeg, catalog) => {
    const res = await tracked('gym-scan', model, () => client.beta.messages.create({
      model,
      max_tokens: 2000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      messages: [
        {
          role: 'user',
          content: [
            // Catalog first and cached (same for every scan), then the photo (#866).
            { type: 'text', text: `Equipment ids (id: name):\n${catalog.map((c) => `${c.id}: ${c.label}`).join('\n')}`, cache_control: CACHED },
            { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: jpeg.toString('base64') } },
          ],
        },
      ],
    }));
    if (res.stop_reason === 'refusal') return [];
    const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return cleanScan((JSON.parse(text) as { items: string[] }).items, catalog);
  };
};
