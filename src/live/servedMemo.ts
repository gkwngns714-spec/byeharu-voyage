// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DESK'S MEMORY OF SERVED ANSWERS — a question asked a moment ago is not asked again, and a question
// on the wire is not asked twice (2026-10-19).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-19: "when pressing a different trade goods, it takes too long to load". Each press
// on the Markets list mounted the good's panes afresh, and every read on them was asked from nothing —
// world.good_board took 4–6 s on prod (docs/dev-log/2026-10-19-good-switch-fast.md) — so going BACK to a
// good just shown waited as long as the first time. A served read that names a `memo` key (useServedRead)
// now keeps its answer here:
//
//   · AN ANSWER IS KEPT ONLY WHILE IT IS STILL TRUE TO SHOW. The caller says how long (`freshMs`): the
//     desk's reads until the market's next edge (their clock's `next_change_at`, the moment the open desk
//     would re-ask anyway), and never longer than MAX_FRESH_MS. A kept answer is drawn at once and not
//     re-asked; once it is no longer fresh it is gone, and the read waits as before.
//   · A QUESTION ON THE WIRE IS SHARED: a prefetch (a row the pointer rests on) and the panes it opens ask
//     the server once between them.
//   · A REFUSAL IS NOT KEPT: the next ask asks.
//
// The key is the read's own question (fleet version, amount, city, side included), so a trade — a new
// fleet version — is a new question, never an old answer.

import type { RpcResult } from '../lib/rpc'

/** The longest an answer is reused without asking, whatever its clock says. */
export const MAX_FRESH_MS = 120_000
/** How many answers are kept (the oldest goes first). */
const MAX_KEPT = 200

interface Kept {
  view: unknown
  untilMs: number
}

const kept = new Map<string, Kept>()
const flying = new Map<string, Promise<RpcResult<unknown>>>()

/** The answer kept for `key` while it is fresh, else undefined. */
export function peekServed<V>(key: string): V | undefined {
  const k = kept.get(key)
  if (!k) return undefined
  if (Date.now() >= k.untilMs) {
    kept.delete(key)
    return undefined
  }
  return k.view as V
}

/**
 * Ask `key`'s question: a fresh kept answer is the answer (unless `force` — the market's edge, or the
 * world's beat, re-asks); a question already on the wire is joined; otherwise `ask` is called and an ok
 * answer kept for `freshMs(view)` ms (capped at MAX_FRESH_MS).
 */
export function askServed<V>(
  key: string,
  ask: () => Promise<RpcResult<V>>,
  freshMs: (view: V) => number,
  force = false,
): Promise<RpcResult<V>> {
  if (!force) {
    const view = peekServed<V>(key)
    if (view !== undefined) return Promise.resolve<RpcResult<V>>({ ok: true, value: view })
  }
  const onWire = flying.get(key)
  if (onWire) return onWire as Promise<RpcResult<V>>
  const p = ask().then(
    (r) => {
      flying.delete(key)
      if (r.ok) {
        const ms = Math.min(MAX_FRESH_MS, Math.max(0, freshMs(r.value)))
        kept.delete(key)
        if (ms > 0) kept.set(key, { view: r.value, untilMs: Date.now() + ms })
        while (kept.size > MAX_KEPT) kept.delete(kept.keys().next().value as string)
      } else {
        kept.delete(key)
      }
      return r
    },
    (e: unknown) => {
      flying.delete(key)
      throw e
    },
  )
  flying.set(key, p as Promise<RpcResult<unknown>>)
  return p
}
