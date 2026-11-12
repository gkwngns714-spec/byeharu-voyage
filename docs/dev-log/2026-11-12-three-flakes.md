# 2026-11-12 — Three intermittent reds, each read to its cause

Three reds came and went on CI on 2026-11-11. One is a defect a player meets (the Stats page jumps); the other two are
defects of the specs' own waits. Client only, no migration.

## 1. Stats > Overview: the chart jumped when the Economy Watch landed (real, fixed)

**The red.** `tests/news.dotSize.spec.ts:169` at 390: `stats world @390: pressing "4 news" moved its chart: y 255 → y 611`
(run 43103929440, shard plain 2/3).

**The cause.** The Economy Watch card stands directly above the world's chart (`Overview.tsx`). Its figures ride the live
read (`world.stats_now`), which is a second read behind the face's own (`world.stats_overview`) on one queue. The card drew
nothing until that read landed (`Watch.tsx`: `if (!watch) return null`), and then a whole card appeared above the chart:
on a phone the chart dropped by the card and its gap; at 1,280 it changed column.

**The fix** (`src/features/stats/Watch.tsx`). The card is drawn from the first frame. Its lines stand in one box that is
seven statement lines tall (7 × 52 px), before the read and after it:
- while the read is out, the box holds seven `Skeleton` lines (the one loading placeholder, so `ready()` and `settled()`
  in the specs now wait for the watch too);
- once it lands, the box holds the lines the server served. A line it did not serve leaves its room at the foot of the box.

`data-watch-loaded` on the box says which is drawn. `Overview.tsx` hands the card the live answer (`live`), not
`live?.watch`, so the card can tell "the read is out" from "this world has no watch yet".

**Decided by default (the owner may reverse it).** The card's height depends on which of the seven lines the server
serves (a world under a day old has no day total; an hour with no price step has no swing), so there is no single "real
height" to reserve before the read. A card that is always seven lines tall is the only card that never moves what is
under it — at the landing, and also hour by hour when the swing line comes and goes. The cost: in a world that serves
fewer lines (the local test world serves five) the card has empty room at its foot — 104 px on a phone; from 768 px the
card is in a row beside the chart and was already stretched. In production all seven are normally served. The other way
to do it, if the empty foot is not wanted: hold the whole face in its loading state until both reads have landed (what
the city page now does, below) — no empty room, but the face opens one read later and the swing line still moves the
chart when it comes and goes.

**Not covered:** a world that has not been counted yet (`watch` null after the read lands) draws no card, as before; the
placeholder then goes away once. The Overview of such a world is the "no figures yet" note in any case.

**The sweep** (Overview, Merchants, CityDetail, News, and the band above them): the same pattern — something above other
content that is not drawn until a later read lands.

| Where | What | Done |
| --- | --- | --- |
| `Overview.tsx` Watch card | above the world's chart; rides `stats_now` | fixed (above) |
| `CityDetail.tsx` people block (population strip + chart) | in the middle of the page; rides `stats_city_people`, a second read | fixed: the page keeps its loading placeholder until both reads have answered (the idiom `Me.tsx` already uses). A failed people read still ends the wait. |
| `CityDetail.tsx` "Wanted" note at the top | rides the store's market read (`loadMarket`) | NOT changed: absent while city wants are dark, and there is no way to tell "not loaded" from "none" without waiting on a read that may never be wanted. Reported. |
| `LiveNow.tsx` "funds at sea" card (the band on every face) | a fifth card, served only while a cargo ship exists; rides `stats_now` | NOT changed: whether it exists is not known before the read. Reported. |
| `Merchants.tsx`, `News.tsx` | one read each; the news dots are drawn on the chart, not in the flow | nothing to fix |
| `Overview.tsx` Bonus card, `CityDetail.tsx` bonus / flows / goods | same read as the page | nothing to fix |

**The law.** `tests/stats.watchHold.spec.ts`, at 390 and 1,280. A local world has no network seam, so the read is held
another way: every ask prints one `[rpc]` debug line before it is made, and an ask that throws is a failed ask the live
read repeats a second later. The spec makes the page's `console.debug` throw on `world.stats_now` until it lets go. With
the chart drawn and the watch read out for certain, a per-frame sampler records the chart card's box and the watch card's
box on every frame until after the landing; each must be one box throughout, and the sampler must have seen both sides.
On main's build the law is red at both widths ("the watch card does not hold its place while its read is out").

## 2. The map: the tray that "remounted" (not a remount; a spec defect, fixed in the spec)

**The red.** `tests/map.merchants.spec.ts:677` at 1,280 waited its whole 40-minute test on `tray-close` (run
43103929440, shard npc 1/2).

