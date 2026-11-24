import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { SECOND_FLEET_SQL } from './armada.fixture'
import { serveHqLit } from './hqLit.fixture'
import { makeLate, movesOf, sayMove, serveLateWorld, stubRead, watchBoxes } from './lateRead.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// NOTHING ON A PAGE MOVES BY ITSELF, PROVEN WITH THE READ MADE LATE (2026-11-25; tests/lateRead.fixture.ts says how and why).

test.beforeEach(async ({ request, baseURL }) => {
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
})

// FLEETS. Main's run 45433937707 read the fleets' card at 781 px, pressed a fleet, and read it at 833 px: `world.house_room` had
// answered between the two reads (asked 0.53 s before the first), and the New fleet row it draws stood up inside the card.
test('Fleets: the room read lands two seconds late and the fleets card and its rows stay where they stood', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveLateWorld(page, ['world.house_room'])
  await watchBoxes(page, { card: '[data-testid="fleets-list"]', row: '[data-testid="fleet-row"]' })
  await page.goto('fleets')
  await ready(page)
  // the late answer has landed when the row it decides has its last face, and the Room card it draws is up
  await expect(page.locator('[data-testid="fleet-new"], [data-testid="fleet-new-dark"]')).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('fleet-room')).toBeVisible()
  const { moves, seen } = await movesOf(page)
  expect(seen, 'the watch saw no fleets card').toContain('card#0')
  expect(seen, 'the watch saw no fleet row').toContain('row#0')
  expect(moves.map(sayMove), 'a box on Fleets moved by itself when the room read landed').toEqual([])
})

// HQ. Main's run 45346082006 read a cargo row on HQ's Production at 1513 px, pressed its cell, and read it at 1515 px: the per-hour
// figure had landed on the Rank strip between the two reads and made the strip 2 px taller. The strip now holds that room
// (Bridge.tsx's slot). The same cause stood one block lower: Best moves drew its filter chips and "none" before `world.hq_board`
// had answered (250 px at 390), and a dark board then answered "off" (60 px), so the Storage and every plate under
// it went up 190 px. Boxes are read from the company block's own corner: the hall's loading meter stands over that block and
// leaves by design when the hall is read, which is another matter than this read.
test('HQ: the board read lands two seconds late and the Rank strip, Best moves and the Storage stay where they stood', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveLateWorld(page, ['world.hq_board'])
  await watchBoxes(
    page,
    { strip: '[data-testid="hq-bridge"]', moves: '[data-testid="hq-board"]', storage: '[data-testid="corp-warehouse"]' },
    '[data-testid="hq-company"]',
  )
  await page.goto('city')
  await ready(page)
  // the late answer has landed when the board says which it is: dark as the world ships, or served
  await expect(page.locator('[data-testid="hq-board"][data-source]')).toBeVisible({ timeout: 120_000 })
  const { moves, seen } = await movesOf(page)
  for (const mark of ['strip#0', 'moves#0', 'storage#0']) expect(seen, `the watch saw no ${mark}`).toContain(mark)
  expect(moves.map(sayMove), 'a box on HQ moved by itself when the board read landed').toEqual([])
})

// THE TRADE DESK'S "FROM HERE" TILES, WIDE. Main's run 45444351462 failed the align law on `Sanlucar de Barrameda +4,166`: its
// cells' first lines sat 8.3 px apart. No read was late. The name is the one long enough to turn onto two lines in the 1280 desk's
// left pane, the profit was centred against both lines, and whether that harbour is among the three best sales is the market's
// state at that minute. Here every harbour has a name that turns, so the tile is drawn every run.
test('From here at 1280: a harbour name that turns onto two lines keeps the profit on its first line', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize({ width: 1280, height: 800 })
  await serveWorldImage(
    page,
    await patchedWorldImage('long-harbour-names', async (pg) => {
      await pg.exec(`update public.ports set name = name || ' de Barrameda'`)
    }),
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('from-here-tile').first()).toBeVisible({ timeout: 120_000 })
  const tiles = await page.getByTestId('from-here-tile').evaluateAll((els) =>
    els.map((el) => {
      // the centre of the first line of text under `cell`
      const firstLine = (cell: Element | null) => {
        if (!cell) return null
        const walk = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
        for (let n = walk.nextNode(); n; n = walk.nextNode()) {
          if (!n.textContent?.trim()) continue
          const range = document.createRange()
          range.selectNodeContents(n)
          const rects = [...range.getClientRects()].filter((x) => x.width > 0)
          if (rects[0]) return { y: rects[0].top + rects[0].height / 2, lines: new Set(rects.map((x) => Math.round(x.top))).size }
        }
        return null
      }
      const name = firstLine(el.querySelector('[data-testid="from-here-city"]'))
      const profit = firstLine(el.querySelector('[data-testid="from-here-profit"]'))
      return { text: (el.textContent ?? '').trim(), lines: name?.lines ?? 0, apart: name && profit ? Math.abs(name.y - profit.y) : null }
    }),
  )
  expect(tiles.some((x) => x.lines >= 2), `no name turned onto a second line: ${JSON.stringify(tiles)}`).toBe(true)
  for (const x of tiles) expect(x.apart, `${x.text}: the profit stands ${x.apart} px off the name's first line`).toBeLessThanOrEqual(2)
})

