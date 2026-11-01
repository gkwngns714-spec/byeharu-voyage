// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A GOOD HAS A CLASS (0294) — the premium class the player can see at a glance, held as a spec
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-11-01: *"new trade goods - distinctive class showing what is more premium."*
// The server half is proved by 0294's own self-assert on the chain (the rule, the knob's own edges,
// every served good, the reverse). THIS FILE holds the SCREEN, in two halves:
//
//   PURE (no browser, the design system's tables and its tokens):
//     · the class table is complete for 1-5, distinct from the rarity table, and speaks in words that
//       do not collide with docs/WORDS.md (`premium` is a REQUEST's word);
//     · every class colour clears 4.5 : 1 on the sheet and on the inset, in BOTH schemes, MEASURED
//       from src/index.css's own figures; the two premium classes are the only chroma and every
//       class is its own colour.
//   BROWSER (the built image, headless, at 390×844 and 1280×800):
//     · EVERY list a good stands in — the desk's Buy and Request faces, the City page's Market (wide),
//       the Codex's goods, the Forge, a cargo list — draws a class mark per good, from the SERVED
//       number, in the dictionary's word;
//     · NO ROW GROWS: each row is measured with the class marks and again with them hidden — the
//       height must not move (docs/dev-log/2026-11-01-ui-unfold.md U5; the first draft put the mark
//       beside the rarity glyph and a phone row grew a line); and the mark overlaps nothing in its row;
//     · a premium row (4-5) is visibly distinct from a basic one (1-2): its mark colour and its row
//       wash differ — asserted as TOKENS, never as a pixel;
//     · the words are the player's, EN and KO; the press that opens a good spells the class out;
//     · Stats › Markets sorts by class, premium first, through the sort it already has.
//
// WHERE THE BROWSER HALF DOES NOT GO: the City page's Market at 390 (its two-region layout collapses
// the name column to one character — measured on main before this change, BEFORE screenshot in
// docs/dev-log/2026-11-01-good-class.md — and belongs to the City page's own slice).

import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'
import { GOOD_CLASSES, GOOD_CLASS_BARS, GOOD_CLASS_BAR_HEIGHTS, GOOD_CLASS_LOOK, goodClassRow } from '../src/components/ui/goodClassTiers'
import { RARITY_TIER_LOOK } from '../src/components/ui/rarityTiers'
import { DICT } from '../src/lib/i18n'

const PHONE = { width: 390, height: 844 }
const WIDE = { width: 1280, height: 800 }

type Dict = Record<string, string>
const UI_EN = DICT.ui.en as unknown as Dict
const UI_KO = DICT.ui.ko as unknown as Dict
const EN_WORDS = GOOD_CLASSES.map((c) => UI_EN[`class${c}`])
const KO_WORDS = GOOD_CLASSES.map((c) => UI_KO[`class${c}`])

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PURE — the table
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test('the class table is complete for classes 1-5: a word, a lit-bar count, a colour token each', () => {
  expect([...GOOD_CLASSES]).toEqual([1, 2, 3, 4, 5])
  expect(Object.keys(GOOD_CLASS_LOOK).map(Number).sort()).toEqual([1, 2, 3, 4, 5])
  expect(GOOD_CLASS_BARS).toBe(5)
  // THE SHAPE CHANNEL: the class IS the number of lit bars, ascending, one more each step
  expect(GOOD_CLASSES.map((c) => GOOD_CLASS_LOOK[c].bars)).toEqual([1, 2, 3, 4, 5])
  // the meter is the block characters' staircase: five heights, strictly rising, none taller than the box
  expect(GOOD_CLASS_BAR_HEIGHTS).toHaveLength(GOOD_CLASS_BARS)
  for (let i = 1; i < GOOD_CLASS_BARS; i++) expect(GOOD_CLASS_BAR_HEIGHTS[i]).toBeGreaterThan(GOOD_CLASS_BAR_HEIGHTS[i - 1])
  expect(GOOD_CLASS_BAR_HEIGHTS[GOOD_CLASS_BARS - 1]).toBe(8)
  // THE COLOUR CHANNEL: one token each, spelled whole (the Tailwind scanner reads literals)
  expect(GOOD_CLASSES.map((c) => GOOD_CLASS_LOOK[c].tone)).toEqual(['text-class-1', 'text-class-2', 'text-class-3', 'text-class-4', 'text-class-5'])
  // THE WORD CHANNEL: five entries in BOTH languages, none empty, none repeated, none Latin in Korean
  for (const c of GOOD_CLASSES) expect(GOOD_CLASS_LOOK[c].word).toBe(`class${c}`)
  expect(EN_WORDS.every((w) => typeof w === 'string' && w.trim().length > 0), 'an English class word is missing').toBe(true)
  expect(KO_WORDS.every((w) => typeof w === 'string' && w.trim().length > 0), 'a Korean class word is missing').toBe(true)
  expect(new Set(EN_WORDS).size).toBe(5)
  expect(new Set(KO_WORDS).size).toBe(5)
  for (const w of KO_WORDS) expect(w, `Korean class word "${w}" carries a Latin letter`).not.toMatch(/[A-Za-z]/)
})

