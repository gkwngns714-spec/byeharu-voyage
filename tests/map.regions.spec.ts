import { test, expect, type Page } from '@playwright/test'
import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import type { ViewBox } from '../src/lib/geo'
import {
  buildCoastline,
  LABEL_PRIORITY,
  REGION_FILL,
  REGIONS_FILTER_KEY,
  readRegionsFilter,
  regionNameRequests,
  regionTintsOf,
} from '../src/chart'
import { buildRegionTint, regionTintText } from '../scripts/lib/region-tint.mjs'
import { ready, reachable, zoomStepMs } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REGIONS — owner row 93 (2026-09-14): "i told you to create regions on map, show it using
// different color of the sea and country, make filter so that i can choose to apply color, or
// return to the current state."
//
// Pure: the committed data/region-tint.json IS the build (rebuilt here from the chain and
// data/*.json, byte for byte) — so the water on the chart is the raster the game sails and the
// country table is the majority rule, and neither can drift; every region has a token in both
// schemes and a class the JIT can see; the names are label requests to the ONE planner, below
// every harbour and above the seas; with nothing handed in nothing is asked.
//
// Browser: default OFF and the chart's DOM is what it was; ON paints tinted water and land and
// sets a region's name, and the three pinned inks are the same computed colours; OFF again is
// element-for-element the DOM before; the choice survives a reload. Both schemes, both glasses,
// and the frame cost of a zoom step with the filter on against off, printed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const read = (rel: string) => readFileSync(path.join(ROOT, rel), 'utf8')
const WORLD = JSON.parse(read('data/world-110m.json'))
const COAST = buildCoastline(WORLD)
const TINT_RAW = read('data/region-tint.json')
const REGIONS = regionTintsOf(JSON.parse(TINT_RAW), COAST)

// ── 1. THE DATA IS DERIVED, AND THE COMMITTED COPY IS THE DERIVATION ──────────────────────────

test.describe('data/region-tint.json is the build, not a hand', () => {
  test('rebuilt from the chain and data/*.json it is byte-identical to the committed file', () => {
    const { file, report } = buildRegionTint(ROOT)
    expect(regionTintText(file)).toBe(TINT_RAW)
    // The water came from the chain's own writes — all three of them, in order.
    expect(report.writes.map((w) => w.file.slice(10, 14))).toEqual(['0040', '0052', '0079'])
    expect(report.writes.map((w) => w.rows)).toEqual([720, 1, 11])
    // Every navigable cell but the pools no harbour can reach is tinted.
    expect(report.waterCells).toBe(647208)
    expect(report.tintedCells).toBe(647194)
    // Every harbour seeded the search: none was more than 8 rings from water (0040's own bound).
    expect(report.unseeded).toEqual([])
    console.log(
      `countries split across regions (tinted by the majority): ${report.splitCountries
        .map((c) => `${c.iso}→${c.region} [${c.counts.map(([r, n]) => `${r} ${n}`).join(', ')}]`)
        .join('; ')}`,
    )
  })

  test('25 regions, each with land, water, a name, an anchor and a token', () => {
    const raw = JSON.parse(read('data/regions.json')) as { regions: { id: string; name: string }[] }
    expect(raw.regions).toHaveLength(25)
    expect(REGIONS.map((r) => r.id)).toEqual(raw.regions.map((r) => r.id))
    for (const region of REGIONS) {
      expect(region.name).toBe(raw.regions.find((r) => r.id === region.id)!.name)
      expect(region.fill, `${region.id} has no fill class`).toBe(REGION_FILL[region.id])
      expect(region.fill).toBe(`fill-chart-region-${region.id}`)
      expect(region.waterD.startsWith('M'), `${region.id} has no water`).toBe(true)
      expect(Number.isFinite(region.at.x) && Number.isFinite(region.at.y)).toBe(true)
    }
    // MEASURED 2026-09-14: one region holds no drawn land — the Atlantic Isles, whose harbours
    // stand on Portugal's and Spain's islands (tinted with the mainland's majority, Iberia) and on
    // Cape Verde, which the 110m file has no polygon for. Its water is tinted; its name is set.
    expect(REGIONS.filter((r) => r.landD === '').map((r) => r.id)).toEqual(['atlantic-isles'])
    // The land is the BODY'S OWN rings: every country `d` in a region is a substring of the body.
    for (const region of REGIONS) {
      for (const piece of region.landD.split('Z').filter(Boolean)) expect(COAST.d).toContain(piece + 'Z')
    }
  })

  test('every region token is defined in BOTH schemes, and painted through its class', () => {
    const css = read('src/index.css')
    const tokensIn = (opener: string) => {
      const start = css.indexOf(opener)
      let depth = 0
      let i = css.indexOf('{', start)
      const from = i
      for (; i < css.length; i++) {
        if (css[i] === '{') depth++
        else if (css[i] === '}' && --depth === 0) break
      }
      return [...css.slice(from, i).matchAll(/^\s*(--color-chart-region-[a-z-]+)\s*:/gm)].map((m) => m[1]).sort()
    }
    const night = tokensIn('@theme')
    const day = tokensIn(":root[data-theme='light']")
    expect(night).toHaveLength(25)
    expect(day).toEqual(night)
    for (const region of REGIONS) expect(night).toContain(`--color-chart-region-${region.id}`)
    // The class the JIT sees is written out in regions.ts, one per token.
    const source = read('src/chart/regions.ts')
    for (const token of night) expect(source).toContain(token.replace('--color-', 'fill-'))
  })

  test('a malformed file is skipped, never thrown — a backdrop may not take the chart down', () => {
    expect(regionTintsOf(null, COAST)).toEqual([])
    expect(regionTintsOf({ regions: 'no' }, COAST)).toEqual([])
    const one = regionTintsOf(
      { regions: [{ id: 'iberia', name: 'Iberia', at: { lat: 38, lon: -5 } }, { id: 7 }], countries: { PT: 'iberia' }, water: { iberia: [[0, 0, 2, 1], 'junk'] } },
      COAST,
    )
    expect(one).toHaveLength(1)
    expect(one[0].waterD).toBe('M-180 -90h0.5v0.25h-0.5Z')
    expect(one[0].landD).toBe(COAST.countries.find((c) => c.iso === 'PT')!.d)
  })
})

