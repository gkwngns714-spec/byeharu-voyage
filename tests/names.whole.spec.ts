/// <reference types="node" />
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Page } from '@playwright/test'
import { KO_GOODS } from '../src/lib/i18n/names/goods'
import { KO_PORTS } from '../src/lib/i18n/names/ports'
import { KO_HULLS } from '../src/lib/i18n/names/realms'
import { openDetail, ready, settled } from './appReady.fixture'
import { serveVeteranWorld, VETERAN_FLEETS } from './manyFleets.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A NAME IS PRINTED WHOLE (2026-11-11, the full-names slice; docs/dev-log/2026-11-11-full-names.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER'S RULE, ABSOLUTE: a NAME (a city, a good, a fleet, a ship, a captain, a house, a merchant, a route) is never cut
// with "…" in the game. It is printed whole everywhere, wrapping at a space if it must.
//
// Where a name stands it carries `data-name` (src/components/ui/Clip.tsx is the one component that prints a name; a summary
// row's title and a pop-up page's title carry the mark too). Two halves:
//
//   THE LINT (plain Node): no cutting class (`truncate`, `line-clamp-*`, `text-ellipsis`), no `<Clip cut>` and no "slice and
//     add …" may stand in src/ unless it is on the ALLOW list below WITH ITS REASON, and none at all may stand on an element
//     marked as a name. A new one fails here until someone decides, in writing, that what it cuts is not a name.
//
//   THE WALK (the served build): at 390 and 1,280 px, in English and Korean, in a veteran's world (eight fleets, one with the
//     longest name the chain allows, a captain with a 47-character name), every `data-name` on every walked screen is read:
//       (1) NOT CUT: no ellipsis rule and no clip on it or on any box around it, and it does not overflow its own box;
//       (2) NO WORD BROKEN: each word of it stands on one line (a name may turn at a space, or after its own hyphen or its own
//           middle dot: "Bird-of-" / "Paradise", "앵무새·" / "원숭이");
//       (3) INSIDE ITS ROW: it stands inside every box around it, and over none of its neighbours;
//       (4) NOTHING SCROLLS SIDEWAYS: not the page, not a scroller the name is in.
//     and then the same four AGAIN WITH THE LONGEST REAL NAMES PUT IN: the longest city names the world is seeded with
//     (data/ports.json), the longest goods (data/goods.json), the longest hulls (data/ships.generated.json), each in the
//     language shown, and for a fleet, a captain or a house the longest the data holds. A name's own kind is told by what it
//     prints: a slot that shows a city is given cities.
//   On "Your cargo" (the page the owner saw the cut on), a row's price, days and profit also stay together on one line: the
//   city's first line, or the next line where the city's longest word leaves them no room. The flag stays with the name.

const ROOT = path.resolve(process.cwd())
const SRC = path.join(ROOT, 'src')

// ── THE LINT ──────────────────────────────────────────────────────────────────────────────────────

/** WHAT MAY STILL CUT, AND WHY. `n` is how many cutting marks the file holds; a count that moves fails, so a new one is seen. */
const ALLOW: Record<string, { n: number; why: string }> = {
  'src/components/ui/Clip.tsx': {
    n: 1,
    why: 'the `cut` line itself: one line of figures in a fixed bar, read whole by a hover or a press; never asked for a name (the default prints whole)',
  },
  'src/app/TopBar.tsx': {
    n: 1,
    why: '<Clip cut>: the game date, hour and price countdown in the 32-px top bar on a phone: figures, not a name',
  },
  'src/components/ui/LoadMeter.tsx': {
    n: 1,
    why: 'the loading step in hand ("Opening the world"): a status line, not a name',
  },
  'src/features/map/RouteBar.tsx': {
    n: 3,
    why: "another open PR owns this file. The refusal is the server's sentence and the confirm word a verb; the summary line DOES carry the fleet's name and is listed as not fixed in docs/dev-log/2026-11-11-full-names.md",
  },
  'src/features/command/standingRouteDraft.ts': {
    n: 1,
    why: "another open PR owns this file. A route's name is cut to the server's 24 characters with \"…\": listed as not fixed in docs/dev-log/2026-11-11-full-names.md (lifting it needs the server's limit raised)",
  },
}

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f)
    return statSync(p).isDirectory() ? sourceFiles(p) : /\.tsx?$/.test(f) ? [p] : []
  })
}