// ── THE SECOND ROUND (2026-11-25): what the first round found and left ────────────────────────────────────────────────────────────

// THE HALL'S LOADING METER stood in the page's flow over the company block and left when `world.town_hall` answered: the Rank
// strip and everything under it went up 44 px. It stands over the top of that block now, and takes no room to give back.
test('HQ: the hall read lands two seconds late and nothing goes up when the loading meter leaves', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveLateWorld(page, ['world.town_hall'])
  await watchBoxes(page, { strip: '[data-testid="hq-bridge"]', workers: '[data-testid="corp-workers"]', storage: '[data-testid="corp-warehouse"]' })
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-load-host')).toHaveCount(0, { timeout: 120_000 })
  await expect(page.getByTestId('hq-bridge')).toBeVisible()
  const { moves, seen } = await movesOf(page)
  expect(seen, 'the watch saw no Rank strip').toContain('strip#0')
  expect(moves.map(sayMove), 'a box on HQ moved by itself when the loading meter left').toEqual([])
})

// A BLOCK THAT IS THERE ONLY WHEN SOMETHING HAPPENED (a choice at sea, news from away, the country race) cannot
// be a fixed shape: only its read knows whether it is there. It holds the room it had last time (src/components/ui/HeldRoom.tsx). The
// first visit on a glass has nothing to hold and is not judged here; every visit after it is: the page is opened, left to settle, opened again with
// the same read late, and what stands under the block must stand still from its first frame.
async function secondVisit(page: Page, settled: () => Promise<void>): Promise<void> {
  await page.goto('city')
  await ready(page)
  await settled()
  await page.reload()
  await ready(page)
  await settled()
}

// BEST MOVES, THE STORAGE AND THE LEDGER ARE FIXED SHAPES (2026-11-25): the same boxes before their read, after it, and whatever it
// says. Remembering the last height could not hold them: PR #862's run drew one card more than the visit before (company 1166 then
// 1278 px). So this is judged on a FIRST visit, with the board late, in two worlds whose boards differ: every card the lit world
// serves, and the same board cut to ONE card. Nothing may move in either, the two must be one height, and neither a filter nor More
// may change it.
const ONE_CARD = `
  alter function world.hq_board() rename to hq_board__all;
  create function world.hq_board() returns jsonb language sql as $one$
    select case when b ? 'moves'
             then jsonb_set(b, '{moves}', coalesce((select jsonb_agg(m order by i) from jsonb_array_elements(b -> 'moves') with ordinality t(m, i) where i <= 1), '[]'::jsonb))
             else b end
      from (select world.hq_board__all() as b) x
  $one$;
  grant execute on function world.hq_board() to authenticated;`

