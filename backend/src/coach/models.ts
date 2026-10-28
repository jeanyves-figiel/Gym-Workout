/**
 * Model per task (#866): the top model plans workouts and answers Coach; photo scans (gym, pantry, plate) only read
 * what is in the picture against the app's own lists, so a faster, cheaper model does them. AI_MODEL_CHAT /
 * AI_MODEL_SCAN override (e.g. back to the top model for scans) without a code change.
 */
export type AiTask = 'chat' | 'scan' | 'moderate';

export const AI_MODELS: Record<AiTask, string> = {
  chat: 'claude-opus-5-5',
  scan: 'claude-sonnet-5-5',
  // Community moderation (#871): a yes/no check on short texts and profile photos, smallest model.
  moderate: 'claude-haiku-5-5',
};

export const aiModels = (env: Record<string, string | undefined>): Record<AiTask, string> => ({
  chat: env.AI_MODEL_CHAT?.trim() || AI_MODELS.chat,
  scan: env.AI_MODEL_SCAN?.trim() || AI_MODELS.scan,
  moderate: env.AI_MODEL_MODERATE?.trim() || AI_MODELS.moderate,
});

/** Cache marker for the stable part of a prompt (system text, catalogs): repeat calls read it at a tenth of the price. */
export const CACHED = { type: 'ephemeral' } as const;
