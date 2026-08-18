// THE V0 WORLD SHAPE — pure types, no data, no React.
//
// These interfaces are the contract the six V0 screens are written against. They deliberately
// mirror DESIGN.md Appendix 1's table sketch field-for-field where a field exists there, so that
// when the server lands, world.snapshot() / world.fleets() / world.market() can be typed straight
// onto them and the screens do not move.
//
// WHAT IS AUTHORED AND WHAT IS DERIVED — the rule this file exists to state:
//   AUTHORED here: geography, ships, crew, hull, cargo, affinity, stock, the order queue, the log.
//   DERIVED elsewhere, never stored: distance (features/command/geo.ts), fleet speed / endurance /
//   hold (features/fleets/fleetMath.ts), every price and %NBR (features/market/prices.ts).
// A number that can be computed is not a fixture field. That is what makes the fixture checkable:
// a reader can take the coordinates and the formula and get our figure back.

export type PortCode =
  | 'LIS'
  | 'OPO'
  | 'SVQ'
  | 'CAD'
  | 'CEU'
  | 'SAF'
  | 'FNC'
  | 'LPA'
  | 'MRS'
  | 'GOA'
  | 'TUN'
  | 'NAP'

export type GoodCode =
  | 'sal'
  | 'trigo'
  | 'vinho'
  | 'azeite'
  | 'cortica'
  | 'la'
  | 'couro'
  | 'ferro'
  | 'cobre'
  | 'acucar'
  | 'tamaras'
  | 'coral'

export type ShipClassCode = 'barca' | 'caravela_latina' | 'nau'

/** DESIGN.md B.4 — culture gates goods. V0 needs exactly two. */
export type Culture = 'latin' | 'maghrebi'

export interface Port {
  code: PortCode
  /** Historical local form, always (L.12: never invent a name). */
  name: string
  country: string
  nation: string
  lat: number
  lon: number
  sea: string
  culture: Culture
  /** 1-5. Drives stock targets and the crew pool. */
  sizeTier: number
  /** H.1 development tracks, 0-20. */
  devIndustry: number
  devCommerce: number
  devMilitary: number
  /** C.3 — the stat that makes a small hull permanently useful. */
  maxDraft: number
  hasYard: boolean
  yardTier: number
  /** The Mayor's market tax, H.3, banded 0-8%. */
  marketTaxRate: number
  /** Crew available at the Inn without paying the urgent premium (F.2 HIRE). */
  crewPool: number
  crewPoolMax: number
  /** Ducats per head to hire. */
  crewRate: number
  /** Provisioning prices, ducats per tun (F.2 PROVISION). */
  waterPrice: number
  foodPrice: number
  /** Ducats per durability point repaired, before the dev_industry discount (F.2 REPAIR). */
  repairRate: number
  /** Named for the PORT tab; these are the goods this port is known for. */
  specialties: readonly GoodCode[]
  languages: readonly string[]
  /** J.3 presence — a count, never a name. */
  fleetsDocked: number
}

/** An authored sailing edge (B.1). Undirected: the graph builder adds both directions. */
export interface Leg {
  from: PortCode
  to: PortCode
  /** B.6 — multiplies the sea's base hazard. 1.00 is an ordinary run. */
  hazardMult: number
  notes?: string
}

export interface Good {
  code: GoodCode
  /** Historical local (Iberian) form — the name the market table prints. */
  name: string
  english: string
  category: 'staple' | 'material' | 'textile' | 'metal' | 'colonial' | 'luxury'
  /** G.1 — GLOBAL per good. One number, one authority. */
  baseValue: number
  /** Tuns per unit — bullion is dense and cheap to carry, timber is not (G.3). */
  bulk: number
  /** Spoilage, percent per voyage-day. */
  perishablePctDay: number
  /** Cultures that will NOT trade it (B.4 availability_mask). Wine in Islamic ports. */
  forbiddenCultures: readonly Culture[]
  /** Base stock target before the port's size multiplier. */
  stockTargetBase: number
}

export type Rig = 'square' | 'lateen' | 'mixed' | 'oared'

export interface ShipClass {
  code: ShipClassCode
  name: string
  rig: Rig
  /** Tuns. */
  hold: number
  crewRequired: number
  crewMax: number
  /** Knots, before every modifier in B.3. */
  speedKn: number
  maxDurability: number
  guns: number
  draft: number
  role: string
}

export interface CargoLot {
  good: GoodCode
  tuns: number
  /** What it cost per tun, for the Fleets tab's avg-cost column. */
  avgCost: number
}

export interface Ship {
  id: string
  name: string
  classCode: ShipClassCode
  fleetId: string
  isFlagship: boolean
  durability: number
  crew: number
  waterT: number
  foodT: number
  cargo: readonly CargoLot[]
}

