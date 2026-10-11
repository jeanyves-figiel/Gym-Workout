import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';

let app: FastifyInstance;
const make = (env: Record<string, string> = {}) =>
  (app = buildApp({
    config: loadConfig({ NODE_ENV: 'test', ...env }),
    db: openDb(':memory:'),
    mailer: new ConsoleMailer(() => {}),
    apple: async () => {
      throw new Error('unused');
    },
  }));
afterEach(() => app?.close());

describe('legal pages (#125)', () => {
  it.each(['/privacy', '/terms', '/support'])('%s is public HTML', async (url) => {
    const res = await make().inject({ method: 'GET', url });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('MonkeyWorkout');
  });

  it('shows placeholders until the operator is configured', async () => {
    const res = await make().inject({ method: 'GET', url: '/terms' });
    expect(res.body).toContain('[operator name to be completed]');
    expect(res.body).toContain('[contact email to be completed]');
    expect(res.body).toContain('laws of Switzerland');
  });

  it('renders configured operator details escaped, contact falls back to MODERATION_EMAIL', async () => {
    const res = await make({
      LEGAL_OPERATOR: 'Jane <Doe>',
      LEGAL_ADDRESS: 'Street 1, 1000 Town',
      MODERATION_EMAIL: 'mod@example.com',
      LEGAL_LAW: 'France',
      LEGAL_VENUE: 'Paris',
    }).inject({ method: 'GET', url: '/privacy' });
    expect(res.body).toContain('Jane &#60;Doe&#62;');
    expect(res.body).toContain('mailto:mod@example.com');
    expect(res.body).not.toContain('to be completed');
    const terms = await app.inject({ method: 'GET', url: '/terms' });
    expect(terms.body).toContain('laws of France');
    expect(terms.body).toContain('Place of jurisdiction is Paris');
    expect(terms.body).toContain('third-party beneficiaries');
  });
});
