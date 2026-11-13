# 2026-11-13 — 0362: the news tells of big trades, price spikes, pirates and gifts (owner row 216, N4-N6)

Owner, 2026-10-26: *"when an update or a happening is made, it should make a point on the chart, and i will be able to
press it to see what caused it (major event, real time news-like feature)"*.

Design: `docs/NEWS_AND_MARKERS.md`. 0347 built the news table, its reads and three kinds. This slice is **N4** (big
trades, price spikes), **N5** (pirates) and **the gift of N6**, in one migration, 0362. Lit, no switch.

## What shipped

Five kinds, each a row of `public.news_kinds` (importance 2: the World feed shows them, the desk strip does not), each
written by one leaf inside the transaction that causes it:

| Kind | Headline | Fires on | Threshold |
|---|---|---|---|
| `BIG_SALE` | {company} sold {qty} {good} at {city}: {n} | `cmd.do_sell` | total at least `news_big_trade` 250,000 |
| `BIG_BUY` | {company} bought {qty} {good} at {city}: {n} | `cmd.do_buy` | the same knob |
| `PRICE_SPIKE` | {good} at {city} {p} in an hour | `public.tick_price_snapshot`, the run that folds an hour | the bid's close moved at least `news_spike_pct` 20 % against the hour before; the `news_spike_top` 5 largest; a pair quiet for `news_spike_quiet_hours` 6 |
| `PIRATES` | Pirates took {n} from {company} | `voyage.settle`, a RANSOM, PLUNDERED or STRIPPED day that cost something | a player's company always; a ship of the world at `news_pirate_loss` 50,000 and up |
| `CAPITAL_GIFT` | {capital} gave {company} {n} | `public.capital_gift_one` (the merchants' hourly pass and a player's gift after a sale are that one body) | every gift made |

Caps, so the merchants cannot flood the feed:

- The threshold comes first. A trade under the knob costs one knob read and one comparison and writes nothing.
- One row a company, a city, a good and a clock hour (the key): a lot sold in ten parts is one headline.
- **A ship of the world is told only while fewer than `news_merchant_hour` (2) rows of that kind were told in the last
  hour** (`public.news_room`). So the merchants add at most 2 rows an hour to each of the four kinds: 8 an hour, 192 a
  day, at the very most. A player's company is always told. Two sessions telling at the same instant can pass the cap
  by one: it is a count, not a lock, on purpose (a lock would make one sale wait for another).
- Spikes: at most 5 an hour.
- Waiting: a news row is a plain insert. Its key is unique, so two sessions writing the SAME key (one company, city,
  good and hour, or one voyage day) would have the second wait for the first's transaction to end; a company's own
  trades are already one at a time, and no key is shared between companies. The cap itself takes no lock.
- Every knob at 0 turns its kind off (`news_big_trade`, `news_spike_pct`, `news_merchant_hour`).

Not built: `MERCHANT_BROKE`, `WANTS`, `RESTOCK` (the rest of N6), and the feed's "My goods" filter.

## The re-cut bodies, and the other open migrations

Seven hunks over five bodies, each asserted to occur once and to reverse:

| Body | Hunks | What is added |
|---|---|---|
| `cmd.do_sell` | 1 | after the live trade figures: the threshold, then `public.news_big_trade` |
| `cmd.do_buy` | 1 | the same |
| `public.tick_price_snapshot` | 1 | after the hour fold's mark: `public.news_price_spikes`, only when an hour was folded |
| `voyage.settle` | 3 | a variable; her cargo at cost read before the raiders take it; the news of the day before its payload |
| `public.capital_gift_one` | 1 | after the gift's own sub-block: `public.news_gift` when a gift was made |

Checked against each open branch's migration (2026-11-13): `origin/captain-skills` (0355: `crew_terms`, the registry),
`origin/level-up` (0356: `reputation_arrival`, `reputation_card`, `cmd.standing_route_close_lap`, the registry),
`origin/live-rounds` (0357: `fight_sides`, `battle_open`, `battle_resolve`, `tick_battles`, `battle_words`,
`voyage.hold`, `voyage.total_days`, `voyage.days_complete`, `voyage.arrival_at`, the registry), `origin/yard-plan`
(0358) and `origin/auto-route` (0360). **None cuts any of the five bodies**, and 0362 does not cut
`public.client_rpc_entry_points` (no door is added). So 0362 stands on any order of them; nothing is stacked.
In `voyage.settle` the hunks are anchored on three lines 0353 did not add or cut (proof 56 still rebuilds 0353's old
bodies on the new text: green).

