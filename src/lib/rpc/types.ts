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

// The refusal's two numbers are declared where a refusal is declared (result.ts), not a second
// time here — an order row carries the same shape the envelope does, because it is the same thing.
import type { RefusalFigures } from './result'

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
  /**
   * 0067 — WHAT THIS CITY KEEPS. A building is a row `(port, kind, tier)`, not a column, so a
   * seventh building is an INSERT and not a new field here. `has_yard` and `has_academy` above are
   * still the AUTHORED truth in `data/ports.json`; these rows are derived from them, and they are
   * what the game READS — a tier a player raises has nowhere to live in a boolean.
   *
   * Ask it through `src/domain/port` and never by hand: three screens used to each carry their own
   * `port.has_yard` check.
   */
  buildings: readonly PortBuilding[]
  is_ice_closed: boolean
  /** 0..0.08 — the Mayor's market tax (DESIGN H.3). */
  tax_rate: number
  crew_pool: number
  dev_industry: number
  dev_commerce: number
  dev_military: number
  /** 0036: HARBOUR is a settlement with a shore; SEA_PLACE is a named location in open water —
   *  same graph, same router, same arrival, and NOTHING ashore. The one served answer to
   *  "is there a quay here?" — a screen never derives it from other fields. */
  kind: 'HARBOUR' | 'SEA_PLACE'
  /** 0036: the lookout's line for a SEA_PLACE (the LANDFALL report speaks it); null for harbours. */
  approach: string | null
}

/**
 * HOW RARE A GOOD IS — a SERVED word, decided by exactly one server function (0032's
 * `public.good_rarity`: how many ports produce the good, put through one threshold law). The
 * client renders it (`RarityMark` in the design system) and never computes it: a tier derived
 * client-side from price or producer counts would be a second authority that drifts the day
 * either input moves. It measures scarcity of SOURCE, not price — in this world every port
 * trades every good, so gold (22 producing ports) is dear and common, while glassware (one
 * port) is mid-priced and exotic.
 */
export type GoodRarity = 'common' | 'uncommon' | 'rare' | 'exotic'

export interface SnapshotGood {
  id: string
  code: string
  /** Historical local form — the name the market table prints. */
  name: string
  base_value: number
  bulk: number
  category: string
  perishable_pct_day: number
  /** Served by 0032 — see GoodRarity. Optional so the client does not break against a server
   *  that predates it (the same contract `VerbSpec.note` states for 0021). */
  rarity?: GoodRarity
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
  /** THE VOYAGE CLOCK (DESIGN D.1). 480, so a voyage-day is 86_400 / 480 real seconds. It governs
   *  sailing, provisions, wages and hazard checkpoints — everything `formatVoyageDays` prints. */
  time_compression: number
  /** THE CALENDAR CLOCK (DESIGN D.1), served from 0028. How many REAL seconds one game-day is. It
   *  governs the season, the daily trade cap, stock regeneration and the buff calendar — so every
   *  `*_game_days` figure on the wire (`BuffKind.duration_game_days`, `season_game_days`) is
   *  counted in THIS unit and becomes real time by multiplying by this number.
   *
   *  IT IS A DIFFERENT RATE FROM `time_compression`, AND THAT IS THE POINT. Both clocks call their
   *  unit a "day" and they are not the same length: a voyage-day is minutes, a game-day is the
   *  best part of an hour. Until 0028 only the voyage clock crossed the wire, so a screen served a
   *  figure in game-days could either print it on the wrong clock or not at all — and PortFair
   *  correctly printed not at all. Never convert one with the other's constant. */
  game_day_seconds: number
  order_queue_max: number
  fleet_max: number
  ship_max: number
  endurance_margin: number
  trade_step_tuns: number
  water_per_crew_day: number
  food_per_crew_day: number
  wage_per_crew_day: number
  /** The radius the reach table and the trade scan work in. The two advice bands that used to sit
   *  beside it left with the comparison itself in 0071 — there is no cut left to agree with. */
  neighbour_radius_nm: number
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
  /** ONE LINE, 30-60 characters, in a captain's voice — "Put to sea and make for another port."
   *  It is printed on the verb's card, so it has to fit one. Migration 0021 cut these from 85-242
   *  characters (1,212 across the eight verbs, down to 309) after the owner's "too long
   *  explanation. this is a game, make it so." */
  help: string
  /** THE FINE PRINT THAT USED TO BE INSIDE `help`, and is still true: that a big order walks a
   *  stepped book ten tuns at a time, that FULL fills the stores, that hands beyond the idle men
   *  cost two and a half times. It belongs behind the info dot, never on the card.
   *
   *  Optional because it is served by 0021 onward and the client must not break against a server
   *  that predates it. 0021 PROVES each mechanic moved here rather than being deleted — it
   *  requires six phrases present in the old `help` to be present in the new `note`. */
  note?: string
}

