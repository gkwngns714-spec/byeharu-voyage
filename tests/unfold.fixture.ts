import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { gzipSync } from 'node:zlib'
import type { Page } from '@playwright/test'
import { WORLD_IMAGE_DIR } from '../scripts/db/build-image.mjs'
import { asWorldImageFile } from '../src/lib/db/worldImage'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE UNFOLD LAWS' ONE MEASURING APPARATUS (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/dev-log/2026-11-01-ui-unfold.md U1–U8, measured the same way on every screen that unfolds (Stats first,
// then the Codex, the Ledger, Rank and Routes): the three glasses, and one read of a face as data — page and
// Sheet scroll, whether the figure block scrolls, every sideways scroller, text boxes that cross (each clipped by
// the panes that hold it), cut text with no full text, and how many of a list panel's rows stand WHOLE inside
// its body. A second copy of this would drift; each screen's spec says only what is its own.

export interface Glass {
  width: number
  height: number
}
export const GLASSES: readonly Glass[] = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
  { width: 1280, height: 800 },
]

export interface Flat {
  doc: { sh: number; ch: number; sw: number; cw: number }
  sheet: { sh: number; ch: number; top: number } | null
  above: { sh: number; ch: number } | null
  sideways: string[]
  overlaps: string[]
  cuts: string[]
  rows: { found: boolean; whole: number; total: number; inView: boolean }
  /** THE PHONE LAWS (the HQ slice, 2026-11-02) — each a list of defects, empty when the law holds. */
  /** (a) two in-flow SIBLING boxes (a tile, a figure, a label) overlapping by more than 2 px², and two chart labels crossing. */
  boxes: string[]
  /** (b) text of three or more characters laid out narrower than 1.4 × its own font size: the one-character-per-line wrap. */
  narrow: string[]
  /** A row's LABEL (a `data-row-cell="label"`, a summary row's title) wider than the box it stands in: a label never shrinks below its own text. */
  labelCuts: string[]
}

/** THE PHONE LAWS AS LINES, one per defect, empty when they hold (the HQ slice, 2026-11-02): (a) no two boxes overlap, (b) no text stands one letter wide, (c) nothing is cut without its full
 *  text, (d) nothing scrolls sideways. A spec reads a scoped `readGlass` and asserts this is `[]`; the spelling of a law is here once. */
export function phoneLaws(where: string, f: Flat): string[] {
  const out: string[] = []
  for (const d of f.boxes) out.push(`${where}: (a) sibling boxes overlap — ${d}`)
  for (const d of f.overlaps) out.push(`${where}: (a) two texts cross — ${d}`)
  for (const d of f.narrow) out.push(`${where}: (b) one letter per line — ${d}`)
  for (const d of f.cuts) out.push(`${where}: (c) text cut with no way to read it — ${d}`)
  for (const d of f.labelCuts) out.push(`${where}: (c) a label is cut — ${d}`)
  if (f.doc.sw > f.doc.cw) out.push(`${where}: (d) the page scrolls sideways (${f.doc.sw} in ${f.doc.cw} px)`)
  for (const d of f.sideways) out.push(`${where}: (d) a box scrolls sideways — ${d}`)
  return out
}

/** One face as data: scroll, overlap, cut text and the panel's whole rows. Self-contained — it is shipped into the page.
 *  `scope` (a selector) narrows what is MEASURED to one subtree (the HQ's right panel, its left region); the document's own
 *  scroll (`doc`) always stands for the whole page. Absent, everything is measured as before. */
