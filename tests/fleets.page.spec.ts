import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable } from './appReady.fixture'
import { EXTRA_PURSE, SECOND_SHIP, serveDarkTwoShips, serveLitOneShip, serveLitTwoShips } from './fleetsPage.fixture'

// THE FLEETS PAGE A PLAYER CAN BUILD FLEETS WITH (F5, 2026-11-11; owner rows 180 and 316; docs/dev-log/2026-11-11-fleets-page.md).
//
// Every world here is a throwaway copy of this build's image with the room lit (or left dark) inside the copy only (tests/fleetsPage.fixture.ts). What is proven, at a
// phone (390×844), a narrow phone (320×640) and a laptop (1280×800), in English and in Korean:
//
//   THE FLOW   New fleet from the list (3 presses and a name) → a second fleet stands with the chosen name → a ship place is bought (the purse falls by the served price and
//              a locked tile opens) → a ship's Stats opens her sheet and leaves back to the same fleet → the ship is moved back, with the figures the page shows before the
//              press → the empty fleet says what it is and what to do → with no fleet room left, New fleet says the level and the price, and its Buy opens the third fleet.
//   DARK       the real state on prod until the switch is lit: "Not open yet", and no New fleet, no Buy, no Move anywhere on the page.
//   ONE SHIP   New fleet says a second ship comes from a build yard, and its press lands on the HQ's Port place.
//   THE LAWS   on every step: nothing scrolls sideways, no name is cut, a press moves no box, and every page is left both ways (its back press and Escape).
//
// No test here may skip: a build that is not served is a failure, not a pass.

const GLASSES = [
  { width: 390, height: 844 },
  // the narrow phone of the phone tidy (owner, 2026-11-12): nothing overlaps and no word is broken there either
  { width: 320, height: 640 },
  { width: 1280, height: 800 },
] as const
const LOCALES = ['en-US', 'ko-KR'] as const

const WORDS = {
  'en-US': { notOpen: 'Not open yet', trading: 'Trading 3', you: /Fleets 2 \/ 3 · Ships 2 \/ 9/, youDark: /Fleets 1 \/ 2 · Ships 2 \/ / },
  'ko-KR': { notOpen: '아직 안 열림', trading: '교역 3', you: /선단 2 \/ 3 · 배 2 \/ 9/, youDark: /선단 1 \/ 2 · 배 2 \/ / },
} as const

const NEW_FLEET = 'Armada do Sul Dourado'
const SHOTS = path.resolve('docs', 'dev-log', 'img')

/** The dev-log's pictures (docs/dev-log/2026-11-11-fleets-page.md), written only when FLEETS_PAGE_SHOTS is set: `1` writes them beside the dev-log, any other value is
 *  the folder to write them to. */
async function shot(page: Page, name: string) {
  const to = process.env.FLEETS_PAGE_SHOTS
  if (!to) return
  const dir = to === '1' ? SHOTS : path.resolve(to)
  mkdirSync(dir, { recursive: true })
  await page.screenshot({ path: path.join(dir, `2026-11-11-fleets-page-${name}.jpg`), type: 'jpeg', quality: 82 })
}

async function served(request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  expect(await reachable(request, baseURL ?? ''), `nothing is served at ${baseURL}: run a preview of this build first`).toBe(true)
}

async function openFleets(page: Page) {
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('fleet-row').first()).toBeVisible()
  await expect(page.getByTestId('fleet-room')).toBeVisible()
}

/** The purse on the status strip, as a number. */
async function purse(page: Page): Promise<number> {
  return Number(((await page.getByTestId('purse').first().textContent()) ?? '').replace(/[^\d]/g, ''))
}

/** THE LOOK LAWS, read off the glass as it stands: nothing scrolls sideways, no text in the Fleets screen or a layer over it is cut or ended with dots, no word is
 *  broken inside itself, and no two texts stand on each other (the phone tidy, owner 2026-11-12). */
