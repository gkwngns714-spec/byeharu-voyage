import { test, expect, type Page } from '@playwright/test'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'
import { serveRoutesOn } from './routesOn.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE BUILDER ON THE MAP, DRIVEN (owner row 209, docs/ROUTE_BUILDER.md B2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-26: *"in the map, let me click set route, and let me press city, undo, then confirm each visiting
// city, then press final - something like that."* Driven on THE REAL GAME in the tab — the real chain on PGlite, the
// §K.1 house at Lisbon, the real world.route_legs (0346) judging every leg and the real cmd.issue_lines queuing them —
// at the owner's two widths: Set route → a city → another city (a press replaces the next stop) → Undo → the first
// city again → Confirm → a second city → Confirm → Final. Then her queue is on the chart (numbered stops), and a city
// tap opens the city tray exactly as before route mode. The bar never moves while stops are added.
//
// Each city is a harbour NAMED on the opening frame, picked off the DOM the player sees, and kept only when the
// SERVER calls its leg open (Confirm's `data-reason`), so the drive never relies on a city this file guessed.
// It SKIPS with a stated reason when nothing is served (tests/appReady.fixture.ts).
//
// B3, VIA: the chart is drawn back until a named city's Confirm reads "Via N" (the server's `via` on a shut leg);
// one press keeps N+1 stops, and the server calls every one of those legs open. B4, REPEAT (routes switched on,
// routesOn.fixture.ts): Repeat opens THE route editor on the kept stops, her harbour first; Back returns to the
// builder with nothing lost; Start route saves it, and the desk's route row lists the same harbours.
//
// Run it: npm run build && npx vite preview --port 4173, then `npx playwright test map.routebuilder.spec.ts`.

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
}

/** The centres of the harbour names drawn on the glass (not Lisbon, not under the route bar), nearest the chart's
 *  middle first — what a player would put a thumb on. */
async function namedCities(page: Page): Promise<{ code: string; x: number; y: number }[]> {
  const bar = (await page.getByTestId('route-bar').count()) > 0 ? await page.getByTestId('route-bar').boundingBox() : null
  return page.evaluate((barTop) => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const mid = { x: chart.x + chart.width / 2, y: chart.y + chart.height / 2 }
    return [...document.querySelectorAll('text[data-label-id^="port:"]')]
      .map((el) => {
        const r = el.getBoundingClientRect()
        return { code: (el.getAttribute('data-label-id') ?? '').slice(5), x: r.x + r.width / 2, y: r.y + r.height / 2 }
      })
      .filter((c) => c.code !== 'LIS' && c.x > chart.x + 60 && c.x < chart.right - 60 && c.y > chart.y + 70 && c.y < Math.min(chart.bottom, barTop) - 16)
      .sort((a, b) => Math.hypot(a.x - mid.x, a.y - mid.y) - Math.hypot(b.x - mid.x, b.y - mid.y))
  }, bar ? bar.y : Number.POSITIVE_INFINITY)
}

/** Tap a city in route mode and wait for the server's verdict on its leg; the verdict (Confirm's data-reason). */
async function tapCity(page: Page, c: { code: string; x: number; y: number }): Promise<string> {
  await page.mouse.click(c.x, c.y)
  const pending = page.locator('[data-testid="route-leg"][data-pending]')
  await expect(pending).toHaveAttribute('data-to', c.code)
  const confirm = page.getByTestId('route-confirm')
  await expect(confirm).not.toHaveAttribute('data-reason', 'checking', { timeout: 60_000 })
  return (await confirm.getAttribute('data-reason')) ?? ''
}

/** Her tray from the fleets corner, its Set route press, and the bar that takes the tray's place. */
async function setRoute(page: Page) {
  const pill = page.getByTestId('map-fleets-corner').locator('button[aria-expanded]')
  await pill.click()
  await page.getByTestId('map-fleet-row').first().click()
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible()
  await page.getByTestId('map-set-route').click()
  // the fleets list folds back once the tray has given way to the bar, so no harbour name is under it
  if ((await pill.getAttribute('aria-expanded')) === 'true') await pill.click()

  const bar = page.getByTestId('route-bar')
  await expect(bar).toBeVisible()
  await expect(tray, 'a tray stayed open in route mode').toHaveCount(0)
  await expect(bar).toHaveAttribute('data-kept', '0')
  return bar
}

