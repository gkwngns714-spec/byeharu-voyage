// THE V0 WORLD — a realistic snapshot of DESIGN.md K.1's scope, and the only data the six screens
// have until the server exists. No network, no Supabase, no RPC.
//
// EVERY NUMBER HERE IS CHECKABLE. That is the point of the file:
//   · Coordinates are B.2's table, unaltered. Feed any pair to geo.ts's haversine and you get the
//     figures B.3 publishes: Lisboa-Cadiz 188.4, Cadiz-Ceuta 60.7, Lisboa-Funchal 524.9,
//     Lisboa-Marseille 711.6, Lisboa-Las Palmas 708.7, Ceuta-Tunis 750.7.
//   · Ship and class figures are C.2's table, unaltered.
//   · Consumption is C.5: 0.020 tuns of water and 0.015 of food per crewman per voyage-day. So
//     Gaivota's 12 hands on 2.4 t of water and 1.7 t of food is min(10.0, 9.44) = 9.4 days of
//     endurance, which is the figure K.1's ten-minute session quotes.
//   · Prices are NOT stored. Affinity and stock are stored; G.1's formula turns them into a mid,
//     an ask and a bid in features/market/prices.ts. Lisboa's salt comes out at ask 7 d./t and
//     Cadiz's at bid 10 d./t, which is K.1's "-420 / +600" trade at the quantity that actually
//     fits a Barca's hold (see LEDGER below).
//   · The ledger's balances run: no entry's balanceAfter is asserted, every one is the previous
//     balance plus that entry's delta, ending at the player's 8,000 ducats.
//
// ONE KNOWN DEPARTURE FROM THE DOCUMENT, recorded rather than hidden: K.1's session narrates
// "BUY sal 60" onto the Barca Gaivota. A Barca holds 60 tuns and its stores occupy that same hold
// (C.5), so 60 tuns of salt cannot fit beside 4.1 tuns of water and food. The ledger below trades
// 55 tuns, which fits with 0.9 tuns to spare, and the arithmetic is exact at that quantity.

import type {
  Fleet,
  Good,
  GoodCode,
  LedgerEntry,
  Leg,
  Player,
  Port,
  PortCode,
  PortGood,
  QueuedOrder,
  Ship,
  ShipClass,
  V0World,
} from './types'

// ── PORTS ────────────────────────────────────────────────────────────────────────────────────
// B.2's twelve, with the development, draft, yard and provisioning figures V0 needs. Development
// levels and prices are ours (B.2 authors only geography); everything geographic is the document's.

