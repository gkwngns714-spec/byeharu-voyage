import { test, expect } from '@playwright/test'
import { PHONE, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PRIMITIVES, MEASURED — docs/UI_DIRECTION.md §7 step 2
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §5 states twelve primitives as NUMBERS: a row is 52px, every target clears 44px, a tray stops at
// 96px / half the glass / all of it, and opening a tray moves nothing above it. A number in a
// component's header is not a guard — nav.geometry.spec.ts exists because the tab bar's geometry
// was being argued about in comments — so every one of those is read off the running build here.
//
// ── WHERE IT MEASURES, AND WHY THAT PLACE ──────────────────────────────────────────────────────
// `/ui`, the design-system gallery (src/features/gallery/GalleryScreen.tsx). Step 2 changes no
// screen, so the twelve are not composed anywhere else yet — and even after step 9 they should be
// measured on a page that renders them ALL rather than through whatever a screen happens to
// compose. The gallery is outside `RequireAuth` and outside `AppShell` and reads nothing from the
// store, so unlike every other browser spec in this repo it does not pay the 78s cold chain and
// does not skip on a cloud build. `ready()` is deliberately not used: there is no world to wait
// for, and the thing to wait for is the gallery itself.
//
// ── THE ONE THING UNDER 44px, AND IT IS FENCED ─────────────────────────────────────────────────
// `Button size="sm"` is 36px — §5's "44 and 36", an in-row secondary action that only ever sits
// beside something on the floor. The gallery puts those two buttons in a box marked
// `data-targets="36"` and this spec skips that box BY NAME. That is deliberately awkward: an
// exception you have to declare in the markup is one somebody notices, where an id allowlist in a
// spec file is one that grows quietly.
//
// ── HOW TO RUN IT ───────────────────────────────────────────────────────────────────────────────
//     npm run build && npx vite preview --port 4213
//     PLAYWRIGHT_BASE_URL=http://localhost:4213/byeharu-voyage/ npx playwright test primitives.geometry
// localhost, never the 127.0.0.1 literal — playwright.config.ts's header carries that scar.

test.use({ viewport: PHONE })

/** The reach floor. navTabs.ts sets it, Explain.tsx and TabRow.tsx cite it, and §4.2 builds the
 *  52px row out of it (44 + the 8pt rhythm). */
const TOUCH_FLOOR = 44

/** `--spacing-row` in src/index.css: 3.25rem. A `Row` may GROW (it takes a second line), so this
 *  is asserted as the exact height of the four plain rows the gallery draws and as a floor
 *  everywhere else. */
const ROW = 52

/** `TRAY_PEEK` in src/components/ui/trayDetents.ts: one row plus one reach floor. */
const PEEK = 96

async function openGallery(
  page: import('@playwright/test').Page,
  request: Parameters<typeof reachable>[0],
  baseURL: string | undefined,
) {
  test.setTimeout(120_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('ui')
  await page.waitForSelector('[data-testid="gallery"]', { timeout: 30_000 })
  await page.waitForTimeout(250)
}

test(`row: a Row is ${ROW}px, and every target clears ${TOUCH_FLOOR}px at ${PHONE.width}px`, async ({
  page,
  request,
  baseURL,
}) => {
  await openGallery(page, request, baseURL)

  const report = await page.evaluate((floor) => {
    const rows = [...document.querySelectorAll('[data-testid="gallery-row"]')].map((r) =>
      Math.round(r.getBoundingClientRect().height),
    )
    // Every real control on the page. The fenced 36px box is skipped by name — see the header.
    const targets = [...document.querySelectorAll('button, a, input, [role="tab"]')]
      .filter((el) => !el.closest('[data-targets="36"]'))
      .map((el) => {
        const r = el.getBoundingClientRect()
        return {
          tag: el.tagName.toLowerCase(),
          text: ((el as HTMLElement).innerText || el.getAttribute('aria-label') || '').slice(0, 24),
          w: Math.round(r.width),
          h: Math.round(r.height),
        }
      })
      // A control scrolled out of the sheet's own box has no rectangle to judge.
      .filter((t) => t.w > 0 && t.h > 0)
    return {
      rows,
      targets,
      short: targets.filter((t) => t.h < floor || t.w < floor),
      pageScrollW: document.documentElement.scrollWidth,
      pageClientW: document.documentElement.clientWidth,
    }
  }, TOUCH_FLOOR)

  console.log(
    `PRIMITIVES @${PHONE.width}×${PHONE.height}: ${report.rows.length} rows ${JSON.stringify(report.rows)}, ` +
      `${report.targets.length} targets, ${report.short.length} under ${TOUCH_FLOOR}px`,
  )

  // NON-VACUITY, the floor every browser spec in this repo carries: point the base URL at a bare
  // host and vite preview answers with its own "did you mean" page, which would pass every
  // assertion below by having no rows and no controls at all.
  expect(report.rows.length, 'no [data-testid="gallery-row"] — did /ui render?').toBeGreaterThanOrEqual(4)
  expect(report.targets.length, 'the gallery rendered no controls at all').toBeGreaterThan(20)

  // 1. THE ROW IS 52px. Not "about 52": the whole reason `--spacing-row` is a token is that a row
  //    spelled `min-h-13` in one file and `py-3.5` in another drifts by two pixels and nobody sees
  //    it until two lists are side by side.
  expect(report.rows, `a Row is not ${ROW}px tall`).toEqual(report.rows.map(() => ROW))

  // 2. EVERY TARGET CLEARS 44. Height AND width — a 44px-tall chip 30px wide is still a miss.
  expect(
    report.short.map((t) => `${t.tag} "${t.text}" ${t.w}×${t.h}`),
    `a control is under the ${TOUCH_FLOOR}px reach floor. §5 allows exactly one exception — ` +
      `Button size="sm" at 36px — and the gallery fences it in a data-targets="36" box.`,
  ).toEqual([])

  // 3. And the page never moves sideways. Asserted last and never alone (layout.spec.ts's header
  //    explains why a green page-scroll check on its own is camouflage).
  expect(report.pageScrollW).toBeLessThanOrEqual(report.pageClientW)
})

test(`tray: the detents are ${PEEK}px, half the glass and all of it`, async ({ page, request, baseURL }) => {
  await openGallery(page, request, baseURL)

  const trayHeight = async () =>
    await page.evaluate(() => {
      const t = document.querySelector('[data-testid="demo-tray"]')
      if (!t) return { present: false, h: 0, position: '', bottom: 0 }
      const r = t.getBoundingClientRect()
      return {
        present: true,
        h: Math.round(r.height),
        position: getComputedStyle(t).position,
        bottom: Math.round(window.innerHeight - r.bottom),
      }
    })

  // Closed is CLOSED — the component returns null rather than standing at zero height, which is
  // the state a two-flag `open` + `detent` API gets wrong (Tray.tsx's header).
  expect((await trayHeight()).present, 'a tray is standing before anything opened one').toBe(false)

  // THE LADDER IS CLIMBED FROM THE TRAY'S OWN HANDLE, not from the gallery's chips. Once a tray is
  // standing it covers the bottom of the sheet, and the chip for the next stop is behind it — which
  // is the tray doing its job, and would make this spec a test of whether Playwright can click
  // through a dialog. The handle is a real control (↑ and ↓ step the same ladder a drag snaps to,
  // Tray.tsx), it is always on screen, and using it proves the keyboard path at the same time.
  const handle = page.getByRole('button', { name: 'Resize' })
  const stops: Record<string, number> = {}
  for (const [name, open] of [
    ['peek', async () => await page.getByTestId('tray-peek').click()],
    ['half', async () => await handle.press('ArrowUp')],
    ['full', async () => await handle.press('ArrowUp')],
  ] as const) {
    await open()
    // The rise is 240ms on --ease-sheet (§4.6); 500 is that with room, and the spec is measuring
    // where the tray LANDS, not how it travels.
    await page.waitForTimeout(500)
    const t = await trayHeight()
    stops[name] = t.h
    // 1. IT IS DOCKED, AND IT IS OUT OF FLOW. `fixed` is not a style choice here — it is the
    //    mechanism that makes "nothing above the press moves" true by construction rather than by
    //    care, which is the whole argument of Tray.tsx's header.
    expect(t.position, `the tray is ${t.position}, not fixed — it is IN FLOW and can reflow a grid`).toBe('fixed')
    expect(t.bottom, 'the tray is not on the bottom edge of the glass').toBe(0)
  }

  console.log(`TRAY DETENTS @${PHONE.height}px glass: ${JSON.stringify(stops)}`)

  // 2. THE THREE STOPS. peek is an absolute 96 (one row + one reach floor); half and full are
  //    fractions of the glass, so at 844 they are 422 and 844. One pixel of tolerance for the
  //    browser's own rounding of `50dvh`, and no more than one.
  expect(stops.peek, `peek is ${stops.peek}px, not ${PEEK}`).toBe(PEEK)
  expect(Math.abs(stops.half - PHONE.height / 2), `half is ${stops.half}px of a ${PHONE.height}px glass`).toBeLessThanOrEqual(1)
  expect(Math.abs(stops.full - PHONE.height), `full is ${stops.full}px of a ${PHONE.height}px glass`).toBeLessThanOrEqual(1)

  // 3. THE CLOSE CONTROL IS REAL AND IT DISMISSES. §5: "dismissed by drag or ✕".
  await page.getByTestId('tray-close').click()
  await page.waitForTimeout(400)
  expect((await trayHeight()).present, 'the ✕ did not dismiss the tray').toBe(false)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE OWNER'S RULE, AS A MEASUREMENT
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Said three times and built backwards twice (docs/OWNER_REQUESTS.md rows 6, 15, 25, 28, 45):
// *"when pressing sail, stop folding the sail … don't restruct anything."* tests/layout.spec.ts
// already holds it for COMMAND's good picker, where the fold is placed after the whole row by
// arithmetic. This holds it for the mechanism that replaces the arithmetic, and it holds it in
// BOTH modes — because §7 leaves the docked-or-inline choice with the owner, and the plan has to
// survive either answer.

/** Where every tile sits inside its FIELD, not inside the viewport — so the sheet scrolling to
 *  bring a control into view cannot be mistaken for the grid restructuring. */
const TILE_OFFSETS = () =>
  ([...document.querySelectorAll('[data-testid="gallery-tile"]')] as HTMLElement[]).map((t) => ({
    left: t.offsetLeft,
    top: t.offsetTop,
    w: Math.round(t.getBoundingClientRect().width),
    h: Math.round(t.getBoundingClientRect().height),
  }))

test('tray: opening one moves nothing above it — docked and inline', async ({ page, request, baseURL }) => {
  await openGallery(page, request, baseURL)

  const before = await page.evaluate(TILE_OFFSETS)
  expect(before.length, 'no [data-testid="gallery-tile"] — did the tile field render?').toBeGreaterThan(3)
  // The field is a FIELD: at 390px at least two tiles share a row. Said here as well as in
  // layout.spec because `TileField` is a different grid from the one that spec measures, and a
  // one-column field would satisfy every offset assertion below by having nothing beside anything.
  const perRow = new Map<number, number>()
  for (const t of before) perRow.set(t.top, (perRow.get(t.top) ?? 0) + 1)
  expect(Math.max(...perRow.values()), 'every tile is on a line of its own — that is a list').toBeGreaterThanOrEqual(2)

  // DOCKED. Press a tile's head, which is what a player does, and which opens the tray at peek.
  await page.getByTestId('gallery-tile').first().getByRole('button').first().click()
  await page.waitForTimeout(500)
  await expect(page.getByTestId('demo-tray')).toBeVisible()

  const afterDocked = await page.evaluate(TILE_OFFSETS)
  expect(
    afterDocked,
    'opening a DOCKED tray moved a tile. It is `fixed`; if this is red the tray has been given a ' +
      'place in the flow, and the owner has refused restructure-on-press three times.',
  ).toEqual(before)

  await page.getByTestId('tray-close').click()
  await page.waitForTimeout(400)

  // INLINE — the other answer to the same rule, and the one the owner may still choose. It IS in
  // flow, so what is BELOW it moves down; nothing at or above it may move, and the tiles are above.
  await page.getByTestId('tray-inline').click()
  await page.waitForTimeout(500)
  const inline = page.getByTestId('demo-tray-inline')
  await expect(inline).toBeVisible()
  expect(
    await inline.evaluate((el) => getComputedStyle(el).position),
    'the inline tray is not in flow — then it is the docked one wearing another name',
  ).toBe('relative')

  const afterInline = await page.evaluate(TILE_OFFSETS)
  expect(
    afterInline,
    'opening an INLINE tray moved a tile. It must land after everything it folds under, never ' +
      'inside the grid.',
  ).toEqual(before)
})

test('sheet: the title pins small on scroll, and a Note never prints the server code', async ({
  page,
  request,
  baseURL,
}) => {
  await openGallery(page, request, baseURL)

  const header = page.getByTestId('sheet-header')
  await expect(header).toHaveAttribute('data-pinned', 'false')
  // The TITLE is what shrinks, not the header's box — the box also carries the one trailing
  // control, which is on the 44px floor and does not move. `t-title` is 20px; `t-body` is 16px.
  const title = header.locator('h1')
  const large = await title.evaluate((el) => getComputedStyle(el).fontSize)

  await page.evaluate(() => {
    const box = document.querySelector('[data-testid="gallery"] > div')
    if (box) box.scrollTop = 400
  })
  await page.waitForTimeout(400)
  await expect(header).toHaveAttribute('data-pinned', 'true')
  const small = await title.evaluate((el) => getComputedStyle(el).fontSize)
  console.log(`SHEET TITLE: ${large} large → ${small} pinned`)
  expect(large, 'the unpinned title is not t-title').toBe('20px')
  expect(small, `the pinned title is ${small} and the large one ${large} — it did not shrink`).toBe('16px')

  // §5's refusal form: "the code never prints (it goes to `console.debug`)". §2 item 13 lists
  // thirteen kinds of developer vocabulary that had leaked onto player screens; the gallery hands
  // `Note` an `E_HOLD_FULL` on purpose so that this can be a measurement rather than a rule.
  expect(
    await page.locator('[data-testid="gallery"]').innerText(),
    'a server code reached the screen — Note.tsx writes it to console.debug and nowhere else',
  ).not.toContain('E_HOLD_FULL')
})

test('a tray does not animate for a player who asked it not to', async ({ page, request, baseURL }) => {
  // `page.emulateMedia`, not `test.use({ reducedMotion })`: the option exists on the runner but not
  // on this version's `Fixtures` type, and a spec that has to be cast to compile is a spec nobody
  // will trust. This says the same thing to the same engine.
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await openGallery(page, request, baseURL)
  await page.getByTestId('tray-half').click()
  await page.waitForTimeout(200)

  // §4.6: "prefers-reduced-motion collapses all to 0". src/index.css does it at the TOKEN — the
  // durations themselves go to 0ms — so nothing that reads them has a media query of its own, and
  // this is the proof that the collapse actually reaches a component.
  const duration = await page
    .getByTestId('demo-tray')
    .evaluate((el) => getComputedStyle(el).transitionDuration)
  expect(duration, `the tray still animates for ${duration} under prefers-reduced-motion`).toMatch(/^0m?s$/)
})
