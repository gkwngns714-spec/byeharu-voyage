import pw from '@playwright/test'
const { chromium } = pw
const b = await chromium.launch()
for (const vp of [{ width: 390, height: 568 }, { width: 1280, height: 800 }]) {
  const ctx = await b.newContext({ viewport: vp, colorScheme: 'dark', locale: 'en-US' })
  const p = await ctx.newPage()
  await p.goto('http://localhost:4333/byeharu-voyage/stats', { timeout: 30000 })
  try { await p.waitForSelector('[data-testid="stats-overview"]', { timeout: 30000 }) } catch { console.log('NOT READY', vp.width); await ctx.close(); continue }
  await p.waitForTimeout(3000)
  console.log(vp.width, JSON.stringify(await p.evaluate(() => {
    const sheet = document.querySelector('[data-sheet]')
    const figs = [...document.querySelectorAll('span,div')].filter((el) => el.children.length === 0 && el.textContent && /[0-9]/.test(el.textContent) && (el.className?.toString() ?? '').includes('tabular-nums'))
    const face = document.querySelector('[data-testid="stats-overview"]')
    return { sh: sheet?.scrollHeight, ch: sheet?.clientHeight, figures: figs.length, face: Math.round(face.getBoundingClientRect().height), blocks: [...face.children].map((c) => Math.round(c.getBoundingClientRect().height)) }
  })))
  await ctx.close()
}
await b.close()