## Proven (local, PGlite, the cached chain; never from zero)

- The file applies on head 0354: self-assert ok in about 60 ms.
- **Old = new** (`scripts/db/proofs/64_news_kinds.sql`): the old bodies are rebuilt from the live ones by the
  migration's own hunks, and each scene is played under both, in subtransactions rolled back, and compared as text:
  12 real trades (a sale and a buy, a player's and a merchant's, the knob far above, at the total, a ducat over it:
  the answer, events, ledger, purse, market row, hold, allowance), the real snapshot over two planted hours (the
  answer, the hour rows, the mark), three passages of 12 real raid days (every day, the report, the purse, the hulls),
  a real gift (the answer, events, ledger, the gift row).
- Each kind through the real command: a sale and a buy at the knob (one row) and under it (none), a refused sale
  (none), seven merchant sales above the knob in an hour (exactly 2 told), a player after them (told), the snapshot
  (+30 % and -30 % told with before and after, +5 % not, a later run in the hour nothing), raid days (a company's day
  that lost cargo told with what the cargo cost, a day that lost nothing not; a merchant's small loss not, her large
  one told), a gift (one row at her capital).
- Red first: proof 64 fails on a world with no 0362. 21 mutations red (`proof-0362.mjs`): 13 by the self-assert, 8 by
  proof 64 (a dropped threshold on a sale and on a buy, a knob at 0 meaning all, an extra event, a purse moved, the cargo priced after the
  raid, every move a spike, a gift told when none was made).
- Proofs 01, 02, 04, 05, 06, 10, 11, 12, 13, 18, 22, 23, 26, 31, 34, 46, 47, 54, 55, 56 and 57 green on the file.
- `tests/news.kinds.spec.ts`: each headline reads right in English and Korean with the words its writer gives; the
  proof's copy of the hunks is the migration's. The client names no kind, so it needed no word and no code.

## Cost a call, old against new (local, interleaved in one session, each call rolled back; means)

PGlite's clock ticks in whole milliseconds, so these are means over many calls. Two runs:

| Call | Old | New | Added |
|---|---|---|---|
| a sale under the knob (400 each) | 2.298 / 2.785 ms | 2.298 / 2.765 ms | 0.000 / -0.020 ms: inside the noise |
| a buy under the knob (400 each) | 2.988 / 3.325 ms | 3.023 / 3.440 ms | +0.035 / +0.115 ms: inside the noise |
| the threshold alone (20,000 calls) | | | **0.005 to 0.006 ms** (one `wc_num` read and one comparison) |
| a sale above the knob, told (400 each) | 2.150 / 2.690 ms | 2.418 / 2.913 ms | **+0.22 to +0.27 ms** (a handful a day) |
| snapshot, no hour folded (3 of 4 runs; 1,392 pairs) | 209 / 231 ms | 210 / 227 ms | nothing (noise) |
| snapshot, the run that folds an hour (once an hour) | 216 / 261 ms | 234 / 268 ms | +7 to +17 ms; the leaf alone **5 to 6 ms** |
| a passage of 12 raid days, a company with cargo | 79.4 / 93.1 ms | 86.1 / 97.4 ms | +4 to +7 ms a passage: **+0.35 to +0.56 ms a raid day** (4 of the 12 lost cargo and were told) |

A sea day that is not a costly raid, and an arrival, gain nothing: the hunk is inside the PIRATES arm.
Prod has more recorded pairs than the local 1,392; the spike leaf is two primary-key probes a pair, so it grows in line.

## Expected news volume, from the local world

`volume-scene.sql` (60 merchant fleets started through the world's own lever, 12 beats of the real arrivals job and the
real lap-start pass, the market pinned, a quiet sea): 387 merchant trades; totals p50 43,377, p90 307,976, p99
1,598,743, the largest 1,797,964. **51 of 387 (13 %) reach 250,000** (24 sales, 27 buys); 128 reach 100,000.

