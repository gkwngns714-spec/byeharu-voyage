// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RESOURCE CACHE — every served read the client may keep, and the ONE rule for how long
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-31: *"make it download one time, then keep it even though you move from tab
// to tab."* A tab switch remounts a screen, and every served read on it used to ask the server
// again — the Codex asked the officer catalogue on every mount AND on every world beat, a Command
// remount asked the market again, and a catalogue that had not changed in the whole session was
// downloaded a third time. This module is the ONE place that decides whether a read goes to the
// wire. There is no second cache in `src/live` any more (the desk's `servedMemo` was folded in
// here, not left standing beside it).
//
// ── THE THREE LIFETIMES ───────────────────────────────────────────────────────────────────────
// A caller says how long its answer stays true, and nothing else may keep a second opinion:
//
//   SESSION_MS   a STATIC CATALOGUE — the world snapshot, the sea raster, the officer roster, the
//                skill book, the route board. It cannot change by playing, so it is fetched once
//                per tab and kept for the tab's whole life. A verb that CAN change it is named in
//                `catalog.ts` (`invalidates`) and drops exactly that entry.
//   edge         a CLOCKED PAYLOAD — the market and every payload carrying `clock.next_change_at`.
//                The server's own next instant is the refresh, so a payload read at 10:00:10 with
//                an edge at 10:01:00 is kept for 50 s and asked again after the edge — never
//                because a tab was remounted. `msUntilEdge` is the one reading of that clock.
//   one beat     everything else — a read that rides the world's beat. The world store's beat is
//                how time passes (a read IS the catch-up, worldStore rule 1), so an answer is
//                kept for exactly one beat and the beat's own re-ask refreshes it. A remount
//                inside that beat draws the answer at once and touches no wire.
//
// A DRY RUN IS NEVER KEPT (`cache: false` at its caller): `cmd.preview*` is a real write rolled
// back, and a stale estimate would promise something the commit can refuse. The Stats tab's
// one-second stream is not a cache either — it is a live feed by the owner's order (row 213), and
// freezing it would be the opposite of what was asked.
//
// ── A QUESTION ON THE WIRE IS ASKED ONCE ────────────────────────────────────────────────────
// Two mounts (or a prefetch and the screen it opens) asking the same key share one promise. A
// REFUSAL IS NOT KEPT: the next read asks, because the server just said why the answer is not an
// answer. An answer with no freshness left (0 ms) is not kept either.
//
// ── A MUTATION DROPS THE LIVE ANSWERS, ONCE, HERE ───────────────────────────────────────────
// `catalog.ts` marks every verb that changes the world (`mutates`), and `backend.ts` calls
// `invalidateLiveResources` after one SUCCEEDS. Every finite-lifetime entry goes — a trade moves
// the market, an invest moves the town hall, a sail moves the fleet — and a verb whose effect
// reaches a SESSION entry names that entry in `invalidates` (a hire changes the roster, a study
// changes the skill book). An ask already on the wire when the mutation lands is not kept, so an
// answer computed before the commit cannot poison the cache after it.
//
// THE KEY IS THE READ'S OWN QUESTION, prefixed with its RPC: `name|subject|question`. The RPC name
// is load-bearing — `useMerchantCard(fleetId)` and `useTradeHistory(fleetId)` share a subject
// string, and without the prefix a merchant card could be served to a trade history. The key is
// written by `useServedRead`; nothing outside this module stores one.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { setMutationListener } from '../lib/rpc/backend'
import type { RpcResult } from '../lib/rpc/result'

/** How long an answer stays true, in ms, or a function of the answer itself (a served clock). */
export type Freshness<V> = number | ((value: V) => number)

/** Keep forever — for the session. The live catalogues, the snapshot, the raster. */
export const SESSION_MS = Number.POSITIVE_INFINITY
/** The longest a CLOCKED answer is kept, even if a served instant is absurd. The old cap that
 *  `servedMemo` applied to every answer; here it belongs to the edge reading alone. */
export const MAX_EDGE_MS = 120_000
/** A ceiling on the finite (beat/edge) entries; session entries are few and never evicted. */
const MAX_KEPT = 400

interface KeptEntry {
  readonly value: unknown
  readonly untilMs: number
  readonly session: boolean
}

interface FlyingRead {
  readonly promise: Promise<RpcResult<unknown>>
  /** Identifies THIS flight in the map: a mutation may detach it and a new read may take the
   *  slot, and the old answer must not remove the new one's record when it lands. */
  readonly token: symbol
}

const kept = new Map<string, KeptEntry>()
const flying = new Map<string, FlyingRead>()
/** Bumped by every invalidation. A read that started before the bump may still answer its own
 *  caller, but it may not write the cache: its answer was computed before the mutation. */
let epoch = 0

function freshEntry(key: string): KeptEntry | undefined {
  const entry = kept.get(key)
  if (!entry) return undefined
  if (Date.now() >= entry.untilMs) {
    kept.delete(key)
    return undefined
  }
  return entry
}

