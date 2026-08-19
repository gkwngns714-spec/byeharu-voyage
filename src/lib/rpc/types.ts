// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RPC CONTRACT — typed from the SQL, not from the design document
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Every field below was read out of supabase/migrations/ and then CONFIRMED against the payload a
// live chain actually returned (tests/rpc.surface.spec.ts asserts these shapes at runtime, so a
// migration that renames a key turns a spec red instead of turning a screen blank).
//
// Where DESIGN.md and the SQL disagree, THE SQL WINS and the difference is noted here:
//
//   * `world.snapshot()` carries NO player. The house's name, level, reputation and tax relief are
//     not served by any V0 read; `world.ledger()` serves the purse (`ducats`) and nothing else
//     about the player: the house's name, level and reputation are not served — see README §4.
//   * `world.market()` prices from `world.price()`, which returns ask/bid/mid. The fixture's
//     PortGood carries authored `affinity`, `drift`, `seasonMod`, `history7` and `event`; NONE of
//     those cross the RPC boundary. Price is derived server-side and the client is told the price.
//   * A port carries `crew_pool` but no crew RATE, no water/food price and no repair rate; those
//     live in world_config, which snapshot() serves only as an allow-list (no provisioning prices
//     in it). PROVISION/HIRE/REPAIR are priced by the server when the order runs.
//   * Fields are snake_case, because they are Postgres columns and a renaming layer in between
//     would be a second authority for what a field is called.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── world.snapshot() ───────────────────────────────────────────────────────────────────────────

export interface SnapshotPort {
  id: string
  code: string
  name: string
  country: string
  /** Nation CODE (`PRT`), not id. Null where a port has no nation row. */
  nation: string | null
  lat: number
  lon: number
  /** Sea NAME, e.g. `Atlântico Ibérico`. */
  sea: string
  /** Region CODE, e.g. `IBE`. */
  region: string
  culture: string
  size_tier: number
  max_draft: number
  has_yard: boolean
  yard_tier: number
  has_academy: boolean
  is_ice_closed: boolean
  /** 0..0.08 — the Mayor's market tax (DESIGN H.3). */
  tax_rate: number
  crew_pool: number
  dev_industry: number
  dev_commerce: number
  dev_military: number
}

export interface SnapshotLeg {
  id: string
  /** Port CODES, canonically ordered (lower code first). The graph is undirected. */
  from: string
  to: string
  /** Sailed distance, which may exceed the great circle where the route rounds land. */
  nm: number
  hazard_mult: number
  notes: string | null
}

export interface SnapshotGood {
  id: string
  code: string
  /** Historical local form — the name the market table prints. */
  name: string
  base_value: number
  bulk: number
  category: string
  perishable_pct_day: number
  /** Cultures that will NOT trade it. Empty = traded everywhere (DESIGN B.4). */
  culture_mask: string[]
}

/** `to_jsonb(ship_classes)` — the whole row, so every column is here. */
export interface SnapshotShipClass {
  id: string
  code: string
  name: string
  family: string
  rig: string
  hold: number
  crew_required: number
  crew_max: number
  speed_kn: number
  durability: number
  guns: number
  draft: number
  build_hours: number
  build_cost: number
  tier: number
}

/** The allow-listed knobs. `world_secret` is NOT among them and 0009 asserts that by value. */
export interface SnapshotConfig {
  time_compression: number
  order_queue_max: number
  fleet_max: number
  ship_max: number
  endurance_margin: number
  trade_step_tuns: number
  water_per_crew_day: number
  food_per_crew_day: number
  wage_per_crew_day: number
}

export interface VerbArg {
  name: string
  /** `fleet` | `port` | `good` | `qty` | `price` | `number` | `enum` | `flag`. */
  type: string
  required: boolean
  /** The word that introduces this argument, e.g. `TO`, `VIA`, `AT`. */
  keyword?: string
  repeat?: boolean
  values?: string[]
  default?: string | number
  op?: string
}

export interface VerbSpec {
  verb: string
  args: VerbArg[]
  help: string
}

export interface WorldSnapshot {
  ports: SnapshotPort[]
  legs: SnapshotLeg[]
  goods: SnapshotGood[]
  ship_classes: SnapshotShipClass[]
  config: SnapshotConfig
  /** The same eight verbs `cmd.verb_schema()` serves — one grammar, delivered with the world. */
  verbs: VerbSpec[]
}

// ── world.market(port) ─────────────────────────────────────────────────────────────────────────

export interface MarketPort {
  id: string
  code: string
  name: string
  tax_rate: number
  /** Half-spread, derived from dev_commerce (DESIGN G.1). */
  spread: number
  culture: string
  dev_commerce: number
}

export interface MarketGood {
  good_id: string
  code: string
  name: string
  category: string
  /** What the player PAYS (ask). */
  buy: number
  /** What the player RECEIVES (bid). */
  sell: number
  mid: number
  /** DESIGN E.4 %NBR: this port's mid as a percentage of ports within 600 nm. Null if alone. */
  pct_nbr: number | null
  stock: number
  stock_target: number
  /** 0..6 — the six-block stock meter. */
  stock_band: number
  /** False when the port's culture refuses the good outright (B.4). It is a fact, not a price. */
  available: boolean
  advice: 'buy' | 'sell' | 'hold'
}

