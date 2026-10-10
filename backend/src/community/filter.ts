/**
 * Objectionable-text filter for community content (App Store 1.2). Deliberately small and
 * conservative: slurs, sexual terms and common insults (EN/FR/DE), matched on whole words after
 * folding accents and common leetspeak. Everything else is handled by reports + block.
 */
const WORDS = [
  // insults / profanity
  'fuck', 'fucker', 'fucking', 'motherfucker', 'shit', 'bitch', 'bastard', 'asshole', 'cunt', 'dick', 'dickhead', 'prick',
  'whore', 'slut', 'wanker', 'twat', 'retard', 'retarded',
  'connard', 'connasse', 'salope', 'pute', 'putain', 'encule', 'enculer', 'batard', 'merde', 'nique', 'ntm', 'fdp',
  'arschloch', 'hurensohn', 'fotze', 'wichser', 'schlampe',
  // sexual
  'porn', 'porno', 'xxx', 'nude', 'nudes', 'blowjob', 'cum', 'pussy', 'penis', 'vagina', 'boobs', 'onlyfans',
  // slurs
  'nigger', 'nigga', 'faggot', 'fag', 'tranny', 'kike', 'spic', 'chink', 'negre', 'pede', 'tapette', 'bougnoule',
  // violence
  'kys', 'killyourself',
];
const SET = new Set(WORDS);
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', $: 's', '!': 'i' };

const plain = (s: string) => s.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
const leet = (s: string) => s.replace(/[013457@$!]/g, (c) => LEET[c] ?? c);

/** True when `text` contains a blocked word (also catches "f.u.c.k" and "fuuuck"-style spellings). */
export const isObjectionable = (text: string | null | undefined): boolean => {
  if (!text) return false;
  const p = plain(text);
  return hasWord(p) || hasWord(leet(p));
};

const hasWord = (f: string): boolean => {
  const tokens = f.split(/[^\p{L}]+/u).filter(Boolean);
  for (const t of tokens) {
    if (SET.has(t) || SET.has(t.replace(/(.)\1+/g, '$1'))) return true;
  }
  // spaced/dotted spellings ("f.u.c.k", "s h i t"): join runs of single-letter tokens
  let run = '';
  for (const t of [...tokens, '']) {
    if (t.length === 1) run += t;
    else {
      if (run.length > 1 && SET.has(run)) return true;
      run = '';
    }
  }
  return false;
};