export const PORTS: readonly Port[] = [
  {
    code: 'LIS', name: 'Lisboa', country: 'Portugal', nation: 'Portugal',
    lat: 38.71, lon: -9.14, sea: 'Atlântico Ibérico', culture: 'latin',
    sizeTier: 5, devIndustry: 12, devCommerce: 17, devMilitary: 8,
    maxDraft: 4, hasYard: true, yardTier: 3, marketTaxRate: 0.04,
    crewPool: 240, crewPoolMax: 400, crewRate: 22, waterPrice: 3, foodPrice: 12, repairRate: 2.0,
    specialties: ['vinho', 'sal', 'azeite', 'cortica'], languages: ['Portuguese'], fleetsDocked: 3,
  },
  {
    code: 'OPO', name: 'Porto', country: 'Portugal', nation: 'Portugal',
    lat: 41.15, lon: -8.61, sea: 'Atlântico Ibérico', culture: 'latin',
    sizeTier: 3, devIndustry: 9, devCommerce: 11, devMilitary: 4,
    maxDraft: 3, hasYard: true, yardTier: 2, marketTaxRate: 0.035,
    crewPool: 120, crewPoolMax: 200, crewRate: 20, waterPrice: 3, foodPrice: 11, repairRate: 2.2,
    specialties: ['vinho', 'cortica'], languages: ['Portuguese'], fleetsDocked: 1,
  },
  {
    code: 'SVQ', name: 'Sevilla', country: 'Castile', nation: 'Spain',
    lat: 37.39, lon: -5.99, sea: 'Atlântico Ibérico', culture: 'latin',
    // Sevilla lies up the Guadalquivir: a deep hull cannot reach it. This is C.3's draft rule
    // doing real work, and it is why the Nau in Aurora can never call here.
    sizeTier: 4, devIndustry: 11, devCommerce: 14, devMilitary: 9,
    maxDraft: 2, hasYard: true, yardTier: 2, marketTaxRate: 0.04,
    crewPool: 180, crewPoolMax: 300, crewRate: 24, waterPrice: 4, foodPrice: 13, repairRate: 2.3,
    specialties: ['azeite', 'acucar'], languages: ['Spanish'], fleetsDocked: 2,
  },
  {
    code: 'CAD', name: 'Cádiz', country: 'Castile', nation: 'Spain',
    lat: 36.53, lon: -6.29, sea: 'Atlântico Ibérico', culture: 'latin',
    sizeTier: 3, devIndustry: 8, devCommerce: 13, devMilitary: 11,
    maxDraft: 4, hasYard: true, yardTier: 2, marketTaxRate: 0.035,
    crewPool: 140, crewPoolMax: 220, crewRate: 23, waterPrice: 3, foodPrice: 12, repairRate: 2.2,
    specialties: ['sal', 'vinho'], languages: ['Spanish'], fleetsDocked: 2,
  },
  {
    code: 'CEU', name: 'Ceuta', country: 'Portugal', nation: 'Portugal',
    lat: 35.89, lon: -5.32, sea: 'Strait of Gibraltar', culture: 'latin',
    sizeTier: 2, devIndustry: 5, devCommerce: 8, devMilitary: 13,
    maxDraft: 3, hasYard: false, yardTier: 0, marketTaxRate: 0.03,
    crewPool: 70, crewPoolMax: 140, crewRate: 19, waterPrice: 4, foodPrice: 14, repairRate: 2.6,
    specialties: ['cortica', 'trigo'], languages: ['Portuguese', 'Arabic'], fleetsDocked: 0,
  },
  {
    code: 'SAF', name: 'Safi', country: 'Morocco', nation: 'free',
    lat: 32.30, lon: -9.24, sea: 'Atlantic Morocco', culture: 'maghrebi',
    sizeTier: 2, devIndustry: 4, devCommerce: 5, devMilitary: 6,
    maxDraft: 2, hasYard: false, yardTier: 0, marketTaxRate: 0.05,
    crewPool: 50, crewPoolMax: 120, crewRate: 16, waterPrice: 5, foodPrice: 10, repairRate: 3.0,
    specialties: ['tamaras', 'couro'], languages: ['Arabic'], fleetsDocked: 0,
  },
  {
    code: 'FNC', name: 'Funchal', country: 'Madeira, Portugal', nation: 'Portugal',
    lat: 32.65, lon: -16.91, sea: 'Atlantic Islands', culture: 'latin',
    sizeTier: 2, devIndustry: 6, devCommerce: 7, devMilitary: 3,
    maxDraft: 3, hasYard: false, yardTier: 0, marketTaxRate: 0.04,
    crewPool: 45, crewPoolMax: 100, crewRate: 21, waterPrice: 4, foodPrice: 13, repairRate: 2.8,
    specialties: ['acucar', 'vinho'], languages: ['Portuguese'], fleetsDocked: 1,
  },
  {
    code: 'LPA', name: 'Las Palmas', country: 'Canarias, Castile', nation: 'Spain',
    lat: 28.13, lon: -15.43, sea: 'Atlantic Islands', culture: 'latin',
    sizeTier: 2, devIndustry: 5, devCommerce: 6, devMilitary: 4,
    maxDraft: 3, hasYard: true, yardTier: 1, marketTaxRate: 0.045,
    crewPool: 40, crewPoolMax: 100, crewRate: 20, waterPrice: 4, foodPrice: 14, repairRate: 2.8,
    specialties: ['acucar'], languages: ['Spanish'], fleetsDocked: 0,
  },
  {
    code: 'MRS', name: 'Marseille', country: 'France', nation: 'France',
    lat: 43.30, lon: 5.37, sea: 'Golfe du Lion', culture: 'latin',
    sizeTier: 4, devIndustry: 12, devCommerce: 15, devMilitary: 8,
    maxDraft: 4, hasYard: true, yardTier: 2, marketTaxRate: 0.04,
    crewPool: 160, crewPoolMax: 280, crewRate: 25, waterPrice: 3, foodPrice: 12, repairRate: 2.2,
    specialties: ['azeite', 'coral'], languages: ['French'], fleetsDocked: 1,
  },
  {
    code: 'GOA', name: 'Genova', country: 'Republic of Genoa', nation: 'free',
    lat: 44.41, lon: 8.93, sea: 'Ligurian Sea', culture: 'latin',
    sizeTier: 4, devIndustry: 14, devCommerce: 16, devMilitary: 7,
    maxDraft: 4, hasYard: true, yardTier: 3, marketTaxRate: 0.03,
    crewPool: 170, crewPoolMax: 300, crewRate: 26, waterPrice: 3, foodPrice: 12, repairRate: 2.0,
    specialties: ['coral', 'azeite'], languages: ['Italian'], fleetsDocked: 2,
  },
  {
    code: 'TUN', name: 'Tunis', country: 'Hafsid / Ottoman', nation: 'Ottoman',
    lat: 36.80, lon: 10.18, sea: 'Sicily Channel', culture: 'maghrebi',
    sizeTier: 3, devIndustry: 7, devCommerce: 10, devMilitary: 12,
    maxDraft: 3, hasYard: false, yardTier: 0, marketTaxRate: 0.05,
    crewPool: 90, crewPoolMax: 180, crewRate: 17, waterPrice: 5, foodPrice: 11, repairRate: 3.0,
    specialties: ['tamaras', 'coral'], languages: ['Arabic', 'Turkish'], fleetsDocked: 0,
  },
  {
    code: 'NAP', name: 'Napoli', country: 'Spanish Naples', nation: 'Spain',
    lat: 40.85, lon: 14.27, sea: 'Tyrrhenian Sea', culture: 'latin',
    sizeTier: 4, devIndustry: 10, devCommerce: 12, devMilitary: 10,
    maxDraft: 4, hasYard: true, yardTier: 2, marketTaxRate: 0.045,
    crewPool: 150, crewPoolMax: 260, crewRate: 24, waterPrice: 3, foodPrice: 11, repairRate: 2.3,
    specialties: ['vinho', 'cortica'], languages: ['Italian', 'Spanish'], fleetsDocked: 1,
  },
]