**The reading that was offered** — the open sheet swaps component when a traffic read omits the hull — is not what
happened, and the code cannot do it for a merchant:
- the traffic the map draws is the kept roster (`seaRoster.ts` `mergeRoster`: "nobody is dropped"); a hull leaves it only
  on a full read, once in ten minutes;
- for an ordinary merchant the three special ids (`cargoId`, `navyId`, `pirateId`) are null whether or not she is in the
  read, so the same `MerchantSheet` with the same key stands in the same place: React keeps the node.

**What the trace says** (the run's own Playwright trace, read event by event):
1. 101,153 ms: hull A tapped; `world.npc_fleet_card` asked 15 ms later; her sheet opens.
2. 101,649 ms: the spec presses her ✕. A side panel slides out for 240 ms before it is gone (`Tray.tsx`, `leaving`).
3. 101,823 ms (174 ms later, the slide still running): the spec taps hull B at (865, 166). **No card is asked** — the tap
   selected nothing.
4. 101,832 ms: "is a merchant sheet visible?" answers yes — it is A's, still sliding out. The spec takes it for B's and
   reads it.
5. 101,950 ms: the spec presses the ✕ again; at 102,033 ms the slide ends and the button is "detached from the DOM,
   retrying" — printed once, not in a loop. No tray ever comes back, and a `click()` with no timeout waits for one for
   the rest of the test.

**Why the tap selected nothing — measured locally at 1,280 on the merchants-on world:** with no panel open, (865, 165) is
the sea. With a sheet open, and for the 240 ms it slides out, the chart's corner controls stand shifted to the panel's
left edge and (865, 165) is `map-view-controls`, which answers no tap (it is chart chrome). A tap there while a sheet
leaves: 40 ms later one sheet is still counted; 640 ms later there is no tray at all. That is the red, reproduced.
The app is right at each step (controls take no tap; a closing panel finishes closing). `MapScreen.tsx` is not touched.

**The fix** (`tests/map.merchants.spec.ts`). One helper, `closeOpenTray`: press the ✕ (60 s at most) and wait until the
tray is gone before the next aim — the real condition: the controls are back at the edge and no old sheet can answer for
a new one. The hull hunt (`openMerchantWorthReading`) and the re-aim (`tapHull`) use it; `closeTray` got the 60-s bound.
A stuck tray now fails in a minute with a sentence instead of holding a shard for 40.

## 3. `tests/city.goodTrades.spec.ts:40` beside `align` and `city.audit` (a spec defect, fixed in the spec)

**Reproduced** on main's build: the trio with two workers, run 3 of 3 red at 36.2 s: `Timeout 30000ms exceeded while
waiting on the predicate` at the retry block after the resize to 1,280.

**The cause, from that run's trace.** After `setViewportSize` the desk swaps to its wide form a moment later (matchMedia →
React → the desk remounts, and the phone's tray closes with it). The retry block asked two questions as two reads —
"is the tray there?" (yes, 10 ms after the resize) and "is it unfolded?" (no, 4 ms later: the swap had landed in
between) — and then pressed the tray's More with no timeout. The tray was gone; the press waited for it; a retry block
cannot interrupt a press, so it never retried and its 30 s ran out with the press still unfinished in the trace.
Measured: the swap lands 33 ms after the resize on an idle machine, 204 ms with the CPU slowed 6 times, 1.4 s at 20
times. Two busy workers beside it only widen the window. Nothing is shared between workers; the app does what it is
meant to.

**The fix.** The spec waits for the swap itself — the desk says when it is the wide one (`data-desk="terminal"`,
`CommandScreen.tsx`) and the phone's tray is gone with it — and then presses. The More press is bounded (5 s), so the
retry block that remains (the wide ledger is a fresh mount) really retries.

## Checks (local, a served build, headless)
- `tsc -b`, `eslint .`, `vite build`: clean.
- `tests/stats.watchHold.spec.ts`: red at both widths on main's build; 2 of 2 green on this branch (and again in the run below).
- `sections`, `duplication`, every `stats.*` and `news.*` spec, two workers: 77 passed, 0 failed.
- The trio `city.goodTrades` + `align` + `city.audit`, two workers: main's build 2 green and 1 red in 3 runs; this branch
  5 green in 5 runs (12 tests each).
- `tests/map.merchants.spec.ts` on the merchants-on world, one worker: 15 passed. The one red, `:239` ("7 merchants · 4 in
  port" read as Korean), is the plain-Node word test that fails on this machine's Korean locale and passes on CI
  (CLAUDE.md); it opens no browser and this branch does not touch it.
