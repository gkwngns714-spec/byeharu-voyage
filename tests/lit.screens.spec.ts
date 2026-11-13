import { readFileSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Page } from '@playwright/test'
import { translate, type TKey } from '../src/lib/i18n'
import { KO_SKILLS } from '../src/lib/i18n/names/skills'
import { arrivedAtEdge, ready, settled, WORLD_BOOT_MS } from './appReady.fixture'
import { serveVeteranWorld } from './manyFleets.fixture'
import { serveNpcOn } from './npcOn.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LIT SCREENS HOLD THEIR LINES (2026-11-14; docs/dev-log/2026-11-14-lit-screens.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, on a phone (row 318): *"word box overlapping, long words and sentences making new messy lines... fix all.
// especially on phone."* tests/small.screens.spec.ts holds the screens of 2026-11-12; this file holds what the fourth
// pass fixed on the screens lit since.
//
// THE LAWS, in English and Korean:
//   (1) THE YARD'S HULL TILES: a hull's tonnage is one line ("1,275 tons" stood as "1,275" over "tons"), and no hull's
//       name is turned inside a word, in the hulls under "More" too. At 320 and 390 px.
//   (2) THE ROUTE BAR'S FIVE BUTTONS: with the longest refusal words put into Confirm and Repeat, every button's words
//       are whole and on one line, and no button stands past the bar. At 320 and 390 px.
//   (3) A FLEET'S PAGE DRAWS ITS EMPTY AND LOCKED PLACES WITH ITS SHIPS: the tile field's height is the same from its
//       first frame (the places landed a moment later and pushed the page's foot down).
//   (4) EVERY SKILL HAS A KOREAN NAME (lib/i18n/names/skills.ts), so a skill's tile is not English under Korean.
//   (5) THE HQ'S TITLE: with "Port Royal" and "Island capital" put in at 320 px, the name and the kind are one line each (they
//       stood as "Port / Royal" and "Island / capital"), and the kind does not stand over the name.
//   (6) FIVE CHOICES ON A 320-PX GLASS: with "Market, Town, Production, Inn, Repair" put into Trade's five faces, no word stands
//       past its own cell ("Production" stood over the cells beside it).
//   (7) THE TOP BAR GIVES WAY WHOLE: with a six- and a eight-figure purse put in, the date and the hour are not cut, and every
//       piece of the right side is either wholly on the bar or wholly off it (in Korean at 390 px the date was cut to "06:…").
//   (8) A PICKER OF FLEETS KEEPS THEIR NAMES: eight fleets on the HQ's Cargo face, no name turned inside a word and none on more
//       than two lines ("Nossa Senhora da Estrela" stood on four, in four 76-px columns).
//   (9) A CITY SHEET'S HEAD ON THE MAP: with the longest city name put in at 320 px, the name is whole and "Send fleet" does not
//       stand on it or past the glass (산루카르데바라메다 stood over the button).
//  (10) A HARBOUR'S MERCHANTS at 320 px: no company turned inside a word ("Herma / nos / Ocam / po"), and her level does not stand
//       on her name.
// Nothing here asserts a price, a count or which hulls a yard builds: only names, lines and boxes.

const SKILLS = (JSON.parse(readFileSync(path.resolve('data', 'skills.json'), 'utf8')) as { skills: { code: string; name: string }[] }).skills

test('every skill has a Korean name, and no two skills share one', () => {
  const missing = SKILLS.filter((s) => !KO_SKILLS[s.code]).map((s) => s.code)
  expect(missing, 'skills with no Korean name').toEqual([])
  const names = SKILLS.map((s) => KO_SKILLS[s.code])
  expect(new Set(names).size, 'two skills share a Korean name').toBe(names.length)
  for (const n of names) expect(n, `"${n}" carries Latin letters`).not.toMatch(/[A-Za-z]/)
})

async function open(page: Page, route: string) {
  test.setTimeout(480_000)
  await page.goto(route)
  await ready(page)
  await page.evaluate(() => document.fonts.ready)
}

/** Under `scope`: every text whose words do not all stand whole (a word on two lines), and every element marked one-line
 *  (`whitespace-nowrap`) that stands on two. Self-contained: Playwright ships this function's source into the page. */
