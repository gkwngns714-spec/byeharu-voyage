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
// ── A DOORWAY ONTO useServedRead AND useSettled (2026-09-14) ───────────────────────────────────
// `src/live/` — it is the one copy of what the server last said about a line, which is what this
// layer is for (docs/SECTIONS.md). Its caller is the Storage face (PortStorage.tsx: STORE / TAKE of
// a chosen count, owner row 88). Until 2026-09-14 it carried its own copy of the whole mechanism:
// an answer keyed on (fleet, line, readAt) that was thrown away every time the world was read —
// every 3 s (AppShell.tsx, READ_MIN_MS) the estimate and the refusal went blank and `loading`
// went true until the re-ask landed — and a second `PREVIEW_SETTLE_MS` with its own `setTimeout`.
// That is the same disease `useBuyCapacity` had the same day (the owner: *"when i press buy, the
// max keeps refreshing"*), so both are one thing now: the SUBJECT is (fleet, the SETTLED line), a
// re-read of the same subject keeps the last answer and marks it `loading`, a new line shows
// nothing of the old one, and the settle is `useSettled` — the one timer.
//
// ── WHAT IT RETURNS, AND WHAT IT DELIBERATELY DOES NOT ─────────────────────────────────────────
// The verb-shaped `estimate` as served — its READING belongs to `src/domain/order` (`saleEstimate`,
// `moveEstimate`), never here. A refusal is returned rather than swallowed: a dry run that refuses
// is the server saying the button would refuse too, and a tray may say so before the press. Both
// outcomes are folded into ONE served value and handed to useServedRead as `ok`, exactly as
// useManifestPreview does — a refusal is the answer here, not the absence of one.
// A queueable line (the fleet is at sea) carries no estimate and no refusal: nothing was run.

import { cmdPreview, ok } from '../lib/rpc'
import type { Refusal } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useSettled } from './useSettled'

export interface OrderPreview {
  /** The verb's own estimate for this exact line, or null while none is known for it. */
  estimate: Record<string, unknown> | null
  /** The server's refusal of the dry run, or null when it did not refuse (or has not answered). */
  refusal: Refusal | null
  /** True while the answer for THIS line is still on the wire. */
  loading: boolean
}

const NOTHING: OrderPreview = { estimate: null, refusal: null, loading: false }
const WAITING: OrderPreview = { estimate: null, refusal: null, loading: true }

/** What the server said about one line: an estimate, or a refusal. */
interface Priced {
  estimate: Record<string, unknown> | null
  refusal: Refusal | null
}

/**
 * @param fleetId whose order it is — `cmd.preview`'s own argument, exactly as `cmd.issue`'s.
 * @param line    the exact text the button will issue (composed by `orderText`), or null for
 *                "nothing to preview" — no pick, or a quantity of nought.
 */
export function useOrderPreview(fleetId: string, line: string | null): OrderPreview {
  // Only a line that has stood still is asked: the stepper's slider reports every step of a drag.
  const settled = useSettled(line)
  // A line that has gone (the tray closed) is not asked for, even while the settled copy lags.
  const subject = line !== null && settled !== null ? `${fleetId}:${settled}` : null
  const read = useServedRead<Priced>(subject, async () => {
    const r = await cmdPreview(fleetId, settled as string, null)
    return ok<Priced>(
      r.ok ? { estimate: r.value.estimate ?? null, refusal: null } : { estimate: null, refusal: r.refusal },
    )
  })

  if (line === null) return NOTHING
  // Exposed only while the settled line IS the button's: the figure printed is always the figure
  // for the quantity chosen.
  if (settled !== line) return WAITING
  return { estimate: read.view?.estimate ?? null, refusal: read.view?.refusal ?? null, loading: read.loading }
}
