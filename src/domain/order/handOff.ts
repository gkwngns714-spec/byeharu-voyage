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
// QUANTITIES. BOTH SIDES HAND OVER THE WORD `ALL`, and neither computes a number.
//
// This comment used to say a BUY was "prefilled with what the hold can still take". That stopped
// being true in D11g and the sentence outlived it by two weeks — which is its own small lesson: a
// comment describing a behaviour is a second authority for that behaviour, and it drifts silently
// because nothing compiles it.
//
// The reason it changed is worth keeping. A client-side maximum ignores the purse, so the very
// first tap a new player made arrived on CMD already refused — "60 tuns cost 8020 d. and you hold
// 8000". The same bug was then found a THIRD and a FOURTH time (the MAX chip, and PORT's
// `affordableUnits`, deleted 2026-08-22). `ALL` is resolved server-side by
// `public.fleet_buy_capacity()`, which walks the same stepped book a real trade walks and stops at
// whichever of hold, stock, daily cap or purse binds first — and because the grammar reads it WHEN
// THE ORDER RUNS, it is still right after a voyage that changed the hold.
//
// Neither side is a price and neither is binding: CMD previews the order and the server prices it.

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
