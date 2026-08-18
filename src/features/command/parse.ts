// THE PARSER — one implementation of DESIGN.md F.1, pure, no React.
//
// F.4 step 4: "Submit sends the STRING, not a structured object. The server parses it. There is
// exactly one parser." This is the CLIENT copy, and it exists for exactly one reason: F.5 layer 1,
// the live check line under the input. It is advisory. When the two disagree the server is right.
//
// F.1's rules, each implemented once below:
//   · Case-insensitive.
//   · Diacritics folded — `cadiz` = `Cádiz`, `cortica` = `cortiça`.
//   · Names matched by UNIQUE PREFIX; ambiguity is an error that LISTS THE CANDIDATES.
//   · Numbers accept `_` and `,` separators (`200_000`).
//   · Keywords TO / VIA / AT / IN / AS / FROM / INTO are noise-tolerant — omitting them is
//     accepted when unambiguous, so `SAIL Aurora Amsterdam` parses.
//
// Multi-word names (Las Palmas) are handled by a greedy run: the resolver tries the longest run of
// tokens that is not a keyword or a number, then shortens. This is why `SAIL Aurora TO Las Palmas`
// does not read "Las" as the port and "Palmas" as a stray token.

import type { GoodCode, PortCode } from '../../fixtures/types'
import type { ErrorCode } from './errors'
import type { ParsedOrder, PriceLimit, Qty, Verb } from './grammar'
import { isKeyword, isV0Verb, isVerb } from './grammar'

/** What the parser needs to know about the world to resolve a name. Deliberately minimal: the
 *  parser resolves names, it does not judge states. */
export interface ParseContext {
  fleets: readonly { id: string; name: string }[]
  ports: readonly { code: PortCode; name: string }[]
  goods: readonly { code: GoodCode; name: string; english: string }[]
}

export type ParseResult =
  | { ok: true; order: ParsedOrder }
  | { ok: false; code: ErrorCode; message: string; candidates?: readonly string[] }

/** F.1 — fold case and diacritics. NFD splits an accented letter into base + combining mark, and
 *  the range strip removes the mark, so "Cádiz" and "cadiz" become the same key. */
/** Unicode combining diacritical marks, U+0300..U+036F — written as escapes rather than as literal
 *  marks so the source stays greppable and cannot be mangled by an editor's normalisation. */
const COMBINING_MARKS = new RegExp('[\\u0300-\\u036f]', 'g')

export function fold(text: string): string {
  return text.normalize('NFD').replace(COMBINING_MARKS, '').toLowerCase()
}

/** F.1 — `200_000` and `1,500` are numbers. Returns null when the token is not one. */
export function parseNumber(token: string): number | null {
  const cleaned = token.replace(/[_,]/g, '')
  if (!/^\d+(\.\d+)?$/.test(cleaned)) return null
  return Number(cleaned)
}

function isNumeric(token: string): boolean {
  return parseNumber(token) !== null
}

/** Tokenise. Comparators are split off a glued number so `AT<=700` and `AT <= 700` are one thing. */
export function tokenize(raw: string): string[] {
  return raw
    .replace(/(<=|>=|=<|=>)/g, ' $1 ')
    .trim()
    .split(/[\s,]+/)
    .filter((t) => t.length > 0)
}

interface Candidate<T> {
  value: T
  /** Display name, for the ambiguity list. */
  label: string
  /** Every string this candidate answers to, already folded. */
  keys: readonly string[]
}

type Resolution<T> =
  | { kind: 'found'; value: T; consumed: number }
  | { kind: 'ambiguous'; candidates: readonly string[] }
  | { kind: 'none' }

