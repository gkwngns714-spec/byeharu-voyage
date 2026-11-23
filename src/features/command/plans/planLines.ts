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

import { courseLeg, daysAt, type PlanLeg, sailOrigin } from '../../../domain/passage'
import { formatFixed, formatMiles, formatVoyageDays } from '../../../lib/format'
import type { SeaNav } from '../../../lib/sea'
import type { BoardPassage, BoardSea, FleetView, GoodBoard, PlanLine, SnapshotPort } from '../../../lib/rpc'
import type { PlanDraft } from './planDraft'
import { getLocale, t } from '../../../lib/i18n'
import { seaWallWords } from '../../../components/ui'
import { seaWallOf } from '../../../lib/rpc'

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

/** THE TRIP'S ROWS ON THE BOARD — the buy row (the plan's buy city), the sell row (its sell city), the trip's days and
 *  the supplies it asks. THE TRIP'S END ROW SAYS BOTH, WHOLE (0361): a trip that ends in a sale reads its sell row (the
 *  server measures that row from where she is, through the buy city when the good is bought first, the calls on the way
 *  in its days and her casks walked along it); a trip that only BUYS (Sail & buy, owner row 229: no sell city) reads its
 *  buy row. Nothing is added up here. THE ONE READING: the Buy / Sell panel and the order's estimate both print it. */
