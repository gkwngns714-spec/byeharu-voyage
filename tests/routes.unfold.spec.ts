import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, playedWorld, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ROUTES, UNFOLDED — the owner's law, measured at three glasses (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded … make things unfolded, minimize scrolling, everything compact with full info."*
// (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8; docs/dev-log/2026-11-01-unfold-routes.md.) Routes was ONE
// summary row (`Routes 40 · Open`); the board was behind the press. It is now ONE list panel
// (src/components/ui/ListPanel.tsx; src/features/routes/RoutesScreen.tsx): the lanes, hers first, the order strip and the
// board's one button in its header, the lane tray a sibling outside the scroller.
//
//   U2  the page and the Sheet never scroll; the board scrolls inside its panel;
//   U1  the panel stands inside the glass with at least min(lanes, N) lanes WHOLE before any press;
//   U3  nothing removed: the three orders, the refresh button, the lanes, the empty state are all there;
//   U5  no two text boxes cross; cut text carries its full text; no placeholder dash in a lane;
//   U8  a press on a lane opens THAT lane's tray, and closing it leaves the board as it was.
//
// TWO WORLDS, BOTH READ, NO SKIP. The canary a CI run boots serves NO lane (its traders are off); the owner's serves up to
// `route_board_max`. The laws are about the lanes, so the glass tests and the lane proofs run on the PLAYED world the fixture
// builds at run time (tests/unfold.fixture.ts: this build's own image with `world.route_board` replaced by forty lanes), and
// the empty board has its own test on the canary. CI fails any skipped test, so nothing here waits for an env var.

/** Lanes WHOLE in the panel's body, by glass width (the budget table in the dev-log: ≥ 6 · 3 · 8). */
const NEED: Record<number, number> = { 390: 6, 320: 3, 1280: 8 }

/** The fixture's board: forty lanes served (of a hundred and twenty), two of them hers. */
const SERVED = 40

for (const glass of GLASSES) {
  test(`Routes is unfolded at ${glass.width}×${glass.height}: flat page, the board on the glass, nothing removed, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await playedWorld(page)
    await page.goto('routes')
    await ready(page)
    await expect(page.getByTestId('routes')).toBeVisible()
    await expect(page.getByTestId('routes-list')).toBeVisible({ timeout: 60_000 })

    const where = `Routes @${glass.width}×${glass.height}`
    const failures: string[] = []
    const m = await readGlass(page, 'routes-list', 'route-lane')
    console.log(`UNFOLD ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, lanes ${m.rows.whole}/${m.rows.total}`)
    if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
    if (m.doc.sw > m.doc.cw + 1) failures.push(`${where}: the document scrolls sideways`)
    if (m.sheet === null) failures.push(`${where}: no Sheet`)
    else if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
    for (const s of m.sideways) failures.push(`${where}: ${s} scrolls sideways`)
    if (!m.rows.found) failures.push(`${where}: no list panel`)
    else {
      if (!m.rows.inView) failures.push(`${where}: the panel is not inside the glass`)
      // the fixture is live: the board serves its forty, so the floor below is a number and not min(0, N)
      if (m.rows.total !== SERVED) failures.push(`${where}: ${m.rows.total} lanes served; the played world serves ${SERVED}`)
      const need = Math.min(m.rows.total, NEED[glass.width])
      if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole lanes of ${m.rows.total}; the law is ${need}`)
    }
    // nothing removed: the three orders, and the refresh button on the 44-px floor
    for (const order of ['Distance', 'Earnings', 'Calls']) {
      if ((await page.getByRole('tab', { name: order, exact: true }).count()) !== 1) failures.push(`${where}: the ${order} order is not there`)
    }
    const refresh = await page.getByTestId('routes-refresh').boundingBox()
    if (refresh === null) failures.push(`${where}: no refresh button`)
    else if (refresh.height < 43.5 || refresh.width < 43.5) failures.push(`${where}: the refresh button is ${refresh.width}×${refresh.height}`)
    // an absent ranked figure is a word, never a dash
    const lanes = page.getByTestId('route-lane')
    for (let i = 0; i < m.rows.total; i++) {
      const value = (await lanes.nth(i).locator('[data-row-cell="value"]').innerText()).trim()
      if (/^[—–-]$/.test(value)) failures.push(`${where}: lane ${i} draws a dash`)
    }
    for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
    for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
    expect(failures, 'the Routes board is not unfolded').toEqual([])
  })
}

test('a lane opens its tray and closing it leaves the board; an order re-ranks the lanes; no lane draws a dash', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await playedWorld(page)
  await page.goto('routes')
  await ready(page)
  await expect(page.getByTestId('routes-list')).toBeVisible({ timeout: 60_000 })

  const lanes = page.getByTestId('route-lane')
  await expect(lanes).toHaveCount(SERVED)
  const title = await page.getByTestId('routes-list').getByRole('heading').first().boundingBox()
  const first = await lanes.first().boundingBox()

  await lanes.first().click()
  const tray = page.getByTestId('route-tray')
  await expect(tray).toBeVisible()
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  await expect(lanes).toHaveCount(SERVED)
  expect(await lanes.first().boundingBox(), 'opening and closing a lane moved the first row').toEqual(first)

  // the Calls order ranks the merchants' lanes by how many harbours they call at, most first (hers lead the list)
  await page.getByRole('tab', { name: 'Calls', exact: true }).click()
  const calls = await lanes.evaluateAll((els) =>
    els.map((e) => Number(((e.querySelector('[data-row-cell="value"]')?.textContent ?? '').match(/\d+/) ?? ['0'])[0])),
  )
  const merchants = calls.slice(2)
  expect(merchants, 'the merchants lanes are not ranked by calls').toEqual([...merchants].sort((a, b) => b - a))
  expect(await page.getByTestId('routes-list').getByRole('heading').first().boundingBox(), 'a re-rank moved the title').toEqual(title)

  // the Earnings order: a lane with no closed lap yet says so in a word — it never draws a dash (the old board did)
  await page.getByRole('tab', { name: 'Earnings', exact: true }).click()
  const earned = await lanes.evaluateAll((els) => els.map((e) => (e.querySelector('[data-row-cell="value"]')?.textContent ?? '').trim()))
  expect(earned.some((v) => /^[—–-]$/.test(v)), 'a lane draws a dash').toBe(false)
  expect(earned.some((v) => v === 'not yet'), 'a lane with no closed lap does not say so').toBe(true)
})

test('a young world: no lane yet — the board says so, the three orders and the refresh button stand', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[1])
  await page.goto('routes')
  await ready(page)
  await expect(page.getByTestId('routes-list')).toBeVisible({ timeout: 60_000 })

  await expect(page.getByTestId('route-lane')).toHaveCount(0)
  await expect(page.getByTestId('routes-list').getByText(/No routes/)).toHaveCount(1)
  for (const order of ['Distance', 'Earnings', 'Calls']) await expect(page.getByRole('tab', { name: order, exact: true })).toHaveCount(1)
  const refresh = await page.getByTestId('routes-refresh').boundingBox()
  expect(refresh, 'no refresh button').not.toBeNull()
  expect(refresh!.height, 'the refresh button is under the 44-px floor').toBeGreaterThanOrEqual(43.5)
})