async function laws(page: Page, where: string) {
  const broken = await page.evaluate(() => {
    const out: string[] = []
    const root = document.documentElement
    if (root.scrollWidth > root.clientWidth) out.push(`the page scrolls sideways (${root.scrollWidth} > ${root.clientWidth})`)
    const scopes = [...document.querySelectorAll('[data-testid="fleets"], [data-testid="you"], [data-detail-page], [data-testid="map-ship-panel"]')]
    for (const scope of scopes) {
      for (const el of scope.querySelectorAll<HTMLElement>('*')) {
        if (el.children.length > 0 || el.getClientRects().length === 0) continue
        const text = (el.textContent ?? '').trim()
        if (text === '') continue
        if (text.includes('…')) out.push(`"${text}" ends with dots`)
        // a cut is a line that hides part of itself: its own box, or the nearest box that clips it
        for (let box: HTMLElement | null = el; box && box !== scope; box = box.parentElement) {
          const style = getComputedStyle(box)
          if (style.textOverflow === 'ellipsis' && box.scrollWidth > box.clientWidth + 1) {
            out.push(`"${text}" is cut (${box.scrollWidth} > ${box.clientWidth})`)
            break
          }
        }
        const r = el.getBoundingClientRect()
        if (r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1)) out.push(`"${text}" stands outside the glass`)
      }
    }
    // A WORD KEEPS ITS LINE, AND NO TEXT STANDS ON ANOTHER: every piece of text on the glass, read as it is drawn. A text under an open layer is not on the glass
    // (the point in its middle belongs to the layer), so it is not read.
    const drawn: { text: string; left: number; top: number; right: number; bottom: number }[] = []
    const seen = new Set<Node>()
    for (const scope of scopes) {
      const walk = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT)
      for (let node = walk.nextNode(); node; node = walk.nextNode()) {
        const raw = node.textContent ?? ''
        const host = node.parentElement
        if (seen.has(node) || raw.trim() === '' || !host) continue
        seen.add(node)
        const range = document.createRange()
        range.selectNodeContents(node)
        const r = range.getBoundingClientRect()
        if (r.width === 0 || r.height === 0) continue
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        if (!hit || !(hit === host || host.contains(hit) || hit.contains(host))) continue
        drawn.push({ text: raw.trim(), left: r.left, top: r.top, right: r.right, bottom: r.bottom })
        for (const word of raw.matchAll(/\S{2,}/g)) {
          range.setStart(node, word.index)
          range.setEnd(node, word.index + word[0].length)
          const tops = new Set([...range.getClientRects()].filter((q) => q.width > 0).map((q) => Math.round(q.top)))
          if (tops.size > 1) out.push(`"${word[0]}" is broken inside the word (in "${raw.trim()}")`)
        }
      }
    }
    for (let i = 0; i < drawn.length; i++) {
      for (let j = i + 1; j < drawn.length; j++) {
        const a = drawn[i]
        const b = drawn[j]
        if (Math.min(a.right, b.right) - Math.max(a.left, b.left) > 2 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 2) out.push(`"${a.text}" stands on "${b.text}"`)
      }
    }
    return out
  })
  expect(broken, `${where}: the look laws`).toEqual([])
}

/** The boxes of every element with one of these test ids, in order: what a press may not move. */
async function boxes(page: Page, ids: readonly string[]) {
  return page.evaluate(
    (list) =>
      list.flatMap((id) =>
        [...document.querySelectorAll(`[data-testid="${id}"]`)].map((el) => {
          const r = el.getBoundingClientRect()
          return `${id} ${Math.round(r.left)},${Math.round(r.top)} ${Math.round(r.width)}×${Math.round(r.height)}`
        }),
      ),
    [...ids],
  )
}

