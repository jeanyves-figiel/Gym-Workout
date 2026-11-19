// Renders the share art (#1113) into backend/content/share/. Dev only, needs Playwright + Chromium:
//   node backend/scripts/share-art/render.mjs <dir with 01-week.jpg 03-coach-chat.jpg 08-fuel.jpg>
// Screens: the 6.9" App Store set (/mnt/project-files/app-store-screenshots/iphone-6.9). Icon: the app's AppIcon-1024.
import { createRequire } from 'node:module';
import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const { chromium } = createRequire(import.meta.url)('playwright');
const here = dirname(fileURLToPath(import.meta.url));
const shots = resolve(process.argv[2] ?? '/mnt/project-files/app-store-screenshots/iphone-6.9');
const out = resolve(here, '../../content/share');
const work = join(here, '.work');
rmSync(work, { recursive: true, force: true });
mkdirSync(join(work, 'shots'), { recursive: true });
cpSync(join(here, 'art.html'), join(work, 'art.html'));
cpSync(resolve(here, '../../../ios/MonkeyWorkout/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'), join(work, 'icon.png'));
for (const f of ['01-week.jpg', '03-coach-chat.jpg', '08-fuel.jpg']) cpSync(join(shots, f), join(work, 'shots', f));
mkdirSync(out, { recursive: true });
const sizes = { link: [1200, 630], story: [1080, 1920], post: [1080, 1080], event: [1920, 1080] };
const browser = await chromium.launch();
for (const [k, [width, height]] of Object.entries(sizes)) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.goto(`file://${join(work, 'art.html')}?k=${k}`);
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: join(out, `${k}.jpg`), type: 'jpeg', quality: 86 });
  await page.close();
}
await browser.close();
rmSync(work, { recursive: true, force: true });
console.log('wrote', Object.keys(sizes).map((k) => `${k}.jpg`).join(', '), 'to', out);
