// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A VALUE THAT HAS RESTED — the one settle timer, for every line the server is asked to dry-run.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A DRY RUN IS A REAL WRITE, ROLLED BACK (`cmd.preview`), and a stepper's slider reports every
// step of a drag, so an un-debounced ask turned a 50-step drag into 50 round-trips. The cure is a
// COPY of the value that only follows it once it has stood still for `ms` — and only the settled
// copy is a subject for `useServedRead`.
//
// Until 2026-09-14 that cure was written twice: `useTrade.ts` kept a `settled` state behind its
// own `PREVIEW_SETTLE_MS`, and `useOrderPreview.ts` kept a second `PREVIEW_SETTLE_MS` with a
// `setTimeout` inside its ask effect. Two timers, two constants, one rule — the shape
// docs/NO_SPAGHETTI.md forbids. This is the one, and the constant is exported from here only.

import { useEffect, useState } from 'react'

/** How long a chosen quantity must stand still before the server is asked to price it. Long
 *  enough that a slider drag is one ask; short enough that a tap on + reads as immediate. */
export const PREVIEW_SETTLE_MS = 200

/** A copy of `value` that follows it once it has rested `ms`. Starts equal to it. */
export function useSettled<T>(value: T, ms: number = PREVIEW_SETTLE_MS): T {
  const [settled, setSettled] = useState(value)
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), ms)
    return () => clearTimeout(timer)
  }, [value, ms])
  return settled
}
