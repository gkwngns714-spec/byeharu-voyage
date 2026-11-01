import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { NAV_CELLS, tabWord } from '../src/app/navTabs'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CONSISTENCY — the laws one screen at a time, measured in the running build (2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, after finding the City page's rail lacked the Fleets cell the shell has:
//   *"this is only one thing that I HAVE FOUND. who knows what else? i am starting doubt your
//   ability."* — then: *"find everything and fix it"*.
//
// This file is the permanent net under that pass. The audit that found the defects walked 90
// screens (every route, desk face, Stats face, pop-up page and the Menu tray at 390×844 and
// 1280×800) and wrote its evidence to test-results/consistency-audit.json; the laws below are what
// survived it, each one a measurement rather than a comment:
//
//   1. ONE TAB TABLE. The shell rail's cells, order and hrefs are exactly `NAV_CELLS`, and the
//      Menu's rows are exactly its members. A hand-written rail cell (the defect the owner found)
//      fails here.
//   2. ONE WORD PER DESTINATION. Every tab screen's title equals the word on its rail cell (the
//      audit found Rank titled "Standings" while its cell said "Rank").
//   3. THE 44-PX FLOOR. Every visible control is at least 44×44. The design system's sanctioned
//      36-px size has NO user left on any walked screen (Command's City view went md, row 33);
//      the allowlist below stays as the one declared place, now empty (a future 36 must be
//      declared there, not filtered silently).
//   4. NO SCROLL. The document, a tab's Sheet and every pop-up page's root never scroll; no
//      visible box scrolls sideways. Lists scroll inside their own bounded panes.
//   5. NO PLACEHOLDER DASH where a figure is owed. Measured on the COMPACT screens — now
//      including the desk, whose good sparkline drew "—" below two served points until row 37
//      (it now draws NOTHING, and `sparkAbsence` below proves each gap is the served absence).
//      Inside a page a dash is sometimes the truth: a good no market prices has no figure, and
//      the economy watch's fields are dark in local mode — the app's documented "the server did
//      not price this side" (the first run flagged 16 of those; the dev-log records the
//      investigation, and the rule stays where a figure is actually owed).
//   6. NO DUPLICATE LABEL for two different controls on one screen.
//   7. TWO PLAIN WORDS at most on a summary row's title (the owner's label law).
//   8. REACHABILITY. Every top destination is a cell or a Menu row with a real href; the City page
//      renders the shell's own NavBar, and both rails must equal NAV_CELLS cell for cell.
//
// ── THE CITY LAW AT 320, MEASURED (the old fixme FLIPPED, 2026-11-01) ──────────────────────────
// #426 (merged 2026-10-31) made the City page render the shell's NavBar from the one table and the
// hall need no scroll at 390; the only owed law was 320×568, and the city slice (#429/#430) packed
// it. The `test.fixme` that excused it was itself a CI red (a skip counts as a failure), so it is
// now a REAL test at the foot, held to the served build's measured numbers: folded 278/278,
// expanded 289/278 (11 px inside the panel), the page 568/568 flat in both states.

const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

/** Every route this pass walks. `command` is the desk (no longer a tab, still a route); `city` is
 *  the HQ page with its own rail. The City's BUILDING faces are owned by the city slice and are
 *  measured only by its own spec today (the audit's evidence is in the dev-log). */
const ROUTES = ['command', 'fleets', 'map', 'stats', 'ledger', 'rank', 'routes', 'compendium', 'profile', 'you', 'city'] as const

/** The tab screens that print a Sheet title, and the route each one's rail word belongs to. */
const TITLED = [
  ['fleets', '/fleets'],
  ['stats', '/stats'],
  ['ledger', '/ledger'],
  ['rank', '/rank'],
  ['routes', '/routes'],
  ['compendium', '/compendium'],
  ['profile', '/profile'],
  ['you', '/you'],
] as const

const STATS_FACES = ['Overview', 'Markets', 'Cities', 'Merchants', 'Me'] as const
const DESK_FACES = ['Trade', 'City', 'Invest', 'Report'] as const

/** THE ONE DECLARED PLACE FOR A SUB-44 CONTROL — NOW EMPTY (consistency row 33 fixed: the Command
 *  desk City face's `City view` is the md 44-px size, and #426 removed the city faces' Back).
 *  `Button size="sm"` (36px, docs/UI_DIRECTION.md §5's in-row size) has no visible user on any
 *  walked screen. The mechanism stays so a future one must be DECLARED here by test id, not
 *  filtered silently. */
const SM_ALLOWED = new Set<string>()

interface Snapshot {
  doc: { sw: number; cw: number; sh: number; ch: number }
  sheet: { sh: number; ch: number; top: number } | null
  pageRoot: { sh: number; ch: number; top: number } | null
  hscroll: { testid: string | null; cls: string; sw: number; cw: number }[]
  controls: { tag: string; role: string | null; testid: string | null; label: string; w: number; h: number }[]
  dashes: { testid: string | null; text: string }[]
  duplicates: { label: string; where: string[] }[]
  summaries: { testid: string | null; title: string; words: number }[]
}

/** One screen as data. When a pop-up page is up, controls and dashes are read FROM THE PAGE — the
 *  covered tab behind it is not re-measured. Self-contained: Playwright ships this into the page. */
async function snapshot(page: Page): Promise<Snapshot> {
  return page.evaluate(() => {
    const vis = (el: Element) => {
      const r = el.getBoundingClientRect()
      const cs = getComputedStyle(el)
      return r.width > 1 && r.height > 1 && cs.visibility !== 'hidden' && cs.display !== 'none' && r.bottom > 0 && r.top < innerHeight + 1
    }
    const nearTid = (el: Element | null) => {
      let e: Element | null = el
      for (let i = 0; e && i < 6; i++, e = e.parentElement) {
        const t = e.getAttribute('data-testid')
        if (t) return t
      }
      return null
    }
    const word = (el: Element) => ((el.getAttribute('aria-label') ?? (el as HTMLElement).innerText ?? '') + '').replace(/\s+/g, ' ').trim()
    const dialog = document.querySelector('[data-detail-page]') as HTMLElement | null
    const scoped: ParentNode = dialog ?? document

    const controls = [...scoped.querySelectorAll('a, button, input, select, textarea, [role="button"], [role="tab"], [role="switch"], [role="link"]')]
      .filter((el) => vis(el))
      .map((el) => {
        const r = el.getBoundingClientRect()
        return {
          tag: el.tagName.toLowerCase(),
          role: el.getAttribute('role'),
          // THE CONTROL'S OWN ID, not an ancestor's: six cells inside one filter bar are six
          // controls, and an ancestor test id would merge them and hide a duplicate word.
          testid: el.getAttribute('data-testid'),
          label: word(el),
          w: Math.round(r.width * 10) / 10,
          h: Math.round(r.height * 10) / 10,
        }
      })

    const byLabel = new Map<string, string[]>()
    for (const c of controls) {
      if (c.label.length < 2) continue
      const key = c.label
      const list = byLabel.get(key) ?? []
      const id = c.testid ?? `${c.tag} ${c.label}`
      if (!list.includes(id)) list.push(id)
      byLabel.set(key, list)
    }
    const duplicates = [...byLabel.entries()].filter(([, v]) => v.length > 1).map(([label, where]) => ({ label, where }))

    const dashes = [...scoped.querySelectorAll('span, div, td, dd, strong')]
      .filter((el) => vis(el) && el.children.length === 0 && /^—/.test((el.textContent ?? '').trim()))
      .map((el) => ({ testid: nearTid(el), text: (el.textContent ?? '').trim() }))

    const summaries = [...scoped.querySelectorAll('[data-summary-row]')]
      .filter((el) => vis(el))
      .map((el) => {
        const titleEl = el.firstElementChild as HTMLElement | null
        const title = (titleEl?.textContent ?? '').replace(/\s+/g, ' ').trim()
        return { testid: el.getAttribute('data-testid'), title, words: title === '' ? 0 : title.split(' ').length }
      })

    const hscroll = [...document.querySelectorAll('*')]
      .filter((el) => {
        if (!(el instanceof HTMLElement) || !vis(el)) return false
        if (!/auto|scroll/.test(getComputedStyle(el).overflowX)) return false
        return el.scrollWidth > el.clientWidth + 1
      })
      .map((el) => ({
        testid: nearTid(el),
        cls: (el.getAttribute('class') ?? '').slice(0, 60),
        sw: (el as HTMLElement).scrollWidth,
        cw: (el as HTMLElement).clientWidth,
      }))

    const de = document.documentElement
    const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
    return {
      doc: { sw: de.scrollWidth, cw: de.clientWidth, sh: de.scrollHeight, ch: de.clientHeight },
      sheet: sheet ? { sh: sheet.scrollHeight, ch: sheet.clientHeight, top: sheet.scrollTop } : null,
      pageRoot: dialog ? { sh: dialog.scrollHeight, ch: dialog.clientHeight, top: dialog.scrollTop } : null,
      hscroll,
      controls,
      dashes,
      duplicates,
      summaries,
    }
  })
}

/** Every law that applies to any screen or page, as a list of failures (all of them, not the first). */
function violations(s: Snapshot, where: string, opts: { dashes?: boolean } = {}): string[] {
  const out: string[] = []
  if (s.doc.sw > s.doc.cw + 1) out.push(`${where}: the document scrolls sideways ${s.doc.sw}/${s.doc.cw}`)
  if (s.doc.sh > s.doc.ch + 1) out.push(`${where}: the document scrolls down ${s.doc.sh}/${s.doc.ch}`)
  if (s.sheet !== null) {
    if (s.sheet.top > 0) out.push(`${where}: the Sheet is already scrolled on arrival`)
    if (s.sheet.sh > s.sheet.ch + 1) out.push(`${where}: the Sheet scrolls ${s.sheet.sh}/${s.sheet.ch}`)
  }
  if (s.pageRoot !== null) {
    if (s.pageRoot.top > 0) out.push(`${where}: the page root is already scrolled`)
    if (s.pageRoot.sh > s.pageRoot.ch + 1) out.push(`${where}: the page root scrolls ${s.pageRoot.sh}/${s.pageRoot.ch}`)
  }
  for (const h of s.hscroll) out.push(`${where}: sideways scroller ${h.testid ?? h.cls} (${h.sw}/${h.cw})`)
  for (const c of s.controls) {
    if (c.w >= 44 && c.h >= 44) continue
    if (c.testid !== null && SM_ALLOWED.has(c.testid)) continue
    out.push(`${where}: ${c.tag}${c.testid ? `#${c.testid}` : ''} "${c.label.slice(0, 40)}" is ${c.w}×${c.h} — under the 44px floor`)
  }
  if (opts.dashes !== false) for (const d of s.dashes) out.push(`${where}: placeholder dash ${d.testid ?? '(leaf)'} "${d.text}" where a figure is owed`)
  for (const d of s.duplicates) out.push(`${where}: two controls share the label "${d.label}": ${d.where.join(', ')}`)
  for (const sm of s.summaries) if (sm.words > 2) out.push(`${where}: summary title "${sm.title}" is ${sm.words} words — the law is one or two`)
  return out
}

/** ROW 37's LAW (consistency audit): a good card draws a price line ONLY where the SERVED series
 *  has two or more points (`data-points`, off world.price_series via dayLine); below two it draws
 *  NOTHING — the absence is drawn as an absence, never as a dash. Read from the DOM, so the claim
 *  is made against the served number itself. */
async function sparkAbsence(page: Page, where: string): Promise<string[]> {
  return page.evaluate((where) => {
    const out: string[] = []
    for (const card of Array.from(document.querySelectorAll('[data-testid="trade-good"]'))) {
      const spark = card.querySelector('[data-testid="trade-good-spark"]')
      if (!spark) {
        out.push(`${where}: a good card has no spark slot`)
        continue
      }
      const points = Number(spark.getAttribute('data-points') ?? '0')
      const drawn = spark.querySelector('svg') !== null
      const text = (spark.textContent ?? '').trim()
      if (points >= 2 && !drawn) out.push(`${where}: a good with ${points} served points draws no line`)
      if (points < 2 && (drawn || text !== ''))
        out.push(`${where}: a good with ${points} served points draws ${drawn ? 'a line' : `"${text}"`} — the absence must be drawn as absence`)
    }
    return out
  }, where)
}

async function screen(page: Page, route: string) {
  await page.goto(route)
  await ready(page)
  await page.waitForTimeout(300)
}

interface RailCell {
  id: string
  tag: string
  href: string | null
  label: string
  w: number
  h: number
}

async function railCells(page: Page): Promise<RailCell[]> {
  return page.evaluate(() => {
    // #426: both rails are the shell NavBar, so `nav-bar` is the one cell list to read.
    const bar = document.querySelector('[data-testid="nav-bar"]')
    if (!bar) return []
    return [...bar.children].map((c) => {
      const r = c.getBoundingClientRect()
      return {
        id: c.getAttribute('data-testid') ?? '',
        tag: c.tagName.toLowerCase(),
        href: c.getAttribute('href'),
        label: (c.querySelector('[data-testid^="nav-label-"]')?.textContent ?? '').trim(),
        w: Math.round(r.width),
        h: Math.round(r.height),
      }
    })
  })
}

/** Open the Menu tray and return its rows, in order. The group cell is the bar's only button. */
async function menuRows(page: Page): Promise<{ href: string | null; label: string }[]> {
  const group = page.locator('[data-testid="nav-bar"] > button').first()
  await group.click()
  const panel = page.locator('[data-testid="nav-group-panel"]')
  await expect(panel).toBeVisible()
  const rows = await panel.locator('a').evaluateAll((as) =>
    as.map((a) => ({ href: a.getAttribute('href'), label: (a.textContent ?? '').replace(/\s+/g, ' ').trim() })),
  )
  await page.keyboard.press('Escape')
  await expect(panel).toHaveCount(0)
  return rows
}

/** EVERY SUMMARY ROW OPENS A PAGE, and the page obeys the laws. Returns how many were opened. */
async function walkPages(page: Page, failures: string[], where: string): Promise<number> {
  const rows = page.locator('[data-summary-row]')
  const count = await rows.count()
  let opened = 0
  for (let i = 0; i < count; i++) {
    const row = rows.nth(i)
    if (!(await row.isVisible())) continue
    const id = (await row.getAttribute('data-testid')) ?? `row${i}`
    await row.click()
    const dialog = page.locator('[data-detail-page]')
    if ((await dialog.count()) === 0) {
      failures.push(`${where}: summary ${id} opened no page`)
      continue
    }
    await expect(dialog.locator('[data-detail-back]').first()).toBeVisible()
    await page.waitForTimeout(120)
    // NO DASH BAN INSIDE A PAGE (see the header): a dash there can be the served absence itself.
    failures.push(...violations(await snapshot(page), `${where} › ${id}`, { dashes: false }))
    await dialog.locator('[data-detail-back]').last().click()
    await expect(page.locator('[data-detail-page]')).toHaveCount(0)
    opened++
  }
  return opened
}

test(`one rail table: the shell draws NAV_CELLS, its words and the Menu's rows, at ${SIZES[0].width}`, async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(SIZES[0])
  await screen(page, 'stats')

  const cells = await railCells(page)
  const expected = NAV_CELLS.map((c) => (c.kind === 'tab' ? { id: `nav-cell-${c.to}`, to: c.to } : { id: `nav-cell-${c.id}`, to: null }))
  expect(cells.map((c) => c.id), 'the bar is not the one tab table (navTabs.NAV_CELLS)').toEqual(expected.map((e) => e.id))
  expect(cells.length, 'the bar draws no cells — did the shell render?').toBe(5)

  for (const [i, cell] of cells.entries()) {
    const want = expected[i]
    // A DESTINATION IS A REAL ANCHOR to its route; a group is a button that reveals (never a route).
    if (want.to !== null) {
      expect(cell.tag, `${cell.id} is not an anchor`).toBe('a')
      expect(cell.href ?? '', `${cell.id} does not link to ${want.to}`).toMatch(new RegExp(`${want.to}$`))
      expect(cell.label, `${cell.id}'s word is not the shell dictionary's`).toBe(tabWord('en', want.to))
    } else {
      expect(cell.tag, `${cell.id} is not a group button`).toBe('button')
      expect(cell.label, 'the group is not worded Menu').toBe('Menu')
    }
    expect(cell.w, `${cell.id} is ${cell.w}px wide`).toBeGreaterThanOrEqual(44)
    expect(cell.h, `${cell.id} is ${cell.h}px tall`).toBeGreaterThanOrEqual(44)
  }

  // THE MENU'S ROWS ARE THE GROUP'S MEMBERS, in order, each a real href with the table's word.
  const group = NAV_CELLS.find((c) => c.kind === 'group')
  const members = group !== undefined && group.kind === 'group' ? group.members : []
  const rows = await menuRows(page)
  expect(rows.length, 'the Menu revealed no members').toBe(members.length)
  for (const [i, m] of members.entries()) {
    expect(rows[i].href ?? '', `Menu row ${i} does not link to ${m.to}`).toMatch(new RegExp(`${m.to}$`))
    expect(rows[i].label, `Menu row ${i} is not worded "${tabWord('en', m.to)}"`).toBe(tabWord('en', m.to))
  }
})

test.describe('the screen says the rail’s word', () => {
  for (const [route, to] of TITLED) {
    test(`${route}: title equals the nav word`, async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await page.setViewportSize(SIZES[0])
      await screen(page, route)
      const title = (await page.locator('[data-testid="sheet-header"] h1').innerText()).trim()
      const cell = page.getByTestId(`nav-cell-${to}`)
      let word: string
      if ((await cell.count()) > 0) {
        word = ((await page.getByTestId(`nav-label-${to}`).innerText()) ?? '').trim()
      } else {
        // A CABIN MEMBER: its word is on the Menu row that reaches it.
        const group = page.locator('[data-testid="nav-bar"] > button').first()
        await group.click()
        word = (await page.locator(`[data-testid="nav-group-panel"] a[href$="${to}"]`).innerText()).trim()
        await page.keyboard.press('Escape')
      }
      expect(title, `${route} titles itself "${title}" while its rail says "${word}"`).toBe(word)
    })
  }
})

