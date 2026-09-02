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
// object on every `set()`. `refresh()` alone sets twice — `{busy: true}` on the way in, the
// payload on the way out — so ONE read re-rendered every bare subscriber twice over, whether or
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
  cmdHaggle,
  cmdHireOfficer,
  cmdIssue,
  cmdPostOfficer,
  cmdPreview,
  cmdProvisionPresetApply,
  cmdProvisionPresetDelete,
  cmdProvisionPresetSave,
  cmdStudySkill,
  initRpc,
  worldFleets,
  worldLedger,
  worldMarket,
  worldOfficers,
  worldPlayer,
  worldPriceHistory,
  worldSkills,
  worldStandings,
  worldBuffs,
  worldSnapshot,
  worldProvisionPresets,
  worldSeaRaster,
  worldReach,
} from '../lib/rpc'
import { navFromServed, type SeaNav } from '../lib/sea'
import type {
  FleetView,
  HaggleAttempt,
  LedgerEvent,
  MarketView,
  OfficerRoster,
  PlayerHouse,
  PreviewResult,
  PriceHistory,
  ProvisionPresetBook,
  Refusal,
  ReachPayload,
  SkillBook,
  SnapshotNation,
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

  /** The static world: ports, goods, ship classes, config knobs, the verb grammar. */
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
  /** The book of standing orders (0034). Null until FLEETS asks for it — it is that tab's card,
   *  and the server tops fleets up on arrival whether or not anyone is looking. */
  presets: ProvisionPresetBook | null
  /** What is on at the quay (0026), keyed by port id — a fair is a PORT's fact, not the world's. */
  buffs: Record<string, BuffsView>
  /** One port's remembered prices, keyed by port id (0013). Fetched beside its market. */
  history: Record<string, PriceHistory>

  /** The purse, and the events behind it. */
  ducats: number | null
  events: LedgerEvent[]
  /** One port's prices, keyed by port id. Fetched on demand; the Market tab drives it. */
  markets: Record<string, MarketView>

  /** True while a refresh is in flight — for a quiet indicator, never for a blocking spinner. */
  busy: boolean
  /** The last refusal any command produced, for the screen that issued it to render. */
  refusal: Refusal | null
  /** When the last successful read landed (ms since epoch), so a screen can say "as of". */
  readAt: number | null

  // ── lookups, built once per snapshot ─────────────────────────────────────────────────────────
  portByCode: Record<string, SnapshotPort>
  nationByCode: Record<string, SnapshotNation>
  portById: Record<string, SnapshotPort>
  goodByCode: Record<string, SnapshotGood>

  // ── what a screen may do ─────────────────────────────────────────────────────────────────────
  /** Open the world. Idempotent; AppShell calls it once. */
  open: () => Promise<void>
  /** Read again — fleets and ledger. THIS IS HOW TIME PASSES. */
  refresh: () => Promise<void>
  /** Fetch (and cache) one port's market. */
  loadMarket: (portId: string) => Promise<void>
  /** Fetch (and cache) one port's remembered prices. */
  loadHistory: (portId: string) => Promise<void>
  /** Fetch (and cache) one place's sailed distances to everywhere (0039). */
  loadReach: (portId: string) => Promise<void>
  /** Fetch (and cache) where the goods of one port pay more. Naming the fleet lying there is what
   *  makes the quantities hers rather than the server's stated default. */
  /** Fetch the roster and the school. Idempotent; screens call them on mount. */
  loadOfficers: () => Promise<void>
  loadSkills: () => Promise<void>
  loadStandings: (limit?: number | null) => Promise<void>
  loadBuffs: (portId: string) => Promise<void>
  /** Fetch the book of standing orders. FLEETS calls it on mount and after every preset verb. */
  loadPresets: () => Promise<void>
  /** Write or adjust a standing order (0034). Re-reads the book — the server's answer is the only
   *  true one, the same rule every other verb here follows. */
  savePreset: (presetId: string | null, name: string | null, days: number | null) => Promise<boolean>
  deletePreset: (presetId: string) => Promise<boolean>
  /** Put a fleet under an order, or clear it with null. Nothing is bought now — the order fires
   *  when she makes port, and only there — so only the book is re-read, never the fleets. */
  applyPreset: (fleetId: string, presetId: string | null) => Promise<boolean>
  /** Sign an officer, post one, or study a level. Each re-reads what it changed, because the
   *  server's answer is the only true one — no local patching (the `issue` rule). */
  hireOfficer: (code: string, fleetId: string | null) => Promise<boolean>
  postOfficer: (code: string, fleetId: string | null) => Promise<boolean>
  studySkill: (code: string, fleetId: string) => Promise<boolean>

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

export const useWorld = create<LiveWorld>((set, get) => ({
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
  presets: null,
  buffs: {},
  history: {},
  ducats: null,
  events: [],
  markets: {},
  busy: false,
  refusal: null,
  readAt: null,
  portByCode: {},
  nationByCode: {},
  portById: {},
  goodByCode: {},

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
    const portByCode: Record<string, SnapshotPort> = {}
    const portById: Record<string, SnapshotPort> = {}
    for (const p of snap.value.ports) {
      portByCode[p.code] = p
      portById[p.id] = p
    }
    const goodByCode: Record<string, SnapshotGood> = {}
    for (const g of snap.value.goods) goodByCode[g.code] = g
    const nationByCode: Record<string, SnapshotNation> = {}
    for (const nat of snap.value.nations) nationByCode[nat.code] = nat

    set({
      snapshot: snap.value,
      seaNav: navFromServed(sea.value),
      portByCode,
      portById,
      goodByCode,
      nationByCode,
      mode,
    })
    await get().refresh()
    // A world that answered snapshot() but not fleets() is still a world worth showing: the
    // failure is already in `fatal` and the screens render it in place.
    if (get().phase !== 'failed') set({ phase: 'ready' })
  },

  refresh: async () => {
    set({ busy: true })
    // The house rides along with the fleets: it is the same read cadence (fame is derived from the
    // ledger, so it moves whenever the ledger does) and a separate poll would be a second clock.
    const [fleets, ledger, player] = await Promise.all([worldFleets(), worldLedger(), worldPlayer()])
    if (!fleets.ok) {
      set({ busy: false, fatal: fleets.refusal, phase: 'failed' })
      return
    }
    set({
      fleets: fleets.value,
      // A failed player read leaves the house NULL rather than fatal, for the same reason a failed
      // ledger read only nulls the purse: the world is still playable without it.
      player: player.ok ? player.value.player : null,
      ducats: ledger.ok ? (ledger.value.ducats ?? null) : null,
      events: ledger.ok ? ledger.value.events : [],
      busy: false,
      readAt: Date.now(),
    })
  },

  loadMarket: async (portId) => {
    const r = await worldMarket(portId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return
    }
    set((s) => ({ markets: { ...s.markets, [portId]: r.value } }))
  },

  loadHistory: async (portId) => {
    const r = await worldPriceHistory(portId)
    if (!r.ok) return
    set((s) => ({ history: { ...s.history, [portId]: r.value } }))
  },

  // A FAILED REACH READ IS SILENT, like history: the picker still lists every harbour, only
  // unordered by distance — a truthful, lesser answer (§7C's mirror), never a fabricated figure.
  loadReach: async (portId) => {
    if (get().reaches[portId]) return
    const r = await worldReach(portId)
    if (!r.ok) return
    set((s) => ({ reaches: { ...s.reaches, [portId]: r.value } }))
  },

  loadOfficers: async () => {
    const r = await worldOfficers()
    if (r.ok) set({ officers: r.value })
    else set({ refusal: r.refusal })
  },

  loadSkills: async () => {
    const r = await worldSkills()
    if (r.ok) set({ skills: r.value })
    else set({ refusal: r.refusal })
  },

  // A FAILED BOARD READ IS LOUD, unlike the history read. That one decorates a price that is true
  // without them; the board IS the screen, so a RANK tab that silently kept yesterday's order would
  // be showing a standing nobody holds.
  loadStandings: async (limit = null) => {
    const r = await worldStandings(limit)
    if (r.ok) set({ standings: r.value })
    else set({ refusal: r.refusal })
  },

  // A FAILED BUFF READ IS SILENT, and this is the one place that choice has a second consequence:
  // this read is also what winds the calendar where pg_cron is absent (0026). A quay that does not
  // know a fair is on still quotes the right price — `world.market` reads the spread itself — so the
  // cost of failing quietly is a missing sign, never a wrong number.
  loadBuffs: async (portId) => {
    const r = await worldBuffs(portId)
    if (!r.ok) return
    set((s) => ({ buffs: { ...s.buffs, [portId]: r.value } }))
  },

  // A FAILED BOOK READ IS LOUD, for the standings' reason: the card IS the book, and a Presets
  // panel silently showing yesterday's orders would let a player believe a standing order stands
  // when it does not.
  loadPresets: async () => {
    const r = await worldProvisionPresets()
    if (r.ok) set({ presets: r.value })
    else set({ refusal: r.refusal })
  },

  savePreset: async (presetId, name, days) => {
    const r = await cmdProvisionPresetSave(presetId, name, days)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await get().loadPresets()
    return true
  },

  deletePreset: async (presetId) => {
    const r = await cmdProvisionPresetDelete(presetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await get().loadPresets()
    return true
  },

  applyPreset: async (fleetId, presetId) => {
    const r = await cmdProvisionPresetApply(fleetId, presetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await get().loadPresets()
    return true
  },

  hireOfficer: async (code, fleetId) => {
    const r = await cmdHireOfficer(code, fleetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await Promise.all([get().loadOfficers(), get().refresh()])
    return true
  },

  postOfficer: async (code, fleetId) => {
    const r = await cmdPostOfficer(code, fleetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await Promise.all([get().loadOfficers(), get().refresh()])
    return true
  },

  studySkill: async (code, fleetId) => {
    const r = await cmdStudySkill(code, fleetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await Promise.all([get().loadSkills(), get().refresh()])
    return true
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
  haggle: async (fleetId, goodId, side) => {
    const r = await cmdHaggle(fleetId, goodId, side)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return null
    }
    set({ refusal: null })
    await get().refresh()
    return r.value
  },

  issue: async (fleetId, text, path = null) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    const r = await cmdIssue(fleetId, text, fleet?.version ?? null, path)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    // The order may have executed already (a docked fleet acts at once), so read the world back
    // rather than patching a local copy of it — the server's answer is the only true one.
    await get().refresh()
    const port = fleet?.port ? get().portByCode[fleet.port] : null
    // The order moved the book — the stock fell, the price stepped — so the market is re-read.
    // 0071: the destination comparison that used to be re-read beside it is gone with the rest of
    // "where to sail".
    if (port) await get().loadMarket(port.id)
    return true
  },

  preview: async (fleetId, text, path = null) => {
    const r = await cmdPreview(fleetId, text, path)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return null
    }
    set({ refusal: null })
    return r.value
  },

  cancel: async (fleetId, index = null) => {
    const r = await cmdCancel(fleetId, index)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    await get().refresh()
    return true
  },

  clear: async (fleetId) => {
    const r = await cmdClear(fleetId)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    await get().refresh()
    return true
  },

  // THE HELM ORDER AT SEA (0039). The server settles her first, truncates the voyage at her
  // closed-form position, and departs the onward passage through the one parser and mover — so
  // this action is read-back like every other: the world is re-read, never locally patched.
  divert: async (fleetId, destPortId, destPoint = null, path = null) => {
    const r = await cmdDivert(fleetId, destPortId, destPoint, path)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    await get().refresh()
    return true
  },

  dismissRefusal: () => set({ refusal: null }),
}))
