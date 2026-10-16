import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'
import { GOTO_CLEAR_MIN_DEG, GOTO_SPAN_MAX_DEG, goToSpan, MIN_SPAN_X, MAX_SPAN_X, zoomPercent } from '../src/chart/chartView'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GO TO, DRIVEN (src/chart/goTo.ts) — owner, 2026-10-15: *"if i press a city, it will point me to
// that location with a marker"*.
//
// A city's name in its own panel is a link. The chart is first dragged so the city is somewhere
// else on the glass; pressing the name must glide the view back until the city stands in the
// middle of the CLEAR glass (beside the side panel on a wide screen; the whole glass on a phone,
// where the panel folds out of the way), with the marker ringing it. The marker is placed from the
// same viewBox the chart draws with, so "the marker is at the middle" is "the view is centred on
// the city" — measured off the DOM, never off a prop.
//
// Run it: npm run build && npm run preview, then `npx playwright test map.goto.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const WIDE = { width: 1280, height: 800 }

/** Press a harbour's name somewhere in the left part of the glass; returns its code. */
async function openACity(page: Page, maxX: number): Promise<string> {
  await page.locator('[data-label-id^="port:"]').first().waitFor({ state: 'attached', timeout: 120_000 })
  const pick = await page.evaluate((limit) => {
    const glass = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    for (const e of document.querySelectorAll('[data-label-id^="port:"]')) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width > 0 && x > glass.x + 80 && x < limit && y > glass.y + 120 && y < glass.bottom - 140) {
        return { id: e.getAttribute('data-label-id')!, x, y }
      }
    }
    return null
  }, maxX)
  if (!pick) throw new Error('no harbour named in the open part of the opening frame')
  await page.mouse.click(pick.x, pick.y)
  await expect(page.getByTestId('map-place-name')).toBeVisible()
  return pick.id.slice('port:'.length)
}

async function drag(page: Page, from: { x: number; y: number }, by: { x: number; y: number }) {
  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 10; i++) await page.mouse.move(from.x + (by.x * i) / 10, from.y + (by.y * i) / 10)
  await page.mouse.up()
}

/** Waits, in the page and frame by frame, for the marker to stand within 8 px of `target` —
 *  inside its ring time (GOTO_MARK_MS, 4 s); a marker that never arrives fails with what it saw. */
async function settlesAt(page: Page, target: { x: number; y: number }) {
  const seen: string[] = []
  const ok = await page
    .waitForFunction(
      ({ x, y }) => {
        const w = window as unknown as { __goto?: string[] }
        w.__goto ??= []
        const e = document.querySelector('[data-testid="map-goto-marker"]')
        if (!e) {
          w.__goto.push('none')
          return false
        }
        const r = e.getBoundingClientRect()
        w.__goto.push(`${r.x.toFixed(0)},${r.y.toFixed(0)}`)
        return Math.hypot(r.x - x, r.y - y) < 8
      },
      target,
      { polling: 'raf', timeout: 3500 },
    )
    .then(() => true)
    .catch(() => false)
  if (!ok) seen.push(...(await page.evaluate(() => (window as unknown as { __goto?: string[] }).__goto ?? [])))
  expect(ok, `the marker settles on ${target.x},${target.y}; saw ${seen.filter((_, i) => i % 10 === 0).join(' ')}`).toBe(true)
}

