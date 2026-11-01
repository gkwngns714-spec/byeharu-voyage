import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, openFace, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CODEX, UNFOLDED — the owner's law, measured on every face at three glasses (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded … make things unfolded, minimize scrolling, everything compact with full info."*
// (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8, brief 2026-11-01-unfold-lists.md.) The Codex
// was four faces over ONE summary row (`Goods 629 · Open`) with three quarters of the glass empty. It is now the
// four faces over ONE list panel (src/components/ui/ListPanel.tsx; src/features/compendium/CompendiumScreen.tsx):
//
//   U2  the page and the Sheet never scroll; the list scrolls inside its panel;
//   U1  the panel stands inside the glass with at least N rows WHOLE before any press (N per face and glass below);
//   U3  nothing removed: the face's rows, its search and its filters are all there;
//   U5  no two text boxes cross, and — stricter than the shared law, because the catalogue's names are static and the
//       rows were built for it — NO text in the panel is cut at all: a name wraps at its spaces, it is never clipped;
//   U8  a press on a row opens THAT item's tray, and closing it leaves the list as it was.

/** Every box in the panel whose text is clipped (ellipsis or hidden overflow) — none may be. Self-contained: it is shipped into the page. */
const CLIPPED = (panel: string) => {
  const root = document.querySelector(`[data-testid="${panel}"]`)
  if (!root) return ['no panel']
  return [...root.querySelectorAll('*')]
    .filter((e): e is HTMLElement => {
      if (!(e instanceof HTMLElement) || e.clientWidth <= 2 || !(e.textContent ?? '').trim()) return false
      const s = getComputedStyle(e)
      return (s.overflowX === 'hidden' || s.overflowX === 'clip' || s.textOverflow === 'ellipsis') && e.scrollWidth > e.clientWidth + 1
    })
    .map((e) => `${e.tagName.toLowerCase()} "${(e.textContent ?? '').trim().slice(0, 30)}" ${e.scrollWidth}/${e.clientWidth}`)
}

interface Face {
  tab: string
  row: string | null
  /** Rows WHOLE in the panel's body, by glass width. */
  rows: Record<number, number>
  /** What else the face has, by test id. */
  ids: readonly string[]
}

const FACES: readonly Face[] = [
  { tab: 'Goods', row: 'good-tile', rows: { 390: 8, 320: 4, 1280: 8 }, ids: ['codex-search', 'good-kind'] },
  { tab: 'Ships', row: 'ship-tile', rows: { 390: 4, 320: 2, 1280: 4 }, ids: ['codex-search', 'ship-filters'] },
  { tab: 'Captains', row: 'officer-tile', rows: { 390: 4, 320: 2, 1280: 4 }, ids: ['codex-search', 'captain-filters'] },
  { tab: 'Nations', row: 'nation-row', rows: { 390: 12, 320: 6, 1280: 12 }, ids: ['codex-search', 'nation-rows', 'nation-great', 'nation-rulers'] },
]

for (const glass of GLASSES) {
  test(`every Codex face is unfolded at ${glass.width}×${glass.height}: flat page, its list on the glass, nothing removed, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('compendium')
    await ready(page)
    await expect(page.getByTestId('codex')).toBeVisible()

    const failures: string[] = []
    for (const face of FACES) {
      await openFace(page, face.tab)
      const where = `${face.tab} @${glass.width}×${glass.height}`
      const m = await readGlass(page, 'codex-list', face.row)
      console.log(`UNFOLD ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, rows ${m.rows.whole}/${m.rows.total}`)
      if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
      if (m.doc.sw > m.doc.cw + 1) failures.push(`${where}: the document scrolls sideways`)
      if (m.sheet === null) failures.push(`${where}: no Sheet`)
      else if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
      for (const s of m.sideways) failures.push(`${where}: ${s} scrolls sideways`)
      if (!m.rows.found) failures.push(`${where}: no list panel`)
      else {
        if (!m.rows.inView) failures.push(`${where}: the panel is not inside the glass`)
        const need = face.rows[glass.width]
        if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole rows of ${m.rows.total}; the law is ${need}`)
      }
      for (const id of face.ids) if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: ${id} is gone`)
      for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
      for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
      for (const c of await page.evaluate(CLIPPED, 'codex-list')) failures.push(`${where}: text is cut in the panel ${c}`)
    }
    expect(failures, 'the Codex faces are not unfolded').toEqual([])
  })
}

test('a row press opens its tray and closing it leaves the list; the search narrows the rows; the filters pick', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await page.goto('compendium')
  await ready(page)

  // GOODS: a row opens the good's tray; closing it leaves the panel and its rows where they were
  const goods = page.getByTestId('good-tile')
  const total = await goods.count()
  expect(total, 'the goods are not all on the glass').toBeGreaterThan(100)
  const first = (await goods.first().innerText()).split('\n')[0]
  await goods.first().click()
  await expect(page.getByTestId('good-tray')).toBeVisible()
  await expect(page.getByTestId('good-tray')).toContainText(first.trim().slice(0, 5))
  await page.getByTestId('tray-close').click()
  await expect(page.getByTestId('good-tray')).toHaveCount(0)
  expect(await goods.count(), 'closing the tray changed the list').toBe(total)

  // THE SEARCH is the panel's own: it narrows the rows, clearing it brings them all back
  await page.getByTestId('codex-search').fill('amber')
  await expect.poll(() => goods.count(), { timeout: 15_000 }).toBeLessThan(total)
  expect(await goods.count()).toBeGreaterThan(0)
  await page.getByTestId('codex-search').fill('')
  await expect.poll(() => goods.count(), { timeout: 15_000 }).toBe(total)

  // SHIPS: the four pickers stand over the rows, each naming itself; one picked narrows the list
  await openFace(page, 'Ships')
  const ships = page.getByTestId('ship-tile')
  const shipTotal = await ships.count()
  expect(shipTotal).toBeGreaterThan(10)
  const pick = page.getByTestId('filter-pick-size')
  await expect(pick).toBeVisible()
  const options = await pick.locator('option').evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value))
  await pick.selectOption(options[1])
  await expect.poll(() => ships.count(), { timeout: 15_000 }).toBeLessThan(shipTotal)
  await pick.selectOption('all')
  await expect.poll(() => ships.count(), { timeout: 15_000 }).toBe(shipTotal)
  await ships.first().click()
  await expect(page.getByTestId('ship-tray')).toBeVisible()
  await page.getByTestId('tray-close').click()
  await expect(page.getByTestId('ship-tray')).toHaveCount(0)
})
