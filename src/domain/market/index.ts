// THE MARKET, AS A RULE OF THE GAME — not as a screen.
//
// MOVED HERE 2026-09-01 from features/market/marketRows.ts. `buyableHere` answers a question about
// the WORLD ("does this city sell this?"), and once PORT began trading too (OWNER_REQUESTS row 53)
// two screens needed it. `tests/sections.spec.ts` refuses one screen reaching into another and its
// message names the cure: move what is shared into a section of its own under src/domain.
//
// A section stands on `lib` and on nothing above it, which this does: it reads two SERVED fields
// and derives nothing.

import type { MarketGood } from '../../lib/rpc'

/**
 * The four blocks the table is cut into. Three are §E.4's bands, read straight off the server's
 * `advice`. The fourth is not a band at all: `available: false` means the port's culture will not
 * trade the good AT ALL (§B.4 — wine in a Maghrebi port), which is a fact about the port and can
 * never be advice to buy it.
 */
/**
 * 0071 — WHAT A ROW IS, not what to do about it. These used to be `buy | sell | hold`, cut from
 * this quay's mid as a percentage of its neighbours. That comparison is the answer the game exists
 * to make the player find (the owner: *"the game is to challenge players for finding the best
 * prices by themselves"*), so it is gone, and with it the only thing the blocks could sort by.
 *
 * What is left is a FACT about each row: this city deals in it, or it is only in the payload
 * because a fleet of yours lies here carrying it.
 */
export type MarketBlock = 'traded' | 'unavailable'

/**
 * 0061 — CAN THIS BE BOUGHT AT THIS QUAY AT ALL? THE one reading of that question on this screen;
 * everything that draws a price cell, a tap target or a block asks it rather than testing a field.
 *
 * There are two reasons a city will not sell a good and they are different facts about the port:
 * `available: false` is the CULTURE mask (§B.4 — wine in a Maghrebi port), and `offered: false` is
 * the ROSTER — a city trades 4-10 goods (the owner, docs/OWNER_REQUESTS.md row 48) and
 * `public.port_offers` is the server's one authority for which. `cmd.do_buy` refuses BOTH with the
 * same E_UNAVAILABLE, so this screen must not offer a buy for either; "not traded here" is already
 * the sentence it says, and it is true of both.
 *
 * A row can be `offered: false` and still be in the payload: `world.market` carries the goods a
 * fleet of yours is lying here CARRYING, so that they can be sold. Selling is composed on COMMAND,
 * whose sell list is deliberately not narrowed by this predicate.
 */
export function buyableHere(good: MarketGood): boolean {
  return good.available && good.offered !== false
}