/**
 * A NATION, served as a catalogue from 0028 — the one place a nation CODE becomes a name.
 *
 * Every payload in this game that mentions a nation says its code and only its code:
 * `SnapshotPort.nation`, `StandingRow.nation`. Before 0028 nothing on the wire could turn one into
 * a name, so a screen could only print "PRT" or grow its own lookup table — and a client-side
 * code -> name table is the second authority `portNameOf` (src/live/worldStore.ts:192-208) exists to
 * prevent, after the port version of it had been hand-written seven times.
 *
 * `PlayerHouse.nation_name` is still served beside your own house's `nation`, and 0028 asserts the
 * two say the same word, so the convenience field cannot drift away from this catalogue.
 */
export interface SnapshotNation {
  id: string
  code: string
  /** The name a player is shown. "Portugal", never "PRT". */
  name: string
  flag_char: string
  /** The port CODE of the capital, resolvable through `portByCode`. Null where none is authored. */
  capital: string | null
}

export interface WorldSnapshot {
  ports: SnapshotPort[]
  goods: SnapshotGood[]
  /** DESIGN B.1, served from 0028. The one reading of what a nation code is called. */
  nations: SnapshotNation[]
  /** 0067 — what each kind of building is CALLED and what it DOES, once for the whole world. The
   *  names live with the buildings, never hard-coded on a screen. */
  building_kinds: SnapshotBuildingKind[]
  ship_classes: SnapshotShipClass[]
  config: SnapshotConfig
  /** The same eight verbs `cmd.verb_schema()` serves — one grammar, delivered with the world. */
  verbs: VerbSpec[]
}

// ── world.sea_raster() / world.reach(port) — the free sea (0039) ───────────────────────────────

/** The navigable-water raster, packed. Unpack through `src/lib/sea` (`navFromServed`) — the one
 *  reading of the format on this side of the wire. */
export interface SeaRasterPayload {
  cols: number
  rows: number
  cell_deg: number
  bits_per_cell: number
  cells_base64: string
}

