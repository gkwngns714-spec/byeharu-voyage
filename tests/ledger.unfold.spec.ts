import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, openFace, playedWorld, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LEDGER (History), UNFOLDED — the owner's law, measured on every face at three glasses (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded … make things unfolded, minimize scrolling, everything compact with full info."*
// (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8; docs/dev-log/2026-11-01-unfold-ledger.md.) The History
// tab was four face tabs over ONE summary row (`History 50 · Open`); the feed was behind the press. It is now the face
// tabs over ONE list panel (src/components/ui/ListPanel.tsx; src/features/ledger/LedgerScreen.tsx):
//
//   U2  the page and the Sheet never scroll; the feed scrolls inside its panel;
//   U1  the panel stands inside the glass with at least min(entries, N) rows WHOLE before any press;
//   U3  nothing removed: the rows, the face tabs and the empty state are all there;
//   U5  no two text boxes cross; cut text carries its full text;
//   U8  a press on a row with a report opens THAT entry's tray, and closing it leaves the list as it was.
//
// TWO WORLDS, BOTH READ, NO SKIP. The canary a CI run boots serves ONE entry (the founding); the owner's serves fifty. The
// laws are about the fifty, so the glass tests and the tray proof run on the PLAYED world the fixture builds at run time
// (tests/unfold.fixture.ts: this build's own image with `world.ledger` replaced by a page of fifty), and the young world
// has its own test: one entry, and an empty face that says so. (The first cut of this file skipped the tray proof without
// the played world; CI fails any skipped test, and was right to.)

/** Rows WHOLE in the panel's body, by glass width (the budget table in the dev-log: ≥ 6 · 3 · 8). */
const NEED: Record<number, number> = { 390: 6, 320: 3, 1280: 8 }

/** The fixture's page: fifty entries — ten in Trade, twenty in Voyage, twenty in Crew. */
const SERVED = { All: 50, Trade: 10, Voyage: 20, Crew: 20 } as const
const FACES = Object.keys(SERVED) as (keyof typeof SERVED)[]

for (const glass of GLASSES) {
  test(`every Ledger face is unfolded at ${glass.width}×${glass.height}: flat page, its feed on the glass, nothing removed, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await playedWorld(page)
    await page.goto('ledger')
    await ready(page)
    await expect(page.getByTestId('ledger')).toBeVisible()

    const failures: string[] = []
    for (const face of FACES) {
      await openFace(page, face)
      const where = `${face} @${glass.width}×${glass.height}`
      const m = await readGlass(page, 'ledger-list', 'ledger-row')
      console.log(`UNFOLD ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, rows ${m.rows.whole}/${m.rows.total}`)
      if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
      if (m.doc.sw > m.doc.cw + 1) failures.push(`${where}: the document scrolls sideways`)
      if (m.sheet === null) failures.push(`${where}: no Sheet`)
      else if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
      for (const s of m.sideways) failures.push(`${where}: ${s} scrolls sideways`)
      if (!m.rows.found) failures.push(`${where}: no list panel`)
      else {
        if (!m.rows.inView) failures.push(`${where}: the panel is not inside the glass`)
        // the fixture is live: every face serves its share, so the floor below is a number and not min(0, N)
        if (m.rows.total !== SERVED[face]) failures.push(`${where}: ${m.rows.total} rows served; the played world serves ${SERVED[face]}`)
        const need = Math.min(m.rows.total, NEED[glass.width])
        if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole rows of ${m.rows.total}; the law is ${need}`)
      }
      if ((await page.getByRole('tablist').first().getByRole('tab').count()) !== FACES.length) failures.push(`${where}: the four face tabs are not all there`)
      for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
      for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
    }
    expect(failures, 'the Ledger faces are not unfolded').toEqual([])
  })
}

test('a row with a report opens its tray and closing it leaves the feed where it was; a face tab narrows the feed', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await playedWorld(page)
  await page.goto('ledger')
  await ready(page)

  const rows = page.getByTestId('ledger-row')
  await expect(rows).toHaveCount(SERVED.All)
  // a row that opens something is a real button; the others are not
  const withReport = page.locator('button[data-testid="ledger-row"]')
  expect(await withReport.count(), 'the played feed has voyage reports').toBeGreaterThan(0)
  const before = await rows.first().boundingBox()

  await withReport.first().click()
  const tray = page.getByTestId('ledger-report')
  await expect(tray).toBeVisible()
  await expect(tray).toContainText(/sailed|winds|losses/i)
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  await expect(rows).toHaveCount(SERVED.All)
  expect(await rows.first().boundingBox(), 'opening and closing a report moved the first row').toEqual(before)

  // a face tab narrows the feed to its kinds; the title counts what is shown
  await openFace(page, 'Voyage')
  await expect(rows).toHaveCount(SERVED.Voyage)
  await expect(page.getByTestId('ledger-list')).toContainText(String(SERVED.Voyage))
})

test('a young world: one entry on the glass, and a face with nothing says so', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await page.goto('ledger')
  await ready(page)

  const rows = page.getByTestId('ledger-row')
  await expect(rows).toHaveCount(1)
  await expect(page.getByTestId('ledger-list')).toBeVisible()
  const m = await readGlass(page, 'ledger-list', 'ledger-row')
  expect(m.rows.whole, 'the one entry is not whole in the glass').toBe(1)
  await openFace(page, 'Trade')
  await expect(rows).toHaveCount(0)
  await expect(page.getByTestId('ledger-list').getByText(/Nothing/)).toHaveCount(1)
})
