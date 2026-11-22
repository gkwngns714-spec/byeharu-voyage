# 0474: a fair gift and one profit (third play-test, findings 2, 28 and 1)

`docs/design/playable-2026-11-22.md` section 6. Migration `20260818000474_a_fair_gift_and_one_profit.sql`, proof 177,
harness `scripts/ops/harness/gift-profit/`.

## Finding 2: ordering the second hull paid the gift back (switched: `fair_gift_enabled`)
- Cause: the gift's worth (`public.player_worth`: purse + cargo at cost - debts) did not count a paid hull order. 5,098 after a 48,557
  order is under the line (0.2 x 40,000 = 8,000), so the next sale paid 40,000.
- Fix (lit): the worth adds what she paid for a hull on order, or for an ordered hull launched within `gift_cooldown_hours` (24) that is
  still hers. The starting ship and a hull built from materials are not counted (decided by default: every company owns her first ship,
  so counting it would end the gift for all). Not decided here: the working purse the order leaves (deposit, or a refusal under 20,000).
- Proof 177 (local image): dark, 5,000 coins + a 48,557 order is on the roster; lit, off it on order and launched within 24 h; on it
  again launched 25 h ago or with no order.
- Prod before (2026-11-23, `before-0474.sql`): no company gifted in the last 7 days with a hull on order (`gifted_with_hull` []), none
  would be now (`would_now` 0): the exploit has not been used on production yet.

## Finding 28: Rank Week counted the gift and the order (switched: `fair_gift_enabled`)
- One definition of trade: `public.ledger_is_trade` (BUY, SELL, TAX, WAGES, PORT_FEE, PROVISION, REQUEST_FILL). The history job keeps the
  day's non-trade earning rows in `history_company_day.not_trade`; lit, the settled week and your live figure both leave them out.
- Proof 177: a sale 3,000, a gift 40,000, a hull order -20,000: dark 23,000, lit 3,000, the same live and after the history job adds
  the day, and the settle writes the same row.
- Backfill: the two weeks' gifts and hull orders already settled; other non-trade rows of days settled before 0474 stay until the week turns.

## Finding 1: one trip, three profits (not switched: a figure told right, no coin moves differently)
- The card: `world.board_sell` kept a walked row's harbours from the unwalked legs (null), so the card's dock fee was 0. Proof 177's
  negative control (the old line put back): "anise, 241 units to Setubal: card profit 359, board 280, dock fee 79". With 0474, 10 of 10
  Lisbon cards equal the trip board's row to the coin, all 10 with a dock fee.
- The arrival: the SOLD event carries `wages` (`public.wages_due`, the rule `public.pay_wages` now pays by), `dock_fee` (this call's,
  kept by `public.port_call` on the fleet until her first sale there) and `trip_net`; the arrival card prints `trip_net`.
  Proof 177: anise x5, profit 205, tax 31, wages 40, dock fee 57, trip_net 77; the purse moved 277 = trip_net + the goods' cost 200.
- The play-test's trip, after: card 2,918, sheet 2,918, arrival 2,918 (3,100 - tax 105 - wages 8 - fee 69), purse +2,918.
- Not in `trip_net`: supplies bought at the sail (the sheet shows them on their own row; zero on the first hour's trips).
