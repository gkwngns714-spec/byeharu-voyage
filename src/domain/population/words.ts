import type { TKey, useT } from '../../lib/i18n'
import type { TownHallPeople } from '../../lib/rpc'

// ONE HOME for the words of a population step (0304 hall, 0305 Stats city page): the arrow, its tone and its reason.

/** THE STEP'S WORDS: an arrow for the last 10-minute step, then why — the signal that moved it, the bound that stopped it, or Steady. */
export const STEP_ARROW: Record<TownHallPeople['kind'], string> = { GROW: '↑', HOLD: '→', SHRINK: '↓' }
export const STEP_TONE: Record<TownHallPeople['kind'], 'success' | 'muted' | 'danger'> = { GROW: 'success', HOLD: 'muted', SHRINK: 'danger' }
const STEP_KIND: Record<TownHallPeople['kind'], TKey> = { GROW: 'city.popGrow', HOLD: 'city.popHold', SHRINK: 'city.popShrink' }
const STEP_REASON: Record<NonNullable<TownHallPeople['reason']>, TKey> = {
  INVEST: 'city.popINVEST',
  FAMINE: 'city.popFAMINE',
  WAR: 'city.popWAR',
  PIRATES: 'city.popPIRATES',
  STORM: 'city.popSTORM',
  CEILING: 'city.popCEILING',
  FLOOR: 'city.popFLOOR',
}
export function stepWords(t: ReturnType<typeof useT>, p: Pick<TownHallPeople, 'kind' | 'reason'>): string {
  const why = p.reason && STEP_REASON[p.reason] ? t(STEP_REASON[p.reason]) : t(STEP_KIND[p.kind])
  return `${STEP_ARROW[p.kind]} ${why}`
}

