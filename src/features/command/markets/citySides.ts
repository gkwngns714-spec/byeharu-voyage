import type { GoodBoard } from '../../../lib/rpc'

// BOTH SIDES OF ONE GOOD, CITY BY CITY — the two halves of what the board already serves, joined.
//
// THE OWNER, 2026-10-20 (request 178): *"I want both for all cities."*
//
// `world.good_board` answers a good's page in TWO lists (0171): `buy` — the cities that SELL it, each
// with what the asked amount costs there (`world.quote`, buy side) — and `sell` — every harbour whose
// culture buys it, the dearest `good_board_quoted` of them priced in full (`world.quote`, sell side),
// the rest carrying the market's middle price alone. A city that sells a good also buys it, so it
// stands in both lists and BOTH SIDES OF ITS PRICE ARE ALREADY SERVED; they were simply drawn in two
// different places, in the same ink, with no word saying which side each figure was.
//
// This joins them BY CITY and does nothing else. No price is derived, no side is inferred from the
// other: the spread, the tax and the city's bid factor belong to `world.price_sides` and a round trip
// never pays (0211). A side the board did not price stays `null` here and prints as a dash.
//
// WHAT IT CANNOT DO, said plainly: the board prices the sell side at the dearest
// `good_board_quoted` cities (10 on production), so a cheap selling city usually has an ask here and
// no bid. The whole pair for every city is one `world.good_board` change away — one extra
// `world.price` per row, 236 ms for 238 cities as COMMAND_DESK §1.4 measured it — and that is a
// migration, written down in docs/dev-log/2026-10-20-prices-both-ways.md rather than guessed at here.

export interface CitySides {
  /** What ONE unit costs you there, as the board priced the asked amount. Null: it is not sold there. */
  pay: number | null
  /** What ONE unit pays you there. Null: the board did not price this side at this city. */
  get: number | null
  /** The market's middle price there — what the chart's line is made of. Null: unserved. */
  mid: number | null
}

const NO_SIDES: CitySides = { pay: null, get: null, mid: null }

/** Every city the board names, with both sides of its price as the board serves them. */
export function citySides(board: GoodBoard | null): Record<string, CitySides> {
  const out: Record<string, CitySides> = {}
  const at = (port: string): CitySides => {
    const had = out[port]
    if (had) return had
    const fresh: CitySides = { pay: null, get: null, mid: null }
    out[port] = fresh
    return fresh
  }
  for (const r of board?.buy ?? []) at(r.port).pay = r.price_each
  for (const r of board?.sell ?? []) {
    const s = at(r.port)
    s.mid = r.mid
    s.get = r.quoted ? r.price_each : null
  }
  return out
}

/** One city's sides, or the empty pair when the board does not name it (and while it is on the wire). */
export function sidesAt(sides: Record<string, CitySides>, port: string | null): CitySides {
  return (port ? sides[port] : null) ?? NO_SIDES
}
