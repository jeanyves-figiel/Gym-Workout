import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { openDb } from '../src/db.ts';
import { ConsoleMailer } from '../src/mailer.ts';
import { CAST_NAMESPACE } from '../src/routes/cast.ts';

let app: FastifyInstance;
const make = () =>
  (app = buildApp({
    config: loadConfig({ NODE_ENV: 'test' }),
    db: openDb(':memory:'),
    mailer: new ConsoleMailer(() => {}),
    apple: async () => {
      throw new Error('unused');
    },
  }));
afterEach(() => app?.close());

describe('Chromecast receiver (#1008)', () => {
  it('serves the receiver page on the workout namespace', async () => {
    const res = await make().inject({ method: 'GET', url: '/cast/receiver' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('cast_receiver_framework.js');
    expect(res.body).toContain(CAST_NAMESPACE);
  });

  it('serves a movement clip, whole and by byte range', async () => {
    const whole = await make().inject({ method: 'GET', url: '/cast/motion/motion-front-squat.mp4' });
    expect(whole.statusCode).toBe(200);
    expect(whole.headers['content-type']).toBe('video/mp4');
    const size = Number(whole.headers['content-length']);
    expect(size).toBeGreaterThan(100);
    const part = await app.inject({ method: 'GET', url: '/cast/motion/motion-front-squat.mp4', headers: { range: 'bytes=0-99' } });
    expect(part.statusCode).toBe(206);
    expect(part.headers['content-range']).toBe(`bytes 0-99/${size}`);
    expect(part.rawPayload.length).toBe(100);
  });

  it.each(['motion-nope.mp4', '..%2F..%2Fpackage.json', 'motion-../x.mp4', 'evil.txt'])('404 for %s', async (file) => {
    const res = await make().inject({ method: 'GET', url: `/cast/motion/${file}` });
    expect(res.statusCode).toBe(404);
  });
});
