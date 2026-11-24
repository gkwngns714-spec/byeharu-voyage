import { useCallback, useState } from 'react'
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
//             a kept answer for the same worker as she then stood is good for `ask_s` (300 s). Never on a timer.
// NO FIGURE IS WORKED OUT IN THE CLIENT: a rate, a run's units, its cost and its time are drawn as served.

/** How long an answer that is not a company's is kept. */
const NONE_MS = 60_000

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

/** `worker`: the server's id (`fleet:<uuid>` | `party:<n>`), or null for nothing to ask. Asked once a mount (see the header). */
export function useActionsRead(worker: string | null): ServedRead<WorkerActionsView> {
  const moved = useMoved()
  // frozen at the sheet's opening: her fleet arriving, or a press, never re-asks a sheet that stands
  const [question] = useState(moved)
  return useServedRead<WorkerActionsView>(worker, () => worldActions(worker ?? ''), {
    question: worker !== null && question !== null ? `${worker}:${question}` : null,
    trigger: 0,
    name: 'actions',
    freshMs: (v: WorkerActionsView) => (v.company ? v.ask_s * 1000 : NONE_MS),
  })
}