test('HQ, the board lit: Best moves is three slots of one height whether the late board serves many cards or one, under any filter, and More opens over the page', async ({ browser, baseURL }) => {
  test.setTimeout(900_000)
  const heights: Record<string, number> = {}
  for (const world of ['many', 'one'] as const) {
    const context = await browser.newContext({ viewport: PHONE, baseURL })
    const page = await context.newPage()
    await page.addInitScript(() => window.localStorage.setItem('bv:welcome-seen', '1'))
    await serveHqLit(page, { served: true, late: ['world.hq_board'], also: world === 'one' ? { name: 'one-card', sql: ONE_CARD } : undefined })
    await watchBoxes(page, { company: '[data-testid="hq-company"]', board: '[data-testid="hq-board"]', plate: '[data-plate-mark]' }, '[data-testid="hq-company"]')
    await page.goto('city')
    await ready(page)
    await expect(page.locator('[data-testid="hq-board"][data-source="served"]')).toBeVisible({ timeout: 180_000 })
    await expect(page.locator('[data-testid="corp-ledger"]:not([data-state="asking"])')).toBeVisible({ timeout: 60_000 })
    await expect(page.locator('[data-testid="corp-warehouse"]:not([data-state="asking"])')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('hq-move-slot')).toHaveCount(3)
    const cards = await page.getByTestId('hq-moves').getByTestId('hq-move').count()
    if (world === 'one') expect(cards, 'the cut board draws one card').toBe(1)
    else expect(cards, 'the lit board draws three cards').toBe(3)
    const boardHeight = async () => Math.round((await page.getByTestId('hq-board').boundingBox())!.height)
    heights[world] = await boardHeight()

    // A FILTER: each chip in turn, the height unmoved
    const chips = page.getByTestId('hq-filters').locator('button:not([data-gave-way])')
    for (let i = 0; i < (await chips.count()); i++) {
      await chips.nth(i).click()
      expect(await boardHeight(), `the filter ${await chips.nth(i).innerText()} changed Best moves' height`).toBe(heights[world])
    }
    await chips.first().click()

    // MORE: every move, in a sheet over HQ; the page under it as it was
    if (world === 'many') {
      await page.getByTestId('hq-moves-more').click()
      await expect(page.getByTestId('hq-sheet-moves')).toBeVisible()
      expect(await page.getByTestId('hq-moves-all').getByTestId('hq-move').count(), 'the sheet holds more than the three').toBeGreaterThan(3)
      expect(await boardHeight(), 'More changed the page under its sheet').toBe(heights[world])
      await page.keyboard.press('Escape')
      await expect(page.getByTestId('hq-sheet-moves')).toHaveCount(0)
    } else {
      await expect(page.getByTestId('hq-moves-more')).toBeDisabled()
    }

    const { moves, seen } = await movesOf(page)
    expect(seen, 'the watch saw no plate').toContain('plate#0')
    expect(moves.map(sayMove), `the board of ${world}: a box on HQ moved by itself`).toEqual([])
    await context.close()
  }
  expect(heights.one, 'Best moves is one height with one card and with many').toBe(heights.many)
})

// THE WORKER LIST IS AS MANY ROWS AS THE WORLD ALREADY SAYS: her fleets, and her Land party when the Land's switch is lit. PR #862's
// second run: on a first visit the list waited as one row and the party's row landed 321 ms later, 112 px. Judged on a FIRST visit
// (nothing remembered), with the Land's read late.
test('HQ, the Land lit, a first visit: the Land read lands late and the party row fills a place that was already there', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveHqLit(page, { late: ['world.land'] })
  await watchBoxes(page, { workers: '[data-testid="corp-workers"]', board: '[data-testid="hq-board"]', plate: '[data-plate-mark]' }, '[data-testid="hq-company"]')
  await page.goto('city')
  await ready(page)
  // a first visit, and nothing remembered for the list in any case: it is not a held room
  expect(await page.evaluate(() => Object.keys(window.localStorage).filter((k) => k.includes('hq-workers')).length), 'the worker list remembers a height').toBe(0)
  await expect(page.locator('[data-held-room="hq-workers"]')).toHaveCount(0)
  await expect(page.getByTestId('corp-worker-list').locator('> li')).toHaveCount(2, { timeout: 180_000 })
  const { moves, seen } = await movesOf(page)
  for (const mark of ['workers#0', 'board#0', 'plate#0']) expect(seen, `the watch saw no ${mark}`).toContain(mark)
  expect(moves.map(sayMove), 'a box on HQ moved by itself when the Land read landed').toEqual([])
})

// THE STORAGE stood up when the third of its reads had answered. It is in the first frame now, a skeleton until then.
test('HQ: the Land, requests and warehouse reads land late and the Storage, the Ledger and the plates stay where they stood', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveLateWorld(page, ['world.land', 'world.requests', 'world.warehouse'], 1)
  await watchBoxes(page, { storage: '[data-testid="corp-warehouse"]', ledger: '[data-testid="corp-ledger"]', plate: '[data-plate-mark]' }, '[data-testid="hq-company"]')
  await page.goto('city')
  await ready(page)
  await expect(page.locator('[data-testid="corp-warehouse"][data-state="shed"]')).toBeVisible({ timeout: 180_000 })
  const { moves, seen } = await movesOf(page)
  for (const mark of ['storage#0', 'ledger#0', 'plate#0']) expect(seen, `the watch saw no ${mark}`).toContain(mark)
  expect(moves.map(sayMove), 'a box on HQ moved by itself when the Storage was read').toEqual([])
})