// ── LEGS ─────────────────────────────────────────────────────────────────────────────────────
// K.1: "22 authored legs connecting them, distances from B.3." The distance is NOT stored: it is
// the haversine of the two endpoints (geo.ts), so a leg cannot drift away from its coordinates.
// What IS authored is WHICH pairs are sailable — and that is the whole reason the router can never
// cut a line through Iberia. There is no Lisboa-Marseille edge. The Mediterranean is entered
// through Ceuta and the Strait, exactly as it was.

export const LEGS: readonly Leg[] = [
  { from: 'OPO', to: 'LIS', hazardMult: 0.9 },
  { from: 'OPO', to: 'CAD', hazardMult: 1.0 },
  { from: 'OPO', to: 'FNC', hazardMult: 1.2, notes: 'Open Atlantic; no shelter for three days.' },
  { from: 'LIS', to: 'SVQ', hazardMult: 0.9, notes: 'Up the Guadalquivir on the tide.' },
  { from: 'LIS', to: 'CAD', hazardMult: 1.0, notes: 'Cape St Vincent; the first blow of any voyage.' },
  { from: 'LIS', to: 'SAF', hazardMult: 1.1 },
  { from: 'LIS', to: 'FNC', hazardMult: 1.1 },
  { from: 'LIS', to: 'LPA', hazardMult: 1.15 },
  { from: 'SVQ', to: 'CAD', hazardMult: 0.8 },
  { from: 'CAD', to: 'CEU', hazardMult: 1.0, notes: 'The Strait. Barbary sail work this water.' },
  { from: 'CAD', to: 'SAF', hazardMult: 1.1 },
  { from: 'CEU', to: 'SAF', hazardMult: 1.05 },
  { from: 'FNC', to: 'LPA', hazardMult: 0.95 },
  { from: 'FNC', to: 'SAF', hazardMult: 1.05 },
  { from: 'SAF', to: 'LPA', hazardMult: 1.0 },
  { from: 'CEU', to: 'MRS', hazardMult: 1.05 },
  { from: 'CEU', to: 'TUN', hazardMult: 1.35, notes: 'The Barbary coast. The worst water in V0.' },
  { from: 'MRS', to: 'GOA', hazardMult: 0.85 },
  { from: 'MRS', to: 'NAP', hazardMult: 0.95 },
  { from: 'GOA', to: 'NAP', hazardMult: 0.9 },
  { from: 'GOA', to: 'TUN', hazardMult: 1.2 },
  { from: 'TUN', to: 'NAP', hazardMult: 1.1 },
]

// ── GOODS ────────────────────────────────────────────────────────────────────────────────────
// K.1's twelve, named in their historical Iberian form (L.12). base_value is GLOBAL per good —
// G.1's "one number, one authority" — and every port price is that number bent by affinity.

export const GOODS: readonly Good[] = [
  { code: 'sal', name: 'sal', english: 'salt', category: 'staple', baseValue: 9, bulk: 1.0, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 4000 },
  { code: 'trigo', name: 'trigo', english: 'wheat', category: 'staple', baseValue: 8, bulk: 1.0, perishablePctDay: 0.5, forbiddenCultures: [], stockTargetBase: 5000 },
  // B.4 / G.3: wine does not sell in Islamic-culture ports. This is the availability_mask, and it
  // is the reason Safi and Tunis have no vinho row and no opinion about its price.
  { code: 'vinho', name: 'vinho', english: 'wine', category: 'staple', baseValue: 44, bulk: 1.0, perishablePctDay: 0.1, forbiddenCultures: ['maghrebi'], stockTargetBase: 2200 },
  { code: 'azeite', name: 'azeite', english: 'olive oil', category: 'staple', baseValue: 52, bulk: 1.0, perishablePctDay: 0.1, forbiddenCultures: [], stockTargetBase: 1800 },
  { code: 'cortica', name: 'cortiça', english: 'cork', category: 'material', baseValue: 30, bulk: 1.4, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 1200 },
  { code: 'la', name: 'lã', english: 'wool', category: 'textile', baseValue: 26, bulk: 1.2, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 1600 },
  { code: 'couro', name: 'couro', english: 'hides', category: 'material', baseValue: 60, bulk: 1.1, perishablePctDay: 0.3, forbiddenCultures: [], stockTargetBase: 900 },
  { code: 'ferro', name: 'ferro', english: 'iron', category: 'metal', baseValue: 38, bulk: 0.6, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 1400 },
  { code: 'cobre', name: 'cobre', english: 'copper', category: 'metal', baseValue: 34, bulk: 0.5, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 1100 },
  { code: 'acucar', name: 'açúcar', english: 'sugar', category: 'colonial', baseValue: 110, bulk: 0.9, perishablePctDay: 0.2, forbiddenCultures: [], stockTargetBase: 600 },
  { code: 'tamaras', name: 'tâmaras', english: 'dates', category: 'colonial', baseValue: 64, bulk: 0.9, perishablePctDay: 0.6, forbiddenCultures: [], stockTargetBase: 700 },
  { code: 'coral', name: 'coral', english: 'coral', category: 'luxury', baseValue: 240, bulk: 0.3, perishablePctDay: 0, forbiddenCultures: [], stockTargetBase: 200 },
]

