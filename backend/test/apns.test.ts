import { generateKeyPairSync } from 'node:crypto';
import { createServer, type IncomingHttpHeaders } from 'node:http2';
import type { AddressInfo } from 'node:net';
import { decodeProtectedHeader, decodeJwt } from 'jose';
import { describe, expect, it } from 'vitest';
import { createApnsSender } from '../src/push/apns.ts';

describe('APNs sender', () => {
  it('posts JSON over HTTP/2 with a reused ES256 provider token and reports Apple reasons', async () => {
    const seen: { headers: IncomingHttpHeaders; body: string }[] = [];
    const server = createServer((req, res) => {
      let body = '';
      req.setEncoding('utf8');
      req.on('data', (c: string) => (body += c));
      req.on('end', () => {
        seen.push({ headers: req.headers, body });
        if (req.headers[':path']?.endsWith('dead')) {
          res.writeHead(410, { 'content-type': 'application/json' }).end(JSON.stringify({ reason: 'Unregistered' }));
        } else res.writeHead(200).end();
      });
    });
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const send = createApnsSender(
      { teamId: 'U7VAR53G86', keyId: 'KEY1234567', privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() },
      () => new Date('2026-10-10T10:00:00Z'),
      { sandbox: origin, production: origin },
    );
    const ok = await send({ token: 'ab'.repeat(32), env: 'sandbox', topic: 'Com.app.MonkeyWorkout', payload: { aps: { alert: 'hi' } }, collapseId: 'c1' });
    const dead = await send({ token: 'dead', env: 'production', topic: 'Com.app.MonkeyWorkout', payload: {} });
    server.close();

    expect(ok).toEqual({ status: 200, reason: undefined });
    expect(dead).toEqual({ status: 410, reason: 'Unregistered' });
    const h = seen[0]!.headers;
    expect(h[':method']).toBe('POST');
    expect(h[':path']).toBe(`/3/device/${'ab'.repeat(32)}`);
    expect(h['apns-topic']).toBe('Com.app.MonkeyWorkout');
    expect(h['apns-push-type']).toBe('alert');
    expect(h['apns-collapse-id']).toBe('c1');
    expect(JSON.parse(seen[0]!.body)).toEqual({ aps: { alert: 'hi' } });
    const jwt = String(h.authorization).replace(/^bearer /, '');
    expect(decodeProtectedHeader(jwt)).toEqual({ alg: 'ES256', kid: 'KEY1234567' });
    expect(decodeJwt(jwt)).toMatchObject({ iss: 'U7VAR53G86', iat: Math.floor(Date.parse('2026-10-10T10:00:00Z') / 1000) });
    expect(seen[1]!.headers.authorization).toBe(h.authorization);
  });
});
