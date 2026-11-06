import { test, expect } from '@playwright/test'
import { pathToFileURL } from 'node:url'
import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { rolldown } from 'rolldown'
import * as glyphs from '../src/chart/glyphs'
import { buildChartModel, type TrafficOnChart } from '../src/chart/chartModel'
import { mapTrafficOf } from '../src/chart/liveWorld'
import { shipMarks } from '../src/chart/shipMarks'
import { project } from '../src/lib/geo'
import type { TrafficFleet } from '../src/lib/rpc'

// ═════════════════════════════════════════════════════════════════════════════
// 500 CARGO SHIPS ON THE CHART — 0326: a country keeps 20 to 50 ships, so the world holds up to 500, and a cargo ship is never thinned (KIND_LOOK.cargo.thin false).
//
// WHAT HOLDS THE LOAD DOWN: a ship in port is not on the chart (chartModel, owner 2026-10-13), and a cargo ship sails only with a load. Prod, 2026-11-06: 29 of 100 at sea.
// So the marks grow with the loads, not with the count: 500 ships with 40 at sea draw 40.
//
// THE WORST CASE, 500 AT ONCE AT SEA, on the real FleetsLayer in headless Chromium at DPR 2, is printed, not asserted: a time on a shared PC is a measurement, not a law.
// The figures of 2026-11-06 are in docs/dev-log/2026-11-06-cargo-ships-follow-wealth.md. Needs `vite build` for the stylesheet.
// ═════════════════════════════════════════════════════════════════════════════

const nw = project({ lat: 60, lon: -179 })
const se = project({ lat: -60, lon: 179 })
const view = { x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y }
const VIEWPORT = { width: 1440, height: 900 }

function sailing(id: string, i: number, cargo: boolean): TrafficFleet {
  const lat = -40 + ((i * 37) % 800) / 10
  const lon = -170 + ((i * 73) % 3400) / 10
  return {
    id, company: 'Crown Cargo', nation_code: 'PRT', ink: 'prt', name: `Ship ${i}`, status: 'SAILING',
    ships: 1, hulls: cargo ? ['qpinnace'] : ['nau', 'barca'],
    port: null, roadstead: null, anchor: null, next_lap_at: null, lane: null,
    ...(cargo ? { kind: 'CARGO_SHIP' as const } : {}),
    voyage: {
      to: 'FNC', dest_point: null, course: [[lat, lon], [lat + 1, lon + 1]], eta: new Date(Date.now() + 600_000).toISOString(), total_nm: 500, nm_done: 100,
      waters: [], departed_at: new Date(Date.now() - 30_000).toISOString(),
      position: { seg_index: 0, leg_frac: 0.25, nm_done: 100, total_nm: 500, lat, lon, seg_nm: 400 },
    },
  }
}

function docked(id: string): TrafficFleet {
  return {
    id, company: 'Crown Cargo', nation_code: 'PRT', ink: 'prt', name: 'Cargo ship', status: 'DOCKED',
    ships: 1, hulls: ['qpinnace'], kind: 'CARGO_SHIP',
    port: 'LIS', roadstead: [38.6, -9.4], anchor: null, voyage: null, next_lap_at: null, lane: null,
  }
}

const world = (merchants: number, cargoAtSea: number, cargoInPort: number): TrafficFleet[] => [
  ...Array.from({ length: merchants }, (_, i) => sailing(`m-${i}`, i, false)),
  ...Array.from({ length: cargoAtSea }, (_, i) => sailing(`c-${i}`, i + 1000, true)),
  ...Array.from({ length: cargoInPort }, (_, i) => docked(`d-${i}`)),
]

const cargoOf = (marks: readonly TrafficOnChart[]) => marks.filter((t) => t.merchant.cargo).length

test('500 cargo ships with 40 at sea draw 40 marks: a ship in port is not on the chart', () => {
  const model = buildChartModel([], [], [], null, mapTrafficOf(world(0, 40, 460)))
  expect(model.traffic).toHaveLength(40)
  expect(cargoOf(shipMarks([], model.traffic, view).traffic)).toBe(40)
})

test('the widest view keeps every cargo ship at sea, 500 of them, and thins only the merchants', () => {
  const model = buildChartModel([], [], [], null, mapTrafficOf(world(800, 500, 0)))
  const marks = shipMarks([], model.traffic, view).traffic
  expect(cargoOf(marks)).toBe(500)
  expect(marks.length).toBeLessThan(1300)
})

test('measured at DPR 2: the real layer with 40 and with 500 cargo ships at sea', async ({ browser }) => {
  const file = path.resolve('test-results', 'cargoload-render.mjs')
  const bundle = await rolldown({
    input: path.resolve('tests', 'kinds.entry.ts'),
    platform: 'node',
    external: ['react', 'react-dom/server'],
    transform: { jsx: { runtime: 'automatic' } },
    logLevel: 'silent',
  })
  await bundle.write({ file, format: 'esm' })
  const render = (await import(pathToFileURL(file).href)) as {
    renderLayer: (props: Record<string, unknown>) => string
    registerHullClasses: typeof glyphs.registerHullClasses
  }
  render.registerHullClasses((['fore', 'square'] as const).flatMap((rig) => ([1, 2, 3, 4, 5, 6] as const).map((size) => ({ code: `${rig}${size}`, rig, tier: size, size }))))
  const css = readFileSync(path.join('dist', 'assets', readdirSync(path.join('dist', 'assets')).find((f) => f.endsWith('.css'))!), 'utf8')

  const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2 })
  const page = await context.newPage()
  await page.setContent(`<!doctype html><style>${css}</style><body style="margin:0"><div id="glass"></div></body>`)
  const out: Record<string, unknown> = {}
  for (const [name, rows] of [['today-29', world(800, 29, 71)], ['job-40', world(800, 40, 320)], ['worst-500', world(800, 500, 0)]] as const) {
    const t0 = performance.now()
    const model = buildChartModel([], [], [], null, mapTrafficOf(rows))
    const t1 = performance.now()
    const marks = shipMarks([], model.traffic, view)
    const t2 = performance.now()
    const svg = render.renderLayer({ fleets: [], traffic: marks.traffic, selectedId: null, unitsPerPx: 0.25, sun: { lat: 20, lon: 0 } })
    const t3 = performance.now()
    const paint = await page.evaluate(async ({ svg, view, vp }) => {
      const glass = document.getElementById('glass')!
      const best: number[] = []
      for (let i = 0; i < 5; i++) {
        glass.innerHTML = ''
        await new Promise((r) => requestAnimationFrame(r))
        const t = performance.now()
        glass.innerHTML = `<svg class="bv-chart-night" width="${vp.width}" height="${vp.height}" viewBox="${view.x} ${view.y} ${view.width} ${view.height}">${svg}</svg>`
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
        best.push(performance.now() - t)
      }
      return best.sort((a, b) => a - b)[2]
    }, { svg, view, vp: VIEWPORT })
    out[name] = {
      marks: marks.traffic.length, modelMs: Math.round(t1 - t0), shipMarksMs: +(t2 - t1).toFixed(2), renderMs: Math.round(t3 - t2), kb: Math.round(svg.length / 1024), paintDpr2Ms: Math.round(paint),
    }
  }
  console.log('MAP LOAD', JSON.stringify(out))
  await context.close()
})
