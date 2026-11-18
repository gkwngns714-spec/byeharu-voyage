# 2026-11-18: three faults found in play (content plan, "faults found in play")

Each was looked at in the running game first: a headless drive of a LOCAL build (no cloud keys; the bundle holds no project ref; the drive
aborts on any request to supabase.co) at 390x844, `vite preview` on port 4791, one persistent profile. SQL was then read from the build's
own world image in Node (PGlite in memory). No production read or write.

The build: the cached world image `world-52339ee6ac13475c-413-1b4af1f` matched the chain's fingerprint, so `npm run build` replayed nothing
(29 s, then 5 s).

## 1. A best-sale card promised +22,416 and the sale paid +617 (fixed, client)

**Seen.** Fresh local world, Lisbon, Trade: the cinnamon card said "Setubal +22,416 · 58s" (50 units, cost 33,389). Pressed: the plan said
Profit +22,416. Buy & sell: the arrival card said Profit +617. Every figure the same as the playtest's.

**Cause.** The card (`world.best_sales`), the plan (`world.good_board` / `world.board_sell`) and the sale (`cmd.do_sell`) all price through
`world.quote`. One authority already. What differed was the market row it read.
- On Supabase the drift job (`public.tick_market_drift_each_port`, pg_cron) brings every harbour's rows to the present drift slot and game day
  each minute, and that includes the stock regenerated over the missed days.
- In a tab nothing did. `src/lib/rpc/localBackend.ts` plays the arrivals, lap starts, the price record, stats and battles, but not the drift.
  A harbour's rows moved only when its own market was read (`world.market` ticks that one quay).
- In the shipped image, 159,137 of 159,766 market rows (253 harbours) were behind the game day. Setubal's cinnamon had stock 868.5 of
  2,390, 974 game days behind. The quote paid 1,116.28 a unit (`price_each`). The same row's own forecast, `at_arrival`, said 676.82.
- Caught up the way `world.market` does it (`public.tick_market_drift(now(), SET)`), the stock is 2,390 and the quote pays 680.12 a unit.
  That is the sale's price.
- The buy side made the gap worse: Lisbon had been caught up (its market was read), so the buy was cheap. In Node, where Lisbon was
  still stale too, the same buy cost 60,816.

"A plan promised +2,528 where the card said +797" fits the same cause: a city chip's press reads `world.market` for that city. Its rows
then
move between the card's read and the plan's read. After the fix a sweep of 29 cards (Setubal, Lisbon, Seville, Porto) found every plan
equal to its card to the coin. That is not proof that this was the playtest's case, which nobody recorded.

