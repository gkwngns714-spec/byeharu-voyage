// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SERVED READ THAT RIDES THE WORLD'S BEAT — asked once per read, KEPT ACROSS A TAB SWITCH
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Four port faces — the shed, the inn, the workstation, the yard — each ask the server a question
// about (this port, maybe this fleet), and each must ask AGAIN whenever the world is read again:
// a STORE moves cargo, a MAKE spends it, a HIRE changes who is offered. They were four copies of
// the same hook, and every copy had the same defect: on every world read it threw its answer away
// and reported `{view: null, loading: true}` until the new one arrived. The shell reads the world
// every few seconds (AppShell.tsx), so the Store went blank to "Asking the shed what it holds…"
// and repainted every beat — the owner, 2026-09-13: *"why is store keep refreshing?"* — and
// PortInn.tsx had already grown a workaround (its crew row mounted OUTSIDE the room, so the
// re-read would not unmount its tray). That is the disease NO_SPAGHETTI.md names: a defect in four
// places is fixed in one, and the other three keep it.
//
// ── THE RULE ───────────────────────────────────────────────────────────────────────────────────
// The SUBJECT (port, fleet) decides what an answer is FOR. A new read of the same subject keeps
// the last answer on screen, silently, until the fresh one lands; a new SUBJECT shows nothing of
// the old one — Dublin's shed is never drawn under Lisbon's heading.
//
// A refusal is an answer: it clears the view, because the server just said there is nothing to
// show (the fleet left, the city keeps no such house). A caller draws `view` when it has one, and
// its waiting line only when `loading && !view` — the first ask.
//
// A RE-ASK ON THE WORLD'S BEAT IS NOT LOADING (2026-09-30). Until then `loading` was also true
// while the SAME question was re-asked on the beat, so every beat it went true and false again —
// and the sentence above was not true: a subject whose answer was a refusal (or a null served
// value) has no `view`, so `loading && !view` mounted its waiting line on every beat and unmounted
// it when the re-ask landed. The request board flipped "No requests." to "Loading…", the trade
// tray's unknown `Max` to "Checking how much you can buy…", the manifest's refused basket grew a
// "Loading…" row, the haggle thread's tries re-toned — each a bar blinking on its own, the owner's
// words that day: *"i see multiple cases where a bar … blinks occasionally on its own"*. Now
// `loading` means only what a caller can act on: nothing of this subject has been answered yet
// (the first ask), or the figures on screen answer an earlier question (`stale`). The beat's
// re-ask is silent; its answer simply replaces the last one when it lands.
//
// ── ONE CACHE, AND THE TAB-SWITCH RULE (2026-10-31, src/store/resourceCache.ts) ───────────────
// The owner: *"make it download one time, then keep it even though you move from tab to tab."*
// Every read now goes through the ONE keyed cache. Its key is `name|subject|question`, where
// `name` is the RPC — required for `useMerchantCard(fleetId)` and `useFleetTrades(fleetId)` to
// share a subject without sharing an answer. A fresh kept answer is drawn at once on a NEW MOUNT
// (the render-time `peekResource` below), and the mount's own ask is served from the cache instead
// of the wire; a remount inside the answer's lifetime therefore downloads nothing.
//
// The caller states the lifetime, and the defaults are the three the cache documents:
//   · no `freshMs` — ONE WORLD BEAT. This hook's own rule: the beat is when it would ask again.
//   · `SESSION_MS` — a static catalogue (the officer roster, the skill book, sea conditions).
//   · `msUntilEdge` — a clocked payload (useDesk's good board and price-why).
// A DRY RUN passes `cache: false`: `cmd.preview*` is a real write rolled back, and a stale estimate
// would promise something the commit can refuse. The beat's re-ask (a new `readAt` on THIS mount)
// still forces, because that is how the live figures arrive; the cache only stops a remount from
// asking the same question early.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react'
import type { RpcResult } from '../lib/rpc'
import { peekResource, readResource, type Freshness } from '../store/resourceCache'
import { useWorld } from './worldStore'

export interface ServedRead<V> {
  /** The last answer for this subject, or null before the first one (or after a refusal). */
  view: V | null
  /** True while the first ask for this subject, or a new question, is on the wire. NEVER for the
   *  re-ask of the same question on the world's beat — that one is silent (see the header). */
  loading: boolean
  /** True while `view` answers an EARLIER question than the one now asked — the figures on screen
   *  are this subject's, but not yet for what was just chosen. Always false when the question is
   *  the subject. A caller dims such a view; it never prints it as the answer to the new question. */
  stale: boolean
}

const IDLE = { view: null, loading: false, stale: false }
const WAITING = { view: null, loading: true, stale: false }

