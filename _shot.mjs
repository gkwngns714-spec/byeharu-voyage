import { chromium } from '@playwright/test';
const out = 'C:/Users/gkwng/AppData/Local/Temp/claude/C--Windows-System32/eccf5855-1f56-4703-b874-ac25ab8aee95/scratchpad/';
const b = await chromium.launch();
const p = await (await b.newContext({ viewport:{width:390,height:844} })).newPage();
await p.goto('http://localhost:4173/byeharu-voyage/market', { waitUntil:'load' });
await p.waitForFunction(()=>!document.querySelector('.animate-pulse')&&!document.body.innerText.includes('Opening the world'),null,{timeout:200000}).catch(()=>console.log('!! timeout'));
await p.waitForTimeout(3500);
const t = await p.innerText('body');
const i = t.search(/PAYS|WORTH|ROUTE|CARRY/i);
console.log('--- text from first route mention ---');
console.log(t.slice(i, i+700).replace(/\n{2,}/g,'\n'));
// scroll to the bottom of the screen's own scroll container
await p.evaluate(() => { const el=[...document.querySelectorAll('*')].find(e=>e.scrollHeight>e.clientHeight+50 && getComputedStyle(e).overflowY==='auto'); if(el) el.scrollTop = el.scrollHeight; });
await p.waitForTimeout(1200);
await p.screenshot({ path: out+'f_market_bottom.png' });
await b.close();