async function drive(page: Page, label: string) {
  await openMap(page)
  const bar = await setRoute(page)
  const box0 = await bar.boundingBox()
  expect(box0).not.toBeNull()

  // TWO CITIES THE SERVER CALLS OPEN: the nearest named harbours, each tried until its leg is open
  const cities = await namedCities(page)
  expect(cities.length, 'fewer than two harbours are named on the opening frame').toBeGreaterThanOrEqual(2)
  let first: (typeof cities)[number] | null = null
  for (const c of cities) {
    if ((await tapCity(page, c)) === 'open') {
      first = c
      break
    }
  }
  expect(first, 'no named city near Lisbon has an open leg').not.toBeNull()
  const second = cities.find((c) => c.code !== first!.code)!

  // A PRESS REPLACES THE NEXT STOP, and Undo takes the next stop away
  await tapCity(page, second)
  await expect(page.getByTestId('route-leg')).toHaveCount(1)
  await page.getByTestId('route-undo').click()
  await expect(page.getByTestId('route-leg')).toHaveCount(0)

  // THE FIRST CITY AGAIN, CONFIRMED
  expect(await tapCity(page, first!)).toBe('open')
  await page.getByTestId('route-confirm').click()
  await expect(bar).toHaveAttribute('data-kept', '1')
  await expect(page.locator('[data-testid="route-leg"][data-pending]')).toHaveCount(0)

  // A SECOND STOP, from the first: tried city by city until the server calls the leg open
  let kept2 = false
  for (const c of await namedCities(page)) {
    if (c.code === first!.code) continue
    if ((await tapCity(page, c)) === 'open') {
      await page.getByTestId('route-confirm').click()
      kept2 = true
      break
    }
  }
  expect(kept2, 'no second named city has an open leg from the first').toBe(true)
  await expect(bar).toHaveAttribute('data-kept', '2')
  await expect(page.getByTestId('route-leg')).toHaveCount(2)

  // THE BAR NEVER MOVED while stops were added and taken away (the owner's law: a press never re-flows)
  const box2 = await bar.boundingBox()
  expect(box2, 'the route bar moved or changed height when a stop was added').toEqual(box0)
  // nothing scrolls sideways
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: `test-results/route-builder-${label}.png` })

  // FINAL: the two SAILs are queued; route mode ends and her queue is drawn as numbered stops
  await page.getByTestId('route-final').click()
  await expect(bar).toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId('map-detail-tray')).toBeVisible()
  await expect(page.locator('[data-testid="map-path-stop"]').first()).toBeVisible({ timeout: 60_000 })
  expect(await page.locator('[data-testid="map-path-stop"]').count()).toBeGreaterThanOrEqual(1)
  await page.screenshot({ path: `test-results/route-builder-${label}-final.png` })

  // OUT OF ROUTE MODE, A CITY TAP SELECTS AS BEFORE: the city tray opens with its name
  await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
  await expect(page.getByTestId('map-detail-tray')).toHaveCount(0)
  const again = (await namedCities(page))[0]
  await page.mouse.click(again.x, again.y)
  await expect(page.getByTestId('map-place-name')).toBeVisible()
}

/** B3: a far city's Confirm reads "Via N"; one press keeps the N harbours and the city, every leg open. */
async function driveVia(page: Page, label: string) {
  await openMap(page)
  const bar = await setRoute(page)
  const box0 = await bar.boundingBox()
  const confirm = page.getByTestId('route-confirm')
  const chart = (await page.getByTestId('map-chart').boundingBox())!

  // DRAW THE CHART BACK until a named city is one the server calls shut AND names the harbours between
  let far: string | null = null
  const tried = new Set<string>()
  for (let step = 0; step < 5 && far === null; step++) {
    for (const c of await namedCities(page)) {
      if (tried.has(c.code)) continue
      tried.add(c.code)
      const reason = await tapCity(page, c)
      if ((await confirm.getAttribute('data-via')) !== null) {
        expect(reason, 'a leg with harbours between is a leg the server calls shut').toMatch(/^E_/)
        far = c.code
        break
      }
    }
    if (far === null) {
      await page.mouse.move(chart.x + chart.width / 2, chart.y + chart.height / 3)
      await page.mouse.wheel(0, 600)
      await page.waitForTimeout(1200)
    }
  }
  expect(far, `no named city is shut with harbours between (tried ${[...tried].join(' ')})`).not.toBeNull()

  // THE BUTTON SAYS "Via N" AND PRESSES
  const n = Number(await confirm.getAttribute('data-via'))
  expect(n).toBeGreaterThanOrEqual(1)
  await expect(confirm).toHaveText(`Via ${n}`)
  await expect(confirm).toBeEnabled()
  await page.screenshot({ path: `test-results/route-builder-${label}-via.png` })
  await confirm.click()

  // N HARBOURS AND THE CITY ARE KEPT — N+1 stops, the city last, each leg leaving where the one before ended
  await expect(bar).toHaveAttribute('data-kept', String(n + 1))
  const legs = page.getByTestId('route-leg')
  await expect(legs).toHaveCount(n + 1)
  await expect(page.locator('[data-testid="route-leg"][data-pending]')).toHaveCount(0)
  await expect(legs.nth(n)).toHaveAttribute('data-to', far!)
  for (let i = 1; i <= n; i++) {
    expect(await legs.nth(i).getAttribute('data-from')).toBe(await legs.nth(i - 1).getAttribute('data-to'))
  }
  // EVERY LEG IN THEM IS OPEN: the server has judged the kept legs and calls none shut, so Final may be pressed
  await expect(bar).toHaveAttribute('data-judged', 'true', { timeout: 60_000 })
  await expect(bar, 'a leg through the harbours between is shut').not.toHaveAttribute('data-blocked', 'true')
  await expect(page.getByTestId('route-final')).toBeEnabled()
  expect(await bar.boundingBox(), 'the route bar moved when Via was pressed').toEqual(box0)
  await page.screenshot({ path: `test-results/route-builder-${label}-via-kept.png` })

  // LEAVABLE: Undo takes them away one stop at a time, and Cancel ends route mode
  for (let i = n; i >= 0; i--) {
    await page.getByTestId('route-undo').click()
    await expect(bar).toHaveAttribute('data-kept', String(i))
  }
  await page.getByTestId('route-cancel').click()
  await expect(bar).toHaveCount(0)
}