/** PRESS A FACE TAB, BOUNDED. A tab whose word changed in the code (the fourth desk face became
 *  "Report" in #416 while this walk still said "Profit") made locator.click() wait for a tab that
 *  would never appear — the whole walk died on the 30-minute TEST timeout and named no cause. Ten
 *  seconds, then the walk records WHICH word was missing and moves on: a one-word defect is a
 *  one-line red, never a half-hour hang. */
async function pressFace(tabs: Locator, face: string, where: string, failures: string[]): Promise<boolean> {
  try {
    await tabs.getByRole('tab', { name: face, exact: true }).click({ timeout: 10_000 })
    return true
  } catch {
    failures.push(`${where}: the "${face}" tab was not pressable within 10 s — does the tablist still carry that word?`)
    return false
  }
}

for (const size of SIZES) {
  test(`every route, face and page obeys the laws at ${size.width}×${size.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(1_800_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)
    const failures: string[] = []
    let pagesOpened = 0
    // LIST PANELS MET (the unfold slice, 2026-11-02): a list that stands on the glass is the new unit of "a screen
    // that rendered", beside the summary pages that are leaving by law (U1). Counted where they stand.
    const panelsHere = () => page.locator('[data-list-panel]:visible').count()
    let panelsMet = 0
    let statsPanels = 0

    for (const route of ROUTES) {
      await screen(page, route)
      if (route !== 'stats') panelsMet += await panelsHere()
      // THE CITY'S FIGURES ARE SERVED, NOT PLACEHOLDERS: wait for the hall read before the dash
      // sweep, or a slow first read would be mistaken for a dash where a figure is owed.
      if (route === 'city') await page.getByTestId('city-hall-scroll').waitFor({ timeout: 60_000 })
      // The desk is held to the dash ban too (row 37 fixed): its good sparkline draws nothing below
      // two served points, and `sparkAbsence` below proves every gap is the served absence itself.
      failures.push(...violations(await snapshot(page), `${size.width} ${route}`))

      if (route === 'stats') {
        for (const face of STATS_FACES) {
          if (!(await pressFace(page.getByRole('tablist'), face, `${size.width} stats/${face}`, failures))) continue
          await page.waitForTimeout(500)
          failures.push(...violations(await snapshot(page), `${size.width} stats/${face}`))
          statsPanels += await panelsHere()
          pagesOpened += await walkPages(page, failures, `${size.width} stats/${face}`)
        }
      } else if (route === 'command') {
        for (const face of DESK_FACES) {
          if (!(await pressFace(page.getByRole('tablist', { name: 'Desk faces' }), face, `${size.width} desk/${face}`, failures))) continue
          await page.waitForTimeout(400)
          failures.push(...violations(await snapshot(page), `${size.width} desk/${face}`))
          // ROW 37: every good card's spark is a line iff the SERVED series holds two or more points.
          if (face === 'Trade') failures.push(...(await sparkAbsence(page, `${size.width} desk/${face}`)))
        }
      } else if (route === 'fleets') {
        // HER PAGE IS THE ONE DETAIL (owner, 2026-10-31): every fleet row opens it, and it obeys
        // the page law like any other.
        const n = await page.locator('[data-testid="fleet-row"]').count()
        for (let i = 0; i < n; i++) {
          await page.getByTestId('fleet-row').nth(i).click()
          const fleetPage = page.getByTestId('fleet-page')
          if ((await fleetPage.count()) === 0) {
            failures.push(`${size.width} fleets: fleet row ${i} opened no page`)
            continue
          }
          await page.waitForTimeout(250)
          failures.push(...violations(await snapshot(page), `${size.width} fleets/fleet${i}`))
          await page.locator('[data-detail-back]').last().click()
          await expect(page.getByTestId('fleet-page')).toHaveCount(0)
          pagesOpened++
        }
      } else if (route !== 'city' && route !== 'map') {
        pagesOpened += await walkPages(page, failures, `${size.width} ${route}`)
      }
    }

    // NON-VACUITY, REWRITTEN TO THE NEW LAW (2026-11-02): this floor was "more than 15 pop-up pages opened", and
    // Stats alone supplied 15 of them (five faces of summary rows). U1 takes those rows away — a list is on the
    // screen, not behind a press — so the floor counts what the walk now meets: every Stats face must stand its own
    // list panel (all five, by name), and the pages and panels together must stay a real walk. Each screen that
    // unfolds later trades its pages for a panel here; the sum does not fall.
    expect(statsPanels, 'the Stats faces did not each stand a list panel — are the lists back behind a press?').toBe(STATS_FACES.length)
    panelsMet += statsPanels
    expect(pagesOpened + panelsMet, 'the walk met almost no pages and list panels — did the screens render?').toBeGreaterThan(8)

    console.log(`CONSISTENCY ${size.width}×${size.height}: ${failures.length} violations`)
    for (const f of failures) console.log(`  ${f}`)
    expect(failures, 'the consistency laws are broken').toEqual([])
  })
}

// ── THE CITY PAGE — the doors, the figures and the glass (passing today) ────────────────────────
for (const size of [{ width: 390, height: 844 }, { width: 320, height: 568 }] as const) {
  test(`HQ at ${size.width}×${size.height}: every building door visible, no scroll, no dead band`, async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.setViewportSize(size)
    await screen(page, 'city')
    const m = await page.evaluate(() => {
      const pick = (id: string) => {
        const el = document.querySelector(`[data-testid="${id}"]`)
        if (!el) return null
        const r = el.getBoundingClientRect()
        return { t: Math.round(r.top), b: Math.round(r.bottom), l: Math.round(r.left), r: Math.round(r.right), w: Math.round(r.width), h: Math.round(r.height) }
      }
      const tiles = [...document.querySelectorAll('[data-testid^="city-building-"]')]
        .filter((e) => /^city-building-(hall|market|storage|forge|port|inn)$/.test(e.getAttribute('data-testid') ?? ''))
        .map((e) => {
          const r = e.getBoundingClientRect()
          return {
            id: e.getAttribute('data-testid') ?? '',
            w: Math.round(r.width),
            h: Math.round(r.height),
            inView: r.top >= 0 && r.bottom <= innerHeight + 1 && r.left >= 0 && r.right <= innerWidth + 1,
          }
        })
      const de = document.documentElement
      return {
        tiles,
        boxes: { header: pick('city-header'), buildings: pick('city-buildings'), summary: pick('city-summary'), grid: pick('city-building-grid'), rail: pick('city-rail'), hall: pick('city-hall-panel'), image: pick('city-info-image') },
        doc: { sw: de.scrollWidth, cw: de.clientWidth, sh: de.scrollHeight, ch: de.clientHeight },
      }
    })
    expect(m.doc.sh, 'the HQ page scrolls down').toBeLessThanOrEqual(m.doc.ch + 1)
    expect(m.doc.sw, 'the HQ page scrolls sideways').toBeLessThanOrEqual(m.doc.cw + 1)
    expect(m.tiles.length, 'the HQ frame must show all six doors (Hall · Market · Storage · Forge · Port · Inn)').toBe(6)
    for (const t of m.tiles) {
      expect(t.inView, `${t.id} is pushed off the glass at ${size.width}`).toBe(true)
      expect(t.h, `${t.id} is ${t.h}px tall`).toBeGreaterThanOrEqual(44)
      expect(t.w, `${t.id} is ${t.w}px wide`).toBeGreaterThanOrEqual(44)
    }
    // THE FRAME'S ORDER AND AIR (owner, 2026-10-31: "Pack them up … without scrolling down"): the
    // six doors stand above the split, the figures below it, and the rail follows the figures with
    // no dead band. (The earnings block is INSIDE the figures card since #426.)
    const b = m.boxes
    expect(b.header !== null && b.buildings !== null && b.grid !== null && b.summary !== null && b.rail !== null, 'a HQ frame block is missing').toBe(true)
    expect(b.grid!.b, 'the six doors overlap the split below them').toBeLessThanOrEqual(b.summary!.t + 1)
    expect(b.rail!.t - b.summary!.b, 'dead space between the figures and the rail').toBeLessThanOrEqual(24)
    expect(b.rail!.b, 'the rail hangs below the glass').toBeLessThanOrEqual(size.height + 1)
  })
}

// ── THE CITY RAIL IS THE SHELL RAIL (#426) ─────────────────────────────────────────────────────
test('the City rail equals the shell rail, cell for cell', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.setViewportSize(SIZES[0])
  await screen(page, 'city')
  const city = await railCells(page)
  await screen(page, 'stats')
  const shell = await railCells(page)
  // #426 renders the shell's own NavBar on the City page, both from the ONE tab table; this is the
  // independent DOM guard (nav.rails.spec is the slice's own).
  expect(city.map((c) => c.id)).toEqual(shell.map((c) => c.id))
  expect(city.map((c) => c.label)).toEqual(shell.map((c) => c.label))
  for (const [i, c] of city.entries()) expect(c.href).toBe(shell[i].href)
})

test('HQ: a building press changes only the split; the six doors and the frame stay at 390 and 320', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  const FRAME = ['city-header', 'city-buildings', 'city-building-grid', 'city-summary', 'city-rail']
  for (const size of [{ width: 390, height: 844 }, { width: 320, height: 568 }]) {
    await page.setViewportSize(size)
    await screen(page, 'city')
    await page.getByTestId('city-hall-scroll').waitFor({ timeout: 60_000 })
    const boxes = () =>
      page.evaluate((ids: string[]) =>
        ids
          .map((id) => {
            const el = document.querySelector(`[data-testid="${id}"]`)
            if (!el) return `${id}:missing`
            const r = el.getBoundingClientRect()
            return `${id}:${Math.round(r.left)},${Math.round(r.top)},${Math.round(r.width)},${Math.round(r.height)}`
          })
          .join('|'), FRAME)
    const before = await boxes()
    // AT 390 THE HALL ITSELF NEEDS NO SCROLL (owner: "right now city hall i need to scroll down").
    if (size.width === 390) {
      const fit = await page.getByTestId('city-hall-scroll').evaluate((el) => ({ sh: (el as HTMLElement).scrollHeight, ch: (el as HTMLElement).clientHeight }))
      expect(fit.sh, 'the hall panel scrolls at 390').toBeLessThanOrEqual(fit.ch + 1)
    }
    for (const b of ['hall', 'market', 'storage', 'forge', 'port', 'inn']) {
      await page.getByTestId(`city-building-${b}`).click()
      await page.waitForTimeout(350)
      if (b === 'hall') {
        expect(await page.getByTestId('city-face-panel').count(), 'the hall opened a face panel').toBe(0)
        await expect(page.getByTestId('city-hall-panel')).toBeVisible()
      } else {
        const panel = page.getByTestId('city-face-panel')
        await expect(panel).toBeVisible()
        await expect(panel).toHaveAttribute('data-building', b)
        const w = (await panel.boundingBox())!.width
        expect(w, `the ${b} face is a full-screen layer, not the in-place panel`).toBeLessThan(size.width - 1)
      }
      expect(await boxes(), `pressing ${b} moved the HQ frame at ${size.width}`).toBe(before)
      const m = await page.evaluate(() => ({
        sw: document.documentElement.scrollWidth,
        cw: document.documentElement.clientWidth,
        sh: document.documentElement.scrollHeight,
        ch: document.documentElement.clientHeight,
      }))
      expect(m.sh, `pressing ${b} scrolled the page at ${size.width}`).toBeLessThanOrEqual(m.ch + 1)
      expect(m.sw, `pressing ${b} sheared the page sideways at ${size.width}`).toBeLessThanOrEqual(m.cw + 1)
    }
    // Back to the hall; the frame is still where it was.
    await page.getByTestId('city-building-hall').click()
    await expect(page.getByTestId('city-hall-panel')).toBeVisible()
    expect(await boxes(), `returning to the hall moved the frame at ${size.width}`).toBe(before)
  }
})

// THE HALL AT 320 — MEASURED, NOT EXCUSED (the city slice packed it: #429/#430). The old
// `test.fixme` here excused a defect that no longer exists; a skip is a red in CI's counting, so
// this is a real test now, held to the numbers measured on the served build (2026-11-01,
// origin/main 0ef5281f): FOLDED — page 568/568, panel 278/278 (no scroll); EXPANDED — page
// 568/568 (still flat), the book 125 px inside a 278-px panel, panel scroll 289/278: 11 px of
// scroll INSIDE the panel and never on the page. A regression past those numbers fails here.
test('HQ at 320: the page never scrolls; the folded hall fits, and the expanded book keeps its measured 11 px', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.setViewportSize({ width: 320, height: 568 })
  await screen(page, 'city')
  await page.getByTestId('city-hall-scroll').waitFor({ timeout: 60_000 })
  const read = () =>
    page.evaluate(() => {
      const de = document.documentElement
      const panel = document.querySelector('[data-testid="city-hall-scroll"]') as HTMLElement
      const book = document.querySelector('[data-testid="city-hall-book"]')
      return {
        page: { sh: de.scrollHeight, ch: de.clientHeight },
        panel: { sh: panel.scrollHeight, ch: panel.clientHeight },
        book: book === null ? null : Math.round(book.getBoundingClientRect().height),
      }
    })

  // FOLDED — the page is flat and the panel fits
  const folded = await read()
  expect(folded.page.sh, `the page scrolls at 320: ${folded.page.sh}/${folded.page.ch}`).toBeLessThanOrEqual(folded.page.ch + 1)
  expect(folded.panel.sh, `the folded hall scrolls: ${folded.panel.sh}/${folded.panel.ch}`).toBeLessThanOrEqual(folded.panel.ch + 1)
  expect(folded.book, 'the book stands open before its fold is pressed').toBeNull()

  // EXPANDED — the page stays flat; the book scrolls INSIDE the panel by its measured 11 px
  await page.getByTestId('city-hall-influence').click()
  await expect(page.getByTestId('city-hall-book')).toBeVisible()
  const open = await read()
  expect(open.page.sh, `expanding the book scrolled the page at 320: ${open.page.sh}/${open.page.ch}`).toBeLessThanOrEqual(open.page.ch + 1)
  const inner = open.panel.sh - open.panel.ch
  expect(inner, `the expanded book no longer overflows its panel — re-state this truth: ${open.panel.sh}/${open.panel.ch}`).toBeGreaterThanOrEqual(0)
  expect(inner, `the expanded book's internal scroll grew past its measured 11 px: ${open.panel.sh}/${open.panel.ch}`).toBeLessThanOrEqual(12)
})