// ── SHIP CLASSES ─────────────────────────────────────────────────────────────────────────────
// C.2's three V0 hulls, transcribed. Nothing added, nothing tuned.

export const SHIP_CLASSES: readonly ShipClass[] = [
  { code: 'barca', name: 'Barca', rig: 'lateen', hold: 60, crewRequired: 8, crewMax: 20, speedKn: 5.0, maxDurability: 400, guns: 0, draft: 1, role: 'Starter coaster' },
  { code: 'caravela_latina', name: 'Caravela latina', rig: 'lateen', hold: 90, crewRequired: 12, crewMax: 30, speedKn: 6.0, maxDurability: 550, guns: 2, draft: 1, role: 'Fast explorer' },
  { code: 'nau', name: 'Nau', rig: 'square', hold: 400, crewRequired: 60, crewMax: 140, speedKn: 4.4, maxDurability: 1800, guns: 12, draft: 3, role: 'Bulk ocean trader' },
]

// ── THE MARKET ───────────────────────────────────────────────────────────────────────────────
// AFFINITY is the authored soul of the world (G.1): 12 ports x 12 goods, laid out as a matrix so
// a reader can see the gradients rather than hunt through 144 objects. Column order is GOOD_ORDER.
// A zero means the culture refuses the good and no row is emitted at all.
//
// Read it as geography. Salt is cheap where it is made (Portugal, Setubal's pans) and dear across
// the Strait. Cork is Portuguese and nowhere else. Sugar is Madeiran and Canarian and expensive in
// Lisboa. Dates come out of the Maghreb at a third of what Iberia pays for them.

const GOOD_ORDER: readonly GoodCode[] = [
  'sal', 'trigo', 'vinho', 'azeite', 'cortica', 'la',
  'couro', 'ferro', 'cobre', 'acucar', 'tamaras', 'coral',
]

const AFFINITY: Record<PortCode, readonly number[]> = {
  //     sal   trigo vinho azeite cortica la   couro ferro cobre acucar tamaras coral
  LIS: [0.894, 1.05, 0.66, 0.78, 0.60, 1.02, 1.32, 1.28, 1.00, 1.40, 1.60, 1.55],
  OPO: [1.020, 1.12, 0.58, 0.88, 0.68, 0.88, 1.24, 1.22, 1.08, 1.48, 1.72, 1.70],
  SVQ: [1.150, 0.90, 0.92, 0.66, 1.12, 1.18, 0.92, 1.12, 1.18, 0.82, 1.32, 1.48],
  CAD: [1.127, 1.00, 0.98, 0.74, 1.18, 1.22, 0.96, 1.08, 1.14, 0.86, 1.22, 1.38],
  CEU: [1.120, 1.40, 0.00, 1.02, 1.42, 1.36, 1.02, 0.94, 1.02, 1.28, 0.76, 1.08],
  SAF: [1.050, 1.55, 0.00, 1.16, 1.62, 0.74, 0.76, 1.42, 1.32, 1.12, 0.36, 0.92],
  FNC: [1.020, 1.70, 0.92, 1.26, 1.32, 1.52, 1.71, 1.56, 1.46, 0.42, 1.42, 1.62],
  LPA: [1.080, 1.76, 1.02, 1.32, 1.38, 1.58, 1.68, 1.62, 1.52, 0.56, 1.28, 1.58],
  MRS: [1.180, 1.26, 0.78, 0.62, 1.28, 0.92, 1.22, 0.88, 0.82, 1.52, 1.12, 0.68],
  GOA: [1.260, 1.36, 0.82, 0.72, 1.32, 0.82, 1.28, 0.78, 0.72, 1.58, 1.22, 0.52],
  TUN: [0.880, 1.22, 0.00, 0.92, 1.48, 1.08, 1.02, 1.18, 1.08, 1.38, 0.38, 0.58],
  NAP: [1.120, 1.06, 0.88, 0.70, 1.38, 1.02, 1.18, 0.98, 0.92, 1.42, 1.02, 0.78],
}

/** stock / stock_target, authored only where it is NOT 1.00 — a glut or a shortage is an event
 *  worth naming, and G.1's (target/stock)^0.5 turns each one into a price move you can see. */