/** The fresh answer kept for `key`, or undefined. Drawn synchronously on a remount. */
export function peekResource<V>(key: string): V | undefined {
  return freshEntry(key)?.value as V | undefined
}

function lifetimeOf<V>(freshMs: Freshness<V>, value: V): number {
  const raw = typeof freshMs === 'function' ? freshMs(value) : freshMs
  if (raw === SESSION_MS) return SESSION_MS
  return Number.isFinite(raw) ? Math.max(0, raw) : 0
}

function trim(): void {
  if (kept.size <= MAX_KEPT) return
  for (const key of kept.keys()) {
    if (kept.get(key)?.session !== false) continue
    kept.delete(key)
    if (kept.size <= MAX_KEPT) return
  }
}

/**
 * Ask `key`'s question: a fresh kept answer is the answer; a question already on the wire is
 * joined; otherwise `ask` is called and an ok answer kept for `freshMs` (a refusal is not kept).
 * `force` ignores the kept answer — the world beat, a served edge, or a caller that just mutated —
 * but still joins a read already in flight, so a slow answer is never stacked.
 */
export function readResource<V>(
  key: string,
  ask: () => Promise<RpcResult<V>>,
  freshMs: Freshness<V>,
  force = false,
): Promise<RpcResult<V>> {
  if (!force) {
    const entry = freshEntry(key)
    if (entry) return Promise.resolve<RpcResult<V>>({ ok: true, value: entry.value as V })
  }
  const onWire = flying.get(key)
  if (onWire) return onWire.promise as Promise<RpcResult<V>>

  const epochAtStart = epoch
  const token = Symbol(key)
  const promise = ask().then(
    (result) => {
      // Only THIS flight's record may be removed: a mutation may have detached it, and a new read
      // may already hold the key (the epoch guard below keeps its answer; this keeps its slot).
      if (flying.get(key)?.token === token) flying.delete(key)
      if (epochAtStart !== epoch) return result
      if (!result.ok) {
        kept.delete(key)
        return result
      }
      const ms = lifetimeOf(freshMs, result.value)
      const session = ms === SESSION_MS
      const untilMs = session ? SESSION_MS : Date.now() + ms
      kept.delete(key)
      if (session || ms > 0) kept.set(key, { value: result.value, untilMs, session })
      trim()
      return result
    },
    (err: unknown) => {
      if (flying.get(key)?.token === token) flying.delete(key)
      throw err
    },
  )
  flying.set(key, { promise: promise as Promise<RpcResult<unknown>>, token })
  return promise
}

/** The one spelling of "this key belongs to that RPC": `name`, or `name|…`. */
function belongsTo(key: string, name: string): boolean {
  return key === name || key.startsWith(`${name}|`)
}

/**
 * Drop one key, or every key whose RPC name is `name`. The named form is for a SESSION entry a
 * verb changes (the officer roster after a hire); a mutation usually drops the finite entries
 * wholesale through `invalidateLiveResources` below.
 */
export function invalidateResource(match: string | ((key: string) => boolean)): void {
  const hit = typeof match === 'function' ? match : (key: string) => belongsTo(key, match)
  for (const key of [...kept.keys()]) if (hit(key)) kept.delete(key)
  for (const key of [...flying.keys()]) if (hit(key)) flying.delete(key)
  epoch += 1
}

/**
 * THE MUTATION'S TAIL (backend.ts, after a verb that changes the world succeeds): every
 * finite-lifetime answer is dropped, plus the SESSION entries the verb names in `catalog.ts`
 * (`invalidates`). Reads already on the wire are detached — see `epoch`.
 */
export function invalidateLiveResources(extra: readonly string[] = []): void {
  for (const [key, entry] of [...kept]) {
    const named = extra.some((name) => belongsTo(key, name))
    if (!entry.session || named) kept.delete(key)
  }
  flying.clear()
  epoch += 1
}

/** Forget everything. Specs and a hard backend switch only. */
export function clearResourceCache(): void {
  kept.clear()
  flying.clear()
  epoch += 1
}

/** How many answers are kept — a spec's reading, never a screen's. */
export function resourceCacheSize(): number {
  return kept.size
}

/**
 * How long a served clock's answer stays true: the gap between the payload's `now` and its edge.
 * Clamped to `MAX_EDGE_MS` so a skewed or absurd served instant cannot hold a price for ever.
 * This replaces the desk's private `untilEdge`; the market and the desk read it from here.
 */
export function msUntilEdge(clock: { now: string; next_change_at: string }): number {
  const ms = Date.parse(clock.next_change_at) - Date.parse(clock.now)
  if (!Number.isFinite(ms)) return 0
  return Math.min(MAX_EDGE_MS, Math.max(0, ms))
}

// THE DISPATCHER'S MUTATION SIGNAL (backend.ts, `setMutationListener`). The cache imports DOWN
// into lib — the direction the layering allows; lib may never import up into the store, which
// `tests/sections.spec.ts` proves. Every screen's served reads import this module before it can
// issue a verb, so the subscription is in place before the first mutation.
setMutationListener((_name, invalidates) => invalidateLiveResources(invalidates))