/** The file's code with its comments blanked (line, block and JSX comments), line numbers kept. */
function code(text: string): string[] {
  let block = false
  return text.split(/\r?\n/).map((line) => {
    let out = ''
    for (let i = 0; i < line.length; i++) {
      if (block) {
        if (line.startsWith('*/', i)) {
          block = false
          i++
        }
        continue
      }
      if (line.startsWith('/*', i)) {
        block = true
        i++
        continue
      }
      if (line.startsWith('//', i) && !/https?:$/.test(line.slice(0, i))) break
      out += line[i]
    }
    return out
  })
}

const CUT_CLASS = /(?<![\w-])(truncate|text-ellipsis|line-clamp-[\w[\]]+)(?![\w-])/g
/** JS-side shortening: a slice or substring whose result is followed by an ellipsis. */
const CUT_JS = /\.(slice|substring|substr)\([^)]*\)\s*\}?\s*(…|\.\.\.)/g
const CUT_PROP = /<Clip\b[^>]*\bcut\b/g

test('LINT: nothing in src/ cuts text unless it is on the allow-list with its reason, and nothing marked as a name cuts at all', () => {
  const found: Record<string, number> = {}
  const onName: string[] = []
  for (const file of sourceFiles(SRC)) {
    const rel = path.relative(ROOT, file).split(path.sep).join('/')
    const lines = code(readFileSync(file, 'utf8'))
    lines.forEach((line, i) => {
      // only a class inside a string is a class: `truncate` as a bare word in code is something else
      const inString = [...line.matchAll(/(["'`])((?:(?!\1).)*)\1?/g)].map((m) => m[2]).join(' ')
      const hits = [...inString.matchAll(CUT_CLASS)].length + [...line.matchAll(CUT_JS)].length + [...line.matchAll(CUT_PROP)].length
      if (hits === 0) return
      found[rel] = (found[rel] ?? 0) + hits
      // an element marked as a name: the mark on the same element (the tag's lines around this one)
      const tag = lines.slice(Math.max(0, i - 3), i + 4).join('\n')
      const open = tag.lastIndexOf('<', tag.indexOf(line) + line.length)
      const el = tag.slice(open, tag.indexOf('>', open) + 1)
      if (/data-name\b/.test(el) || (/<Clip\b/.test(el) && !/\bcut\b/.test(el) && [...inString.matchAll(CUT_CLASS)].length > 0)) onName.push(`${rel}:${i + 1}`)
    })
  }
  expect(onName, 'a cutting class stands on an element marked as a name: a name is printed whole (KEEP_WORDS_CLASS, or <Clip>)').toEqual([])
  const faults: string[] = []
  for (const [file, n] of Object.entries(found)) {
    const allowed = ALLOW[file]
    if (!allowed) faults.push(`${file}: ${n} cutting mark(s) and no entry on the allow-list. If it can cut a NAME, print it whole (<Clip>, KEEP_WORDS_CLASS); if not, list it with its reason`)
    else if (allowed.n !== n) faults.push(`${file}: ${n} cutting mark(s), the allow-list says ${allowed.n} (${allowed.why})`)
  }
  for (const file of Object.keys(ALLOW)) if (!(file in found)) faults.push(`${file}: on the allow-list, but it cuts nothing any more: take it off`)
  for (const [file, a] of Object.entries(ALLOW)) expect(a.why.length, `${file}: the allow-list entry has no reason`).toBeGreaterThan(20)
  expect(faults, 'text is cut in src/ outside the allow-list').toEqual([])
})

test('LINT: the scan sees a cut when there is one (the rule is not vacuous)', () => {
  const sample = ['// truncate in a comment', '<span className="min-w-0 truncate">x</span>', 'const n = `${name.slice(0, 23)}…`', '{/* line-clamp-2 */}', '<Clip cut className="a">']
  const lines = code(sample.join('\n'))
  const count = (re: RegExp) => lines.reduce((n, l) => n + [...l.matchAll(re)].length, 0)
  expect([count(CUT_CLASS), count(CUT_JS), count(CUT_PROP)]).toEqual([1, 1, 1])
})

// ── THE LONGEST REAL NAMES ────────────────────────────────────────────────────────────────────────

const data = <T>(file: string) => JSON.parse(readFileSync(path.resolve('data', file), 'utf8')) as T
const PORTS = data<{ ports: { name: string }[] }>('ports.json').ports.map((p) => p.name)
const GOODS = data<{ goods: { id: string; name: string }[] }>('goods.json').goods
const HULLS = data<{ hulls: { name: string }[] }>('ships.generated.json').hulls.map((h) => h.name)
const OFFICERS = data<{ officers: { name: string }[] }>('officers.json').officers.map((o) => o.name)
const HOUSES = data<{ houses: { company: string; master: string; fleets: { name: string }[] }[] }>('npc-houses.json').houses

/** The names that ask the most of a box: the two longest, and the one with the longest single word. */
function hardest(names: readonly string[]): string[] {
  const all = [...new Set(names.filter((n) => n.trim() !== ''))]
  const byLength = [...all].sort((a, b) => b.length - a.length)
  const word = (n: string) => Math.max(...n.split(/\s+/).map((w) => w.length))
  const byWord = [...all].sort((a, b) => word(b) - word(a))
  return [...new Set([...byLength.slice(0, 2), byWord[0]])].filter((n) => n !== undefined)
}

type Kind = 'port' | 'good' | 'hull' | 'other'

function catalogue(ko: boolean): { kindOf: Record<string, Kind>; stress: Record<Kind, string[]> } {
  const ports = PORTS.map((n) => (ko ? (KO_PORTS[n] ?? n) : n))
  const goods = GOODS.map((g) => (ko ? (KO_GOODS[g.id] ?? g.name) : g.name))
  const hulls = HULLS.map((n) => (ko ? (KO_HULLS[n] ?? n) : n))
  // a fleet (the chain allows 24 characters), a captain, a house, a master, a merchant fleet: people's and players' names, one spelling in both languages
  const other = [...VETERAN_FLEETS, ...OFFICERS, ...HOUSES.flatMap((h) => [h.company, h.master, ...h.fleets.map((f) => f.name)])]
  const kindOf: Record<string, Kind> = {}
  for (const n of hulls) kindOf[n] = 'hull'
  for (const n of goods) kindOf[n] = 'good'
  for (const n of ports) kindOf[n] = 'port'
  return { kindOf, stress: { port: hardest(ports), good: hardest(goods), hull: hardest(hulls), other: hardest(other) } }
}

// ── THE MEASURE (runs in the page; self-contained) ────────────────────────────────────────────────

interface Read {
  faults: string[]
  names: number
  stressed: number
  /** For the dev-log: the narrowest box a name was read in, and the tallest a stressed name stood. */
  boxes: { text: string; width: number; lines: number }[]
}

const MEASURE = ({ kindOf, stress, scope }: { kindOf: Record<string, string>; stress: Record<string, string[]>; scope: string | null }): Read => {
  const faults: string[] = []
  const boxes: { text: string; width: number; lines: number }[] = []
  const root = scope ? document.querySelector(scope) : document.body
  if (!root) return { faults: [`${scope} is not on the page`], names: 0, stressed: 0, boxes }
  const visible = (e: Element) => {
    const r = e.getBoundingClientRect()
    if (r.width === 0 || r.height === 0) return false
    const s = getComputedStyle(e)
    return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0
  }
  const at = (e: Element) => e.closest('[data-testid]')?.getAttribute('data-testid') ?? e.tagName.toLowerCase()
  const texts = (e: Element) => {
    const out: Text[] = []
    const walk = document.createTreeWalker(e, NodeFilter.SHOW_TEXT)
    for (let n = walk.nextNode(); n; n = walk.nextNode()) if ((n.textContent ?? '').trim() !== '') out.push(n as Text)
    return out
  }
  const read = (el: HTMLElement, label: string) => {
    const say = (what: string) => faults.push(`${at(el)} "${label}": ${what}`)
    const r = el.getBoundingClientRect()
    // (1) not cut, by itself
    if (el.scrollWidth > el.clientWidth + 1) say(`overflows its own box (${el.scrollWidth} px in ${el.clientWidth})`)
    // (2) no word broken
    let lines = 0
    for (const node of texts(el)) {
      const text = node.data
      for (const m of text.matchAll(/[^\s·-]+[-·]?/g)) {
        const range = document.createRange()
        range.setStart(node, m.index)
        range.setEnd(node, m.index + m[0].length)
        const tops = new Set([...range.getClientRects()].filter((q) => q.width > 0).map((q) => Math.round(q.top)))
        if (tops.size > 1) say(`the word "${m[0]}" stands on ${tops.size} lines in a ${Math.round(r.width)}-px box`)
      }
      const all = document.createRange()
      all.selectNodeContents(node)
      lines = Math.max(lines, new Set([...all.getClientRects()].filter((q) => q.width > 0).map((q) => Math.round(q.top))).size)
    }
    boxes.push({ text: label, width: Math.round(r.width), lines })
    // (1) and (3), by every box around it; a scroller ends the walk on its own axis (what is past its edge is scrolled to, not cut)
    let x = true
    let y = true
    for (let a = el.parentElement; a && a !== document.documentElement && (x || y); a = a.parentElement) {
      const s = getComputedStyle(a)
      if (s.display === 'inline' || s.display === 'contents') continue
      const b = a.getBoundingClientRect()
      const who = at(a) === at(el) ? a.tagName.toLowerCase() : at(a)
      if (x) {
        if (s.textOverflow === 'ellipsis' && s.overflowX !== 'visible' && a.scrollWidth > a.clientWidth + 1) say(`an ellipsis cuts it (${who})`)
        const scrolls = s.overflowX === 'auto' || s.overflowX === 'scroll'
        if (scrolls) {
          if (a.scrollWidth > a.clientWidth + 1) say(`its scroller scrolls sideways (${who}: ${a.scrollWidth} px in ${a.clientWidth})`)
          x = false
        } else if (r.left < b.left - 1 || r.right > b.right + 1) {
          say(`${s.overflowX === 'visible' ? 'stands outside' : 'is clipped by'} ${who} (${Math.round(r.left)}–${Math.round(r.right)} in ${Math.round(b.left)}–${Math.round(b.right)})`)
          x = false
        }
      }
      if (y) {
        if (s.overflowY === 'auto' || s.overflowY === 'scroll') y = false
        else if (r.top < b.top - 1 || r.bottom > b.bottom + 1) {
          say(`${s.overflowY === 'visible' ? 'stands above or below' : 'is clipped top or bottom by'} ${who} (${Math.round(r.top)}–${Math.round(r.bottom)} in ${Math.round(b.top)}–${Math.round(b.bottom)})`)
          y = false
        }
      }
      // a page laid over the screen (a pop-up page, a tray) is its own glass: what is behind it is not around it
      if (s.position === 'fixed') break
    }
    // (3) over none of its neighbours: the boxes beside it, and beside the box it stands in
    for (const host of [el, el.parentElement]) {
      if (!host?.parentElement) continue
      for (const sib of host.parentElement.children) {
        if (sib === host || !visible(sib) || getComputedStyle(sib).position === 'absolute' || getComputedStyle(sib).position === 'fixed') continue
        const q = sib.getBoundingClientRect()
        const over = Math.min(r.right, q.right) - Math.max(r.left, q.left) > 1 && Math.min(r.bottom, q.bottom) - Math.max(r.top, q.top) > 1
        if (over && !sib.contains(el)) say(`stands over its neighbour "${(sib.textContent ?? '').trim().slice(0, 30)}"`)
      }
    }
    // (4)
    if (document.documentElement.scrollWidth > document.documentElement.clientWidth) say(`the page scrolls sideways (${document.documentElement.scrollWidth} px in ${document.documentElement.clientWidth})`)
  }
  const names = ([...root.querySelectorAll('[data-name]')] as HTMLElement[]).filter(visible)
  let stressed = 0
  for (const el of names) {
    const own = (el.textContent ?? '').replace(/\s+/g, ' ').trim()
    if (own === '') continue
    read(el, own)
    // the longest real names of its own kind, put in its own text
    const nodes = texts(el)
    const node = nodes[nodes.length - 1]
    if (!node) continue
    const was = node.data
    const kind = kindOf[was.trim()] ?? 'other'
    for (const name of stress[kind]) {
      node.data = name
      read(el, `${name} [put in for ${own}]`)
      stressed++
    }
    node.data = was
  }
  return { faults: [...new Set(faults)], names: names.length, stressed, boxes }
}

/** "Your cargo": in each city's row the price, the days and the profit stand together, on the line of the city's first line (or, where
 *  the city's longest word leaves them no room, on the next line), and the flag stands with the name's first word. */
const CARGO_ROWS = (name: string | null) => {
  const faults: string[] = []
  const rows = [...document.querySelectorAll('[data-testid="cargo-place"]')] as HTMLElement[]
  for (const row of rows) {
    const cell = row.querySelector('[data-testid="cargo-place-name"]') as HTMLElement
    const walk = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
    let node: Text | null = null
    for (let n = walk.nextNode(); n; n = walk.nextNode()) if ((n.textContent ?? '').trim() !== '') node = n as Text
    if (!node) continue
    const was = node.data
    if (name) node.data = name
    const range = document.createRange()
    range.selectNodeContents(node)
    const first = [...range.getClientRects()].filter((q) => q.width > 0)[0]
    const r = row.getBoundingClientRect()
    const n = cell.getBoundingClientRect()
    const bottoms: number[] = []
    for (const id of ['cargo-place-price', 'cargo-place-days', 'cargo-place-profit']) {
      const c = row.querySelector(`[data-testid="${id}"]`) as HTMLElement
      const q = c.getBoundingClientRect()
      if (q.width === 0) continue
      bottoms.push(q.bottom)
      // beside the name, on its first line; or, where the name's longest word leaves them no room, on a line of their own under it
      const beside = Math.abs(q.bottom - first.bottom) <= 2 && q.left >= n.right - 0.5
      const under = q.top >= n.bottom - 1
      if (!beside && !under) faults.push(`"${node.data.trim()}": ${id} stands neither on the name's first line nor under the name (${Math.round(q.bottom - first.bottom)} px off)`)
      if (q.right > r.right + 0.5 || q.left < r.left - 0.5) faults.push(`"${node.data.trim()}": ${id} stands outside its row`)
      if (c.scrollWidth > c.clientWidth + 1) faults.push(`"${node.data.trim()}": ${id} is cut`)
    }
    if (Math.max(...bottoms) - Math.min(...bottoms) > 2) faults.push(`"${node.data.trim()}": the price, the days and the profit do not stand on one line`)
    // the flag never stands alone: it is on the line of the name's first word
    const flag = cell.querySelector('img, svg')
    if (flag) {
      const f = flag.getBoundingClientRect()
      if (f.bottom < first.top || f.top > first.bottom) faults.push(`"${node.data.trim()}": the flag stands on another line than the name's first word`)
    }
    node.data = was
  }
  return { faults, rows: rows.length }
}

// ── THE WALK ──────────────────────────────────────────────────────────────────────────────────────

/** The two glasses the law is held at. `NAMES_WIDE=1` adds the 1,920-px desk for a measurement by hand (the dev-log's third column). */
const GLASSES = [{ width: 390, height: 844 }, { width: 1280, height: 800 }, ...(process.env.NAMES_WIDE ? [{ width: 1920, height: 1080 }] : [])]

const quiet = (page: Page) => page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})

for (const locale of ['en-US', 'ko-KR'] as const) {
  const ko = locale === 'ko-KR'
  for (const glass of GLASSES) {
    test.describe(`names are whole — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test('no name is cut, broken inside a word or out of its row, as it stands and with the longest real names put in', async ({ page }, info) => {
        test.setTimeout(1_500_000)
        const cat = catalogue(ko)
        const faults: string[] = []
        const log: string[] = []
        let surfaces = 0
        const look = async (where: string, scope: string | null = null, least = 1) => {
          await quiet(page)
          await page.evaluate(() => document.fonts.ready)
          const read = await page.evaluate(MEASURE, { ...cat, scope })
          surfaces++
          const narrow = [...read.boxes].sort((a, b) => a.width - b.width)[0]
          const tall = [...read.boxes].sort((a, b) => b.lines - a.lines)[0]
          log.push(
            `${where}: ${read.names} names, ${read.stressed} read again with a longest name, ${read.faults.length} faults` +
              (narrow ? `; narrowest "${narrow.text}" ${narrow.width} px; most lines "${tall.text}" ${tall.lines}` : ''),
          )
          expect(read.names, `${where}: no name was found to read: the walk is vacuous there`).toBeGreaterThanOrEqual(least)
          for (const f of read.faults) faults.push(`${where}: ${f}`)
        }
        /** Every face of the screen's first tab strip, pressed in turn. */
        const faces = async (where: string, scope: string | null = null, least = 0) => {
          const tabs = page.getByRole('tablist').first().getByRole('tab')
          await tabs.first().waitFor({ timeout: 60_000 })
          for (let i = 0; i < (await tabs.count()); i++) {
            // a tab that leaves the screen (the desk's Production) is walked as its own screen
            const before = page.url()
            await tabs.nth(i).click()
            await page.waitForTimeout(400)
            if (page.url().split('?')[0] !== before.split('?')[0]) {
              await page.goBack()
              await ready(page)
              continue
            }
            await look(`${where} › face ${i + 1}`, scope, least)
          }
        }
        const open = async (route: string) => {
          await page.goto(route)
          await ready(page)
        }
        await serveVeteranWorld(page)

        // TRADE, AND "YOUR CARGO" (the page the owner saw the cut on): buy one unit so the hold has a good and its cities
        await open('command')
        const card = page.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
        await expect(card).toBeVisible({ timeout: 120_000 })
        await card.getByTestId('trade-buy').click()
        const figure = page.getByTestId('good-detail').getByTestId('stepper-figure')
        await expect(figure).toBeVisible({ timeout: 60_000 })
        await figure.fill('1')
        await figure.press('Enter')
        await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 60_000 })
        await page.getByTestId('trade-act').click()
        await expect(page.getByTestId('trade-toast')).toBeVisible({ timeout: 60_000 })
        await open('command')
        await look('Trade')
        await openDetail(page, 'cargo-open')
        const cargo = page.getByTestId('cargo-open-page')
        await expect(cargo.getByTestId('cargo-place').first()).toBeVisible({ timeout: 120_000 })
        await settled(cargo)
        // the good's name, the page's title, and a city in every row
        await look('Trade › Your cargo', '[data-testid="cargo-open-page"]', 3)
        for (const name of [null, ...cat.stress.port]) {
          const rows = await page.evaluate(CARGO_ROWS, name)
          expect(rows.rows, 'Your cargo has no city row').toBeGreaterThan(0)
          for (const f of rows.faults) faults.push(`Trade › Your cargo, the row's line: ${f}`)
        }

        // THE DESK'S OTHER FACES (City carries the city's name over its buildings; Levels the ships and captains)
        await open('command')
        await faces('Desk')

        // THE CITY PAGE (its market chart names the good in hand) AND THE HQ's PRODUCTION
        await open('city')
        for (const tile of ['hall', 'market', 'production', 'port', 'inn']) {
          await page.getByTestId(`city-building-${tile}`).click()
          await page.waitForTimeout(400)
          if (tile === 'market') await expect(page.getByTestId('city-market-chart-good')).toBeVisible({ timeout: 120_000 })
          // the page's title is the city; the Market's chart names the good in hand
          await look(`City › ${tile}`, null, tile === 'market' ? 2 : 1)
        }
        await open('city?place=production')
        await look('Production', null, 0)

        // FLEETS: eight fleets, one with the longest name the chain allows; her page (the title, the ships)
        await open('fleets')
        await look('Fleets', null, 8)
        await page.getByTestId('fleet-row').filter({ hasText: 'Nossa Senhora da Estrela' }).click()
        await expect(page.getByTestId('fleet-page')).toBeVisible()
        await look('Fleets › a fleet', '[data-testid="fleet-page"]', 2)

        // YOU: the ships and six captains, one with a 47-character name
        await open('you')
        await look('You', null, 6)

        // STATS (cities, markets, merchant houses), RANK, ROUTES, THE COMPENDIUM
        await open('stats')
        await faces('Stats')
        await open('rank')
        await faces('Rank')
        await open('routes')
        await look('Routes', null, 0)
        await open('compendium')
        await faces('Compendium')

        // THE MAP'S CITY TRAY (the tray's title is the city)
        await open('map')
        await openCityPanel(page, 'LIS', ko ? (KO_PORTS.Lisbon ?? 'Lisbon') : 'Lisbon')
        await look('Map › Lisbon')

        await info.attach(`names-${locale}-${glass.width}.txt`, { body: [...log, '', ...faults].join('\n'), contentType: 'text/plain' })
        console.log(`${locale} @${glass.width}\n${log.join('\n')}\n${faults.length} faults\n${faults.join('\n')}`)
        expect(surfaces, 'the walk skipped screens').toBeGreaterThan(12)
        expect(faults, `${locale} @${glass.width}: a name is cut, broken or out of its row`).toEqual([])
      })
    })
  }
}
