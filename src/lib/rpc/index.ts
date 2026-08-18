// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RPC SURFACE — nine functions, and everything the six V0 tabs are made of
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// DESIGN Appendix 2 names the client's whole vocabulary: four reads and five commands. This file
// is that vocabulary in TypeScript, and it is the ONLY thing a screen should import. It contains
// no SQL, no Supabase, no PGlite and no `if (hasCloud)` — those live one layer down, once.
//
// EVERY function returns `RpcResult<T>`, never a bare payload and never a throw:
//
//     const r = await worldFleets()
//     if (!r.ok) return <Notice code={r.refusal.code}>{r.refusal.sentence}</Notice>
//     r.value.forEach(...)
//
// A refusal is data (result.ts). `E_HOLD_FULL` is the game working, and it arrives with the
// sentence and the fixes DESIGN F.5 promises.
//
// TWO THINGS THE SURFACE DOES NOT DO
//   * It does not cache. `world.snapshot()` is static enough to cache hard, but caching is a
//     screen-lifetime decision and a second copy of the world here would be the exact thing
//     src/live/worldStore.ts is where a screen-lifetime copy belongs, and it keeps exactly one.
//   * It does not settle, tick or poll. Every read RPC settles server-side first (D.2): the READ
//     is the catch-up, so "refetch" is the entire client-side time model.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { call } from './backend'
import type { RpcResult } from './result'
import type {
  CancelResult,
  ClearResult,
  FleetView,
  IssueResult,
  LedgerPage,
  MarketView,
  PreviewResult,
  VerbSpec,
  WorldSnapshot,
} from './types'

/**
 * The static world — 12 ports, 22 legs, 12 goods, 3 ship classes, the allow-listed config knobs
 * and the 8 verbs. Changes only when a migration changes it; safe to fetch once per session.
 */
export function worldSnapshot(): Promise<RpcResult<WorldSnapshot>> {
  return call<WorldSnapshot>('worldSnapshot')
}

/**
 * One port's reading room (§E.4): every good priced ask/bid/mid, with %NBR, the stock band, the
 * culture availability flag and the buy/hold/sell advice the MARKET tab sorts on.
 *
 * @param portId `SnapshotPort.id` — a uuid, NOT the three-letter code.
 */
export function worldMarket(portId: string): Promise<RpcResult<MarketView>> {
  return call<MarketView>('worldMarket', [portId])
}

/**
 * The player's fleets, ships, cargo, voyage position and order queue.
 *
 * THIS CALL ADVANCES THE WORLD. `world.fleets()` settles every voyage first, so a player who was
 * away nine hours arrives home in this response rather than watching a fleet teleport afterwards.
 */
export function worldFleets(): Promise<RpcResult<FleetView[]>> {
  return call<FleetView[]>('worldFleets')
}

/**
 * The log (§E.6) — the source of truth, not a UI convenience.
 *
 * @param cursor pass the previous page's `next_cursor` for the next page; null for the newest.
 * @param limit  server-clamped to 1..200; the default is the chain's own 50.
 */
export function worldLedger(cursor: string | null = null, limit = 50): Promise<RpcResult<LedgerPage>> {
  return call<LedgerPage>('worldLedger', [cursor, limit])
}

/**
 * THE only mutating entry point in the game. It takes a STRING, because the tap-builder and the
 * keyboard must submit the same thing through the same parser (F.4).
 *
 * @param expectedVersion the fleet's `version` as the screen last saw it. Supply it: it is what
 *        makes two devices unable to double-issue, and a mismatch comes back as `E_STALE` rather
 *        than as a duplicated order.
 */
export function cmdIssue(
  fleetId: string,
  rawText: string,
  expectedVersion: number | null = null,
): Promise<RpcResult<IssueResult>> {
  return call<IssueResult>('cmdIssue', [fleetId, rawText, expectedVersion])
}

/**
 * The dry run (F.5 layer 3). It executes the REAL verb in a subtransaction and throws it away, so
 * the estimate and the commit cannot disagree — and so a preview that refuses is telling you
 * exactly what the commit would have refused.
 */
export function cmdPreview(fleetId: string, rawText: string): Promise<RpcResult<PreviewResult>> {
  return call<PreviewResult>('cmdPreview', [fleetId, rawText])
}

/** Cancel one queued order by its 1-based index, or the head of the queue when index is null. */
export function cmdCancel(fleetId: string, index: number | null = null): Promise<RpcResult<CancelResult>> {
  return call<CancelResult>('cmdCancel', [fleetId, index])
}

/**
 * Drop every pending order. A voyage already at sea KEEPS SAILING — RECALL is not a V0 verb, and
 * the result says so in `active_left_running` and `note` rather than half-doing it.
 */
export function cmdClear(fleetId: string, includeActive = false): Promise<RpcResult<ClearResult>> {
  return call<ClearResult>('cmdClear', [fleetId, includeActive])
}

/** The grammar, for the tap-builder: the same 8 verbs `world.snapshot().verbs` carries. */
export function cmdVerbSchema(): Promise<RpcResult<VerbSpec[]>> {
  return call<VerbSpec[]>('cmdVerbSchema')
}

// ── the seam's own plumbing, re-exported so a caller imports from ONE place ─────────────────────

export { initRpc, rpcMode, forgetRpcChoice } from './init'
export { backendKind, currentBackend, setBackend, clearBackend, call } from './backend'
export type { RpcBackend, BackendKind } from './backend'
export { createLocalBackend } from './localBackend'
export type { LocalCaller } from './localBackend'
export { createCloudBackend } from './cloudBackend'
export { RPCS, rpcLabel, localSql, namedArgs } from './catalog'
export type { RpcName, RpcSpec } from './catalog'
export { expectOk, fromError, fromPayload, ok, refused } from './result'
export type { Refusal, RpcResult } from './result'
export type * from './types'