export function tripRows(b: GoodBoard | null, plan: Pick<PlanDraft, 'buyAt' | 'sellAt'>) {
  const buyRow = b && plan.buyAt ? (b.buy.find((r) => r.port === plan.buyAt) ?? null) : null
  const sellRow = b && plan.sellAt ? (b.sell.find((r) => r.port === plan.sellAt) ?? null) : null
  if (plan.buyAt && !plan.sellAt) return { buyRow, sellRow, days: !buyRow ? null : buyRow.here ? 0 : buyRow.days, supplies: buyRow?.supplies ?? null }
  return { buyRow, sellRow, days: plan.buyAt && !buyRow ? null : (sellRow?.days ?? null), supplies: sellRow?.supplies ?? null }
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

/** What the board served about the fleet reading a row (0188): its speed, the farthest one leg its captain
 *  plots (null for a company sailing without one), the days of supplies on board now (null when the
 *  board did not say), and whether the sea conditions bite (0219; false when the board did not say). */
export interface ReachBoard {
  speedKn: number
  reachNm: number | null
  supplyDays: number | null
  seaBite: boolean
}

/** That, read off a served `world.good_board`. */
export function reachBoard(board: Pick<GoodBoard, 'fleet' | 'reach' | 'supplies' | 'sea'>): ReachBoard {
  return {
    speedKn: board.fleet.speed_kn,
    reachNm: board.reach?.reach_nm ?? null,
    // 0231: what her hold can carry beside her cargo (every SAIL tops up to it), not what her casks hold now
    supplyDays: board.supplies?.carry_days ?? board.supplies?.days ?? null,
    seaBite: board.sea?.bite ?? false,
  }
}

/** What the fleet holds, beside what a sea asks: her served title level and wave resistance (null when unread). */
export interface SeaHeld {
  title: number | null
  wave: number | null
}

/** One ask of a sea as HAVE / NEED (2026-11-15 owner: shorter words — "just tell me what i have, and what is required"):
 *  `Waves 12 / 30`, `Title 1 / 2`; the need alone when what she holds is unread. `short`: the server's refusal says this
 *  ask is short (0396's flags; a refusal without them, an older world's, reads its own two figures). */
export interface SeaPair {
  ask: 'wave' | 'title'
  text: string
  short: boolean
}

export function seaPairs(sea: BoardSea, held: SeaHeld | null): SeaPair[] {
  const f = sea.refusal?.figures
  const pair = (ask: 'wave' | 'title', need: number | null, have: number | null, flag: boolean | undefined): SeaPair | null => {
    if (need === null || need <= 0) return null   // an ask of 0 is no ask: never printed (the map and the Codex hide it too)
    const short = !!sea.refusal && (flag ?? (have !== null && have < need))
    return { ask, text: t(ask === 'wave' ? 'desk.seaTagWaves' : 'desk.seaTagTitle', { n: have === null ? String(need) : `${have} / ${need}` }), short }
  }
  return [
    pair('wave', f ? f.needs_wave : sea.needs_wave, (f ? f.wave : held?.wave) ?? null, f?.short_wave),
    pair('title', f ? f.needs_title : sea.needs_title, (f ? f.title : held?.title) ?? null, f?.short_title),
  ].filter((p): p is SeaPair => p !== null)
}

/** What a sea asks, as HAVE / NEED (0219) — THE ONE WORDING, read by `reachWords` when the sea closes a city and
 *  by the plan's per-city sea rows:
 *
 *    Macaronesia and the Canary Current · Waves 12 / 10 · Title 1 / 2     (a refusal names the zone that refuses)
 *    Waves 18 / 30 · Title 2 / 4                                          (the route's most any leg asks)
 *
 *  The figures are the server's. */
export function seaAsksWords(sea: BoardSea, held: SeaHeld | null = null): string {
  const pairs = seaPairs(sea, held)
    .map((p) => p.text)
    .join(' · ')
  return sea.refusal?.figures ? t('desk.seaZone', { zone: sea.refusal.figures.zone_name, pairs }) : pairs
}

/** A leg's length as the player reads it: days at sea at this fleet's speed (docs/WORDS.md — a distance reads
 *  as days of sailing); miles only when the board gave no speed to sail them at. */
function legWords(nm: number, speedKn: number): string {
  return speedKn > 0 ? formatVoyageDays(daysAt(nm, speedKn)) : formatMiles(nm)
}

/** Days as HAVE / NEED in one unit: "4.3 / 7.8 days". */
function daysPair(have: number, need: number): string {
  return t('format.days', { n: `${formatFixed(have, 1)} / ${formatFixed(need, 1)}` })
}

/** Why a city cannot be sailed to (0188), in plain words — THE ONE WORDING, read after the city's name and a
 *  dash by the plan builder's note and the best-trade card alike (docs/WORDS.md: no nm, no her, no passage):
 *
 *    (0219, the sea closes it: the closed-sea wording, components/ui/seaWallWords.ts)
 *    Too far · leg max 9.4 days · needs Navigation 3
 *    Too far · leg max 9.4 days · no captain or stop reaches
 *    Supplies 4.3 / 7.8 days · hold full      (0231: her navigation reaches it, her stores beside her cargo do not)
 *    Supplies 4.3 / 7.8 days · via Guangzhou  (0238: the crossing is on the way to the buy city)
 *    Supplies 12.0 / 21.3 days                (0231: what her hold carries beside her cargo, against the longest leg)
 *  (the owner, 2026-10-19: "make it in simple words"; 2026-11-15: "just tell me what i have, and what is required")
 *
 *  No voyage: the board served no `stops` (or, as 0188 serves a buy row it cannot reach, `stops: []` with no
 *  miles). Otherwise the voyage exists and it is the supplies that fall short. */
export function reachWords(row: BoardPassage & { miles: number | null }, board: ReachBoard): string {
  if (row.stops == null || row.miles === null) {
    // 0219: lit, a city the SEA closes has no voyage either — the server says so; say that, not "too far"
    const sea = row.sea
    if (board.seaBite && sea?.refusal) {
      // THE ONE WORDING of a closed sea (components/ui/seaWallWords.ts): the sea, what it asks that she does not hold,
      // what to do. The callers close the sentence, so the last stop is left off here.
      const wall = seaWallOf(sea.refusal)
      if (wall) return seaWallWords(getLocale(), wall).replace(/[.]$/, '')
      return seaAsksWords(sea)
    }
    // 0231: her navigation would reach it, her stores would not: the server's E_ENDURANCE figures, in plain words
    const shut = row.shut?.figures
    if (row.shut?.code === 'E_ENDURANCE' && shut) {
      const pair = daysPair(shut.carry_days, shut.need_days)
      // 0238 (owner, Port Royal): the crossing is on the way to the city it is bought at — name that city
      // 0345 (owner row 221): lit, the stores have their own space, so it is the stores that are short, not the hold
      const words = t(shut.stores_space ? 'desk.storesShort' : 'desk.holdTooFull', { pair })
      return shut.buy_at ? t('desk.viaCity', { words, city: shut.buy_at_name ?? shut.buy_at }) : words
    }
    const own =
      t('desk.far') +
      (board.reachNm !== null ? t('desk.navigatorOnly', { leg: legWords(board.reachNm, board.speedKn) }) : '')
    const n = row.needs
    if (n && n.navigation !== null) return t('desk.captainCould', { own, n: n.navigation })
    if (n) return t('desk.noCaptain', { own })
    return own
  }
  if (row.longest_leg && row.longest_leg.days > 0) {
    return board.supplyDays !== null
      ? t('desk.storesShort', { pair: daysPair(board.supplyDays, row.longest_leg.days) })
      : t('desk.longerThan', { leg: formatVoyageDays(row.longest_leg.days) })
  }
  return t('desk.orSupplies')
}
