// THE GRAMMAR TABLE — DESIGN.md F.1's EBNF and F.2's verb reference, as data.
//
// ONE GRAMMAR, TWO INPUT METHODS (F.4). The keyboard path reads this table to know what a verb
// means; the tap-builder reads the SAME table to know what pickers to show, and then emits the
// string a keyboard would have typed. There is no second definition of what SAIL takes, which is
// the whole reason a player can learn the language by tapping and then start typing it without
// hitting a behaviour change.
//
// When the server lands this table is replaced by cmd.verb_schema() (Appendix 2) — "served by
// cmd.verb_schema() so the grammar has one authority". The shape below is the shape that RPC
// should return, so that swap is a fetch, not a rewrite.
//
// TWENTY-SEVEN VERBS, NOT TWENTY-SIX. F.1's EBNF lists 27 (E.1's verb pad shows 21 of them, for
// space). The EBNF is the grammar, so the EBNF is what is implemented; the count is recorded here
// rather than silently reconciled. See README.md.

import type { GoodCode, PortCode } from '../../fixtures/types'

export const VERBS = [
  'SAIL', 'DOCK', 'ANCHOR', 'RECALL', 'WAIT',
  'BUY', 'SELL', 'LOAD', 'UNLOAD', 'TRANSFER',
  'PROVISION', 'HIRE', 'DISCHARGE', 'REPAIR',
  'SPLIT', 'MERGE', 'FLAG', 'RENAME', 'ASSIGN',
  'INVEST', 'BUILD', 'SCRAP',
  'EXPLORE', 'SURVEY', 'REPORT',
  'CANCEL', 'CLEAR',
] as const

export type Verb = (typeof VERBS)[number]

const VERB_SET: ReadonlySet<string> = new Set(VERBS)

export function isVerb(word: string): word is Verb {
  return VERB_SET.has(word)
}

/** K.1 — the eight the V0 slice ships. Everything else parses (so the player is told WHY, not
 *  told "unknown verb") and is refused with E_RANK_LOCKED. */
export const V0_VERBS: readonly Verb[] = [
  'SAIL', 'BUY', 'SELL', 'PROVISION', 'HIRE', 'REPAIR', 'CANCEL', 'CLEAR',
]

const V0_SET: ReadonlySet<string> = new Set(V0_VERBS)

export function isV0Verb(verb: Verb): boolean {
  return V0_SET.has(verb)
}

/** F.1 — keywords are noise-tolerant: omitting them is accepted when unambiguous, so
 *  `SAIL Aurora Amsterdam` parses. They are consumed as separators, never as values. */
export const KEYWORDS: readonly string[] = [
  'TO', 'VIA', 'AT', 'IN', 'AS', 'FROM', 'INTO', 'ONTO', 'FOR', 'WITH',
  'SPEED', 'DAYS', 'CREW', 'SHIPS', 'ROUTE', 'NAME', 'WAREHOUSE',
]

const KEYWORD_SET: ReadonlySet<string> = new Set(KEYWORDS)

export function isKeyword(word: string): boolean {
  return KEYWORD_SET.has(word.toUpperCase())
}

// ── THE TAP-BUILDER SCHEMA ───────────────────────────────────────────────────────────────────

export type SlotKind =
  /** Pick one of the player's fleets. */
  | 'fleet'
  /** Pick a port. */
  | 'port'
  /** Pick a good traded in the port the fleet is lying in. */
  | 'good'
  /** ALL / HALF / a number of tuns. */
  | 'qty'
  /** A whole number (crew, order index, price). */
  | 'number'
  /** One of a fixed set of literal tokens. */
  | 'choice'

export interface Slot {
  kind: SlotKind
  /** What the picker is called on screen. */
  label: string
  /** The keyword emitted before the value, if the grammar has one ("TO", "AT <="). */
  keyword?: string
  /** Optional slots may be skipped; the builder shows a "skip" chip. */
  optional?: boolean
  /** `choice` slots only: the literal token runs the player may pick between. */
  options?: readonly string[]
  /** `number` slots only: suggested values, so a phone never needs a keyboard. */
  suggestions?: readonly number[]
}

export interface VerbSpec {
  verb: Verb
  /** One line, in the player's language, for the verb pad. */
  summary: string
  /** F.2's shape line, e.g. "SAIL <fleet> TO <port> [VIA <port> ...]". */
  shape: string
  slots: readonly Slot[]
}

/** The eight V0 verbs, with the argument schema the tap-builder walks. Non-V0 verbs carry no slot
 *  list on purpose: the builder cannot compose an order the game will not accept. */
