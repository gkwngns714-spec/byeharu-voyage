import { num, str } from '../lib/json'
import type { LedgerEvent } from '../lib/rpc'

// 0477 (roadmap 2026-11-23 slice 7): an EARLY_SIGHTING event (public.early_sighting_close) as the arrival card reads it. Nothing is computed:
// the server's pirate and end, the loss (the ransom that left her purse), what the insurer paid back or would have, and the same fight's
// end with her hulls armed like the pirate's when she had no guns.

export interface Sighting {
  id: string
  fleet: string | null
  pirate: string
  outcome: string
  lost: number
  insured: boolean
  paid: number
  back: number
  guns: boolean
  gunsOutcome: string | null
}

/** An EARLY_SIGHTING event's lines; null for any other event. */
export function sightingOf(e: LedgerEvent): Sighting | null {
  if (e.kind !== 'EARLY_SIGHTING') return null
  const p = e.payload
  return {
    id: e.id,
    fleet: str(p, 'fleet'),
    pirate: str(p, 'pirate') ?? '',
    outcome: str(p, 'outcome') ?? 'NO_FIGHT',
    lost: num(p, 'lost') ?? 0,
    insured: p?.insured === true,
    paid: num(p, 'insurance_paid') ?? 0,
    back: num(p, 'insurance_back') ?? 0,
    guns: p?.guns === true,
    gunsOutcome: str(p, 'guns_outcome'),
  }
}