/** THE NAME RESOLVER — F.1's prefix rule, once, for fleets, ports and goods alike. */
function resolveName<T>(
  tokens: readonly string[],
  at: number,
  candidates: readonly Candidate<T>[],
): Resolution<T> {
  // How many tokens could belong to this name? Stop at a keyword, a number or a comparator.
  let run = 0
  while (
    at + run < tokens.length &&
    run < 3 &&
    !isKeyword(tokens[at + run]) &&
    !isNumeric(tokens[at + run]) &&
    !/^(<=|>=|=<|=>)$/.test(tokens[at + run])
  ) {
    run += 1
  }
  if (run === 0) return { kind: 'none' }

  for (let k = run; k >= 1; k -= 1) {
    const query = fold(tokens.slice(at, at + k).join(' '))
    const exact = candidates.filter((c) => c.keys.includes(query))
    if (exact.length === 1) return { kind: 'found', value: exact[0].value, consumed: k }
    if (exact.length > 1) return { kind: 'ambiguous', candidates: exact.map((c) => c.label) }
    const prefixed = candidates.filter((c) => c.keys.some((key) => key.startsWith(query)))
    if (prefixed.length === 1) return { kind: 'found', value: prefixed[0].value, consumed: k }
    // A longer run that is ambiguous stays ambiguous when shortened, so answer here.
    if (prefixed.length > 1) return { kind: 'ambiguous', candidates: prefixed.map((c) => c.label) }
  }
  return { kind: 'none' }
}

function fleetCandidates(ctx: ParseContext): Candidate<string>[] {
  return ctx.fleets.map((f) => ({ value: f.id, label: f.name, keys: [fold(f.name)] }))
}

function portCandidates(ctx: ParseContext): Candidate<PortCode>[] {
  return ctx.ports.map((p) => ({
    value: p.code,
    label: p.name,
    keys: [fold(p.name), fold(p.code)],
  }))
}

function goodCandidates(ctx: ParseContext): Candidate<GoodCode>[] {
  return ctx.goods.map((g) => ({
    value: g.code,
    label: g.name,
    keys: [fold(g.name), fold(g.code), fold(g.english)],
  }))
}

/** A cursor over the token stream, so each verb's parser reads rather than indexes. */
class Cursor {
  private i = 0
  readonly tokens: readonly string[]
  constructor(tokens: readonly string[]) {
    this.tokens = tokens
  }
  get done(): boolean {
    return this.i >= this.tokens.length
  }
  peek(): string | null {
    return this.i < this.tokens.length ? this.tokens[this.i] : null
  }
  get index(): number {
    return this.i
  }
  advance(n = 1): void {
    this.i += n
  }
  /** Consume a keyword if it is next. Noise-tolerant: absent is fine (F.1). */
  eatKeyword(...words: string[]): boolean {
    const next = this.peek()
    if (next && words.some((w) => w.toUpperCase() === next.toUpperCase())) {
      this.i += 1
      return true
    }
    return false
  }
  eatComparator(): '<=' | '>=' | null {
    const next = this.peek()
    if (next === '<=' || next === '=<') {
      this.i += 1
      return '<='
    }
    if (next === '>=' || next === '=>') {
      this.i += 1
      return '>='
    }
    return null
  }
  eatNumber(): number | null {
    const next = this.peek()
    if (next === null) return null
    const n = parseNumber(next)
    if (n === null) return null
    this.i += 1
    return n
  }
}

function fail(code: ErrorCode, message: string, candidates?: readonly string[]): ParseResult {
  return { ok: false, code, message, candidates }
}

function readFleet(cur: Cursor, ctx: ParseContext, what: string): string | ParseResult {
  const res = resolveName(cur.tokens, cur.index, fleetCandidates(ctx))
  if (res.kind === 'ambiguous') {
    return fail('E_AMBIGUOUS', `"${cur.peek()}" could be ${res.candidates.join(' or ')}.`, res.candidates)
  }
  if (res.kind === 'none') {
    return fail(
      'E_NO_SUCH_FLEET',
      cur.done ? `${what} needs a fleet.` : `You have no fleet called "${cur.peek()}".`,
    )
  }
  cur.advance(res.consumed)
  return res.value
}

function readPort(cur: Cursor, ctx: ParseContext): PortCode | ParseResult {
  const res = resolveName(cur.tokens, cur.index, portCandidates(ctx))
  if (res.kind === 'ambiguous') {
    return fail('E_AMBIGUOUS', `"${cur.peek()}" could be ${res.candidates.join(' or ')}.`, res.candidates)
  }
  if (res.kind === 'none') {
    return fail(
      'E_NO_SUCH_PORT',
      cur.done ? 'Name a port to sail to.' : `There is no port called "${cur.peek()}" in these waters.`,
    )
  }
  cur.advance(res.consumed)
  return res.value
}

