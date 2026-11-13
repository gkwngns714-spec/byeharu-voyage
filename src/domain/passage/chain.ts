// A PASSAGE THROUGH THE HARBOURS BETWEEN — the one reading of "can she get there, how long, what does it cost".
//
// THE OWNER, 2026-11-13: *"when moving to a city, anywhere, far away, it says navigation restriction. i want the game to
// calculate which cities to cross automatically, and just tell me the final time, price reaching the destination when
// pressed send fleet."*
//
// NOT A SECOND AUTHORITY. Her navigation still bounds every leg (the owner's standing rule), and nothing here measures a
// reach, a sea or a store:
//   the harbours between   the SERVER's — `via` on a shut leg of world.route_legs (0346), which is voyage.reach_passage,
//                          the one pathfinder: the fewest sailed miles with every leg within her navigation and her
//                          stores, and of two equal ways the one with fewer calls (so the least time; a tie goes to
//                          the cheaper)
//   the courses            the one course author's (`sailLegs`, as a plan's and the route builder's)
//   open or shut           the SERVER's — voyage.leg_refusal, asked of every leg of the chain before it is offered
//   the time and the price the SERVER's — world.trip_cost (0360), asked of the legs it called open: the sailing of every leg
//                          AND the real time she lies at each harbour between; supplies (her casks walked along the
//                          trip), wages and the dock fee of every call, each its own figure, and their total. Before
//                          0360 is in a world the read is missing: `trip` is null and the row falls back to the legs'
//                          own days and supplies (world.route_legs), added up in `passageOf`
//
// Pure: no React, no store, no call. `live/passagePlan.ts` asks the server; the Map's place tray prints the answer.

import { seaWallOf, type PlanLine, type RouteLeg, type RouteLegAsk, type SeaWall, type ServedRefusal, type TripCost } from '../../lib/rpc'
import type { PlanLeg } from './legs'

export type PassagePlan =
  | {
      kind: 'open'
      /** The harbours she calls at on the way, in order; none when one leg reaches it. */
      stops: readonly string[]
      /** One SAIL each: the stops, then the city. */
      legs: readonly PlanLeg[]
      /** Days at sea over every leg (the server's figures, summed). */
      days: number
      /** What the supplies for every leg cost her as her hold stands now (the server's figures, summed). */
      cost: number
      /** THE WHOLE TRIP'S TIME AND PRICE as world.trip_cost serves them (0360); null where that read is not answered. */
      trip: TripCost | null
    }
  | {
      kind: 'shut'
      /** The leg that stops her: the whole way when no harbour between opens it, else the leg of the chain. */
      from: string | null
      to: string
      /** The server's reason; null when no water joins the two. */
      refusal: ServedRefusal | null
      /** Too far or past her stores in one go, and the server names no harbours between. */
      noStops: boolean
      /** A SEA CLOSED TO HER is what stops it (the server's own figures, lib/rpc/seaWall.ts): the leg that is shut is
       *  shut by a sea, or it is too far in one go and the sea on the direct course is why no harbours between open it
       *  (world.route_legs `sea`, 0376). Null when the sea is not the reason. */
      sea: SeaWall | null
    }

/** The codes of a leg shut by its LENGTH or its STORES: the two a call on the way can open (0346 serves `via` for them). */
export function shutByReach(code: string | null | undefined): boolean {
  return code === 'E_LEG_TOO_FAR' || code === 'E_ENDURANCE'
}

/** The legs as world.route_legs is asked them. */
export function passageAsk(legs: readonly PlanLeg[]): RouteLegAsk[] {
  return legs.map((l) => ({ from: l.from, to: l.to, course: l.path }))
}

/** The server's answer over the proposed legs, read as a plan: open with its totals, or shut at its first shut leg. */
export function passageOf(legs: readonly PlanLeg[], served: readonly RouteLeg[]): PassagePlan | null {
  if (legs.length === 0 || served.length !== legs.length) return null
  const shut = served.findIndex((s) => s.shut !== null)
  if (shut >= 0) {
    const s = served[shut]
    const noStops = legs.length === 1 && shutByReach(s.shut?.code) && !(s.via && s.via.length > 0)
    return { kind: 'shut', from: legs[shut].from, to: legs[shut].to, refusal: s.shut, noStops, sea: seaWallOf(s.shut) ?? (noStops ? seaWallOf(s.sea) : null) }
  }
  let days = 0
  let cost = 0
  for (const s of served) {
    if (s.days === null) return null
    days += s.days
    cost += s.supplies?.cost ?? 0
  }
  return { kind: 'open', stops: legs.slice(0, -1).map((l) => l.to), legs, days, cost, trip: null }
}

/** The plan as the grammar's lines: one SAIL a leg, each with its proposed course (cmd.issue_lines queues all or none). */
export function passageLines(plan: Extract<PassagePlan, { kind: 'open' }>): PlanLine[] {
  return plan.legs.map((l) => ({ text: `SAIL ${l.to}`, path: l.path }))
}
