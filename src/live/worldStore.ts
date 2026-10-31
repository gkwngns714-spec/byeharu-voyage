// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LIVE WORLD — one store, mounted once, read by every tab.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This replaced the fixture layer (`src/fixtures/`, now deleted). Same shape of promise — ONE
// source, mounted once, read by every screen — but the source is now the real chain: PGlite in this
// tab, or a Supabase project when there is one. No screen imports `supabase`, `PGlite`, `hasCloud`
// or any RPC transport; a screen imports THIS and nothing else about data.
//
// ── THE THREE RULES THIS FILE EXISTS TO KEEP ────────────────────────────────────────────────────
//
// 1. A READ IS THE CATCH-UP. `world.fleets()` settles every voyage server-side before it answers,
//    so the way to advance time is to READ AGAIN. There is no tick loop on the client and there
//    never will be one: `refresh()` is the entire client-side time model.
//
// 2. A REFUSAL IS DATA. Every RPC returns `RpcResult`, never throws. `E_HOLD_FULL` is the game
//    working — it arrives with a code, a sentence and tappable fixes (DESIGN F.5) — so the store
//    keeps the last refusal as state rather than swallowing it into a console.
//
// 3. NUMBERS COME FROM THE SERVER. Speed, endurance, prices, %NBR, free hold, voyage position: all
//    of them are computed inside the transaction that owns them. The client's job is to print
//    them. There is no second implementation of any of it on this side of the wire.
//
// 4. A SCREEN SUBSCRIBES TO FIELDS, NEVER TO THE STORE. `useWorld((s) => s.fleets)`, one hook per
//    field. **`useWorld()` with no selector is banned** — the reason is below.
//
// ── RULE 4, AND WHY IT IS A RULE RATHER THAN A TASTE (2026-08-22) ──────────────────────────────
//
// Both spellings worked, so both got written. MARKET, MAP, the shell and the world gate selected
// fields; FLEETS, LEDGER, COMMAND, PORT, PROFILE and RANK called `useWorld()` bare and passed the
// whole `LiveWorld` down as a prop. Two conventions for one thing is the duplication this project
// forbids on its own account — and this one also has a cost that can be measured.
//
// `useWorld()` with no selector subscribes to the WHOLE store object, and zustand replaces that
// object on every `set()`. `refresh()` alone sets three times — `{reading: true}` on the way in, the
// routes book, the payload on the way out — so ONE read re-rendered every bare subscriber three times over, whether or
// not a field it draws had moved. That is not theoretical here: reading IS how time passes (rule
// 1), issuing an order from Command refreshes the world, and the Ledger's list is long.
//
// THE CONVENTION IS THE FINE-GRAINED SELECTOR, in every screen, for actions as much as for data.
// A zustand action is a stable reference, so selecting one costs nothing and never re-renders.
//
// THE ONE THING TO WATCH: a selector must return something STABLE. Returning a fresh object or
// array (`useWorld((s) => ({ a: s.a, b: s.b }))`, `useWorld((s) => s.fleets.filter(…))`) builds a
// new value every render and re-renders for ever. Take ONE field per hook and do the shaping in
// the component, under `useMemo` where it is worth it. `fleetOf` / `portOfFleet` below are plain
// functions over an already-selected value for exactly that reason — they are not selectors.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { create } from 'zustand'
import {
  cmdCancel,
  cmdClear,
  cmdDivert,
  cmdFulfil,
  cmdHaggle,
  cmdHireOfficer,
  cmdIssue,
  cmdIssueLines,
  cmdPreview,
  cmdStandingRouteAssign,
  cmdStandingRouteDelete,
  cmdStandingRoutePause,
  cmdStandingRouteSave,
  cmdSkillEnroll,
  cmdSkillQueueSet,
  cmdTradeBasket,
  initRpc,
  worldFleets,
  worldLedger,
  worldMarket,
  worldOfficers,
  worldAllegiance,
  worldPlayer,
  worldPriceSeries,
  cmdWatchPrice,
  worldSkills,
  worldStandings,
  worldBuffs,
  worldSnapshot,
  worldStandingRoutes,
  worldRouteBoard,
  worldSeaRaster,
  worldReach,
  worldSeaRoster,
} from '../lib/rpc'
import { navFromServed, type SeaNav } from '../lib/sea'
import { registerHullClasses } from '../chart'
import { msUntilEdge, peekResource, readResource, SESSION_MS } from '../store/resourceCache'
import { READ_MAX_MS } from '../domain/readClock'
import { whereabouts } from '../domain/fleet'
import { mergeRoster, readSavedRoster, rosterKey, savedRosterText, trafficRowAt } from './seaRoster'
import { namedMarket, namedSnapshot } from './worldNames'
import { getLocale, subscribeLocale } from '../lib/i18n'
import type {
  FleetView,
  HaggleAttempt,
  LedgerEvent,
  ManifestLine,
  PlanLine,
  ManifestReceipt,
  MarketView,
  OfficerRoster,
  PlayerHouse,
  PreviewResult,
  PriceSeries,
  PriceSpan,
  Refusal,
  RpcResult,
  AllegianceView,
  StandingRouteBook,
  StandingRouteStopDraft,
  ReachPayload,
  RouteBoard,
  RosterFleet,
  SeaTraffic,
  SkillBook,
  SnapshotNation,
  PortAllegiance,
  StandingsBoard,
  BuffsView,
  SnapshotGood,
  SnapshotPort,
  WorldSnapshot,
} from '../lib/rpc'

export type LoadPhase = 'idle' | 'opening' | 'ready' | 'failed'

export interface LiveWorld {
  // ── what is loaded ───────────────────────────────────────────────────────────────────────────
  phase: LoadPhase
  /** Set when the world could not be opened at all. A failure is rendered, never spun on. */
  fatal: Refusal | null
  /** Which backend answered. Display only — nothing branches on it. */
  mode: 'local' | 'cloud' | null

