import { useState } from 'react'
import { worldRoundQuote, worldRounds, type RoundRun, type RoundTerms, type RoundsView } from '../lib/rpc'
import { useJobEdits } from './useAwayReport'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// THE ROUNDS, SERVED (0518 to 0534, docs/design/rounds-2026-11-25.md). One read a surface that opens (world.rounds), and one quote when she picks a work and a
// sea (world.round_quote). NO FIGURE IS WORKED OUT HERE: a round's cost, the runs, the log and what she has in hand are drawn as served. Dark: {on: false}, and
// nothing of it is drawn.

export type LitRounds = Extract<RoundsView, { company: true }>

export function litRounds(v: RoundsView | null): LitRounds | null {
  return v && v.on && v.company ? v : null
}

/** world.rounds, asked once when the surface opens (and again after a press of hers: a fleet's new version, a job set). `fleet`: one of hers, whose
 *  works and seas are served too; null: the runs alone. `ask` false: nothing to ask. */
export function useRounds(fleet: string | null, ask = true): ServedRead<RoundsView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const versions = useWorld((s) => s.fleets.map((f) => `${f.id}.${f.version}`).join(','))
  const edits = useJobEdits((s) => s.edits)
  return useServedRead<RoundsView>(ask && company !== null ? `${company}:${fleet ?? '-'}` : null, () => worldRounds(fleet), {
    question: ask && company !== null ? `${company}:${fleet ?? '-'}:${edits}:${versions}` : null,
    trigger: 0,
    name: 'rounds',
    freshMs: 60_000,
  })
}

/** What a round of `work` costs her from `base` (asked when either is picked; once a pair). */
export function useRoundQuote(fleet: string, work: string | null, base: string | null): ServedRead<{ on: boolean; terms?: RoundTerms | null }> {
  // frozen for the sheet's life: her stores do not move while it stands
  const [at] = useState(() => useWorld.getState().fleets.find((f) => f.id === fleet)?.version ?? 0)
  const key = work !== null && base !== null ? `${fleet}:${work}:${base}` : null
  return useServedRead(fleet, () => worldRoundQuote(fleet, work ?? '', base ?? '', {}), {
    question: key === null ? null : `${key}:${at}`,
    trigger: 0,
    name: 'roundQuote',
    freshMs: 60_000,
  })
}

/** Her run, or null: she was never sent. */
export const runOf = (v: LitRounds | null, fleet: string): RoundRun | null => v?.runs.find((r) => r.fleet === fleet) ?? null

/** A run's salvage, as served in what it has in hand. */
export function salvageOf(run: RoundRun): { good: string; qty: number }[] {
  const s = run.carry['salvage']
  return s && typeof s === 'object' ? Object.entries(s as Record<string, number>).map(([good, qty]) => ({ good, qty: Number(qty) })) : []
}

/** A served number in what the run has in hand (gold, rp, won, gold_due), or null. */
export const carried = (run: RoundRun, key: 'gold' | 'rp' | 'won' | 'gold_due'): number | null => (typeof run.carry[key] === 'number' ? (run.carry[key] as number) : null)
