# 2026-11-22: A job says where to buy, and your week is live (0473, proof 176)

The play-test: `docs/design/playable-2026-11-22.md` section 5, rows 6 and 10 (S4 and S6 for the lead). Two fixes to lit features:
`hold_requests_enabled` and `houses_board_enabled` are on in production. No new switch.

## What a player sees

- **Office > Requests, a hold job:** a new line under the pay, "Buy at Setubal · 4m" (KO "{도시}에서 구매 · {시간}"): the nearest harbour
  that sells the good and a Barca's sailing time there from this port. Both are served (`world.contracts` row `from`); the client
  measures nothing.
- **The job's good is one she can fetch in time.** It is sold at a harbour a Barca sails to and back in half the time the job stands.
  Lisbon no longer asks for a Cape good with 4 hours on the clock.
- **Rank > Week:** your own profit, place, tie and the gap to the house ahead are counted in the read, so a +1,485 sale shows at once.
  The other rows are still the history job's count, and the board's caption now says so: "Others counted 10 min ago"
  (KO "다른 상회 10분 전 집계"). The page's "Updated ..." caption, the Captains' photograph's age, shows only on Captains and Countries.

## Decided by default

- **The speed a job is measured at is a Barca's:** `hold_request_speed_kn` = the Barca's `speed_kn` (15: 5 kn x `speed_scale` 3), a
  new company's hull, so the slowest starter decides it. Real seconds = nm / kn x 3600 / `time_compression` (voyage.depart's rule).
- **There and back in half the time it stands** (`hold_request_trip_share` 0.5). The time it stands is exact:
  `clock_start('game_day', expires_day) - now`. The other half is room to buy, wait and be slow.
- **The deadline is drawn first.** Its draw keeps its key (`hold:<seq>:hours`), so drawing it before the good moves no other draw. A
  harbour with no good within reach posts nothing that minute; the wind tries again the next.
- **The source is kept on the row** (`trade_contracts.source_port_id`, nullable, no foreign key: adding one locks `ports`). The miles
  are read at the read from the poster's `sea_reaches` row, so a re-sailed reach table moves them with it.
- **The open jobs standing at the deploy** get their nearest seller, however far, in one UPDATE. The row tells the truth about them
  until they expire (6 h at most).
- **Your week, live:** `history_company_day` for your days this week (at most 7 rows by its key) plus your ledger since the history
  mark (`ledger_player_created`, one range of one player's rows), the kinds `ledger_is_earning` counts: the same sum the settle writes
  next. A company not settled yet (new this week) is counted in "of N". `you.live` is true.
- **"Your row" on the board is the live one.** Your place is counted against the other houses' settled rows. The board's other rows
  are not recounted.

## Measurements

- **Production, before** (`scripts/ops/harness/requests-source/before-0473.sql`, 2026-11-22, prod head 0471, `time_compression` 192,
  Barca 15 kn): the open hold jobs' nearest seller, sample: Accra 60 min one way, Aden 129 min (ginseng), Alexandria 144 min (shea nut),
  Algiers 280 min (Korean movable type, 13,435 nm), Amboina 261 min (beer). With 2-6 h on the clock, a round trip of 2 x 280 min cannot be made.
- **Local world, proof 176:** 30 harbours at the start of a game day posted 57 jobs, each sold at its source. One way for a Barca:
  min 0.4 min, median 25.9 min, max 59.6 min. A minute before the day ends no harbour posted (no good is within reach of 60 s).
- **The live figure's cost** (proof 176, PGlite, 847 houses on the board): `world.houses_week()` 1.05 ms with 3 of your rows after the
  mark, 1.10 ms with 303. The range is a Bitmap Index Scan on `ledger_player_created`.
- **Production, after:** `scripts/ops/harness/requests-source/after-0473.sql` (the lead runs it: the backfill, the jobs posted since,
  and the live range's row counts per company).
