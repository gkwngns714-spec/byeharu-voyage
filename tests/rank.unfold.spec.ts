import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, openFace, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// RANK, UNFOLDED — the owner's law, measured on both faces at three glasses (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded … make things unfolded, minimize scrolling, everything compact with full info."*
// (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8; docs/dev-log/2026-11-01-unfold-rank.md.) Rank was the two
// face tabs over ONE summary row (`Captains 10 · Open`); the board was behind the press. It is now the face tabs over ONE
// list panel (src/components/ui/ListPanel.tsx; src/features/rank/RankScreen.tsx): YOUR line pinned in the panel's header,
// the board scrolling under it, the fame tray a sibling outside the scroller.
//
//   U2  the page and the Sheet never scroll; the board scrolls inside its panel;
//   U1  the panel stands inside the glass with at least min(rows, N) rows WHOLE before any press;
//   U3  nothing removed: your line, the rows, the countries, the face tabs and the settled caption are all there;
//   U5  no two text boxes cross; cut text carries its full text;
//   U8  a press on your line opens the fame tray, and closing it leaves the board as it was.

/** Rows WHOLE in the panel's body, by glass width (the budget table in the dev-log). */
const NEED: Record<number, number> = { 390: 6, 320: 3, 1280: 8 }

const FACES = [
  { tab: 'Captains', panel: 'rank-list' },
  { tab: 'Countries', panel: 'rank-countries' },
] as const

for (const glass of GLASSES) {
  test(`both Rank faces are unfolded at ${glass.width}×${glass.height}: flat page, the board on the glass, nothing removed, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('rank')
    await ready(page)
    await expect(page.getByTestId('rank')).toBeVisible()

    const failures: string[] = []
    for (const face of FACES) {
      await openFace(page, face.tab)
      const where = `${face.tab} @${glass.width}×${glass.height}`
      // the rows of this panel carry no id of their own on Captains (the board's), so the whole-row count is read here
      const m = await readGlass(page, face.panel, null)
      const rows = await page.getByTestId(face.panel).locator('[data-list-body] [data-row-line]').count()
      const whole = await page.getByTestId(face.panel).evaluate((panel) => {
        const body = panel.querySelector('[data-list-body]')
        if (!body) return 0
        const b = body.getBoundingClientRect()
        return [...body.querySelectorAll('[data-row-line]')].filter((r) => {
          const x = r.getBoundingClientRect()
          return x.top >= b.top - 1 && x.bottom <= b.bottom + 1
        }).length
      })
      console.log(`UNFOLD ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, rows ${whole}/${rows}`)
      if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
      if (m.doc.sw > m.doc.cw + 1) failures.push(`${where}: the document scrolls sideways`)
      if (m.sheet === null) failures.push(`${where}: no Sheet`)
      else if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
      for (const s of m.sideways) failures.push(`${where}: ${s} scrolls sideways`)
      if (!m.rows.found) failures.push(`${where}: no list panel`)
      else {
        if (!m.rows.inView) failures.push(`${where}: the panel is not inside the glass`)
        const need = Math.min(rows, NEED[glass.width])
        if (whole < need) failures.push(`${where}: ${whole} whole rows of ${rows}; the law is ${need}`)
      }
      if ((await page.getByRole('tablist').first().getByRole('tab').count()) !== FACES.length) failures.push(`${where}: the face tabs are not all there`)
      for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
      for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
    }
    expect(failures, 'the Rank faces are not unfolded').toEqual([])
  })
}

test('your line stays on the glass while the board scrolls; a press on it opens the fame tray and closing leaves the board', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[1])
  await page.goto('rank')
  await ready(page)
  await expect(page.getByTestId('rank-list')).toBeVisible()

  const you = page.getByTestId('rank-you')
  await expect(you).toBeVisible()
  const before = await you.boundingBox()
  // scroll the board to its end: the pinned line does not move
  await page.getByTestId('rank-list').locator('[data-list-body]').evaluate((el) => {
    el.scrollTop = el.scrollHeight
  })
  expect(await you.boundingBox(), 'the pinned line moved while the board scrolled').toEqual(before)

  await you.click()
  const tray = page.getByTestId('fame-tray')
  await expect(tray).toBeVisible()
  await expect(tray).toContainText(/Trade/)
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  expect(await you.boundingBox(), 'opening and closing the tray moved the pinned line').toEqual(before)
})