export const VERB_SPECS: readonly VerbSpec[] = [
  {
    verb: 'SAIL',
    summary: 'Send a fleet to sea.',
    shape: 'SAIL <fleet> TO <port> [VIA <port> ...] [SPEED cruise|press]',
    slots: [
      { kind: 'fleet', label: 'Fleet' },
      { kind: 'port', label: 'Destination', keyword: 'TO' },
      { kind: 'port', label: 'Call on the way', keyword: 'VIA', optional: true },
      { kind: 'choice', label: 'Pace', keyword: 'SPEED', optional: true, options: ['cruise', 'press'] },
    ],
  },
  {
    verb: 'BUY',
    summary: 'Take cargo aboard at the market price.',
    shape: 'BUY <good> <qty> [AT <= price] [FOR <fleet>]',
    slots: [
      { kind: 'good', label: 'Good' },
      { kind: 'qty', label: 'Tuns' },
      { kind: 'number', label: 'Pay no more than', keyword: 'AT <=', optional: true },
      { kind: 'fleet', label: 'Fleet', keyword: 'FOR', optional: true },
    ],
  },
  {
    verb: 'SELL',
    summary: 'Put cargo on the market.',
    shape: 'SELL <good> <qty|ALL|HALF> [AT >= price] [FROM <fleet>]',
    slots: [
      { kind: 'good', label: 'Good' },
      { kind: 'qty', label: 'Tuns' },
      { kind: 'number', label: 'Take no less than', keyword: 'AT >=', optional: true },
      { kind: 'fleet', label: 'Fleet', keyword: 'FROM', optional: true },
    ],
  },
  {
    verb: 'PROVISION',
    summary: 'Buy water and food.',
    shape: 'PROVISION <fleet> [FULL | <days> DAYS]',
    slots: [
      { kind: 'fleet', label: 'Fleet' },
      { kind: 'choice', label: 'How much', optional: true, options: ['FULL', '15 DAYS', '30 DAYS', '45 DAYS'] },
    ],
  },
  {
    verb: 'HIRE',
    summary: 'Sign on hands from the port.',
    shape: 'HIRE <count> CREW [FOR <fleet>]',
    slots: [
      { kind: 'number', label: 'Hands', suggestions: [4, 8, 12, 20, 40] },
      { kind: 'choice', label: '', options: ['CREW'] },
      { kind: 'fleet', label: 'Fleet', keyword: 'FOR', optional: true },
    ],
  },
  {
    verb: 'REPAIR',
    summary: 'Put a fleet in the yard.',
    shape: 'REPAIR <fleet> [TO <pct>]',
    slots: [
      { kind: 'fleet', label: 'Fleet' },
      { kind: 'number', label: 'Repair to', keyword: 'TO', optional: true, suggestions: [80, 90, 100] },
    ],
  },
  {
    verb: 'CANCEL',
    summary: 'Drop an order from the queue.',
    shape: 'CANCEL <fleet> [<index>]',
    slots: [
      { kind: 'fleet', label: 'Fleet' },
      { kind: 'number', label: 'Order', optional: true, suggestions: [1, 2, 3, 4] },
    ],
  },
  {
    verb: 'CLEAR',
    summary: 'Drop every pending order.',
    shape: 'CLEAR <fleet> [ALL]',
    slots: [
      { kind: 'fleet', label: 'Fleet' },
      { kind: 'choice', label: 'Also recall the voyage', optional: true, options: ['ALL'] },
    ],
  },
]

export function verbSpec(verb: Verb): VerbSpec | undefined {
  return VERB_SPECS.find((s) => s.verb === verb)
}

// ── THE PARSED ORDER ─────────────────────────────────────────────────────────────────────────

export type Qty =
  | { kind: 'exact'; tuns: number }
  | { kind: 'ALL' }
  | { kind: 'HALF' }
  | { kind: 'percent'; pct: number }

export interface PriceLimit {
  op: '<=' | '>='
  price: number
}

export type ProvisionTarget =
  | { mode: 'FULL' }
  | { mode: 'DAYS'; days: number }
  | { mode: 'EXPLICIT'; waterT: number; foodT: number }

export interface ParsedOrder {
  verb: Verb
  /** The exact string the player submitted — the only thing the server will ever be sent. */
  raw: string
  /** True when the verb is real but outside K.1's V0 slice. */
  locked: boolean
  fleetId?: string
  port?: PortCode
  via?: readonly PortCode[]
  good?: GoodCode
  qty?: Qty
  limit?: PriceLimit
  /** HIRE: hands to sign on. */
  crewCount?: number
  /** CANCEL: 1-based order index. Absent means "the head of the queue". */
  orderIndex?: number
  /** CLEAR ALL — also recalls the active voyage (F.3). */
  includeActive?: boolean
  provision?: ProvisionTarget
  /** REPAIR TO <pct>. */
  repairToPct?: number
  speed?: 'cruise' | 'press'
}
