import { worldSeaConditions, type SeaConditions } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

// THE SEA CONDITIONS, AS SERVED (0215 `world.sea_conditions()`): the zones and what each asks, the caller's
// title, each fleet's wave resistance, and whether the conditions bite yet. The client prints these and derives
// none of them (docs/SEA_CONDITIONS_AND_REGIONS.md §1: the rule is `public.sea_refusal`, written once, on the
// server). Asked ONCE per mount — `trigger` is a constant, so it does not ride the world's 3-s beat: the zones
// are world data, and a title or a fleet's wave changes on a trade or a refit, not between two beats.

export function useSeaConditions(): ServedRead<SeaConditions> {
  return useServedRead('sea-conditions', () => worldSeaConditions(), { trigger: 0 })
}
