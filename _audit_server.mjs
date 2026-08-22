// THROWAWAY AUDIT HARNESS — read-only audit driver. Delete when done.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const SP = process.env.AUDIT_SP;
const CMD = path.join(SP, 'cmd.mjs');
const OUT = path.join(SP, 'out.json');
const SHOTS = path.join(SP, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

const URL_BASE = process.env.AUDIT_URL || 'http://localhost:4173/byeharu-voyage/';

const browser = await chromium.launch({ headless: true });
let ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
let page = await ctx.newPage();

const logs = [];
function attach(p) {
  p.on('console', (m) => logs.push({ t: Date.now(), type: m.type(), text: m.text() }));
  p.on('pageerror', (e) => logs.push({ t: Date.now(), type: 'pageerror', text: String(e && e.stack || e) }));
  p.on('requestfailed', (r) => logs.push({ t: Date.now(), type: 'requestfailed', text: r.url() + ' :: ' + (r.failure() && r.failure().errorText) }));
}
attach(page);

const api = {
  get page() { return page; },
  get ctx() { return ctx; },
  browser,
  logs,
  SHOTS,
  URL_BASE,
  async freshContext() {
    try { await ctx.close(); } catch { /* ignore */ }
    ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
    page = await ctx.newPage();
    attach(page);
    return page;
  },
  async waitReady(timeout = 200000) {
    const t0 = Date.now();
    await page.waitForFunction(
      () => {
        const b = document.body;
        if (!b) return false;
        if (document.querySelector('.animate-pulse')) return false;
        if (b.innerText.includes('Opening the world')) return false;
        return b.innerText.trim().length > 20;
      },
      undefined,
      { timeout }
    );
    return Date.now() - t0;
  },
  async text() { return await page.evaluate(() => document.body.innerText); },
  async shot(name) {
    const f = path.join(SHOTS, name.endsWith('.png') ? name : name + '.png');
    await page.screenshot({ path: f, fullPage: false });
    return f;
  },
  async shotFull(name) {
    const f = path.join(SHOTS, name.endsWith('.png') ? name : name + '.png');
    await page.screenshot({ path: f, fullPage: true });
    return f;
  },
};

let lastMtime = 0;
if (fs.existsSync(CMD)) lastMtime = fs.statSync(CMD).mtimeMs;

fs.writeFileSync(path.join(SP, 'server-ready.txt'), 'ready ' + new Date().toISOString());
console.log('AUDIT SERVER READY');

// eslint-disable-next-line no-constant-condition
while (true) {
  await new Promise((r) => setTimeout(r, 300));
  if (!fs.existsSync(CMD)) continue;
  const m = fs.statSync(CMD).mtimeMs;
  if (m === lastMtime) continue;
  lastMtime = m;
  const src = fs.readFileSync(CMD, 'utf8');
  const started = Date.now();
  let result;
  try {
    const mod = await import('data:text/javascript;base64,' + Buffer.from(src).toString('base64'));
    result = { id: mod.ID || null, ok: true, value: await mod.default(api) };
  } catch (e) {
    const idm = /export const ID='(\d+)'/.exec(src);
    result = { id: idm ? idm[1] : null, ok: false, error: String(e && e.stack || e) };
  }
  result.ms = Date.now() - started;
  fs.writeFileSync(OUT, JSON.stringify(result, null, 2));
  console.log('[cmd done]', result.ok ? 'ok' : 'ERR', result.ms + 'ms');
}
