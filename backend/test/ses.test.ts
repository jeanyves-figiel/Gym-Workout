import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.ts';
import { buildMime, SesMailer, signV4 } from '../src/ses.ts';

describe('SigV4', () => {
  it('matches the AWS documentation example (IAM ListUsers)', () => {
    const auth = signV4({
      method: 'GET',
      url: new URL('https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        Host: 'iam.amazonaws.com',
        'X-Amz-Date': '20150830T123600Z',
      },
      body: '',
      service: 'iam',
      region: 'us-east-1',
      accessKeyId: 'AKIDEXAMPLE',
      secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
      amzDate: '20150830T123600Z',
    });
    expect(auth).toBe(
      'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7',
    );
  });
});

describe('SesMailer', () => {
  const creds = { region: 'eu-central-2', accessKeyId: 'AKIDTEST', secretAccessKey: 'secret' };
  const now = () => new Date('2026-10-10T08:00:00Z');

  it('posts a signed SendRawEmail to the regional API endpoint', async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const fetchFn = (async (url: URL, init: RequestInit) => {
      calls.push({ url: url.toString(), init });
      return new Response('<SendRawEmailResponse/>', { status: 200 });
    }) as unknown as typeof fetch;
    await new SesMailer(creds, 'MonkeyWorkout <no-reply@monkeygrade.cloud>', fetchFn, now).send({ to: 'a@b.c', subject: '123456 is your code', text: 'Hi ✓' });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.url).toBe('https://email.eu-central-2.amazonaws.com/');
    const h = calls[0]!.init.headers as Record<string, string>;
    expect(h.authorization).toMatch(/^AWS4-HMAC-SHA256 Credential=AKIDTEST\/20261010\/eu-central-2\/ses\/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=[0-9a-f]{64}$/);
    expect(h['x-amz-date']).toBe('20261010T080000Z');
    const form = new URLSearchParams(calls[0]!.init.body as string);
    expect(form.get('Action')).toBe('SendRawEmail');
    const mime = Buffer.from(form.get('RawMessage.Data')!, 'base64').toString('utf8');
    expect(mime).toContain('To: a@b.c');
    expect(mime).toContain('Subject: 123456 is your code');
  });

  it('throws with the SES error code on failure', async () => {
    const fetchFn = (async () =>
      new Response('<ErrorResponse><Error><Code>MessageRejected</Code><Message>Email address is not verified.</Message></Error></ErrorResponse>', { status: 400 })) as unknown as typeof fetch;
    await expect(new SesMailer(creds, 'x@y.z', fetchFn, now).send({ to: 'a@b.c', subject: 's', text: 't' })).rejects.toThrow(/MessageRejected/);
  });

  it('encodes non-ASCII subjects', () => {
    expect(buildMime('x@y.z', { to: 'a@b.c', subject: 'Café', text: 't' })).toContain('Subject: =?UTF-8?B?');
  });

  it('is picked when SES credentials are configured', () => {
    const c = loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(40), CODE_PEPPER: 'p', SES_ACCESS_KEY_ID: 'AK', SES_SECRET_ACCESS_KEY: 'SK', SMTP_URL: 'smtp://old' });
    expect(c.mail.transport).toBe('ses');
    expect(c.mail.ses?.region).toBe('eu-central-2');
  });
});
