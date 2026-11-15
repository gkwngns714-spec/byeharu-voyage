// Bundled by tests/ship.look.spec.ts (rolldown) so the REAL FleetsLayer and ShipArt can be server-rendered: Playwright's
// own transform swaps a .tsx import in a spec for a component reference, so the spec cannot import them directly
// (tests/kinds.entry.ts is the same seam). ShipArt reads the chart through its barrel, as every caller outside
// src/chart does, so the spec stubs the barrel's `?url` and `?raw` asset imports (the coast and sea files: nothing here draws them).
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { FleetsLayer } from '../src/chart/FleetsLayer'
import { registerHullClasses } from '../src/chart/glyphs'
import { ShipArt } from '../src/live/battle/ShipArt'

export { registerHullClasses }
export function renderLayer(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(FleetsLayer as never, props))
}
export function renderShipArt(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement('svg', null, createElement(ShipArt as never, props)))
}