for (const glass of GLASSES) {
  for (const locale of LOCALES) {
    const tag = `${glass.width}×${glass.height} ${locale}`
    const w = WORDS[locale]

    test.describe(tag, () => {
      test.use({ viewport: glass, locale })

      test(`lit: New fleet, a bought ship place, a ship's sheet, the move back, the empty fleet, a bought fleet — ${tag}`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        await served(request, baseURL)
        await serveLitTwoShips(page)
        await openFleets(page)
        const name = `${glass.width}-${locale.slice(0, 2)}`
        await expect(page.getByTestId('fleet-row')).toHaveCount(1)
        await laws(page, 'the list')
        await shot(page, `list-lit-${name}`)

        // ── NEW FLEET: three presses and a name ──────────────────────────────────────────────────────────────────────────────────────
        let presses = 0
        const list = ['fleet-row', 'fleet-new', 'fleets-company', 'fleet-room']
        const listBefore = await boxes(page, list)
        await page.getByTestId('fleet-new').click()
        presses++
        const newPage = page.getByTestId('fleet-new-page')
        await expect(newPage).toBeVisible()
        expect(await boxes(page, list), 'the press on New fleet moved the list').toEqual(listBefore)
        const choices = newPage.getByTestId('fleet-new-ship')
        await expect(choices).toHaveCount(2)
        await expect(newPage.getByTestId('fleet-new-make')).toBeDisabled()
        const pick = ['fleet-new-ship', 'fleet-new-name', 'fleet-new-make']
        const pickBefore = await boxes(page, pick)
        await choices.filter({ hasText: SECOND_SHIP }).click()
        presses++
        expect(await boxes(page, pick), 'picking a ship moved the page').toEqual(pickBefore)
        await newPage.getByTestId('fleet-new-name').fill(NEW_FLEET)
        await laws(page, 'the New fleet page')
        await shot(page, `new-fleet-${name}`)
        await newPage.getByTestId('fleet-new-make').click()
        presses++
        await expect(newPage).toHaveCount(0)
        await expect(page.getByTestId('fleet-row')).toHaveCount(2)
        await expect(page.getByTestId('fleet-row').filter({ hasText: NEW_FLEET })).toHaveCount(1)
        expect(presses, 'presses from the Fleets list to a second fleet').toBe(3)
        await expect(page.getByTestId('fleets-total')).toContainText('2')
        await expect(page.getByTestId('fleet-room-fleet').getByTestId('fleet-room-have')).toContainText('2 / 2')
        await laws(page, 'the list with two fleets')
        await shot(page, `two-fleets-${name}`)

        // ── THE FOUNDING FLEET'S PAGE: her places, and a ship place bought ───────────────────────────────────────────────────────────
        await page.getByTestId('fleet-row').first().click()
        const fleetPage = page.getByTestId('fleet-page')
        await expect(fleetPage).toBeVisible()
        // TWO STEPS (owner, 2026-11-14: "when pressed a fleet, show only ships"): her page is her ships, one row each; her places, totals and Rename are one row further
        await expect(fleetPage.getByTestId('fleet-ship-row')).toHaveCount(1)
        await laws(page, "the fleet's page")
        await fleetPage.getByTestId('fleet-more').click()
        const morePage = page.getByTestId('fleet-more-page')
        await expect(morePage).toBeVisible()
        await expect(morePage.getByTestId('fleet-place-empty')).toHaveCount(1)
        await expect(morePage.getByTestId('fleet-place-locked')).toHaveCount(5)
        await expect(morePage.getByTestId('fleet-totals')).toBeVisible()
        await expect(morePage.getByTestId('fleet-rename')).toBeVisible()
        // one Buy, on the first locked place, at the first price
        await expect(morePage.getByTestId('fleet-place-buy')).toHaveCount(1)
        await expect(morePage.getByTestId('fleet-place-locked').first()).toContainText('10,000')
        await expect(morePage.getByTestId('fleet-place-locked').nth(1)).toContainText('20,000')
        await laws(page, "the fleet's More page")
        await shot(page, `fleet-page-${name}`)
        // The Buy is brought onto the glass first, so the press itself scrolls nothing. The totals, Command and Rename stand ABOVE the places on the More page, so a
        // bought place (a shorter tile: Empty has no price and no Buy) can move none of them at any width.
        await morePage.getByTestId('fleet-place-buy').scrollIntoViewIfNeeded()
        const tiles = ['fleet-totals', 'fleet-rename', 'fleet-command']
        const tilesBefore = await boxes(page, tiles)
        const purseBefore = await purse(page)
        expect(purseBefore, 'the purse the fixture paid').toBeGreaterThanOrEqual(EXTRA_PURSE)
        await morePage.getByTestId('fleet-place-buy').click()
        await expect(morePage.getByTestId('fleet-place-empty')).toHaveCount(2)
        await expect(morePage.getByTestId('fleet-place-locked')).toHaveCount(4)
        await expect.poll(() => purse(page), { message: 'the purse falls by the served price of a ship place' }).toBe(purseBefore - 10_000)
        expect(await boxes(page, tiles), 'the Buy moved the totals or the foot').toEqual(tilesBefore)
        await expect(morePage.getByTestId('fleet-place-locked').first()).toContainText('20,000')
        await expect(page.locator('body')).not.toContainText('E_')
        // the More page is left by Escape, to the same fleet
        await page.keyboard.press('Escape')
        await expect(morePage).toHaveCount(0)
        await expect(fleetPage).toBeVisible()

        // ── ONE SHIP'S PAGE AND HER SHEET: a press on her row, Stats on her page, and back to the same fleet both ways ───────────────
        await fleetPage.getByTestId('fleet-ship-row').first().click()
        const shipPage = page.getByTestId('fleet-ship-page')
        await expect(shipPage).toBeVisible()
        await laws(page, "the ship's page")
        // (her sheet carries a `ship-stats` block of its own, so the page under it is measured by its sections and its Power line; Stats is brought onto the glass
        // first, so the press itself scrolls nothing)
        const shipBoxes = ['fleet-fold-section', 'ship-power']
        const stats = shipPage.getByTestId('ship-stats').first()
        await stats.scrollIntoViewIfNeeded()
        const shipBefore = await boxes(page, shipBoxes)
        await stats.click()
        const sheet = page.getByTestId('map-ship-panel')
        await expect(sheet).toBeVisible()
        await expect(sheet).toContainText('Gaivota')
        if (glass.width < 1024) expect(await boxes(page, shipBoxes), 'opening the sheet moved the page under it').toEqual(shipBefore)
        await page.waitForTimeout(400)
        await laws(page, "the ship's sheet")
        await shot(page, `ship-sheet-${name}`)
        await sheet.getByTestId('tray-close').click()
        await expect(sheet).toHaveCount(0)
        await expect(fleetPage).toBeVisible()
        await stats.click()
        await expect(sheet).toBeVisible()
        await page.keyboard.press('Escape')
        await expect(sheet).toHaveCount(0)
        await expect(shipPage, "Escape left the sheet AND the ship's page").toBeVisible()
        await page.keyboard.press('Escape')
        await expect(shipPage).toHaveCount(0)
        await expect(fleetPage, "Escape left the ship's page AND the fleet").toBeVisible()
        await page.keyboard.press('Escape')
        await expect(fleetPage).toHaveCount(0)

        // ── THE NEW FLEET'S PAGE: move her ship back, with the figures shown before the press ───────────────────────────────────────
        await page.getByTestId('fleet-row').filter({ hasText: NEW_FLEET }).click()
        await expect(fleetPage).toBeVisible()
        await expect(fleetPage.getByTestId('fleet-ship-row')).toHaveCount(1)
        await expect(fleetPage.getByTestId('fleet-ship-row')).toContainText(SECOND_SHIP)
        // Move is her own press, on the page her row opens
        await fleetPage.getByTestId('fleet-ship-row').first().click()
        await expect(shipPage).toBeVisible()
        await expect(shipPage.locator('h1')).toHaveText(SECOND_SHIP)
        // (the Move page prints two totals lines of its own, so the page under it is measured by its sections and its foot)
        const under = ['fleet-fold-section', 'ship-stats', 'ship-move']
        await expect(shipPage.getByTestId('ship-move')).toBeVisible()   // her moves are asked when her page opens; Move stands once they are answered
        await shipPage.getByTestId('ship-move').scrollIntoViewIfNeeded()   // on the glass first, so the press itself scrolls nothing
        const before = await boxes(page, under)
        await shipPage.getByTestId('ship-move').click()
        const movePage = page.getByTestId('ship-move-page')
        await expect(movePage).toBeVisible()
        expect(await boxes(page, under), 'the press on Move moved the page under it').toEqual(before)
        await expect(movePage.getByTestId('ship-move-ship')).toBeVisible()
        await expect(movePage.getByTestId('ship-move-now')).toBeVisible()
        // both fleets' totals as they are now: the one she leaves, and the one she may join
        await expect(movePage.getByTestId('fleet-totals')).toHaveCount(2)
        await expect(movePage.getByTestId('ship-move-target')).toHaveCount(1)
        await laws(page, 'the Move page')
        await shot(page, `move-${name}`)
        // leavable both ways: the back press, then again by Escape, each to the same fleet
        await movePage.locator('[data-detail-back]').click()
        await expect(movePage).toHaveCount(0)
        await expect(shipPage).toBeVisible()
        await shipPage.getByTestId('ship-move').click()
        await expect(movePage).toBeVisible()
        await page.keyboard.press('Escape')
        await expect(movePage).toHaveCount(0)
        await expect(shipPage).toBeVisible()
        await shipPage.getByTestId('ship-move').click()
        await movePage.getByTestId('ship-move-target').click()
        await expect(movePage).toHaveCount(0)
        // she has left this fleet, so her page here is gone with her and the fleet's page stands
        await expect(shipPage).toHaveCount(0)

        // ── THE EMPTY FLEET: said plainly, with what to do ───────────────────────────────────────────────────────────────────────────
        await expect(fleetPage.getByTestId('fleet-no-ships')).toBeVisible()
        await expect(fleetPage.getByTestId('fleet-empty-how')).toBeVisible()
        await expect(fleetPage.getByTestId('fleet-command')).toHaveCount(0)
        await expect(fleetPage.getByTestId('fleet-rename')).toBeVisible()
        await laws(page, "the empty fleet's page")
        await shot(page, `empty-fleet-${name}`)
        await fleetPage.locator('[data-detail-back]').first().click()
        await expect(fleetPage).toHaveCount(0)
        await expect(page.getByTestId('fleet-row')).toHaveCount(2)

        // ── NO FLEET ROOM LEFT: New fleet says the level and the price, and its Buy opens the third fleet ───────────────────────────
        await page.getByTestId('fleet-new').click()
        await expect(newPage).toBeVisible()
        const need = newPage.getByTestId('fleet-new-need-room')
        await expect(need).toBeVisible()
        await expect(need.getByTestId('fleet-new-level')).toContainText(w.trading)
        await expect(need.getByTestId('fleet-new-price')).toContainText('60,000')
        await laws(page, 'New fleet with no room')
        await shot(page, `new-fleet-no-room-${name}`)
        const purseThen = await purse(page)
        await need.getByTestId('fleet-new-buy').click()
        await expect(newPage.getByTestId('fleet-new-pick')).toBeVisible()
        await expect.poll(() => purse(page), { message: 'the purse falls by the served price of a fleet' }).toBe(purseThen - 60_000)
        await expect(newPage.getByTestId('fleet-new-ship')).toHaveCount(2)
        await newPage.locator('[data-detail-back]').click()
        await expect(newPage).toHaveCount(0)
        await expect(page.getByTestId('fleet-room-fleet').getByTestId('fleet-room-have')).toContainText('2 / 3')
        await expect(page.locator('body')).not.toContainText('E_')
        await laws(page, 'the list at the end')

        // ── YOU: one line, the same figures, a link back to Fleets ───────────────────────────────────────────────────────────────────
        await page.goto('you')
        await ready(page)
        await expect(page.getByTestId('you')).toBeVisible()
        const line = page.getByTestId('you-room')
        await expect(line).toHaveText(w.you)
        await laws(page, 'You')
        await shot(page, `you-${name}`)
        await line.click()
        await expect(page.getByTestId('fleets')).toBeVisible()
        await expect(page).toHaveURL(/\/fleets$/)
      })

      test(`dark: "Not open yet", and no New fleet, no Buy, no Move — ${tag}`, async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        await served(request, baseURL)
        await serveDarkTwoShips(page)
        await openFleets(page)
        const name = `${glass.width}-${locale.slice(0, 2)}`
        const sheet = page.getByTestId('fleets')

        // the list: New fleet is a line that says so, not a press
        await expect(sheet.getByTestId('fleet-new')).toHaveCount(0)
        const line = sheet.getByTestId('fleet-new-dark')
        await expect(line).toContainText(w.notOpen)
        expect(await line.evaluate((el) => el.closest('button, a') !== null || el.querySelector('button, a') !== null), 'the dark New fleet line can be pressed').toBe(false)
        await expect(sheet.getByTestId('fleet-room-dark')).toHaveText(w.notOpen)
        await expect(sheet.getByTestId('fleet-room').locator('button')).toHaveCount(0)
        await laws(page, 'the dark list')
        await shot(page, `list-dark-${name}`)

        // her page: two ships, five locked places that say "Not open yet", and nothing to buy or move
        await page.getByTestId('fleet-row').first().click()
        const fleetPage = page.getByTestId('fleet-page')
        await expect(fleetPage).toBeVisible()
        await expect(fleetPage.getByTestId('fleet-ship-row')).toHaveCount(2)
        await laws(page, "the dark fleet's ships")
        // 2026-11-14: her places, totals, Rename and Command are one row further
        await fleetPage.getByTestId('fleet-more').click()
        const morePage = page.getByTestId('fleet-more-page')
        await expect(morePage.getByTestId('fleet-place-locked')).toHaveCount(5)
        await expect(morePage.getByTestId('fleet-place-dark')).toHaveCount(5)
        await expect(morePage.getByTestId('fleet-place-dark').first()).toHaveText(w.notOpen)
        await laws(page, "the dark fleet's page")
        await shot(page, `fleet-page-dark-${name}`)
        for (const id of ['ship-move', 'fleet-place-buy', 'fleet-room-buy', 'fleet-new', 'fleet-new-buy', 'fleet-new-make']) {
          await expect(page.getByTestId(id), `dark: ${id} is drawn`).toHaveCount(0)
        }
        // what was there before is still there: her totals, Rename, Command, and each ship's Stats
        await expect(morePage.getByTestId('fleet-totals')).toBeVisible()
        await expect(morePage.getByTestId('fleet-rename')).toBeVisible()
        await expect(morePage.getByTestId('fleet-command')).toBeVisible()
        await page.keyboard.press('Escape')
        await expect(morePage).toHaveCount(0)
        await fleetPage.getByTestId('fleet-ship-row').nth(1).click()
        const shipPage = page.getByTestId('fleet-ship-page')
        await expect(shipPage).toBeVisible()
        await expect(shipPage.getByTestId('ship-move'), 'dark: Move is drawn on a ship').toHaveCount(0)
        await laws(page, "the dark ship's page")
        await shipPage.getByTestId('ship-stats').click()
        await expect(page.getByTestId('map-ship-panel')).toContainText(SECOND_SHIP)
        await page.keyboard.press('Escape')
        await expect(page.getByTestId('map-ship-panel')).toHaveCount(0)
        await expect(shipPage).toBeVisible()
        await page.keyboard.press('Escape')
        await expect(shipPage).toHaveCount(0)
        await expect(fleetPage).toBeVisible()

        // You says the room she has now, dark or lit
        await page.goto('you')
        await ready(page)
        await expect(page.getByTestId('you-room')).toHaveText(w.youDark)
        await laws(page, 'You, dark')
        await shot(page, `you-dark-${name}`)
      })

      test(`lit, one ship: New fleet says a second ship comes from a build yard, and goes there — ${tag}`, async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        await served(request, baseURL)
        await serveLitOneShip(page)
        await openFleets(page)
        const name = `${glass.width}-${locale.slice(0, 2)}`
        await page.getByTestId('fleet-new').click()
        const newPage = page.getByTestId('fleet-new-page')
        await expect(newPage.getByTestId('fleet-new-need-ship')).toBeVisible()
        await expect(newPage.getByTestId('fleet-new-pick')).toHaveCount(0)
        await expect(newPage.getByTestId('fleet-new-make')).toHaveCount(0)
        await laws(page, 'New fleet with one ship')
        await shot(page, `new-fleet-one-ship-${name}`)
        // leavable both ways
        await page.keyboard.press('Escape')
        await expect(newPage).toHaveCount(0)
        await page.getByTestId('fleet-new').click()
        await newPage.locator('[data-detail-back]').click()
        await expect(newPage).toHaveCount(0)
        await page.getByTestId('fleet-new').click()
        await newPage.getByTestId('fleet-new-yard').click()
        await expect(page).toHaveURL(/\/city\?port=[A-Z]+&place=port$/)
        await expect(page.getByTestId('city-face-panel')).toBeVisible({ timeout: 120_000 })
        await page.goBack()
        await expect(page.getByTestId('fleets')).toBeVisible({ timeout: 120_000 })
      })
    })
  }
}
