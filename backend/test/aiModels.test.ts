import { describe, expect, it } from 'vitest';
import { AI_MODELS } from '../src/coach/models.ts';
import { loadConfig } from '../src/config.ts';

describe('model per task (#866)', () => {
  it('plans with the top model and scans with the faster one by default', () => {
    const { models } = loadConfig({ NODE_ENV: 'test' }).coachChat;
    expect(models).toEqual(AI_MODELS);
    expect(models.chat).toBe('claude-opus-5-5');
    expect(models.scan).toBe('claude-sonnet-5-5');
  });

  it('takes AI_MODEL_CHAT / AI_MODEL_SCAN overrides, ignoring blanks', () => {
    expect(loadConfig({ NODE_ENV: 'test', AI_MODEL_SCAN: 'claude-opus-5-5' }).coachChat.models).toEqual({ chat: 'claude-opus-5-5', scan: 'claude-opus-5-5' });
    expect(loadConfig({ NODE_ENV: 'test', AI_MODEL_CHAT: '  ' }).coachChat.models.chat).toBe('claude-opus-5-5');
  });
});
