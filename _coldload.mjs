// THROWAWAY AUDIT SCRIPT — cold-load reliability probe. Delete when done.
import { chromium } from 'playwright';
import fs from 'node:fs';

const URL = 'http://localhost:4173/byeharu-voyage/';
const N = Number(process.argv[2] || 10);
const OUT = process.argv[3];
const results = [];

const browser = await chromium.launch({ headless: true });
for (let i = 0; i < N; i++) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
  page.on('pageerror', (e) => logs.push('PAGEERROR: ' + String(e)));
  const t0 = Date.now();
  let r = { i, ok: false, ms: null, err: null, body: null };
  try {
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForFunction(
      () => {
        const b = document.body;
        if (!b) return false;
        if (document.querySelector('.animate-pulse')) return false;
        if (b.innerText.includes('Opening the world')) return false;
        return b.innerText.trim().length > 20;
      },
      undefined,
      { timeout: 180000 },
    );
    // give the post-found reload a chance
    await page.waitForTimeout(6000);
    const txt = await page.evaluate(() => document.body.innerText);
    r.ok = !/E_WORLD_UNAVAILABLE|Aborted\(\)|could not open the world|world is unavailable/i.test(txt);
    r.ms = Date.now() - t0;
    r.body = txt.slice(0, 400);
  } catch (e) {
    r.err = String(e).slice(0, 300);
    try { r.body = (await page.evaluate(() => document.body.innerText)).slice(0, 600); } catch { /* */ }
  }
  r.errLogs = logs.filter((l) => /PAGEERROR|error:|Aborted|E_WORLD/i.test(l)).slice(0, 10);
  r.dbLogs = logs.filter((l) => l.includes('[db]') || l.includes('[rpc]')).slice(0, 10);
  results.push(r);
  fs.writeFileSync(OUT, JSON.stringify(results, null, 1));
  console.log(i, r.ok ? 'OK ' + r.ms + 'ms' : 'FAIL ' + (r.err || 'body-refusal'));
  await ctx.close();
}
await browser.close();
console.log('DONE');