const STOCK_RATIO: Partial<Record<PortCode, Partial<Record<GoodCode, number>>>> = {
  LIS: { sal: 1.25, cortica: 1.30, vinho: 1.20, trigo: 0.90, cobre: 0.95, acucar: 0.80 },
  OPO: { vinho: 1.35 },
  CAD: { sal: 0.85, couro: 1.20, trigo: 1.15 },
  SAF: { tamaras: 1.55 },
  FNC: { acucar: 1.60, couro: 0.70 },
  LPA: { acucar: 1.45 },
  GOA: { coral: 1.45 },
  TUN: { tamaras: 1.70, coral: 1.35 },
}

/** G.6 — a live market event, as a season_mod on one (port, good). Funchal's hides are SOARING,
 *  which is what puts Funchal at 211% of its neighbours on the MARKET tab. */
const SEASON_MOD: Partial<Record<PortCode, Partial<Record<GoodCode, number>>>> = {
  FNC: { couro: 0.18 },
}

/** G.1's Ornstein-Uhlenbeck term. Frozen here (the server rolls it every 10 minutes); non-zero on
 *  two rows only, so that a reader checking the arithmetic has almost nothing to carry. */
const DRIFT: Partial<Record<PortCode, Partial<Record<GoodCode, number>>>> = {
  LIS: { acucar: 0.08 },
  CAD: { sal: -0.04 },
}

/** The last seven game-days of `mid`, oldest first, index 6 = now. Authored for the two ports the
 *  V0 market table renders, because a price history is a RECORD and cannot be recomputed from
 *  present state. Each series ends on exactly the mid that G.1 produces from the row above it —
 *  which is what makes the sparkline and the price column the same fact. */
const HISTORY: Partial<Record<PortCode, Partial<Record<GoodCode, readonly number[]>>>> = {
  LIS: {
    sal: [7.11, 7.04, 6.91, 6.84, 6.77, 6.71, 6.71],
    trigo: [8.0, 8.09, 8.17, 8.25, 8.33, 8.25, 8.25],
    vinho: [25.7, 25.45, 25.2, 24.95, 24.95, 24.71, 24.71],
    azeite: [37.05, 37.42, 37.8, 38.18, 37.8, 37.8, 37.8],
    cortica: [16.04, 15.74, 15.45, 15.15, 15.01, 14.86, 14.71],
    la: [24.47, 24.72, 24.96, 24.72, 24.47, 24.72, 24.72],
    couro: [67.91, 69.39, 70.86, 71.6, 73.08, 73.81, 73.81],
    ferro: [45.79, 45.33, 44.88, 45.33, 45.33, 45.33, 45.33],
    cobre: [33.16, 32.84, 32.84, 32.51, 32.51, 32.51, 32.51],
    acucar: [149.04, 152.51, 157.71, 162.91, 168.11, 171.57, 173.31],
    tamaras: [90.66, 91.62, 93.53, 94.48, 95.44, 95.44, 95.44],
    coral: [346.7, 346.7, 346.7, 346.7, 346.7, 346.7, 346.7],
  },
  CAD: {
    sal: [9.31, 9.41, 9.61, 9.71, 9.91, 10.01, 10.01],
    trigo: [7.43, 7.35, 7.28, 7.21, 7.14, 7.07, 7.07],
    vinho: [40.06, 40.47, 40.47, 40.88, 40.88, 40.88, 40.88],
    azeite: [37.21, 36.84, 36.84, 36.48, 36.48, 36.48, 36.48],
    cortica: [32.55, 32.89, 33.22, 33.22, 33.56, 33.56, 33.56],
    la: [30.37, 30.37, 30.07, 30.07, 30.07, 30.07, 30.07],
    couro: [53.83, 52.84, 52.34, 51.34, 50.84, 50.35, 49.85],
    ferro: [38.91, 38.91, 38.91, 38.91, 38.91, 38.91, 38.91],
    cobre: [36.38, 36.38, 36.74, 36.74, 36.74, 36.74, 36.74],
    acucar: [92.37, 91.47, 91.47, 90.58, 89.68, 89.68, 89.68],
    tamaras: [74.02, 74.02, 74.02, 74.02, 74.02, 74.02, 74.02],
    coral: [317.12, 317.12, 313.98, 313.98, 313.98, 313.98, 313.98],
  },
}

/** A port's stock target is the good's base target scaled by the port's size: tier 5 carries a
 *  quarter more than the reference, tier 2 a fifth less. One line, so a bigger port is bigger in
 *  exactly one way and there is nothing to keep in sync. */
function stockTargetFor(port: Port, good: Good): number {
  return Math.round(good.stockTargetBase * (0.5 + 0.15 * port.sizeTier))
}

export const PORT_GOODS: readonly PortGood[] = PORTS.flatMap((port) =>
  GOOD_ORDER.flatMap((code, column): PortGood[] => {
    const affinity = AFFINITY[port.code][column]
    if (affinity === 0) return []
    const good = GOODS.find((g) => g.code === code)
    if (!good) return []
    const stockTarget = stockTargetFor(port, good)
    const ratio = STOCK_RATIO[port.code]?.[code] ?? 1
    const event = port.code === 'FNC' && code === 'couro'
      ? ({ kind: 'SOARING', sinceDays: 2 } as const)
      : undefined
    return [{
      port: port.code,
      good: code,
      affinity,
      stock: Math.round(stockTarget * ratio),
      stockTarget,
      drift: DRIFT[port.code]?.[code] ?? 0,
      seasonMod: SEASON_MOD[port.code]?.[code] ?? 0,
      history7: HISTORY[port.code]?.[code],
      event,
    }]
  }),
)

