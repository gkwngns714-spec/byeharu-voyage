# 2026-11-13 — S2 + S3: a second ship within reach (0363; owner rows 180, 305, 316; touches row 58)

Design: `docs/SECOND_SHIP.md`, steps S2 and S3. Stacked on S1 (0358, PR #610, branch `yard-plan`).
**Not deployed.** Every figure below is from the LOCAL world image (PGlite), not prod: prod's prices differ by live stock and tax. Nothing was read on prod.

## Why
S1 put the whole errand on the yard's sheet, and the sheet then said the errand out loud: a second Barca was seven goods
from six foreign ports, one of them (flax, Riga) past a single leg of a new company. The owner's rows 180, 305 and 316 ask
for a second ship a new player can reach.

## What changed
- **Server, migration 0363 (`the_barca_needs_no_parts`):** the Barca's two `public.hull_recipe_items` rows are deleted
  (Suit of Sails 1, Anchor & Cable 1) and her `public.hull_recipes.note` is reworded. `data/hulls.json` carries the same
  (the world guard). **No function is re-cut**, no table, knob, switch or job. `cmd.do_build`, `world.building_yard` and
  `world.yard_sources` read the recipe tables: with no row they ask for no part and take none.
  News row: `Barca: no parts needed` · `바르카: 부품 불필요`.
- **Client (S3):**
  - **The goal card on Trade** (`GoalCard.tsx`, `live/useSecondShip.ts`): while the company has ONE ship, the card's
    second line reads **Second ship 1 / 4** · **두 번째 배 1 / 4**. It REPLACES the two tracks line by that one rule; no
    line and no pixel is added (the card stays 44 px). The title's name and Reputation stay on the first line; the
    tracks are one press away (the card still opens Levels) and come back to the card with the second ship. The two
    figures are the yard sheet's own "Ready 1 / 4" (the same read, the same fold).
  - **Plan trip** · **항로 계획** (`PortYard.tsx`, `yardPlan.ts` `planStops`, `features/map/routeSeed.ts`): one row
    under the sheet's totals while something is still to fetch by sea. The press opens the Map's route builder with the
    sellers of what is short kept as stops, nearest first, and this quay last. Nothing is sent: the server judges every
    leg there as it does for a hand-built route, and Final is still her press.
  - Words through `dict/yard.ts`, EN and KO: `planTrip`, `stops`, `secondShip`.

## Measured: the first second ship of a new company (proof 65, local world, storms off)
Both errands were PLAYED through the real commands (`PROVISION`, `SAIL`, `BUY`, `STORE`, `MAKE`, `BUILD`, `HIRE`), every
good bought at its own port, nothing placed. "Before" is the same world with the two rows put back for one company.

| | Before 0363 | After 0363 | Saved |
|---|---|---|---|
| Goods to fetch | 7 (flax, hemp, iron for the parts) | 4 (timber, nails, cordage, tar) | 3 |
| Foreign ports | 6 (Naples, Funchal, La Rochelle, Portsmouth, Riga, Bergen) | 4 (Funchal, La Rochelle, Portsmouth, Bergen) | 2 |
| Voyages | 2 (Naples, Funchal, home; the northern loop with Riga) | 2 (Funchal and back; the northern loop) | |
| Miles | 8,072 nm | 4,283 nm | 3,789 nm |
| Real minutes at sea | 34.3 | 18.5 | 15.7 |
| Coin, purse 40,000 → | 20,177 (19,823 spent) | 21,575 (18,425 spent) | 1,398 |
| of it: goods | 4,006 | 2,620 | 1,386 |
| of it: the yard's labour | 15,000 | 15,000 | 0 |
| of it: crew of 8 | 800 | 800 | 0 |
| of it: provisions and port calls | 17 | 5 | 12 |

- The design guessed about 45 → 25 minutes and 23,900 → 21,000 coin. Measured: 34 → 18.5 minutes at sea and
  19,823 → 18,425 coin. The design's "port calls ~4,000 unverified" is not there in the local world (5 coin).
- The time is sea time only: what she does in port is her own.
- As one tour (the order **Plan trip** hands the Map): Lisbon, Funchal, La Rochelle, Portsmouth, Bergen, Lisbon is
  505 + 1,130 + 417 + 674 + 1,517 = 4,243 nm, every leg under a new company's 1,700.
- It is still an errand: 46 % of her purse, two voyages, four foreign ports, one leg of 1,517 nm.

## What it does to players who already hold something
0363 writes to no player's row (not `player_items`, `player_storage`, a hold or a purse). Proven on probes:
- **A part she keeps stays hers.** A Barca's build no longer takes it (self-assert (c): both parts still there after the
  build). It still goes into a Caravela latina or a Nau (self-assert (d): the latina's refusal counts "Suit of Sails
  (1 of 2)"), and it can still be fitted to a ship (`FIT`, proof 65 `SECOND_SHIP_KEEPS`).
- **Flax, hemp and iron she bought stay hers,** in her hold or her storage. They still make the same parts (`MAKE`) and
  still sell (proof 65).
- **Hull goods in storage count as before.** A company midway through the old errand can build at once.
- Nobody is refunded and nobody loses: a company that already made both parts spent about 1,400 coin and 15 minutes more
  than a company starting today, and keeps two parts worth fitting.
- How many companies on prod hold what: `scripts/ops/harness/second-ship/holders.sql`, to be run before and after the
  deploy. In the local image: 2 companies keep 3 Suits of Sails.

## Row 58 ("Building ships will require not only some of the trading goods, but some items")
Row 58 is closed (built and live, 0068 and 0072). It is the rule this change bends, for one hull:
- Parts stay a rule of the yard. The Caravela latina (4 kinds of part), the Nau (5) and the 11 famous ships keep every
  row (asserted by the migration and by proof 65); every part is still made at a workshop and still fitted to a ship.
- Only the hull a house builds FIRST asks for none, as 89 of the 103 hulls already did.
- It is done as the design ordered: in its own migration, measured before and after, with a forward rollback written
  and played. It is "decided by default": the owner may reverse it.

## Functions re-cut, and the other open migrations
None re-cut. Checked against `origin/captain-skills` (0355), `origin/level-up` (0356), `origin/live-rounds` (0357),
`origin/yard-plan` (0358, the base) and `origin/auto-route` (0360): none touches `hull_recipe_items`, `hull_recipes`,
`data/hulls.json`, `cmd.do_build` or the yard's reads. Their self-asserts commission Barcas with
`public.commission_ship`, which reads no recipe. Client files shared with them: `scripts/ops/harness/README.md` only
(one line each). `MapScreen.tsx` and `useRouteBuilder.ts` are not touched by `auto-route`.

## What moved in S1's proofs and specs, and why
The Barca was S1's example of a hull with parts. She has none now, so:
- **Proof 61** puts her two rows back as its first statement (rolled back with the proof): it proves the plan of a hull
  WITH parts. The errand as it is played today is proof 65.
- **`tests/yard.plan.spec.ts`** runs on a copy of the shipped world with her two rows back
  (`tests/barcaParts.fixture.ts`). The shipped Barca is `tests/second.ship.spec.ts`.
- **`tests/yard.sources.spec.ts`** reads the fitting's line on the Caravela latina's sheet.
- **`tests/rpc.yardSources.spec.ts`** takes the Caravela latina as the hull with parts and asserts the Barca has none.
- **`tests/goal.card.spec.ts`**: a fresh company reads "Second ship 0 / 4" on the second line.

## Proven locally
- The migration on the cached chain (339 files, 338 restored): self-assert in 158 ms (catalog 12 ms, the doors 125 ms),
  budget 20 s. World guard green with the new `data/hulls.json`.
- Proof 65, 4 of 4 markers, 0.8 s; proof 61, 7 of 7.
- The check files and the rollback draft on the local world (`before.sql` and `after.sql` without their head column,
  which PGlite does not have).
- `tsc`, `eslint`, `vite build`; the specs listed in the PR.

## Not proven
- Nothing on prod: no price, no count of holders, no time. The pre-image the migration refuses without (the two rows and
  the old note) was not read on prod: `before.sql` reads it.
- The disposable-Supabase leg and the full suite: CI.
- The far seas: S4 below.

## PROD CHECKS (read-only, one statement a file, `npx --yes supabase@2.120.0 db query --linked -f <file>`)
In `scripts/ops/harness/second-ship/`. 0358 (PR #610) deploys first.
Before the deploy:
1. `before.sql`: head is the migration before 0363; `yard_plan_applied` true; `barca_parts` the two rows; `barca_note`
   the "Two fittings" sentence; `hulls_with_a_part` 14; `update_rows` 0.
2. `holders.sql`: keep the answer (who holds parts, part goods and hull goods).
3. `window.sql`: keep the answer (hulls laid down so far; companies with one ship and with two or more).

After the deploy:
1. `after.sql`: head 20260818000363; `barca_parts` []; the new note; `hulls_with_a_part` 13; `carlat_parts` 4;
   `nau_parts` 5; `sheet_parts` [] and `sheet_goods` 4 with a seller each; `update_rows` 1.
2. `holders.sql` again: no figure lower than before unless a player spent it.
3. 30 minutes later, `window.sql` again: the window's builds by class.

Rollback is forward: `rollback-0363.sql` is the draft (two rows and the note back; `data/hulls.json` with it).

## S4: Sakai and Karachi have no build yard (reported, not built)
The design lists it as its own design, after S2. It is not trivial data:
- A yard is a `port_buildings` row, and a new yard in a capital changes where every company of that country builds.
- From the four Asian capitals the Barca's own goods are out of reach (nails 10,500+ nm, tar 11,300+ nm), and their own
  small hulls also take tar. A yard alone would not let them build; the recipes must be regional, as the Indian hulls'
  already are. That is a recipe change for several hulls: a rule of play, measured in its own window.
- Istanbul's nearest sources are past a single leg.
Nothing of S4 is in this PR.

## Decided by default
- **The goal card's second line is replaced, not shared.** "Trading 1/2 · Exploration 1/2" and "Second ship 1 / 4" do
  not fit one line at 320 px in English, and Trade has no pixel to spare for a third line.
- **Which yard the card counts.** The game has no home port. The card reads the yard of the city a fleet of hers lies
  in; it keeps counting the yard it last counted while she is at sea or in a city with no yard; a yard she visits
  takes over only when it holds MORE of her lines. The last yard is remembered in the browser, per company. On a new
  browser, at sea, the card shows the tracks until she next lies at a yard.
- **Which hull the card counts:** the cheapest hull that yard lays down for her now (at Lisbon, the Barca).
- **The card's press still opens Levels.** It is one button; the yard is on Port > Build.
- **Plan trip orders the stops by the served miles from the yard, nearest first, then home.** She may undo any of them.
  It is offered only while the sheet's button is Build, off (something is still to fetch) and a fleet of hers lies here.
- **"Add a ship" on the Fleets page** (the third item of S3 in the design) is not built: the brief named the goal card
  and the Plan trip press.
- **The number is 0363** as briefed (0355 to 0362 are held by open branches). It deploys after 0358.
- **No refund** for parts already made: they keep their use.
- **The note** now reads "A coaster. A stack of deal boards, tar, cordage and nails - the hull a house builds first."
