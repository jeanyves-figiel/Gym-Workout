/**
 * Model per task (#866): the top model plans workouts and answers Coach; photo scans (gym, pantry, plate) only read
 * what is in the picture against the app's own lists, so a faster, cheaper model does them. AI_MODEL_CHAT /
 * AI_MODEL_SCAN override (e.g. back to the top model for scans) without a code change.
 */
export type AiTask = 'chat' | 'scan';

export const AI_MODELS: Record<AiTask, string> = {
  chat: 'claude-opus-5-5',
  scan: 'claude-sonnet-5-5',
};

export const aiModels = (env: Record<string, string | undefined>): Record<AiTask, string> => ({
  chat: env.AI_MODEL_CHAT?.trim() || AI_MODELS.chat,
  scan: env.AI_MODEL_SCAN?.trim() || AI_MODELS.scan,
});

/** Cache marker for the stable part of a prompt (system text, catalogs): repeat calls read it at a tenth of the price. */
export const CACHED = { type: 'ephemeral' } as const;

/** One paid model call (#877): what it was for, the model, its tokens, or that it failed. */
export interface AiCall {
  feature: string;
  model: string;
  ok: boolean;
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

let sink: ((c: AiCall) => void) | undefined;

/** Where calls are recorded (the app's database); unset in tests that don't care. */
export const onAiCall = (fn: ((c: AiCall) => void) | undefined) => {
  sink = fn;
};

interface Usage {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

/** Runs one model call and records its usage (or failure) for the AI usage report (#877); the result is unchanged. */
export const tracked = async <T extends { usage?: Usage }>(feature: string, model: string, call: () => Promise<T>): Promise<T> => {
  try {
    const res = await call();
    const u = res.usage ?? {};
    sink?.({
      feature,
      model,
      ok: true,
      input: u.input_tokens ?? 0,
      output: u.output_tokens ?? 0,
      cacheRead: u.cache_read_input_tokens ?? 0,
      cacheWrite: u.cache_creation_input_tokens ?? 0,
    });
    return res;
  } catch (e) {
    sink?.({ feature, model, ok: false, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
    throw e;
  }
};

/** US$ per million tokens: input, output, cache read, cache write (5 min). Unknown models count as the top model. */
export const PRICES: Record<string, [number, number, number, number]> = {
  'claude-opus-5-5': [4, 20, 0.2, 5],
  'claude-sonnet-5-5': [2, 10, 0.2, 2.5],
  'claude-haiku-5-5': [0.1, 0.5, 0.01, 0.125],
};

export const costUsd = (model: string, input: number, output: number, cacheRead: number, cacheWrite: number) => {
  const [i, o, r, w] = PRICES[model] ?? PRICES['claude-opus-5-5']!;
  return (input * i + output * o + cacheRead * r + cacheWrite * w) / 1_000_000;
};