// ── THE PLAYER ───────────────────────────────────────────────────────────────────────────────

export const PLAYER: Player = {
  companyName: 'Casa de Aveiro',
  nation: 'Portugal',
  ducats: 8000,
  // C.4: Company LV 2 is two fleets and four ships, which is exactly K.1's V0 cap.
  companyLevel: 2,
  maxFleets: 2,
  maxShips: 4,
  // The Mayor of Lisboa taxes the market at 4.0%; a Trusted house pays 3.0%. V0 has no titles, so
  // this penny of relief is reputation, not rank (I.3's ladder arrives with V1).
  taxRelief: 0.01,
  reputation: 2140,
  reputationLabel: 'Trusted',
}

// ── FLEETS AND SHIPS ─────────────────────────────────────────────────────────────────────────
// Two fleets, four ships, per K.1. One is alongside at Lisboa with an empty queue — which is the
// state the CMD tab badges, because an idle fleet is money not working. The other is eight
// voyage-days out on the Las Palmas run with three orders waiting behind the one it is executing.

const MIN = 60_000

export const SHIPS: readonly Ship[] = [
  {
    id: 'ship-gaivota', name: 'Gaivota', classCode: 'barca', fleetId: 'fleet-gaivota',
    isFlagship: true,
    // Repaired to 388 of 400 after the blow off Cape St Vincent (see the ledger).
    durability: 388, crew: 12,
    // 2.4 t water / 1.7 t food on 12 hands = min(10.0, 9.44) = 9.4 voyage-days (C.5).
    waterT: 2.4, foodT: 1.7, cargo: [],
  },
  {
    id: 'ship-andorinha', name: 'Andorinha', classCode: 'caravela_latina', fleetId: 'fleet-aurora',
    isFlagship: true, durability: 505, crew: 24, waterT: 14, foodT: 11,
    cargo: [{ good: 'sal', tuns: 40, avgCost: 7 }],
  },
  {
    id: 'ship-bomjesus', name: 'Bom Jesus', classCode: 'nau', fleetId: 'fleet-aurora',
    isFlagship: false, durability: 1548, crew: 96, waterT: 60, foodT: 45,
    cargo: [{ good: 'trigo', tuns: 120, avgCost: 9 }],
  },
]

/**
 * Aurora's frozen speed, computed once at departure and stored on the voyage (D.2). Work it:
 *   Andorinha  6.0 x (0.60 + 0.40 x 505/550) x (1 - 0.25 x 65/90)  = 6.0 x 0.9673 x 0.8194 = 4.756
 *   Bom Jesus  4.4 x (0.60 + 0.40 x 1548/1800) x (1 - 0.25 x 225/400) = 4.4 x 0.9440 x 0.8594 = 3.570
 *   fleet      min(4.756, 3.570) x M_formation(2 ships = 1.00)                             = 3.570
 * The Nau is the drag, and that is C.4's point: "One tired carrack ruins a fast squadron."
 * 708.7 nm at 3.5695 kn is 8.27 voyage-days, which is 24.8 real minutes.
 */
const AURORA_SPEED_KN = 3.5695

export function buildFleets(nowMs: number): readonly Fleet[] {
  return [
    { id: 'fleet-gaivota', name: 'Gaivota', status: 'DOCKED', portCode: 'LIS', voyage: null },
    {
      id: 'fleet-aurora', name: 'Aurora', status: 'SAILING', portCode: null,
      voyage: {
        id: 'voyage-aurora-1',
        path: ['LIS', 'LPA'],
        departedAtMs: nowMs - 12 * MIN,
        speedKn: AURORA_SPEED_KN,
      },
    },
  ]
}

// ── THE ORDER QUEUE ──────────────────────────────────────────────────────────────────────────
// F.3: one FIFO queue per fleet, twelve orders deep, and every entry is THE RAW STRING the player
// typed or tapped. Nothing is stored parsed, because the server is the parser (F.4 step 4).

export const ORDERS: readonly QueuedOrder[] = [
  { id: 'ord-1', fleetId: 'fleet-aurora', seq: 1, raw: 'SAIL Aurora TO Las Palmas', status: 'active' },
  { id: 'ord-2', fleetId: 'fleet-aurora', seq: 2, raw: 'SELL trigo ALL', status: 'pending' },
  { id: 'ord-3', fleetId: 'fleet-aurora', seq: 3, raw: 'BUY acucar 90 AT <= 60', status: 'pending' },
  { id: 'ord-4', fleetId: 'fleet-aurora', seq: 4, raw: 'SAIL Aurora TO Lisboa', status: 'pending' },
]

