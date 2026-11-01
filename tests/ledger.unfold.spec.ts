import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, openFace, readGlass, seededWorld } from './unfold.fixture'

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
// THE FLOOR IS min(entries served, N), because the world a CI run boots (the canary) serves ONE entry and the owner's
// serves fifty. Both are read: `UNFOLD_WORLD=<a live-sized world image>` (tests/unfold.fixture.ts) serves the fifty-entry
// image locally, and the report-tray proof needs it (the canary has no entry with a report); without it that test is
// SKIPPED, loudly, with the reason — it is not an assertion that a canary world cannot make.

/** Rows WHOLE in the panel's body, by glass width (the budget table in the dev-log: ≥ 6 · 3 · 8). */
const NEED: Record<number, number> = { 390: 6, 320: 3, 1280: 8 }

const FACES = ['All', 'Trade', 'Voyage', 'Crew'] as const

for (const glass of GLASSES) {
  test(`every Ledger face is unfolded at ${glass.width}×${glass.height}: flat page, its feed on the glass, nothing removed, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await seededWorld(page)
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
        const need = Math.min(m.rows.total, NEED[glass.width])
        if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole rows of ${m.rows.total}; the law is ${need}`)
      }
      if ((await page.getByRole('tablist').first().getByRole('tab').count()) !== FACES.length) failures.push(`${where}: the four face tabs are not all there`)
      // an empty face says so in the panel instead of drawing nothing
      if (m.rows.total === 0 && (await page.getByTestId('ledger-list').getByText(/Nothing/).count()) === 0) failures.push(`${where}: an empty face says nothing`)
      for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
      for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
    }
    expect(failures, 'the Ledger faces are not unfolded').toEqual([])
  })
}

test('a row with a report opens its tray and closing it leaves the feed where it was', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  test.skip(!process.env.UNFOLD_WORLD, 'needs the live-sized local world (UNFOLD_WORLD=<image>): the canary world serves no entry with a report')
  await page.setViewportSize(GLASSES[0])
  await seededWorld(page)
  await page.goto('ledger')
  await ready(page)

  const rows = page.getByTestId('ledger-row')
  const total = await rows.count()
  expect(total, 'the live-sized world serves fifty entries').toBeGreaterThan(20)
  const withReport = page.locator('button[data-testid="ledger-row"]')
  expect(await withReport.count(), 'the seeded feed has voyage reports').toBeGreaterThan(0)
  const before = await rows.first().boundingBox()

  await withReport.first().click()
  const tray = page.getByTestId('ledger-report')
  await expect(tray).toBeVisible()
  await expect(tray).toContainText(/sailed|winds|losses/i)
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  expect(await rows.count(), 'closing the tray changed the feed').toBe(total)
  expect(await rows.first().boundingBox(), 'opening and closing a report moved the first row').toEqual(before)

  // a face tab narrows the feed to its kinds; the title counts what is shown
  await openFace(page, 'Voyage')
  const voyage = await rows.count()
  expect(voyage).toBeGreaterThan(0)
  expect(voyage).toBeLessThan(total)
  await expect(page.getByTestId('ledger-list')).toContainText(String(voyage))
})
