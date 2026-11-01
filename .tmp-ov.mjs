import pw from '@playwright/test'
const { chromium } = pw
const b = await chromium.launch()
const ctx = await b.newContext({ viewport: { width: 390, height: 568 }, colorScheme: 'dark', locale: 'en-US' })
const p = await ctx.newPage()
await p.goto('http://localhost:4333/byeharu-voyage/stats')
await p.waitForSelector('[data-testid="stats-overview"]', { timeout: 180000 })
await p.waitForTimeout(12000)
console.log(JSON.stringify(await p.evaluate(() => {
  const sheet = document.querySelector('[data-sheet]')
  const figs = [...document.querySelectorAll('span,div')].filter((el) => el.children.length === 0 && el.textContent && /[0-9]/.test(el.textContent) && (el.className?.toString() ?? '').includes('tabular-nums'))
  const face = document.querySelector('[data-testid="stats-overview"]')
  return { sh: sheet?.scrollHeight, ch: sheet?.clientHeight, figures: figs.length, face: Math.round(face.getBoundingClientRect().height), blocks: [...face.children].map((c) => Math.round(c.getBoundingClientRect().height)) }
})))
await b.close()