**Fix.** `src/lib/rpc/localBackend.ts` `playMarket`: the tab runs `public.tick_market_drift(now())` for every harbour. This is the step the
job's runs add up to. The job's own procedure commits once per harbour, and a CALL can't do that inside the tab's transaction.
`src/lib/rpc/init.ts` runs it at boot, before the first read and before the price record, then every minute (the job's schedule).
- Idempotent by slot and game day.
- The cloud backend is untouched.
- Node specs that build `createLocalBackend` themselves are untouched.

Measured (Node, native PGlite, the shipped image): the first step 4.7 s (159,766 rows), a repeat in the same slot 57 ms, each later slot
0.67 s. A fresh profile reached `data-world="ready"` in 9.3 s and the first best-sale line in 10.1 s. A warm profile before the change took
4.6 s.

**After.** Fresh profile: cinnamon card +609. The earlier trip paid +617. Black pepper: card +4,782, plan +4,782, paid +4,790.

**Spec.** `tests/rpc.marketClock.spec.ts`: after the step no row is behind the game day or the slot, and catching every harbour up as
`world.market` does changes no quote (400 rows). Before the step, 159,766 rows were behind by game day and 105,334 by slot.

**Seen, not fixed (for the lead).** 54,432 rows of the shipped image hold a `drift_slot` (2,986,699) ahead of the present slot (1,994,250).
`tick_market_drift` steps only `drift_slot < present`, so their drift never steps, locally. This looks like a stored counter from before
0413's clock change.
- Not checked on production.
- The read to run there, read-only:
  `select count(*) from public.port_goods where drift_slot > public.drift_slot_of(now())`.

## 2. The Invest tray shows a price and no return (diagnosed; needs a migration: handed to the lead)

**Seen (code; the tray is a stepper, "Cost" and the button).** `src/live/CityTownHall.tsx` `InvestTray` shows the share count and
`estimate.cost` from `cmd.preview_invest` (a rolled-back `cmd.invest`). It shows nothing about what the shares give back.

**What a share gives back.** A coupon, `public.city_coupons` (0312, re-timed by 0413):
- Due: `works_coupon_day` (0.018 in the local world) of what was paid, per real day, times `public.influence_coupon_mult` (1.5 for the
  holder of the city).
- Paid: once a real day, and only up to the city's surplus and its profit that day. So the figure is "up to".

**Served?** No.
- `cmd.preview_invest` / `public.invest_for` return port, kind, shares, price, cost, completed, level, subscribed and purse.
- `world.town_hall` "reads no rate" (0312's header).
- The snapshot's knob allow-list has no coupon knob.
- A client-side rate would be a second copy of the rule.

So this needs a migration (0455 or later, after the 0454 builder). The exact fix is in the hand-off below. The client half is not built:
a word with no figure behind it would be half a slice.

## 3. `tests/news.dotSize.spec.ts:257` at 1280: "hq market: the chart shows no news dot" (a real defect, fixed)

**Seen (CI run 43784696446, #752's second run, shard 5; its report and trace read).**
- The HQ market chart was drawn (aniseed, "1 day", axis "-2.5h ... now"), and the news was asked five times (16 s, 16.5 s, 19 s, 49 s,
  79 s).
- The DOM snapshot's chart held exactly two price points, 0.19 px apart on a 376-px plane: 4.5 s apart, both at about 01:15:00 UTC.
- The 2.5 h span is padding (two points times the step), not age.
- The record began after the probe's news (written 10 min to 55 s before the seed). `world.news_marks`, asked from the record's first
  minute, returned none of it.
- The world served was the spec's seeded one (the route's bare headers).
- The 390 run, 1.5 min earlier in the same shard, passed.

**Cause.** `src/lib/rpc/localBackend.ts` `RECORD_SQL` (the tab's play of the snapshot job) copied "the present slot one slot back, while
the previous slot holds nothing". The copy is a CTE beside the snapshot, so it never sees rows that the same statement just wrote. The
boot's call writes the present slot; the next call copies it back.
- The tab booted at 01:14:59, seconds before a quarter-hour edge (0412's 900-s slots), and wrote slot N.
- Its first chart read at 01:15:00 wrote slot N+1. Slot N was now "the previous slot" and was not empty, so nothing was ever copied back.
- Any boot within the few seconds before an edge does this. That is a timing window in the product's local record, not in the spec, and the
  spec's demand (news from before the tab opened has its dot) is right.

**Reproduced** (Node, the clock fixed: boot 3 s before an edge, the read 1.5 s after, the next due read 30 s later):
- The old rule leaves two points 4.5 s apart and nothing earlier, the CI trace's own pair.
- The new rule adds the point one slot back.

**Fix.** The copy's condition is now the one the line needs, read by time: until no row of the last two slots is a slot's length old, copy
the start of the recent record one slot further back. `recordSqlAt(clock)` exists so the spec can fix the clock. The tab still passes
`now()`.

**Spec.** `tests/rpc.recordEdge.spec.ts` gains "across a slot edge at boot, the tab's record still reaches a slot back". The dot spec is
unchanged.

## Checks run (each once)

- `tsc -b`, eslint on the changed files, `vite build`.
- `rpc.marketClock` 1/1, `rpc.recordEdge` 3/3.
- `news.dotSize` 2/2 (390 and 1280), `command.bestSale` 2/2.
- The trade browser specs: see the PR body.

No screen pieces moved, so `duplication`, `names.whole`, `lit.screens` and `good.class` were not needed for that reason.
