import type { FastifyInstance } from 'fastify';
import type { Config } from '../config.ts';

/**
 * Public legal + support pages (#125): `/privacy`, `/terms`, `/support`.
 * Same URLs serve App Store Connect (Privacy Policy URL, Support URL, custom EULA) and the app's Account links.
 * Operator, address and contact come from env (`LEGAL_*`); unset values render as a visible placeholder.
 */
export const LEGAL_UPDATED = '2026-10-18';

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

interface Legal {
  app: string;
  operator: string;
  address: string;
  email: string;
  emailLink: string;
  law: string;
  venue?: string;
}

const MISSING = (what: string) => `<mark>[${what} to be completed]</mark>`;

const legalInfo = (config: Config): Legal => {
  const { operator, address, email, law, venue } = config.legal;
  return {
    app: esc(config.appName),
    operator: operator ? esc(operator) : MISSING('operator name'),
    address: address ? esc(address) : MISSING('postal address'),
    email: email ? esc(email) : MISSING('contact email'),
    emailLink: email ? `<a href="mailto:${esc(email)}">${esc(email)}</a>` : MISSING('contact email'),
    law: esc(law),
    venue: venue ? esc(venue) : undefined,
  };
};

const page = (app: string, title: string, gradient: string, body: string) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · ${app}</title>
<style>
:root{color-scheme:dark}
body{margin:0;background:#090a0e;color:#e9eaee;font:16px/1.6 -apple-system,system-ui,sans-serif}
main{max-width:720px;margin:0 auto;padding:20px 16px 48px}
header{border-radius:26px;padding:24px 22px;margin-bottom:20px;background:${gradient};color:#fff}
header h1{margin:0;font-size:32px;font-weight:900;letter-spacing:-.02em;line-height:1.1}
header p{margin:6px 0 0;opacity:.9;font-weight:600}
nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}
nav a{padding:6px 14px;border-radius:999px;background:#1b1d25;color:#fff;text-decoration:none;font-weight:700;font-size:14px}
nav a[aria-current]{background:#c6f432;color:#0b0c10}
h2{font-size:20px;font-weight:800;margin:28px 0 6px;color:#fff}
h3{font-size:16px;margin:18px 0 4px;color:#fff}
a{color:#c6f432}
li{margin:4px 0}
.card{background:#14161d;border-radius:20px;padding:16px 18px;margin:12px 0}
mark{background:#ffd60a;color:#000;padding:0 4px;border-radius:4px}
footer{margin-top:36px;font-size:13px;color:#8a8d99}
</style></head><body><main>
<nav><a href="/privacy"${title === 'Privacy Policy' ? ' aria-current="page"' : ''}>Privacy</a><a href="/terms"${title === 'Terms of Use' ? ' aria-current="page"' : ''}>Terms</a><a href="/support"${title === 'Support' ? ' aria-current="page"' : ''}>Support</a></nav>
${body}
<footer>${app} · Last updated ${LEGAL_UPDATED}</footer>
</main></body></html>`;

const privacy = (l: Legal) => `
<header><h1>Privacy Policy</h1><p>What ${l.app} stores, why, and your choices. No ads, no tracking, no data sales.</p></header>

<h2>1. Who is responsible</h2>
<div class="card">${l.operator}<br>${l.address}<br>${l.emailLink}</div>
<p>This policy covers the ${l.app} app for iPhone and Apple Watch and its server. It applies under the Swiss Federal Act on Data Protection (FADP) and, for users in the EU/EEA and UK, the GDPR.</p>

<h2>2. What we collect and why</h2>
<h3>Account</h3>
<ul>
<li>Email address, optional name, a password hash (never the password itself), or your Sign in with Apple identifier (Apple may give us a private relay email).</li>
<li>Date you accepted these terms, email verification status, one-time codes for sign-in, verification and password reset.</li>
<li>Signed-in devices (device name, sign-in and last-use dates) so you can see and sign them out.</li>
</ul>
<p>Why: to create your account, sign you in, keep it secure and sync it across your devices.</p>

<h3>Training and body data</h3>
<ul>
<li>Training profile: goals, schedule, equipment, experience, training style, plan and calendar changes.</li>
<li>Body metrics you enter: height, weight, birth year, optional sex and gender, pronouns and what the coach calls you, body figure choice, and dated body measurements (girths such as chest, waist, arms and thighs, body weight, body fat).</li>
<li>Sets you log (exercise, weight, reps, reps in reserve), completed sessions (exercises, duration, calories, average and maximum heart rate), personal-record attempts, climbing sessions you log (type, date, duration, effort, top grade, notes), other sport sessions you log or rate (sport, date, duration, effort, distance, notes), Hyrox races and sims recorded on your Apple Watch (each run, station and Roxzone time, counted reps, division, goal, average and maximum heart rate; sent from the iPhone, or straight from the Watch when it has Wi-Fi or cellular, using a key that can only upload sport sessions), your own workouts and exercises, including photos you take of machines, and machine setup notes per gym (settings, text and an optional photo, visible only to you).</li>
<li>Gym maps: your floor plan of a gym and the times you tap "Taken?" on a zone. Other members at the same gym see only the plan most members agree with and counts of busy taps, never who made them.</li>
</ul>
<p>Why: to generate your plan, suggest loads, show progress and sync across devices. Body and heart-rate data are health data; we process them only to provide these features, based on your consent, which you can withdraw by deleting the data or your account.</p>

<h3>Apple Health</h3>
<p>With your permission the app reads from Apple Health (weight, height, body fat, lean body mass, waist circumference, age, sex, resting heart rate, heart rate variability, VO2 max, sleep, daily steps and floors climbed (these stay on your iPhone), heart rate and energy during workouts, climbing and other sport workouts with their distance, ascent and route; routes stay on your iPhone) and writes your gym sessions, weight, height and, if you choose, body fat and waist circumference to it. Health data is also used to suggest first-time loads. Health data is used only to estimate calories, show readiness, add XP for daily walking and stairs, send at most one walking reminder a day, and track progress. Most of it stays on your iPhone; only the session summary above (duration, calories, average and maximum heart rate) and the sport sessions you rate (sport, date, duration, your effort, distance) are synced to our server with your training history. Apple Health data is never used for advertising, never sold, never shared with third parties for their own purposes and never stored in iCloud by us. You can change Health permissions at any time in the iOS Settings or the Health app.</p>

<h3>Community (optional)</h3>
<ul>
<li>Nickname, profile photo, short bio, your pronouns if you choose to show them, the wins you choose to share with captions, cheers, follows, blocks and reports.</li>
<li>Each post is visible to Only me, Members or Public (a public web link). You choose per post and can change or delete it at any time.</li>
<li>Photos are re-rendered on your device and stripped of location and other metadata on the server.</li>
</ul>
<p>Why: to run the community features you opt into, and to moderate content (reports are reviewed by the operator).</p>

<h3>Notifications</h3>
<p>Your device's push token, time zone and notification preferences, so we can send reminders and updates from people you follow. You can turn each type off in the app or in iOS Settings.</p>

<h3>Subscriptions</h3>
<p>Purchases are made and billed by Apple through the App Store. We never see your payment details; we receive only the subscription status (product, trial, renewal and expiry dates) needed to unlock features. Complimentary access granted by the operator is recorded on your account.</p>

<h3>Kept on your device only</h3>
<ul>
<li>Location for "Gyms near you": used only for the search with Apple Maps, never sent to our server.</li>
<li>Gym scan photos: sent once to Anthropic to spot the equipment, never stored on our server (only a count of scans per day).</li>
<li>Ask Coach: the conversation stays on this device. Our server passes each message to Anthropic and keeps only a count of messages per day (for the daily limit). When you talk to Coach, Apple speech recognition turns your voice into text, on your iPhone when it supports it (otherwise by Apple); no audio is sent to us or to Anthropic, only the words.</li>
<li>Coach voice: if you pick a studio voice and the coach calls you by your name, that first name (letters only) is recorded once by Amazon Polly as a short clip, kept on our server and on your iPhone; no account id or email is sent.</li>
<li>Face ID / Touch ID app lock: handled by iOS; we never receive biometric data.</li>
<li>MonkeyGrade link (optional): your MonkeyGrade sign-in token stays in this device's Keychain; the app reads your climbing sessions directly from MonkeyGrade.</li>
</ul>

<h2>3. What we do not do</h2>
<p>No advertising, no third-party analytics or tracking SDKs, no data brokers, no sale or rental of personal data, no tracking across other companies' apps or websites.</p>

<h2>4. Service providers</h2>
<p>We use a small number of providers that process data only on our behalf:</p>
<ul>
<li><b>Fly.io</b>: server hosting, database and its backups (Frankfurt, Germany).</li>
<li><b>Tigris Data</b> (object storage offered through Fly.io): encrypted copies of the daily database backup, encrypted on our server before upload with a key the provider does not have.</li>
<li><b>Amazon Web Services (SES)</b>: sending account emails (Zurich, Switzerland).</li>
<li><b>Amazon Web Services (Polly)</b>: records the studio coach voice lines and, if you choose it, the short call with your first name (Frankfurt, Germany).</li>
<li><b>Anthropic</b> (Claude): answers Ask Coach and reads gym scan photos. Only your chat messages, training settings (goal, level, session length, equipment, readiness), your pronouns and the call term you picked (Champ, Queen…; a first name is replaced on your iPhone, never sent), what the screen you ask from shows (an exercise, a chart, a day) or the scan photo are sent, never your name, email or account id; they are not used to train models.</li>
<li><b>Apple</b>: Sign in with Apple, push notifications (APNs), App Store purchases, Apple Health on your device.</li>
</ul>
<p>Some providers are part of groups based in the United States; transfers are covered by the EU/Swiss adequacy frameworks or standard contractual clauses. </p>

<h2>5. How we protect your data</h2>
<ul>
<li><b>In transit</b>: all traffic between the app and our server uses HTTPS (TLS).</li>
<li><b>On our server</b>: the database is stored on an encrypted disk. Passwords are stored only as salted scrypt hashes; one-time codes and sign-in tokens only as hashes; 2-step secrets and Apple sign-in tokens are encrypted (AES-256-GCM).</li>
<li><b>On your device</b>: your data is cached on your iPhone and Apple Watch so the app opens instantly and works offline, protected by iOS Data Protection; sign-in tokens are kept in the iOS Keychain on this device only. Changes made offline are kept and sent automatically when the connection is back. Signing out removes the cached data from the device.</li>
<li><b>Account security</b>: optional 2-step verification and passkeys, a fresh sign-in for sensitive changes (email, password, deleting the account), limits on sign-in attempts, a check of new passwords against known data breaches, and a list of signed-in devices you can sign out.</li>
<li><b>Access</b>: each account can reach only its own data. Only the operator can access the server, for maintenance, restoring backups and handling reports.</li>
<li><b>Backups</b>: the database is backed up daily so it can be restored after a failure: daily copies on the server (kept 7 days), disk snapshots by our host (kept up to 14 days) and an encrypted copy with Tigris Data (kept 30 days).</li>
</ul>

<h2>6. How long we keep data</h2>
<p>Account and training data are kept until you delete them or your account. One-time codes and expired sign-in tokens are purged automatically. When you delete your account, all of its data on our server is deleted immediately (including community posts, photos and push tokens) and Sign in with Apple is revoked; copies in backups (section 5) expire on their own and are all gone within 30 days. Moderation reports about other users may be kept as long as needed to handle them.</p>

<h2>7. Your rights</h2>
<ul>
<li><b>Access and portability</b>: Settings → Export my data downloads everything as JSON.</li>
<li><b>Correction</b>: edit your data in the app at any time.</li>
<li><b>Deletion</b>: Settings → Delete account removes your account and data permanently. If you can't use the app, email ${l.emailLink} from your account's address and we delete it for you.</li>
<li><b>Restoring lost data</b>: if workouts or other data went missing, email ${l.emailLink} from your account's address within 30 days; we can put back your data from our daily backups without affecting anyone else. A deleted account cannot be restored.</li>
<li><b>Withdraw consent / object / restrict</b>: contact ${l.emailLink}.</li>
<li><b>Complaint</b>: you can complain to the Swiss Federal Data Protection and Information Commissioner (FDPIC) or your local EU/EEA or UK data protection authority.</li>
</ul>

<h2>8. Children</h2>
<p>${l.app} is not directed at children under 16 and we do not knowingly collect their data. If you believe a child has created an account, contact us and we will delete it.</p>

<h2>9. Changes</h2>
<p>We will post updates on this page and change the date below. Significant changes will be announced in the app.</p>

<h2>10. Contact</h2>
<p>${l.emailLink}</p>
`;

const terms = (l: Legal) => `
<header><h1>Terms of Use</h1><p>End User License Agreement for ${l.app}.</p></header>

<p>These terms are an agreement between you and ${l.operator} ("we", "us"), not Apple. By creating an account or using ${l.app} you accept them and our <a href="/privacy">Privacy Policy</a>.</p>

<h2>1. Eligibility and account</h2>
<p>You must be at least 16 years old. Keep your sign-in details secure; you are responsible for activity on your account. You can delete your account at any time in Settings → Delete account.</p>

<h2>2. Health and safety</h2>
<p>${l.app} provides general fitness information and training plans. It is <b>not medical advice</b> and does not diagnose or treat any condition. Calorie, readiness and load estimates are approximations. Consult a doctor before starting a new training program, especially if you have a medical condition, injury or are pregnant. Stop exercising if you feel pain, dizziness or shortness of breath. You train at your own risk.</p>

<h2>3. License</h2>
<p>We grant you a personal, non-transferable, non-exclusive license to use ${l.app} on Apple devices you own or control, as permitted by the Usage Rules in the Apple Media Services Terms. You may not copy, modify, reverse-engineer, resell or redistribute the app, or use it to build a competing service.</p>

<h2>4. Subscriptions and free trial</h2>
<ul>
<li>Some features may require a paid subscription, billed by Apple to your Apple Account. Prices and periods are shown in the app before you buy.</li>
<li>Subscriptions renew automatically at the end of each period unless cancelled at least 24 hours before it ends. Your Apple Account is charged within 24 hours before renewal.</li>
<li>A free trial, when offered, converts to a paid subscription at its end unless cancelled at least 24 hours before. Any unused part of a trial is forfeited when you buy a subscription.</li>
<li>Manage or cancel in iOS Settings → your name → Subscriptions. Deleting the app or your account does not cancel a subscription.</li>
<li>Refunds are handled by Apple under its policies (reportaproblem.apple.com).</li>
<li>We may grant complimentary access to some accounts at our discretion; it can be ended at any time.</li>
</ul>

<h2>5. Community and your content</h2>
<p>You keep ownership of what you post (nickname, photo, bio, captions, shared workouts). You give us a worldwide, non-exclusive, royalty-free license to host and display it to the audience you choose, only to run the service; it ends when you delete the content.</p>
<p><b>There is no tolerance for objectionable content or abusive users.</b> You must not post content that is hateful, harassing, threatening, sexually explicit, violent, discriminatory, illegal, infringing, spam, or that shares others' personal data. You must follow the in-app Community guidelines. Users can report content and block other users. We review reports, remove offending content and may suspend or ban accounts that break these rules.</p>

<h2>6. Acceptable use</h2>
<p>Do not misuse the service: no automated scraping, attacks, attempts to access other accounts, or interference with its operation.</p>

<h2>7. Third-party services</h2>
<p>Apple Health, Apple Maps, Sign in with Apple and the optional MonkeyGrade link are governed by their own terms. You must comply with applicable third-party terms when using the app.</p>

<h2>8. Availability and changes</h2>
<p>We work to keep ${l.app} available and your data safe, but the service is provided "as is" and may change or be interrupted. We may update these terms; we will post changes here and, if significant, in the app. Continued use means acceptance.</p>

<h2>9. Liability</h2>
<p>To the extent permitted by law, we are not liable for indirect or consequential damages, or for injuries from exercise. Our total liability is limited to the amount you paid for the app in the 12 months before the claim. Nothing limits liability for gross negligence, intent or anything that cannot be limited by law, or your statutory consumer rights.</p>

<h2>10. Termination</h2>
<p>You can stop using the app and delete your account at any time. We may suspend or terminate accounts that break these terms.</p>

<h2>11. Apple</h2>
<ul>
<li>These terms are between you and us only, not Apple. We, not Apple, are solely responsible for ${l.app} and its content.</li>
<li>Apple has no obligation to provide maintenance or support for the app. Support is provided by us (see <a href="/support">Support</a>).</li>
<li>If the app fails to conform to any applicable warranty, you may notify Apple and Apple will refund the purchase price (if any); to the maximum extent permitted by law Apple has no other warranty obligation.</li>
<li>We, not Apple, are responsible for addressing any claims relating to the app or your use of it, including product liability, legal or regulatory non-compliance, and consumer protection or privacy claims.</li>
<li>We, not Apple, are responsible for the investigation, defense, settlement and discharge of any third-party claim that the app infringes intellectual property rights.</li>
<li>You confirm you are not located in a country subject to a U.S. Government embargo or designated as "terrorist supporting", and are not on any U.S. Government list of prohibited or restricted parties.</li>
<li>Apple and its subsidiaries are third-party beneficiaries of these terms and may enforce them against you.</li>
</ul>

<h2>12. Governing law</h2>
<p>These terms are governed by the laws of ${l.law}, without prejudice to mandatory consumer protection laws of your country of residence.${l.venue ? ` Place of jurisdiction is ${l.venue}, subject to any mandatory place of jurisdiction for consumers.` : ''}</p>

<h2>13. Contact</h2>
<div class="card">${l.operator}<br>${l.address}<br>${l.emailLink}</div>
`;

const support = (l: Legal) => `
<header><h1>Support</h1><p>Help with ${l.app}. We usually reply within a few days.</p></header>

<div class="card"><b>Contact</b><br>${l.emailLink}<br><span style="color:#8a8d99">Include the email of your account (or "Sign in with Apple") and your iPhone model.</span></div>

<h2>Common questions</h2>
<h3>How do I delete my account?</h3>
<p>In the app: Settings → Delete account. It permanently deletes your account and all its data from our server at once and revokes Sign in with Apple. Can't use the app? Email ${l.emailLink} from your account's email address and we delete it for you. Copies in our backups expire on their own within 30 days.</p>
<h3>Some of my data is missing. Can you restore it?</h3>
<p>Email ${l.emailLink} from your account's email address within 30 days, saying what is missing and roughly when you last saw it. We restore your data from our daily backups; nothing else in your account or anyone else's is changed. A deleted account cannot be restored.</p>
<h3>How do I get a copy of my data?</h3>
<p>Settings → Export my data creates a JSON file with your account, training profile, logs, history, personal records, measurements, climbs, other sport sessions and machine setup notes (with their photos).</p>
<h3>I forgot my password.</h3>
<p>On the sign-in screen tap "Forgot password?" and follow the code sent by email.</p>
<h3>How do I cancel my subscription?</h3>
<p>iOS Settings → your name → Subscriptions → ${l.app} → Cancel. Refunds: <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.</p>
<h3>How do I report a post or a member?</h3>
<p>In Community, use Report on the post or the member page, or Block to hide each other both ways. Serious issues: email ${l.emailLink}.</p>
<h3>Apple Health or Apple Watch data is missing.</h3>
<p>Check iOS Settings → Health → Data Access &amp; Devices → ${l.app} and allow the categories you want.</p>

<h2>Legal</h2>
<p><a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Use</a></p>
`;

export const legalRoutes = (app: FastifyInstance, config: Config) => {
  const l = legalInfo(config);
  const pages: Record<string, string> = {
    '/privacy': page(l.app, 'Privacy Policy', 'linear-gradient(135deg,#7a3dff,#ff4dd9)', privacy(l)),
    '/terms': page(l.app, 'Terms of Use', 'linear-gradient(135deg,#ff9e1a,#ff5c3d)', terms(l)),
    '/support': page(l.app, 'Support', 'linear-gradient(135deg,#14c78f,#1f80ff)', support(l)),
  };
  for (const [path, html] of Object.entries(pages)) {
    app.get(path, async (_req, reply) =>
      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .header('X-Content-Type-Options', 'nosniff')
        .header('Cache-Control', 'public, max-age=3600')
        .send(html),
    );
  }
};