function readGood(cur: Cursor, ctx: ParseContext): GoodCode | ParseResult {
  const res = resolveName(cur.tokens, cur.index, goodCandidates(ctx))
  if (res.kind === 'ambiguous') {
    return fail('E_AMBIGUOUS', `"${cur.peek()}" could be ${res.candidates.join(' or ')}.`, res.candidates)
  }
  if (res.kind === 'none') {
    return fail(
      'E_NO_SUCH_GOOD',
      cur.done ? 'Name something to trade.' : `Nobody here trades "${cur.peek()}".`,
    )
  }
  cur.advance(res.consumed)
  return res.value
}

function readQty(cur: Cursor): Qty | ParseResult {
  const next = cur.peek()
  if (next === null) return fail('E_PARSE', 'How much? Give a number of tuns, or ALL, or HALF.')
  const upper = next.toUpperCase()
  if (upper === 'ALL') {
    cur.advance()
    return { kind: 'ALL' }
  }
  if (upper === 'HALF') {
    cur.advance()
    return { kind: 'HALF' }
  }
  const pct = /^(\d+)%$/.exec(next)
  if (pct) {
    cur.advance()
    return { kind: 'percent', pct: Number(pct[1]) }
  }
  const n = cur.eatNumber()
  if (n === null) return fail('E_PARSE', `"${next}" is not a quantity. Give a number, ALL or HALF.`)
  return { kind: 'exact', tuns: n }
}

function readLimit(cur: Cursor, fallbackOp: '<=' | '>='): PriceLimit | null | ParseResult {
  if (!cur.eatKeyword('AT')) return null
  const op = cur.eatComparator() ?? fallbackOp
  const price = cur.eatNumber()
  if (price === null) return fail('E_PARSE', 'AT needs a price, e.g. AT <= 60.')
  return { op, price }
}

function isFailure(v: unknown): v is ParseResult {
  return typeof v === 'object' && v !== null && 'ok' in v && (v as ParseResult).ok === false
}

/** THE ENTRY POINT. Parses a raw command line into a ParsedOrder, or into the exact refusal the
 *  check line under the input will print. */
