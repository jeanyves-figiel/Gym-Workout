// One live studio-voice recording with the environment's Polly keys (#395); prints the MP3 size or the AWS error.
import { pollySynthesizer } from '../src/coach/polly.ts';
import { ssml, voiceLines } from '../src/coach/voiceLines.ts';

const accessKeyId = process.env.POLLY_ACCESS_KEY_ID || process.env.SES_ACCESS_KEY_ID;
const secretAccessKey = process.env.POLLY_SECRET_ACCESS_KEY || process.env.SES_SECRET_ACCESS_KEY;
const region = process.env.POLLY_REGION || 'eu-central-1';
if (!accessKeyId || !secretAccessKey) {
  console.log('No Polly / SES keys set');
  process.exit(1);
}
const synth = pollySynthesizer({ region, accessKeyId, secretAccessKey }, fetch);
const line = voiceLines().find((l) => l.id === 'hype-final-0')!;
let failed = false;
for (const voice of ['Stephen', 'Joanna', 'Arthur']) {
  try {
    const mp3 = await synth(ssml(line), voice);
    console.log(`${voice}: OK ${mp3.length} bytes (${region})`);
  } catch (e) {
    failed = true;
    console.log(`${voice}: FAILED ${(e as Error).message}`);
  }
}
process.exit(failed ? 1 : 0);