  /** The static world: ports, goods, ship classes, config knobs, the verb grammar. Published in
   *  the same `set()` as the first fleets read and `phase: 'ready'` (see `open`), so non-null
   *  means the fleets have been read — a screen may take `fleets: []` beside it as an answer. */
  snapshot: WorldSnapshot | null
  /** THE NAVIGABLE SEA (0039) — the served raster, unpacked once for the pathfinder. The same
   *  row the server verifies every course against, so client and server cannot hold different
   *  water. Null only while the world is still opening. */
  seaNav: SeaNav | null
  /** One place's sailed distances to everywhere (0039), keyed by port id — the SAIL picker's
   *  ordering and figures. Fetched on demand; a reach never changes within a chain version. */
  reaches: Record<string, ReachPayload>
  /** The player's fleets, ships, cargo, queue and voyage position. Refetching this IS the clock. */
  fleets: FleetView[]
  /** The house itself — name, nation, counts and DERIVED fame (0014). Null for a signed-in
   *  account that has not signed the book: a state, not a failure. */
  player: PlayerHouse | null
  /** The officer roster and the school, fetched on demand — neither changes while you look at it. */
  officers: OfficerRoster | null
  skills: SkillBook | null
  /** The settled board (0025). Null until RANK asks for it — nothing else needs it. */
  standings: StandingsBoard | null
  /**
   * EVERY LANE THE WORLD SAILS (0106-0110, owner rows 115/117) — the last `world.route_board`
   * reading, or null before ROUTES has asked for one.
   *
   * ASKED ONCE AND THEN LEFT ALONE, never on the shell's beat, which is the one thing about it
   * worth knowing. The board measured 218 ms a call at 838 routes (profiled on the real chain:
   * `route_requirement` 71.7 ms, `standing_route_state` 52.1, `route_earnings` 34.5, `route_nm`
   * 12.8, the stops and their regions 7.2). None of those is wasteful — there are simply eight
   * hundred routes since 0105 — but two hundred milliseconds every three seconds to repaint a
   * board that changes when a lap closes somewhere is the CADENCE being wrong. ROUTES is in the
   * Cabin group because "none of them acts on the world": it is consulted, not played.
   *
   * So it is a photograph, and `routeBoardAt` dates it so the screen can say how old it is
   * rather than pretend to be live — the bargain RANK strikes with its "settled" line.
   */
  routeBoard: RouteBoard | null
  /** When `routeBoard` was answered, in ms. Null before the first. */
  routeBoardAt: number | null
  /** The last board read was refused; whatever is in `routeBoard` is from before it. A board a
   *  minute old beats no board, so the answer is kept and the screen says which it holds. */
  routeBoardFailed: boolean
  /** The company's standing routes (0092). Null until the first world read lands — `refresh()`
   *  reads them with the fleets, on the same beat. A route runs on the server whether or not
   *  anyone is looking; this is only the reading of it. */
  routes: StandingRouteBook | null
  /** THE MERCHANTS AT SEA AND IN PORT (0099, docs/NPC_TRADERS.md §8.1) — the last
   *  `world.sea_traffic()` reading, or null before the first. Read by `refresh()` on the shell's
   *  beat, AFTER the routes, and ONLY while a screen wants it (`trafficWanted > 0`): a captain on the
   *  Ledger does not pay for merchants he cannot see. A failed read keeps the last reading — a map
   *  without merchants is still a map. Dark (`enabled: false`) it is an empty list.
   *
   *  BACK TO NULL WHEN THE LAST SCREEN THAT WANTED IT GOES (2026-10-10): a reading nobody has
   *  refreshed since the player left the tab would otherwise be painted as the present on remount.
   *  See `wantTraffic`. */
  traffic: SeaTraffic | null
  /** How many mounted screens want the traffic (MAP, PORT). The one seam a screen has into the
   *  cadence; it is never a second clock. */
  trafficWanted: number
  /** The instant `traffic` was PLACED at (epoch ms) — the roster's rows are placed in time on every
   *  beat (src/live/seaRoster.ts) and drifted from this instant. Null with `traffic`. */
  trafficReadAt: number | null
  /** What is on at the quay (0026), keyed by port id — a fair is a PORT's fact, not the world's. */
  buffs: Record<string, BuffsView>
  /** A good's price at a city over a span (0226), keyed `port|good|span` (seriesKey). One read per key;
   *  a pair the record does not keep yet is pressed into it once (cmd.watch_price). */
  series: Record<string, PriceSeries>

  /** The purse, and the events behind it. */
  ducats: number | null
  events: LedgerEvent[]
  /** One port's prices, keyed by port id. Fetched on demand; the Market tab drives it. */
  markets: Record<string, MarketView>

  /** True while a refresh is in flight — for a quiet indicator, never for a blocking spinner. */
  reading: boolean
  /** The last refusal any command produced, for the screen that issued it to render. */
  refusal: Refusal | null
  /** When the last successful read landed (ms since epoch), so a screen can say "as of". */
  readAt: number | null
  /** THE SHELL'S READ CADENCE, in ms (readClock.ts) — AppShell writes it when it arms the beat.
   *  `useServedRead` reads it as the default lifetime of a kept answer: one beat is exactly when
   *  the same mount would ask again. Before the first write, the slow-world floor. */
  readEveryMs: number

  // ── lookups, built once per snapshot ─────────────────────────────────────────────────────────
  portByCode: Record<string, SnapshotPort>
  nationByCode: Record<string, SnapshotNation>
  portById: Record<string, SnapshotPort>
  goodByCode: Record<string, SnapshotGood>
  /** 0143 — EVERY HARBOUR'S FLAG, by port code (`world.allegiance`): the country that holds it today
   *  and whether it is a home city. Read through `portNationOf` alone; empty until the first read
   *  lands, and then a screen prints no flag rather than a guessed one. */
  allegiance: Record<string, PortAllegiance>

  // ── what a screen may do ─────────────────────────────────────────────────────────────────────
  /** Open the world. Idempotent; AppShell calls it once. */
  open: () => Promise<void>
  /** Read again — fleets and ledger. THIS IS HOW TIME PASSES. */
  refresh: () => Promise<void>
  /** Fetch (and cache) one port's market. `force` asks again after a mutation (afterTrade) or a
   *  player's retry; a plain call is served from the cache until the market's own edge. */
  loadMarket: (portId: string, force?: boolean) => Promise<void>
  /** Fetch (and cache) one port's remembered prices. `slots` is how many the asking window needs; the
   *  silent: a chart is a decoration on a price that is true without it. Lands `series[seriesKey(...)]`;
   *  a pair the record does not keep yet is pressed into it once (cmdWatchPrice) and reads again. */
  loadSeries: (portId: string, goodId: string, span: PriceSpan) => Promise<void>
  /** Fetch (and cache) one place's sailed distances to everywhere (0039). */
  loadReach: (portId: string) => Promise<void>
  /** Fetch (and cache) where the goods of one port pay more. Naming the fleet lying there is what
   *  makes the quantities hers rather than the server's stated default. */
  /** Read every harbour's flag again (0143) — the city panel asks when it opens; the beat asks
   *  once an hour. Flags change once a day, so this is never on the 3-s beat. */
  loadAllegiance: () => Promise<void>
  /** Fetch the roster and the school. Idempotent; screens call them on mount. */
  loadOfficers: (force?: boolean) => Promise<void>
  loadSkills: (force?: boolean) => Promise<void>
  loadStandings: (limit?: number | null, force?: boolean) => Promise<void>
  /** Read the route board. ROUTES calls this once on mount and again when the player asks; no
   *  beat calls it (see `routeBoard`). A refusal keeps the last answer and sets
   *  `routeBoardFailed`, rather than blanking a board already on screen. */
  loadRouteBoard: (force?: boolean) => Promise<void>
  loadBuffs: (portId: string, force?: boolean) => Promise<void>
  /** Read the routes (0092) ALONE — for a verb that moved only the book (save, delete). The
   *  beat's reading of them is `refresh()`'s, never a screen's `readAt` effect. */
  loadRoutes: () => Promise<void>
  /** Write a route (routeId null) or replace its stops. Returns the route's id, or null when the
   *  server refused — the refusal lands in `refusal`. */
  saveRoute: (routeId: string | null, name: string | null, stops: readonly StandingRouteStopDraft[]) => Promise<string | null>
  deleteRoute: (routeId: string) => Promise<boolean>
  /** Give a route to a fleet (it starts at once, so the world is read back), or take it off with null. */
  assignRoute: (routeId: string, fleetId: string | null) => Promise<boolean>
  pauseRoute: (routeId: string, paused: boolean) => Promise<boolean>
  /** Hire a captain, or study a level (0166: a captain is seated with `cmdSeatCaptain`). Each re-reads what it changed, because the
   *  server's answer is the only true one — no local patching (the `issue` rule). */
  hireOfficer: (code: string, fleetId: string | null) => Promise<boolean>
  /** 0131: enrol in a skill where this fleet is docked; set the whole training queue (in order).
   *  (The Academy's old one-button `studySkill` left with the instant purchase; cmd.study_skill stays
   *  on the server for older builds and does the same two acts.) */
  enrollSkill: (code: string, fleetId: string) => Promise<boolean>
  setSkillQueue: (entries: readonly { code: string; level: number }[]) => Promise<boolean>

