// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SERVED READ THAT RIDES THE WORLD'S BEAT — asked once per read, and KEEPS ITS ANSWER while the
// next one is on the wire.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Four port faces — the shed, the inn, the workstation, the yard — each ask the server a question
// about (this port, maybe this fleet), and each must ask AGAIN whenever the world is read again:
// a STORE moves cargo, a MAKE spends it, a HIRE changes who is offered. They were four copies of
// the same hook, and every copy had the same defect: on every world read it threw its answer away
// and reported `{view: null, loading: true}` until the new one arrived. The shell reads the world
// every 3 s on this clock (AppShell.tsx, READ_MIN_MS), so the Store went blank to "Asking the shed
// what it holds…" and repainted every 3 s — the owner, 2026-09-13: *"why is store keep
// refreshing?"* — and PortInn.tsx had already grown a workaround (its crew row mounted OUTSIDE
// the room, so the re-read would not unmount its tray). That is the disease NO_SPAGHETTI.md
// names: a defect in four places is fixed in one, and the other three keep it.
//
// ── THE RULE ───────────────────────────────────────────────────────────────────────────────────
// The SUBJECT (port, fleet) decides what an answer is FOR. A new read of the same subject keeps
// the last answer on screen and marks it `loading` until the fresh one lands; a new SUBJECT shows
// nothing of the old one — Dublin's shed is never drawn under Lisbon's heading.
//
// A refusal is an answer: it clears the view, because the server just said there is nothing to
// show (the fleet left, the city keeps no such house). A caller draws `view` when it has one, and
// its waiting line only when `loading && !view` — the first ask.
//
// `useHaggleState` joined the view reads in slice 3 (2026-09-13): its figures are a conversation's
// standing — tries left, the bargain held, the odds — and a thread that blanked on every 3-s beat
// was row 77's defect again; the thread shows `loading` on the re-ask and never a blank.
//
// THE CEILING'S EXEMPTION IS RETIRED (2026-09-14). This header used to say a CEILING read
// (useBuyCapacity) was "deliberately not this: a ceiling shown a beat late is the lie that hook was
// written to remove, so it still waits". That was wrong: the server re-checks the ceiling on
// `cmd.issue` anyway and its refusal is shown, while a ceiling that blanks to 0 every 3 s — the
// `Max` row unmounting and the stepper clamping to nought on every beat — is the worse lie. The
// owner, 2026-09-14: *"when i press buy, the max keeps refreshing."* The ceiling, the storage
// tray's dry run (useOrderPreview) are doorways onto this rule now; nothing in src/live keys its
// own answer on `readAt` any more. (The on-board sale estimate, `useSellEstimate`, was a third
// doorway until 2026-09-18, when the on-board figure became the per-unit gap of two served
// prices and the hook was deleted.)
//
// ONE MODE OF RE-ASKING. Every read asks again on the world's beat and keeps the last answer
// meanwhile — right for ONE open tray or face: the ceiling, a dry run, the shed. A second mode,
// `reask: 'subject'` (ask once per subject, never on the beat), was added 2026-09-14 for the
// on-board list's SELL-all estimate — a LIST of `cmd.preview` asks that must not ride the beat —
// and retired 2026-09-18 with that estimate (the on-board figure is now the gap of two prices
// already served; OnBoard.tsx). A list of served-write asks must not come back through this hook
// without that mode coming back with it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react'
import type { RpcResult } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface ServedRead<V> {
  /** The last answer for this subject, or null before the first one (or after a refusal). */
  view: V | null
  /** True while an ask is on the wire — the first one, a re-ask on the world's beat, or a new
   *  question. */
  loading: boolean
  /** True while `view` answers an EARLIER question than the one now asked — the figures on screen
   *  are this subject's, but not yet for what was just chosen. Always false when the question is
   *  the subject. A caller dims such a view; it never prints it as the answer to the new question. */
  stale: boolean
}

const IDLE = { view: null, loading: false, stale: false }
const WAITING = { view: null, loading: true, stale: false }

export interface ServedReadOptions {
  /** What is ASKED, when that is finer than the subject (2026-09-14): the trade tray's dry run
   *  is FOR (fleet, side, good) but asks about a QUANTITY, and the owner will not have the sale's
   *  figures blink on every press of + — so a new question re-asks and the last answer for the
   *  same subject stands, `stale`, until the new one lands. Defaults to the subject: one string,
   *  one ask, as the four port faces use it. Null with a subject means "nothing to ask right now"
   *  (a quantity of nought); the last answer still stands. */
  question?: string | null
}

/**
 * @param subject   What the answer is FOR, as ONE string — `${portId}:${fleetId ?? '-'}` — or
 *                  null for "nothing to ask" (no port picked). A change of subject drops the answer.
 * @param ask       The RPC. Read through a ref, so a caller may pass a fresh closure every render
 *                  without re-arming the read; only the subject, the question and the world's
 *                  `readAt` re-ask.
 */
export function useServedRead<V>(
  subject: string | null,
  ask: () => Promise<RpcResult<V>>,
  { question = subject }: ServedReadOptions = {},
): ServedRead<V> {
  // The beat this answer is for: the world's read.
  const beat = useWorld((s) => s.readAt) ?? 0

  const askRef = useRef(ask)
  useEffect(() => {
    askRef.current = ask
  })

  const [answer, setAnswer] = useState<{
    subject: string
    question: string
    beat: number
    view: V | null
  } | null>(null)

  useEffect(() => {
    if (subject === null || question === null) return
    let live = true
    void askRef.current().then((r) => {
      if (!live) return
      setAnswer({ subject, question, beat, view: r.ok ? r.value : null })
    })
    return () => {
      live = false
    }
  }, [subject, question, beat])

  if (subject === null) return IDLE
  // Nothing of THIS subject's has been answered yet: wait, and show none of another subject's.
  if (answer === null || answer.subject !== subject) return WAITING
  // The last answer stands while the next read of the same subject — the same question on the
  // world's beat, or a new question — is on the wire.
  const stale = answer.question !== question
  return { view: answer.view, loading: stale || answer.beat !== beat, stale }
}
