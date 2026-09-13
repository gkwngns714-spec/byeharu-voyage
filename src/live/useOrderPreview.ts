// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE ORDER LINE, DRY-RUN — what `cmd.preview()` says THIS exact line would do, re-asked on the
// world's beat and only after the finger has rested.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE CONCEPT (docs/NO_SPAGHETTI.md §7B) ──────────────────────────────────────────────────────
// "The server's answer for the line a button is about to issue." A tray that prints a figure for a
// chosen quantity may print only what the server computed for THAT quantity — never a client
// multiplication — so every stepper that issues a line needs the same three things: the line
// previewed, the answer keyed to the line so a stale one is never shown, and a settle delay so a
// slider drag is one ask rather than fifty (`cmd.preview` is a REAL write, rolled back).
//
// ── WHERE IT LIVES, AND WHO THE SECOND CALLER IS ──────────────────────────────────────────────
// `src/live/` — it is the one copy of what the server last said about a line, which is what this
// layer is for (docs/SECTIONS.md). Its FIRST caller is the Storage face (PortStorage.tsx: STORE /
// TAKE of a chosen count, owner row 88). Its SECOND caller is `useTrade.ts`, which carries this
// exact mechanism inline today (the `previewKey` / `PREVIEW_SETTLE_MS` block) for BUY / SELL —
// that is a second copy of one rule, and it is named here rather than left to be found: when the
// slice that owns useTrade.ts lands, that block composes this hook and the copy is deleted. Until
// then this file is the one that says what the rule IS, and the settle delay is spelt once here.
//
// ── WHAT IT RETURNS, AND WHAT IT DELIBERATELY DOES NOT ─────────────────────────────────────────
// The verb-shaped `estimate` as served — its READING belongs to `src/domain/order` (`saleEstimate`,
// `moveEstimate`), never here. A refusal is returned rather than swallowed: a dry run that refuses
// is the server saying the button would refuse too, and a tray may say so before the press.
// A queueable line (the fleet is at sea) carries no estimate and no refusal: nothing was run.

import { useEffect, useState } from 'react'
import { cmdPreview } from '../lib/rpc'
import type { Refusal } from '../lib/rpc'
import { useWorld } from './worldStore'

/** How long a chosen quantity must stand still before the server is asked to price it. Long
 *  enough that a slider drag is one ask; short enough that a tap on + reads as immediate. */
export const PREVIEW_SETTLE_MS = 200

export interface OrderPreview {
  /** The verb's own estimate for this exact line, or null while none is known for it. */
  estimate: Record<string, unknown> | null
  /** The server's refusal of the dry run, or null when it did not refuse (or has not answered). */
  refusal: Refusal | null
  /** True while the answer for THIS line is still on the wire. */
  loading: boolean
}

const NOTHING: OrderPreview = { estimate: null, refusal: null, loading: false }

/**
 * @param fleetId whose order it is — `cmd.preview`'s own argument, exactly as `cmd.issue`'s.
 * @param line    the exact text the button will issue (composed by `orderText`), or null for
 *                "nothing to preview" — no pick, or a quantity of nought.
 */
export function useOrderPreview(fleetId: string, line: string | null): OrderPreview {
  // Re-asked whenever the world is read again: a preview from before a trade landed is a preview
  // of a world that no longer exists.
  const readAt = useWorld((s) => s.readAt) ?? 0
  const key = line !== null ? `${fleetId}:${line}:${readAt}` : null

  const [answer, setAnswer] = useState<{ key: string; preview: OrderPreview } | null>(null)

  useEffect(() => {
    if (key === null || line === null) return
    let live = true
    const timer = setTimeout(() => {
      void cmdPreview(fleetId, line, null).then((r) => {
        if (!live) return
        setAnswer({
          key,
          preview: r.ok
            ? { estimate: r.value.estimate ?? null, refusal: null, loading: false }
            : { estimate: null, refusal: r.refusal, loading: false },
        })
      })
    }, PREVIEW_SETTLE_MS)
    return () => {
      live = false
      clearTimeout(timer)
    }
  }, [key, fleetId, line])

  if (key === null) return NOTHING
  if (answer === null || answer.key !== key) return { estimate: null, refusal: null, loading: true }
  return answer.preview
}