  /** ONE attempt at a bargain (0022). Returns the attempt — WON OR LOST, both of which are `ok` —
   *  or null when the server refused. Attempts are finite and a lost one is spent, so a caller may
   *  never retry on the player's behalf. */
  haggle: (
    fleetId: string,
    goodId: string,
    side: 'buy' | 'sell',
  ) => Promise<HaggleAttempt | null>

  /** Issue an order. The string is the whole contract (F.4) — the tap-builder composes the same
   *  string a keyboard would. A SAIL also carries its PROPOSED course (0039), which the server
   *  verifies and measures itself. Refreshes on success so the queue and purse are never stale. */
  issue: (fleetId: string, text: string, path?: [number, number][] | null) => Promise<boolean>
  /** A PLAN (0175): several lines queued together or not at all — the desk's "Queue it once". A refusal
   *  (naming its line) lands in `refusal` as every verb's does; the world is read back as after `issue`. */
  issueLines: (fleetId: string, lines: readonly PlanLine[]) => Promise<boolean>
  /** THE MANIFEST (0083): several buy and sell lines at the quay she lies at, landing together or
   *  not at all. Returns the served receipt, or null when the quay refused — the refusal (with
   *  `line`, the input index that refused) lands in `refusal` as every verb's does. Re-reads the
   *  world and the market on success exactly as `issue` does: one post-trade read, not two. */
  issueManifest: (fleetId: string, lines: readonly ManifestLine[]) => Promise<ManifestReceipt | null>
  /** A DELIVERY (0087): the whole lot a request asks for, sold at this port's bid with the premium
   *  paid beside it, together or not at all. Returns the served receipt (0083's, with the premium
   *  on it), or null when the server refused — the refusal lands in `refusal` as every verb's
   *  does. Reads the world and the market back on success exactly as `issue` does. */
  fulfil: (fleetId: string, contractId: string) => Promise<ManifestReceipt | null>
  /** Dry-run the same string: the server executes the real verb and rolls it back (F.5 layer 3). */
  preview: (
    fleetId: string,
    text: string,
    path?: [number, number][] | null,
  ) => Promise<PreviewResult | null>
  cancel: (fleetId: string, index?: number | null) => Promise<boolean>
  clear: (fleetId: string) => Promise<boolean>
  /** The helm order at sea (0039): a SAILING fleet turns WHERE SHE IS and makes for a port or a
   *  point of open water, on a proposed course the server bridges to her true position and
   *  verifies. A refusal (E_NOT_SAILING, E_SAME_DEST, E_LAND…) lands in `refusal` as usual. */
  divert: (
    fleetId: string,
    destPortId: string | null,
    destPoint?: { lat: number; lon: number } | null,
    path?: [number, number][] | null,
  ) => Promise<boolean>
  /** A screen that draws merchants calls this on mount and the returned function on unmount
   *  (`useEffect(() => wantTraffic(), [wantTraffic])`). The first want reads at once, so the
   *  merchants arrive with the screen rather than one beat later; after that the beat reads. */
  wantTraffic: () => () => void
  /** Drop the last refusal — a screen calls this when the player moves on. */
  dismissRefusal: () => void
}

// `fleetOf(world, id)` and `portOfFleet(world, fleet)` were deleted here on 2026-08-22 with zero
// callers anywhere in src, tests or scripts. Both took the WHOLE store as their first argument,
// which is the shape this file has since banned (see the selector rule above): a screen that
// called them would have had to subscribe to everything to use them. `find` on a served array is
// not a concept that needs an authority, and "where does her next order happen" — the real
// question the second one looked like it answered — turned out to be four different rules, one of
// which was a bug; it now lives, once, in domain/fleet as fleetPortCode/housePortCode.

/** THE SERVED COPIES, untouched (src/live/worldNames.ts): the store publishes them re-named for the
 *  viewer's language, and re-derives from these on a switch — never from an already-named copy. */
let servedSnapshot: WorldSnapshot | null = null
const servedMarkets = new Map<string, MarketView>()

/** The snapshot in the viewer's language, and the lookups built once from it. */
function snapshotLookups(served: WorldSnapshot) {
  const snapshot = namedSnapshot(served, getLocale())
  const portByCode: Record<string, SnapshotPort> = {}
  const portById: Record<string, SnapshotPort> = {}
  for (const p of snapshot.ports) {
    portByCode[p.code] = p
    portById[p.id] = p
  }
  const goodByCode: Record<string, SnapshotGood> = {}
  for (const g of snapshot.goods) goodByCode[g.code] = g
  const nationByCode: Record<string, SnapshotNation> = {}
  for (const nat of snapshot.nations) nationByCode[nat.code] = nat
  return { snapshot, portByCode, portById, goodByCode, nationByCode }
}

/**
 * WHAT A PORT CODE IS CALLED — the one reading of it.
 *
 * The server speaks in codes (`LIS`); a player has never been shown one and should not be. That
 * translation was hand-written seven times as `portByCode[code]?.name ?? code`, and an eighth was
 * about to be typed on Profile, which was printing a bare `LIS` where every other screen said
 * "Lisbon". Seven copies of a fallback is how a fallback drifts: one of them will one day print
 * the code, or an empty string, or "unknown".
 *
 * It takes the LOOKUP rather than the store because a screen selects primitives
 * (`useWorld((s) => s.portByCode)`) and never subscribes to the whole object — rule 4 above.
 *
 * FOLDED SO FAR: LedgerScreen, ProfileScreen, and — 2026-08-22 — CommandScreen (3 sites) and
 * PortScreen (3 sites: the one that was there, plus two the Port rewrite would otherwise have
 * ADDED, which is the whole reason a fallback reaches seven copies). STILL WRITING THEIR OWN:
 * `features/fleets/FleetsScreen.tsx:117,309`. Listed here rather than in a doc so the count cannot
 * be lost; re-derive it before trusting it.
 */