export async function readGlass(page: Page, panel: string, row: string | null, scope: string | null = null): Promise<Flat> {
  return page.evaluate(
    ({ panel, row, scope }) => {
      const vis = (e: Element) => {
        const r = e.getBoundingClientRect()
        const s = getComputedStyle(e)
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0
      }
      const de = document.documentElement
      const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
      const above = document.querySelector('[data-list-above]') as HTMLElement | null
      /** What is measured: the whole page, or the one subtree the caller named. */
      const root: Element = (scope !== null ? document.querySelector(scope) : document.body) ?? document.body
      const inside = [...root.querySelectorAll('*')]

      // every visible box that scrolls sideways
      const sideways = inside
        .filter((e) => e instanceof HTMLElement && vis(e) && /auto|scroll/.test(getComputedStyle(e).overflowX) && e.scrollWidth > e.clientWidth + 1)
        .map((e) => e.getAttribute('data-testid') ?? e.tagName.toLowerCase())

      // text boxes, each clipped by every ancestor that clips: text scrolled out of a pane is not on the glass
      const leaves: { txt: string; l: number; t: number; r: number; b: number; host: Element }[] = []
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const txt = (n.textContent ?? '').trim()
        const host = n.parentElement
        if (!txt || !host || !vis(host) || host.closest('svg')) continue
        const range = document.createRange()
        range.selectNodeContents(n)
        const r0 = [...range.getClientRects()].find((x) => x.width > 0 && x.height > 0)
        if (!r0) continue
        let r: { left: number; top: number; right: number; bottom: number } | null = { left: r0.left, top: r0.top, right: r0.right, bottom: r0.bottom }
        for (let a: Element | null = host; a && a !== document.body && r; a = a.parentElement) {
          const s = getComputedStyle(a)
          if (s.overflowX === 'visible' && s.overflowY === 'visible') continue
          const c = a.getBoundingClientRect()
          r = { left: Math.max(r.left, c.left), top: Math.max(r.top, c.top), right: Math.min(r.right, c.right), bottom: Math.min(r.bottom, c.bottom) }
          if (r.right - r.left <= 0 || r.bottom - r.top <= 0) r = null
        }
        if (!r || r.bottom < 0 || r.top > innerHeight) continue
        leaves.push({ txt: txt.slice(0, 32), l: r.left, t: r.top, r: r.right, b: r.bottom, host })
      }
      const overlaps: string[] = []
      for (let i = 0; i < leaves.length; i++) {
        for (let j = i + 1; j < leaves.length; j++) {
          const a = leaves[i]
          const b = leaves[j]
          if (a.host === b.host || a.host.contains(b.host) || b.host.contains(a.host)) continue
          const ox = Math.min(a.r, b.r) - Math.max(a.l, b.l)
          const oy = Math.min(a.b, b.b) - Math.max(a.t, b.t)
          if (ox > 2 && oy > 3) overlaps.push(`"${a.txt}" × "${b.txt}" (${Math.round(ox)}×${Math.round(oy)})`)
        }
      }

      // cut text carries its full text (align.spec's CUT, held here at 320 too); a 1-px screen-reader label is not text on the glass
      const cuts = inside
        .filter((e): e is HTMLElement => {
          if (!(e instanceof HTMLElement) || !vis(e) || e.closest('svg') || e.clientWidth <= 2) return false
          if (!(e.textContent ?? '').trim()) return false
          const s = getComputedStyle(e)
          const cut = (s.overflowX === 'hidden' || s.overflowX === 'clip' || s.textOverflow === 'ellipsis') && e.scrollWidth > e.clientWidth + 1
          return cut && !e.closest('[title]')?.getAttribute('title')?.trim()
        })
        .map((e) => `${e.getAttribute('data-testid') ?? e.tagName.toLowerCase()} "${(e.textContent ?? '').trim().slice(0, 30)}"`)

      // ── THE PHONE LAWS (the HQ slice, 2026-11-02; docs/dev-log/2026-11-02-city-phone.md) ───────────────────────────
      // They are read only for a NAMED subtree (`scope`): they compare every pair of boxes in it, which is cheap for a panel and a long wait for the
      // Codex's 629 rows, and the five unfold specs name no scope and assert none of them.
      const phone = scope !== null
      const name = (e: Element) => `${e.getAttribute('data-testid') ?? e.getAttribute('data-row-cell') ?? e.tagName.toLowerCase()} "${(e.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 22)}"`

      // (a) no two SIBLING boxes overlap by more than 2 px². In-flow siblings only: an absolute or fixed child is a layer drawn over
      // its parent on purpose (a gauge's fill, a chevron), never a box that has lost its place. An svg's insides are the chart's own.
      const boxes: string[] = []
      for (const p of phone ? [root, ...inside] : []) {
        if (p.tagName.toLowerCase() === 'svg' || p.parentElement?.closest('svg')) continue
        const kids = [...p.children].filter((k) => vis(k) && !['absolute', 'fixed'].includes(getComputedStyle(k).position))
        for (let i = 0; i < kids.length; i++) {
          for (let j = i + 1; j < kids.length; j++) {
            const a = kids[i].getBoundingClientRect()
            const b = kids[j].getBoundingClientRect()
            const area = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left)) * Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top))
            if (area > 2) boxes.push(`${name(kids[i])} × ${name(kids[j])} (${Math.round(area)} px²)`)
          }
        }
      }
      // …and no two CONTROLS overlap, whoever their parents are: a span picker standing over the price field below it (the request page's chart box was
      // 256 px round a card of 420) is two cousins, not two siblings, and the one underneath cannot be pressed. A control that is itself a layer
      // (absolute or fixed, or inside one: the ✕ inside a field) is on its parent on purpose.
      const layered = (e: Element) => {
        for (let a: Element | null = e; a && a !== root; a = a.parentElement) if (['absolute', 'fixed'].includes(getComputedStyle(a).position)) return true
        return false
      }
      const controls = (phone ? [...root.querySelectorAll('button, a[href], input, select, textarea, [role="button"], [role="tab"]')] : []).filter((e) => vis(e) && !layered(e))
      for (let i = 0; i < controls.length; i++) {
        for (let j = i + 1; j < controls.length; j++) {
          if (controls[i].contains(controls[j]) || controls[j].contains(controls[i])) continue
          if (controls[i].parentElement === controls[j].parentElement) continue // siblings are counted above
          const a = controls[i].getBoundingClientRect()
          const b = controls[j].getBoundingClientRect()
          const area = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left)) * Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top))
          if (area > 2) boxes.push(`control ${name(controls[i])} × ${name(controls[j])} (${Math.round(area)} px²)`)
        }
      }
      // …and no TEXT stands on a control it is not inside: a good's stock gauge ("6,700 / 6,700") ran 4 px under the buy cell beside it in the Map's port tray at 390 and in
      // the desk's Trade rows (the sweep's row 7) — a text and a control are cousins too, and the figure that is under the control cannot be read.
      if (phone) {
        const leaves = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
        for (let n = leaves.nextNode(); n; n = leaves.nextNode()) {
          const txt = (n.textContent ?? '').replace(/s+/g, ' ').trim()
          const host = n.parentElement
          if (!txt || !host || host.closest('svg') || !vis(host)) continue
          const range = document.createRange()
          range.selectNodeContents(n)
          const r = [...range.getClientRects()].find((x) => x.width > 0 && x.height > 0)
          if (!r) continue
          for (const c of controls) {
            if (c.contains(host)) continue
            const b = c.getBoundingClientRect()
            const ox = Math.min(r.right, b.right) - Math.max(r.left, b.left)
            const oy = Math.min(r.bottom, b.bottom) - Math.max(r.top, b.top)
            if (ox > 2 && oy > 3) boxes.push(`text "${txt.slice(0, 20)}" stands on control ${name(c)} (${Math.round(ox)}×${Math.round(oy)} px)`)
          }
        }
      }
      // …and a chart's labels are siblings too: two axis labels standing on each other
      const chartText = (phone ? [...root.querySelectorAll('svg text')] : []).filter(vis)
      for (let i = 0; i < chartText.length; i++) {
        for (let j = i + 1; j < chartText.length; j++) {
          const a = chartText[i].getBoundingClientRect()
          const b = chartText[j].getBoundingClientRect()
          const area = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left)) * Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top))
          if (area > 2) boxes.push(`chart "${(chartText[i].textContent ?? '').trim()}" × "${(chartText[j].textContent ?? '').trim()}" (${Math.round(area)} px²)`)
        }
      }

      // (b) no text of three or more characters is laid out in a column narrower than 1.4 × its font size: that is a column one
      // letter wide — a good's name wrapped to nothing beside two price tiles. It is read off the TEXT's own line boxes, not its
      // element's box (a label squeezed to 0 px draws its letters outside it), and only a text that WRAPPED can be such a column: a
      // word that stands on one line ("All", 14.6 px at 12 px type) is short, not squeezed.
      const narrow: string[] = []
      const words = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
      for (let n = phone ? words.nextNode() : null; n; n = words.nextNode()) {
        const txt = (n.textContent ?? '').replace(/\s+/g, ' ').trim()
        const host = n.parentElement
        if (txt.length < 3 || !host || host.closest('svg')) continue
        const style = getComputedStyle(host)
        if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) continue
        const range = document.createRange()
        range.selectNodeContents(n)
        const lines = [...range.getClientRects()].filter((x) => x.width > 0 && x.height > 0)
        const widest = Math.max(0, ...lines.map((x) => x.width))
        const size = parseFloat(style.fontSize)
        if (lines.length > 1 && widest < 1.4 * size) narrow.push(`"${txt.slice(0, 24)}" stands ${lines.length} lines high and ${widest.toFixed(1)} px wide at ${size} px type`)
      }

      // a label never shrinks below its own text: no row label, no summary title, is wider than the cell it stands in. A cell may
      // be 0 px wide (that is the defect), so it is found by style, not by its box; 4 px of a trailing mark's side is not cut text.
      const labelCuts = (phone ? [...root.querySelectorAll('[data-row-cell="label"]')] : [])
        .filter((e): e is HTMLElement => {
          if (!(e instanceof HTMLElement)) return false
          const style = getComputedStyle(e)
          return style.display !== 'none' && style.visibility !== 'hidden' && e.scrollWidth > e.clientWidth + 4
        })
        .map((e) => `${name(e)} (${e.scrollWidth} in ${e.clientWidth} px)`)

      const panelEl = document.querySelector(`[data-testid="${panel}"]`)
      const body = panelEl?.querySelector('[data-list-body]') ?? null
      let whole = 0
      let total = 0
      let inView = false
      if (body !== null) {
        const b = body.getBoundingClientRect()
        inView = b.height > 0 && b.top >= 0 && b.bottom <= innerHeight + 1
        if (row !== null) {
          const rows = [...body.querySelectorAll(`[data-testid="${row}"]`)]
          total = rows.length
          whole = rows.filter((r) => {
            const x = r.getBoundingClientRect()
            return x.top >= b.top - 1 && x.bottom <= b.bottom + 1
          }).length
        }
      }
      return {
        doc: { sh: de.scrollHeight, ch: de.clientHeight, sw: de.scrollWidth, cw: de.clientWidth },
        sheet: sheet ? { sh: sheet.scrollHeight, ch: sheet.clientHeight, top: sheet.scrollTop } : null,
        above: above ? { sh: above.scrollHeight, ch: above.clientHeight } : null,
        sideways,
        overlaps: [...new Set(overlaps)],
        cuts: [...new Set(cuts)],
        rows: { found: body !== null, whole, total, inView },
        boxes: [...new Set(boxes)],
        narrow: [...new Set(narrow)],
        labelCuts: [...new Set(labelCuts)],
      }
    },
    { panel, row, scope },
  )
}

