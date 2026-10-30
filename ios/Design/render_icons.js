// Renders ios/Design/*.svg app icons to 1024 PNGs: node ios/Design/render_icons.js <svgdir> <pngdir>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [src, out] = process.argv.slice(2);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const f of fs.readdirSync(src).filter(f => f.endsWith('.svg'))) {
    await p.goto('file://' + path.resolve(src, f));
    await p.screenshot({ path: path.join(out, f.replace('.svg', '.png')) });
  }
  await b.close();
})();
