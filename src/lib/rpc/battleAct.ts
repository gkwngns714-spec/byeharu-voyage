import { call } from './backend'
import type { RpcResult } from './result'
import type { TickAbilityCode, TickTimeline } from './types'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HER SIDE'S COMMANDER ACTS (0439; docs/design/tick-combat.md sections 4, 7 and the contract, 9.2).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The battle screen's action bar (src/live/battle/BattleScreen.tsx) presses one of the eight abilities for her own fleet
// at the next tick. The server is the judge: it lands the act at the next tick at the earliest (later if her side's
// global cooldown says so), judges the cooldown and the Fury against the current timeline at that tick, re-runs the
// fight (the past is the same by construction) and answers the new timeline, which the screen swaps in at the same tick.
// Kept in its own file, as battleJoin.ts, so the screen's other wrappers never share a hunk with it.

/** Every refusal `cmd.battle_act` answers (contract 9.2; E_TOO_SOON is the spam cap: one act a fleet every gcd ticks). */
export const BATTLE_ACT_REFUSALS = [
  'E_NO_BATTLE',
  'E_BATTLE_OVER',
  'E_NOT_YOUR_BATTLE',
  'E_COOLDOWN',
  'E_NO_FURY',
  'E_PAST_TICK',
  'E_BAD_CODE',
  'E_TOO_SOON',
] as const
export type BattleActRefusal = (typeof BATTLE_ACT_REFUSALS)[number]

/** `cmd.battle_act`'s receipt: the tick it landed on, the timeline's new version and the timeline itself. */
export interface BattleActReceipt {
  battle: string
  tick: number
  k: number
  resolves_at: string
  ticks?: TickTimeline | null
}

/** Her fleet's side uses an ability at a tick (the next one at the earliest) (0439). */
export function cmdBattleAct(battleId: string, fleetId: string, code: TickAbilityCode, tick: number): Promise<RpcResult<BattleActReceipt>> {
  return call<BattleActReceipt>('cmdBattleAct', [battleId, fleetId, code, tick])
}
