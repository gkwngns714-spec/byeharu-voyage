# 2026-11-23 — 0480 the HQ board from the server: every option ranked, one press (dark: `hq_board_enabled`)

`docs/design/hq-command-2026-11-23.md` section 2, v2 items 1-3: the server ranks, risk on a sale, the rate. The standing fleet jobs
(item 4 on) are 0481. The owner, 2026-11-23: "choosing best options available, finding best options."

## What it does (lit)
- **One read**, `world.hq_board()` (STABLE, registered, signed in only). Dark `{on: false}` after one knob read. Lit, signed out or a
  merchant `{on: true, company: false}`. Lit, her company: `public.hq_board_for(her)` →
  `{moves: [{id, kind, band, fleet, fleet_name, at, score, profit, seconds, risk, needs, act}], rate, next, threats, unpriced, clock, ms}`.
- **Trade**: each IDLE fleet's `world.best_sales` (DOCKED, nothing queued, on no standing route), the oldest first. Bounded:
  `hq_board_fleets` (4) fleets a call, and no new read starts after `hq_board_budget_ms` (2,000); the fleets left are in `unpriced`.
  Her best `hq_board_runs` (3) paying sales a fleet, by coin an hour (v1's filter: pays, a harbour, `near` not false).
  - **risk** `{danger, bounty, pirate}` (`public.hq_course_risk`): the highest danger level (1-5, `world.sea_danger`'s own formula,
    `public.hq_sea_level`) of the waters of every harbour the passage calls at (her port, the stops, the sale's harbour); the richest
    standing bounty whose pirate's home is one of those harbours or whose ship lies in one of those waters. Computed in the board, NOT in
    `world.best_sales`: the desk's time-budgeted read is untouched.
  - **act** `cmd.issue_lines` with `{fleet, version, plan: {good, buy_at, sell_at, units, stops}}`. The client writes the lines with the
    desk's own `planLines` (the course from the chart, as the desk's Go) and sends them by the store's `issueLines`. The server cannot
    write the lines whole: a SAIL with no course is refused `E_NO_COURSE` by `cmd.do_sail`. `stops`: `world.board_passages` from her port
    with her stores' reach, as best_sales' own `board_origin` asks it.
- **Requests**: every open request at every harbour where a fleet of hers lies DOCKED, for each such fleet with the good aboard; the
  units `cmd.run_fulfil` would land (hold, budget, today's allowance) and the net `cmd.preview_fulfil` serves (the sale's quote total +
  the bonus, rounded up), in a read. The self-assert and proof 183 compare it with `cmd.preview_fulfil` to the ducat. Act `cmd.fulfil`.
- **Yard**: while she holds fewer than `hq_board_build_below` (2) ships, none on order, the yard taking orders: the cheapest hull a
  building yard where a fleet of hers lies lays down for her (yard labour, the sheet's figure), priced by `public.hull_order_price`, when
  her purse covers it. Act `cmd.order_hull`.
- **Land**: the party's goods come home or waiting (Land lit). Act `cmd.land_collect`.
- **Crew**: a docked fleet with no captain in any cabin, at an Inn where a captain she has not signed sits now and her purse pays the
  wage; the cheapest. Act `cmd.hire_officer` (hired into the fleet: seated).
- **Invest**: idle coin (purse less the dearest trade card's buy) of `hq_board_idle_coin` (20,000) or more, the purses lit: at each
  harbour where a fleet of hers lies docked (`cmd.invest`'s own gate), the work whose stake of that coin pays the most a day
  (`public.coupon_day_of`; the price `public.works_share_price`, `world.holdings`' leaf); the best three. Act `cmd.invest`.
- **Rate**: her ledger's last 24 hours (FOUNDING and probes out, as `world.report`) by the `(player_id, created_at)` index, over 24.
- **Next**: the soonest arrival, hull ready, lesson done or route lap. **Threats**: her voyages under way whose waters stand at
  `hq_board_danger_warn` (4) or more, or that carry a bounty pirate.

## The ranking (one rule: the ORDER BY in `public.hq_board_for`; v1's `src/domain/hq/moves.ts`, served)
band 0 the yard; band 1 trade runs and requests together by `score` = coin an hour (a trade run: profit x 3600 / its seconds; a request:
net x 3600 / `hq_board_request_floor_s`, 900 s); band 2 Land goods; band 3 a captain; band 4 invest (score: a day's coupon / 24). Then
the higher score, the bigger profit, the id.

## Client
- Lit, `useBoard` reads `world.hq_board()` (`src/live/useHqBoard.ts`: asked when HQ opens, when a fleet of hers acts, and at the market's
  edge; never on the beat) and draws its moves in its order, its rate (the bridge says "24 h, per hour"), next and threats. v1's reads
  (best_sales x3, the city's requests, the day's report) are asked only once the server has said it is dark: never beside a lit board.
- One press on a served card commits its `act` through the building's own door (`src/features/city/board/servedPress.ts`); HQ stays.
  A refusal shows under the card in the server's words (`Note`), the card kept.
- A trade card's risk is a mark: a shield in the tone of the waters' danger (muted 1-2, warning 3, danger 4-5), or the pirate in the
  danger tone with the bounty when one is on the passage.
- Dark: v1 exactly (the client ranking, the presses that open the desk, the yard, the inn, the Office).

## Measured
- Local chain (PGlite), proof 183 `HB_COST`: one call lit ~0.5 s with one idle fleet priced, ~0.9 s with two (best_sales ~0.45 s,
  board_passages ~0.08 s a fleet). Self-assert ~0.24 s.
- Prod (`before-0480`, the one read, 2026-11-23): head 0479; one `world.best_sales` for the newest company at Lisbon **2,735 ms**
  (`cut`: its own 2.5 s budget ran out), 6 paying cards; 19 companies, 19 idle fleets, at most 1 a company. So a board on prod today is
  about one best_sales plus ~0.1 s: ~3 s. With more idle fleets the 2 s budget starts no second read after a Lisbon-sized one: a call
  stays under ~2 s + 2.5 s + 0.2 s.

## Load
No table, no index, no cron, no beat step: one read when HQ opens, when a fleet of hers acts, and at the market's edge. Read the gate
before lighting it: each HQ visit then costs about one `world.best_sales` per idle fleet (v1 cost the same, up to three, client-side).

## Decided by default (the owner may reverse)
- Risk is computed in the board, not in `world.best_sales` (the desk's read stays as fast as it is).
- The course's waters are the waters of the harbours it calls at (the course itself is the client's chart's, plotted at the press).
- The yard card: only fewer than 2 ships, none on order, at a yard where a fleet of hers lies.
- A request's figure is `cmd.preview_fulfil`'s net (the sale and the bonus), as the brief asks; v1 showed the bonus alone.
- `hq_board_budget_ms` 2,000 (not 3,000) after prod's Lisbon read took 2.7 s.
- The invest card keeps the client's one level gate (Trading 5): a served invest card is hidden while the gate holds Invest.
