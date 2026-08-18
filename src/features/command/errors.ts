// THE ERROR VOCABULARY — DESIGN.md F.5's full list, verbatim, plus the fail-closed copy map.
//
// F.5: "Errors are a code, a sentence, and a fix — never a bare code." So this file holds the
// codes and a GENERIC sentence for each, and the validator that raises one supplies the SPECIFIC
// sentence (with the fleet's real endurance, the real free hold, the real limit price) plus the
// insertable fixes. The generic sentence exists so that an unmapped or server-only code reaching
// the screen still reads as English instead of as a token — CORE_REUSE 2.1: "A raw
// insufficient_cargo reaching the player is not a cosmetic bug in a text game; it is the game
// failing to speak."
//
// The list is closed on purpose. A validator may not invent a code; if a new refusal exists, it
// gets a code here first, and the server's vocabulary and this one stay the same vocabulary.

export const ERROR_CODES = [
  'E_PARSE',
  'E_AMBIGUOUS',
  'E_NO_SUCH_FLEET',
  'E_NO_SUCH_PORT',
  'E_NO_SUCH_GOOD',
  'E_NO_SUCH_SHIP',
  'E_NO_SUCH_OFFICER',
  'E_NOT_DOCKED',
  'E_NOT_SAILING',
  'E_NOT_AT_PORT',
  'E_NO_ROUTE',
  'E_ENDURANCE',
  'E_CREW_SHORT',
  'E_CREW_MAX',
  'E_CREW_POOL',
  'E_DRAFT',
  'E_PORT_CLOSED',
  'E_FLAGSHIP_DISABLED',
  'E_LANGUAGE',
  'E_INSUFFICIENT_FUNDS',
  'E_HOLD_FULL',
  'E_NO_CARGO',
  'E_NO_STOCK',
  'E_UNAVAILABLE',
  'E_DAILY_CAP',
  'E_PRICE_LIMIT',
  'E_MIN_INVEST',
  'E_WEEKLY_CAP',
  'E_NO_PRESENCE',
  'E_SEASON_CLOSED',
  'E_FLEET_CAP',
  'E_FLEET_SIZE',
  'E_SHIP_CAP',
  'E_LAST_SHIP',
  'E_DIFFERENT_PORT',
  'E_YARD_TIER',
  'E_NO_YARD',
  'E_NO_BLUEPRINT',
  'E_MATERIALS',
  'E_SCOUTING',
  'E_ALREADY_EXPLORED',
  'E_ALREADY_REPORTED',
  'E_NO_ACADEMY',
  'E_QUEUE_FULL',
  'E_RANK_LOCKED',
  'E_STALE',
] as const

export type ErrorCode = (typeof ERROR_CODES)[number]

const CODE_SET: ReadonlySet<string> = new Set(ERROR_CODES)

export function isErrorCode(value: string): value is ErrorCode {
  return CODE_SET.has(value)
}

/** The generic sentence — the fallback when a caller has no specific one to give. Every entry is
 *  a complete sentence in the player's language, never a restatement of the code. */
export const ERROR_SENTENCE: Record<ErrorCode, string> = {
  E_PARSE: 'That is not an order this game understands.',
  E_AMBIGUOUS: 'That name matches more than one thing.',
  E_NO_SUCH_FLEET: 'You have no fleet by that name.',
  E_NO_SUCH_PORT: 'There is no port by that name in these waters.',
  E_NO_SUCH_GOOD: 'Nobody trades anything by that name.',
  E_NO_SUCH_SHIP: 'You own no ship by that name.',
  E_NO_SUCH_OFFICER: 'No officer of yours answers to that name.',
  E_NOT_DOCKED: 'That fleet is not alongside. It must be docked to do this.',
  E_NOT_SAILING: 'That fleet is not at sea.',
  E_NOT_AT_PORT: 'That fleet is not lying off a port.',
  E_NO_ROUTE: 'No sailed route connects those two ports.',
  E_ENDURANCE: 'That fleet does not carry enough water and food for the passage.',
  E_CREW_SHORT: 'That fleet is short-handed and cannot sail.',
  E_CREW_MAX: 'Those ships cannot berth that many hands.',
  E_CREW_POOL: 'This port has no more men to give.',
  E_DRAFT: 'That harbour is too shallow for the deepest hull in the fleet.',
  E_PORT_CLOSED: 'That port is closed.',
  E_FLAGSHIP_DISABLED: 'The flagship is disabled. The fleet cannot sail until it is repaired.',
  E_LANGUAGE: 'You cannot make yourself understood in that port.',
  E_INSUFFICIENT_FUNDS: 'You do not have the ducats.',
  E_HOLD_FULL: 'There is not that much room in the hold.',
  E_NO_CARGO: 'That fleet is not carrying it.',
  E_NO_STOCK: 'The port has none to sell.',
  E_UNAVAILABLE: 'That good is not traded here this season.',
  E_DAILY_CAP: 'You have moved as much of that good here as the port will let you today.',
  E_PRICE_LIMIT: 'The market will not meet your limit.',
  E_MIN_INVEST: 'That is below the minimum investment.',
  E_WEEKLY_CAP: 'That would exceed your weekly ceiling in this port.',
  E_NO_PRESENCE: 'You have no agent in that port this season.',
  E_SEASON_CLOSED: 'The investment season is closed.',
  E_FLEET_CAP: 'Your company cannot command another fleet yet.',
  E_FLEET_SIZE: 'A fleet cannot carry more than eight ships.',
  E_SHIP_CAP: 'Your company cannot own another ship yet.',
  E_LAST_SHIP: 'A fleet cannot be left without a ship.',
  E_DIFFERENT_PORT: 'Those fleets are not in the same port.',
  E_YARD_TIER: 'This yard cannot build that class.',
  E_NO_YARD: 'There is no repair yard in this port.',
  E_NO_BLUEPRINT: 'You do not hold that blueprint.',
  E_MATERIALS: 'You do not have the materials.',
  E_SCOUTING: 'Nobody aboard can survey that.',
  E_ALREADY_EXPLORED: 'That has already been explored.',
  E_ALREADY_REPORTED: 'That has already been reported.',
  E_NO_ACADEMY: 'There is no academy in this port.',
  E_QUEUE_FULL: 'That fleet already holds twelve orders.',
  E_RANK_LOCKED: 'That order is not open to you in this version of the game.',
  E_STALE: 'That fleet changed underneath you. Read it again and reissue.',
}

/** The fail-closed mapper. An unknown string never reaches the player as a token. */
export function errorSentence(code: string): string {
  return isErrorCode(code) ? ERROR_SENTENCE[code] : 'That order cannot be carried out.'
}

/** An insertable fix (F.5): a real, complete command the player can tap to put in the input. */
export interface Fix {
  /** The command string. Tapping it REPLACES the input — the player then edits or submits. */
  command: string
  /** Optional parenthetical, e.g. "(est. 8,240 d.)" or "(take the market)". */
  note?: string
}
