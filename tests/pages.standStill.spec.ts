import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { movesOf, sayMove, serveLateWorld, watchBoxes } from './lateRead.fixture'
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
