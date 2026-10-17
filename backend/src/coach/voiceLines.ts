import { createHash } from 'node:crypto';

/**
 * Studio coach voices (#395): every line the in-workout coach can say with a studio voice, recorded once per voice with
 * Amazon Polly neural and cached. No numbers or exercise names, so one recording fits every member; the app's subtitle
 * bubble shows the same words, and the set card / record burst show the numbers.
 */
export type CoachStyle = 'chill' | 'hype' | 'drill';
export const STYLES: CoachStyle[] = ['chill', 'hype', 'drill'];

/** Moment kinds, matching `CoachMoment.studioKind` in the app. */
export const KINDS = [
  'start',
  'set',
  'set-more',
  'set-heavier',
  'set-same',
  'final',
  'halfway',
  'rest',
  'record',
  'record-heavier',
  'finish',
] as const;
export type CoachKind = (typeof KINDS)[number];

export const VOICE_LINES: Record<CoachStyle, Record<CoachKind, string[]>> = {
  chill: {
    start: ['Nice to see you. Easy start, good form, we build from there.', "Let's go. One exercise at a time.", 'Breathe, settle in. First set when you are ready.'],
    set: ['Nice and steady.', 'Good set. Shake it out, breathe.', 'Good set. Recover well.'],
    'set-more': ['One more rep than last time. Nice.', 'More reps than last time. Lovely work.'],
    'set-heavier': ['Heavier than last time. Nicely done.', 'More weight than last time, and it looked smooth.'],
    'set-same': ['Same as last time. Solid.', 'Matched last time. Steady progress.'],
    final: ['Last set. Make it your best one.', 'Final set. Smooth and controlled.', 'One more set, then this one is done.'],
    halfway: ["Halfway there. You're doing great.", 'Half done. Keep the pace easy.', "That's half. Sip some water."],
    rest: ['Ten seconds. Get comfortable on the machine.', 'Almost time. Ten seconds.', 'Ten seconds, deep breath.'],
    record: ['New best set. Well done.', "That's a record. Enjoy it."],
    'record-heavier': ['New personal record. Heavier than ever. Well done.', 'Your heaviest ever. Enjoy that one.'],
    finish: ['Workout done. Rest well.', 'All done. Good work today, be proud.'],
  },
  hype: {
    start: ["Let's go! Let's own every exercise today.", 'Game on! Time for a great workout.', "You showed up. That's the hardest rep. Let's do this!"],
    set: ['Boom! Set done!', "That's how it's done!", 'Strong set! Keep that energy!'],
    'set-more': ['Yes! One more rep than last time!', 'More reps than last time! Love it!'],
    'set-heavier': ['Boom! Heavier than last time!', 'More weight, same power! Yes!'],
    'set-same': ['Right on last time! Now beat it!', 'Matched last time! Keep pushing!'],
    final: ['Last set! Make it count!', 'Final set! Empty the tank!', 'This is the one! Last set, go!'],
    halfway: ["Halfway! You're past the hump!", "Half done! Let's finish this!", 'Halfway and flying!'],
    rest: ['Ten seconds! Get ready!', 'Ten seconds, here we go again!', 'Get set, ten seconds!'],
    record: ["New record! You're on fire!", 'Personal record! Beast mode!'],
    'record-heavier': ['Beast mode! Heaviest you have ever lifted!', 'New personal record! More weight than ever!'],
    finish: ['Done! Workout crushed! Legend!', 'Workout crushed! See you next time, champ!'],
  },
  drill: {
    start: ['No excuses. Move.', 'Clock is running. First set, now.', 'Focus. Every rep clean.'],
    set: ['Logged. Next.', "Recover. Don't get comfortable.", 'Done. Rest is earned, not given.'],
    'set-more': ['One more rep than last time. Again.', 'More reps than last time. Expected.'],
    'set-heavier': ['Heavier than last time. Now own it.', 'More weight. Good. Keep it clean.'],
    'set-same': ['Same as last time. Not good enough. Next set, more.', 'Matched last time. Raise it.'],
    final: ['Final set. Leave nothing.', 'Last set. Every rep. Full range.', "Final set. Finish strong or don't finish."],
    halfway: ['Halfway. No slowing down.', 'Half done. The second half decides.', 'Halfway. Stay sharp.'],
    rest: ['Ten seconds. Hands on.', 'Ten. Get in position.', 'Ten seconds. Up.'],
    record: ['Record. Now own it.', "New best. That's the standard now."],
    'record-heavier': ['Record. Heaviest ever. Now beat it next time.', 'New max weight. That is the new floor.'],
    finish: ['Done. Eat, sleep, repeat.', 'Workout complete. Recover. Come back stronger.'],
  },
};