/** One place's sailed distances to everywhere: `{ code: nm }`, plus its own water approach. */
export interface ReachPayload {
  from: string
  snap_nm: number
  reaches: Record<string, number>
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

// ── world.inn(port) — who is drinking here today (0073) ────────────────────────────────────────

/** One officer in the room. `signed` is whether you already keep her, so nothing is offered twice. */
export interface InnGuest {
  code: string
  name: string
  specialty: OfficerSpecialty
  bonus_pct: number
  wage: number
  blurb: string
  /** Her nation's name, or null for someone who belongs to no crown. */
  nation: string | null
  /** The port she calls home — which is why she is likelier to be found near it. */
  home: string | null
  signed: boolean
}

export interface InnView {
  port_id: string
  has_inn: boolean
  /** The world's own day. Present so a screen can say WHEN this room was true. */
  game_day: number
  present: InnGuest[]
}

// ── world.building_yard(port) — what this yard can lay down (0072) ─────────────────────────────

/** One material a hull wants, and how much of it is ashore in this city. */
export interface HullMaterial {
  /** The good's code, or the fitting's. */
  code: string
  name: string
  qty: number
  /** How much you keep HERE — in the warehouse for a good, in your store for a fitting. */
  have: number
}

export interface YardHull {
  /** `ship_classes.code`. */
  class: string
  name: string
  tier: number
  note: string
  /** The yard tier she wants. */
  yard_tier: number
  /** The yard's LABOUR, in ducats — not the price of a ship. */
  ducats: number
  hold: number
  speed_kn: number
  crew_required: number
  durability: number
  draft: number
  /** Whether THIS yard is good enough. The server's rule, never re-derived here. */
  buildable: boolean
  goods: HullMaterial[]
  items: HullMaterial[]
}

export interface BuildingYardView {
  port_id: string
  /** This city's building-yard tier, or null where it lays down nothing. */
  tier: number | null
  hulls: YardHull[]
}

// ── world.warehouse(port, fleet) — what this city is keeping for you (0070) ────────────────────

/** One line of a shed, or one line of a hold — the same shape, because the screen moves between them. */
export interface StoredGood {
  good: string
  name: string
  qty: number
  bulk: number
  /** Space taken, qty x bulk. Present on what is ashore; a hold line does its own arithmetic. */
  tuns?: number
}

export interface WarehouseView {
  port_id: string
  /** This city's warehouse tier, or null where it keeps none. */
  tier: number | null
  /** Tuns it holds in total. */
  cap: number
  /** Tuns of it you are using. */
  used: number
  stored: StoredGood[]
  /** What the named fleet is carrying, or empty when none was named. */
  aboard: StoredGood[]
}

// ── world.workstation(port, fleet) — what this city can make (0068) ───────────────────────────

/** One input of a recipe, and what the named fleet has of it aboard. */
export interface RecipeLine {
  good: string
  name: string
  qty: number
  /** Tuns in her hold, or null when no fleet was named. */
  aboard: number | null
}

/** One fitting, as this city sees it. */
export interface WorkstationItem {
  code: string
  name: string
  slot: string
  /** DESIGN 1.3 — every fitting buys one stat and spends another. Carried on the row. */
  buys: string
  spends: string
  note: string
  volume: number
  /** The workstation tier a city needs to make it. */
  ws_tier: number
  /** Whether THIS city's workstation is good enough. The server's rule, never re-derived here. */
  makeable: boolean
  /** How many you already own in this city — items have a LOCATION. */
  owned_here: number
  recipe: RecipeLine[]
}

export interface WorkstationView {
  port_id: string
  /** This city's workstation tier, or null where it keeps none. */
  tier: number | null
  items: WorkstationItem[]
}

/** 0067 — what a kind of building is called and what it does. Served once, read by every screen. */
export interface SnapshotBuildingKind {
  kind: BuildingKind
  name: string
  /** One sentence: what a player can do here. */
  does: string
}

/** 0067 — one building standing in one city. `kind` is a row in `public.building_kinds`. */
export interface PortBuilding {
  kind: BuildingKind
  /** 1..5 — how good this city is at it. Where "some cities can craft" lives. */
  tier: number
}

/** The seven kinds a city can keep. `shipyard` REPAIRS; `building_yard` BUILDS. Never one word. */
export type BuildingKind =
  | 'market'
  | 'warehouse'
  | 'workstation'
  | 'building_yard'
  | 'inn'
  | 'shipyard'
  | 'academy'

export interface MarketGood {
  good_id: string
  code: string
  name: string
  category: string
  /** Served by 0032 from the SAME authority as `SnapshotGood.rarity` — one rule, two callers, so
   *  a market row never needs a code→catalogue join to say one word. Optional for the same
   *  serve-order reason. */
  rarity?: GoodRarity
  /** What the player PAYS (ask). */
  buy: number
  /** What the player RECEIVES (bid). */
  sell: number
  mid: number
  /**
   * 0071 — HOW FAR THIS PRICE CAN TRAVEL, low and high, at this quay today. Priced through the one
   * expression with the drift term held at each end of its own band and every other term of this
   * row left as it is.
   *
   * It replaces `pct_nbr`, and the difference is the whole point: a range is a FACT about this
   * good here, where a neighbour comparison was an ANSWER about somewhere else. The owner:
   * *"price range when pressed for more info, no nearby price info needed"*.
   */
  range_lo: number
  range_hi: number
  stock: number
  stock_target: number
  /** 0..6 — the six-block stock meter. */
  stock_band: number
  /** False when the port's culture refuses the good outright (B.4). It is a fact, not a price. */
  available: boolean
  /**
   * 0061 — IS THIS GOOD ON THIS CITY'S QUAY? A city trades 4-10 goods (the owner,
   * docs/OWNER_REQUESTS.md row 48) and `public.port_offers` is the one authority for which. A row
   * with `offered: false` is in the payload only because a fleet of yours lies here CARRYING it:
   * it may be SOLD on this quay and it may never be bought, and `cmd.do_buy` refuses it with
   * E_UNAVAILABLE. Optional for the serve-order reason `rarity` is.
   */
  offered?: boolean
}

/**
 * ONE ROW OF `world.trade_routes()` (0019) — a good, the reachable port that pays most for it, and
 * what the voyage is worth.
 *
 * EVERY MONEY FIGURE HERE CAME OUT OF `world.quote()`, the same function a committed BUY and SELL
 * execute at, at the quantity named in `qty`. `nm` is the SAILED distance over the water
 * (`sea_reaches`, 0038 — derived from the raster, Arctic closed), never a straight line.
 * `profit` is the TRADE's margin — a voyage
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
  /** Sailed distance over the water, from the same table the endurance gate reads. */
  nm: number
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
  /** The sailed radius searched, in nm; null when the caller pinned a destination. */
  radius_nm: number | null
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

/** The prices' own clock (0029), served beside the prices so a countdown has one author. */
export interface MarketClock {
  /** The server's reading of "now" at the instant this payload was made — the same per-payload
   *  fact `BuffsView.now` is. ISO timestamptz. */
  now: string
  /** The instant the drift walk next steps the whole market (`public.next_drift_change_at`).
   *  ISO timestamptz. A countdown is SUBTRACTION against this and `now` — it must never be
   *  recomputed from `slot_seconds` and a wall clock (that is a second authority for "when do
   *  prices change", wrong by the elapsed slot time on every read and silently wrong the day the
   *  cadence knob moves — migration 0029 measures both). When the countdown reaches zero the
   *  client RE-ASKS `world.market()`; the re-ask is itself what steps the market where pg_cron
   *  is absent, so assuming instead of re-asking shows prices the server no longer serves.
   *  Another captain's trade or stock regeneration can nudge an individual price sooner; the
   *  scheduled walk moves at this instant and not before. */
  next_change_at: string
}

export interface MarketView {
  /** Null when the port id does not exist. */
  port: MarketPort | null
  goods: MarketGood[]
  clock: MarketClock
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

// ── world.haggle_state(fleet, good) · cmd.haggle(fleet, good, side) — migration 0022 ───────────
//
// EVERY FIELD BELOW WAS READ OUT OF `20260818000022_a_bargain_is_struck_on_the_quay.sql`, from the
// `jsonb_build_object` that produces it (`:610-635` for the read, `:534-557` for the verb) — not
// inferred from the shape of `buy_capacity`, which it resembles but does not copy.
//
// WHAT A BARGAIN IS, IN ONE LINE: a concession off the PORT'S SPREAD — never off the mid. The mid
// is what a good is worth and is the same for every house on the quay; 0022 refuses to let a
// negotiation touch it, because `world.market()`'s %NBR, the price history and `trade_routes`
// would then each be reporting a different world.

/** She is not alongside, so there is nobody to bargain with. The server's own two-key answer. */
export interface HaggleAshore {
  docked: false
  attempts_max: number
  /** The server's sentence — "She is at sea. A bargain is struck on the quay." Render it as-is. */
  why: string
}

/** She is alongside: the whole state of the bargaining for one good at this port, today. */
export interface HaggleOnQuay {
  docked: true
  /** Port and good CODES. */
  port: string
  good: string
  game_day: number
  /** HOW MUCH NEGOTIATION CAN BE DONE — the literal answer, and the server's count, never ours. */
  attempts_used: number
  attempts_left: number
  attempts_max: number
  wins: number
  /** The bargain currently HELD, as a fraction of the port's spread, and the same as a percentage. */
  concession: number
  concession_pct: number
  concession_max: number
  concession_max_pct: number
  /** What one more win would add, in percentage points of the spread. */
  step_pct: number
  /** The odds of the NEXT attempt — read from `public.haggle_odds`, the same authority
   *  `cmd.haggle` rolls against, so the panel cannot promise what the verb will not do. */
  next_odds: number
  next_odds_pct: number
  /** The port's PUBLISHED spread, and the spread THIS house executes at — purser and bargain
   *  already folded in by `world.spread_effective`, which is what `world.quote` itself calls. */
  spread_published: number
  spread_effective: number
  spread_floor: number
  /** True when the stack has reached `haggle_spread_floor_frac` × published and can go no lower. */
  at_floor: boolean
  /** "the next trade of this good at this port, or the day's end" — the server's own words. */
  spent_on: string
}

export type HaggleState = HaggleAshore | HaggleOnQuay

/**
 * What ONE attempt returns. A refusal never arrives here: `cmd.haggle` answers a refusal as
 * `{ok:false, error_code, error_message, fixes}` in the payload, which `fromPayload()` turns into
 * a `Refusal` before a caller ever sees it — so E_NOT_DOCKED, E_NO_STOCK, E_NO_CARGO and
 * E_HAGGLE_SPENT reach the screen in the server's own words, with the server's own fixes.
 *
 * THE ATTEMPT IS SPENT BEFORE THE ROLL IS TAKEN and the roll is keyed on the attempt INDEX
 * (0022:508-518), so a retry is a genuinely different draw that has already cost a chance. There is
 * no sequence of calls that re-rolls one draw, and nothing on this side should pretend otherwise.
 */
export interface HaggleAttempt {
  ok: true
  won: boolean
  good: string
  good_name: string
  port: string
  side: 'buy' | 'sell'
  /** The odds this attempt was rolled against — read BEFORE the attempt was spent. */
  odds: number
  /** 1-based: which attempt of the day this was. */
  attempt: number
  attempts_max: number
  attempts_left: number
  concession: number
  concession_pct: number
  concession_max_pct: number
  next_odds: number
  spread_published: number
  spread_effective: number
  /** The sentence a player reads, won or lost. Written by the server; never composed here. */
  message: string
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

/** The closed-form position of DESIGN D.2 — computed, never simulated. 0039: the point sits on
 *  the served COURSE (linear along its segment — the same interpolation the server's water law
 *  samples), so the glyph is always ON the drawn line. */
export interface VoyagePosition {
  seg_index: number
  leg_frac: number
  nm_done: number
  total_nm: number
  lat: number
  lon: number
}

/**
 * ONE SEA HER COURSE STILL HAS TO CROSS (migration 0055), served in sailing order on
 * `FleetVoyage.waters`. Everything here except `nm_to` is FROZEN AT DEPARTURE — `voyage.depart`
 * stores the verified segments and each one carries its own `sea_id` — so the list cannot drift
 * while she sails, and nothing on it is a prediction: no rng stream is touched to produce it.
 */
export interface VoyageWater {
  /** Sea CODE — `MED`, `STR`. */
  sea: string
  name: string
  /** 1 (home waters) … 5 (deadly): `seas.danger_level`, authored per sea by 0040 — and the SAME
   *  column the per-sea encounter mix is keyed on, so what is shown and what will decide her
   *  weather are one number rather than two authorities. */
  danger: number
  /** The sea's character in plain words — a NAME, not a sentence (`seas.note`). */
  note: string
  /** Sailed nautical miles she must still make good before she enters it. 0 for the one she is in. */
  nm_to: number
  /** How much of her remaining passage lies in it. */
  nm_in: number
  /** True for the water she is in right now — always exactly the first row. */
  now: boolean
}

export interface FleetVoyage {
  id: string
  /** Destination port CODE — null when she is bound for a bare point of open water (0039). */
  to: string | null
  /** [lat, lon] of the open-water destination; null when `to` names a port. */
  dest_point: [number, number] | null
  /** THE WHOLE COURSE she sails, [[lat, lon], …] — the chart draws exactly this polyline and
   *  nothing of its own (src/chart/route.ts). */
  course: [number, number][]
  /** ISO timestamp. */
  eta: string
  /**
   * 0063 — WHEN SHE LEFT, ISO. The anchor of the movement model: `voyage.progress_nm` measures
   * every mile from it (0006:575-589). It is SERVED because it cannot be derived here — `eta`
   * MOVES (a hazard delays her, a fair wind gives hours back, `voyage.recompute_eta` re-derives
   * it when a knob moves), so arrival minus duration is not departure. Optional for the
   * serve-order reason `waters` is: a build talking to a server that predates 0063 simply draws
   * no elapsed figure.
   */
  departed_at?: string
  total_nm: number
  nm_done: number
  /** THE WATERS SHE STILL HAS TO CROSS (0055), in sailing order. Optional only for the sake of a
   *  build talking to a server older than 0055; the chain always serves it, empty on arrival. */
  waters?: VoyageWater[]
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
  /**
   * The two numbers behind a FAILED order's refusal, served from `public.orders.error_figures`
   * (migration 0050). The queue is where a halted fleet is read, so the halt gets the same bar the
   * refusal itself got — never a second, prose-only rendering of the same event.
   */
  figures: RefusalFigures | null
  /** Verb-shaped result of a completed order (`{qty, good, total, avg_price}` for BUY, …). */
  result: Record<string, unknown> | null
}

export interface FleetView {
  id: string
  name: string
  status: FleetStatus
  /** Bump this into cmd.issue() as `expected_version` to make double-issue impossible (F.3). */
  version: number
  /** Port CODE while docked; null at sea and at open anchor. */
  port: string | null
  /** [lat, lon] while ANCHORED at a bare point of open water (0039); null otherwise. */
  anchor: [number, number] | null
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
  /** As on QueuedOrder — the refusal's figures, served (0050), never derived from the sentence. */
  figures: RefusalFigures | null
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
 * What `cmd.divert()` hands back when a sailing fleet answers her helm (0039). She turns WHERE
 * SHE IS: `at` is the "lat,lon" of the turn, and the onward passage to `dest` is already under
 * way — the refusals (E_NOT_SAILING, E_NO_SUCH_PORT, E_SAME_DEST, E_LAND…) arrive as a `Refusal`
 * as usual.
 */
export interface DivertResult {
  ok: true
  /** "lat,lon" of the point she turned at. */
  at: string
  /** The port CODE she was bound for, or "open sea". */
  was: string
  /** The port CODE — or "lat,lon" point — she now makes for. */
  dest: string
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
  /** 0069 — the three tracks. Fame is one number for a board; a LEVEL is what promotion requires. */
  levels: PlayerLevels
}

/** One track of DESIGN 8. `level` is the same curve for all three, so "level 4" means one amount
 *  of work whichever word comes before it. */
export interface LevelTrack {
  points: number
  level: number
}

export interface PlayerLevels {
  trading: LevelTrack & { turnover: number }
  exploration: LevelTrack & { ports_reached: number; nm_sailed: number }
  /** Reads zero, and says so: there is no combat in this game yet (migration 0035, deliberately). */
  combat: LevelTrack & { playable: boolean }
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

// ── the board (0025) ───────────────────────────────────────────────────────────────────────────

/**
 * ONE HOUSE'S LINE ON THE BOARD. Four things and no fifth: a name, a nation, a standing, and the
 * fames the standing is computed from.
 *
 * WHAT IS DELIBERATELY ABSENT, and why it is absent HERE as well as on the server: no purse, no
 * cargo, no fleet, no ship, no port, no ledger line. DESIGN J.1 makes the order book the only PvP
 * surface, so another house's purse and the harbour her fleet lies in are not colour — they say
 * what she can afford to corner and where to be waiting. `public.standings` carries RLS with NO
 * policy and NO grant to any client role, so this shape is what the server can physically hand
 * over, not a subset a screen politely asks for.
 */
export interface StandingRow {
  /** Competition rank: two houses level are BOTH 1st and the next is 3rd. */
  position: number
  /** True when at least one other house shares this position. */
  tied: boolean
  company_name: string
  nation: string
  trade_fame: number
  exploration_fame: number
  total_fame: number
  ports_reached: number
  is_you: boolean
}

/**
 * THE BOARD IS SETTLED, NOT LIVE, and it says so. `settled_at`/`age_seconds` are what let a screen
 * print "as of four minutes ago" instead of implying a figure that moves while you read it — your
 * OWN figures stay live through `world.player()`, which is the one place a house reads itself.
 *
 * `season` is null and stays null until something records a boundary. It is carried rather than
 * omitted so that the day seasons land, no payload shape changes.
 */
export interface StandingsBoard {
  settled_at: string | null
  age_seconds: number | null
  board_slot: number | null
  slot_seconds: number
  houses: number
  board_size: number
  season: null
  board: StandingRow[]
  /** Your line even when you are off the end of the board; null before the book is signed. */
  you: (Omit<StandingRow, 'company_name' | 'nation' | 'is_you'> & { on_board: boolean }) | null
  /** Present only on an empty world — a STATE with its reason, never a refusal. */
  why?: string
}

// ── what is on at the quay (0026) ──────────────────────────────────────────────────────────────

/** The one effect a timed modifier may reach today. Speed is absent ON PURPOSE: `voyage.depart`
 *  freezes a fleet's speed into `voyages.speed_profile`, and a modifier that moved a frozen number
 *  would be folded into a stored total the moment she sailed. */
export type BuffEffect = 'SPREAD'

/** An authored kind of thing that can be on — the calendar is DATA, so magnitude, duration, season
 *  length and chance all live on this row rather than in a knob table beside it. */
export interface BuffKind {
  code: string
  name: string
  subject_kind: string
  effect: BuffEffect
  magnitude_pct: number
  /** How long one runs, counted on the CALENDAR clock — multiply by `SnapshotConfig
   *  .game_day_seconds` for real time, never by `time_compression`. */
  duration_game_days: number
  /** The calendar half. NULL in BOTH of these means "this kind is not on a calendar" — a buff some
   *  other rule awards (0026:173-176 makes that a CHECK). Nothing authored today is in that state,
   *  which is exactly why the null branch has to be handled rather than assumed away. */
  season_game_days: number | null
  chance_per_season: number | null
  blurb: string
  /** False when no rule reads this effect yet. Nothing authored today is false. */
  takes_effect: boolean
}

/** A kind that is actually on, at one port, between two instants. */
export interface RunningBuff {
  code: string
  name: string
  effect: BuffEffect
  magnitude_pct: number
  blurb: string
  starts_at: string
  ends_at: string
  /** Inside its window right now. A row outside its window moves nothing. */
  live: boolean
  takes_effect: boolean
}

export interface PortBuffs {
  code: string
  name: string
  /** The port's cut AFTER anything running — the published figure every captain sees. */
  spread_published: number
  buff_pct: number
  running: RunningBuff[]
}

/**
 * Reading this winds the calendar where pg_cron is absent (0009's catch-up idiom) — but SINCE 0028
 * IT IS NO LONGER THE ONLY THING THAT DOES. `world.fleets()`, the read AppShell makes every thirty
 * seconds, winds it too, so a fair happens whether or not anybody opens a quay. Both call the one
 * writer, `public.tick_buff_calendar`; neither decides when a fair happens.
 */
export interface BuffsView {
  now: string
  effects_read: BuffEffect[]
  cap_pct: number
  kinds: BuffKind[]
  /** Null when asked without a port — the catalogue with nobody's quay attached. */
  port: PortBuffs | null
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

// ── THE BOOK OF STANDING ORDERS (0034) ──────────────────────────────────────────────────────────
// A provision preset is a HOUSE-owned standing order — "keep her at N days of stores" — that a
// fleet points at by reference. The days figure is a RANGE target judged against the served
// `endurance_days` when the fleet makes port; the tonnage it costs is computed there, from the
// crew aboard then. Nothing on this side derives either figure — the client's job is to print
// the target beside the crew it is measured against.

export interface ProvisionPresetFleetRef {
  id: string
  name: string
}

export interface ProvisionPreset {
  id: string
  name: string
  /** The RANGE target, in voyage-days — never a tonnage. Sized at fire time from crew aboard. */
  days: number
  /** The fleets sailing under this order. Served, so FLEETS and the book cannot disagree. */
  fleets: ProvisionPresetFleetRef[]
}

/** What `world.provision_presets()` serves: the whole book, and how full it may get. */
export interface ProvisionPresetBook {
  max: number
  presets: ProvisionPreset[]
}

/** `cmd.provision_preset_save` — create (id null) or adjust. Refusals arrive as `Refusal`. */
export interface PresetSaved {
  ok: true
  id: string
  name: string
  days: number
}

export interface PresetDeleted {
  ok: true
  deleted: string
  /** How many fleets the strike released — the FK detaches them, and the server says so. */
  detached_fleets: number
}

export interface PresetApplied {
  ok: true
  fleet: string
  preset: string | null
  days: number | null
}
