import pw from '@playwright/test'
const { chromium } = pw
const b = await chromium.launch()
const faces = ['Overview', 'Markets', 'Cities', 'Merchants', 'Me']
for (const [name, port] of [['before', 4335], ['after', 4333]]) {
  for (const vp of [{ width: 390, height: 568 }, { width: 1280, height: 800 }]) {
    const ctx = await b.newContext({ viewport: vp, colorScheme: 'dark', locale: 'en-US' })
    const p = await ctx.newPage()
    await p.goto(`http://localhost:${port}/byeharu-voyage/stats`)
    await p.waitForSelector('[data-testid="stats"]', { timeout: 180000 })
    await p.waitForTimeout(12000)
    for (const face of faces) {
      const tab = p.getByRole('tablist').getByRole('tab', { name: face, exact: true })
      if ((await tab.count()) > 0) {
        await tab.click()
        await p.waitForTimeout(2500)
      }
      const r = await p.evaluate(() => {
        const sheet = document.querySelector('[data-sheet]')
        const figs = [...document.querySelectorAll('span,div')].filter(
          (el) => el.children.length === 0 && el.textContent && /[0-9]/.test(el.textContent) && (el.className?.toString() ?? '').includes('tabular-nums'),
        )
        return { sh: sheet?.scrollHeight, ch: sheet?.clientHeight, figures: figs.length }
      })
      console.log(`${name} ${vp.width}x${vp.height} ${face}: sheet ${r.sh}/${r.ch} figures=${r.figures}`)
    }
    await ctx.close()
  }
}
await b.close()