// ── 2. THE NAMES GO THROUGH THE ONE PLANNER ────────────────────────────────────────────────────

test.describe('a region\'s name is a request, below every harbour, above the seas', () => {
  test('on the glass it asks, centred, in the region tone; off the glass it does not', () => {
    const world: ViewBox = { x: -180, y: -90, width: 360, height: 180 }
    const atWorld = regionNameRequests(REGIONS, world)
    expect(atWorld).toHaveLength(25)
    for (const r of atWorld) {
      expect(r.placement).toBe('centred')
      expect(r.tone).toBe('region')
      expect(r.priority).toBe(LABEL_PRIORITY.region)
    }
    expect(LABEL_PRIORITY.region).toBeGreaterThan(LABEL_PRIORITY.sea)
    expect(LABEL_PRIORITY.region).toBeLessThan(LABEL_PRIORITY.quiet + 1)
    const iberia: ViewBox = { x: -12, y: -45, width: 12, height: 10 }
    expect(regionNameRequests(REGIONS, iberia).map((r) => r.text)).toEqual(['Iberia'])
    expect(regionNameRequests([], iberia)).toEqual([])
  })

  test('the filter reads only its own value, and a throwing store means OFF', () => {
    expect(readRegionsFilter(() => '1')).toBe(true)
    expect(readRegionsFilter(() => '0')).toBe(false)
    expect(readRegionsFilter(() => 'yes')).toBe(false)
    expect(readRegionsFilter(() => null)).toBe(false)
    expect(
      readRegionsFilter(() => {
        throw new Error('private mode')
      }),
    ).toBe(false)
    expect(REGIONS_FILTER_KEY).toMatch(/^byeharu-voyage\./)
  })

  test('the layer is furniture: ChartCanvas is the only composer, and off means untouched', () => {
    const canvas = read('src/chart/ChartCanvas.tsx')
    expect(canvas).toContain('regions ? regionNameRequests(regions, box) : []')
    expect(canvas).toContain('regions={regions}')
    const layer = read('src/chart/CoastlineLayer.tsx')
    expect(layer).toContain('data-testid="map-regions-water"')
    expect(layer).toContain('data-testid="map-regions-land"')
    const importers = readdirSync(path.join(ROOT, 'src', 'chart')).filter(
      (f) => /\.tsx?$/.test(f) && read(path.join('src', 'chart', f)).includes("from './regions'"),
    )
    expect(importers.sort()).toEqual(['ChartCanvas.tsx', 'CoastlineLayer.tsx', 'backdrop.ts', 'index.ts', 'useBackdrop.ts'])
  })
})

// ── 3. THE RUNNING CHART ───────────────────────────────────────────────────────────────────────

