import { call } from './backend'
import type { RpcResult } from './result'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// JOINING A BATTLE (0436; docs/design/tick-combat.md section 8 and the contract, 9.2).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Joining is a CHOICE: a ship inside the red circle is never pulled in. Her player presses Join on the map's Join bar
// (src/features/battle/JoinBar.tsx) and picks a side. The server is the judge: a fleet that is not hers, out of reach,
// busy, at peace, a side against a player (no PvP) or the wrong side of a raid is refused with its code.
// Kept in its own file so the battle screen's wrappers (world.battle_ticks, cmd.battle_end) never share a hunk with it.

export type BattleSide = 'ATTACKER' | 'DEFENDER'

/** Every refusal `cmd.battle_join` answers (contract 9.2). */
export const BATTLE_JOIN_REFUSALS = [
  'E_NO_BATTLE',
  'E_BATTLE_OVER',
  'E_NOT_YOUR_FLEET',
  'E_NOT_IN_REACH',
  'E_BAD_SIDE',
  'E_HUMAN_TARGET',
  'E_FLEET_BUSY',
  'E_AT_PEACE',
] as const
export type BattleJoinRefusal = (typeof BATTLE_JOIN_REFUSALS)[number]

/** `cmd.battle_join`'s receipt: the battle, the side she joined, and the tick she comes up on the sheet. */
export interface BattleJoinReceipt {
  battle: string
  side: BattleSide
  from_tick: number
}

/** Her fleet joins a battle on one side (0436). */
export function cmdBattleJoin(battleId: string, fleetId: string, side: BattleSide): Promise<RpcResult<BattleJoinReceipt>> {
  return call<BattleJoinReceipt>('cmdBattleJoin', [battleId, fleetId, side])
}
