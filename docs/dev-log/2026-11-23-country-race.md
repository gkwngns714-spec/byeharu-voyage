# 2026-11-23 — 0484 the country race (dark: `nation_race_enabled`)

`docs/design/roadmap-2026-11-23.md` slice 15 ("Nations matter"), on HQ's board (`docs/design/hq-command-2026-11-23.md`). The owner,
2026-11-23: "i want this game to be strategical game, where all the work (activities) are done in HQ - words with graphics. choosing best
options available, finding best options." Slice 15: a home perk of cheaper dock fees at your country's harbours, the country's jobs, a
weekly influence race shown on the map with cities tinted by who leads, and Reputation and a title for the winner's top companies.

## What it does (lit)
- **The race cities** are the contested harbours (`port_allegiance.home` false: 210 of 254). A home city never changes hands, so it is no
  race. The racers are the ten great powers that are not the pirates. **Companies race; merchant houses do not** (a merchant's sale or gift
  writes nothing after one players probe), so a player's work is what moves the race.
- **The week** runs Monday 00:00 UTC to Monday 00:00 UTC (`public.nation_race_week`). Nothing resets: the week is a key of the book.
- **Points** (`public.nation_race_book`, one writer `public.nation_race_post`; her country is read at the moment), from three existing
  doors, one hunk each:
  - a **sale** in a race city (`cmd.do_sell`): floor(the sale's total / 100); the SOLD event carries `race {points}`;
  - a **job**, a city's request fulfilled in a race city (`cmd.run_fulfil`): floor(its bonus x 3 / 100), on top of the sale's points;
  - a **gift or a stake** into a race city's purse (`public.pay_city`'s SHARE/DONATION branch, beside the influence it already posts):
    floor(the coin x 10 / 100).
- **A city's leader this week** is the country with the most points there (`public.nation_race_leaders`, the one reader).
- **The weekly settle** (`public.nation_race_settle`, run by the cron job `byeharu-voyage:nation-race`, hourly at :21, at most one week a
  run): the country leading the most race cities wins (ties: its points, then its code). Its top 3 companies that week each get 200
  Reputation (kind `nation_race`, keyed by the week: once) and hold the title **Champion** until the next week settles. One row a week in
  `public.nation_race_weeks`. Book rows older than 4 weeks are deleted by the same run.
- **The home perk**: her dock fee at a harbour her own country holds is 50 % less, through the one dock fee (`public.port_fee`, one hunk ->
  `public.nation_fee_factor`), so the charge, the trip's figures and the town hall agree. It stacks on the country factor and the regard
  band that already apply there.
- Influence itself (`port_influence`, the daily count, the flags, the mayors) is not touched: a gift still posts influence exactly as
  before; the race is a second, weekly book beside it.

## HQ (the owner's "choosing best options")
- `public.hq_board_for` gains ONE hunk before its return: `v_moves := public.nation_race_marks(p_player, v_moves)`. Lit, a trade card that
  sells in a race city and a request card in one carry `race {points, lead}`: what the move adds for her country (a trade: its sale total /
  100; a request: the sale's part of its net / 100 plus its bonus x 3 / 100) and who leads that city this week (`mine`, `rival`, `open`).
  The ranking is not changed.
- **The race strip** under the bridge (`RaceBridge.tsx`, `world.nation_race()` through `live/useNationRace.ts`): her country's flag and
  place (`1 of 10`), the top countries as flags with a bar of the contested cities each leads (hers in the accent), her influence this
  week, the week's countdown, the home perk (`−50%` on an anchor), the Champion laurel when she holds the title, and last week's winner's
  flag on a trophy.
- **The Influence chip** on a card: the banner and `+N`, green where her country leads, amber where a rival does (a city to win), muted
  where nobody has scored. The **Influence** filter chip (shown when any card carries one) lists only those cards.
- **The map's Race layer** (the filter's fourth choice, offered only while the race is lit): every contested city someone leads this week
  is ringed (hers green, a rival's amber, with the world events' rings) and its name carries the leader's flag.
