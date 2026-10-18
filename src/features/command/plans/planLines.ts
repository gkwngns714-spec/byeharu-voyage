// A PLAN, IN THE GRAMMAR'S OWN WORDS (docs/COMMAND_DESK.md §3.5) — pure: no React, no store, no figure.
//
//   SAIL Mocha                       (when the fleet is not already there; the course proposed by the one
//   BUY coffee 60 AT <= 95            course author between the roads — `proposeCourse`, as a typed SAIL
//   SAIL Lisbon                       and the route editor propose theirs; the server re-verifies it when
//   SELL coffee ALL AT >= 140         the line runs, so a proposal makes nothing legal, only findable)
//
// and "Make it a route": the same two stops in the route editor's own draft (`RouteStopDraft`). Every
// rule — can it buy there, is the price inside the limit, is the water open — is the server's, when the
// line runs (COMMAND_DESK D6: a plan does not wait; a limit missed refuses the line like any order).

import { proposeCourse, sailOrigin, sailTarget } from '../../../domain/passage'
import type { SeaNav } from '../../../lib/sea'
import type { FleetView, PlanLine, SnapshotPort } from '../../../lib/rpc'
import { emptyStop, type RouteStopDraft } from '../standingRouteDraft'
import type { PlanDraft } from './planDraft'

export type PlanText = { ok: true; lines: PlanLine[] } | { ok: false; noCourseTo: string }

/** A number as the grammar reads it: no grouping, at most two decimals. */
function num(n: number): string {
  return String(Math.round(n * 100) / 100)
}

export function planLines(
  plan: PlanDraft,
  fleet: FleetView,
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
): PlanText {
  const lines: PlanLine[] = []
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  let from = sailOrigin(fleet, portByCode)
  const sail = (code: string): boolean => {
    const to = sailTarget({ dest: code }, portByCode)
    const course = from && to ? proposeCourse(nav, from, to) : null
    if (!course) return false
    lines.push({ text: `SAIL ${code}`, path: course })
    from = to
    return true
  }
  let here = docked
  if (plan.buyAt) {
    if (plan.buyAt !== here) {
      if (!sail(plan.buyAt)) return { ok: false, noCourseTo: plan.buyAt }
      here = plan.buyAt
    }
    lines.push({
      text: `BUY ${plan.good} ${plan.units !== null && plan.units > 0 ? num(plan.units) : 'ALL'}${plan.max !== null ? ` AT <= ${num(plan.max)}` : ''}`,
    })
  }
  if (plan.sellAt) {
    if (plan.sellAt !== here) {
      if (!sail(plan.sellAt)) return { ok: false, noCourseTo: plan.sellAt }
    }
    lines.push({ text: `SELL ${plan.good} ALL${plan.min !== null ? ` AT >= ${num(plan.min)}` : ''}` })
  }
  return { ok: true, lines }
}

/** "Make it a route": the buy stop and the sell stop, in the route editor's own draft. */
export function planRoute(plan: PlanDraft): RouteStopDraft[] {
  const stops: RouteStopDraft[] = []
  if (plan.buyAt) {
    stops.push({ ...emptyStop(plan.buyAt), sellAll: false, buyGood: plan.good, buyUnits: plan.units, buyMax: plan.max })
  }
  if (plan.sellAt) {
    stops.push({ ...emptyStop(plan.sellAt), sellAll: true, sellAllFloor: { price_limit: plan.min, at_profit: false } })
  }
  return stops
}
