import { useCallback, useEffect, useState } from 'react'
import { create } from 'zustand'
import { useShellState } from '../app/shellState'
import { useReaskAtEdge } from '../components/ui'
import { worldActions, worldWorkers, type WorkerActionsView, type WorkersView } from '../lib/rpc'
import { useJobEdits } from './useAwayReport'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORKERS AND THEIR ACTIONS, SERVED (0496, docs/design/hq-corp-2026-11-24.md A2.1, B3, C1, C3)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// world.workers()        HQ's one list of who does what: each fleet and the land party, her action in the one shape, her state, the two
//                        served stamps of her bar, and coin and experience an hour. It asks no quote.
// world.actions(worker)  one worker's options for the Assign sheet, each in the same shape, only what the server would take. It PRICES.
//
// HOW OFTEN (the server's own `ask_s`, read from each answer):
//   workers   when HQ opens, once after a command of hers (a fleet's new version, a job set or cleared, the party sent or called) and
//             once when a served stamp passes; a kept answer is good for `ask_s` (60 s). Never on the beat.
//   actions   ONCE WHEN THE ASSIGN SHEET OPENS. The question is frozen when the sheet mounts, so nothing re-asks it while it stands;
//             a kept answer for the same worker as she then stood is good for `ask_s` (300 s). Never on a timer, but for one answer: the
//             server's `closed` E_SLOW ("ask again in a moment") is asked again by itself, at most three times (QUIET_MS).
// NO FIGURE IS WORKED OUT IN THE CLIENT: a rate, a run's units, its cost and its time are drawn as served.

/** How long an answer that is not a company's is kept. */
const NONE_MS = 60_000

/** How long after an E_SLOW answer the sheet asks again by itself, one wait a try; past the last the sheet says so (Try again). */
const QUIET_MS = [2_000, 5_000, 10_000]

/** A command of hers that moves no fleet's version (the party sent or called home): it asks the list again. */
export const useWorkEdits = create<{ edits: number; touch: () => void }>()((set) => ({ edits: 0, touch: () => set((s) => ({ edits: s.edits + 1 })) }))

export type LitWorkers = Extract<WorkersView, { company: true }>
export type LitActions = Extract<WorkerActionsView, { company: true }>

export function litWorkers(v: WorkersView | null): LitWorkers | null {
  return v && v.company ? v : null
}

export function litActions(v: WorkerActionsView | null): LitActions | null {
  return v && v.company ? v : null
}

/** What moves the list besides the clock: her fleets' versions and her own presses. */
function useMoved(): string | null {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const jobs = useJobEdits((s) => s.edits)
  const work = useWorkEdits((s) => s.edits)
  return company === null ? null : `${company}:${jobs}:${work}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
}

export function useWorkersRead(): ServedRead<WorkersView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const question = useMoved()
  const { nowMs } = useShellState()
  const [edges, setEdges] = useState(0)
  const read = useServedRead<WorkersView>(company, () => worldWorkers(), {
    question,
    trigger: edges,
    name: 'workers',
    freshMs: (v: WorkersView) => (v.company ? v.ask_s * 1000 : NONE_MS),
  })
  // the next served stamp to pass (a voyage's arrival, the party's next trip home): the list is asked once when it does
  const lit = litWorkers(read.view)
  const servedAt = lit ? Date.parse(lit.now) : null
  let edge: number | null = null
  if (lit && servedAt !== null)
    for (const w of lit.workers) {
      const to = w.progress?.to ? Date.parse(w.progress.to) : NaN
      if (Number.isFinite(to) && to > servedAt && (edge === null || to < edge)) edge = to
    }
  useReaskAtEdge(
    edge,
    servedAt,
    nowMs,
    useCallback(() => setEdges((n) => n + 1), []),
  )
  return read
}

/** `worker`: the server's id (`fleet:<uuid>` | `party:<n>`), or null for nothing to ask. Asked once a mount (see the header), and once
 *  more when the read answered that it took too long (`closed` E_SLOW): by itself after each of QUIET_MS while the sheet stands, then
 *  each time SHE presses `again`. `tries` counts them all; `retrying`: an E_SLOW answer stands and it is being asked again by itself. */
export function useActionsRead(worker: string | null): ServedRead<WorkerActionsView> & { again: () => void; tries: number; retrying: boolean } {
  const moved = useMoved()
  // frozen at the sheet's opening: her fleet arriving, or a press, never re-asks a sheet that stands
  const [question] = useState(moved)
  const [tries, setTries] = useState(0)
  const read = useServedRead<WorkerActionsView>(worker, () => worldActions(worker ?? ''), {
    question: worker !== null && question !== null ? `${worker}:${question}:${tries}` : null,
    trigger: 0,
    name: 'actions',
    // a read that took too long is not kept: the next ask goes to the server
    freshMs: (v: WorkerActionsView) => (v.company ? (v.closed?.code === 'E_SLOW' ? 0 : v.ask_s * 1000) : NONE_MS),
  })
  const slow = read.view?.company === true && read.view.closed?.code === 'E_SLOW'
  const quiet = slow && !read.stale ? QUIET_MS[tries] : undefined
  useEffect(() => {
    if (quiet === undefined) return
    const id = setTimeout(() => setTries((n) => n + 1), quiet)
    return () => clearTimeout(id)
  }, [quiet])
  const retrying = slow && (tries < QUIET_MS.length || (tries === QUIET_MS.length && read.stale))
  return { ...read, tries, retrying, again: useCallback(() => setTries((n) => n + 1), []) }
}