const READ_LINES = (scope: string) => {
  const faults: string[] = []
  const lines = (r: Range) => {
    const tops: number[] = []
    for (const b of r.getClientRects()) if (b.width > 0.5 && !tops.some((t) => Math.abs(t - b.top) < 4)) tops.push(b.top)
    return tops.length
  }
  for (const root of document.querySelectorAll(scope)) {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    for (let n = w.nextNode(); n; n = w.nextNode()) {
      const node = n as Text
      if (node.data.trim() === '' || node.parentElement?.closest('svg')) continue
      for (const m of node.data.matchAll(/[^\s-]+-?/g)) {
        const r = document.createRange()
        r.setStart(node, m.index)
        r.setEnd(node, m.index + m[0].length)
        if (lines(r) > 1) faults.push(`"${node.data.trim()}": the word "${m[0]}" stands on two lines`)
      }
      // a figure and its unit ("1,275 tons"): a text of two words, the first a number, is one line
      if (/^[\d.,]+\s\S+$/.test(node.data.trim())) {
        const r = document.createRange()
        r.selectNodeContents(node)
        if (lines(r) > 1) faults.push(`"${node.data.trim()}" stands on two lines`)
      }
    }
  }
  return [...new Set(faults)]
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  const lang = locale === 'ko-KR' ? 'ko' : 'en'
  for (const glass of [
    { width: 320, height: 640 },
    { width: 390, height: 844 },
  ] as const) {
    test.describe(`lit screens — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test("the yard's hull tiles: a tonnage is one line and no name is turned inside a word", async ({ page }) => {
        await open(page, 'port')
        await page.getByRole('tablist', { name: translate(lang, 'desk.cityBuildings') }).getByRole('tab', { name: translate(lang, 'town.f_building_yard'), exact: true }).click()
        const yard = page.getByTestId('port-yard')
        await expect(yard).toBeVisible({ timeout: 60_000 })
        await settled(yard)
        const more = page.getByTestId('yard-more')
        if ((await more.count()) > 0) await more.click()
        const tiles = yard.locator('[data-testid^="hull-"]')
        await expect(tiles.first()).toBeVisible()
        expect(await tiles.count(), 'the yard lists too few hulls').toBeGreaterThan(5)
        expect(await page.evaluate(READ_LINES, '[data-testid="port-yard"] [data-testid^="hull-"]'), `${locale} @${glass.width}: a hull tile's line is broken`).toEqual([])
      })

      test("the route bar's five buttons keep their words whole with the longest refusal in Confirm and Repeat", async ({ page }) => {
        await open(page, 'map')
        await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
        const pill = page.getByTestId('map-fleets-corner').locator('button[aria-expanded]')
        await pill.click()
        await page.getByTestId('map-fleet-row').first().click()
        await expect(page.getByTestId('map-detail-tray')).toBeVisible()
        await page.getByTestId('map-set-route').click()
        const bar = page.getByTestId('route-bar')
        await expect(bar).toBeVisible()
        const refusals = (['map.routeConfirm', 'map.routeNoWater', 'map.routeSame', 'map.routeTooFar', 'map.routeSupplies', 'map.routeSeaShut', 'map.routeChecking'] as TKey[]).map((k) => translate(lang, k))
        const faults = await page.evaluate((words) => {
          const out: string[] = []
          const bar = document.querySelector('[data-testid="route-bar"]')!.getBoundingClientRect()
          const buttons = ['undo', 'confirm', 'final', 'repeat', 'cancel'].map((id) => document.querySelector(`[data-testid="route-${id}"]`) as HTMLElement)
          const textOf = (e: HTMLElement) => {
            const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT)
            for (let n = w.nextNode(); n; n = w.nextNode()) if ((n as Text).data.trim() !== '') return n as Text
            return null
          }
          for (const word of words) {
            for (const id of [1, 3]) textOf(buttons[id])!.data = word
            const tops = new Set<number>()
            for (const b of buttons) {
              const node = textOf(b)!
              const r = document.createRange()
              r.selectNodeContents(node)
              const rects = [...r.getClientRects()].filter((x) => x.width > 0.5)
              const box = b.getBoundingClientRect()
              tops.add(Math.round(box.top))
              if (new Set(rects.map((x) => Math.round(x.top))).size > 1) out.push(`with "${word}": "${node.data}" stands on two lines`)
              if (rects.some((x) => x.left < box.left - 0.5 || x.right > box.right + 0.5)) out.push(`with "${word}": "${node.data}" stands past its button`)
              if (b.scrollWidth > b.clientWidth + 1) out.push(`with "${word}": "${node.data}" is cut (${b.scrollWidth} > ${b.clientWidth})`)
              if (box.left < bar.left - 0.5 || box.right > bar.right + 0.5) out.push(`with "${word}": "${node.data}" stands past the bar`)
            }
            // the bar's own words fit one line of buttons; only a long refusal may put the last button under
            if (word === words[0] && tops.size > 1) out.push('the five buttons with their own words stand on two lines')
          }
          return out
        }, refusals)
        expect(faults, `${locale} @${glass.width}: the route bar`).toEqual([])
      })
    })
  }

  test.describe(`lit screens — ${locale} at 320×640`, () => {
    test.use({ locale, viewport: { width: 320, height: 640 } })

    test("the HQ's title: the name and the kind are one line each, the kind under the name where they do not fit", async ({ page }) => {
      await open(page, 'city')
      await expect(page.getByTestId('city-building-grid')).toBeVisible({ timeout: 120_000 })
      const read = await page.evaluate(() => {
        const set = (id: string, text: string) => {
          const el = document.querySelector(`[data-testid="${id}"]`)
          if (!el) return null
          const node = document.createTreeWalker(el, NodeFilter.SHOW_TEXT).nextNode() as Text | null
          if (!node) return null
          node.data = text
          const r = document.createRange()
          r.selectNodeContents(node)
          const rects = [...r.getClientRects()].filter((b) => b.width > 0.5)
          return { lines: new Set(rects.map((b) => Math.round(b.top))).size, box: el.getBoundingClientRect() }
        }
        set('city-name', 'Port Royal')
        set('city-kind', 'Island capital')
        const name = set('city-name', 'Port Royal')
        const kind = set('city-kind', 'Island capital')
        if (!name || !kind) return null
        const over = kind.box.left < name.box.right - 1 && kind.box.right > name.box.left + 1 && kind.box.top < name.box.bottom - 1 && kind.box.bottom > name.box.top + 1
        return { name: name.lines, kind: kind.lines, over, right: Math.max(name.box.right, kind.box.right), glass: window.innerWidth }
      })
      expect(read, 'the HQ draws no title with a kind').not.toBeNull()
      expect(read!.name, `${locale}: "Port Royal" stands on ${read!.name} lines`).toBe(1)
      expect(read!.kind, `${locale}: "Island capital" stands on ${read!.kind} lines`).toBe(1)
      expect(read!.over, `${locale}: the kind stands over the name`).toBe(false)
      expect(read!.right, `${locale}: the title stands past the glass`).toBeLessThanOrEqual(read!.glass)
    })

    test('five choices keep their words inside their own cells', async ({ page }) => {
      await open(page, 'command')
      await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
      const faults = await page.evaluate((words) => {
        const set = [...document.querySelectorAll('[role="tablist"]')].find((g) => g.querySelectorAll('[role="tab"]').length === 5)
        if (!set) return ['no set of five choices on Trade']
        const out: string[] = []
        const tabs = [...set.querySelectorAll('[role="tab"]')] as HTMLElement[]
        const textOf = (tab: HTMLElement) => document.createTreeWalker(tab, NodeFilter.SHOW_TEXT).nextNode() as Text
        tabs.forEach((tab, i) => (textOf(tab).data = words[i]))
        const edge = set.getBoundingClientRect()
        for (const tab of tabs) {
          const node = textOf(tab)
          const r = document.createRange()
          r.selectNodeContents(node)
          const box = tab.getBoundingClientRect()
          for (const b of r.getClientRects()) if (b.left < box.left - 0.5 || b.right > box.right + 0.5) out.push(`"${node.data}" stands ${Math.round(Math.max(box.left - b.left, b.right - box.right))} px past its cell`)
          if (new Set([...r.getClientRects()].map((b) => Math.round(b.top))).size > 1) out.push(`"${node.data}" stands on two lines`)
          if (box.right > edge.right + 0.5) out.push(`"${node.data}": the cell stands past the set`)
        }
        return out
      }, ['Market', 'Town', 'Production', 'Inn', 'Repair'])
      expect(faults, `${locale}: a set of five choices at 320 px`).toEqual([])
    })
  })

  test.describe(`lit screens, the map's sheets — ${locale} at 320×640`, () => {
    test.use({ locale, viewport: { width: 320, height: 640 } })

    /** Press a harbour's name on the chart: Lisbon, or the named harbour nearest the middle that is not Lisbon. */
    async function pressHarbour(page: Page, lisbon: boolean) {
      await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
      await expect(page.locator('text[data-label-id^="port:"]').first()).toBeVisible()
      const at = await page.evaluate((lisbon) => {
        const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
        const mid = { x: chart.x + chart.width / 2, y: chart.y + chart.height / 2 }
        const all = [...document.querySelectorAll('text[data-label-id^="port:"]')]
          .map((el) => {
            const r = el.getBoundingClientRect()
            return { code: (el.getAttribute('data-label-id') ?? '').slice(5), x: r.x + r.width / 2, y: r.y + r.height / 2 }
          })
          .filter((c) => (c.code === 'LIS') === lisbon && c.x > chart.x + 30 && c.x < chart.right - 30 && c.y > chart.y + 70 && c.y < chart.bottom - 60)
          .sort((a, b) => Math.hypot(a.x - mid.x, a.y - mid.y) - Math.hypot(b.x - mid.x, b.y - mid.y))
        return all[0] ?? null
      }, lisbon)
      expect(at, 'no harbour name to press on the opening chart').not.toBeNull()
      await page.mouse.click(at!.x, at!.y)
      await expect(page.getByTestId('map-place-name')).toBeVisible()
      // the tray slides in from the right: measured only once it stands on the glass's edge
      await arrivedAtEdge(page.getByTestId('map-detail-tray'), 320)
    }

    test("a city sheet's head: a long name is whole and the button does not stand on it", async ({ page }) => {
      await open(page, 'map')
      await pressHarbour(page, false)
      const send = page.getByTestId('map-send-fleet')
      await expect(send, 'the head of a harbour she is not in carries no Send button').toBeVisible()
      const read = await page.evaluate((name) => {
        const head = document.querySelector('[data-testid="map-place-name"]')!
        const w = document.createTreeWalker(head, NodeFilter.SHOW_TEXT)
        let node: Text | null = null
        for (let n = w.nextNode(); n; n = w.nextNode()) if ((n as Text).data.trim() !== '') node = n as Text
        if (!node) return null
        node.data = name
        const r = document.createRange()
        r.selectNodeContents(node)
        const words = [...r.getClientRects()].filter((b) => b.width > 0.5)
        const button = document.querySelector('[data-testid="map-send-fleet"]')!.getBoundingClientRect()
        const broken = name.split(' ').some((word) => {
          const at = node!.data.indexOf(word)
          const one = document.createRange()
          one.setStart(node!, at)
          one.setEnd(node!, at + word.length)
          return new Set([...one.getClientRects()].filter((b) => b.width > 0.5).map((b) => Math.round(b.top))).size > 1
        })
        return {
          broken,
          over: words.some((b) => b.left < button.right - 1 && b.right > button.left + 1 && b.top < button.bottom - 1 && b.bottom > button.top + 1),
          off: button.right > window.innerWidth + 0.5 || words.some((b) => b.right > window.innerWidth + 0.5),
        }
      }, lang === 'ko' ? '산루카르데바라메다' : 'Sanlucar de Barrameda')
      expect(read, 'the head has no name').not.toBeNull()
      expect(read!.broken, `${locale}: the name is turned inside a word`).toBe(false)
      expect(read!.over, `${locale}: the name stands on the Send button`).toBe(false)
      expect(read!.off, `${locale}: the head stands past the glass`).toBe(false)
    })

    test("a harbour's merchants: no company is turned inside a word, and the figures do not stand on the name", async ({ page }) => {
      await serveNpcOn(page)
      await open(page, 'map')
      await pressHarbour(page, true)
      await page.getByTestId('map-city-tabs').getByRole('tab').nth(3).click()
      const rows = page.getByTestId('merchant-row')
      await expect(rows.first(), 'Lisbon lists no merchant').toBeVisible({ timeout: 60_000 })
      expect(await page.evaluate(READ_LINES, '[data-testid="merchant-row"]'), `${locale}: a merchant's row is broken`).toEqual([])
      const over = await rows.evaluateAll((els) =>
        els.flatMap((row) => {
          const name = row.querySelector('[data-testid="merchant-row-name"]')!.getBoundingClientRect()
          const line = row.querySelector('[data-testid="merchant-row-line"]')!.getBoundingClientRect()
          const level = row.querySelector('[data-testid="merchant-row-level"]')!.parentElement!.getBoundingClientRect()
          const hit = (a: DOMRect, b: DOMRect) => a.left < b.right - 1 && a.right > b.left + 1 && a.top < b.bottom - 1 && a.bottom > b.top + 1
          return hit(name, level) || hit(line, level) ? [`${row.textContent?.slice(0, 30)}: the level stands on her name`] : []
        }),
      )
      expect(over, `${locale}: a merchant's row`).toEqual([])
    })
  })

  for (const glass of [
    { width: 320, height: 640 },
    { width: 390, height: 844 },
  ] as const) {
    test.describe(`lit screens, the bar and the pickers — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test('the top bar gives way whole: the date is not cut and nothing on its right side is cut in half', async ({ page }) => {
        await open(page, 'fleets')
        await expect(page.getByTestId('fleet-row').first()).toBeVisible()
        const faults = await page.evaluate(() => {
          const out: string[] = []
          const purse = document.querySelector('[data-testid="purse"]')!
          const node = document.createTreeWalker(purse, NodeFilter.SHOW_TEXT).nextNode() as Text
          for (const figure of ['240,000', '99,960,000']) {
            node.data = figure
            const box = document.querySelector('[data-testid="top-bar-right"]')!.getBoundingClientRect()
            const date = document.querySelector('[data-testid="game-date"]')!.parentElement!
            if (date.scrollWidth > date.clientWidth + 1) out.push(`purse ${figure}: the date and hour are cut (${date.scrollWidth} > ${date.clientWidth})`)
            for (const id of ['purse', 'kst-clock', 'kst-word']) {
              const el = document.querySelector(`[data-testid="${id}"]`) as HTMLElement | null
              if (!el || el.getClientRects().length === 0) continue
              const b = el.getBoundingClientRect()
              const whollyOff = b.top >= box.bottom - 0.5
              const whollyOn = b.left >= box.left - 0.5 && b.right <= box.right + 0.5 && b.bottom <= box.bottom + 0.5
              if (!whollyOff && !whollyOn) out.push(`purse ${figure}: ${id} is cut in half`)
              if (id === 'purse' && !whollyOn) out.push(`purse ${figure}: the purse is not on the bar`)
            }
            if (document.documentElement.scrollWidth > window.innerWidth) out.push(`purse ${figure}: the page scrolls sideways`)
          }
          return out
        })
        expect(faults, `${locale} @${glass.width}: the top bar`).toEqual([])
      })

      test('a picker of fleets keeps their names: no word broken, none on more than two lines', async ({ page }) => {
        await serveVeteranWorld(page)
        await open(page, 'city')
        await page.getByTestId('city-building-production').click()
        const face = page.getByTestId('city-face-panel')
        await expect(face).toHaveAttribute('data-building', 'production')
        await face.getByRole('tab', { name: translate(lang, 'city.cargo'), exact: true }).click()
        const cargo = page.getByTestId('production-cargo')
        await expect(cargo).toBeVisible()
        const tabs = cargo.getByRole('tab')
        await expect(tabs.first()).toBeVisible()
        expect(await tabs.count(), 'the veteran has too few fleets in port').toBeGreaterThan(4)
        expect(await page.evaluate(READ_LINES, '[data-testid="production-cargo"] [role="tab"]'), `${locale} @${glass.width}: a fleet's name is broken`).toEqual([])
        const tall = await tabs.evaluateAll((els) =>
          els.flatMap((e) => {
            const r = document.createRange()
            r.selectNodeContents(e)
            const lines = new Set([...r.getClientRects()].filter((b) => b.width > 0.5).map((b) => Math.round(b.top))).size
            return lines > 2 ? [`"${e.textContent}" stands on ${lines} lines`] : []
          }),
        )
        expect(tall, `${locale} @${glass.width}: a fleet's name`).toEqual([])
      })
    })
  }

  test.describe(`lit screens — ${locale} at 390×844`, () => {
    test.use({ locale, viewport: { width: 390, height: 844 } })

    test("a fleet's page draws its empty and locked places with its ships: the tile field never grows after its first frame", async ({ page }) => {
      await open(page, 'fleets')
      const row = page.getByTestId('fleet-row').first()
      await expect(row).toBeVisible()
      // the Room card has been answered: the list is whole
      await expect(page.getByTestId('fleet-room')).toBeVisible()
      await settled(page.getByTestId('fleet-room'))
      await page.evaluate(() => {
        const seen: number[] = []
        ;(window as unknown as { tileHeights: number[] }).tileHeights = seen
        const tick = () => {
          const field = document.querySelector('[data-testid="fleet-tiles"]')
          if (field) seen.push(Math.round(field.getBoundingClientRect().height))
          requestAnimationFrame(tick)
        }
        requestAnimationFrame(tick)
      })
      await row.click()
      await expect(page.getByTestId('fleet-tiles')).toBeVisible()
      await expect(page.locator('[data-testid="fleet-place-empty"], [data-testid="fleet-place-locked"]').first(), 'the fleet page draws no place').toBeVisible()
      await page.waitForTimeout(1500)
      const heights = await page.evaluate(() => [...new Set((window as unknown as { tileHeights: number[] }).tileHeights)])
      expect(heights, `${locale}: the tile field changed height after it was drawn (px, in order)`).toHaveLength(1)
    })
  })
}
