// Bundled by tests/fight.log.spec.ts (rolldown) so the REAL FightLog can be server-rendered: Playwright's own
// transform swaps a .tsx import in a spec for a component reference, so the spec cannot import it directly
// (tests/kinds.entry.ts is the same seam for the chart). The bundle holds its own copy of the dictionary's state, so
// the language is set through it.
// 0357: the battle card's face (src/live/BattleView.tsx) through the same seam, for tests/battle.card.spec.ts.
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { setLocale } from '../src/lib/i18n'
import { BattleView } from '../src/live/BattleView'
import { FightLog } from '../src/live/FightLog'

export { setLocale }
export function renderLog(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(FightLog as never, props))
}
export function renderBattle(props: Record<string, unknown>): string {
  return renderToStaticMarkup(createElement(BattleView as never, props))
}
