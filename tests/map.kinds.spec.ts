// ═════════════════════════════════════════════════════════════════════════════════════════════════
// EVERY KIND HAS ITS LOOK, DAY AND NIGHT — W0a `each_kind_its_look` of docs/WORLD_POWERS.md section 9
// ═════════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"the ship type (cargo, merchant, navy) should be distinguished, as in graphics or as in color.
//    day and night"*   (owner, 2026-11-05)
//
// Written first, RED on main (the day merchant on the pale shallows is 1.6 : 1, her keyline the day sea), then
// green. The contrast law does not read a copy of anything: it server-renders the REAL `FleetsLayer` for each
// kind, lays it on a ground in a real browser with the BUILT stylesheet (`dist/assets/*.css`, so run
// `vite build` first), and reads the computed fill, keyline and mark colours the browser resolved (CSS mixes
// in sRGB, and so does this).
//
// WHAT IS NOT HERE YET: navy and pirate have no shape and no row (W12, W17: "same spec gains the row").
//
// TWO THINGS THE DOC GOT WRONG ABOUT THE GROUND, FOUND BY READING THE CSS:
//  - The doc's "light sea" ground does not occur on a chart: `.bv-chart-night` puts the night palette back on
//    the chart in BOTH schemes (src/index.css). So "light sea" here is the light theme's chart, which must
//    measure the same as the dark one, and does.
//  - Regions OFF is the default, and then a merchant is the one blue (`--color-merchant`), not her nation's ink.
//    The server-rendered default is Regions off; "Regions on" is the same CSS rule the cargo ship wears with no
//    day share, and is measured that way (named in the table).

