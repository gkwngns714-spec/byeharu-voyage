import { num, str } from '../lib/json'
import type { LedgerEvent } from '../lib/rpc'

// THE BOUNTY A FIGHT PAID (0471), read off the battle's own BATTLE_REPORT: `payload.bounty` ({name, epithet, given, home, paid, value}),
// written by public.bounty_close under the battle's lock and carried by the report of the company that beat her. The one reader, for the
// fight cards and the arrival card. Pure (a spec reads it in Node). Null: no bounty on this report, or nothing paid.

export interface PaidBounty {
  battle: string | null
  paid: number
  epithet: string
  given: string
  home: string | null
}

export function bountyOf(event: LedgerEvent): PaidBounty | null {
  if (event.kind !== 'BATTLE_REPORT') return null
  const b = (event.payload as Record<string, unknown> | undefined)?.bounty
  if (b === null || typeof b !== 'object') return null
  const o = b as Record<string, unknown>
  const paid = num(o, 'paid')
  const epithet = str(o, 'epithet')
  const given = str(o, 'given')
  if (paid === null || paid <= 0 || epithet === null || given === null) return null
  return { battle: str(event.payload as Record<string, unknown>, 'battle_id'), paid, epithet, given, home: str(o, 'home') }
}

/** The bounty a given battle paid, among these events; null when none. */
export function bountyOfBattle(events: readonly LedgerEvent[], battleId: string | null | undefined): PaidBounty | null {
  if (!battleId) return null
  for (const e of events) {
    const b = bountyOf(e)
    if (b && b.battle === battleId) return b
  }
  return null
}