export type FleetStatus =
  | 'DOCKED'
  | 'ANCHORED'
  | 'SAILING'
  | 'REPAIRING'
  | 'ADRIFT'
  | 'UNABLE_TO_SAIL'

/** D.2 — a voyage is a closed-form function of departure, not a simulated position. */
export interface Voyage {
  id: string
  /** The port sequence actually sailed, origin first. */
  path: readonly PortCode[]
  departedAtMs: number
  /** Frozen at departure (B.3): the fleet speed used for the whole voyage. */
  speedKn: number
}

export interface Fleet {
  id: string
  name: string
  status: FleetStatus
  /** Where it is when DOCKED / ANCHORED / REPAIRING. Null while SAILING. */
  portCode: PortCode | null
  voyage: Voyage | null
  /** REPAIRING only: when the yard hands it back. */
  busyUntilMs?: number
}

export type OrderStatus = 'pending' | 'active' | 'done' | 'failed' | 'cancelled' | 'skipped'

export interface QueuedOrder {
  id: string
  fleetId: string
  /** 1-based position, as CANCEL <fleet> <index> addresses it (F.4). */
  seq: number
  /** THE STRING. The tap-builder and the keyboard both produce this and nothing else (F.4). */
  raw: string
  status: OrderStatus
  errorCode?: string
}

export type LedgerKind = 'TRADE' | 'VOYAGE' | 'PORT' | 'REPAIR' | 'PROVISION' | 'CREW' | 'MARKET'

/** One paragraph of an after-action report (B.6, E.6) — prose, because that IS the combat system. */
export interface ReportParagraph {
  /** Voyage-day the checkpoint fell on. */
  day: number
  hazard: 'STORM' | 'CALM' | 'PIRATES' | 'SHORT_RATIONS' | 'CLEAR'
  text: string
}

export interface LedgerLine {
  label: string
  value: string
}

export interface LedgerEntry {
  id: string
  atMs: number
  kind: LedgerKind
  /** Who it happened to — a fleet name, or BUREAU / MARKET for world events. */
  actor: string
  /** The one-line headline, as the Ledger prints it. */
  headline: string
  /** Ducats moved. 0 for an entry that moved no money (a departure, a market notice). */
  ducatsDelta: number
  /** Balance AFTER this entry. I.4's discipline: the running total is carried, not recomputed. */
  balanceAfter: number
  /** Present on a voyage report: the prose B.6 promises instead of a fight scene. */
  report?: readonly ReportParagraph[]
  /** The itemised block under a report (wages, provisions, damage, fame). */
  lines?: readonly LedgerLine[]
  /** Unread entries carry the LEDGER tab badge. */
  unread?: boolean
}

export interface Player {
  companyName: string
  nation: string
  ducats: number
  /** C.4 — caps fleets and ships. */
  companyLevel: number
  maxFleets: number
  maxShips: number
  /** Reputation-derived relief on the Mayor's market tax; effective = max(0, market - relief). */
  taxRelief: number
  reputation: number
  reputationLabel: string
}

/** One (port, good) row — G.1's "every pair is one row. Price is derived, never stored." */
export interface PortGood {
  port: PortCode
  good: GoodCode
  /** G.1 — the authored soul of the world, 0.25 to 3.00. */
  affinity: number
  stock: number
  stockTarget: number
  /** G.1 Ornstein-Uhlenbeck term, clamped +/-0.25. Authored flat here; the server rolls it. */
  drift: number
  /** G.6 market events and B.4 season land here, -0.30 to +0.30. */
  seasonMod: number
  /** The last 7 game-days of mid, oldest first, index 6 = today. Authored, because a price
   *  history is a record of what happened and cannot be recomputed from present state. */
  history7?: readonly number[]
  /** G.6 — a live event on this row. */
  event?: { kind: 'SOARING' | 'PLUNGING' | 'BOOMING' | 'BLOCKADE'; sinceDays: number }
}

export interface V0World {
  /** The instant this snapshot describes. Every ETA and countdown is measured from it. */
  nowMs: number
  /** The calendar clock's origin (D.1): real time at game 1 January of epochYear. */
  calendarEpochMs: number
  epochYear: number
  player: Player
  ports: readonly Port[]
  legs: readonly Leg[]
  goods: readonly Good[]
  shipClasses: readonly ShipClass[]
  fleets: readonly Fleet[]
  ships: readonly Ship[]
  orders: readonly QueuedOrder[]
  portGoods: readonly PortGood[]
  ledger: readonly LedgerEntry[]
  /** Where the player is standing — the PORT tab's subject. */
  currentPort: PortCode
}