// ── ONE HOME PER FACT (owner, 2026-10-31: *"no info duplicate info needed… this goes for every
// parts of the game"*) ─────────────────────────────────────────────────────────────────────────
// The inventory (docs/dev-log/2026-10-31-no-duplicates.md) walked every screen's visible lines and
// found the facts printed on more than one tab. Each repeat was removed from the tab whose subject
// it is not; this test holds the removals:
//   * the captains' board is RANK's — Stats/Me no longer repeats it;
//   * the desk's cargo DOOR carries no figure (Fleets is the home); the strip keeps her hold,
//     because the desk acts on that hold (stated judgment call);
//   * the hall's five figures (Population · Gold · Status · Relationship · Employees) never
//     appear outside the City screen.
test('one home per fact: the captains board is Rank’s, the desk’s cargo door is a door, the hall’s figures stay in the City', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(SIZES[0])
  const failures: string[] = []

  // STATS/ME — the captains board has ONE home, and it is not here
  await screen(page, 'stats')
  if (!(await pressFace(page.getByRole('tablist'), 'Me', 'stats/Me', failures))) return expect(failures, 'the Me face did not open').toEqual([])
  if ((await page.getByTestId('stats-leaderboard').count()) !== 0)
    failures.push('stats/Me: the captains board stands here again — Rank is its home')
  const titles = await page.locator('[data-summary-row]').evaluateAll((els) => els.map((e) => (e.firstElementChild?.textContent ?? '').trim()))
  if (titles.includes('Captains')) failures.push(`stats/Me: a "Captains" summary row stands (${titles.join(', ')})`)

  // RANK — the board lives here, on the glass (it stood behind `rank-open` until the unfold slice, 2026-11-02, owner row
  // 260), and it names you
  await screen(page, 'rank')
  await expect(page.getByTestId('rank-list')).toBeVisible()
  if ((await page.getByTestId('rank-you').count()) === 0) failures.push('rank: the captains board does not name you')

  // THE DESK — the cargo door carries no figure; the strip keeps the acting figure
  await screen(page, 'command')
  if (!(await pressFace(page.getByRole('tablist', { name: 'Desk faces' }), 'Trade', 'desk/Trade', failures)))
    return expect(failures, 'the Trade face did not open').toEqual([])
  const door = (await page.getByTestId('cargo-open').innerText()).trim()
  if (/\d/.test(door)) failures.push(`desk/Trade: the cargo door carries a figure ("${door}") — Fleets is the home; the door must be a door`)
  const strip = (await page.getByTestId('command-line').innerText()).trim()
  if (!/\d/.test(strip)) failures.push('desk: the strip lost the acting cargo figure')

  // THE HALL'S FIVE FIGURES — the City screen only
  for (const route of ['fleets', 'map', 'stats', 'rank', 'routes', 'compendium', 'you', 'profile', 'ledger', 'command']) {
    await screen(page, route)
    for (const id of ['city-population', 'city-gold', 'city-status', 'city-relationship', 'city-employees']) {
      if ((await page.getByTestId(id).count()) !== 0) failures.push(`${route} prints the hall's ${id}`)
    }
  }

  expect(failures, 'one fact, one home').toEqual([])
})