test('a LIST ROW wears the class from the served number alone: the number, and a wash from class 4 — never a guess', () => {
  for (const c of GOOD_CLASSES) {
    const row = goodClassRow(c)
    expect(row['data-good-class']).toBe(c)
    expect(row.className !== undefined, `class ${c}: the wash belongs to the premium classes (4, 5) and to them only`).toBe(c >= 4)
  }
  expect(goodClassRow(4).className).not.toBe(goodClassRow(5).className)
  // a server older than this build serves no class; a newer one may serve a class this build does not know
  for (const none of [undefined, null, 0, 6, 99, -1]) expect(goodClassRow(none as number | null | undefined), `class ${String(none)} must draw nothing`).toEqual({})
})

test('the class table is NOT the rarity table: no shared colour, no shared word, no glyph', () => {
  const rarityTones = Object.values(RARITY_TIER_LOOK).map((l) => l.tone)
  const classTones = GOOD_CLASSES.map((c) => GOOD_CLASS_LOOK[c].tone)
  expect(classTones.filter((t) => rarityTones.includes(t))).toEqual([])
  for (const c of GOOD_CLASSES) expect('icon' in GOOD_CLASS_LOOK[c], 'a class is a meter, never a rarity glyph').toBe(false)
  for (const r of Object.keys(RARITY_TIER_LOOK)) {
    expect(EN_WORDS, `the class words repeat the rarity word "${r}"`).not.toContain(UI_EN[r])
    expect(KO_WORDS, `the Korean class words repeat the rarity word "${r}"`).not.toContain(UI_KO[r])
  }
})

