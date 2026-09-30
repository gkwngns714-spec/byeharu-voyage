// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PRESS IN FLIGHT — the one gate a control may wear while its own verb is on the wire.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE RULE (the owner, 2026-09-30: *"i see multiple cases where a bar (Start route in command for
// example) blinks occasionally on its own"*): A BACKGROUND WORLD READ NEVER DISABLES OR RESTYLES A
// CONTROL. ONLY THE PRESS ITSELF DOES.
//
// Until that day COMMAND's Start route, the route fold's buttons, every queue ✕ and Clear wore
// `disabled={busy}`, where `busy` was the world store's in-flight flag for `refresh()` — and the
// shell calls `refresh()` on its own every few seconds (AppShell.tsx, READ_MIN_MS). So every beat
// greyed every one of those buttons to `disabled:opacity-45` and back (A2 adds
// tests/flicker.spec.ts, which counts the flips). The flag answered "is the world being read?"; the buttons wanted
// "is MY press still going?". This hook is the second question, asked once.
//
// ONE INSTANCE PER GROUP OF CONTROLS THAT ACT ON THE SAME THING — the queue (every ✕ and Clear),
// a route fold, an editor — never one per button: a CANCEL addresses its order by `seq` and a
// press awaits the world read that renumbers them, so while ONE press of the group is on the wire
// no other press of the group may be taken on a stale reading. A press made while one is pending
// is dropped, not queued.
//
// `pending` is state, so the group re-renders twice per press (on and off) and never on the beat.
// A press that resolves after its component unmounted writes nothing.

import { useCallback, useEffect, useRef, useState } from 'react'

export interface Press {
  /** True from the moment `run` is called until its act settles. Wire it to `<Button busy>`. */
  pending: boolean
  /** Run one press. Dropped while another press of this group is pending. A store verb resolves
   *  and never rejects (worldStore.ts rule 2); should an act reject anyway, the rejection reaches
   *  the caller and `pending` is cleared either way. */
  run: (act: () => Promise<unknown>) => Promise<void>
}

export function usePress(): Press {
  const [pending, setPending] = useState(false)
  // The ref is the gate; the state only draws it. Two presses in one frame both read the ref.
  const inFlight = useRef(false)
  const mounted = useRef(true)
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])

  const run = useCallback(async (act: () => Promise<unknown>) => {
    if (inFlight.current) return
    inFlight.current = true
    setPending(true)
    try {
      await act()
    } finally {
      inFlight.current = false
      if (mounted.current) setPending(false)
    }
  }, [])

  return { pending, run }
}