/** B4: Repeat opens the route editor on the kept stops; Back returns; Start route saves, and the desk lists it. */
async function driveRepeat(page: Page, label: string) {
  await serveRoutesOn(page)
  await openMap(page)
  const bar = await setRoute(page)
  const repeat = page.getByTestId('route-repeat')
  await expect(repeat, 'Repeat pressed with no stop kept').toBeDisabled()

  // ONE STOP, then a second when the loop through it still closes (the server judges the closing leg)
  const cities = await namedCities(page)
  let first: (typeof cities)[number] | null = null
  for (const c of cities) {
    if ((await tapCity(page, c)) === 'open') {
      first = c
      break
    }
  }
  expect(first, 'no named city near Lisbon has an open leg').not.toBeNull()
  await page.getByTestId('route-confirm').click()
  await expect(bar).toHaveAttribute('data-kept', '1')
  await expect(repeat).toHaveAttribute('data-reason', 'open', { timeout: 60_000 })
  for (const c of await namedCities(page)) {
    if (c.code === first!.code) continue
    if ((await tapCity(page, c)) !== 'open') continue
    await page.getByTestId('route-confirm').click()
    await expect(bar).toHaveAttribute('data-kept', '2')
    await expect(repeat).not.toHaveAttribute('data-reason', 'checking', { timeout: 60_000 })
    if ((await repeat.getAttribute('data-reason')) === 'open') break
    await page.getByTestId('route-undo').click()
    await expect(bar).toHaveAttribute('data-kept', '1')
  }
  await expect(repeat).toHaveAttribute('data-reason', 'open', { timeout: 60_000 })
  await expect(repeat).toHaveText('Repeat')

  // THE LOOP'S HARBOURS: where she lies, then each kept stop — read off the bar's own leg lines
  const legs = page.getByTestId('route-leg')
  const kept = await legs.count()
  const codes = [(await legs.first().getAttribute('data-from'))!]
  for (let i = 0; i < kept; i++) codes.push((await legs.nth(i).getAttribute('data-to'))!)
  const names: string[] = []
  for (const code of codes) names.push(((await page.locator(`text[data-label-id="port:${code}"]`).first().textContent()) ?? '').trim())
  const box0 = await bar.boundingBox()

  // REPEAT OPENS THE ROUTE EDITOR WITH THE SAME STOPS
  await repeat.click()
  const pageUp = page.getByTestId('route-repeat-page')
  await expect(pageUp).toBeVisible()
  const stops = pageUp.getByTestId('route-editor-stop')
  await expect(stops).toHaveCount(codes.length)
  for (let i = 0; i < codes.length; i++) await expect(stops.nth(i).getByTestId('route-stop-port')).toContainText(names[i])
  await page.screenshot({ path: `test-results/route-builder-${label}-repeat.png` })

  // BACK: the builder is as it was left — the same stops kept, the bar where it stood
  await pageUp.locator('[data-detail-back]').click()
  await expect(pageUp).toHaveCount(0)
  await expect(bar).toHaveAttribute('data-kept', String(kept))
  expect(await bar.boundingBox(), 'the route bar moved across the editor and back').toEqual(box0)

  // AGAIN, AND SAVED: the route starts, route mode ends, and her tray is up
  await repeat.click()
  await expect(stops).toHaveCount(codes.length)
  await pageUp.getByTestId('route-start').click()
  await expect(pageUp).toHaveCount(0, { timeout: 60_000 })
  await expect(bar).toHaveCount(0)
  await expect(page.getByTestId('map-detail-tray')).toBeVisible()

  // THE DESK LISTS THE ROUTE, by the same harbours in the same order
  await page.locator('a[href$="/command"]:visible').first().click()
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Goods', exact: true }).click()
  await expect(page.getByTestId('route-row')).toContainText(names.join(' ⇄ '), { timeout: 60_000 })
  await page.screenshot({ path: `test-results/route-builder-${label}-repeat-saved.png` })
}

for (const [label, viewport] of [
  ['390', { width: 390, height: 844 }],
  ['1280', { width: 1280, height: 800 }],
] as const) {
  test.describe(`the route builder at ${label}`, () => {
    test.use({ viewport, deviceScaleFactor: 2 })
    test.setTimeout(600_000)
    test(`Set route, tap, Undo, Confirm twice, Final — at ${label}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npx vite preview\``)
      await drive(page, label)
    })
    test(`a far city reads Via N, and one press keeps N+1 stops with every leg open — at ${label}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npx vite preview\``)
      await driveVia(page, label)
    })
    test(`Repeat opens the route editor with the same stops, and saving it lists the route — at ${label}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npx vite preview\``)
      await driveRepeat(page, label)
    })
  })
}
