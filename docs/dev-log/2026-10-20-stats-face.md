# 2026-10-20 — the Stats tab's FACE (`osn-stats-face`, client only, no migration)

**The owner**, 2026-10-20, hours after 0214 went live (OWNER_REQUESTS rows 188 and 187):

* 188 — *"Statistic tab, it has no visuals, no charts, no number moving around... come on make it modern,
  sophisticated yet simple"*
* 187 — *"I want stats to be in real time- by seconds updated."*

0214 shipped the SERVER (the rollup, the gate, six reads) and a plain face: captions with figures under them,
and four small charts that drew NOTHING, because `SeriesChart` refuses a line below two points and the tab was
an hour old. That is what "no charts" meant, and it was fair.

**Nothing on the server moved. No migration, no new read, no new write.** The six reads of 0214 are the same
six; this is their face.

## The two cadences (request 187, answered the way row 187 already recorded)

The rollup stays at a count a quarter hour — that cadence is why it is cheap on a live database (per-second
snapshots would multiply a ~50 MB table by 900). The split:

* **RIGHT NOW** (`src/features/stats/LiveNow.tsx`) — a band on every face, fed by the store the shell ALREADY
  polls (AppShell's beat, 3 s at the current clock): your purse, your fleets at sea, your fleets in port, the
  cargo you carry, and the countdown to the next count. No read of its own, no second poller, no write.
* **THE ROLLUP** (`statsPulse.ts`) — re-asked once a minute as before, AND at the edge of the next count
  (`useReaskAtEdge` on the served `age_seconds` + `slot_seconds`, with 20 s of grace because prod's job runs at
  `6,21,36,51`). A fresh count reaches the screen within seconds of the server writing it, and the age beside
  the title ticks every second. The edge cannot loop: it is armed only when the next count was still ahead when
  the answer landed, so a late job arms nothing and the minute backstop catches up.
* **The age is a GAP, never a date**: the server's `age_seconds` plus the time elapsed here, both on the one
  clock (`lib/serverClock`). A device whose clock is an hour out still measures a minute as a minute.

## The visuals (request 188)

**Five new primitives in `src/components/ui`** — each one promoted because two or more faces wanted it:

| primitive | is | callers |
|---|---|---|
| `Counter` + pure `countUp.ts` | a `Figure` that WALKS to its new value over 480 ms, ease-out, and is set at once for `prefers-reduced-motion` | every headline figure on the tab |
| `StatCell` | label · that one figure (counting) · its move · its sparkline, no box | fourteen hand-written copies across the five faces |
| `StackedBar` | one whole cut into the KINDS that make it up, 2 px of surface between segments, legend with figures | the world's money by holder, the merchants' fleets |
| `RankBars` | a short list in order, each row's bar against the biggest (built out of `Row` + `Bar`) | the world's flows ×2, risers, fallers, most traded, a city's top goods ×2, its flows, best and worst merchant day, your best sales |
| `SignedBars` | one bar a period, up for a gain and down for a loss from the one zero line; the bar capped at 24 px and centred in its slot | the desk's Profit face (now composes it instead of its own grid), the world's new money, a city's income, your week |

`SeriesChart` gained ONE prop, `empty`: what stands where the line would be while the record is too short to
draw one. Default null — every existing caller is unchanged. The Stats faces pass *"The line starts with the
next count"*, which is the honest sentence and the fix for the owner's "no charts".

**Face by face.** Overview: a hero figure for every purse in the world (with the day's new money as its delta),
the four holders as one stacked bar and then as four cells with their own sparklines and shares, the world's
whole purse as one chart, the day's printed / burned / moved / trades as counters, net new money as bars a
count, what the cities bought and sold as two small multiples, and the flows by kind as ranked bars. Markets:
the day's market as four counters (goods traded, units traded, rose, fell, in the window the player chose),
then risers / fallers / most traded as ranked bars, then every good as before (row, sparkline, price, move,
stock). Cities: what you can read as counters, and **a bar on every locked row showing how far your stake has
got** — a lock that says only "invest 20,000" is a wall; one that shows two thirds is a game. A city's own face
(now `CityDetail.tsx`, so no file is over 250 lines) draws its purse as a line, income less spending as bars a
count, its top goods and its flows as ranked bars. Merchants: where the fleets are as one stacked bar (blue
moving, green in port, amber repairing, red cannot sail, grey laid up — §4.4's tones), the day's figures as
counters with sparklines, and two charts (what they earned, how many were at sea). Me: the week as counters
with today as the hero, the seven game days as the desk's own signed bars, your best sales and the leaderboard
as before.

**Tokens only**, so both schemes work; one accent; green–red only for new money against burned and for gain
against loss; text in ink tokens and never in a series colour; a legend wherever colour carries identity; no
box, no border, no second palette.

## Decided by default (the owner may reverse any of these)

1. **The live figures are yours, not the world's.** The honest live reads are the ones the shell already makes
   (purse, fleets). The world's money, the goods and the cities are sums over every market and every harbour;
   they cannot move faster than the job writes them, and a ticker that re-printed the same number every second
   would be a lie about the data. `world.sea_traffic` was considered for "merchants at sea now" and refused: it
   is capped at `sea_traffic_max` (240 of 854 fleets), so any count drawn from it would be wrong.
2. **The rollup's cadence is untouched**, and no knob was changed. `stats_fine_hours` is still there if the
   owner later wants the history itself finer.
3. **A bar row shows the last 24 counts** (six hours), not all 96: at 390 px a 96th of the sheet is thinner
   than the gap beside it. The charts still carry the whole window.
4. **The counter is the one new motion** §4.6 allows, and only for a figure whose served value changed.
5. **`Counter` takes the NUMBER and the formatter**, so every step reads in the game's own spelling.
6. **Profit (the COMMAND desk) was repointed** onto `SignedBars` rather than left as a second copy. Its figures,
   its testid and its aria label are unchanged; the bars are now capped at 24 px and 2 px apart.

## Verified here

`npx tsc -b`, `npx eslint .`, `npm run build`, and the pure specs: `countUp` (new — the walk's ends, its
easing, and that a flow's tone is the server's side), `seriesChart`, `duplication`, `sections`, `words`,
`format`, `i18n.keys`, `planWords` — 50/50. The world specs are CI's (this computer never builds the PGlite
world from zero); `tests/stats.tab.spec.ts` gained the live band, its purse, a drawn chart on the Overview and
the seven bars on Me.
