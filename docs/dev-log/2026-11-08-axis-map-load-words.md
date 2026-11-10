# 2026-11-08 — a young chart's axis, the map's loading percentage, the real-life cell, the phone's send button (client only)

The drive audit (#560, `docs/dev-log/2026-11-08-drive-audit.md` §2 and §3) reported, beside the HQ's four defects (fixed by #562 and
#563), two smaller defects and two observations a player would meet on a young world, on the map, on a city's Stats page and on a
phone: D5, D6, O4 and O7. Client only: no migration, no server change, production never touched. Worktree `fix-axis-map-load-words`
from origin/main 2353770b, rebased on de22c145 (#562); the local PGlite world (no `.env.local`); `vite preview --port 4209 --host
localhost`; every spec `--workers=1`, headless, DPR 2. The pure model laws ran in Node with its global `navigator` off
(`NODE_OPTIONS=--no-experimental-global-navigator`): this machine's locale is Korean, and the dictionary would otherwise answer "지금"
where CI reads "now".

## D5 — a young world's chart: "now · now · now" and a −1 🪙 floor

**What the walk saw.** The Stats › Cities face's City purses chart of the shipped young world — two points, the boot's own count and
the live point, a second apart, both 0 — labelled all three x ticks "now" and drew its flat 0 line between the y figures "1 🪙" and
"−1 🪙" (`stats-cities-young-1280@2x-before.png`). Every flat series did the same: a city page's own purse chart drew "1 🪙" over its
flat line of 0 (`stats-city-people-1280-ko@2x-before.png`, bottom).

**Cause.** `src/components/ui/seriesChartModel.ts`, the one model every series chart draws from: `agoLabel` rounded every stretch under
a minute to "now", and a zero-range y band was padded by ±1 (so as not to divide by zero) and then PRINTED as the axis.

**Change** (the one model; the right-edge rule of #551, `wholePeriods`, untouched):
- `agoLabel` is one rule at any span: seconds under a minute (`30s` / `30초`, the existing `format.shortS`), minutes under an hour, hours
  under two days, days under two years, years to a tenth. The price chart reads it as before (days and years only).
- an x label that would only repeat its neighbour is dropped — the middle first (the edges are the axis's anchors), then the left when
  the whole span itself rounds to now — so no two labels say the same thing: a series 40 s old reads `40s · 20s · now`, one a second old
  `1s · now`, one younger than half a second `now` alone.
- a flat series has ONE y figure, its own value, at the line — the price chart's own rule for a flat price (`priceChartModel.ts`, one y
  label when the band is 0). The padding stays geometry. `SeriesChart.tsx` prints that one figure at its line instead of a high and a low.

## D6 — the map had no loading percentage (owner row 255)

**The owner** (2026-10-31): *"when reloading, for example opening the city, or loading the map, show percentage of its loading
time"*. The city got `LoadMeter` (measured work: one `done` per real read, no timer; `tests/city.audit.spec.ts`); the map kept a plain
line, "opening the chart…", in the middle of the sea (`map-loading-{1280,390}@2x-before.png`).

**Change** — the same component, the same rule, nothing measured twice:
- `src/live/loadSteps.ts` (new): `worldLoadSteps(t, boot)` — the world's three real steps off the store's `boot` (World · Sea · Fleets),
  said once; their words move from `city.load*` to `common.load*` (the same words, EN and KO). The city appends its hall as before
  (`CityScreen.tsx`).
- `src/features/map/MapScreen.tsx`: the map appends its own served read — the first roster of the ships at sea (`traffic`: null until it
  lands, dark or lit; `map.loadShips` "Ships" / "배") — and lays the one `LoadMeter` over the sea as an overlay (`map-load-host`:
  absolute, pointer-transparent, top centre, clear of the fleets corner and the zoom column): the same spot before the chart and over it
  for the beat the roster still takes, so nothing moves when it goes. `ChartMessage.tsx` keeps the refusal and loses the line. Two
  comments that named the line (`AppShell.tsx`, `tests/seaFrame.fixture.ts`) say what stands there now.
- The roster is a step from the first frame while the world opens (the screen's effect asks for it at once), and once the world is up
  only from the moment it is asked (`trafficWanted`, this screen's alone). Why: a lit world (production's) KEEPS the ships it has read
  across tabs and places them in the very call that asks for them (`wantTraffic`), so on a return to the map the read is not pending —
  but the screen's first commit, before its effect, still held `traffic` null, and a meter listing the step from the first frame
  committed "Ships 75 %" for that one frame and removed it (a flash at the top of the sea on every return; the law below caught it).
- What a player meets: a cold load of the map counts World → Sea → Fleets (→ Ships) and the meter is gone the instant the last read
  lands. Back on the map from another tab the world is already up: on a lit world nothing shows (the kept ships paint at once); where
  the roster must be read again (a dark world, or a first visit with nothing kept) "Ships 75 %" stands for that read.

## O4 — "Real life (c. 1650) 0.0 %" read as "real life is 0 %" (owner row 273)

**The row's own word** for the cell was *vs real life*. The figure is the DIFFERENCE from the real-world population, and the cell printed
it under "Real life (c. 1650)" / "실제(약 1650년) 대비" — a share without its whole (`stats-city-people-1280-{en,ko}@2x-before.png`).

**Change** (`src/features/stats/CityDetail.tsx`, `src/lib/i18n/dict/stats.ts`): the label is "vs real life" / "실제 대비"; the figure keeps
its sign (`formatPctChange`, unchanged: `+4.2%`, `−3.0%`, `0.0%`); the real figure stands under it with its year — "4,000 in 1650" /
"1650년 50,000명" (`stats.peopleReal`), the way the Population card carries its step under its figure; `data-baseline` carries the served
figure for the law.

## O7 — the phone's send button "drops the sum" (owner row 76): not reproduced, now held by a law

**The audit** read "Buy 10 units" at 390 and "Buy 10 units · 5,748 🪙" at 1280. The sum is the server's own for the quantity — the dry
run, `src/live/useTrade.ts`, asked once the quantity has rested 200 ms — and the button prints it only once it is the sum for the
quantity on the button. Replayed on the old build at both widths with a recorder on the button (a probe, not committed):

| | 1280 | 390 |
|---|---|---|
| button live, reading "Buy 10 units" | +290 ms | +230 ms |
| the sum lands, "Buy 10 units · 5,748 🪙" | +545 ms | +485 ms |
| the audit's read: 300 ms + one full-page screenshot after the tray opened | screenshot 174 ms → read the sum | screenshot 89 ms → read before it |

So the phone carries the sum ~250 ms after the button goes live, as the laptop does; the audit's phone read came first because the
phone's screenshot is the smaller one. On a phone the button stands at the foot of the tray, below the fold: the sum has landed before a
thumb can reach it. **No product change.** The law stands so a phone that ever drops the sum goes red: `tests/drive.market.spec.ts`, at
390 in English and Korean — the button carries "🪙" once the price is served ("Buy 10 units · 5,748 🪙" / "10개 사기 · 5,748 🪙", one
line beside "Add"), on the 44-px reach floor, inside its panel, nothing cut (`market-tray-send-390-{en,ko}@2x.png`).

## Red first, then green

RED on 2353770b (the old build, the new laws; 9 failed, 4 passed in 3.5 min):

| law | the old build said |
|---|---|
| `seriesChart`: a stretch under a minute | `agoLabel(30 s)` = "now" (expected "30s") |
| `seriesChart`: a flat series has one y figure | three y ticks, `[-1, 0, 1]` (expected `[0]`) |
| `drive.stats`: the young world's City purses chart (D5) | "2 points, flat; x labels [now \| now \| now]; y figures [1 🪙 \| −1 🪙]" |
| `drive.map` @1280, @390 (D6) | "the map showed no loading percentage": no meter written, cold or warm |
| `stats.cityPeople` ×4 (O4) | "Real life (c. 1650)0.0%" / "실제(약 1650년) 대비0.0%" |
| `drive.market` @390 en, ko (O7) | GREEN: "Buy 10 units · 5,748 🪙" 310 ms / "10개 사기 · 5,748 🪙" 321 ms after the button went live |

And the meter's first form (the Ships step listed from the first frame, as drafted), on the merchants-on world (`npcOn`):
`drive.map` "merchants on: a return to the map commits no frame of meter" RED — cold `world 0, sea 25, fleets 50, fleets 75, gone`;
back from the HQ one meter committed and removed, `[{ships 75}, gone]`. With the step listed only once asked: back from the HQ `[]`,
GREEN (cold unchanged).

GREEN on the rebased branch (0dfa7a2f on de22c145), `tsc -b`, `eslint .` and `vite build` clean, then ONE run of every spec this
touches, one worker: **437 passed, 0 failed, 0 skipped (40.9 min)**.

| law | the new build says |
|---|---|
| `seriesChart` (7) | `['40s', '20s', 'now']` for a 40-second series, `['1s', 'now']` a second old, `['now']` under half a second; one y figure `[0]` on a flat 0 |
| `drive.stats` young world (D5) | "2 points, flat; x labels [1s \| now]; y figures [0 🪙]; reading 0 🪙" |
| `drive.stats` counted world | eight quarters, labels `2h · 53m · now`, every series on its right edge, no falling last point (findings `[]`) |
| `drive.map` @1280 / @390 (D6) | cold: World 0 → Sea 25 → Fleets 50 → 75 → gone, `data-world` ready when it went, every entry `position: absolute`, the chart's box `0,32,1280,711` / `0,32,390,755` throughout, the old build's own box; back from the HQ: Ships 75, then gone |
| `drive.map` merchants on (D6) | cold World 0 → Sea 25 → Fleets 50 → 75 → gone; back from the HQ: no meter at all |
| `stats.cityPeople` ×4 (O4) | "vs real life 0.0% 4,000 in 1650" (Acapulco) and "실제 대비 0.0% 1650년 50,000명" (the Korean sort's first city), at 1280 and 320, sign law held, no sideways scroll |
| `drive.market` @390 en, ko (O7) | "Buy 10 units · 5,748 🪙" 310 ms / "10개 사기 · 5,748 🪙" 325 ms after the button went live; 44 px, inside the panel, nothing cut |

The rest of the run, unchanged and green: `align` 2, `city.audit` 9, `consistency` 17, `drive.hq` 11, `drive.nav` 4, `market.desk` 3,
`i18n.keys` 4, `i18n.ko` 2, `words` 1, `planWords` 12, every other `stats.*` (42) and every `map.*` (301, the merchants-on world among
them; `map.atmosphere` included though no CSS file changed). The tally counts two uncommitted probe tests that measured the loaded
map's box on the old build and the new (`0,32,1280,711` and `0,32,390,755` on both).

## Pictures (`docs/dev-log/2026-11-08-axis-map-load-words/`, DPR 2, read)

- D5: `stats-cities-young-1280@2x-before.png` ("now now now", "1 🪙" and "−1 🪙" around a flat 0) → `stats-cities-young-1280@2x.png`.
- D6: `map-loading-{1280,390}@2x-before.png` ("opening the chart…" mid-sea) → `map-loading-{1280,390}@2x.png` (the meter on a plate at the
  top of the sea).
- O4: `stats-city-people-1280-{en,ko}@2x-before.png` → `stats-city-people-1280-{en,ko}@2x.png`.
- O7: `market-tray-send-390-{en,ko}@2x.png` (the button with its sum, beside "Add").

## What is not proven

- Never driven on production. The lit world's return to the map was driven on the local merchants-on world (`npcOn`), the shipped image
  with the merchants switched on, not on production's own roster.
- A city whose population differs from its real figure: every city the laws opened stood at 0.0% (the population step is dark
  locally), so the signed `+` / `−` figures were held by the law's rule (the sign of population ÷ real − 1) but not seen.
- A young chart in Korean was not photographed: the words are the dictionary's existing `format.shortS` / `shell.now` ("30초", "지금").

## Seen in passing (not this slice)

- The price chart's legend prints "low", "now", "high" (and "estimate", "best") as literals in `src/components/ui/PriceChart.tsx`, not
  through the dictionary, so a Korean glass reads "비용 · 판매 · low · now · high" (`market-tray-send-390-ko@2x.png`, the Market chart
  under the tray).
- On a phone, with the trade tray scrolled to its send button, the tray's span chips (1 day … All) stand over the city header's flag at
  the top of the glass (`market-tray-send-390-{en,ko}@2x.png`, top edge).