export function portNameOf(portByCode: Record<string, SnapshotPort>, code: string): string {
  return portByCode[code]?.name ?? code
}

/**
 * WHAT A NATION CODE IS CALLED — the one reading of it, and the second member of this family.
 *
 * Written the day the board shipped (0025) printing `PRT` and `ESP` beside every captain's name,
 * on a screen whose whole job is telling houses apart. The agent that built it REFUSED to write the
 * lookup table here and reported the gap instead, which is why there is one authority to write
 * rather than a seventh copy to find: 0028 serves `snapshot.nations`, so the answer now comes from
 * the world rather than from a table a screen keeps.
 *
 * The fallback is the CODE and not a word like "unknown", for `portNameOf`'s reason: a code is at
 * least true, and a screen printing "unknown" beside a real house hides the defect instead of
 * showing it.
 */
export function nationNameOf(
  nationByCode: Record<string, SnapshotNation>,
  code: string,
): string {
  return nationByCode[code]?.name ?? code
}

/**
 * THE COUNTRY A HARBOUR BELONGS TO TODAY (0143, docs/INFLUENCE.md D13) — the one client reading of
 * `world.allegiance`, which serves `public.port_nation`, the one server reading. No screen reads
 * `snapshot.ports[].nation` (that is the snapshot's copy, cached with the static world) or
 * `port.country` (the modern country's name) for a flag; tests/map.flag.spec.ts greps for it.
 * Undefined until the first read lands — a screen then prints no flag, never a guessed one.
 */
export function portNationOf(
  allegiance: Record<string, PortAllegiance>,
  code: string,
): PortAllegiance | undefined {
  return allegiance[code]
}

/** How long a flag answer is kept (0143). The daily count moves the flags once a day, and a
 *  company changing country is a verb that drops this entry by name (catalog.ts). */
const ALLEGIANCE_ASK_EVERY_MS = 60 * 60_000
/** The pairs this tab has already pressed into the record (loadSeries): one press per pair per session,
 *  because the press is idempotent on the server and the next tick is what starts the line. */
const seriesWatched = new Set<string>()
/** The one spelling of a series key. */
export const seriesKey = (portId: string, goodId: string, span: PriceSpan) => `${portId}|${goodId}|${span}`

/** THE ROSTER'S CADENCE (0118). A delta asks from the last answer's instant LESS this overlap: a tick
 *  that started before that instant commits its rows dated earlier, after it (tick_arrivals runs for
 *  up to a minute), and a row served twice is folded in twice, harmlessly. */
const ROSTER_OVERLAP_MS = 45_000
/** HOW OFTEN THE ROSTER IS ASKED (2026-10-14). Ships are placed in time between answers, so a beat in
 *  between only re-places the kept roster; the wire carries a delta at most this often. */
const ROSTER_ASK_EVERY_MS = 30_000
/** THE LEDGER IS RE-READ when the purse or a fleet moved, and otherwise at most this often — so an
 *  event that moves neither still lands, and an idle map does not re-read 19 KB every beat. */
const LEDGER_CATCH_UP_MS = 60_000
/** The whole roster again after this long, so a fact no delta carries (an eta a hazard moved
 *  mid-passage) is never older than this. */
const ROSTER_FULL_EVERY_MS = 10 * 60_000
/** A kept roster is written to storage at most this often — it is half a megabyte of text. */
const ROSTER_SAVE_EVERY_MS = 60_000

