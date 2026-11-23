import { useCallback, useState } from 'react'
import { useShellState } from '../app/shellState'
import { useReaskAtEdge } from '../components/ui'
import { worldHqBoard, type HqBoardView } from '../lib/rpc'
import { msUntilEdge } from '../store/resourceCache'
import { useServedRead, type ServedRead } from './useServedRead'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HQ BOARD, SERVED (0480, docs/design/hq-command-2026-11-23.md v2) — world.hq_board(): every move open to her now, ranked by the
// server, each naming the command that commits it. ONE READ, asked when HQ opens, when one of her fleets acts (a new version is a new
// question) and at the MARKET'S EDGE (the served clock, as the desk's best_sales), never on the beat: it prices her idle fleets with
// world.best_sales, the desk's own costly read.
// Dark (hq_board_enabled false) it answers {on: false} after one knob read, kept a minute, and the board ranks v1's own.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How long a dark answer is kept: the switch is the owner's, thrown rarely. */
const DARK_MS = 60_000

/**
 * @param company  her company's id (the subject), or null while none is read
 * @param question what moves the answer besides the market: her fleets' ids and versions
 */
export function useHqBoard(company: string | null, question: string | null): ServedRead<HqBoardView> {
  const { nowMs } = useShellState()
  const [edges, setEdges] = useState(0)
  const read = useServedRead<HqBoardView>(company, () => worldHqBoard(), {
    question: company !== null && question !== null ? `${company}:${question}` : null,
    trigger: edges,
    name: 'hq_board',
    freshMs: (v: HqBoardView) => (v.on && v.company ? msUntilEdge(v.clock) : DARK_MS),
  })
  const lit = read.view && read.view.on && read.view.company ? read.view : null
  useReaskAtEdge(
    lit ? Date.parse(lit.clock.next_change_at) : null,
    lit ? Date.parse(lit.clock.now) : null,
    nowMs,
    useCallback(() => setEdges((n) => n + 1), []),
  )
  return read
}