export async function openFace(page: Page, tab: string) {
  await page.getByRole('tablist').first().getByRole('tab', { name: tab, exact: true }).click()
  await page
    .waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 })
    .catch(() => {})
  await page.waitForTimeout(600)
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PLAYED WORLD, BUILT AT RUN TIME — the rows a canary world does not have
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The world a browser spec boots is the canary: ONE ledger entry (the founding), no route lane (its traders are off), a board
// of ten. The owner's world serves fifty ledger entries and a board of lanes, and the unfold laws are about THOSE rows (how
// many stand whole in the glass, a row with a report that opens its tray, a lane the server cannot rank). A spec may not
// skip — CI fails any skipped test, because a skip means the app was not served — so the rows are made here: restore THIS
// build's own world image, replace the two reads that serve them with type-shaped fixtures, dump it, and serve that image to
// the page in place of the built one. It is how db.image.spec builds its wounded image. Nothing is written to disk and nothing
// outside the spec's browser context sees it.

/** A jsonb literal for a SQL string (standard_conforming_strings: only the quote needs doubling). */
const jsonb = (value: unknown) => `'${JSON.stringify(value).replace(/'/g, "''")}'::jsonb`

let played: Promise<Buffer> | null = null

function playedImage(): Promise<Buffer> {
  played ??= (async () => {
    const dir = path.join(process.cwd(), 'dist', WORLD_IMAGE_DIR)
    const name = readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f))
    if (name === undefined) throw new Error(`NO PRE-BUILT WORLD in ${dir} — run "npm run build"`)
    const { PGlite } = await import('@electric-sql/pglite')
    const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
    try {
      const ports = (await pg.query<{ code: string }>('select code from public.ports order by code limit 60')).rows.map((r) => r.code)
      await pg.query('drop function if exists world.ledger(timestamptz, int)')
      await pg.query(
        `create function world.ledger(p_cursor timestamptz default null, p_limit int default 50) returns jsonb language sql volatile as $f$ select ${jsonb(ledgerPage(ports))} $f$`,
      )
      await pg.query('drop function if exists world.route_board()')
      await pg.query(`create function world.route_board() returns jsonb language sql stable as $f$ select ${jsonb(routeBoard(ports))} $f$`)
      const tar = new Uint8Array(await (await pg.dumpDataDir('none')).arrayBuffer())
      return Buffer.from(gzipSync(tar))
    } finally {
      await pg.close()
    }
  })()
  return played
}

