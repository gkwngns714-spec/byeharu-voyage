# 2026-11-22: The first hour (0472, proof 175)

The design: `docs/design/playable-2026-11-22.md` section 5 (second play-test), the lead's items S1, S2 and S3.
Ships **dark** behind `first_hour_enabled` (false). Lighting it is the owner's; it changes live play for every company, so it gets
its own 30-minute after-check (`scripts/ops/harness/first-hour/after-0472.sql`).

## What changes, lit (decided by default)

| | Before | Lit |
|---|---|---|
| S1 Trade card (`world.best_sales`) | a good bought here is priced at the full load her hold, the stock, the day's cap and her purse allow | the smaller of that and what HALF her coin buys at the city's ask: `least(load, max(1, floor(purse / 2 / ask)))`, the docked Buy's own first count (`TradePanel.tsx` firstBuy). The Buy & sell sheet opens at the card's units, so the card's profit, the sheet's default and the docked Buy are one number |
| S2 yard Order (`public.hull_order_price`) | labour + materials + 50 % fee, less the Trading discount (0468) | her SECOND hull (at most one ship, none on order): the fee is raised so the price before the discount is at least `first_hull_order_floor` (52,000); the discount comes off the whole fee. The third hull and later: unchanged. Building from materials: unchanged |
| S3 Trade card's sale | the best profit per hour among the sales she can pay for | the same, but for a company paid for Trading under `first_hour_trading_below` (5), a PAYING sale within `first_hour_trip_hours` (2 h real) comes first. Nothing near pays: as before. The far sale (`far`, the sheet's third choice) is unchanged |

Why 52,000: she starts with 40,000 and keeps half of it each trip (S1). A good trip at half-coin in the chain's world earns about
+1,200 to +3,500 (below), so the floor asks about 12,000 earned: four to six good trips, 20-40 minutes of play. At Trading 5 the
order is 48,554 (10 % off the 34,460 fee), at Trading 8 about 45,100: the per-level discount stays worth having.

## Numbers, a fresh Lisbon company (the chain's world, every prod switch lit; 40,000 coins; Trading 1)

| | Dark (today) | Lit |
|---|---|---|
| Top card at Lisbon | Raw silk to Setubal, 90 units, cost 39,352, +6,777 | Raw silk to Setubal, 45 units, cost 19,637, +3,545 |
| Quicksilver | 20 units, cost 37,125, +5,098 | 10 units, cost 18,554, +2,579 |
| Black pepper | 270 units, cost 38,697, +4,076 | 141 units, cost 20,091, +2,573 |
| Cards at half her coin | 0 of 10 | 7 of 10 (the other 3 already cost less: cork, wool cloth, iron) |
| Order, Barca at Lisbon, Trading 1 | 26,310 (labour 15,000, materials 2,540, fee 8,770) | 52,000 (fee 34,460, "First order") |
| Order, Barca, Trading 5 (unlocks lit) | 25,433 | 48,554 |
| Top card's hours from Porto | 0.08 h (Merino sheep to Setubal) | 0.07 h (Merino sheep to Setubal, 40 units, +2,148) |

The chain's world names no 6-7 hour card from Porto (the longest best sale over 17 harbours is 1.47 h, Busan), so S3 changes no card
at its 2 h horizon here; at a 0.04 h horizon (proof 175, FH_NEAR) it changes four cards at Lisbon, London, Goa, Venice and Amsterdam,
each to a paying sale within the horizon. The play-test's world (Porto to Osaka, Busan, 6-7 h) is where the 2 h horizon bites.

Prod (read-only, before): head 0471; all six hunks' old text once and no new text in the live bodies; 16 human companies hold at most
one ship with none on order, so their next order would carry the floor once lit.

## The client

- No change for S1 and S3: the card, the sheet and the docked Buy already read the served units (`Trade.tsx` pressBest opens the plan
  at the card's units; `saleChoice.ts` picks rows of the trip board at those units).
- The yard: with `first` served, a "First order" / "첫 주문" row shows the raised fee under the wait. Dark: absent.

## Checks

The migration's self-assert (dark = the pre-images on copies; lit halved cards and the floor) and proof 175 (FH_DARK, FH_HALF,
FH_NEAR, FH_ORDER, FH_DISCOUNT). Harness: `scripts/ops/harness/first-hour/before-0472.sql`, `after-0472.sql`.