import { test, expect, type Page } from '@playwright/test'
import { rolldown } from 'rolldown'
import { pathToFileURL } from 'node:url'
import { mkdirSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import * as glyphs from '../src/chart/glyphs'
import { project } from '../src/lib/geo'
import type { FleetOnChart, TrafficOnChart } from '../src/chart/chartModel'
import type { MerchantInk } from '../src/chart/mapTypes'
import { mapTrafficOf } from '../src/chart/liveWorld'
import type { TrafficFleet } from '../src/lib/rpc'

const INKS: readonly MerchantInk[] = ['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east']
const CLASSES = (['fore', 'square'] as const).flatMap((rig) =>
  ([1, 2, 3, 4, 5, 6] as const).map((size) => ({ code: `${rig}${size}`, rig, tier: size, size })),
)

// ── the built stylesheet ───────────────────────────────────────────────────────────────────────────
function builtCss(): string {
  const dir = path.join('dist', 'assets')
  const file = readdirSync(dir).find((f) => f.endsWith('.css'))
  if (!file) throw new Error('no built CSS in dist/assets: run vite build first')
  return readFileSync(path.join(dir, file), 'utf8')
}

// ── one ship, as the real layer draws her ──────────────────────────────────────────────────────────
// The real FleetsLayer, bundled for node (tests/kinds.entry.ts says why it is not imported directly).
let render: { renderLayer: (props: Record<string, unknown>) => string; registerHullClasses: typeof glyphs.registerHullClasses }
test.beforeAll(async () => {
  const file = path.resolve('test-results', 'kinds-render.mjs')
  const bundle = await rolldown({
    input: path.resolve('tests', 'kinds.entry.ts'),
    platform: 'node',
    external: ['react', 'react-dom/server'],
    transform: { jsx: { runtime: 'automatic' } },
    logLevel: 'silent',
  })
  await bundle.write({ file, format: 'esm' })
  render = (await import(pathToFileURL(file).href)) as typeof render
  render.registerHullClasses(CLASSES)
})

const AT = { lat: 0, lon: 0 }
type Who = { readonly kind: 'merchant' | 'cargo' | 'yours'; readonly ink: MerchantInk; readonly hull?: string }

function fleetOf(id: string, heading = 0, hulls: string[] = ['nau']): FleetOnChart {
  return {
    fleet: { id, hulls },
    at: AT,
    voyage: null,
    track: null,
    heading,
    destinationCode: null,
    dockedAtCode: null,
  } as unknown as FleetOnChart
}

/** The real FleetsLayer drawing ONE ship on a 40-unit window centred on her, `scale` device px per CSS px. */
function shipSvg(who: Who, ground: string, extra = '', size = 40, heading = 0): string {
  const p = project(AT)
  const row = who.kind === 'yours' ? null : ({ ...fleetOf('t', heading, who.kind === 'cargo' ? [who.hull ?? glyphs.CARGO_HULL] : ['nau']), merchant: { ink: who.ink, ...(who.kind === 'cargo' ? { cargo: true } : {}) }, loopD: null, laneD: null } as unknown as TrafficOnChart)
  const layer = {
    fleets: row ? [] : [fleetOf('f', heading)],
    traffic: row ? [row] : [],
    selectedId: null,
    unitsPerPx: 1,
    sun: { lat: 90, lon: 0 },
  }
  return `<svg class="bv-chart-night" data-kind="${who.kind}" data-ink="${who.ink}" width="${size}" height="${size}" viewBox="${p.x - 20} ${p.y - 20} 40 40" style="background:${ground};${extra}">${render.renderLayer(layer)}</svg>`
}

// ── colour arithmetic (WCAG 2.x), on what the browser resolved ─────────────────────────────────────
type Rgba = readonly [number, number, number, number]
function parse(c: string): Rgba {
  const rgb = c.match(/rgba?\(([^)]+)\)/)
  if (rgb) {
    const [r, g, b, a] = rgb[1].split(/[ ,/]+/).filter(Boolean).map(Number)
    return [r / 255, g / 255, b / 255, a ?? 1]
  }
  const cs = c.match(/color\(srgb ([^)]+)\)/)
  if (cs) {
    const [r, g, b, a] = cs[1].split(/[ /]+/).filter(Boolean).map(Number)
    return [r, g, b, a ?? 1]
  }
  throw new Error(`cannot read colour ${c}`)
}
const over = (top: Rgba, under: Rgba): Rgba => {
  const a = top[3]
  return [top[0] * a + under[0] * (1 - a), top[1] * a + under[1] * (1 - a), top[2] * a + under[2] * (1 - a), 1]
}
const lum = (c: Rgba) => {
  const f = (v: number) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
  return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
}
const contrast = (a: Rgba, b: Rgba) => {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

interface Reading {
  readonly kind: string
  readonly ink: string
  readonly fill: Rgba
  readonly line: Rgba
  readonly mark: Rgba | null
  readonly ground: Rgba
}

/** Lay every ship on its ground, turn `--night` to `night`, and read what the browser resolved. */
async function read(page: Page, night: number): Promise<Reading[]> {
  const rows = await page.evaluate((n) => {
    const out: Record<string, string | null>[] = []
    for (const svg of Array.from(document.querySelectorAll('svg[data-kind]'))) {
      for (const g of Array.from(svg.querySelectorAll<SVGGElement>('g[data-hulls]'))) g.style.setProperty('--night', String(n))
      const hull = svg.querySelector('path[data-hull-class]')!
      const mark = svg.querySelector('path[data-kind-mark]')
      const halo = svg.querySelector('circle.bv-sun-fleet-halo')
      const cs = getComputedStyle(hull)
      out.push({
        kind: svg.getAttribute('data-kind'),
        ink: svg.getAttribute('data-ink'),
        fill: cs.fill,
        line: cs.stroke,
        mark: mark ? getComputedStyle(mark).fill : null,
        ground: getComputedStyle(svg).backgroundColor,
        halo: halo ? getComputedStyle(halo).fill : null,
      })
    }
    return out
  }, night)
  return rows.map((r) => {
    let ground = parse(r.ground!)
    if (r.halo) ground = over(parse(r.halo), ground) // yours is read against her halo, not the bare sea
    return { kind: r.kind!, ink: r.ink!, fill: parse(r.fill!), line: parse(r.line!), mark: r.mark ? parse(r.mark) : null, ground }
  })
}

/** Dress every drawn cargo hull as a Regions-on merchant in her nation's ink: the FleetsLayer rule for a merchant when the filter is on (it is a hook, not a prop, so the server render cannot set it). */
const asRegionsMerchant = () => {
  for (const svg of Array.from(document.querySelectorAll<SVGSVGElement>('svg[data-ink]'))) {
    for (const h of Array.from(svg.querySelectorAll<SVGPathElement>('path[data-hull-class]'))) {
      h.classList.remove('bv-sun-kind-fill')
      h.classList.add('bv-sun-merchant-nation')
      h.style.setProperty('--nation-ink', `var(--color-nation-${svg.getAttribute('data-ink')})`)
    }
    for (const m of Array.from(svg.querySelectorAll('path[data-kind-mark]'))) m.remove()
  }
}

const WHO: readonly Who[] = [
  { kind: 'merchant', ink: 'prt' },
  ...INKS.map((ink): Who => ({ kind: 'cargo', ink })),
  { kind: 'yours', ink: 'prt' },
]

const GROUNDS = [
  { name: 'night sea', css: 'var(--color-chart-sea)', night: 1, theme: 'dark' },
  { name: 'night sea, light theme', css: 'var(--color-chart-sea)', night: 1, theme: 'light' },
  { name: 'day sea', css: 'var(--color-chart-day-sea)', night: 0, theme: 'dark' },
  { name: 'day deep', css: 'var(--color-chart-day-deep)', night: 0, theme: 'dark' },
  { name: 'day shallow', css: 'var(--color-chart-day-shallow)', night: 0, theme: 'dark' },
] as const

async function pageWith(page: Page, theme: string, ground: string, who: readonly Who[] = WHO): Promise<void> {
  await page.emulateMedia({ colorScheme: theme === 'light' ? 'light' : 'dark' })
  await page.setContent(
    `<!doctype html><html data-theme="${theme}"><head><style>${builtCss()}</style></head><body style="margin:0">` +
      who.map((w) => shipSvg(w, ground)).join('') +
      '</body></html>',
  )
}

test.describe('the contrast law, on the built stylesheet', () => {
  test.beforeAll(() => glyphs.registerHullClasses(CLASSES))

  for (const g of GROUNDS) {
    test(`on the ${g.name}: every kind's fill or keyline is 3 : 1, her mark 3 : 1 on her fill`, async ({ page }) => {
      await pageWith(page, g.theme, g.css)
      const rows = await read(page, g.night)
      const table = rows.map((r) => ({
        kind: r.kind,
        ink: r.ink,
        fill: contrast(r.fill, r.ground).toFixed(2),
        keyline: contrast(r.line, r.ground).toFixed(2),
        mark: r.mark ? contrast(r.mark, r.fill).toFixed(2) : '-',
      }))
      console.log(`${g.name}\n` + table.map((t) => `${t.kind.padEnd(9)}${t.ink.padEnd(5)} fill ${t.fill}  keyline ${t.keyline}  mark ${t.mark}`).join('\n'))
      for (const r of rows) {
        const best = Math.max(contrast(r.fill, r.ground), contrast(r.line, r.ground))
        expect(best, `${r.kind} ${r.ink} on ${g.name}`).toBeGreaterThanOrEqual(3)
        if (r.mark) expect(contrast(r.mark, r.fill), `${r.kind} ${r.ink} mark on ${g.name}`).toBeGreaterThanOrEqual(3)
      }
    })
  }

  test('Regions on: a merchant in her nation ink holds on every ground', async ({ page }) => {
    for (const g of GROUNDS) {
      await pageWith(page, g.theme, g.css, INKS.map((ink): Who => ({ kind: 'cargo', ink })))
      await page.evaluate(asRegionsMerchant)
      for (const r of await read(page, g.night)) {
        expect(Math.max(contrast(r.fill, r.ground), contrast(r.line, r.ground)), `merchant ${r.ink} on ${g.name}`).toBeGreaterThanOrEqual(3)
      }
    }
  })

  test('twilight: at --night 0, 0.25, 0.5, 0.75, 1 the fill or keyline holds on the mixed sea, and the mark on her fill', async ({ page }) => {
    for (const night of [0, 0.25, 0.5, 0.75, 1]) {
      const sea = `color-mix(in srgb, var(--color-chart-sea) ${night * 100}%, var(--color-chart-day-sea))`
      await pageWith(page, 'dark', sea)
      for (const r of await read(page, night)) {
        const best = Math.max(contrast(r.fill, r.ground), contrast(r.line, r.ground))
        expect(best, `${r.kind} ${r.ink} at --night ${night}`).toBeGreaterThanOrEqual(3)
        if (r.mark) expect(contrast(r.mark, r.fill), `${r.kind} ${r.ink} mark at --night ${night}`).toBeGreaterThanOrEqual(3)
      }
    }
  })

  test('one colour: every cargo ship is the same fill whatever her nation, by day and by night, and it is not a merchant colour', async ({ page }) => {
    const fills: string[] = []
    for (const night of [0, 1]) {
      await pageWith(page, 'dark', night ? 'var(--color-chart-sea)' : 'var(--color-chart-day-sea)', [
        ...INKS.map((ink): Who => ({ kind: 'cargo', ink })),
        { kind: 'merchant', ink: 'prt' },
      ])
      const rows = await read(page, night)
      const cargo = rows.filter((r) => r.kind === 'cargo').map((r) => r.fill.join())
      expect(new Set(cargo).size, `cargo fills at --night ${night}`).toBe(1)
      fills.push(cargo[0])
      expect(rows.find((r) => r.kind === 'merchant')!.fill.join(), `merchant vs cargo at --night ${night}`).not.toBe(cargo[0])
    }
    expect(fills[0], 'day and night').toBe(fills[1])
  })
})

test.describe('the silhouettes', () => {
  test.beforeAll(() => glyphs.registerHullClasses(CLASSES))

  test('cargo differs from every merchant hull by at least 20 % of her area, at 1x and 2x', async ({ page }) => {
    const cargo = glyphs.hullPath(glyphs.CARGO_HULL)
    const others = CLASSES.map((c) => ({ code: c.code, d: glyphs.hullPath(c.code) }))
    for (const dpr of [1, 2]) {
      const res = await page.evaluate(
        ({ cargo, others, dpr }) => {
          const raster = (d: string) => {
            const cv = document.createElement('canvas')
            cv.width = 40 * dpr
            cv.height = 40 * dpr
            const c = cv.getContext('2d')!
            c.scale(dpr, dpr)
            c.translate(20, 20)
            c.fill(new Path2D(d))
            return c.getImageData(0, 0, cv.width, cv.height).data
          }
          const a = raster(cargo)
          let area = 0
          for (let i = 3; i < a.length; i += 4) if (a[i] > 127) area++
          return others.map((o) => {
            const b = raster(o.d)
            let diff = 0
            for (let i = 3; i < a.length; i += 4) if (a[i] > 127 !== b[i] > 127) diff++
            return { code: o.code, share: diff / area }
          })
        },
        { cargo, others, dpr },
      )
      for (const r of res) expect(r.share, `cargo vs ${r.code} at ${dpr}x`).toBeGreaterThanOrEqual(0.2)
    }
  })
})

test.describe('one renderer, one table', () => {
  const src = readFileSync(path.join('src', 'chart', 'FleetsLayer.tsx'), 'utf8')
  const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

  test('FleetsLayer has one hullPath, one HullGroup, kindMarkPath once, and names no kind', () => {
    expect(code.match(/hullPath\(/g)).toHaveLength(1)
    expect(code.match(/function HullGroup/g)).toHaveLength(1)
    expect(code.match(/kindMarkPath\(/g)).toHaveLength(1)
    expect(code).not.toMatch(/cargo|navy|pirate/i)
  })

  test('every kind has one row, with the table fields', () => {
    for (const k of ['merchant', 'cargo', 'yours']) {
      expect(Object.keys(glyphs.KIND_LOOK[k as 'merchant']).sort(), k).toEqual(['fill', 'hull', 'mark', 'minHalfLength', 'thin'])
    }
  })

  test('cargo: no hole in her path, the mark is solid; merchants draw no mark', () => {
    expect(glyphs.hullPath(glyphs.CARGO_HULL).match(/M/g)).toHaveLength(1)
    expect(glyphs.KIND_LOOK.cargo.mark).toBe('bars')
    expect(glyphs.KIND_LOOK.merchant.mark).toBeNull()
    expect(glyphs.KIND_LOOK.yours.mark).toBeNull()
  })

  test('size: cargo is drawn at 5.8, above the nau (the ordinary merchant), just under the heavy galleon, and is never thinned', () => {
    expect(glyphs.GLYPH.cargoHullHalfLength).toBe(5.8)
    expect(glyphs.GLYPH.cargoHullHalfLength).toBeGreaterThan(glyphs.GLYPH.hullHalfLength[3])
    expect(glyphs.GLYPH.cargoHullHalfLength).toBeLessThan(glyphs.GLYPH.hullHalfLength[4])
    expect(glyphs.KIND_LOOK.cargo.thin).toBe(false)
    expect(glyphs.KIND_LOOK.cargo.fill.token).toBe('var(--color-cargo-hull)')
    expect(glyphs.KIND_LOOK.merchant.fill.token).toBeNull()
  })

  test('mark width: every bar is at least 2 CSS px thick at the shortest the kind is drawn', () => {
    const l = Math.max(glyphs.KIND_LOOK.cargo.minHalfLength, glyphs.hullHalfLengthOf(glyphs.CARGO_HULL))
    const bars = glyphs.kindMarkPath('bars', l).split('M').filter(Boolean)
    expect(bars).toHaveLength(2)
    for (const bar of bars) {
      const pts = bar.replace('Z', '').split('L').map((p) => p.trim().split(/\s+/).map(Number))
      const ys = pts.map((p) => p[1])
      expect(Math.max(...ys) - Math.min(...ys)).toBeGreaterThanOrEqual(2)
    }
  })
})

test.describe('parity: nothing else moves', () => {
  const row = (over: Partial<TrafficFleet> & { id: string }): TrafficFleet =>
    ({ company: 'c', nation_code: 'PRT', ink: 'prt', name: 'n', status: 'DOCKED', ships: 1, hulls: ['nau'], port: 'LIS', roadstead: [38.7, -9.2], anchor: null, voyage: null, next_lap_at: null, lane: null, ...over }) as TrafficFleet

  test('a merchant row carries no kind and no merchant hull gains an element', async ({ page }) => {
    const [m] = mapTrafficOf([row({ id: 'm1' })])
    expect('cargo' in m).toBe(false)
    expect(glyphs.shipKindOf(m)).toBe('merchant')
    glyphs.registerHullClasses(CLASSES)
    await pageWith(page, 'dark', 'var(--color-chart-sea)', [{ kind: 'merchant', ink: 'prt' }, { kind: 'yours', ink: 'prt' }])
    expect(await page.locator('path[data-kind-mark]').count()).toBe(0)
    expect(await page.locator('path[data-hull-class]').count()).toBe(2)
  })
})

test.describe('the pictures', () => {
  const OUT = path.join('docs', 'dev-log', '2026-11-06-cargo-colour')
  const KINDS: readonly { label: string; who: Who; regionsOn?: boolean }[] = [
    { label: 'merchant (Regions off, the one blue)', who: { kind: 'merchant', ink: 'prt' } },
    { label: 'merchant (Regions on, Portugal)', who: { kind: 'cargo', ink: 'prt', hull: 'nau' }, regionsOn: true },
    { label: 'CARGO, Portugal', who: { kind: 'cargo', ink: 'prt' } },
    { label: 'CARGO, England', who: { kind: 'cargo', ink: 'eng' } },
    { label: 'CARGO, Ottoman', who: { kind: 'cargo', ink: 'ott' } },
    { label: 'yours (gold, on her halo)', who: { kind: 'yours', ink: 'prt' } },
  ]
  const SCENES = [
    { name: 'night', ground: 'var(--color-chart-sea)', night: 1 },
    { name: 'twilight', ground: 'color-mix(in srgb, var(--color-chart-sea) 50%, var(--color-chart-day-sea))', night: 0.5 },
    { name: 'day sea', ground: 'var(--color-chart-day-sea)', night: 0 },
    { name: 'day deep', ground: 'var(--color-chart-day-deep)', night: 0 },
    { name: 'day shallow', ground: 'var(--color-chart-day-shallow)', night: 0 },
  ]

  test('each kind at chart size, 1x and 2x, by night and by day', async ({ browser }) => {
    mkdirSync(OUT, { recursive: true })
    glyphs.registerHullClasses(CLASSES)
    const cell = (k: (typeof KINDS)[number], sc: (typeof SCENES)[number], heading: number, size: number) =>
      `<td style="padding:0">${shipSvg(k.who, sc.ground, '', size, heading).replace('<svg ', `<svg data-night="${sc.night}" ${k.regionsOn ? 'data-regions-on="1" ' : ''}`)}</td>`
    const html =
      `<!doctype html><html data-theme="dark"><head><style>${builtCss()} td,th{font:12px sans-serif;color:#222}</style></head><body style="margin:0;background:#fff;padding:12px"><table style="border-collapse:collapse">` +
      `<tr><th></th>${SCENES.map((s) => `<th colspan="2">${s.name}</th>`).join('')}</tr>` +
      KINDS.map(
        (k) =>
          `<tr><td style="padding-right:12px;white-space:nowrap">${k.label}</td>${SCENES.map((sc) => cell(k, sc, 0, 40) + cell(k, sc, 62, 40)).join('')}</tr>`,
      ).join('') +
      '</table>' +
      `<p style="font:12px sans-serif;color:#222">The same hulls, 4x, to read the shape (night, then day sea)</p><table><tr>${KINDS.map((k) => cell(k, SCENES[0], 0, 160)).join('')}</tr><tr>${KINDS.map((k) => cell(k, SCENES[2], 0, 160)).join('')}</tr></table></body></html>`
    for (const dpr of [1, 2]) {
      const context = await browser.newContext({ viewport: { width: 1000, height: 900 }, deviceScaleFactor: dpr, colorScheme: 'dark' })
      const page = await context.newPage()
      await page.setContent(html)
      await page.evaluate(() => {
        for (const svg of Array.from(document.querySelectorAll<SVGSVGElement>('svg[data-night]'))) {
          for (const g of Array.from(svg.querySelectorAll<SVGGElement>('g[data-hulls]'))) g.style.setProperty('--night', svg.getAttribute('data-night')!)
          if (svg.hasAttribute('data-regions-on')) {
            for (const h of Array.from(svg.querySelectorAll<SVGPathElement>('path[data-hull-class]'))) {
              h.classList.remove('bv-sun-kind-fill')
              h.classList.add('bv-sun-merchant-nation')
              h.style.setProperty('--nation-ink', `var(--color-nation-${svg.getAttribute('data-ink')})`)
            }
            for (const m of Array.from(svg.querySelectorAll('path[data-kind-mark]'))) m.remove()
          }
        }
      })
      await page.screenshot({ path: path.join(OUT, `kinds-${dpr}x.png`), fullPage: true })
      await context.close()
    }
  })
})