/** Serve the played world to this page: fifty ledger entries and a board of forty lanes. Call it before `page.goto`. */
export async function playedWorld(page: Page): Promise<void> {
  const body = await playedImage()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body, contentType: 'application/gzip' }))
}

/** `world.ledger`'s page: fifty entries, newest first, of the kinds headline.ts composes — ten in Trade, twenty in Voyage,
 *  twenty in Crew, and a voyage report (a row that opens its tray) among the Voyage ones. */
function ledgerPage(ports: string[]) {
  const now = Date.now()
  const port = (i: number) => ports[i % ports.length]
  const goods = ['Silk', 'Pepper', 'Cloves', 'Amber', 'Brazilwood', 'Porcelain', 'Tin', 'Saffron', 'Merino Wool', 'Sugar', 'Camphor', 'Nutmeg']
  const fleets = ['Santa Clara', 'Boa Esperança', 'São Gabriel', 'Fortuna']
  const events: Record<string, unknown>[] = []
  let mins = 3
  for (let i = 0; i < 50; i++) {
    mins += 7 + ((i * 13) % 23)
    const fleet = fleets[i % fleets.length]
    const good = goods[(i * 5) % goods.length]
    const qty = 20 + ((i * 7) % 60)
    const sold = 12 + ((i * 17) % 110) + 0.5
    const bought = 8 + ((i * 11) % 90) + 0.5
    const nm = 220 + i * 31
    const [kind, payload, delta] = ((): [string, Record<string, unknown>, number | null] => {
      switch (i % 10) {
        case 0: return ['BOUGHT', { port: port(i * 3), fleet, good, qty, avg_price: bought, total: Math.round(qty * bought) }, -Math.round(qty * bought)]
        case 1: return ['SOLD', { port: port(i * 3), fleet, good, qty, avg_price: sold, total: Math.round(qty * sold) }, Math.round(qty * sold)]
        case 2: return ['DEPARTED', { fleet, voyage_id: 'v', total_nm: nm, points: 9, dest: port(i * 3 + 7), eta: new Date(now + 300 * 60_000).toISOString() }, null]
        case 3:
          return [
            'VOYAGE_REPORT',
            {
              fleet, voyage_id: 'v', from: port(i * 3), to: port(i * 3 + 7), total_nm: nm,
              lines: [`${fleet} sailed ${nm} nm from the home port.`, 'Fair winds for two days, a calm on the third.', 'No losses; the hold came in whole.'],
            },
            null,
          ]
        case 4: return ['PROVISIONED', { fleet, water_t: 4.5, food_t: 6.2, cost: 180 + i }, -(180 + i)]
        case 5: return ['HIRED', { fleet, count: 6 + (i % 5), urgent: i % 4 === 0, cost: 90 + i * 2 }, -(90 + i * 2)]
        case 6: return ['WAGES', { fleet }, -(120 + i * 3)]
        case 7: return ['REPAIRED', { fleet }, null]
        case 8: return ['SIGNED_OFFICER', { officer: 'Afonso de Albuquerque', code: 'x', specialty: 'Combat', bonus_pct: 7, cost: 1200 }, -1200]
        default: return ['STUDIED', { skill: 'Navigation', code: 'NAVIGATION', level: 2 + (i % 3), port: port(i * 3), cost: 400 }, -400]
      }
    })()
    events.push({ id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, kind, payload, at: new Date(now - mins * 60_000).toISOString(), ducats_delta: delta, balance_after: null })
  }
  return { events, next_cursor: null, ducats: 40000, ledger_sum: 40000 }
}