export const useWorld = create<LiveWorld>((set, get) => {
  /**
   * WHAT IS READ BACK AFTER A TRADE — the one spelling, for the two verbs that trade (`issue` and
   * `issueManifest`, 0083). The order may have executed already (a docked fleet acts at once), so
   * the world is read back rather than a local copy patched — the server's answer is the only
   * true one. `refresh()` re-reads the fleets (hold, cargo, version), the ledger (the purse) and
   * the house; then the market she lies at, because the trade moved the book — the stock fell,
   * the price stepped. 0071: the destination comparison that used to be re-read beside it is
   * gone with the rest of "where to sail". Not exported: it is this store's own tail, not a verb.
   */
  const afterTrade = async (fleet: FleetView | undefined): Promise<void> => {
    await get().refresh()
    // "The market she lies at" — in port or not is `domain/fleet`'s one rule, not a bare `port` read.
    const where = fleet ? whereabouts(fleet) : null
    const port = where?.kind === 'docked' ? get().portByCode[where.port] : null
    if (port) await get().loadMarket(port.id, true)
  }

  /**
   * THE VERB'S DOOR — the one spelling of what every write here does with its answer. A refusal
   * lands in `refusal` (rule 2) and the verb reports null; on success the last refusal is cleared
   * (unless `keepRefusal`: CANCEL and CLEAR never cleared it) and `after` reads back what the verb
   * moved — the server's answer is the only true one, never a local patch. `refreshOnStale`: an
   * E_STALE refusal means this tab's fleet version is behind the server's (another tab traded, or a
   * read is in flight), so the world is read back NOW and the player's next press sends the fresh
   * version instead of the same stale one again (PR #59 review SHOULD 7).
   */
  const verb = async <V>(
    call: Promise<RpcResult<V>>,
    after: (() => Promise<unknown>) | null,
    { keepRefusal = false, refreshOnStale = false }: { keepRefusal?: boolean; refreshOnStale?: boolean } = {},
  ): Promise<{ value: V } | null> => {
    const r = await call
    if (!r.ok) {
      set({ refusal: r.refusal })
      if (refreshOnStale && r.refusal.code === 'E_STALE') await get().refresh()
      return null
    }
    if (!keepRefusal) set({ refusal: null })
    if (after) await after()
    return { value: r.value }
  }

  /**
   * THE READ'S DOOR — an on-demand read lands its answer through `land`. A LOUD read (the screen IS
   * the answer: officers, skills, standings, a market) puts its refusal in `refusal`; a
   * SILENT one (a decoration that is true without it: history, reach, buffs) keeps what it had.
   * Each caller states which, beside its reason.
   */
  const loader = async <V>(
    call: Promise<RpcResult<V>>,
    land: (value: V, s: LiveWorld) => Partial<LiveWorld>,
    { loud }: { loud: boolean },
  ): Promise<void> => {
    const r = await call
    if (r.ok) set((s) => land(r.value, s))
    else if (loud) set({ refusal: r.refusal })
  }

  /**
   * THE ONE READER OF THE ROUTES BOOK (0092) — the beat's reading (`refresh()`) and the re-read
   * after a verb that moved the book alone (`loadRoutes`) are both this, so its two rules are
   * written once:
   *
   * A FAILED READ IS QUIET AND KEEPS THE LAST BOOK — the rule of every read that rides the beat
   * (loadMarket, loadOfficers, loadStandings): the next read corrects it. It sets no
   * refusal, because a refusal set here would overwrite the one a verb just drew. Until 2026-09-30
   * it blanked the book to null instead, so a failed read made the fold blink to "Loading…".
   *
   * AN OLDER ANSWER NEVER OVERWRITES A NEWER ONE. Reads are numbered as they are issued, and an
   * answer is applied only if no later-issued read has been applied already. Without this a
   * background beat that left before a save, delete, assign or pause and landed after it would
   * put the OLD book back over the verb's read-back — a deleted route reappearing for a beat, a
   * blink of its own. A read issued earlier can still carry a NEWER book (the verb committed
   * before it ran on the server); that is applied, and the verb's own read then lands the same
   * or a newer one — the book never goes backwards.
   */
  let routesAsked = 0
  let routesApplied = 0
  const readRoutes = async (): Promise<void> => {
    const seq = ++routesAsked
    const r = await worldStandingRoutes()
    if (!r.ok || seq < routesApplied) return
    routesApplied = seq
    set({ routes: r.value })
  }

  /**
   * THE ONE READER OF THE SEA TRAFFIC (0099) — `refresh()`'s, and the first want's. The routes
   * book's two rules hold here for the same reasons: a failed read is quiet and keeps the last
   * reading, and an older answer never overwrites a newer one.
   */
  // THE KEPT ROSTER (0118) and the instant of its last answer — see `readTraffic`.
  let roster = new Map<string, RosterFleet>()
  let rosterAt: string | null = null
  let rosterFullAtMs = 0
  let rosterLoadedFor: 'local' | 'cloud' | null = null
  let rosterAskedAtMs = 0
  let rosterSavedAtMs = 0
  /** THE SAVED ROSTER, read once per backend before the first read or paint (see seaRoster.ts). */
  const loadSavedRoster = (): void => {
    const mode = get().mode
    if (mode === null || rosterLoadedFor === mode) return
    rosterLoadedFor = mode
    let raw: string | null
    try {
      raw = localStorage.getItem(rosterKey(mode))
    } catch {
      raw = null
    }
    const saved = readSavedRoster(raw, Date.now(), ROSTER_FULL_EVERY_MS)
    if (saved && rosterAt === null) {
      roster = mergeRoster(new Map(), saved.fleets, true)
      rosterAt = saved.at
      rosterFullAtMs = saved.fullAtMs
    }
  }
  const saveRoster = (force: boolean): void => {
    const mode = get().mode
    if (mode === null || rosterAt === null || (!force && Date.now() - rosterSavedAtMs < ROSTER_SAVE_EVERY_MS)) return
    rosterSavedAtMs = Date.now()
    try {
      localStorage.setItem(rosterKey(mode), savedRosterText(rosterAt, rosterFullAtMs, roster))
    } catch {
      // A full or blocked storage is not an error: the next visit reads the whole roster once.
    }
  }
  /** The kept roster placed at this instant — the chart's `traffic`. */
  const placeRoster = (at: string): void => {
    const now = Date.now()
    const fleets = [...roster.values()].map((f) => trafficRowAt(f, now))
    set({ traffic: { enabled: true, at, fleets, total: fleets.length, omitted: 0 }, trafficReadAt: now })
  }
  // THE LEDGER'S LAST READ: what moved the last time it was read, and when (see `refresh`).
  let ledgerSig = ''
  let ledgerReadAtMs = 0
  let trafficAsked = 0
  let trafficApplied = 0
  /** THE LAST WANTER ALSO CANCELS WHAT IS ALREADY ON THE WIRE. Clearing `traffic` on release is not
   *  enough on its own: a read issued before the release lands after it and re-fills the store with
   *  a reading nobody is watching and nothing will refresh, which a remounted MAP then paints as
   *  the present — the teleport again, by a longer road (the 2026-10-10 review). Retiring the
   *  sequence here makes every read older than this moment a no-op, through the same ordering
   *  mechanism the reader already uses. */
  const dropTrafficInFlight = (): void => {
    trafficApplied = ++trafficAsked
    // THE ROSTER IS KEPT (2026-10-14). Its rows are placed in time from frozen facts, so a kept copy
    // painted later is placed at that later instant — no teleport — and a return to MAP shows every
    // ship at once and catches up with one delta.
  }
  // THE ROSTER (0118): every merchant once, then only the fleets whose state moved. Kept here, and
  // placed in time on every beat, so the chart draws every ship at any zoom and a pan reads nothing.
  const readTraffic = async (): Promise<void> => {
    const seq = ++trafficAsked
    loadSavedRoster()
    rosterAskedAtMs = Date.now()
    const full = rosterAt === null || Date.now() - rosterFullAtMs > ROSTER_FULL_EVERY_MS
    const since = full || rosterAt === null ? null : new Date(Date.parse(rosterAt) - ROSTER_OVERLAP_MS).toISOString()
    const r = await worldSeaRoster(since)
    if (!r.ok || seq < trafficApplied) return
    trafficApplied = seq
    if (!r.value.enabled) {
      roster = new Map()
      rosterAt = null
      try {
        const mode = get().mode
        if (mode) localStorage.removeItem(rosterKey(mode))
      } catch {
        // nothing kept, nothing to forget
      }
      set({ traffic: { enabled: false, at: r.value.at, fleets: [], total: 0, omitted: 0 }, trafficReadAt: Date.now() })
      return
    }
    roster = mergeRoster(roster, r.value.fleets, r.value.full)
    rosterAt = r.value.at
    if (r.value.full) rosterFullAtMs = Date.now()
    placeRoster(r.value.at)
    saveRoster(r.value.full)
  }

  return {
  phase: 'idle',
  fatal: null,
  mode: null,
  snapshot: null,
  seaNav: null,
  reaches: {},
  fleets: [],
  player: null,
  officers: null,
  skills: null,
  standings: null,
  routes: null,
  routeBoard: null,
  routeBoardAt: null,
  routeBoardFailed: false,
  traffic: null,
  trafficWanted: 0,
  trafficReadAt: null,
  buffs: {},
  series: {},
  ducats: null,
  events: [],
  markets: {},
  reading: false,
  refusal: null,
  readAt: null,
  readEveryMs: READ_MAX_MS,
  portByCode: {},
  nationByCode: {},
  portById: {},
  goodByCode: {},
  allegiance: {},

  open: async () => {
    if (get().phase !== 'idle') return
    set({ phase: 'opening' })

    // initRpc() BOOTS A DATABASE, and a database can fail to boot — a migration that will not
    // apply throws here rather than returning a refusal, because it happens below the RPC seam
    // where the refusal contract starts. Letting it escape left every screen on "Opening the
    // world…" for ever, which is what a swallowed exception looks like from the player's side.
    // A failure to open is a failure to render, so it becomes one.
    let mode: 'local' | 'cloud'
    try {
      mode = await initRpc()
    } catch (err) {
      set({
        phase: 'failed',
        fatal: {
          code: 'E_WORLD_UNAVAILABLE',
          sentence:
            'The world could not be opened in this browser. ' +
            (err instanceof Error ? err.message : String(err)),
          fixes: [],
          source: 'fault',
        },
      })
      return
    }

    const snap = await worldSnapshot()
    if (!snap.ok) {
      set({ phase: 'failed', fatal: snap.refusal, mode })
      return
    }
    // THE SEA RIDES WITH THE WORLD. Without the raster no course can be proposed and SAIL — the
    // game's core verb — is dead, so a world without its water is a failed open, not a degraded
    // one (§7C: the else branch would be a different product wearing this one's name).
    const sea = await worldSeaRaster()
    if (!sea.ok) {
      set({ phase: 'failed', fatal: sea.refusal, mode })
      return
    }
    servedSnapshot = snap.value
    const named = snapshotLookups(snap.value)

    // THE WORLD IS PUBLISHED WITH ITS FLEETS, IN ONE `set()` (2026-10-08). This used to publish the
    // snapshot first and THEN await the first read, so for the whole of that read the store said
    // "the world is here, and you own no fleets" — `snapshot` set, `fleets: []`, `readAt: null`.
    // COMMAND gates on the snapshot, and a captain who owns Gaivota was told "No fleets yet. Start
    // your company…" on a cold load of the live site (tests/firstRead.empty.spec.ts watches it).
    // The read does not need the snapshot (it is fleets, ledger, house and routes), so it runs
    // first and the world appears with its fleets already in it: there is no state in which a
    // screen can see `snapshot` without the first fleets read having landed. `phase: 'ready'`
    // lands in the same `set()`, so the two readings of "the world is up" cannot disagree.
    const seaNav = navFromServed(sea.value)
    // 0135 — every served hull class's rig and size, so the chart draws each of the 55 as one of its
    // eight silhouettes (src/chart/glyphs.ts `hullShapeOf`). Before the first fleets read, so no hull
    // is ever drawn from a snapshot the store holds but the chart has not seen.
    registerHullClasses(snap.value.ship_classes)
    await get().refresh()
    set({
      ...named,
      seaNav,
      mode,
      // A world that answered snapshot() but not fleets() is still a world worth showing: the
      // failure is already in `fatal` (refresh set `phase: 'failed'`) and the screens render it.
      ...(get().phase === 'failed' ? {} : { phase: 'ready' as const }),
    })
  },

  refresh: async () => {
    set({ reading: true })
    // The house rides along with the fleets: it is the same read cadence (fame is derived from the
    // ledger, so it moves whenever the ledger does) and a separate poll would be a second clock.
    const [fleets, player] = await Promise.all([worldFleets(), worldPlayer()])
    if (!fleets.ok) {
      set({ reading: false, fatal: fleets.refusal, phase: 'failed' })
      return
    }
    // THE LEDGER ONLY WHEN SOMETHING MOVED (2026-10-14): the purse, or a fleet's version or state —
    // every trade, arrival and order bumps one — else once a LEDGER_CATCH_UP_MS.
    const sig =
      `${player.ok ? (player.value.player?.ducats ?? '-') : 'x'}|` +
      fleets.value.map((f) => `${f.id}:${f.version}:${f.status}`).join(',')
    const ledger =
      sig !== ledgerSig || Date.now() - ledgerReadAtMs > LEDGER_CATCH_UP_MS ? await worldLedger() : null
    if (ledger?.ok) {
      ledgerSig = sig
      ledgerReadAtMs = Date.now()
    }
    // THE ROUTES RIDE THE SAME BEAT (2026-09-30), for the same reason: COMMAND's fold and FLEETS'
    // caption each re-read them on `readAt`, a second and third clock. AFTER the fleets, never
    // beside them: `world.fleets()` (0009) and `world.standing_routes()` (0092) each settle every
    // fleet they serve, and `voyage.settle` takes `for update` on the fleet row (0007:916) in
    // whatever order the loop yields — two such transactions in flight at once, over two or more
    // route fleets, can deadlock, and if the fleets read is the one Postgres kills this refresh
    // sets `phase: 'failed'` and the shell stops reading for good. Read one after the other and
    // the routes read's settle is a no-op. On the fatal branch above the routes are not read at
    // all and the last book stands.
    await readRoutes()
    // 0143: THE FLAGS — a read that takes no lock and changes once a day. The cache keeps the
    // answer for the hour (loadAllegiance's lifetime), so this call is a memory read on 59 beats
    // out of 60; the hour now lives with the answer it describes, not in a second counter here.
    await get().loadAllegiance()
    // THE MERCHANTS RIDE THE SAME BEAT, after the routes and only while a screen wants them. This
    // read takes no lock, but it keeps the one order (fleets → routes → traffic) so the deadlock
    // rule above stays one rule.
    if (get().trafficWanted > 0) {
      if (rosterAt === null || Date.now() - rosterAskedAtMs >= ROSTER_ASK_EVERY_MS) await readTraffic()
      else if (roster.size > 0) placeRoster(rosterAt)
    }
    set({
      fleets: fleets.value,
      // A failed player read leaves the house NULL rather than fatal, for the same reason a failed
      // ledger read only nulls the purse: the world is still playable without it.
      player: player.ok ? player.value.player : null,
      ...(ledger === null
        ? {}
        : { ducats: ledger.ok ? (ledger.value.ducats ?? null) : null, events: ledger.ok ? ledger.value.events : [] }),
      reading: false,
      readAt: Date.now(),
    })
  },

  loadMarket: async (portId, force = false) => {
    // KEPT UNTIL THE MARKET'S OWN EDGE (resourceCache, `msUntilEdge`): the payload carries the
    // instant the whole market next steps, so a remount inside that slot draws the kept prices and
    // touches no wire. A trade forces it (`afterTrade`); past the edge the next read asks.
    const key = `worldMarket|${portId}`
    if (!force) {
      const held = peekResource<MarketView>(key)
      if (held !== undefined) {
        if (get().markets[portId] === undefined) {
          servedMarkets.set(portId, held)
          set((s) => ({ markets: { ...s.markets, [portId]: namedMarket(held, getLocale()) } }))
        }
        return
      }
    }
    await loader(
      readResource(key, () => worldMarket(portId), (v) => msUntilEdge(v.clock), force),
      (v, s) => {
        servedMarkets.set(portId, v)
        return { markets: { ...s.markets, [portId]: namedMarket(v, getLocale()) } }
      },
      { loud: true },
    )
  },

  // THE SERIES READ (0226): one read per (port, good, span); a payload already kept is not asked again
  // in this session (the beat does not re-read charts — a chart's line moves one point a slot). A pair the
  // record does not keep yet comes back `recording: false` with no points: the store presses it into the
  // record ONCE (cmd.watch_price, idempotent) and nothing else — the next tick writes the first point, and
  // the next open of the chart reads it. A failed read or press is SILENT (a decoration).
  loadSeries: (portId, goodId, span) => {
    const key = seriesKey(portId, goodId, span)
    if (get().series[key] !== undefined) return Promise.resolve()
    const cacheKey = `worldPriceSeries|${key}`
    const pressWatch = (v: PriceSeries | undefined) => {
      const pair = `${portId}|${goodId}`
      if (v && !v.recording && !seriesWatched.has(pair)) {
        seriesWatched.add(pair)
        void cmdWatchPrice(portId, goodId)
      }
    }
    const held = peekResource<PriceSeries>(cacheKey)
    if (held !== undefined) {
      set((s) => ({ series: { ...s.series, [key]: held } }))
      pressWatch(held)
      return Promise.resolve()
    }
    // A SERIES IS STATIC PER CHAIN (a chart's line moves one point a slot, not per tab): kept for
    // the session, and a pair the record does not keep yet is pressed into it once.
    return loader(readResource(cacheKey, () => worldPriceSeries(portId, goodId, span), SESSION_MS), (v, s) => ({
      series: { ...s.series, [key]: v },
    }), { loud: false }).then(() => pressWatch(get().series[key]))
  },

  // A FAILED REACH READ IS SILENT, like history: the picker still lists every harbour, only
  // unordered by distance — a truthful, lesser answer (§7C's mirror), never a fabricated figure.
  loadReach: async (portId) => {
    if (get().reaches[portId]) return
    const key = `worldReach|${portId}`
    const held = peekResource<ReachPayload>(key)
    if (held !== undefined) {
      set((s) => ({ reaches: { ...s.reaches, [portId]: held } }))
      return
    }
    // A reach never changes within a chain version (0039): session lifetime.
    await loader(readResource(key, () => worldReach(portId), SESSION_MS), (v, s) => ({
      reaches: { ...s.reaches, [portId]: v },
    }), { loud: false })
  },

  // A FAILED FLAG READ IS SILENT: the last flags stand (or none, before the first), which is a
  // truthful lesser answer — the city line then prints no flag, never a stale guess as new.
  loadAllegiance: async () => {
    // The flags move once a day (0143); the hour is the read's lifetime, so the beat's call is a
    // memory read on 59 beats out of 60 and the map's port-open call is the same one answer.
    const key = 'worldAllegiance'
    const held = peekResource<AllegianceView>(key)
    if (held !== undefined) {
      if (Object.keys(get().allegiance).length === 0) {
        set({ allegiance: Object.fromEntries(held.ports.map((p) => [p.port, p])) })
      }
      return
    }
    await loader(readResource(key, () => worldAllegiance(), ALLEGIANCE_ASK_EVERY_MS), (v) => ({
      allegiance: Object.fromEntries(v.ports.map((p) => [p.port, p])),
    }), { loud: false })
  },

  // THE CATALOGUES ARE KEPT FOR THE SESSION (resourceCache): the officer roster and the skill book
  // cannot change by looking at them, and the verbs that DO change them name them in catalog.ts
  // (`invalidates`), so a hire/study drops exactly that entry. `force` is for a screen whose own
  // served edge has passed (PortAcademy's next level).
  loadOfficers: async (force = false) => {
    const key = 'worldOfficers'
    if (!force) {
      const held = peekResource<OfficerRoster>(key)
      if (held !== undefined) {
        if (get().officers === null) set({ officers: held })
        return
      }
    }
    await loader(readResource(key, () => worldOfficers(), SESSION_MS, force), (officers) => ({ officers }), {
      loud: true,
    })
  },

  loadSkills: async (force = false) => {
    const key = 'worldSkills'
    if (!force) {
      const held = peekResource<SkillBook>(key)
      if (held !== undefined) {
        if (get().skills === null) set({ skills: held })
        return
      }
    }
    await loader(readResource(key, () => worldSkills(), SESSION_MS, force), (skills) => ({ skills }), { loud: true })
  },

  // A FAILED BOARD READ IS LOUD, unlike the history read. That one decorates a price that is true
  // without them; the board IS the screen, so a RANK tab that silently kept yesterday's order would
  // be showing a standing nobody holds.
  loadStandings: async (limit = null, force = false) => {
    const key = `worldStandings|${limit ?? '-'}`
    if (!force) {
      const held = peekResource<StandingsBoard>(key)
      if (held !== undefined) {
        if (get().standings === null) set({ standings: held })
        return
      }
    }
    // The board rides the world's beat while RANK is open (RankScreen's readAt effect): one beat
    // is its lifetime, so a remount in that window draws the kept board.
    await loader(readResource(key, () => worldStandings(limit), () => get().readEveryMs, force), (standings) => ({
      standings,
    }), { loud: true })
  },

  loadRouteBoard: async (force = false) => {
    // A REFUSAL IS NOT A REFUSAL BANNER HERE. The board is consulted deliberately and its own
    // screen prints "the last read was refused — these are the figures from before it", which is
    // more use than a world-level refusal the player has to dismiss to get back to the list.
    const key = 'worldRouteBoard'
    if (!force) {
      const held = peekResource<RouteBoard>(key)
      if (held !== undefined) {
        if (get().routeBoard === null) {
          set({ routeBoard: held, routeBoardAt: Date.now(), routeBoardFailed: false })
        }
        return
      }
    }
    // ASKED ONCE, THEN LEFT ALONE (the store's own rule since 0106): session lifetime. The ROUTES
    // screen's refresh press forces it, and no beat calls it.
    const r = await readResource(key, () => worldRouteBoard(), SESSION_MS, force)
    if (r.ok) set({ routeBoard: r.value, routeBoardAt: Date.now(), routeBoardFailed: false })
    else set({ routeBoardFailed: true })
  },

  // A FAILED BUFF READ IS SILENT, and this is the one place that choice has a second consequence:
  // this read is also what winds the calendar where pg_cron is absent (0026). A quay that does not
  // know a fair is on still quotes the right price — `world.market` reads the spread itself — so the
  // cost of failing quietly is a missing sign, never a wrong number.
  loadBuffs: async (portId, force = false) => {
    const key = `worldBuffs|${portId}`
    if (!force) {
      const held = peekResource<BuffsView>(key)
      if (held !== undefined) {
        if (get().buffs[portId] === undefined) set((s) => ({ buffs: { ...s.buffs, [portId]: held } }))
        return
      }
    }
    // A fair's edge forces (PortFair); otherwise one beat is the lifetime.
    await loader(readResource(key, () => worldBuffs(portId), () => get().readEveryMs, force), (v, s) => ({
      buffs: { ...s.buffs, [portId]: v },
    }), { loud: false })
  },

  // The re-read after a verb that moved the book alone (save, delete). The beat's reading is
  // `refresh()`'s; both are `readRoutes`, the one reader.
  loadRoutes: () => readRoutes(),

  saveRoute: async (routeId, name, stops) =>
    (await verb(cmdStandingRouteSave(routeId, name, stops), () => get().loadRoutes()))?.value.id ?? null,

  deleteRoute: async (routeId) =>
    (await verb(cmdStandingRouteDelete(routeId), () => get().loadRoutes())) !== null,

  // ASSIGN AND RESUME MOVE THE FLEET NOW (the route writes her orders and the queue runs them), so
  // both read the world back — the queue, the purse and the route — never a local patch.
  // refresh() reads the routes with the fleets — one read, not two racing.
  assignRoute: async (routeId, fleetId) =>
    (await verb(cmdStandingRouteAssign(routeId, fleetId), get().refresh)) !== null,

  pauseRoute: async (routeId, paused) =>
    (await verb(cmdStandingRoutePause(routeId, paused), get().refresh)) !== null,

  hireOfficer: async (code, fleetId) =>
    (await verb(cmdHireOfficer(code, fleetId), () => Promise.all([get().loadOfficers(), get().refresh()]))) !== null,

  enrollSkill: async (code, fleetId) =>
    (await verb(cmdSkillEnroll(code, fleetId), () => Promise.all([get().loadSkills(), get().refresh()]))) !== null,
  // A refused queue still re-reads the book: the server's queue is the only true one.
  setSkillQueue: async (entries) => {
    const r = await verb(cmdSkillQueueSet(entries), () => get().loadSkills())
    if (r === null) await get().loadSkills()
    return r !== null
  },

  // ONE ATTEMPT AT A BARGAIN (0022). A WRITE, so it lives here rather than in a read hook.
  //
  // IT RETURNS THE ATTEMPT, WON OR LOST, and the caller renders the server's own `message`. A lost
  // haggle is NOT a refusal — the factor heard you and said no, which is the game working — so it
  // comes back `ok:true, won:false` and must never be dressed as an error. A real refusal
  // (E_NOT_DOCKED, E_NO_STOCK, E_NO_CARGO, E_HAGGLE_SPENT) arrives through the usual `refusal`
  // channel, in the server's own words and with the server's own fixes.
  //
  // A WON BARGAIN CHANGES WHAT A TRADE COSTS, so the world is read back: `refresh()` bumps `readAt`,
  // which is what `useBuyCapacity` and `useHaggleState` key on, so the ceiling and the estimate are
  // re-asked at the new spread rather than standing stale. THE MARKET IS DELIBERATELY NOT RE-READ:
  // the port's PUBLISHED price has not moved, and 0022 refused to make it move for exactly this
  // reason — a bargain is a better fill inside the port's cut, not a different world.
  haggle: async (fleetId, goodId, side) => (await verb(cmdHaggle(fleetId, goodId, side), get().refresh))?.value ?? null,

  issue: async (fleetId, text, path = null) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    return (await verb(cmdIssue(fleetId, text, fleet?.version ?? null, path), () => afterTrade(fleet))) !== null
  },

  issueLines: async (fleetId, lines) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    return (
      (await verb(cmdIssueLines(fleetId, lines, fleet?.version ?? null), () => afterTrade(fleet), { refreshOnStale: true })) !== null
    )
  },

  issueManifest: async (fleetId, lines) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    const done = await verb(cmdTradeBasket(fleetId, lines, fleet?.version ?? null), () => afterTrade(fleet), {
      refreshOnStale: true,
    })
    return done?.value ?? null
  },

  // The same door-shape as issueManifest: version from the fleet in hand, E_STALE read back now.
  fulfil: async (fleetId, contractId) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    const done = await verb(cmdFulfil(fleetId, contractId, fleet?.version ?? null), () => afterTrade(fleet), {
      refreshOnStale: true,
    })
    return done?.value ?? null
  },

  preview: async (fleetId, text, path = null) => (await verb(cmdPreview(fleetId, text, path), null))?.value ?? null,

  cancel: async (fleetId, index = null) =>
    (await verb(cmdCancel(fleetId, index), get().refresh, { keepRefusal: true })) !== null,

  clear: async (fleetId) => (await verb(cmdClear(fleetId), get().refresh, { keepRefusal: true })) !== null,

  // THE HELM ORDER AT SEA (0039). The server settles her first, truncates the voyage at her
  // closed-form position, and departs the onward passage through the one parser and mover — so
  // this action is read-back like every other: the world is re-read, never locally patched.
  divert: async (fleetId, destPortId, destPoint = null, path = null) =>
    (await verb(cmdDivert(fleetId, destPortId, destPoint, path), get().refresh)) !== null,

  wantTraffic: () => {
    set((s) => ({ trafficWanted: s.trafficWanted + 1 }))
    // A KEPT OR SAVED ROSTER PAINTS AT ONCE, placed at this instant; the beat below catches it up.
    if (get().trafficWanted === 1 && get().traffic === null) {
      loadSavedRoster()
      if (rosterAt !== null && roster.size > 0) placeRoster(rosterAt)
    }
    // THE FIRST WANT RIDES A BEAT; IT NEVER READS ALONE (2026-10-10). A lone read lands AFTER the
    // beat's `readAt`, so 0075's drift then extrapolates the merchants from an instant EARLIER than
    // the positions it was given and overshoots until the next beat pulls them back: measured on
    // an in-app Map → Fleets → Map, all 32 hulls leapt 40-195 px when the mount-time reading landed
    // and nearly every one stepped 5-20 px BACK half a second later. `refresh()` reads the traffic
    // inside the same beat that sets `readAt` (it is already counted now, the counter is up), so
    // the position and the instant it is drifted from come from one reading. Never on top of a read
    // in flight — AppShell's own beat states the reason; that read will pick the traffic up anyway.
    if (get().trafficWanted === 1 && get().phase === 'ready' && !get().reading) void get().refresh()
    let released = false
    return () => {
      if (released) return
      released = true
      // THE LAST WANTER TAKES THE READING WITH IT. Keeping it meant a remounted MAP or PORT painted
      // the merchants where they were MINUTES ago — the chart draws `traffic` the moment it mounts —
      // and then every hull teleported when the first fresh reading landed. A chart with no
      // merchants on it for one beat is honest; a chart with merchants in last session's places is
      // not (worldStore rule 1: a read is the catch-up).
      let last = false
      set((s) => {
        const left = Math.max(0, s.trafficWanted - 1)
        last = left === 0
        return last
          ? { trafficWanted: 0, traffic: null, trafficReadAt: null }
          : { trafficWanted: left }
      })
      if (last) dropTrafficInFlight()
    }
  },

  dismissRefusal: () => set({ refusal: null }),
  }
})

// A LANGUAGE SWITCH re-names the world in place: one `set()`, so every screen re-renders with the
// new names and nothing is fetched again.
subscribeLocale(() => {
  if (!servedSnapshot) return
  const locale = getLocale()
  const markets: Record<string, MarketView> = {}
  for (const [id, m] of servedMarkets) markets[id] = namedMarket(m, locale)
  useWorld.setState({ ...snapshotLookups(servedSnapshot), markets })
})