// ── THE LEDGER ───────────────────────────────────────────────────────────────────────────────
// E.6, reverse-chronological on screen and chronological here. The balances RUN: 9,400 brought
// into the window, every delta applied in order, 8,000 at the end — which is the player's ducats.
//
// The story is K.1's ten-minute session as it actually plays at V0 quantities: Gaivota loads salt
// at Lisboa where it is 71% of its neighbours, sells it at Cadiz where it is 113%, brings hides
// back the other way, and pays for a gale off Cape St Vincent on the return. Then Aurora is loaded
// and provisioned for Las Palmas and sails while the player is looking at something else.

function ledgerChronological(nowMs: number): readonly Omit<LedgerEntry, 'balanceAfter'>[] {
  return [
    {
      id: 'led-01', atMs: nowMs - 260 * MIN, kind: 'TRADE', actor: 'GAIVOTA',
      headline: 'BOUGHT sal 55 t @ 7 d. · Lisboa', ducatsDelta: -385,
      lines: [
        { label: 'unit', value: '7 d./t (ask)' },
        { label: 'hold after', value: '59.1 / 60 t' },
        { label: '%NBR here', value: '71% — the buy band' },
      ],
    },
    {
      id: 'led-02', atMs: nowMs - 258 * MIN, kind: 'VOYAGE', actor: 'GAIVOTA',
      headline: 'DEPARTED Lisboa for Cadiz · 188 nm', ducatsDelta: 0,
      lines: [{ label: 'estimate', value: '2.1 voyage-days · 6.3 min real' }],
    },
    {
      id: 'led-03', atMs: nowMs - 252 * MIN, kind: 'VOYAGE', actor: 'GAIVOTA',
      headline: 'VOYAGE REPORT · Lisboa to Cadiz', ducatsDelta: -25,
      report: [
        {
          day: 1, hazard: 'PIRATES',
          text:
            'Day 1. Three lateen sail stood out of the Barbary shore an hour after first light and ' +
            'held our course through the forenoon. We had the weather of them and the master would ' +
            'not shorten sail. By the afternoon watch they had fallen away to the south-east and ' +
            'did not close. Nothing carried away, nothing taken.',
        },
        {
          day: 2, hazard: 'CLEAR',
          text: 'Day 2. A quiet run in under Cadiz with the last of the flood. Made fast at noon.',
        },
      ],
      lines: [
        { label: 'wages', value: '2.1 days x 12 crew' },
        { label: 'provisions', value: 'water 0.5 t, food 0.4 t (consumed)' },
        { label: 'damage', value: 'none' },
      ],
    },
    {
      id: 'led-04', atMs: nowMs - 252 * MIN, kind: 'PORT', actor: 'GAIVOTA',
      headline: 'DOCKED Cadiz · port dues', ducatsDelta: -50,
      lines: [{ label: 'dues', value: '50 d. x 1 ship' }],
    },
    {
      id: 'led-05', atMs: nowMs - 251 * MIN, kind: 'TRADE', actor: 'GAIVOTA',
      headline: 'SOLD sal 55 t @ 10 d. · Cadiz', ducatsDelta: 550,
      lines: [
        { label: 'unit', value: '10 d./t (bid)' },
        { label: 'realised margin', value: '+165 d. on 385 d. of capital' },
        { label: '%NBR here', value: '113% — the sell band' },
      ],
    },
    {
      id: 'led-06', atMs: nowMs - 250 * MIN, kind: 'TRADE', actor: 'GAIVOTA',
      headline: 'BOUGHT couro 48 t @ 52 d. · Cadiz', ducatsDelta: -2496,
      lines: [
        { label: 'unit', value: '52 d./t (ask)' },
        { label: '%NBR here', value: '68% — Cadiz is cheap for hides' },
      ],
    },
    {
      id: 'led-07', atMs: nowMs - 248 * MIN, kind: 'VOYAGE', actor: 'GAIVOTA',
      headline: 'DEPARTED Cadiz for Lisboa · 188 nm', ducatsDelta: 0,
    },
    {
      id: 'led-08', atMs: nowMs - 242 * MIN, kind: 'VOYAGE', actor: 'GAIVOTA',
      headline: 'VOYAGE REPORT · Cadiz to Lisboa', ducatsDelta: -24,
      report: [
        {
          day: 1, hazard: 'STORM',
          text:
            'Day 1. It came on to blow hard from the west off Cape St Vincent before the middle ' +
            'watch. We handed everything and ran under bare poles for the better part of a day and ' +
            'a night with the seas making clean over her. The larboard bulwark is stove in forward ' +
            'and we have started a butt somewhere below the waterline; the pumps held it. The hides ' +
            'are wet and will be the worse for it, but nothing went over the side.',
        },
        {
          day: 2, hazard: 'CLEAR',
          text:
            'Day 2. The wind took off with the dawn. Made the bar at Lisboa on the young flood and ' +
            'warped in to the yard.',
        },
      ],
      lines: [
        { label: 'wages', value: '2.0 days x 12 crew' },
        { label: 'damage', value: 'hull 400 to 346 (-13.5%)' },
        { label: 'cargo', value: 'couro 48 t — none jettisoned' },
      ],
      unread: true,
    },
    {
      id: 'led-09', atMs: nowMs - 242 * MIN, kind: 'PORT', actor: 'GAIVOTA',
      headline: 'DOCKED Lisboa · port dues', ducatsDelta: -50,
    },
    {
      id: 'led-10', atMs: nowMs - 240 * MIN, kind: 'TRADE', actor: 'GAIVOTA',
      headline: 'SOLD couro 48 t @ 71 d. · Lisboa', ducatsDelta: 3408,
      lines: [
        { label: 'unit', value: '71 d./t (bid)' },
        { label: 'realised margin', value: '+912 d. on 2,496 d. of capital' },
        { label: 'round trip', value: '+1,077 d. gross, +928 d. after wages and dues' },
      ],
    },
    {
      id: 'led-11', atMs: nowMs - 230 * MIN, kind: 'REPAIR', actor: 'GAIVOTA',
      headline: 'REPAIRED hull 346 to 388 · Lisboa yard', ducatsDelta: -74,
      lines: [
        { label: 'work', value: '42 points x 2.0 d.' },
        { label: 'industry discount', value: 'Lisboa dev_industry 12 = -12%' },
      ],
    },
    {
      id: 'led-12', atMs: nowMs - 26 * MIN, kind: 'TRADE', actor: 'AURORA',
      headline: 'BOUGHT trigo 120 t @ 9 d. · Lisboa', ducatsDelta: -1080,
      lines: [{ label: 'stowed', value: 'Bom Jesus — 120 of 400 t' }],
    },
    {
      id: 'led-13', atMs: nowMs - 22 * MIN, kind: 'TRADE', actor: 'AURORA',
      headline: 'BOUGHT sal 40 t @ 7 d. · Lisboa', ducatsDelta: -280,
      lines: [{ label: 'stowed', value: 'Andorinha — 40 of 90 t' }],
    },
    {
      id: 'led-14', atMs: nowMs - 16 * MIN, kind: 'PROVISION', actor: 'AURORA',
      headline: 'PROVISIONED water 74 t, food 56 t · Lisboa', ducatsDelta: -894,
      lines: [
        { label: 'water', value: '74 t x 3 d.' },
        { label: 'food', value: '56 t x 12 d.' },
        { label: 'endurance', value: '29.2 voyage-days (the Caravela is the short hull)' },
      ],
    },
    {
      id: 'led-15', atMs: nowMs - 12 * MIN, kind: 'VOYAGE', actor: 'AURORA',
      headline: 'DEPARTED Lisboa for Las Palmas · 709 nm', ducatsDelta: 0,
      lines: [
        { label: 'fleet speed', value: '3.6 kn — the Nau sets it' },
        { label: 'estimate', value: '8.3 voyage-days · 24.8 min real' },
      ],
    },
    {
      id: 'led-16', atMs: nowMs - 5 * MIN, kind: 'MARKET', actor: 'MARKET',
      headline: 'couro SOARING in Funchal (+18%, 2 days)', ducatsDelta: 0,
      lines: [
        { label: 'Funchal', value: '211% of its neighbours — the sell band' },
        { label: 'from Lisboa', value: '525 nm · 13 min at a Barca’s pace' },
      ],
      unread: true,
    },
  ]
}