/** One choice open at sea and one lately settled, as `world.sea_choices` serves them (0486): the first draws a card over the workers,
 *  the second a line in "While you were away". */
const SEA = (() => {
  const option = (key: string, safe: boolean) => ({ key, p: 0.6, win: 400, lose: -200, ev: 160, safe })
  const choice = (id: string, state: 'open' | 'settled') => ({
    id,
    kind: 'storm',
    fleet: '00000000-0000-4000-8000-00000000f1ee',
    fleet_name: 'Gaivota',
    from: 'LIS',
    to: 'CAD',
    appears_at: '2026-01-01T00:00:00Z',
    deadline: '2099-01-01T00:00:00Z',
    stake: 1000,
    danger: 2,
    guns: 4,
    options: [option('ride', false), option('reef', true), option('run', false)],
    best: 'ride',
    chosen: state === 'open' ? null : 'reef',
    state,
    by: state === 'open' ? null : 'default',
    outcome: state === 'open' ? null : { option: 'reef', good: true, amount: 120, full: 120, by: 'default', kind: 'storm' },
    settled_at: state === 'open' ? null : '2026-01-02T00:00:00Z',
  })
  return { on: true, company: true, open: [choice('00000000-0000-4000-8000-0000000000a1', 'open')], recent: [choice('00000000-0000-4000-8000-0000000000a2', 'settled')] }
})()

test('HQ, a choice open at sea and news from away: on a second visit their room is held while both reads are late, and the workers under them stand still', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveWorldImage(
    page,
    await patchedWorldImage('sea-and-away-late', async (pg) => {
      await stubRead(pg, 'world.sea_choices', SEA)
      await stubRead(pg, 'world.away_report', { on: true, company: true, jobs: [], since: null, runs: 0, earned: 0 })
      await makeLate(pg, 'world.sea_choices', 2)
      await makeLate(pg, 'world.away_report', 2)
    }),
  )
  await watchBoxes(page, { strip: '[data-testid="hq-bridge"]', workers: '[data-testid="corp-workers"]', moves: '[data-testid="hq-board"]' }, '[data-testid="hq-company"]')
  await secondVisit(page, async () => {
    await expect(page.getByTestId('hq-sea')).toBeVisible({ timeout: 180_000 })
    await expect(page.getByTestId('hq-away-sea')).toBeVisible({ timeout: 60_000 })
  })
  const { moves, seen } = await movesOf(page)
  expect(seen, 'the watch saw no workers').toContain('workers#0')
  expect(moves.map(sayMove), 'a box on HQ moved by itself when the sea and away reads landed').toEqual([])
})

test('HQ, the country race lit: on a second visit the race holds its room while its read is late, and the company block keeps its height', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveHqLit(page, { race: true, late: ['world.nation_race'] })
  await watchBoxes(page, { company: '[data-testid="hq-company"]' }, '[data-testid="hq-company"]')
  await secondVisit(page, async () => {
    await expect(page.getByTestId('hq-race')).toBeVisible({ timeout: 180_000 })
  })
  const { moves, seen } = await movesOf(page)
  expect(seen, 'the watch saw no company block').toContain('company#0')
  expect(moves.map(sayMove), 'the company block changed its height by itself when the race read landed').toEqual([])
})

// FLEETS, ARMADAS. The first round named the armadas card as one that might stand up late between the fleets and the Room. It does
// not: `world.armadas` is read inside the world's own read and set in the same write as the fleets (worldStore.refresh), so the
// card is in the page's first frame. This holds that true with the read late.
test('Fleets: the armadas read lands two seconds late and the armadas card is there from the first frame, nothing moved', async ({ page }) => {
  test.setTimeout(600_000)
  await page.setViewportSize(PHONE)
  await serveWorldImage(
    page,
    await patchedWorldImage('armada-late', async (pg) => {
      await pg.exec(SECOND_FLEET_SQL)
      await makeLate(pg, 'world.armadas', 2)
    }),
  )
  await watchBoxes(page, { card: '[data-testid="fleets-list"]', armadas: '[data-testid="armadas-list"]' })
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('armadas-list')).toBeVisible({ timeout: 180_000 })
  await expect(page.locator('[data-testid="fleet-new"], [data-testid="fleet-new-dark"]')).toBeVisible({ timeout: 120_000 })
  const { moves, seen } = await movesOf(page)
  expect(seen, 'the watch saw no armadas card').toContain('armadas#0')
  expect(moves.map(sayMove), 'a box on Fleets moved by itself').toEqual([])
})
