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
  BuyCapacity,
  CancelResult,
  ClearResult,
  FleetView,
  FoundedHouse,
  HiredOfficer,
  IssueResult,
  LedgerPage,
  MarketView,
  OfficerRoster,
  PlayerView,
  PostedOfficer,
  PreviewResult,
  PriceHistory,
  SkillBook,
  StudiedSkill,
  TradeRoutes,
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
 * How many tuns of a good this fleet can actually buy where she lies, and WHICH limit stops her —
 * hold, stock, the daily cap, or the purse. Priced by the server through the same stepped quote a
 * real BUY walks, so the number a picker offers and the number the trade charges cannot disagree.
 */
export function worldBuyCapacity(fleetId: string, goodId: string): Promise<RpcResult<BuyCapacity>> {
  return call<BuyCapacity>('worldBuyCapacity', [fleetId, goodId])
}

/**
 * WHERE THIS GOOD IS WORTH MORE THAN IT IS HERE, AND WHAT THE VOYAGE WOULD BE WORTH (0019).
 *
 * `world.market()` serves ONE port and has no opinion about any other, which is why a player could
 * read seventy rows at Lisboa and still not find a trade that paid. This ranks the reachable ports
 * against the one you are standing in, priced end to end through the same `world.quote()` a real
 * BUY and SELL execute at, over the SAILED leg distance, and only to ports this fleet may actually
 * reach.
 *
 * @param fleetId name her and the quantities become real — hold, purse, stock and the daily cap.
 *                Omit it and every row is priced at the server's stated default, reported in
 *                `basis.tuns`.
 * @param maxLegs how many sailed legs out to look. Null takes the server's own default.
 * @param limit   how many rows; null for every good that pays.
 * @param toPortId pin the destination, and the read answers the OTHER question a trader has —
 *                "what should I carry there?" — over the same shortlist, quotes and sail gate.
 *                The leg and port caps do not apply: you have named the only destination there is.
 */
export function worldTradeRoutes(
  portId: string,
  fleetId: string | null = null,
  maxLegs: number | null = null,
  limit: number | null = null,
  toPortId: string | null = null,
): Promise<RpcResult<TradeRoutes>> {
  return call<TradeRoutes>('worldTradeRoutes', [portId, fleetId, maxLegs, limit, toPortId])
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

/**
 * Sign the book: found this account's house, its 8,000 ducats and its first Barca at Lisboa.
 *
 * CALLED ONCE PER ACCOUNT, EVER, and the server is what makes that true — `public.players.auth_uid`
 * is unique, and 0011 translates the violation into `E_ALREADY_FOUNDED`. So the client never has to
 * ask "has this player founded yet?" before calling; it may simply call, and read the refusal.
 *
 * Nothing here identifies the captain. The uid is the JWT's, read server-side (0011), which is why
 * this is the only founding path a browser is allowed to hold — `public.new_house()` takes a uid
 * and is revoked from every client role for exactly that reason.
 */
export function cmdFoundHouse(
  companyName: string,
  nationCode = 'PRT',
): Promise<RpcResult<FoundedHouse>> {
  return call<FoundedHouse>('cmdFoundHouse', [companyName, nationCode])
}

// ── 0013-0016 ───────────────────────────────────────────────────────────────────────────────────

/**
 * One port's remembered prices — every good it trades, oldest point first (0013).
 *
 * ONE CALL PER PORT, NOT PER GOOD. A market screen draws a line on every row it shows, and 70 goods
 * would otherwise be 70 round trips with the client deciding how many points a line has.
 */
export function worldPriceHistory(portId: string, slots = 48): Promise<RpcResult<PriceHistory>> {
  return call<PriceHistory>('worldPriceHistory', [portId, slots])
}

/**
 * The signed-in house, reading itself (0014) — name, nation, purse, counts, and DERIVED fame.
 *
 * Takes no id: the server reads `auth.uid()`, so a caller can only ever read their own. A signed-in
 * account that has not signed the book yet reads back `{ player: null }`, which is a STATE and not
 * a refusal — the register screen exists for exactly that case.
 */
export function worldPlayer(): Promise<RpcResult<PlayerView>> {
  return call<PlayerView>('worldPlayer')
}

/** The officer roster, and which of them this house has signed (0015). */
export function worldOfficers(): Promise<RpcResult<OfficerRoster>> {
  return call<OfficerRoster>('worldOfficers')
}

/** What can be learned, and how far this house has learned it (0016). */
export function worldSkills(): Promise<RpcResult<SkillBook>> {
  return call<SkillBook>('worldSkills')
}

/** Sign an officer, and optionally post them to a fleet at once. The wage leaves the purse through
 *  the one money mover, so the ledger and the purse cannot disagree. */
export function cmdHireOfficer(code: string, fleetId: string | null = null) {
  return call<HiredOfficer>('cmdHireOfficer', [code, fleetId])
}

/** Move an officer already in the house's service to a fleet, or ashore with `null`. */
export function cmdPostOfficer(code: string, fleetId: string | null = null) {
  return call<PostedOfficer>('cmdPostOfficer', [code, fleetId])
}

/** Raise one skill by one level, for money, at a port that keeps an academy (0016). */
export function cmdStudySkill(code: string, fleetId: string) {
  return call<StudiedSkill>('cmdStudySkill', [code, fleetId])
}