export interface StudioVoice {
  /** Amazon Polly voice id. */
  id: string;
  name: string;
  gender: 'female' | 'male';
  /** us, gb, au, ie, in, za, nz */
  accent: string;
  label: string;
  /** Polly language code for the voice. */
  language: string;
}

/** Polly neural English voices. */
export const STUDIO_VOICES: StudioVoice[] = [
  { id: 'Joanna', name: 'Joanna', gender: 'female', accent: 'us', label: 'American', language: 'en-US' },
  { id: 'Ruth', name: 'Ruth', gender: 'female', accent: 'us', label: 'American, bright', language: 'en-US' },
  { id: 'Matthew', name: 'Matthew', gender: 'male', accent: 'us', label: 'American', language: 'en-US' },
  { id: 'Gregory', name: 'Gregory', gender: 'male', accent: 'us', label: 'American, deep', language: 'en-US' },
  { id: 'Stephen', name: 'Stephen', gender: 'male', accent: 'us', label: 'American, warm', language: 'en-US' },
  { id: 'Amy', name: 'Amy', gender: 'female', accent: 'gb', label: 'British', language: 'en-GB' },
  { id: 'Arthur', name: 'Arthur', gender: 'male', accent: 'gb', label: 'British', language: 'en-GB' },
  { id: 'Olivia', name: 'Olivia', gender: 'female', accent: 'au', label: 'Australian', language: 'en-AU' },
  { id: 'Niamh', name: 'Niamh', gender: 'female', accent: 'ie', label: 'Irish', language: 'en-IE' },
  { id: 'Kajal', name: 'Kajal', gender: 'female', accent: 'in', label: 'Indian', language: 'en-IN' },
  { id: 'Ayanda', name: 'Ayanda', gender: 'female', accent: 'za', label: 'South African', language: 'en-ZA' },
  { id: 'Aria', name: 'Aria', gender: 'female', accent: 'nz', label: 'New Zealand', language: 'en-NZ' },
];

export interface VoiceLine {
  /** `<style>-<kind>-<n>`, stable while the line list keeps its order. */
  id: string;
  text: string;
  /** Changes when the text changes, so cached recordings are redone. */
  hash: string;
  style: CoachStyle;
  kind: CoachKind;
}

const RATE: Record<CoachStyle, string> = { chill: '95%', hype: '108%', drill: '105%' };

const escapeXml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/'/g, '&apos;').replace(/"/g, '&quot;');

/** What Polly reads for a line. */
export const ssml = (line: VoiceLine) => `<speak><prosody rate="${RATE[line.style]}">${escapeXml(line.text)}</prosody></speak>`;

export const voiceLines = (): VoiceLine[] =>
  STYLES.flatMap((style) =>
    KINDS.flatMap((kind) =>
      VOICE_LINES[style][kind].map((text, n) => {
        const line = { id: `${style}-${kind}-${n}`, text, style, kind, hash: '' };
        line.hash = createHash('sha256').update(ssml(line)).digest('hex').slice(0, 16);
        return line;
      }),
    ),
  );
