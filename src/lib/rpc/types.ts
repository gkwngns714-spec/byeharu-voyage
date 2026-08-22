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
  /** DESIGN E.4 — the radius %NBR compares against, and the two bands it is cut into. These were
   *  declared on the client until 0019; they are the server's numbers and it serves them now, so a
   *  caption cannot disagree with the computation behind it. */
  neighbour_radius_nm: number
  advice_buy_below: number
  advice_sell_above: number
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

/**
 * ONE ROW OF `world.trade_routes()` (0019) — a good, the reachable port that pays most for it, and
 * what the voyage is worth.
 *
 * EVERY MONEY FIGURE HERE CAME OUT OF `world.quote()`, the same function a committed BUY and SELL
 * execute at, at the quantity named in `qty`. `nm` is the SAILED leg distance over the shortest
 * route (`voyage.reach_from`), never a straight line. `profit` is the TRADE's margin — a voyage
 * also pays its crew's wages each day at sea, and that is deliberately not folded in here (see the
 * migration header): `days` is printed beside it so the exposure is visible.
 */
export interface TradeRoute {
  good_id: string
  code: string
  name: string
  to: { id: string; code: string; name: string }
  /** The quantity every figure in this row was priced at. */
  qty: number
  outlay: number
  proceeds: number
  profit: number
  return_pct: number | null
  buy_price: number
  sell_price: number
  /** Sailed leg distance over the shortest route, and how many legs it is. */
  nm: number
  legs: number
  /** Null when no fleet was named — there is no speed to divide by, so no days to quote. */
  days: number | null
  profit_per_day: number | null
  profit_per_nm: number
}

/** What the read searched under, reported rather than assumed. */
export interface TradeRoutesBasis {
  /** `fleet` — priced at what this fleet can afford and carry. `default` — at `tuns`. */
  qty_from: 'fleet' | 'default'
  tuns: number
  /** Null when the caller pinned a destination — there is no reach to report, only that port. */
  max_legs: number | null
  /** The port code the scan was pinned to, or null when it looked everywhere in reach. */
  to: string | null
  ports_considered: number
  goods_cap: number
  keep_per_good: number
  routes_found: number
}

