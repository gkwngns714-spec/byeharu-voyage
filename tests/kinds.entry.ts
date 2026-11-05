// Bundled by tests/map.kinds.spec.ts (rolldown) so the REAL FleetsLayer can be server-rendered: Playwright's own
// transform swaps a .tsx import in a spec for a component reference, so the spec cannot import it directly.
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { FleetsLayer } from '../src/chart/FleetsLayer'
import { registerHullClasses } from '../src/chart/glyphs'

export { registerHullClasses }
export function renderLayer(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(FleetsLayer as never, props))
}
