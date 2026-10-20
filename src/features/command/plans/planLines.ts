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
//
// INSURING THE CARGO (0212). `plan.insure` writes ` INSURED` on every LADEN SAIL — the legs after the BUY (or
// every leg, when the plan sells what is already on board) — and on no empty leg: an empty hold insures nothing
// and would be charged nothing, so the word there is noise. The price is the server's, set when she sails
// (public.insure_voyage over the cargo then on board); nothing here guesses it.

import { proposeCourse, sailOrigin, sailTarget } from '../../../domain/passage'
import { pathLengthNm } from '../../../lib/geo'
import { formatMiles, formatVoyageDays } from '../../../lib/format'
import type { SeaNav } from '../../../lib/sea'
import type { BoardPassage, FleetView, GoodBoard, PlanLine, SnapshotPort } from '../../../lib/rpc'
import { emptyStop, type RouteStopDraft } from '../standingRouteDraft'
import type { PlanDraft } from './planDraft'

export type PlanText = { ok: true; lines: PlanLine[] } | { ok: false; noCourseTo: string }

/** A number as the grammar reads it: no grouping, at most two decimals. */
function num(n: number): string {
  return String(Math.round(n * 100) / 100)
}

/** Sailed miles as days at sea at this fleet's speed — the one arithmetic the plan and its words share. */
function daysAt(nm: number, speedKn: number): number {
  return nm / speedKn / 24
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
  // 0212: laden from the start when the plan sells what is on board; otherwise from the BUY on
  let laden = plan.buyAt === null
  /** A SAIL with its proposed course; at a harbour, PROVISION FULL first when her casks would not cover it. */
  const sail = (code: string): boolean => {
    const to = sailTarget({ dest: code }, portByCode)
    const course = from && to ? proposeCourse(nav, from, to) : null
    if (!course) return false
    if (stores && stores.speedKn > 0) {
      const days = daysAt(pathLengthNm(course.map(([lat, lon]) => ({ lat, lon }))), stores.speedKn)
      if (here !== null && casks < days * stores.margin) {
        if (buyLine !== null && here === plan.buyAt) lines.splice(buyLine, 0, { text: 'PROVISION FULL' })
        else lines.push({ text: 'PROVISION FULL' })
        casks = Math.max(casks, stores.days)
      }
      casks -= days
    }
    lines.push({ text: `SAIL ${code}${plan.insure && laden ? ' INSURED' : ''}`, path: course })
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
    laden = true
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

/** "via Ceuta, Angra" — the ports the voyage calls at between (0188), or null when it sails straight.
 *  THE ONE WORDING: the plan builder's estimate line and the best-trade card both read it. */
export function viaWords(stops: readonly string[], name: (code: string) => string): string | null {
  return stops.length > 0 ? `via ${stops.map(name).join(', ')}` : null
}

/** What the board served about the fleet reading a row (0188): its speed, the farthest one leg its captain
 *  plots (null for a company sailing without one), and the days of supplies on board now (null when the
 *  board did not say). */
export interface ReachBoard {
  speedKn: number
  reachNm: number | null
  supplyDays: number | null
}

/** That, read off a served `world.good_board`. */
export function reachBoard(board: Pick<GoodBoard, 'fleet' | 'reach' | 'supplies'>): ReachBoard {
  return { speedKn: board.fleet.speed_kn, reachNm: board.reach?.reach_nm ?? null, supplyDays: board.supplies?.days ?? null }
}

/** A leg's length as the player reads it: days at sea at this fleet's speed (docs/WORDS.md — a distance reads
 *  as days of sailing); miles only when the board gave no speed to sail them at. */
function legWords(nm: number, speedKn: number): string {
  return speedKn > 0 ? formatVoyageDays(daysAt(nm, speedKn)) : formatMiles(nm)
}

/** Why a city cannot be sailed to (0188), in plain words — THE ONE WORDING, read after the city's name and a
 *  dash by the plan builder's note and the best-trade card alike (docs/WORDS.md: no nm, no her, no passage):
 *
 *    too far to sail in one go: your navigator can only plan 9.4 days at sea without a stop. A captain with
 *      Navigation 3 could take you there
 *    too far to sail in one go: your navigator can only plan 9.4 days at sea without a stop. No captain can plan
 *      a trip that long, and there are no ports on the way to stop at
 *    the longest stretch at sea is 21.3 days, but your supplies last only 12.0 days
 *  (the owner, 2026-10-19: "What does this mean? make it in simple words")
 *
 *  No voyage: the board served no `stops` (or, as 0188 serves a buy row it cannot reach, `stops: []` with no
 *  miles). Otherwise the voyage exists and it is the supplies that fall short. */
export function reachWords(row: BoardPassage & { miles: number | null }, board: ReachBoard): string {
  if (row.stops == null || row.miles === null) {
    const own = `too far to sail in one go${board.reachNm !== null ? `: your navigator can only plan ${legWords(board.reachNm, board.speedKn)} at sea without a stop` : ''}`
    const n = row.needs
    if (n && n.navigation !== null) return `${own}. A captain with Navigation ${n.navigation} could take you there`
    if (n) return `${own}. No captain can plan a trip that long, and there are no ports on the way to stop at`
    return own
  }
  if (row.longest_leg && row.longest_leg.days > 0) {
    const leg = `the longest stretch at sea is ${formatVoyageDays(row.longest_leg.days)}`
    return board.supplyDays !== null ? `${leg}, but your supplies last only ${formatVoyageDays(board.supplyDays)}` : `${leg}, longer than your supplies last`
  }
  return 'too far to sail in one go, or your supplies run out first'
}
