# 2026-11-25 — `cargo-at-cost`: goods bought and still held are not a loss (0501, proof 203; dark)

The lead: HQ's per hour counts a cargo BUY as a running loss until it is sold (a test company reads Trading −38,869 while its cargo
is at sea). The same kind of complaint as the owner's *"why investing causes les money? wtf?"* (0493).

## What was recorded, and what was not (read on the chain's bodies before 0501)

- **A sale's cost is recorded.** `cmd.do_sell` writes the SOLD event with `cost` (`public.fleet_cargo_basis` × units; 0081, 0474,
  0490) in the transaction that writes its SELL ledger row. "Sales less the basis of what was sold" is exact, also for goods bought
  before the window.
- **A loss's cost was not.** `voyage.lose_hold` and `voyage.raid_takes` take goods through `public.fleet_unload`, which drops a
  good's `cargo_basis` with its last unit. The day's payload kept `cargo_lost {good: units}` and no cost. It cannot be derived
  afterwards: held now = start stock + buys − cost of sales − losses, with start stock and losses both unknown.
- So the first report stopped there. The lead chose to record the cost at the loss (option 2).

## Server (0501)

**The record (not behind the switch; additive; from deploy on).** The three writers of a day that loses cargo add one key to the
day's payload in `public.voyage_events`: `cargo_lost_cost` = her cargo at cost before the loss less after it
(`public.fleet_stock_at_cost`, 0129: the expression the day's news already tells, 0362).

| Body | Hunks | Where |
|---|---|---|
| `voyage.settle` | 3 | the PIRATES arm (its own variable beside the news' `v_cost0`: proof 64 rebuilds a body without that one) |
| `voyage.forced_home` | 3 | ran dry, the hold lost: the key goes in the day's payload it returns; the feed's FORCED_HOME event is as it was |
| `voyage.navy_meets` | 3 | a navy's plunder |

`voyage.lose_hold`, `voyage.raid_takes` and `public.fleet_unload` are not touched. No new row, table or ledger row.
`voyage.npc_wreck` (a merchant's wreck) is not touched.

**The switch** `cargo_at_cost_enabled` (false). `cargo_at_cost_since` holds the deploy time.

**The read** `public.cargo_rate_for(player)` (STABLE, server only): `bought` (her BUY ledger rows), `cost_sold` (her SOLD events'
`cost`), `lost` (her voyages' days' `cargo_lost_cost`), all over the last 24 hours, and `since`.

**`public.company_rate_for`** (4 hunks). Dark: 0493's answer to the letter. Lit:

- `trade` = her ledger's trade line + bought − cost_sold (her sales less the recorded cost of what she sold);
- `cargo_lost` = a running line, −lost (no ledger row: no coin moved);
- `cargo` = `{at_cost, net_24h, bought, cost_sold, lost, exact_since, exact}`, with `at_cost` = greatest(0, bought − cost_sold − lost)
  and `net_24h` = −(bought − cost_sold − lost).

**The sums, exact:** the running lines sum to `net_24h`; `all_24h` is still her ledger's sum; and
`net_24h + one_time_24h + cargo.net_24h = all_24h`. `cargo.net_24h` is the reconciling figure: negative, the coin that went into
goods that are neither sold nor lost; positive, the cost of goods bought before the window that she sold or lost in it (they count
at their basis, and `at_cost` is then 0).

### Not counted, said plainly

- **Losses before the deploy have no record** and none is estimated. `cargo.exact` is false while the 24 hours reach back before
  `exact_since`; such a loss leaves its goods in `at_cost` until their BUY leaves the window.
- A sale of goods with no recorded basis (land goods, a gift) counts cost 0: she paid nothing for them. Buying into a hold that
  already carries such goods makes the blended basis unknown (0081), and that sale then also counts 0.
- Goods a forge or a make order consumes, and goods a courier contract carries, leave no cost record.
- A day's loss is windowed by the day's own instant (`resolved_at`), a sale by its event's.
- No jettison path exists in the chain.

## Client

`RateWhy.tsx`: the line `cargo_lost` reads "Lost cargo". The sheet gains a neutral Cargo section when `rate.cargo` is served:
"Cargo 25,654 · At cost · −25,654", from when losses are counted while not exact, and "All coin" (the ledger's sum), so
Running + One time + Cargo = All coin. Types `HqRateCargo`. Dark, nothing changes.

## Measurements (local PGlite, this PC, a private prefix cache)

- 0501 on the chain's world before it: self-assert passed, 150 ms. Scene: the rate dark equals the old body's answer; lit: trade +3,000,
  lost cargo −1,500, net 1,200, cargo 2,500 at cost; older goods at basis: net 2,200, reconciling +1,500.
- **The loss itself:** a forced home on the new body and on the old body, the same voyage: hold, hulls, crew, purse, ledger, events,
  voyage and the cities' purses identical by digest; the payload identical but for `cargo_lost_cost` 2,000. One call each: 12 ms
  new (run first, cold plans), 7 ms old.
- **What the record adds:** `public.fleet_stock_at_cost`, 0.010–0.015 ms a read (proof 203, 200 reads); two reads on a day that
  loses cargo, none on any other day.
- Proof 203: 7/7. Real `cmd.do_buy` (anise ×10 for 857), `cmd.do_sell` of four (316, recorded cost 343: the trade line is −27, the
  SOLD event's own profit; cargo 514), then ran dry: the real `voyage.settle` wrote FORCED_HOME with `cargo_lost_cost` 514; lit,
  the lost-cargo line is −514 and cargo 0.
- Proofs 196 (5/5), 64 (6/6: real raid days through the hunked `voyage.settle`), 23 (6/6), 01, 101, 201 (18/18) pass with 0501.
- The first cut used the news' `v_cost0` in `voyage.settle` and broke proof 64 (it rebuilds the body without that variable). Fixed
  at the cause: the record reads the figure itself.

## Not verified

- Production: nothing was read. The before / after reads are in `scripts/ops/harness/cargo-at-cost/`.
- `voyage.navy_meets`'s arm was not driven (its hunks are the forced home's shape); `voyage.settle`'s PIRATES arm ran through
  proof 64 without an assert on the new key.
- The self-assert's scene uses its own company, voyage and planted rows: no market price, no real company, no real job. It does
  call `voyage.depart` and `voyage.forced_home` on prod's world (rolled back).
