import { passageAsk, passageOf, sailLegs, shutByReach, type PassagePlan } from '../domain/passage'
import type { SeaNav } from '../lib/sea'
import { worldRouteLegs, worldTripCost, type FleetView, type SnapshotPort } from '../lib/rpc'

// THE PASSAGE PLANNER'S ONE CALLER OF THE SERVER (domain/passage/chain.ts carries the rule and the owner's words).
//
//   1. the one leg, from where she is to the city, is asked of world.route_legs (0346). Open: that is the plan.
//   2. shut by its length or its stores, with harbours between served (`via`, voyage.reach_passage): the legs through
//      them are proposed by the one course author and asked again, every one judged by the server (voyage.leg_refusal).
//      All open: that is the plan, with its days and its supplies added up. One shut: the plan is shut at that leg.
//   3. shut with no harbours between: shut, and `noStops` says there is no port to stop at.
//   4. an open plan is priced: world.trip_cost (0360) is asked of its legs for the whole time and the three costs.
//
// Null when the server did not answer (a fault, or a fleet not the caller's): the caller keeps the verdict it had.
// A read only: nothing is queued here. The send is the one plan path's (`worldStore.issueLines` → cmd.issue_lines),
// which asks the passage gate of every SAIL again before any is queued; each SAIL is still the server's to refuse.

export async function planPassage(
  fleet: FleetView,
  dest: string,
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
): Promise<PassagePlan | null> {
  const direct = sailLegs(fleet, nav, portByCode, [dest])
  if (direct.length !== 1) return { kind: 'shut', from: null, to: dest, refusal: null, noStops: false }
  const first = await worldRouteLegs(fleet.id, passageAsk(direct))
  if (!first.ok || !first.value) return null
  const plan = passageOf(direct, first.value.legs)
  const via = first.value.legs[0]?.via ?? null
  if (plan?.kind === 'open') return priced(fleet, plan)
  if (!plan || !shutByReach(plan.refusal?.code) || !via || via.length === 0) return plan

  const chain = sailLegs(fleet, nav, portByCode, [...via, dest])
  if (chain.length !== via.length + 1) {
    return { kind: 'shut', from: chain[chain.length - 1]?.to ?? direct[0].from, to: [...via, dest][chain.length], refusal: null, noStops: false }
  }
  const second = await worldRouteLegs(fleet.id, passageAsk(chain))
  if (!second.ok || !second.value) return null
  const through = passageOf(chain, second.value.legs)
  return through?.kind === 'open' ? priced(fleet, through) : through
}

/** THE WHOLE TRIP'S TIME AND PRICE (0360, world.trip_cost) laid on an open plan: the calls on the way are in its days, and
 *  supplies, wages and dock fees are each their own figure. A world without that read answers nothing: the plan stands
 *  as the legs' own figures made it. THE ONE CALLER: the Map's row and the Trade panel's days both read `plan.trip`. */
async function priced(fleet: FleetView, plan: Extract<PassagePlan, { kind: 'open' }>): Promise<PassagePlan> {
  const cost = await worldTripCost(fleet.id, passageAsk(plan.legs))
  return cost.ok && cost.value && cost.value.legs.length === plan.legs.length ? { ...plan, trip: cost.value } : plan
}