export interface MarketView {
  /** Null when the port id does not exist. */
  port: MarketPort | null
  goods: MarketGood[]
}

/** world.buy_capacity(fleet, good) — the most this fleet can ACTUALLY take on here, priced through
 *  the same stepped quote a committed trade uses, and the word for what stops her. A ceiling worked
 *  out on the client from the spot price is always too high: buying moves the market (§G.2). */
export interface BuyCapacity {
  max_qty: number
  est_total: number
  /** `hold` · `stock` · `daily cap` · `purse` · `at sea` — a phrase for the caption, not a code. */
  bound_by: string
}

// ── world.fleets() ─────────────────────────────────────────────────────────────────────────────

export type FleetStatus = 'DOCKED' | 'ANCHORED' | 'SAILING' | 'REPAIRING' | 'ADRIFT' | 'UNABLE_TO_SAIL'

export interface FleetShip {
  id: string
  name: string
  /** Ship class NAME (`Barca`), not code. */
  class: string
  is_flagship: boolean
  durability: number
  max_durability: number
  crew: number
  crew_required: number
  crew_max: number
  hold: number
  /** goods CODE → tuns aboard. `{}` when empty. Water and food are stores, not cargo. */
  cargo: Record<string, number>
  /** Tuns occupied, bulk applied. */
  cargo_tuns: number
  water_t: number
  food_t: number
}

/** The closed-form position of DESIGN D.2 — computed, never simulated. */
export interface VoyagePosition {
  leg_index: number
  from_code: string
  to_code: string
  leg_frac: number
  nm_done: number
  total_nm: number
  lat: number
  lon: number
}

export interface FleetVoyage {
  id: string
  /** Destination port CODE. */
  to: string
  /** ISO timestamp. */
  eta: string
  total_nm: number
  nm_done: number
  position: VoyagePosition | null
}

export type OrderStatus = 'pending' | 'active' | 'done' | 'failed' | 'cancelled' | 'skipped'

export interface QueuedOrder {
  id: string
  /** 1-based, and the number `CANCEL <n>` addresses. */
  seq: number
  /** THE STRING the player typed or tapped. */
  text: string
  verb: string
  status: OrderStatus
  error_code: string | null
  error_message: string | null
  /** Verb-shaped result of a completed order (`{qty, good, total, avg_price}` for BUY, …). */
  result: Record<string, unknown> | null
}

export interface FleetView {
  id: string
  name: string
  status: FleetStatus
  /** Bump this into cmd.issue() as `expected_version` to make double-issue impossible (F.3). */
  version: number
  /** Port CODE while not SAILING; null at sea. */
  port: string | null
  busy_until: string | null
  /** Formation speed in knots, slowest ship first (B.3). */
  speed_kn: number
  endurance_days: number
  voyage: FleetVoyage | null
  ships: FleetShip[]
  queue: QueuedOrder[]
}

// ── world.ledger(cursor, limit) ────────────────────────────────────────────────────────────────

export interface LedgerEvent {
  id: string
  /** `FOUNDED` · `TRADE_BUY` · `TRADE_SELL` · `DEPARTED` · `VOYAGE_REPORT` · `WAGES` · … */
  kind: string
  payload: Record<string, unknown>
  /** ISO timestamp. */
  at: string
  /** Null for an event that moved no money. */
  ducats_delta: number | null
  balance_after: number | null
}

export interface LedgerPage {
  events: LedgerEvent[]
  /** Pass back as `cursor` for the next page. Null when the page is the last one. */
  next_cursor: string | null
  /** The purse. Absent (undefined) only when there is no signed-in player at all. */
  ducats?: number
  /** Σ ledger.ducats_delta — must equal `ducats`; the chain enforces it with a trigger. */
  ledger_sum?: number
}

// ── cmd.* ──────────────────────────────────────────────────────────────────────────────────────

export interface ParsedCommand {
  verb: string
  args: Record<string, unknown>
  fleet_id: string
}

export interface PreviewResult {
  ok: true
  parsed: ParsedCommand
  /** Present when the verb was really executed and rolled back. Verb-shaped. */
  estimate?: Record<string, unknown>
  /** CANCEL / CLEAR act at once; there is nothing to estimate. */
  immediate?: boolean
  /** The fleet is at sea, so the order is queueable rather than executable now. */
  queued?: boolean
}

/**
 * The order as `cmd.issue()` reports it back — NOT a full QueuedOrder. The issue payload carries
 * six fields and deliberately omits `text` and `verb`: the caller just supplied the text, and the
 * queue in the same response carries both for every order that is still live.
 */
export interface IssuedOrder {
  id: string
  seq: number
  status: OrderStatus
  error_code: string | null
  error_message: string | null
  result: Record<string, unknown> | null
}

export interface IssueResult {
  ok: true
  order: IssuedOrder
  queue: QueuedOrder[]
  /** The fleet's version AFTER the issue. Carry it into the next call. */
  version: number
  fixes: string[]
  error_code: null
  error_message: null
}

export interface CancelResult {
  ok: true
  /** The `seq` that was cancelled. */
  cancelled: number
  queue: QueuedOrder[]
}

export interface ClearResult {
  ok: true
  /** How many pending orders were dropped. */
  cancelled: number
  /** A voyage already at sea keeps sailing — RECALL is not a V0 verb. */
  active_left_running: boolean
  note: string | null
  queue: QueuedOrder[]
}
