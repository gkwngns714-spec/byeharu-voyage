// THE HAND-OFF — the ONE place the MARKET tab touches the CMD tab.
//
// §E.4: "tap a row → BUY/SELL prefilled on CMD." The market never issues an order and never
// composes one twice: it names an INTENT (this fleet, this verb, this good, this much) and hands
// it to the command draft, which is the single authority for the order being made.
//
// ── WHY THIS FILE IS THREE LINES OF BODY ────────────────────────────────────────────────────────
// `features/command/commandDraft.ts` is owned by the CMD tab and changed under this one on
// 2026-08-19: the draft went from a half-typed STRING to a structured intent (fleet + verb +
// a value per argument NAME as the server's own verb schema names them). Everything the market
// knows about that seam is `handOffTrade` below, so a change to the draft's shape is reconciled in
// exactly one function and no screen code moves. That is the whole reason this file exists.
//
// ARGUMENT NAMES AND VALUES come from the chain, not from taste: `snapshot.verbs` gives BUY and
// SELL the arguments `good`, `qty` and an optional `limit` (migration 0008), and the values are the
// literal tokens the order line will carry — a good CODE (`sal`), which `cmd.resolve_good()`
// matches exactly, never the printed name, which may be two words.
//
// QUANTITIES. A BUY is prefilled with what the hold can still take, because the answer to "how
// much" is almost always "as much as fits". A SELL is prefilled with the word ALL, which the
// grammar reads WHEN THE ORDER RUNS rather than when it is made — so it is still right after a
// voyage that changed the hold. Neither is a price and neither is binding: CMD previews the order
// and the server prices it.

import { useCommandDraft } from './draft'

export interface TradeIntent {
  /** The fleet the order belongs to; null when the player has none here and CMD must ask. */
  fleetId: string | null
  verb: 'BUY' | 'SELL'
  /** The goods CODE (`sal`), not the printed name. */
  goodCode: string
  /** A number of tuns, or one of the grammar's quantity words. */
  qty: number | 'ALL' | 'HALF'
}

/** Hand the trade to the CMD tab. THE ONLY CALL THE MARKET MAKES INTO THE COMMAND FEATURE. */
export function handOffTrade(intent: TradeIntent): void {
  useCommandDraft.getState().handOff({
    fleetId: intent.fleetId,
    verb: intent.verb,
    args: { good: intent.goodCode, qty: String(intent.qty) },
  })
}