That is far more than the design's sample (2026-10-26: 250,000 was the 99.9th per cent of a sale, about 30 a day).
The local world is the chain's seed, not prod; but if prod's trades look like this, the knob alone would tell hundreds
of rows an hour. **So the cap is what bounds it: at most 2 `BIG_SALE` and 2 `BIG_BUY` an hour from the merchants (in
the scene: exactly 2 and 2), 4 rows an hour, 96 a day.** With `PIRATES` and `CAPITAL_GIFT` at their caps too: 8 an
hour. With 5 spikes an hour: **at most 13 rows an hour, 312 a day, plus the players' own.** The design budgeted 450 to
1,000 rows a day.

When the cap binds, the headlines are the first two of each hour, not the two largest. `trade-sizes.sql` (a prod
check) reads the last 24 hours of trades on prod; if the merchants' `at_250k` is far above 48 a day, raise
`news_big_trade` to about that day's p99.9 (the owner's knob).

## Decided by default

- The price read for a spike is the bid's close (every recorded pair has a bid; an ask only where the city sells).
- A STRIPPED day is `PIRATES` news too. A ransom day that moved no gold is not news.
- What the pirates took is the cargo at what it cost her (read before and after the raid), plus the ransom paid and a
  cargo ship's gold. Insurance paid later is not taken off.
- The news instant is when the world learns it (the row's own clock), also for a voyage settled late.
- Figures in a headline are written by the server with thousands commas, so the client has no rule for them.
- Four knobs the design does not name: `news_pirate_loss`, `news_merchant_hour` (2), `news_spike_top`,
  `news_spike_quiet_hours`.
- The five largest spikes of the hour are taken first and the quiet ones among them passed over (the design could
  be read the other way): a second run of the same hour then tells nothing, and a pair that keeps moving is told once.
- The self-assert plays the leaves on probe rows only (no real sale, no real voyage on prod: nothing of live play is
  locked while the file applies); the real commands are proof 64's. Its probe hours are planted in 2099, which no fold
  or prune of the live job reads.
- The update row: "More news" / "더 많은 소식".

## Deploy, after-check, rollback

PROD CHECKS, in order (all read-only, one statement a file, `scripts/ops/harness/news-kinds/`):

1. `volatility.sql` — 5 rows, each volatile, definer, `search_path=public, pg_temp`, no client.
2. `trade-sizes.sql` — how the knob sits against today's trades (above).
3. `before.sql` — 7 rows, every `old_times` 1 and `new_times` 0, `made` 0. Keep `bodies`.
4. Deploy (`~/bin/bv-deploy.sh <pr>`), after 0355-0361 or without them: it does not depend on them.
5. `after.sql` — 7 rows, every `new_times` 1, `fns` 7, `client_fns` 0, `kinds` 5, the six knobs, `update_row` 1.
6. `volatility.sql` again — the same five rows.
7. 30 minutes later, and again after a day: `volume.sql` — rows told by kind; the merchants' never above the cap.
   Watch the arrivals beat and the trade tick as for any change to these bodies.

Forward rollback (owner only). The light one, no migration: set `news_big_trade`, `news_spike_pct` and
`news_merchant_hour` to 0. The whole slice: `rollback-0362.sql` cut as a new migration (strip its guard line): every
hunk swapped back, the leaves and knobs dropped; rows already told stay (append-only).

## Not proven

- Anything on prod: the hunks on prod's bodies (`before.sql`), prod's trade sizes, the cost on prod's size.
- A named pirate ship's raid (ransom to her home, a cargo ship's gold booked) through the real settle: proof 64's
  raids are anonymous. The sum is `v_ransom + v_booked + cargo`, and the leaf is proven at each threshold.
- The merchants' hourly gift pass through `tick_reconcile` (proof 64 gives a player's gift through
  `capital_gift_pass`, the same body).
- A player's gift after a real sale with the economy closed (`cmd.do_sell` → `public.player_gift` → the same body).
- The dots and the feed on a page with these kinds: the client code is unchanged and names no kind; the headlines are
  held by `tests/news.kinds.spec.ts`, not by a browser.