/** The balance carried into the oldest visible entry. Every balanceAfter below is derived from it,
 *  so the column cannot disagree with the deltas beside it. 9,400 - 1,400 = 8,000 = PLAYER.ducats. */
export const LEDGER_OPENING_BALANCE = 9400

function withRunningBalance(nowMs: number): readonly LedgerEntry[] {
  let balance = LEDGER_OPENING_BALANCE
  return ledgerChronological(nowMs).map((entry) => {
    balance += entry.ducatsDelta
    return { ...entry, balanceAfter: balance }
  })
}

// ── THE SNAPSHOT ─────────────────────────────────────────────────────────────────────────────

/** PURE. Give it an instant and it gives back the world at that instant — which is what lets a
 *  spec pin time and still read the same fixture the screens read. */
export function buildV0World(nowMs: number): V0World {
  return {
    nowMs,
    // The calendar clock (D.1) is 1 real day = 1 game month. Six real days back from now is six
    // game months, so the snapshot sits in July 1554 and the season is Summer.
    calendarEpochMs: nowMs - 6 * 24 * 60 * 60 * 1000,
    epochYear: 1554,
    player: PLAYER,
    ports: PORTS,
    legs: LEGS,
    goods: GOODS,
    shipClasses: SHIP_CLASSES,
    fleets: buildFleets(nowMs),
    ships: SHIPS,
    orders: ORDERS,
    portGoods: PORT_GOODS,
    ledger: withRunningBalance(nowMs),
    currentPort: 'LIS',
  }
}

/** A fixed instant for specs: 1 June 2026, 09:00 UTC. Nothing in the app reads it. */
export const FIXTURE_INSTANT_MS = Date.UTC(2026, 5, 1, 9, 0, 0)
