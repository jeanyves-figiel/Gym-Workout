import { signV4 } from '../ses.ts';
import type { Fetch } from '../appleTokens.ts';

export interface PollyCredentials {
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
}

/** Text to MP3 with one voice (#395). */
export type Synthesize = (ssml: string, voiceId: string) => Promise<Buffer>;

/**
 * Amazon Polly `SynthesizeSpeech`, neural engine, SigV4-signed over HTTPS. IAM: `polly:SynthesizeSpeech` only.
 */
export const pollySynthesizer = (creds: PollyCredentials, fetchFn: Fetch, now: () => Date = () => new Date()): Synthesize =>
  async (ssml, voiceId) => {
    const url = new URL(`https://polly.${creds.region}.amazonaws.com/v1/speech`);
    const body = JSON.stringify({ Engine: 'neural', OutputFormat: 'mp3', SampleRate: '24000', Text: ssml, TextType: 'ssml', VoiceId: voiceId });
    const amzDate = now().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const headers: Record<string, string> = { 'content-type': 'application/json', host: url.host, 'x-amz-date': amzDate };
    const authorization = signV4({ method: 'POST', url, headers, body, service: 'polly', region: creds.region, accessKeyId: creds.accessKeyId, secretAccessKey: creds.secretAccessKey, amzDate });
    const res = await fetchFn(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-amz-date': amzDate, authorization },
      body,
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Polly SynthesizeSpeech failed: HTTP ${res.status} ${text.slice(0, 200)}`.trim());
    }
    return Buffer.from(await res.arrayBuffer());
  };
