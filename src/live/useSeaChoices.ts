import { create } from 'zustand'
import { useShellState } from '../app/shellState'
import { cmdSeaChoose, worldSeaChoices, type Refusal, type SeaChoicesView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CHOICES AT SEA (0486, docs/design/roadmap-2026-11-23.md slice 16) — world.sea_choices(): her open choices (a storm, a wreck or a strange
// sail met on a long trip: the options, their odds and coin, the best by expected coin, her pick, the deadline) and the lately settled ones
// with their ends. ONE READ, shared by HQ's decision card and While away: asked when HQ opens, when one of her fleets acts (a new
// version), after a press here, and once a minute while a trip of hers is under way (an event is shown at a quarter of the trip); never on
// the beat. Dark it answers {on: false} after one knob read, kept a minute.
// The one door (cmd.sea_choose) goes through this file, so a press re-asks the read and its refusal stands where it was pressed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DARK_MS = 60_000
const LIT_MS = 60_000

interface SeaPicks {
  /** Moves on every committed press, so the read is asked again. */
  edits: number
  /** The choice whose press is on the wire. */
  pending: string | null
  /** The server's refusal, by choice. */
  refused: Record<string, Refusal>
  start: (key: string) => void
  done: (key: string, refusal: Refusal | null) => void
}

export const useSeaPicks = create<SeaPicks>()((set) => ({
  edits: 0,
  pending: null,
  refused: {},
  start: (key) => set({ pending: key }),
  done: (key, refusal) =>
    set((s) => {
      const refused = { ...s.refused }
      if (refusal) refused[key] = refusal
      else delete refused[key]
      return { pending: null, refused, edits: refusal ? s.edits : s.edits + 1 }
    }),
}))

/** Her pick of a choice's options. Null when it committed; else the server's refusal. */
export async function chooseAtSea(choiceId: string, option: string): Promise<Refusal | null> {
  const s = useSeaPicks.getState()
  if (s.pending !== null) return null
  s.start(choiceId)
  const done = await cmdSeaChoose(choiceId, option)
  const refusal = done.ok ? null : done.refusal
  useSeaPicks.getState().done(choiceId, refusal)
  return refusal
}

/** The read, lit for her company; else null (dark, signed out, a merchant, unread). */
export function litSea(v: SeaChoicesView | null): Extract<SeaChoicesView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

export function useSeaChoices(): ServedRead<SeaChoicesView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const edits = useSeaPicks((s) => s.edits)
  // a trip under way is asked again each minute (its event is shown a quarter of the way out); otherwise only when a fleet acts
  const sailing = fleets.some((f) => f.voyage != null)
  const { nowMs } = useShellState()
  const minute = sailing ? Math.floor(nowMs / 60_000) : 0
  const question = company === null ? null : `${company}:${edits}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
  return useServedRead<SeaChoicesView>(company, () => worldSeaChoices(), {
    question,
    trigger: minute,
    name: 'sea_choices',
    freshMs: (v: SeaChoicesView) => (v.on && v.company ? LIT_MS : DARK_MS),
  })
}