- Words, EN and KO (`hq.ts`, `chart.ts`): Country race / 국가 경쟁, Influence / 영향력, Influence +N, You lead, Rival leads, Nobody yet,
  N of M, Week ends, Champion / 챔피언, Last week, Home dock fee −N%, Race / 경쟁. A row in `docs/WORDS.md`.

## Measured
- **Local chain (PGlite).**
  - The self-assert: 127-133 ms (dark world, and with production's switches lit: the purses, the closed economy, regard, Reputation,
    the board, the jobs, the contracts, influence).
  - Proof 187 (9 markers) 0.4 s. A lit sale's hook 0.06 ms; the board's marks 1 ms; the read 1 ms; an hourly run with nothing to settle
    under 0.1 ms. The proof's served request card at ACA: net 100,144, bonus 800 -> +1,017 for Portugal, and the fulfil added exactly that.
  - The home perk: her dock fee at Funchal 113 -> 56; a Castilian's there and hers elsewhere unchanged.
- **Prod (`before-0484`, the one read, 2026-11-23 11:30 UTC).**
  - The gate, in the same statement: beat mean 156 ms over 5 minutes (289 beats), 765 MB, 0 sessions waiting on the disk.
  - Head 20260818000483; no `nation_race_*` knob, table, function or reputation kind; each of the six hunks' anchor once in prod's live
    body and its new text nowhere; the six bodies' md5 equal the chain's (do_sell 4e3221bb, run_fulfil 57d06147, pay_city d5c23dc7,
    port_fee b7977e1f, hq_board_for 4280a08f, client_rpc_entry_points a5914b9e).
  - The probe's selections as the self-assert makes them: ACA (baltic amber), ACC, FNC (Portugal's home), ACA (not Portugal's).
  - 210 contested of 254 harbours; the ten racers; 19 companies (18 Portugal, 1 Japan). Switches: the purses, the closed economy,
    Reputation, regard, influence, the logbook and the board all lit.
  - The companies' own ledgers over 24 hours: no SELL, PREMIUM, DONATION or SHARE row. So lit today the race writes about nothing; at a
    busy hour it is one upsert a company act.
  - The marks' scan of the allegiance: 0.31 ms.

## Load (budget lines in the file)
- **Two new tables:** `public.nation_race_book` (a row a week, city, country and company: a few hundred a week at most; 4 weeks kept,
  trimmed by the job) and `public.nation_race_weeks` (one row a week).
- **One new cron job, hourly at :21:** dark one knob read, 0 rows; lit 0 rows a run except the first of a week (one week row, up to 3
  Reputation rows, the trim).
- **Nothing on the arrivals beat.** A merchant's sale on the beat pays one knob read (dark) or one players probe (lit). A company's sale
  pays one players probe, one allegiance probe and one upsert. A dock fee pays one knob read (dark) or a players and an allegiance probe.
- **A board read** adds one aggregate over the week's book (hundreds of rows) and the 254 allegiance rows.

## Decided by default (the owner may reverse)
- **The race cities are the contested harbours**; home cities never change hands, so a sale or gift there adds nothing.
- **Companies race, merchant houses do not** (cheaper, and the players' work decides it).
- **The rates:** 100 coin of a sale = 1 point; a request's bonus x 3; a gift or stake x 10 (knobs `nation_race_sale_per`,
  `nation_race_job_mult`, `nation_race_gift_mult`). Trade is not counted toward influence itself (0144's D3 stands): the race is its own
  book.
- **The country's jobs are the city requests in contested harbours** (no new job board). Courier contracts do not count.
- **The winner** leads the most contested cities; ties go to its points, then its code. **3 champions**, **200 Reputation** each, once a
  week; the title is held until the next week settles.
- **The home perk is 50 %** off the dock fee at every harbour her country holds (home or won), on top of the country factor and regard.
- **The week** is Monday 00:00 UTC; the job runs hourly at :21 and settles last week on its first lit run (an empty week settles with no
  winner).
- **The board's ranking is unchanged**: the race is a mark and a filter, not a new band.
- The map's Race layer is offered only while the race is lit; a kept "Race" reads as off where it is not.

## Prod checks
- Before: `scripts/ops/harness/nation-race/before-0484.sql` (done, the one read).
- After (and 30 minutes after lighting): `scripts/ops/harness/nation-race/after-0484.sql`.
