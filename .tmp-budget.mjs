import pw from '@playwright/test'
const { chromium } = pw
const b = await chromium.launch()
const ctx = await b.newContext({ viewport: { width: 390, height: 568 }, colorScheme: 'dark', locale: 'en-US' })
const p = await ctx.newPage()
await p.goto('http://localhost:4333/byeharu-voyage/stats')
await p.waitForSelector('[data-testid="stats-overview"]', { timeout: 180000 })
await p.waitForTimeout(12000)
console.log(JSON.stringify(await p.evaluate(() => {
  const h = (sel) => { const el = document.querySelector(sel); return el ? Math.round(el.getBoundingClientRect().height) : null }
  const face = document.querySelector('[data-testid="stats-overview"]')
  const blocks = [...face.children].map((c) => Math.round(c.getBoundingClientRect().height))
  return { sheet: { sh: document.querySelector('[data-sheet]')?.scrollHeight, ch: document.querySelector('[data-sheet]')?.clientHeight }, live: h('[data-testid="stats-live"]'), seg: h('[role="tablist"]'), face: Math.round(face.getBoundingClientRect().height), blocks }
})))
await b.close()