/** What the sheet holds: element counts per layer, the three pinned inks as computed colours. */
async function sheet(page: Page) {
  return page.evaluate(() => {
    const q = (sel: string) => document.querySelectorAll(sel).length
    const fill = (sel: string) => {
      const el = document.querySelector(sel)
      return el ? getComputedStyle(el).fill : null
    }
    const stroke = (sel: string) => {
      const el = document.querySelector(sel)
      return el ? getComputedStyle(el).stroke : null
    }
    const svg = document.querySelector('[data-testid="map-chart"] svg')
    const layers = svg ? [...svg.children].map((c) => c.getAttribute('data-testid') ?? c.tagName) : []
    return {
      elements: q('[data-testid="map-chart"] svg *'),
      layers,
      water: q('[data-testid="map-regions-water"] path'),
      land: q('[data-testid="map-regions-land"] path'),
      regionNames: [...document.querySelectorAll('[data-label-id^="region:"]')].map((t) => t.textContent),
      harbourNames: q('[data-testid="map-labels"] text'),
      sea: fill('[data-testid="map-sea"]'),
      body: fill('[data-testid="map-coastline"]'),
      coast: stroke('[data-testid="map-coast"]'),
      pressed: document.querySelector('[data-testid="map-regions-toggle"]')?.getAttribute('aria-pressed'),
    }
  })
}


async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForFunction(
    () => (document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d') ?? '').length > 1000,
    undefined,
    { timeout: 60_000 },
  )
  await page.waitForTimeout(300)
}

for (const scheme of ['dark', 'light'] as const) {
  for (const viewport of [
    { width: 390, height: 844 },
    { width: 1440, height: 900 },
  ]) {
    test.describe(`the regions filter — ${scheme}, ${viewport.width}×${viewport.height}`, () => {
      test.use({ viewport, colorScheme: scheme })

      test('off by default and the map as it was; on tints and names; off again identical; kept across a reload', async ({
        page,
        request,
        baseURL,
      }) => {
        test.setTimeout(420_000)
        test.skip(
          !(await reachable(request, baseURL ?? '')),
          `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run.`,
        )
        await openMap(page)
        if (scheme === 'light') {
          // The day sea is the app's own choice (features/profile/appearance.ts); the emulated
          // preference decides it when nothing was chosen.
          expect(await page.evaluate(() => document.documentElement.dataset.theme)).toBe('light')
        }

        const off = await sheet(page)
        expect(off.pressed).toBe('false')
        expect(off.water).toBe(0)
        expect(off.land).toBe(0)
        expect(off.regionNames).toEqual([])
        const costOff = await zoomStepMs(page)
        // Back to where the frame was, so the two sheets are of one view.
        await page.getByRole('button', { name: /^Find/ }).click()
        await page.waitForTimeout(300)
        const offAgain = await sheet(page)
        expect(offAgain.elements).toBe(off.elements)

        await page.getByTestId('map-regions-toggle').click()
        await page.waitForTimeout(300)
        const on = await sheet(page)
        expect(on.pressed).toBe('true')
        expect(on.water).toBeGreaterThan(0)
        expect(on.land).toBeGreaterThan(0)
        expect(on.regionNames.length, 'a region is named on its tint').toBeGreaterThan(0)
        // The pinned inks did not move: the same computed colours on the same elements.
        expect(on.sea).toBe(off.sea)
        expect(on.body).toBe(off.body)
        expect(on.coast).toBe(off.coast)
        // The tints are painted in tokens, both of them on the sheet at once.
        const tinted = await page.evaluate(() =>
          [...document.querySelectorAll('[data-testid="map-regions-water"] path, [data-testid="map-regions-land"] path')].map(
            (p) => getComputedStyle(p).fill,
          ),
        )
        expect(tinted.every((f) => /^(rgb|oklch|color)\(/.test(f))).toBe(true)
        expect(new Set(tinted).size).toBeGreaterThan(1)
        // Harbour names still win: every region name placed is one the planner found room for.
        expect(on.harbourNames).toBeGreaterThan(0)
        const costOn = await zoomStepMs(page)
        await page.getByRole('button', { name: /^Find/ }).click()
        await page.waitForTimeout(300)
        console.log(
          `${scheme} ${viewport.width}×${viewport.height}: filter on → ${on.water} water paths, ${on.land} land paths, ` +
            `names ${on.regionNames.join(' · ')}; zoom step OFF ${costOff.toFixed(1)} ms · ON ${costOn.toFixed(1)} ms; ` +
            `elements off ${off.elements} on ${on.elements}`,
        )

        await page.getByTestId('map-regions-toggle').click()
        await page.waitForTimeout(300)
        const back = await sheet(page)
        expect(back).toEqual(off)

        // Kept: on, reload, still on.
        await page.getByTestId('map-regions-toggle').click()
        await page.waitForTimeout(100)
        expect(await page.evaluate((k) => localStorage.getItem(k), REGIONS_FILTER_KEY)).toBe('1')
        await openMap(page)
        const reloaded = await sheet(page)
        expect(reloaded.pressed).toBe('true')
        expect(reloaded.water).toBeGreaterThan(0)
        await page.getByTestId('map-regions-toggle').click()
        expect(await page.evaluate((k) => localStorage.getItem(k), REGIONS_FILTER_KEY)).toBeNull()
      })
    })
  }
}