/** `world.route_board`: forty of a hundred and twenty lanes, two of them hers, some unmeasured, some shut to her, some with no
 *  lap closed yet — the shape `RouteBoard` documents. */
function routeBoard(ports: string[]) {
  const now = new Date().toISOString()
  const companies = ['Casa da Índia', 'Companhia de Malaca', 'Casa de Contratación', 'Juncos de Quanzhou', 'Company of Plymouth', 'Sociedade Matos', 'Huis Reael', 'Banco Foscari', 'Fraterna Badoer', 'Hermanos Hurtado']
  const nations = ['PRT', 'PRT', 'ESP', 'MNG', 'ENG', 'PRT', 'NLD', null, null, 'ESP']
  const names = ['Spice carreira', 'Cloth run', 'Gold coast loop', 'Lisbon–Seville feeder', 'Malabar pepper', 'Silk and silver', 'North Sea herring', 'Levant caravan', 'Tin and wool', 'Sugar triangle']
  const routes = Array.from({ length: 40 }, (_, i) => {
    const mine = i < 2
    const stops = 3 + (i % 5)
    const nm = i % 9 === 5 ? null : 600 + ((i * 397) % 7400)
    const lap = i % 4 === 2 ? null : 800 + ((i * 523) % 9000)
    return {
      id: `route-${i}`,
      name: mine ? ['My Cloth run', 'My Malabar loop'][i] : `${names[i % names.length]} ${i}`,
      mine,
      merchant: !mine,
      company: mine ? null : companies[i % companies.length],
      nation_code: mine ? null : nations[i % nations.length],
      ink: null,
      stops: Array.from({ length: stops }, (_, k) => ports[(i * 4 + k * 3) % ports.length]),
      stop_count: stops,
      nm,
      regions: 1 + (i % 3),
      state: i % 5 === 0 ? 'Sailing' : 'Docked',
      assigned: i % 6 !== 4,
      requires: { navigation: nm === null ? null : 1 + (i % 6) },
      closed: i % 7 === 3,
      earnings: {
        day: 900, day_laps: 2, day_since: null, day_full: true, lap, lap_basis: lap === null ? 1 : 3 + (i % 5), laps_recent: [], laps_done: i % 9,
        total: { laps: i % 9, net: 0, sold: 0, bought: 0, supplies: 0, repairs: 0, wages: 0 },
      },
    }
  })
  return { at: now, merchants: true, routes, total: 120, omitted: 80 }
}

