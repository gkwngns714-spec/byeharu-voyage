// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE — where a good is worth more than it is here, and what the voyage would pay
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A SECTION, NOT A SCREEN. `world.trade_routes()` (migration 0019) answers one question — "where,
// in reach, does this good fetch more than it does here, and what is the margin?" — and TWO screens
// ask it: the Market table prints a destination per row, and the Command tab's unfolded good row
// names the same one while the player is choosing what to buy. It was MARKET's file until COMMAND
// needed it, and at that moment it stopped being either screen's (docs/NO_SPAGHETTI.md §2).
//
// NOTHING HERE COMPUTES A PRICE, A MARGIN OR A DISTANCE. Every figure in a `TradeRoute` came out of
// `world.quote()` — the same function a committed BUY and SELL execute at — and `nm` is the SAILED
// leg distance over the shortest route, never a straight line. This section RE-KEYS the answer; it
// has no opinion about it. A margin the client worked out would be a second authority for the one
// number a player decides a voyage on.
//
// ── WHAT IT MAY DEPEND ON ──────────────────────────────────────────────────────────────────────
// `lib/rpc` types, and nothing else. No React, no store, no screen, no other section.
export { routesByGood } from './routes'