export function parseOrder(raw: string, ctx: ParseContext): ParseResult {
  const tokens = tokenize(raw)
  if (tokens.length === 0) return fail('E_PARSE', 'Type an order, or tap a verb below.')

  const head = tokens[0].toUpperCase()
  if (!isVerb(head)) {
    return fail('E_PARSE', `"${tokens[0]}" is not an order. Tap a verb below to see the shape.`)
  }
  const verb: Verb = head
  const base: ParsedOrder = { verb, raw, locked: !isV0Verb(verb) }
  // A real verb outside the V0 slice is REFUSED, not misparsed: the player is told why by
  // validate(), and the argument grammar for a verb that does nothing is never exercised.
  if (base.locked) return { ok: true, order: base }

  const cur = new Cursor(tokens)
  cur.advance()

  switch (verb) {
    case 'SAIL': {
      const fleetId = readFleet(cur, ctx, 'SAIL')
      if (isFailure(fleetId)) return fleetId
      cur.eatKeyword('TO')
      const port = readPort(cur, ctx)
      if (isFailure(port)) return port
      const via: PortCode[] = []
      while (cur.eatKeyword('VIA')) {
        const stop = readPort(cur, ctx)
        if (isFailure(stop)) return stop
        via.push(stop)
      }
      let speed: 'cruise' | 'press' | undefined
      if (cur.eatKeyword('SPEED')) {
        const word = cur.peek()?.toLowerCase()
        if (word !== 'cruise' && word !== 'press') {
          return fail('E_PARSE', 'SPEED takes cruise or press.')
        }
        cur.advance()
        speed = word
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a SAIL order.`)
      return { ok: true, order: { ...base, fleetId, port, via, speed } }
    }

    case 'BUY':
    case 'SELL': {
      const good = readGood(cur, ctx)
      if (isFailure(good)) return good
      const qty = readQty(cur)
      if (isFailure(qty)) return qty
      const limit = readLimit(cur, verb === 'BUY' ? '<=' : '>=')
      if (isFailure(limit)) return limit
      let fleetId: string | undefined
      if (cur.eatKeyword('FOR', 'FROM')) {
        const f = readFleet(cur, ctx, verb)
        if (isFailure(f)) return f
        fleetId = f
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a ${verb} order.`)
      return { ok: true, order: { ...base, good, qty, limit: limit ?? undefined, fleetId } }
    }

    case 'PROVISION': {
      const fleetId = readFleet(cur, ctx, 'PROVISION')
      if (isFailure(fleetId)) return fleetId
      let provision: ParsedOrder['provision']
      const next = cur.peek()?.toUpperCase()
      if (next === 'FULL') {
        cur.advance()
        provision = { mode: 'FULL' }
      } else if (next === 'WATER') {
        cur.advance()
        const waterT = cur.eatNumber()
        if (waterT === null) return fail('E_PARSE', 'WATER needs a number of tuns.')
        if (cur.eatKeyword('FOOD')) {
          const foodT = cur.eatNumber()
          if (foodT === null) return fail('E_PARSE', 'FOOD needs a number of tuns.')
          provision = { mode: 'EXPLICIT', waterT, foodT }
        } else {
          provision = { mode: 'EXPLICIT', waterT, foodT: 0 }
        }
      } else {
        const days = cur.eatNumber()
        if (days !== null) {
          cur.eatKeyword('DAYS')
          provision = { mode: 'DAYS', days }
        } else {
          provision = { mode: 'FULL' }
        }
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a PROVISION order.`)
      return { ok: true, order: { ...base, fleetId, provision } }
    }

    case 'HIRE': {
      const crewCount = cur.eatNumber()
      if (crewCount === null) return fail('E_PARSE', 'HIRE needs a number of hands, e.g. HIRE 8 CREW.')
      cur.eatKeyword('CREW')
      let fleetId: string | undefined
      if (cur.eatKeyword('FOR')) {
        const f = readFleet(cur, ctx, 'HIRE')
        if (isFailure(f)) return f
        fleetId = f
      } else if (!cur.done) {
        const f = readFleet(cur, ctx, 'HIRE')
        if (isFailure(f)) return f
        fleetId = f
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a HIRE order.`)
      return { ok: true, order: { ...base, crewCount, fleetId } }
    }

    case 'REPAIR': {
      const fleetId = readFleet(cur, ctx, 'REPAIR')
      if (isFailure(fleetId)) return fleetId
      let repairToPct: number | undefined
      if (cur.eatKeyword('TO')) {
        const pct = cur.eatNumber()
        if (pct === null) return fail('E_PARSE', 'REPAIR TO needs a percentage, e.g. REPAIR Gaivota TO 100.')
        repairToPct = pct
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a REPAIR order.`)
      return { ok: true, order: { ...base, fleetId, repairToPct } }
    }

    case 'CANCEL': {
      const fleetId = readFleet(cur, ctx, 'CANCEL')
      if (isFailure(fleetId)) return fleetId
      const orderIndex = cur.eatNumber() ?? undefined
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a CANCEL order.`)
      return { ok: true, order: { ...base, fleetId, orderIndex } }
    }

    case 'CLEAR': {
      const fleetId = readFleet(cur, ctx, 'CLEAR')
      if (isFailure(fleetId)) return fleetId
      let includeActive = false
      if (cur.peek()?.toUpperCase() === 'ALL') {
        cur.advance()
        includeActive = true
      }
      if (!cur.done) return fail('E_PARSE', `"${cur.peek()}" does not belong in a CLEAR order.`)
      return { ok: true, order: { ...base, fleetId, includeActive } }
    }

    default:
      // Unreachable: every V0 verb has a case, and every non-V0 verb returned above.
      return fail('E_PARSE', `${verb} is not yet implemented.`)
  }
}
