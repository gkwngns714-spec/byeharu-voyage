// THROWAWAY AUDIT SCRIPT — first-boot sequence probe. Delete when done.
import { chromium } from 'playwright';

const URL = 'http://localhost:4173/byeharu-voyage/';
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
const marks = [];
page.on('framenavigated', (f) => { if (f === page.mainFrame()) marks.push(['NAV', Date.now(), f.url()]); });
page.on('console', (m) => marks.push(['LOG', Date.now(), m.text().slice(0, 120)]));
const t0 = Date.now();
await page.goto(URL, { waitUntil: 'domcontentloaded' });
const samples = [];
for (let i = 0; i < 90; i++) {
  await page.waitForTimeout(700);
  const s = await page.evaluate(() => {
    const b = document.body;
    return {
      pulse: !!document.querySelector('.animate-pulse'),
      nav: performance.getEntriesByType('navigation').length,
      txt: (b ? b.innerText : '').replace(/\s+/g, ' ').slice(0, 110),
    };
  });
  samples.push([Date.now() - t0, s.pulse, s.nav, s.txt]);
  if (!s.pulse && /Gaivota/.test(s.txt)) break;
}
console.log(JSON.stringify({ marks: marks.map(([k, t, v]) => [k, t - t0, v]), samples }, null, 1));
await browser.close();
