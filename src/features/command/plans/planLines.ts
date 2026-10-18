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
//
// THE PASSAGE SHE CAN SAIL (0188; the owner, 2026-10-18: "your navigation carries you 1700 nm"). A far city is
// reached through the harbours world.good_board serves as the row's `stops` — every leg within her captain's
// reach (voyage.reach_passage, the one authority). Each stop is a real SAIL to a harbour; PROVISION FULL is
// written there only when her casks would not cover the next leg (its course's miles at her speed × the
// endurance margin, voyage.sail_refusal's rule — the stores the board served are the floor after a PROVISION),
// so a long passage spends as few of the queue's lines as it can. cmd.issue_lines asks passage_gate of every
// SAIL before any is queued, and the SAIL itself is still the server's to refuse when it runs.

import { proposeCourse, sailOrigin, sailTarget } from '../../../domain/passage'
import { pathLengthNm } from '../../../lib/geo'
import { formatInt, formatVoyageDays } from '../../../lib/format'
import type { SeaNav } from '../../../lib/sea'
import type { FleetView, PlanLine, SnapshotPort } from '../../../lib/rpc'
import { emptyStop, type RouteStopDraft } from '../standingRouteDraft'
import type { PlanDraft } from './planDraft'

export type PlanText = { ok: true; lines: PlanLine[] } | { ok: false; noCourseTo: string }

/** A number as the grammar reads it: no grouping, at most two decimals. */
function num(n: number): string {
  return String(Math.round(n * 100) / 100)
}

/** The harbours between, per leg, as world.good_board serves them (0188): to the buy city, then to the sell city. */
export interface PlanPassage {
  toBuy: readonly string[]
  toSell: readonly string[]
  /** What the board served (0188): her speed, the days her stores carry now, the margin a leg must leave. */
  stores?: { speedKn: number; days: number; margin: number } | null
}

export function planLines(
  plan: PlanDraft,
  fleet: FleetView,
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
  passage: PlanPassage = { toBuy: [], toSell: [] },
): PlanText {
  const lines: PlanLine[] = []
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  let here = docked
  let from = sailOrigin(fleet, portByCode)
  const stores = passage.stores ?? null
  let casks = stores?.days ?? Number.POSITIVE_INFINITY
  // where the BUY line stands: stores are taken on BEFORE the cargo, so a full hold never refuses the casks
  let buyLine: number | null = null
  /** A SAIL with its proposed course; at a harbour, PROVISION FULL first when her casks would not cover it. */
  const sail = (code: string): boolean => {
    const to = sailTarget({ dest: code }, portByCode)
    const course = from && to ? proposeCourse(nav, from, to) : null
    if (!course) return false
    if (stores && stores.speedKn > 0) {
      const days = pathLengthNm(course.map(([lat, lon]) => ({ lat, lon }))) / stores.speedKn / 24
      if (here !== null && casks < days * stores.margin) {
        if (buyLine !== null && here === plan.buyAt) lines.splice(buyLine, 0, { text: 'PROVISION FULL' })
        else lines.push({ text: 'PROVISION FULL' })
        casks = Math.max(casks, stores.days)
      }
      casks -= days
    }
    lines.push({ text: `SAIL ${code}`, path: course })
    from = to
    here = code
    return true
  }
  /** Through each stop, then on to the city; the first harbour without a course, or null. */
  const passageTo = (stops: readonly string[], city: string): string | null => {
    for (const stop of stops) {
      if (stop === here || stop === city) continue
      if (!sail(stop)) return stop
    }
    return sail(city) ? null : city
  }
  if (plan.buyAt) {
    if (plan.buyAt !== here) {
      const missed = passageTo(passage.toBuy, plan.buyAt)
      if (missed) return { ok: false, noCourseTo: missed }
      here = plan.buyAt
    }
    buyLine = lines.length
    lines.push({
      text: `BUY ${plan.good} ${plan.units !== null && plan.units > 0 ? num(plan.units) : 'ALL'}${plan.max !== null ? ` AT <= ${num(plan.max)}` : ''}`,
    })
  }
  if (plan.sellAt) {
    if (plan.sellAt !== here) {
      const missed = passageTo(passage.toSell, plan.sellAt)
      if (missed) return { ok: false, noCourseTo: missed }
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

/** "via Ceuta, Angra" — the harbours the passage puts in at (0188), or null when it sails straight. */
export function viaWords(stops: readonly string[], name: (code: string) => string): string | null {
  return stops.length > 0 ? `via ${stops.map(name).join(', ')}` : null
}

/** Why a city is not planned (0188): beyond her captain's reach through every harbour, or beyond her stores. */
export function reachWords(
  row: { port: string; stops?: string[] | null; needs?: { navigation: number | null; reach_nm: number } | null; longest_leg?: { days: number } | null },
  name: (code: string) => string,
  reachNm: number | null,
): string {
  if (row.stops === null || row.stops === undefined) {
    const n = row.needs
    const need = n
      ? n.navigation !== null
        ? `needs Navigation ${n.navigation} (reach ${formatInt(n.reach_nm)} nm)`
        : `no Navigation reaches it straight (${formatInt(n.reach_nm)} nm at the most)`
      : null
    return `${name(row.port)} cannot be reached in legs of ${reachNm !== null ? `${formatInt(reachNm)} nm` : 'her reach'}${need ? ` — ${need}` : ''}.`
  }
  return `Her stores will not cover the passage to ${name(row.port)}${row.longest_leg ? ` (its longest leg is ${formatVoyageDays(row.longest_leg.days)})` : ''} — provision first.`
}
