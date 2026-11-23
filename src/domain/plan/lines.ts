// A PLAN, IN THE GRAMMAR'S OWN WORDS (docs/COMMAND_DESK.md §3.5) — pure: no React, no store, no figure.
//
//   SAIL Mocha                       (when the fleet is not already there; the course proposed by the one
//   BUY coffee 60 AT <= 95            course author between the roads — `proposeCourse`, as a typed SAIL
//   SAIL Lisbon                       and the route editor propose theirs; the server re-verifies it when
//   SELL coffee ALL AT >= 140         the line runs, so a proposal makes nothing legal, only findable)
//
// Every rule — can it buy there, is the price inside the limit, is the water open — is the server's, when the
// line runs (COMMAND_DESK D6: a plan does not wait; a limit missed refuses the line like any order).
//
// THE PASSAGE SHE CAN SAIL (0188; the owner, 2026-10-18: "your navigation carries you 1700 nm"). A far city is
// reached through the harbours world.good_board serves as the row's `stops` — every leg within her captain's
// reach (voyage.reach_passage, the one authority). Each stop is a real SAIL to a harbour. cmd.issue_lines asks
// passage_gate of every SAIL before any is queued, and the SAIL itself is still the server's to refuse when it runs.
//
// SUPPLIES ARE THE SAIL'S OWN (0225, owner row 203). No PROVISION line is written here any more: cmd.do_sail buys
// what each leg needs through public.supply_need before it departs, so the plan carries no casks arithmetic and
// no stores input — the board's `supplies` on a row is the same rule's reading, printed by the card.
//
// INSURING THE CARGO (0213). `plan.insure` writes ` INSURED` on every LADEN SAIL — the legs after the BUY (or
// every leg, when the plan sells what is already on board) — and on no empty leg: an empty hold insures nothing
// and would be charged nothing, so the word there is noise. The price is the server's, set when she sails
// (public.insure_voyage over the cargo then on board); nothing here guesses it.
//
// A SECTION OF ITS OWN (0480): moved here whole out of the desk (features/command/plans/planLines.ts) when HQ's board came to send the
// desk's trip with one press (features/city/board/servedPress.ts): two screens write the same lines, so the writer is the game's, not a
// screen's. Nothing in it changed.

import { courseLeg, type PlanLeg, sailOrigin } from '../passage'
import type { SeaNav } from '../../lib/sea'
import type { FleetView, PlanLine, SnapshotPort } from '../../lib/rpc'

/** THE PLAN BEING MADE: one good, one city to buy it at (or what is on board), one city to sell it at, how many, and the two limits
 *  (the desk's draft, features/command/plans/planDraft.ts, keeps one of these). */
export interface PlanDraft {
  /** The good's CODE. */
  good: string
  /** Port CODE to buy at; null when the plan sells what is already on board. */
  buyAt: string | null
  /** Port CODE to sell at. */
  sellAt: string | null
  /** Units to buy; null = as many as fit (ALL). */
  units: number | null
  /** The most to pay a unit (BUY … AT <= max); null = any price. */
  max: number | null
  /** The least to take a unit (SELL … AT >= min); null = any price. */
  min: number | null
  /** 0213: insure the cargo — ` INSURED` on every laden SAIL line (planLines.ts). Absent on a draft
   *  written before 0213, which reads as not asked. */
  insure?: boolean
  /** 0475: A SECOND GOOD for the same trip (a Trade card's `top`): bought at buyAt after the first, sold at sellAt after it. Served for
   *  the first good's units `with`: the lines carry it only while the plan still holds those units and `on` (the sheet's tick). */
  also?: { good: string; units: number; cost: number; profit: number; with: number; on: boolean } | null
}

export type PlanText = { ok: true; lines: PlanLine[]; legs: PlanLeg[] } | { ok: false; noCourseTo: string }

/** A number as the grammar reads it: no grouping, at most two decimals. */
function num(n: number): string {
  return String(Math.round(n * 100) / 100)
}

/** The harbours between, per leg, as world.good_board serves them (0188): to the buy city, then to the sell city. */
export interface PlanPassage {
  toBuy: readonly string[]
  toSell: readonly string[]
}

/** 0475: THE SECOND GOOD the plan's lines carry (a Trade card's `top`, world.best_sales), or null: none, ticked off on the sheet, a
 *  one-ended trip, or the first good's units moved off the count it was served for (the room and the coin it was sized to are gone). */
export function planAlso(plan: Pick<PlanDraft, 'also' | 'units' | 'buyAt' | 'sellAt'>): { good: string; units: number } | null {
  const a = plan.also
  return a && a.on && plan.buyAt && plan.sellAt && plan.units === a.with && a.units > 0 ? { good: a.good, units: a.units } : null
}

export function planLines(
  plan: PlanDraft,
  fleet: FleetView,
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
  passage: PlanPassage = { toBuy: [], toSell: [] },
): PlanText {
  const lines: PlanLine[] = []
  const legs: PlanLeg[] = []
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  let here = docked
  let from = sailOrigin(fleet, portByCode)
  // 0213: laden from the start when the plan sells what is on board; otherwise from the BUY on
  let laden = plan.buyAt === null
  const also = planAlso(plan)
  /** A SAIL with its proposed course. */
  const sail = (code: string): boolean => {
    const next = courseLeg(nav, portByCode, from, here, code)
    if (!next) return false
    legs.push(next.leg)
    lines.push({ text: `SAIL ${code}${plan.insure && laden ? ' INSURED' : ''}`, path: next.leg.path })
    from = next.at
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
    lines.push({
      text: `BUY ${plan.good} ${plan.units !== null && plan.units > 0 ? num(plan.units) : 'ALL'}${plan.max !== null ? ` AT <= ${num(plan.max)}` : ''}`,
    })
    // 0475: the second good, bought right after the first at the same quay (planAlso: only for the units it was served for)
    if (also) lines.push({ text: `BUY ${also.good} ${num(also.units)}` })
    laden = true
  }
  if (plan.sellAt) {
    if (plan.sellAt !== here) {
      const missed = passageTo(passage.toSell, plan.sellAt)
      if (missed) return { ok: false, noCourseTo: missed }
    }
    lines.push({ text: `SELL ${plan.good} ALL${plan.min !== null ? ` AT >= ${num(plan.min)}` : ''}` })
    if (also) lines.push({ text: `SELL ${also.good} ALL` })
  }
  return { ok: true, lines, legs }
}