export interface TradeRoutes {
  from: { id: string; code: string; name: string } | null
  fleet: { id: string; name: string; speed_kn: number; here: boolean } | null
  basis: TradeRoutesBasis
  routes: TradeRoute[]
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
  /**
   * HOW MANY TUNS FIT — the STOWED capacity, `public.ship_hold_capacity(ship)` (0017:156): the
   * rated hull stretched by the quartermasters posted to her fleet. The key keeps its old name
   * deliberately (0017 says so in its own header), so every reader that already said `hold` reads
   * the effective figure without having to know an officer exists.
   */
  hold: number
  /** What the shipwright built — `ship_classes.hold`, before any officer. For a card that wants to
   *  show the hull itself rather than what she can be made to carry. */
  hold_rated: number
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
  /**
   * ROOM FOR THE NEXT PARCEL, IN TUNS — `public.fleet_free_hold(fleet)` (0017:183), and THE ONE
   * ANSWER to it. It is the same reading `cmd.do_buy` checks against and `public.fleet_load`
   * places into, so what a screen prints and what a BUY refuses on cannot disagree.
   *
   * WHY IT IS A FIELD AND NOT A CLIENT FOLD. It was computed three times on this side — in
   * `domain/fleet/derive.ts`, in `features/command/fleetLimits.ts` and in `MarketScreen`, whose
   * copy subtracted only the cargo and forgot the water and the food, so it had over-reported the
   * free hold since the day it was written. Three spellings of one subtraction is exactly the
   * duplication 0017 folded on the server; the client's answer is now to READ this.
   */
  free_hold: number
  /** What this fleet's posted officers are actually worth, per specialty, in PERCENT — already
   *  summed within the specialty and clamped at `officer_bonus_cap_pct` by
   *  `public.fleet_officer_bonus` (0015). Nothing on the client sums `Officer.bonus_pct` itself. */
  officer_pct: Record<OfficerSpecialty, number>
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

/**
 * What `cmd.found_house()` hands back when a captain signs the book (0011).
 *
 * There is no uid in the request and none in the reply: the server took the identity from the JWT,
 * so a client can only ever have founded its own house. A refusal arrives as a `Refusal` through
 * the usual `RpcResult`, never as a field on this — E_ALREADY_FOUNDED, E_NAME_TAKEN, E_BAD_NAME,
 * E_NO_SUCH_NATION and E_NOT_SIGNED_IN are the five the migration can raise.
 */
export interface FoundedHouse {
  player_id: string
  company_name: string
  nation: string
}

// ── 0013-0016: the record, the house, the roster and the school ─────────────────────────────────

/** One remembered point on a good's price line. `mid` only: the spread and the tax are the port's
 *  cut and are read live, while what MOVED is the mid (0013). */
export interface PricePoint {
  /** The drift slot the sample belongs to — the x axis, in units of `slot_seconds`. */
  slot: number
  at: string
  mid: number
}

/** `world.price_history(port, slots)` — ONE call per port, keyed by good CODE, oldest point first.
 *  A good with no points yet is simply absent from `goods`; it is never an empty array, so a
 *  caller must treat "missing" and "flat" as different. */
export interface PriceHistory {
  port: string
  slots: number
  /** How many real seconds one slot spans, so an axis can be labelled without knowing the cadence. */
  slot_seconds: number
  goods: Record<string, PricePoint[]>
}

/** Fame, DERIVED from the append-only record every time it is asked (0014) — never a stored
 *  counter, so it cannot drift from the ledger it is computed from. */
export interface PlayerFame {
  trade: number
  exploration: number
  total: number
  ports_reached: number
  turnover: number
}

/** The signed-in house, reading itself (0014). */
export interface PlayerHouse {
  id: string
  company_name: string
  nation: string | null
  nation_name: string | null
  ducats: number
  company_level: number
  title_level: number
  founded_at: string
  fleets: number
  ships: number
  /** Where her first fleet lies, or null while every fleet is at sea. There is no home port in this
   *  game, so this is reported as what it is rather than as a base. */
  lying_at: string | null
  fame: PlayerFame
}

/** `world.player()`. `player` is NULL for a signed-in account that has not signed the book yet —
 *  a STATE, not a refusal, which is why it is not an error result. */
export interface PlayerView {
  player: PlayerHouse | null
}

export type OfficerSpecialty = 'NAVIGATOR' | 'QUARTERMASTER' | 'SURGEON' | 'PURSER'

export interface Officer {
  code: string
  name: string
  specialty: OfficerSpecialty
  bonus_pct: number
  wage: number
  blurb: string
  port: string | null
  nation: string | null
  /** FALSE when no rule reads this specialty yet (0015 wires NAVIGATOR only). A card that hid this
   *  would be selling a bonus that does nothing — the UI must print it. */
  takes_effect: boolean
  hired: boolean
  /** The fleet they serve in, by NAME, or null for an officer ashore. */
  fleet: string | null
}

export interface OfficerRoster {
  /** The most any one fleet may gain from officers of one specialty, in percent. */
  bonus_cap_pct: number
  specialties_read: OfficerSpecialty[]
  officers: Officer[]
}

export type SkillEffect = 'ENDURANCE' | 'SPEED' | 'TRADE_CAP' | 'SPREAD'

export interface Skill {
  code: string
  name: string
  effect: SkillEffect
  pct_per_level: number
  blurb: string
  /** 0 when never studied — the absence of a row, not a stored zero. */
  level: number
  /** What the next level costs, or null at the ceiling. */
  next_cost: number | null
  /** FALSE when no rule reads this effect yet (0016 wires ENDURANCE only). */
  takes_effect: boolean
}

export interface SkillBook {
  max_level: number
  base_cost: number
  effects_read: SkillEffect[]
  skills: Skill[]
}

/** What `cmd.hire_officer` / `cmd.post_officer` / `cmd.study_skill` hand back. A refusal arrives as
 *  a `Refusal` through the usual `RpcResult`, never as a field here. */
export interface HiredOfficer {
  officer: string
  name: string
  specialty: OfficerSpecialty
  bonus_pct: number
  fleet: string | null
  paid: number
}

export interface PostedOfficer {
  officer: string
  fleet: string | null
}

export interface StudiedSkill {
  skill: string
  name: string
  level: number
  max_level: number
  paid: number
  port: string
  effect: SkillEffect
}