/** One world beat — the default lifetime of a read that rides it. AppShell writes the served
 *  cadence into the store (readEveryMs); this reads it at the moment an answer lands. */
const worldBeatFresh = (): number => useWorld.getState().readEveryMs

export interface ServedReadOptions<V = unknown> {
  /** What is ASKED, when that is finer than the subject (2026-09-14): the trade tray's dry run
   *  is FOR (fleet, side, good) but asks about a QUANTITY, and the owner will not have the sale's
   *  figures blink on every press of + — so a new question re-asks and the last answer for the
   *  same subject stands, `stale`, until the new one lands. Defaults to the subject: one string,
   *  one ask, as the four port faces use it. Null with a subject means "nothing to ask right now"
   *  (a quantity of nought); the last answer still stands. */
  question?: string | null
  /** WHAT RE-ASKS, when it is not the world's beat (2026-10-18, the COMMAND desk): a number the caller
   *  moves when the answer is due again — `useEdgeRead` moves it when the served clock's edge passes.
   *  A read that costs a third of a second on prod (world.good_board) must not ride a 3-s beat.
   *  Absent: the world's beat, as every other read. */
  trigger?: number
  /** THE RPC BEING READ — the first half of its cache key. Absent: nothing is kept (a caller that
   *  has not named its read is not cacheable). Two different RPCs must never share a name. */
  name?: string
  /** How long a kept answer stays true, from when it landed. Defaults to one world beat. */
  freshMs?: Freshness<V>
  /** False for a DRY RUN (`cmd.preview*`): a write rolled back, never remembered. Default true. */
  cache?: boolean
}

/**
 * @param subject   What the answer is FOR, as ONE string — `${portId}:${fleetId ?? '-'}` — or
 *                  null for "nothing to ask" (no port picked). A change of subject drops the answer.
 * @param ask       The RPC. Read through a ref, so a caller may pass a fresh closure every render
 *                  without re-arming the read; only the subject, the question, the key and the
 *                  world's `readAt` re-ask.
 */
export function useServedRead<V>(
  subject: string | null,
  ask: () => Promise<RpcResult<V>>,
  { question = subject, trigger, name, freshMs = worldBeatFresh, cache = true }: ServedReadOptions<V> = {},
): ServedRead<V> {
  // The world's read: a new one re-asks the same question — unless the caller names its own trigger.
  const worldBeat = useWorld((s) => s.readAt) ?? 0
  const beat = trigger ?? worldBeat

  const askRef = useRef(ask)
  const freshRef = useRef(freshMs)
  useEffect(() => {
    askRef.current = ask
    freshRef.current = freshMs
  })

  // The cache key is the read's own question, named for its RPC. A read without a name is never
  // remembered (the old behaviour, kept as the safe fallback for a caller that forgot to name it).
  const key = name && subject !== null && question !== null && cache ? `${name}|${subject}|${question}` : null
  // The question last asked by THIS mount: asking it again is the beat's (or the edge's) re-ask,
  // which forces — a kept answer is not allowed to swallow the beat.
  const askedRef = useRef<string | null>(null)

  const [answer, setAnswer] = useState<{
    subject: string
    question: string
    view: V | null
  } | null>(null)

  useEffect(() => {
    if (subject === null || question === null) return
    let live = true
    const asking = key ?? `${subject}${question}`
    const again = askedRef.current === asking
    askedRef.current = asking
    const answered = key
      ? readResource<V>(key, () => askRef.current(), freshRef.current, again)
      : askRef.current()
    void answered.then((r) => {
      if (!live) return
      setAnswer({ subject, question, view: r.ok ? r.value : null })
    })
    return () => {
      live = false
    }
    // `beat` and `key` are not read in the body: they are here only so the world's read (or the
    // caller's edge) re-asks, and so a new name is a new question.
  }, [subject, question, beat, key])

  if (subject === null) return IDLE
  // This very question answered on this mount: the answer, the beat's re-ask silent behind it.
  if (answer !== null && answer.subject === subject && answer.question === question) {
    return { view: answer.view, loading: false, stale: false }
  }
  // A fresh kept answer to this very question (resourceCache.ts): drawn at once, as if just
  // answered — the tab-switch rule. After a mutation the cache is empty and this waits instead.
  const remembered = key ? peekResource<V>(key) : undefined
  if (remembered !== undefined) return { view: remembered, loading: false, stale: false }
  // Nothing of THIS subject's has been answered yet: wait, and show none of another subject's.
  if (answer === null || answer.subject !== subject) return WAITING
  // The last answer stands while the next read of the same subject — the same question on the
  // world's beat, or a new question — is on the wire. Only the new question is `loading`; the
  // beat's re-ask is not (the header's 2026-09-30 paragraph).
  const stale = answer.question !== question
  return { view: answer.view, loading: stale, stale }
}
