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
// This is a VIEW read. A CEILING read (useBuyCapacity, useHaggleState) is deliberately not this:
// a ceiling shown a beat late is the lie those hooks were written to remove, so they still wait.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react'
import type { RpcResult } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface ServedRead<V> {
  /** The last answer for this subject, or null before the first one (or after a refusal). */
  view: V | null
  /** True while an ask is on the wire — the first one, or a re-ask on the world's beat. */
  loading: boolean
}

const IDLE = { view: null, loading: false }
const WAITING = { view: null, loading: true }

/**
 * @param subject  What the question is about, as ONE string — `${portId}:${fleetId ?? '-'}` — or
 *                 null for "nothing to ask" (no port picked). A change of subject drops the answer.
 * @param ask      The RPC. Read through a ref, so a caller may pass a fresh closure every render
 *                 without re-arming the read; only `subject` and the world's `readAt` re-ask.
 */
export function useServedRead<V>(
  subject: string | null,
  ask: () => Promise<RpcResult<V>>,
): ServedRead<V> {
  const readAt = useWorld((s) => s.readAt) ?? 0

  const askRef = useRef(ask)
  useEffect(() => {
    askRef.current = ask
  })

  const [answer, setAnswer] = useState<{ subject: string; readAt: number; view: V | null } | null>(
    null,
  )

  useEffect(() => {
    if (subject === null) return
    let live = true
    void askRef.current().then((r) => {
      if (!live) return
      setAnswer({ subject, readAt, view: r.ok ? r.value : null })
    })
    return () => {
      live = false
    }
  }, [subject, readAt])

  if (subject === null) return IDLE
  // Nothing of THIS subject's has been answered yet: wait, and show none of another subject's.
  if (answer === null || answer.subject !== subject) return WAITING
  // The last answer stands while the next read of the same subject is on the wire.
  return { view: answer.view, loading: answer.readAt !== readAt }
}
