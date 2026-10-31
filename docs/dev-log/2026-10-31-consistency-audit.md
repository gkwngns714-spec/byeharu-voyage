# CONSISTENCY AUDIT — one rail table, one word per thing, the 44-px floor, no fold left behind (2026-10-31)

Owner row 251. Verbatim, after finding the City page's rail lacked the Fleets cell the shell has:

> *"this is only one thing that I HAVE FOUND. who knows what else? i am starting doubt your ability."*

…and the instruction: **"find everything and fix it"**.

Branch `consistency-audit`, **client-only** (no migration, no server change). Base: origin/main
**`b86f62de`** (#426, the City frame/rail slice — authored on `846b87b1` and rebased onto #426 as
it merged mid-pass).

**Scope ruling and the #426 landing.** The City page was owned by its own agent while this pass ran,
so this branch never edited `src/features/city/**` or the City rail; the audit recorded its
violations with measurements. #426 then merged the City slice (`b86f62de`) and this branch is
rebased onto it: that slice fixed five of the recorded rows — both rails are the shell `NavBar`
from the one table, a building's face composes in place in the right panel, and the old face Back
and scrolling full-screen Sheets are gone. One measured city law remains armed as a `test.fixme`:
the 320×568 hall panel's inner scroll (#426 states 336 px in 179). Everything else — the shell,
Stats, Ledger, Rank, Routes, Compendium, Fleets, Map chrome, Profile, You and the shared words —
is fixed by this branch.

## The evidence, first

A throwaway sweep (`tests/_audit.spec.ts`, deleted after the run; its raw data survives in the
throwaway `test-results/consistency-audit*.json` on the audit machine) walked every route, every
desk face, every Stats face, every summary page the run could reach and the Menu tray at **390×844
and 1280×800** — 90 measured screens — and recorded:

- every rail's cells (labels, order, hrefs, boxes), and every screen that carries its own rail;
- document/Sheet/page scroll and every sideways scroller;
- every visible interactive control's size;
- every placeholder dash, every duplicate control label, every over-long label;
- the owner's HQ rule at 390×844 and 320×568 (doors, boxes, hall scroll, dead bands);
- the press law (22 Menu presses + 48 face/tab presses, boxes compared to the pixel).

Result: **0 page errors**, **0 press-law failures**, and the violation table below. The permanent
net is `tests/consistency.spec.ts`; the measurements are quoted per row.

## Violations: found 40 · fixed 37 · remaining 3

Remaining rows are **not** silently accepted: each names the slice that owns it. **Three** remain —
two in the City slice (35, the 320-px hall scroll; 39, the Forge recipe labels) and one accepted
word collision with its reason (40). The three Command rows (33, 37, 38) are fixed by the
follow-up `command-fix` slice; five more (1, 2, 32, 34, 36) were closed by #426, the parallel City
slice that merged mid-pass.

