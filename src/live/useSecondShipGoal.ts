import { properName, useT } from '../lib/i18n'
import { formatInt, formatRealShort } from '../lib/format'
import { worldHullQuote, worldLevels, type HullQuote, type LevelsView } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useSecondShip, type SecondShip } from './useSecondShip'
import { portNameOf, useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECOND SHIP AS A GOAL — its line and how far along it is, the ONE reading the goal card and the welcome card share.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Lifted out of features/command/GoalCard.tsx (2026-11-23, the visual overhaul's slice 10) when the welcome card came to draw the
// same goal as a ring: two cards may not count one goal two ways. Nothing here is new; it is the goal card's own fold:
//   · a hull on order (0465): its name and when she is ready;
//   · while the yard takes orders and nothing is on order: her purse against the Order's price (the yard's own quote,
//     world.hull_quote, the same cached read the yard's sheet asks; 0472 serves the newcomer's floor there; third play-test,
//     finding 3);
//   · else the yard's lines already stored ("materials 0 / 4", useSecondShip, the sheet's own "Ready 0 / 4").
// `pct` is the same proportion the line says (the purse over the price, or the lines over all of them; a hull on order is all
// the way). Null while the company has no second ship to aim for or no yard has answered (`useSecondShip`).

export interface SecondShipGoal {
  second: SecondShip
  /** Her purse against the Order's price, while that is the line; else null. */
  saving: { have: number; price: number } | null
  /** The line, in the viewer's language. */
  words: string
  /** How far along, 0-100. */
  pct: number
}

export function useSecondShipGoal(nowMs: number): SecondShipGoal | null {
  const t = useT()
  const second = useSecondShip()
  const purse = useWorld((s) => s.ducats)
  const portByCode = useWorld((s) => s.portByCode)
  // the levels read the goal card asks anyway (the same cached key): her Trading level is what re-asks the quote
  const levels = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = levels.view
  const quoteAt = second && second.orderOn && !second.order && second.portId !== null ? second.portId : null
  const quoteHull = second?.hull ?? ''
  const quote = useServedRead<HullQuote>(
    quoteAt === null ? null : `${quoteAt}:${quoteHull}`,
    () => worldHullQuote(quoteAt as string, quoteHull),
    // not on the world's beat: the price moves with her Trading level (0472's discount), so that is what re-asks it
    { name: 'worldHullQuote', trigger: v && v.company ? v.tracks.trading.level : 0 },
  )
  if (!second) return null
  const price = quoteAt !== null && quote.view?.on && typeof quote.view.price === 'number' ? quote.view.price : null
  const saving = second.order === null && price !== null && purse !== null ? { have: purse, price } : null
  const city = second.port ? portNameOf(portByCode, second.port) : null
  const pct = second.order ? 100 : saving ? (Math.max(0, saving.have) / saving.price) * 100 : second.of > 0 ? (second.ready / second.of) * 100 : 0
  return { second, saving, words: secondShipWords(t, second, city, nowMs, saving), pct: Math.min(100, pct) }
}

/** The second ship's line: a hull on order (0465) says when she is ready; else her purse against the Order's price, or the materials
 *  stored, with the yard's city when she is not lying there (the count is of THAT yard, so the line says which). */
export function secondShipWords(
  t: ReturnType<typeof useT>,
  s: SecondShip,
  city: string | null,
  nowMs: number,
  saving: { have: number; price: number } | null,
): string {
  if (s.order) {
    const left = Date.parse(s.order.readyAt) - nowMs
    const name = properName('hull', s.order.name, s.order.name)
    return s.order.ready || left <= 0
      ? t('yard.secondShipOrderReady', { name })
      : t('yard.secondShipOrdered', { name, time: formatRealShort(left) })
  }
  // the yard takes orders: her purse against the Order's price (finding 3), not materials
  if (saving) {
    const have = formatInt(Math.max(0, saving.have))
    const price = formatInt(saving.price)
    return !s.here && city ? t('yard.secondShipSaveAt', { city, have, price }) : t('yard.secondShipSave', { have, price })
  }
  const n = formatInt(s.ready)
  const of = formatInt(s.of)
  return !s.here && city ? t('yard.secondShipAt', { city, n, of }) : t('yard.secondShip', { n, of })
}