test('docs/WORDS.md: `premium` is a REQUEST\'s word (what it pays over the market) — the class does not take it', () => {
  // The Fulfil tray prints a good's marks AND the request's `Premium +200` row; two meanings of one word
  // on one screen is what WORDS.md law 3 forbids. Korean keeps 프리미엄: its request word is 웃돈.
  for (const w of EN_WORDS) expect(w.toLowerCase(), 'an English class word is `premium`').not.toMatch(/premium/)
  const words = readFileSync(path.join(process.cwd(), 'docs', 'WORDS.md'), 'utf8')
  expect(words).toMatch(/what a request pays over the market \| \*\*premium\*\*/)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PURE — the tokens, measured from src/index.css
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** CSS without comments, so a brace or a token named in prose is never read as code. */
const CSS = readFileSync(path.join(process.cwd(), 'src', 'index.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')

/** The text between the braces of the block that opens with `opener`. */
function blockOf(opener: string): string {
  const at = CSS.indexOf(opener)
  if (at < 0) throw new Error(`src/index.css has no "${opener}" block`)
  let depth = 0
  for (let i = CSS.indexOf('{', at); i < CSS.length; i++) {
    if (CSS[i] === '{') depth++
    else if (CSS[i] === '}' && --depth === 0) return CSS.slice(CSS.indexOf('{', at) + 1, i)
  }
  throw new Error(`src/index.css: "${opener}" never closes`)
}

function declarations(block: string): Map<string, string> {
  const out = new Map<string, string>()
  for (const m of block.matchAll(/^\s*(--[a-z0-9-]+)\s*:\s*([^;]+);/gm)) out.set(m[1], m[2].trim())
  return out
}

const NIGHT = declarations(blockOf('@theme {'))
const DAY = new Map([...NIGHT, ...declarations(blockOf(":root[data-theme='light'] {"))])

/** A token's colour as #rrggbb, following `var(--other)` aliases through its scheme. */
function resolve(scheme: Map<string, string>, token: string): string {
  let v = scheme.get(token)
  for (let guard = 0; v !== undefined && guard < 8; guard++) {
    const alias = /^var\((--[a-z0-9-]+)\)$/.exec(v)
    if (!alias) break
    v = scheme.get(alias[1])
  }
  if (v === undefined || !/^#[0-9a-f]{6}$/i.test(v)) throw new Error(`${token} does not resolve to a #rrggbb (got ${String(v)})`)
  return v.toLowerCase()
}

const channel = (h: string, i: number) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16) / 255
const lin = (c: number) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
const luminance = (h: string) => 0.2126 * lin(channel(h, 0)) + 0.7152 * lin(channel(h, 1)) + 0.0722 * lin(channel(h, 2))
const contrast = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}
/** How much a colour is a COLOUR rather than an ink: the spread of its channels, 0 (grey) to 1. (HSL
 *  saturation would read the day's near-black ink, #111827, as 0.39 — it divides by a vanishing lightness.) */
function colourfulness(h: string): number {
  const c = [channel(h, 0), channel(h, 1), channel(h, 2)]
  return Math.max(...c) - Math.min(...c)
}

for (const [scheme, tokens] of [['night', NIGHT], ['day', DAY]] as const) {
  test(`${scheme}: every class colour clears 4.5 : 1 on the sheet and on the inset, is its own colour, and only 4 and 5 are chroma`, () => {
    const sheet = resolve(tokens, '--color-surface')
    const inset = resolve(tokens, '--color-surface-2')
    const colour = GOOD_CLASSES.map((c) => resolve(tokens, `--color-class-${c}`))
    const figures = GOOD_CLASSES.map((c, i) => `${c} ${colour[i]}  ${contrast(colour[i], sheet).toFixed(2)} / ${contrast(colour[i], inset).toFixed(2)}  colourful ${colourfulness(colour[i]).toFixed(2)}`)
    console.log(`class tokens, ${scheme}, on ${sheet} / ${inset}:\n  ${figures.join('\n  ')}`)
    GOOD_CLASSES.forEach((c, i) => {
      expect(contrast(colour[i], sheet), `class ${c} (${colour[i]}) on the sheet ${sheet}`).toBeGreaterThanOrEqual(4.5)
      expect(contrast(colour[i], inset), `class ${c} (${colour[i]}) on the inset ${inset}`).toBeGreaterThanOrEqual(4.5)
    })
    expect(new Set(colour).size, 'two classes share a colour').toBe(5)
    // THE LOUD CLASSES: copper and gold are the scale's only chroma; the everyday three are the inks
    for (const [i, c] of GOOD_CLASSES.entries()) {
      if (c >= 4) expect(colourfulness(colour[i]), `class ${c} is not a colour`).toBeGreaterThan(0.3)
      else expect(colourfulness(colour[i]), `class ${c} is not a quiet ink`).toBeLessThan(0.2)
    }
    // …and no class borrows a rarity hue
    const rarity = ['uncommon', 'rare', 'exotic'].map((r) => resolve(tokens, `--color-rarity-${r}`))
    for (const col of colour) expect(rarity).not.toContain(col)
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BROWSER — the design gallery (no world to boot): both schemes, MEASURED in the running page
// ═══════════════════════════════════════════════════════════════════════════════════════════════

for (const scheme of ['dark', 'light'] as const) {
  test(`gallery (${scheme}): the five class marks render in their own token, and clear 4.5 : 1 on the sheet AND the inset`, async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.setViewportSize(PHONE)
    await page.goto('ui')
    await expect(page.getByTestId('gallery-class-legend')).toBeVisible()
    await page.evaluate((s) => document.documentElement.setAttribute('data-theme', s), scheme)
    const report = await page.evaluate(() => {
      const root = getComputedStyle(document.documentElement)
      /** any CSS colour → [r, g, b] by painting it on a 1-px canvas */
      const rgb = (css: string): [number, number, number] => {
        const probe = document.createElement('i')
        probe.style.color = css
        document.body.appendChild(probe)
        const m = /rgba?\((\d+)[, ]+(\d+)[, ]+(\d+)/.exec(getComputedStyle(probe).color) ?? ['', '0', '0', '0']
        probe.remove()
        return [Number(m[1]), Number(m[2]), Number(m[3])]
      }
      const token = (name: string) => rgb(root.getPropertyValue(name).trim())
      const lum = ([r, g, b]: number[]) => {
        const f = (c: number) => ((c /= 255) <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
      }
      const ratio = (a: number[], b: number[]) => {
        const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x)
        return (hi + 0.05) / (lo + 0.05)
      }
      const sheet = token('--color-surface')
      const inset = token('--color-surface-2')
      return [...document.querySelectorAll('[data-testid="gallery-class-legend"] [data-good-class-mark]')].map((m) => {
        const c = Number(m.getAttribute('data-good-class-mark'))
        const painted = rgb(getComputedStyle(m).color)
        const want = token(`--color-class-${c}`)
        return {
          c,
          painted: painted.join(','),
          want: want.join(','),
          onSheet: Math.round(ratio(painted, sheet) * 100) / 100,
          onInset: Math.round(ratio(painted, inset) * 100) / 100,
          lit: m.querySelector('svg')?.getAttribute('data-meter-lit'),
          word: (m.textContent ?? '').trim(),
        }
      })
    })
    console.log(`gallery class marks (${scheme}): ${JSON.stringify(report)}`)
    expect(report.map((r) => r.c)).toEqual([1, 2, 3, 4, 5])
    for (const r of report) {
      expect(r.painted, `class ${r.c}: the mark is not painted in its own token`).toBe(r.want)
      expect(r.onSheet, `class ${r.c} on the sheet (${scheme})`).toBeGreaterThanOrEqual(4.5)
      expect(r.onInset, `class ${r.c} on the inset (${scheme})`).toBeGreaterThanOrEqual(4.5)
      expect(r.lit, `class ${r.c} lights ${r.c} bars`).toBe(String(r.c))
      expect(r.word).toBe(EN_WORDS[r.c - 1])
    }
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BROWSER — every list a good stands in
// ═══════════════════════════════════════════════════════════════════════════════════════════════

interface RowFacts {
  i: number
  /** the served class the row's own `data-good-class` carries */
  attr: number | null
  /** class marks inside the row */
  marks: number
  /** the mark's own class, and the word it speaks (its accessible name, or its text in the word form) */
  cls: number | null
  word: string | null
  /** the mark's painted colour */
  colour: string
  /** does the row wear the wash */
  wash: boolean
  /** height with the marks / with the class marks hidden */
  h: number
  hBare: number
  /** how far the row spills sideways, with the marks / with the class marks hidden (a row may spill on main —
   *  the request rows' fulfil cell does at 390 — and the question is only whether the mark made it worse) */
  spill: number
  spillBare: number
  /** the compact cluster (GoodKind) — how far it advances its line (its width less what it gives back by a
   *  negative margin), the rarity glyph's own width it joined, and its height; null when the row has none */
  advance: number | null
  glyph: number | null
  clusterH: number | null
  /** what the class mark's box intersects (by > 1 px each way): other marks, buttons, cells, text */
  overlaps: string[]
}

/** Runs IN THE PAGE: every row `sel` matches, measured with the class marks and again with them hidden. */
function inspectRows(sel: string): RowFacts[] {
  const rows = [...document.querySelectorAll<HTMLElement>(sel)]
  // THE BASELINE IS THE ROW AS IT WAS BEFORE THE CLASS: the class mark gone AND the cluster's give-back margin
  // gone, so what stands is the rarity glyph alone at its own 12 px. (The first draft hid the mark only, which
  // left the baseline 2 px NARROWER than the original, and a Linux row that sat on the 2-px edge read as "grown".)
  const style = document.createElement('style')
  style.textContent = '[data-good-class-mark]{display:none !important} [data-testid="good-marks"]{margin-right:0 !important}'
  const withMarks = rows.map((r) => r.getBoundingClientRect().height)
  const spillWith = rows.map((r) => r.scrollWidth - r.clientWidth)
  document.head.appendChild(style)
  const bare = rows.map((r) => r.getBoundingClientRect().height)
  const spillBare = rows.map((r) => r.scrollWidth - r.clientWidth)
  style.remove()

  const hit = (a: DOMRect, b: DOMRect) => Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1
  return rows.map((row, i) => {
    const marks = [...row.querySelectorAll<HTMLElement>('[data-good-class-mark]')]
    const mark = marks[0]
    const overlaps: string[] = []
    if (mark) {
      const box = mark.getBoundingClientRect()
      // 1. any other control, cell, glyph or mark in the row that does not CONTAIN this mark
      for (const el of row.querySelectorAll<HTMLElement>('button, [data-row-cell="value"], [data-row-cell="chevron"], svg, img, [data-good-class-mark]')) {
        if (el === mark || mark.contains(el) || el.contains(mark)) continue
        const r = el.getBoundingClientRect()
        if (r.width > 0 && r.height > 0 && hit(box, r)) overlaps.push(`${el.tagName.toLowerCase()}${el.getAttribute('data-testid') ? '#' + el.getAttribute('data-testid') : ''}`)
      }
      // 2. any text in the row that is not the mark's own
      // (the INK of the text: its leading and trailing spaces are blank, and the cluster's give-back margin lies over one)
      const walk = document.createTreeWalker(row, NodeFilter.SHOW_TEXT)
      for (let n = walk.nextNode(); n; n = walk.nextNode()) {
        const raw = n.textContent ?? ''
        const [from, to] = [raw.length - raw.trimStart().length, raw.trimEnd().length]
        if (from >= to || mark.contains(n)) continue
        const range = document.createRange()
        range.setStart(n, from)
        range.setEnd(n, to)
        if ([...range.getClientRects()].some((r) => r.width > 0 && hit(box, r))) overlaps.push(`text "${raw.trim().slice(0, 24)}"`)
      }
    }
    const cluster = row.querySelector<HTMLElement>('[data-testid="good-marks"]')
    const clusterBox = cluster?.getBoundingClientRect()
    const glyph = cluster?.querySelector<SVGElement>('svg:not([data-meter-lit])')
    const word = mark ? mark.getAttribute('aria-label') ?? (mark.textContent ?? '').trim() : null
    return {
      i,
      attr: row.hasAttribute('data-good-class') ? Number(row.getAttribute('data-good-class')) : null,
      marks: marks.length,
      cls: mark ? Number(mark.getAttribute('data-good-class-mark')) : null,
      word,
      colour: mark ? getComputedStyle(mark).color : '',
      wash: getComputedStyle(row).backgroundImage.includes('gradient'),
      h: Math.round(withMarks[i] * 100) / 100,
      hBare: Math.round(bare[i] * 100) / 100,
      spill: spillWith[i],
      spillBare: spillBare[i],
      advance: cluster && clusterBox ? Math.round((clusterBox.width + (parseFloat(getComputedStyle(cluster).marginRight) || 0)) * 100) / 100 : null,
      glyph: glyph ? Math.round(glyph.getBoundingClientRect().width * 100) / 100 : null,
      clusterH: clusterBox ? Math.round(clusterBox.height * 100) / 100 : null,
      overlaps,
    }
  })
}

/** What every list must say, in one place. `colours` collects class → painted colour across lists. */
function expectList(name: string, rows: RowFacts[], colours: Map<number, Set<string>>, words: readonly string[] = EN_WORDS) {
  expect(rows.length, `${name}: no rows were found — the measurement would prove nothing`).toBeGreaterThan(0)
  const bad = (what: string, pick: (r: RowFacts) => boolean) => {
    const hits = rows.filter(pick).slice(0, 4)
    expect(hits, `${name}: ${what}\n${JSON.stringify(hits, null, 1)}`).toEqual([])
  }
  bad('a row has no class mark (or more than one)', (r) => r.marks !== 1)
  bad('a mark is not a served class 1-5', (r) => r.cls === null || !(r.cls >= 1 && r.cls <= 5))
  bad("the row's own class is not its mark's", (r) => r.attr !== r.cls)
  bad("a mark does not speak the dictionary's word for its class", (r) => r.cls === null || r.word !== words[r.cls - 1])
  bad('a premium row (4-5) has no wash, or an everyday row has one', (r) => r.cls !== null && r.wash !== (r.cls >= 4))
  // ONE-SIDED, on purpose: the cluster advances its line by LESS than the glyph it joined (11 px against 12), so a row that
  // sits exactly on its wrap edge — Cinnamon at 390 does, on main, to the quarter pixel — may fit WITH the mark and wrap
  // without it. A row that got shorter is not a row the class grew; a row that got taller is.
  bad('the class mark GREW a row (it is taller with the mark than with the class hidden)', (r) => r.h - r.hBare > 0.51)
  bad('the class mark overlaps something in its row', (r) => r.overlaps.length > 0)
  bad('the class mark pushed a row sideways (it spills more with the mark than without)', (r) => r.spill - r.spillBare > 1)
  // THE INVARIANT THAT HOLDS ON EVERY MACHINE'S FONTS: the cluster costs the name's line no more than the rarity
  // glyph it joined did (or, with no glyph beside it, no more than its own meter), and it stands inside the 24-px line
  bad("the cluster advances its line by more than the rarity glyph did", (r) => r.advance !== null && r.advance > (r.glyph ? r.glyph : 14) + 0.01)
  bad('the cluster is taller than the 24-px line it rides in', (r) => r.clusterH !== null && r.clusterH > 24)
  for (const r of rows) {
    if (r.cls === null) continue
    const seen = colours.get(r.cls) ?? new Set<string>()
    seen.add(r.colour)
    colours.set(r.cls, seen)
  }
  const classes = [...new Set(rows.map((r) => r.cls))].sort()
  console.log(`${name}: ${rows.length} rows, classes ${JSON.stringify(classes)}, tallest growth ${Math.max(0, ...rows.map((r) => r.h - r.hBare)).toFixed(2)} px, ${rows.filter((r) => r.hBare - r.h > 0.51).length} row(s) shorter`)
}

/** One class → ONE colour, whatever the list; and a premium class is a different colour from an everyday one. */
function expectOneTable(colours: Map<number, Set<string>>) {
  for (const [c, seen] of colours) expect([...seen], `class ${c} is painted in more than one colour`).toHaveLength(1)
  const painted = (c: number) => [...(colours.get(c) ?? [])][0]
  for (const premium of [4, 5]) {
    for (const basic of [1, 2]) {
      if (colours.has(premium) && colours.has(basic)) {
        expect(painted(premium), `class ${premium} and class ${basic} are the same colour`).not.toBe(painted(basic))
      }
    }
  }
}

async function openDeskBuy(page: Page) {
  await page.goto('command')
  await ready(page)
  await openCityFace(page)
  await expect(page.getByTestId('trade-row').first()).toBeVisible()
}

for (const vp of [
  { name: 'phone 390×844', size: PHONE, wide: false },
  { name: 'wide 1280×800', size: WIDE, wide: true },
]) {
  test(`${vp.name}: every list a good stands in wears a class mark — nothing grows, nothing overlaps, premium differs from basic`, async ({ page, request, baseURL }) => {
    // one boot, then the lists in turn: the cold world costs minutes, a reload of a saved one seconds
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
    await page.setViewportSize(vp.size)
    const colours = new Map<number, Set<string>>()

    // 1. THE DESK'S BUY FACE — the Market ledger (TradeRow)
    await openDeskBuy(page)
    expectList(`${vp.name} · desk Buy`, await page.evaluate(inspectRows, '[data-testid="trade-row"]'), colours)

    // …and the press that opens a good spells the class out: the City face's tray (TradeTray →
    // PriceRows) says it in its Kind row, beside the kind and the rarity
    const row = page.getByTestId('trade-row').first()
    const rowClass = Number(await row.getAttribute('data-good-class'))
    await row.getByRole('button').first().click()
    const tray = page.getByTestId('trade-tray')
    await expect(tray).toBeVisible()
    const spoken = tray.getByTestId('good-kind-row').locator('[data-good-class-mark]')
    await expect(spoken, "the trade tray names the good's class").toHaveCount(1)
    await expect(spoken).toHaveAttribute('data-good-class-mark', String(rowClass))
    await expect(spoken).toHaveText(EN_WORDS[rowClass - 1])
    // the three words stand in the Kind row without pushing it sideways (at 390 it is the tray's whole width)
    const kind = await tray.getByTestId('good-kind-row').evaluate((el) => ({ spill: el.scrollWidth - el.clientWidth, over: el.getBoundingClientRect().right - el.closest('[data-testid="trade-tray"]')!.getBoundingClientRect().right }))
    expect(kind.spill, 'the Kind row scrolls sideways').toBeLessThanOrEqual(1)
    expect(kind.over, 'the Kind row runs past the tray').toBeLessThanOrEqual(1)

    // 1b. THE TRADE FACE — the one a player lands on: a Buy press opens TradePanel, whose header says it too
    await page.goto('command')
    await ready(page)
    // the desk remembers the face it was left on (City): turn to Trade, then press the first Buy that is alive
    await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Trade', exact: true }).click()
    const buy = page.locator('[data-testid="trade-buy"]:not([disabled])').first()
    await expect(buy, 'the Trade face has no good to buy').toBeVisible({ timeout: 60_000 })
    await buy.click()
    const detail = page.getByTestId('good-detail')
    await expect(detail).toBeVisible()
    const said = detail.locator('[data-good-class-mark]')
    await expect(said, "the trade panel names the good's class").toHaveCount(1)
    const saidClass = Number(await said.getAttribute('data-good-class-mark'))
    expect(saidClass >= 1 && saidClass <= 5).toBe(true)
    await expect(said).toHaveText(EN_WORDS[saidClass - 1])

    // 2. THE REQUEST BOARD — the same face, turned (world.contracts)
    await page.goto('command')
    await ready(page)
    await openCityFace(page)
    await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: /^Requests$/ }).click()
    await expect(page.getByTestId('request-row').first()).toBeVisible({ timeout: 30_000 })
    expectList(`${vp.name} · desk Requests`, await page.evaluate(inspectRows, '[data-testid="request-row"]'), colours)

    // 3. THE CODEX'S GOODS (SnapshotGood): every good of the world, every class — the face stands on the glass (the
    // Codex unfold, #448): its 629 rows are one list panel, nothing to open
    await page.goto('compendium')
    await ready(page)
    await expect(page.getByTestId('good-tile').first()).toBeVisible({ timeout: 60_000 })
    const tiles = await page.evaluate(inspectRows, '[data-testid="good-tile"]')
    expectList(`${vp.name} · Codex goods`, tiles, colours)
    expect(new Set(tiles.map((t) => t.cls)), 'the Codex does not show all five classes — the catalogue has an empty class').toEqual(new Set([1, 2, 3, 4, 5]))
    // a tile's press spells the class out, in the tray, in its own row
    const loud = page.locator('[data-testid="good-tile"][data-good-class="5"]').first()
    await loud.scrollIntoViewIfNeeded()
    await loud.click()
    const codexTray = page.getByTestId('good-tray')
    await expect(codexTray).toBeVisible()
    await expect(codexTray.getByTestId('good-class-row')).toContainText(EN_WORDS[4])
    await expect(codexTray.getByTestId('good-class-row').locator('[data-good-class-mark]')).toHaveAttribute('data-good-class-mark', '5')

    // 4. THE FORGE (a recipe names its goods by code: the class is read off the catalogue)
    await page.goto('city')
    await ready(page)
    await page.getByTestId('city-building-forge').click()
    await expect(page.getByTestId('city-face-panel')).toHaveAttribute('data-building', 'forge')
    await page.locator('[data-testid^="city-forge-tier-"]').first().click()
    await expect(page.locator('[data-testid^="forge-product-"]').first()).toBeVisible({ timeout: 60_000 })
    expectList(`${vp.name} · Forge`, await page.evaluate(inspectRows, '[data-testid^="forge-product-"]'), colours)

    // 5. THE CITY PAGE'S MARKET — wide only (see the header: the 390 two-region layout is another slice's)
    if (vp.wide) {
      await page.goto('city')
      await ready(page)
      await page.getByTestId('city-building-market').click()
      await expect(page.getByTestId('trade-row').first()).toBeVisible({ timeout: 60_000 })
      expectList(`${vp.name} · City market`, await page.evaluate(inspectRows, '[data-testid="trade-row"]'), colours)
    }

    expectOneTable(colours)
  })
}

test('a cargo list (CargoRows, the one a fleet and a merchant share) wears the class: nothing grows, nothing overlaps', async ({ page, request, baseURL }) => {
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  const colours = new Map<number, Set<string>>()
  for (const size of [PHONE, WIDE]) {
    await page.setViewportSize(size)
    await page.goto('ui')
    await expect(page.getByTestId('gallery-good-marks')).toBeVisible()
    const rows = await page.evaluate(inspectRows, '[data-testid="gallery-cargo-row"]')
    expect(rows.map((r) => r.cls), 'one good in each class').toEqual([1, 2, 3, 4, 5])
    expectList(`cargo @${size.width}`, rows, colours)
  }
  expectOneTable(colours)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BROWSER — Korean: the words are the player's, in the player's language
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })

  test('the Codex tiles and the City market speak the Korean class words, and no Latin', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.setViewportSize(WIDE)
    const colours = new Map<number, Set<string>>()

    await page.goto('compendium')
    await ready(page)
    await expect(page.getByTestId('good-tile').first()).toBeVisible({ timeout: 60_000 })
    expectList('ko · Codex goods', await page.evaluate(inspectRows, '[data-testid="good-tile"]'), colours, KO_WORDS)

    await page.goto('city')
    await ready(page)
    await page.getByTestId('city-building-market').click()
    await expect(page.getByTestId('trade-row').first()).toBeVisible({ timeout: 60_000 })
    expectList('ko · City market', await page.evaluate(inspectRows, '[data-testid="trade-row"]'), colours, KO_WORDS)
    expectOneTable(colours)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BROWSER — the sort (0244's machinery, one more key)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test('Stats › Markets sorts every good by class, premium first, through the sort it already has — and each row wears its class', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.setViewportSize(PHONE)
  await page.goto('stats')
  await ready(page)
  await page.getByRole('tab', { name: 'Markets', exact: true }).click()
  // THE LIST STANDS ON THE FACE (the unfold slice, #447): its sort is a select in the list panel's own header — nothing to open
  await expect(page.getByTestId('stats-markets-sort')).toBeVisible({ timeout: 60_000 })
  // the key is one of the existing sort's own options, beside price and name
  const options = await page.getByTestId('filter-pick-sort').locator('option').evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value))
  expect(options).toEqual(expect.arrayContaining(['movers', 'price', 'name', 'class']))
  await page.getByTestId('filter-pick-sort').selectOption('class')
  await expect(page.getByTestId('stats-good').first()).toBeVisible({ timeout: 60_000 })

  const rows = await page.evaluate(inspectRows, '[data-testid="stats-good"]')
  expectList('stats Every good', rows, new Map())
  const order = rows.map((r) => r.cls as number)
  expect(order[0], 'the first good of a class sort is not a luxury').toBe(5)
  for (let i = 1; i < order.length; i++) expect(order[i], `row ${i} is a higher class than the row before it`).toBeLessThanOrEqual(order[i - 1])
  expect(new Set(order).size, 'a class sort that shows one class proves nothing').toBeGreaterThan(1)
})
