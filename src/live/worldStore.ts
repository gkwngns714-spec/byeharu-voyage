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
// 3. NUMBERS COME FROM THE SERVER. Speed, endurance, prices, %NBR, voyage position: all of them
//    are computed inside the transaction that owns them. The client's job is to print them. There
//    is no second implementation of any of it on this side of the wire.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { create } from 'zustand'
import {
  cmdCancel,
  cmdClear,
  cmdHireOfficer,
  cmdIssue,
  cmdPostOfficer,
  cmdPreview,
  cmdStudySkill,
  initRpc,
  worldFleets,
  worldLedger,
  worldMarket,
  worldOfficers,
  worldPlayer,
  worldPriceHistory,
  worldSkills,
  worldSnapshot,
} from '../lib/rpc'
import type {
  FleetView,
  LedgerEvent,
  MarketView,
  OfficerRoster,
  PlayerHouse,
  PreviewResult,
  PriceHistory,
  Refusal,
  SkillBook,
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

  /** The static world: ports, legs, goods, ship classes, config knobs, the verb grammar. */
  snapshot: WorldSnapshot | null
  /** The player's fleets, ships, cargo, queue and voyage position. Refetching this IS the clock. */
  fleets: FleetView[]
  /** The house itself — name, nation, counts and DERIVED fame (0014). Null for a signed-in
   *  account that has not signed the book: a state, not a failure. */
  player: PlayerHouse | null
  /** The officer roster and the school, fetched on demand — neither changes while you look at it. */
  officers: OfficerRoster | null
  skills: SkillBook | null
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
  /** Fetch the roster and the school. Idempotent; screens call them on mount. */
  loadOfficers: () => Promise<void>
  loadSkills: () => Promise<void>
  /** Sign an officer, post one, or study a level. Each re-reads what it changed, because the
   *  server's answer is the only true one — no local patching (the `issue` rule). */
  hireOfficer: (code: string, fleetId: string | null) => Promise<boolean>
  postOfficer: (code: string, fleetId: string | null) => Promise<boolean>
  studySkill: (code: string, fleetId: string) => Promise<boolean>

  /** Issue an order. The string is the whole contract (F.4) — the tap-builder composes the same
   *  string a keyboard would. Refreshes on success so the queue and purse are never stale. */
  issue: (fleetId: string, text: string) => Promise<boolean>
  /** Dry-run the same string: the server executes the real verb and rolls it back (F.5 layer 3). */
  preview: (fleetId: string, text: string) => Promise<PreviewResult | null>
  cancel: (fleetId: string, index?: number | null) => Promise<boolean>
  clear: (fleetId: string) => Promise<boolean>
  /** Drop the last refusal — a screen calls this when the player moves on. */
  dismissRefusal: () => void
}

/** A fleet by id, for a screen that holds a selection. */
export function fleetOf(world: LiveWorld, id: string | null): FleetView | undefined {
  return id ? world.fleets.find((f) => f.id === id) : undefined
}

/** The port a fleet is lying in, or null at sea. */
export function portOfFleet(world: LiveWorld, fleet: FleetView | undefined): SnapshotPort | null {
  if (!fleet?.port) return null
  return world.portByCode[fleet.port] ?? null
}

export const useWorld = create<LiveWorld>((set, get) => ({
  phase: 'idle',
  fatal: null,
  mode: null,
  snapshot: null,
  fleets: [],
  player: null,
  officers: null,
  skills: null,
  history: {},
  ducats: null,
  events: [],
  markets: {},
  busy: false,
  refusal: null,
  readAt: null,
  portByCode: {},
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
    const portByCode: Record<string, SnapshotPort> = {}
    const portById: Record<string, SnapshotPort> = {}
    for (const p of snap.value.ports) {
      portByCode[p.code] = p
      portById[p.id] = p
    }
    const goodByCode: Record<string, SnapshotGood> = {}
    for (const g of snap.value.goods) goodByCode[g.code] = g

    set({ snapshot: snap.value, portByCode, portById, goodByCode, mode })
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

  issue: async (fleetId, text) => {
    const fleet = get().fleets.find((f) => f.id === fleetId)
    const r = await cmdIssue(fleetId, text, fleet?.version ?? null)
    if (!r.ok) {
      set({ refusal: r.refusal })
      return false
    }
    set({ refusal: null })
    // The order may have executed already (a docked fleet acts at once), so read the world back
    // rather than patching a local copy of it — the server's answer is the only true one.
    await get().refresh()
    const port = fleet?.port ? get().portByCode[fleet.port] : null
    if (port) await get().loadMarket(port.id)
    return true
  },

  preview: async (fleetId, text) => {
    const r = await cmdPreview(fleetId, text)
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

  dismissRefusal: () => set({ refusal: null }),
}))