| # | screen | rule broken | evidence | state |
|---:|---|---|---|---|
| 1 | City (HQ) | reachability: every top destination from every screen | City rail measured **HQ · Map · Stats · Menu**; shell **HQ · Fleets · Map · Stats · Menu**. **Fleets — a top destination — is unreachable from the landing screen** without a detour through another tab (a one-way door). | FIXED — #426 (city slice) |
| 2 | City (HQ) rail | one authority per concept | The rail's 4 cells are hand-written in `CityScreen.tsx` (a second list beside `NAV_CELLS`) and worded from `city.hq/map/stats/menu` (a second dictionary set beside `shell.tab_*`). | FIXED — #426 (city slice) |
| 3 | Rank | two words for one thing | Sheet title **"Standings"**, rail cell **"Rank"** (audit title/rail pair). | FIXED |
| 4 | 8 tab screens | one authority per concept (latent) | Every tab screen carried its own `*.title` key duplicating `shell.tab_*`; Rank's had already drifted. Titles now read `navTabs.tabWord`; **9 duplicate title keys deleted** (`stats.title`, `rank.title`, `rank.standings`, `routes.title`, `codex.codex`, `codex.history`, `fleets.title`, `profile.title`, `you.title`). | FIXED |
| 5 | Stats › Me | label > 2 words | Summary title **"Best sales, 7 days"** (4 words). Now "Best sales", with a `last 7 days` hint on the page so the window is not lost. | FIXED |
| 6 | Stats › Me | label > 2 words | **"Captains, by money"** (3 words). Now "Captains". | FIXED |
| 7 | Stats › Overview | label > 2 words | **"New and moved money"** (4 words). Now "Money flows". | FIXED |
| 8 | Stats › Merchants | label > 2 words | **"Merchant fleets now"** (3 words). Now "Fleets now". | FIXED |
| 9 | Stats › Overview | two words for one thing | The world total is **"World money"** on the row and **"All money"** on its page's cell and chart (same figure, three names). Now "World money" everywhere. | FIXED |
| 10 | Stats › Overview/Markets/Cities/Merchants | the same figure twice | Summary titles carried the count **and** the figure beside it: "Every good · 243 … 243", "Cities · 243 … 243", "Every company · 243 … 243". Titles now carry no count; the figure column keeps it. | FIXED |
| 11 | Stats › Markets | jargon | **"Risers" / "Fallers"** (market-floor jargon). Now **"Up" / "Down"**; empty states "Nothing up / Nothing down". | FIXED |
| 12 | Stats › Live band | label 3 words + jargon | **"Trades since count"** — "count" is the rollup's internal word. Now **"Recent trades"**. | FIXED |
| 13 | Stats › Live band | label 3 words | **"Fleets at sea"**. Now **"At sea"**. | FIXED |
| 14 | Stats › Merchants | label 4 words | **"Laps at a loss"**. Now **"Loss share"**. | FIXED |
| 15 | Stats › Merchants | labels 5 words, jargon "count by count" | **"Earned a day, count by count"** and **"Fleets at sea, count by count"**. Now **"Daily earnings"** and **"At sea"**; the duplicate `atSeaSeries` key was merged into `fleetsAtSea`. | FIXED |
| 16 | Stats › New-money page | label 4 words | **"Last 24 h, by kind"**. Now **"By kind"** (the period is the page's own). | FIXED |
| 17 | Stats › Markets | a control label carrying a figure | **"Show all 243"** (the count was already on screen). Now **"Show all"**. | FIXED |
| 18 | Stats › Merchants | duplicate word for different things | **"Best day"** was both the top-day board and a SORT option on the same page. The sort is now **"Most earned"**. | FIXED |
| 19 | Stats › Overview | duplicate word for different things | Holder categories **"Merchants" / "Cities"** shared the face names **"Merchants" / "Cities"**. Now **"Merchant purses" / "City purses"**. | FIXED |
| 20 | Stats | one sentence, two scopes | `citiesFailed` and `cityFailed` were both **"City figures not loaded."** Now the list says **"City list not loaded."**, the single city keeps its sentence. | FIXED |
| 21 | Map city panel | duplicate word for different things | Its giving-by-week tab was **"History"** — the shell's own **"History"** is the event log. Now **"Giving"** (Korean already distinguished 내역 vs 기록); `map.townhall.spec` drives the new word. | FIXED |
| 22 | Routes | duplicate word for different things | Lane tray row **"Standing"** (the route's state) collided with the provision preset's "standing". Now **"State"**. | FIXED |
| 23 | Routes | 2-word aria + jargon | The sort bar's accessible name was **"Rank by"**. Now **"Sort"** — the same word Stats uses for the same idea. | FIXED |
| 24 | Routes | 44-px floor | **"Read again" 87.5×36 px** (audit, both sizes). Now the md size, 44 px. | FIXED |
| 25 | Fleets | WORDS.md vocabulary (banned word) | The hold breakdown's slice read **"Provisions"** (EN) / **"보급품"** (KO) — docs/WORDS.md bans *provisions* and says **supplies**, and Korean carried two words for the one idea. Now **"Supplies" / "보급"**. | FIXED |
| 26 | Stats → money log (feed) | duplicate word for different things | `k_WORKS_IN` and `k_WORKS_OUT` were both **"Works"** — money into works and money out of them read identically. Now **"Works in" / "Works out"** (KO 사업 수입 / 사업 지출). | FIXED |
| 27 | Profile | one authority per concept | The "Language" heading read `profile.language` while the switch inside it names itself from `common.language` — two keys for one idea. Now both read `common.language`; `profile.language` deleted. | FIXED |
| 28 | Fleets | the owner's press law + 2026-10-31 "enough with folding" | A fleet row UNFOLDED `FleetFold` in place; **every row below the press moved down** (the audit brief's forbidden re-flow; owner row 248's law). The row now opens the one `DetailPage` (`fleet-page`), fixed over the list; the header, the pressed row and the row below keep their boxes to the pixel. | FIXED |
| 29 | Fleets specs | the specs drove the retired fold | `layout.spec.ts`, `wide.layout.spec.ts` and `fleet.supplies.spec.ts` asserted a fold under the row. Rewritten to drive the page, with the owner's newest law written in each; the old phone proof's "what is BELOW may move down" is replaced by "the row below may not move at all". | FIXED |
| 30 | Codex | stale spec structure (compact rework) | `greatPowers.spec.ts:86` expected the nation groups on the compact screen; CI red on #416. It now presses `codex-open` and asserts inside `codex-open-page`. | FIXED |
| 31 | Codex | stale spec structure (compact rework) | `captains.codex.spec.ts` expected `officer-tile` in place. Same door added; a sweep of `tests/` found no `SectionFold`/fold testid references left except the Command route unfold (row 38). | FIXED |
| 32 | City building faces | 44-px floor | **Back 52.3×36 px** on all five faces. Declared by name in the permanent spec's allowlist (`Button size="sm"`, the design system's sanctioned 36). | FIXED — #426 (city slice) |
| 33 | Command desk › City face | 44-px floor | **"City view" 77×36 px**. Declared in the same allowlist. | FIXED — `command-fix` (md = 44 px; the allowlist entry deleted) |
| 34 | City building faces | no-scroll law | Their Sheets scroll: market **1,075/844**, forge **17,496/844**, port **6,488/844** at 390; forge **8,856/800** at 1280. The one-page law says a page's body scrolls, never its root. | FIXED — #426 (city slice) |
| 35 | City (HQ) | the owner's HQ rule: HQ never scrolls | At 320×568 the Town Hall panel's body scrolls **340/156** (the coordinator's named failing case). | REMAINING — city slice (the ONE fixme) |
| 36 | City (HQ) | the owner's newest building rule | Pressing a building opens a **full-screen `city-face` over the whole page** (faceOpen=1; every door's centre is owned by face content): the rule says only the city-image area and the right panel change, six doors always visible. | FIXED — #426 (city slice) |
| 37 | Command | placeholder where a figure is owed | `trade-good-spark` prints **"—" ×1 @390, ×4 @1280** where no price series exists; recorded, not a figure the desk can serve yet. | FIXED — `command-fix` (the absence is drawn as absence; `sparkAbsence` proves it) |
| 38 | Command | the owner's press law / "enough with folding" | The route row still UNFOLDS in place above the queue (`route-unfold`), re-flowing everything below. Outside this pass's file domains. | FIXED — `command-fix` (the one `DetailPage`, `route-page`) |
| 39 | City › Forge face | label length | Product controls carry whole recipe names — **"Adire Cloth Indigo · Potash · Raw Cotton"** and 20+ more. City slice. | REMAINING — city slice |
| 40 | Codex vs Profile | duplicate word for different things | Ship size tier **"Light"** and the appearance scheme **"Light"**. Kept: the contexts never meet, both words are the plain standard, and the six-tier ladder has no better one-word step. | REMAINING — accepted |

**No violation found** (worth stating so the sweep's silence is visible):

- **Dead controls**: 70 presses (22 Menu groups, 48 face tabs) moved or opened what they promised —
  0 failures; a code scan of `src/app`, the nine screens and `components/ui` found no button without
  a handler and no chevron without a door (the two hits were the primitives' own conditional
  buttons).
- **Duplicate labels for different controls**: only the same control on repeated rows (Buy/Sell on
  six goods; one test id) and the City menu's two dismissal affordances (tap-away + ✕, same act).
- **Placeholders/dashes on the nine tab routes and the HQ page**: none after ready — every figure
  the audit read was a number; Population keeps its stated "≈ … / estimated from the city's size".
- **EN/KO**: dictionary parity holds; exactly one KO entry contains Latin letters —
  `common.english: "English"`, the switch deliberately naming the language in its own script. No
  missing or empty entries.

## What changed, by root cause

1. **One authority for a destination's word.** `navTabs.ts` gained `navWord(locale, label)` and
   `tabWord(locale, to)`; `NavBar` and every tab screen (`Stats`, `History`, `Rank`, `Routes`,
   `Codex`, `Fleets`, `Profile`, `You`) now read the same shell-dictionary word for their title
   that the rail prints. Nine per-screen title keys and `profile.language` were deleted. This is
   the root of row 3 and the latent row 4 — not a spell-check.
2. **The owner's newest fold law, applied where it was missed.** FLEETS' in-place unfold —
   the one control left in the game that re-flowed what followed it — is now the one `DetailPage`.
   The fleet's three sections, the passage bar and the `Command` hand-off are unchanged; only the
   door is. `tests/onepage.spec.ts`'s mechanism and `tests/consistency.spec.ts`'s page walk both
   cover it.
3. **The label law, enforced by a test.** Every offending control label was shortened to 1–2 plain
   words (rows 5–17, 23); counts moved out of titles into the figure column (row 10); market jargon
   became Up/Down (row 11). `tests/consistency.spec.ts` now fails any summary title over two words.
4. **One word per idea.** History/Giving (row 21), Best day/Most earned (row 18), Merchants/City
   purses (row 19), Supplies/Provisions (row 25), Works in/out (row 26), State/Standing (row 22),
   World money/All money (row 9), and the two-scope refusal sentence (row 20). The one collision
   left is declared with its reason (row 40).
5. **The 44-px floor.** Routes' refresh went 36→44 (row 24); the two remaining 36-px controls were
   declared by test id in the permanent spec instead of being filtered silently (rows 32–33) —
   #426 removed the city faces' Back and the `command-fix` slice made the desk's City view md, so
   the allowlist is now EMPTY and every walked control is 44 px or larger.
6. **Stale specs after the compact rework.** `greatPowers` and `captains.codex` now drive the
   pop-up page a player drives (rows 30–31); `map.townhall` drives "Giving".

## Specs

- **`tests/consistency.spec.ts` — NEW, permanent.** (1) the shell rail equals `NAV_CELLS`
  cell-for-cell, with the Menu's rows equal to its members; (2) every tab screen's title equals its
  rail word (8 parameterised tests); (3) at 390×844 and 1280×800, every route, desk face, Stats
  face, every opened summary page and every fleet page is held to: no document/Sheet/page-root
  scroll, no sideways scroller, the 44-px floor (the allowlist is now EMPTY; rows 32–33 are
  fixed), the placeholder-dash ban (the desk's sparklines included, with `sparkAbsence` proving
  every gap is the served absence), the duplicate-label ban and the ≤2-word summary-title law; (4) the HQ doors
  visible with no scroll and no dead band at 390 and 320; (5) the City rail equality and the
  six-door press/stability proofs as real tests, plus ONE `test.fixme` for the 320-px hall panel's
  inner scroll with its evidence.
- `layout.spec.ts` — the FLEETS proof rewritten from "unfolds under the row, below may move" to
  "opens her page, the row below may not move".
- `wide.layout.spec.ts` — the FLEETS proof rewritten from the fold's three columns to the page's.
- `fleet.supplies.spec.ts` — the row's page door; same supplies assertions.
- `greatPowers.spec.ts`, `captains.codex.spec.ts` — open the Codex page before asserting its faces.
- `map.townhall.spec.ts` — the city giving tab is worded "Giving".
- `nav.geometry.spec.ts`, `cache.once.spec.ts` — re-pointed to #426's one-rail City page: the City
  rail is read under `city-rail`/`nav-bar` (five cells), the Market building opens `city-face-panel`
  in place, and the Hall tile returns to the Town Hall; the old `city-nav` / `city-face-back`
  selectors are gone. (`nav.rails.spec.ts`, #426's own guard, stays as written.)

## Local verification (this machine, 2026-10-31, rebased on #426)

- `npx tsc -b` clean; `npx eslint .` clean (the three edited specs clean too); `git diff --check`
  clean; `npm run build` clean (tsc + vite + world image) on the rebased tree.
- **Pre-rebase record** (against #425's build, before the City slice merged — kept so the before
  state is not lost): batch 1 **26 passed** with one red in the new spec itself (16 dashes inside
  Stats pages — investigated: all SERVED ABSENCES, not placeholders where data exists, so the ban
  measures the compact screens — and a serial-mode skip, removed); batch 2 **61 passed, 2 skipped,
  0 failed**; batch 3 **10 passed, 0 failed**.
- **Post-rebase lean batch** (the coordinator's list, served build on 4305): `nav.rails`,
  `nav.geometry`, `consistency`, `greatPowers`, `captains.codex`, `layout`, `fleet.supplies`,
  `map.townhall`, `city.page`, `onepage` — **49 passed, 1 failed, 1 skipped**. The red was a STALE
  SPEC, not the app: `nav.geometry.spec`'s City-rail test still selected the pre-#426
  `city-nav`/`city-face-back` and found 0 cells; it and `cache.once.spec`'s two stale selectors were
  re-pointed to `city-rail`/`nav-bar` and `city-face-panel` (see Specs). The skip is the declared
  320-hall `test.fixme`.
- **Post-fix rerun**: `nav.geometry` (3 tests), `cache.once`, `nav.rails` — **5 passed, 0 failed**
  in 29.3 s; both rails print **HQ · Fleets · Map · Stats · Menu**, every cell 78×56 on a 57-px
  bar; `cache.once` still reads the Market-building open as `[1, 0]` (kept until its edge).
- The post-rebase consistency walk reports **0 violations at 390×844 and 1280×800**; both HQ proofs
  pass at 390 and 320; the City rail equality passes; the six-door press-stability proof passes at
  both sizes; only the 320-hall law skips. The stale-selector grep (`city-face` without `-panel`,
  `city-face-back`, `city-nav`) returns none.