test.describe('a place named in a panel is a link that brings the chart to it', () => {
  test.beforeEach(async ({ request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  })

  test('wide: the city glides to the middle of the glass beside the panel, ringed', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(WIDE)
    await page.goto('map')
    await ready(page)

    await openACity(page, WIDE.width - 120)
    // The harbour the tap opened (a dot beside a name may win the tap — hitTest.ts), read off the
    // panel's own link.
    const link = page.getByTestId('map-place-name').getByTestId('goto-link')
    const code = ((await link.getAttribute('data-goto')) ?? '').replace(/^port:/, '')
    expect(code).not.toBe('')
    const glass = await page.getByTestId('map-chart').boundingBox()
    if (!glass) throw new Error('no glass')

    // Move the city away (likely under the panel now): drag the open part of the chart.
    await drag(page, { x: glass.x + 450, y: glass.y + glass.height / 2 }, { x: -300, y: -160 })
    // The panel's edge read once its slide-in has finished (it animates in from the right).
    await page.waitForTimeout(500)
    const panel = await page.getByTestId('map-detail-tray').boundingBox()
    if (!panel) throw new Error('no panel')
    const target = { x: glass.x + (panel.x - glass.x) / 2, y: glass.y + glass.height / 2 }
    // NOT VACUOUS: before the press the city is nowhere near where the go-to must put it.
    const name = page.locator(`[data-label-id="port:${code}"]`).first()
    const before = (await name.count()) > 0 ? await name.boundingBox({ timeout: 1000 }) : null
    if (before) expect(Math.hypot(before.x - target.x, before.y - target.y)).toBeGreaterThan(150)

    await link.click()
    // The panel the link was in stays open — a go-to selects and closes nothing.
    await expect(page.getByTestId('map-detail-tray')).toBeVisible()
    await settlesAt(page, target)
    const at = target
    // And it rings the city itself: her name is drawn beside the marker.
    const label = await name.boundingBox({ timeout: 5000 })
    if (!label) throw new Error(`${code} is not named after the go-to`)
    expect(Math.hypot(label.x + label.width / 2 - at.x, label.y + label.height / 2 - at.y)).toBeLessThan(160)
  })

  test('phone: the panel folds out of the way, the city is centred, the edge tab brings the panel back', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(PHONE)
    await page.goto('map')
    await ready(page)

    await openACity(page, PHONE.width - 40)
    const glass = await page.getByTestId('map-chart').boundingBox()
    if (!glass) throw new Error('no glass')

    await page.getByTestId('map-place-name').getByTestId('goto-link').click()
    // Read inside the marker's ring time first, then the fold.
    await settlesAt(page, { x: glass.x + glass.width / 2, y: glass.y + glass.height / 2 })
    await expect(page.getByTestId('map-unfold')).toBeVisible()
    await expect(page.getByTestId('map-detail-tray')).toBeHidden()

    await page.getByTestId('map-unfold').click()
    await expect(page.getByTestId('map-detail-tray')).toBeVisible()
    await expect(page.getByTestId('map-unfold')).toHaveCount(0)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HOW CLOSE A GO-TO LANDS (2026-10-16) — owner, on the live site: the glide "zooms in too close —
// only water is visible". The rule was `min(current, 12°)`, so a reader already zoomed in kept a
// harbour-approach zoom (1.5°) and the place landed alone. chartView.ts `goToSpan` is now the one
// rule: a READABLE BAND, 12° at most across the glass and 6° at least across the CLEAR glass.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('a go-to lands inside the readable band (chartView.ts goToSpan)', () => {
  test('the rule: in to 12° from further out, out to 6° clear from closer in, kept in between', () => {
    expect(goToSpan(MAX_SPAN_X)).toBe(GOTO_SPAN_MAX_DEG)
    expect(goToSpan(40)).toBe(GOTO_SPAN_MAX_DEG)
    expect(goToSpan(MIN_SPAN_X)).toBe(GOTO_CLEAR_MIN_DEG)
    expect(goToSpan(2)).toBe(GOTO_CLEAR_MIN_DEG)
    expect(goToSpan(8)).toBe(8)
    // Half the glass under a panel: 6° SEEN needs 12° across the whole glass.
    expect(goToSpan(MIN_SPAN_X, 0.5)).toBe(12)
    expect(goToSpan(MIN_SPAN_X, 0.75)).toBeCloseTo(8, 6)
    // The floor never passes the ceiling, however little is clear; nonsense in is the ceiling out.
    expect(goToSpan(MIN_SPAN_X, 0.1)).toBe(GOTO_SPAN_MAX_DEG)
    expect(goToSpan(Number.NaN)).toBe(GOTO_SPAN_MAX_DEG)
    expect(goToSpan(8, 0)).toBe(8)
  })

  test.describe('driven', () => {
    test.beforeEach(async ({ request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    })

    /** The zoom readout (ViewControls, `zoomPercent` of the committed span). */
    async function zoomNow(page: Page): Promise<number> {
      return Number(((await page.getByTestId('map-zoom-percent').textContent()) ?? '').replace(/[^0-9]/g, ''))
    }

    /** Press a zoom button `n` times, then let the glide settle. Pressed through the DOM: on a phone
     *  the open side panel stands over the zoom column, and the zoom buttons are not under test. */
    async function press(page: Page, label: 'Zoom in' | 'Zoom out', n: number) {
      for (let i = 0; i < n; i++) {
        await page.evaluate((l) => (document.querySelector(`[aria-label="${l}"]`) as HTMLElement).click(), label)
        await page.waitForTimeout(80)
      }
      await page.waitForTimeout(800)
    }

    for (const vp of [{ name: 'wide', size: WIDE }, { name: 'phone', size: PHONE }]) {
      test(`${vp.name}: from the closest zoom and from the whole world, it lands readable`, async ({ page }) => {
        test.setTimeout(600_000)
        await page.setViewportSize(vp.size)
        await page.goto('map')
        await ready(page)
        await openACity(page, vp.size.width - 120)
        const link = page.getByTestId('map-place-name').getByTestId('goto-link')

        // The band in the readout's own terms. The wide glass keeps the panel open beside the city,
        // so its floor is the clear share's; the phone folds the panel, so the whole glass is clear.
        const glass = (await page.getByTestId('map-chart').boundingBox())!
        const panel = await page.getByTestId('map-detail-tray').boundingBox()
        const clearShare = vp.name === 'wide' && panel ? (panel.x - glass.x) / glass.width : 1
        const closest = zoomPercent(goToSpan(MIN_SPAN_X, clearShare))
        const widest = zoomPercent(GOTO_SPAN_MAX_DEG)

        // 1 — zoomed all the way IN (the "only water" case): the go-to brings the reader back out.
        await press(page, 'Zoom in', 12)
        expect(await zoomNow(page)).toBe(100)
        await link.click()
        await expect.poll(() => zoomNow(page), { timeout: 4000 }).toBeLessThanOrEqual(closest + 1)
        expect(await zoomNow(page)).toBeGreaterThanOrEqual(widest - 1)
        if (vp.name === 'phone') await page.getByTestId('map-unfold').click()

        // 2 — zoomed all the way OUT: the go-to brings the reader in, no further than the band.
        await press(page, 'Zoom out', 12)
        expect(await zoomNow(page)).toBe(0)
        await link.click()
        await expect.poll(() => zoomNow(page), { timeout: 4000 }).toBeGreaterThanOrEqual(widest - 1)
        expect(await zoomNow(page)).toBeLessThanOrEqual(closest + 1)
      })
    }
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A GO-TO ONLY MOVES THE MAP (2026-10-16) — owner, on the live site: one press on a stop name "may
// also have opened" the trade-history panel. GoToLink (src/chart/GoToLink.tsx) stops its press at
// itself, and no row that holds a link opens the trading. This presses EVERY link in a merchant's
// sheet — her name, where she is, each stop of her route, her officer's home port — with a mouse on
// a wide glass and a finger on a phone, and asserts after each that her sheet is still the one open
// and no TradeHistoryPanel came with it. The merchants are switched on by tests/npcOn.fixture.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('a go-to link opens nothing (no trade history, no other panel)', () => {
  test.beforeEach(async ({ request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  })

  async function pressEveryLinkInAMerchantSheet(page: Page, size: { width: number; height: number }, finger: boolean) {
    await page.setViewportSize(size)
    await serveNpcOn(page)
    await page.goto('map')
    await ready(page)
    // Lisbon, where the fixture lays a merchant up, so its Port tab always lists one.
    const lisbon = page.locator('[data-label-id="port:LIS"]').first()
    await lisbon.waitFor({ state: 'attached', timeout: 120_000 })
    const lb = (await lisbon.boundingBox())!
    await page.mouse.click(lb.x + lb.width / 2, lb.y + lb.height / 2)
    await expect(page.getByTestId('map-place-name')).toBeVisible()
    await page.getByTestId('map-detail-tray').getByRole('tab', { name: 'Port' }).click()
    // Open her by the row's far end, clear of the name (itself a link).
    const row = page.getByTestId('merchant-row').first()
    await row.waitFor({ timeout: 60_000 })
    const rb = (await row.boundingBox())!
    await page.mouse.click(rb.x + rb.width - 12, rb.y + rb.height / 2)
    const sheet = page.getByTestId('merchant-sheet')
    await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
    const name = await page.getByTestId('merchant-sheet-name').textContent()

    const links = sheet.getByTestId('goto-link')
    const n = await links.count()
    // NOT VACUOUS: her name, where she is, and at least two stops of her route.
    expect(n).toBeGreaterThanOrEqual(4)
    expect(await sheet.getByTestId('merchant-route').getByTestId('goto-link').count()).toBeGreaterThanOrEqual(2)
    for (let i = 0; i < n; i++) {
      // A phone folds the panels for a go-to (MapScreen); bring them back to reach the next link.
      if ((await page.getByTestId('map-unfold').count()) > 0) await page.getByTestId('map-unfold').click()
      const link = links.nth(i)
      await link.scrollIntoViewIfNeeded()
      const b = (await link.boundingBox())!
      const at = { x: b.x + b.width / 2, y: b.y + b.height / 2 }
      // HER TEXT IS READ BEFORE THE PRESS, never between the press and the check (2026-10-17). The
      // marker rings for GOTO_MARK_MS (4 s) and then goes; CI run 38927914130 (PR #141) pressed
      // `Setubal`, the marker was on the page at the press's own after-snapshot, and the message's
      // `await link.textContent()` then took 10 s on a busy runner — so the check began after the
      // ring had come and gone, and read 0 for 20 s on a press that had worked.
      const text = await link.textContent()
      if (finger) await page.touchscreen.tap(at.x, at.y)
      else await page.mouse.click(at.x, at.y)
      // The marker is a 0×0 anchor (GoToMarker.tsx), so it is counted, not 'seen'.
      await expect(page.getByTestId('map-goto-marker'), `link ${i} (${text}) rang the place`).toHaveCount(1)
      await page.waitForTimeout(600)
      expect(await page.getByTestId('trade-history').count(), `link ${i} (${text}) opened the trading`).toBe(0)
      expect(await page.getByTestId('map-ship-panel').count(), `link ${i} opened a ship`).toBe(0)
      await expect(page.getByTestId('merchant-sheet-name')).toHaveText(name ?? '')
    }
  }

  test('wide, a mouse', async ({ page }) => {
    test.setTimeout(1_200_000)
    await pressEveryLinkInAMerchantSheet(page, WIDE, false)
  })

  test.describe('a phone, a finger', () => {
    test.use({ hasTouch: true, isMobile: true })
    test('phone, a tap', async ({ page }) => {
      test.setTimeout(1_200_000)
      await pressEveryLinkInAMerchantSheet(page, PHONE, true)
    })
  })
})
