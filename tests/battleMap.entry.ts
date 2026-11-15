// Bundled by tests/map.battleJoin.spec.ts (rolldown) so the REAL FleetsLayer, FightRingsLayer and JoinBar can be
// server-rendered: Playwright's own transform swaps a .tsx import in a spec for a component reference, so the spec cannot
// import them directly (tests/kinds.entry.ts is the same seam). The bundle holds its own copy of the dictionary's state,
// so the language is set through it.
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { setLocale } from '../src/lib/i18n'
import { FleetsLayer } from '../src/chart/FleetsLayer'
import { FightRingsLayer } from '../src/chart/FightRingsLayer'
import { JoinBar } from '../src/features/battle/JoinBar'

export { setLocale }
export function renderFleets(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(FleetsLayer as never, props))
}
export function renderRings(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(FightRingsLayer as never, props))
}
export function renderJoin(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(JoinBar as never, props))
}
