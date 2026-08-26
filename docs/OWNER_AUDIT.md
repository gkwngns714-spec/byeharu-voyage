# OWNER AUDIT — every instruction, checked against the code

**2026-08-26.** You said: *"this tells me that what i've said isn't applied to the game. how should
i know what was implemented and not? … Tell me all the things i said, and tell me all the things
that aren't worked."*

`docs/OWNER_REQUESTS.md` was supposed to be that answer and you proved it could not be trusted —
row 48 said BUILT while every city still sold all 243 goods. So this file re-checks **all 48 rows
against the actual code, the actual migrations and the actual data files**, and treats every state
in that ledger as a claim, not a fact.

## The short version

| Verdict | Rows |
|---|---|
| **TRUE** — checked, it is there | **37** |
| **PARTLY TRUE** — most of it is there, a named piece is not | **8** |
| **NOT TRUE** — marked done, is not done | **1** |
| **CANNOT VERIFY** — I could not settle it from the repo | **2** |

**So the ledger is mostly honest.** One row was flat wrong (48, which you found yourself). Eight
overstate slightly. Two rows in the other direction *understate* — 19 and 22 are marked unfinished
and are in fact finished. This is an audit, not a prosecution: the great majority of what you asked
for is really in the game.

**One correction to what I was told before starting this audit:** I was handed "the grid layout of
trade goods was never done — `grep grid MarketScreen.tsx` = 0". That grep was case-sensitive and
missed the helper `goodTileGridClass`. **The grid is real** (row 34 below). I checked it rather than
repeating it, which is the whole point of this file.

**Ground truth used throughout:** production is at **head 0059, 53 of 53 migrations applied**
(`docs/RESUME.md:12`). So anything in migrations 0001–0059 is live in the real game.

---

## 1. Every instruction, one row each

Numbering follows `docs/OWNER_REQUESTS.md` so the two files can be read side by side.

| # | What you said | Claimed | ACTUALLY | The evidence |
|---|---|---|---|---|
| 1 | *"All game must be logged in so that they are safe."* / *"this is a online game, a user info and game progress should always be kept."* | PART DONE — 2 settings left | **PARTLY TRUE** — the code half is done and the ledger's note is stale | `.github/workflows/deploy-pages.yml:112-126` refuses to publish unless both `VITE_SUPABASE_*` secrets are present (`exit 1`, no silent local-only fallback). `src/features/auth/AuthPage.tsx` exists. The ledger's third blocker — "migrations 0025-0029 applied to the live project" — is cleared: prod is at 0059. The other two blockers are **GitHub settings I cannot read from inside the repo**; what would settle it is `gh api repos/:owner/:repo/actions/secrets` and the Pages source setting |
| 2 | *"Where it pays more does not need to be given in buy."* | DONE — verified | **TRUE** | `src/features/command/ArgPickers.tsx:635-638` records the deletion; a repo-wide grep for `trade_routes` / `loadRoutes` finds them only in `src/features/market/` and `src/live/worldStore.ts:422` — nothing in `src/features/command/` fetches or draws it |
| 3 | *"when pressing hire, 12, it unfolds. this is uncomfortable. keep it without unfolding, and let me hire."* | DONE — verified | **TRUE** | `<Collapsible` appears in exactly three places in the whole app — `FleetsScreen.tsx:493`, `MapPanel.tsx:83`, `PortScreen.tsx:795`. **Zero in `src/features/command/`**, so HIRE has no fold |
| 4 | *"Provision also, does not need to be fold/unfoldable."* | DONE — verified | **TRUE** | Same measurement as row 3 |
| 5 | *"and hands? seriously? change it like crew or something."* | DONE — verified | **PARTLY TRUE** — one string still says it | Server side is genuinely proven: migration 0030 slices three functions and its own self-assert refuses to apply unless the word survives in exactly three named non-player places (`0030:301`, `:304`, `:307`, `:313`). **But `src/domain/fleet/statGloss.ts:79` still reads: "Short of the first figure she may not sail, and hands lost at sea slow her"** — that is the explanation a player opens on the crew figure |
| 6 | *"i want to be able to click on buy and sell itself and do trades. when pressed unfold another so that i can choose how much i buy"* | DONE — verified | **TRUE** (the shape). The measured numbers in the note are stale | `ArgPickers.tsx:798-809` — the buy and sell figures are real `onPress` buttons that fire `onTrade('BUY')` / `onTrade('SELL')`; `:806-807` disables a sell cell with "none aboard". The quantity step unfolds under the pressed row at `:681-718`. The note's *"140 price-cell buttons, min height 75.7px"* **CANNOT VERIFY — needs the running app**, and it was measured on a 70-good catalogue that is now 243 goods |
| 7 | *"create a 도감, separate tab, showing all the trade goods, ships, captains that are made in this game. categorize them, make filters"* | DONE — verified | **TRUE** | `src/app/navTabs.ts:96` registers `/compendium` as "Codex". `CompendiumScreen.tsx:71` has four faces — goods, ships, captains, nations — and `:516` builds rarity filter chips from `RARITY_TIERS` |
| 8 | *"i want explain icon next to everything that has long sentences for explanation"* | DONE — verified | **PARTLY TRUE** — real, but "everything" is unprovable | `Explain` is used 58 times across 11 feature files (Command 7, FleetRail 10, Fleets 11, Haggle 4, OrderComposer 5, Preview 4, Ledger 3, SendFleet 3, Market 3, PortFair 5, Port 3). Whether a *long sentence somewhere has no dot* cannot be settled by grep — it needs a screen-by-screen read, which I did not do |
| 9 | *"i want actual time shown on command, and how much left for it to change the prices live"* | DONE — verified | **TRUE** | Migration 0029 adds `clock` to `world.market()` with `next_change_at` (`0029:8`, `:43`, `:113`). Drawn at `CommandScreen.tsx:374` (`<WallClock>`); the countdown that re-asks at zero is `src/components/ui/reaskAtEdge.ts` |
| 10 | *"do the map layer and finish it"* | DONE — verified | **CANNOT VERIFY** — "finish it" has no test that can pass or fail | The chart layer is substantial and real: 23 files in `src/chart/`, and the four map instructions that *can* be checked (rows 21, 31, 32, 39) are all TRUE. But "finished" is your judgement, not a measurement. What would settle it: you saying which map thing is still missing |
| 11 | *"use fable also for better performance"* → *"use different model since fable 5 is unavailable"* | STANDING, AMENDED | **TRUE** as a record | The row quotes both wordings and states the suspension. Whether a given agent dispatch obeys it leaves no trace in the repo, so compliance itself is **CANNOT VERIFY** |
| 12 | *"no spaghetti — separate independant codes, with plans for future … it has to be planned precisely and correctly"* | STANDING | **TRUE** | `docs/NO_SPAGHETTI.md` exists and `tests/duplication.spec.ts` enforces four of its rules mechanically — no hand-written class recipe twice (`:183`), no name owned twice (`:254`, `:285`), and every migration must prove itself in its own transaction (`:333-342`) |
| 13 | *"nope A, lets make it public"* | DONE 2026-08-23 | **TRUE** | Migration 0031 rotates `world_secret` to 128 hex characters generated on the target database and adds a CHECK that permanently refuses the literal that was printed in the repo (`0031:22-54`). The rotation is conditional, so it fires once and leaves an already-rotated database alone |
| 14 | Supabase access token stored on this machine | DATED — expires ~2026-09-23 | **CANNOT VERIFY** | It is a credential on the machine, not in the repo. What would settle it: `supabase projects list` returning without a login error |
| 15 | *"when pressing sail, stop folding the sail. when pressing buy stop folding buy... don't restruct anything"* | DONE — verified | **TRUE** | The cause named in the row — a single derived open slot — is gone. `missingArgs` survives only as the helper `isComplete` calls (`src/domain/order/text.ts:129-136`); `FLAT_VERBS` does not exist anywhere in the tree |
| 16 | *"how many crew to hire, have it + 10, +100, max, make it more friendly"* | DONE — verified | **TRUE** | `OrderComposer.tsx:828` passes `coarse={[10, 100]}`; the chips are `ArgPickers.tsx:1036-1088`, and `:1067` clamps a jump to the ceiling instead of letting it go dead |
| 17 | *"and how many crew? show my ship info regrading crew, how many needs, min amount, max amount etc at the right"* | DONE — verified | **TRUE** | `FleetRail.tsx:386-426` — one `fleetCrew(fleet)` reading, crew aboard over berths at `:426`, the port's idle men listed in the rail's own contract at `:39` |
| 18 | *"15 days of stores is not clear, 4.9kn is what? 56 t free? lying at lisbon is duplicate... make it separate tab for all of them"* | DONE — verified | **TRUE** | `FleetsScreen.tsx:543` is a `TabRow` with three faces — ships, cargo, stores (`:555`, `:586`, `:646`) |
| 19 | *"right now the sail, all the port is alligned by sentence. make it like a cube, and what is yard?"* | PART DONE | **TRUE — the ledger understates this one** | Both halves are done. Tiles: `ArgPickers.tsx:319-323` renders a real CSS grid with the column count computed once. "yard": the served string the row says is still outstanding was fixed by **migration 0033**, which is applied to production — `0033:15-19` names the exact strings including `0021:297`, the REPAIR help the row calls out |
| 20 | *"when pressing a location to sail, dont unfold, instead make the what sail needs bottom by comming out unfoldingly, also, shown in map where i clicked"* | DONE — verified | **TRUE** | The tapped port is ringed on the chart — `src/chart/PortsLayer.tsx:53` (`const selected = selectedCode === port.code`) and `:79` draws the mark. The confirm unfolds after the row containing the tapped tile (`ArgPickers.tsx:278-279`) |
| 21 | *"the map in sail, i should be able to zoom, drag, move."* | DONE — verified | **TRUE** | `SmallChart.tsx:129` mounts `useChartSurface(..., { scroll: 'page-vertical' })` — one shared gesture hook, drag pans and pinch zooms; `src/chart/ViewControls.tsx` rides both surfaces |
| 22 | *"i want you to categorize trade goods, common, uncommon, rare... make appropirate color or sign so that it is unique"* | DONE — verified, **but the row says "NOT YET ON PRODUCTION"** | **TRUE, and that caveat is now stale** | `src/components/ui/rarityTiers.ts:19-24` gives every tier a **glyph and a colour token**, so it survives greyscale. Migration 0051 makes the tier cuts fractions of the world's own mean producer count (`0051:45-48`). **0051 is applied to production** — prod head is 0059 |
| 23 | *"do all the work properly"* | STANDING | **PARTLY TRUE** | This audit is the answer, and the answer is: mostly, not entirely. Section 2 below is the list of what is not done |
| 24 | *"yes build set ratio but let me set it personally - adjust. Save it as preset. Give something like 6 presets"* + *"the ratio must account for number of crews"* | DONE — verified | **TRUE** | Migration `0034:128` sets `provision_preset_max` to 6 as a world_config knob, enforced by a trigger on the table (`0034:84-85`) so a future writer inherits the cap. Sized from crew at fire time (`0034:76`) |
| 25 | *"when pressing sail, stop folding the sail. when pressing buy stop folding buy... don't restruct anything"* | DONE — verified | **TRUE** | Same evidence as row 15 — this is the same instruction, recorded twice |
| 26 | *"what moves the price -> price movement... Why add unnecessary words?"* + *"stores last -> provision"* + *"cargo space or cargo, and 0T/54T - 0%"* | DONE — verified | **TRUE** | `src/lib/format/numbers.ts:97` — `formatOfTotal` prints `4 / 60`, one authority used by Command, FleetRail, Fleets and Compendium. `FleetRail.tsx:411` and `:550-560` say "provision", not endurance or range; "endurance_days" survives only as the wire field name |
| 27 | *"use worktrees from now on"* | STANDING | **TRUE** | This audit ran in one — `.claude/worktrees/agent-ae9db3a8797fa8040`, branch `osn-owner-audit` |
| 28 | *"i told you to not recreate anything when pressing a certain tab... how many times do i have to say this simple thing?"* | DONE — verified | **TRUE** (the fix). The numbers quoted are the OLD defect, not the fix | The mechanism that caused it is deleted — see row 15's evidence. `ArgPickers.tsx:658-663` documents the old shape and its replacement. The *"140 price cells → 0"* figure in the ledger is a measurement of the **bug**, taken before the fix; it reads like proof of the fix and is not |
| 29 | *"what is max 12 in hire? just max is enough"* | DONE — verified | **TRUE** | `ArgPickers.tsx:955-965` — the chip's label is the bare word `max`, with the figure on the rail beside it |
| 30 | *"in provision, full and days, they does not have to be folded"* | DONE — verified | **TRUE** | Same measurement as row 3 — no `<Collapsible>` in `src/features/command/` |
| 31 | *"find button on map, sail, it is not correct. have a symbol instead"* | DONE — verified | **TRUE** | `src/chart/ViewControls.tsx:70-84` — the crosshair `locate` glyph with the full sentence kept as `aria-label` |
| 32 | *"when i press corfu or dubrovnik... the map does not move to that location. make it move - pinpoint"* | DONE — verified | **TRUE** | One camera move, `surface.centreOn` (`useChartSurface.ts:436`), called from `SmallChart.tsx:158`, `MapScreen.tsx:374` and the minimap — no second camera |
| 33 | *"overall, check game itself - every aspect, and move simple words"* | DONE — verified | **PARTLY TRUE** | The sweep is real — 0030 (hands), 0033 (yard), 0020/0021 (verb help cut from 85-242 chars to 33-43). But it is not complete: I found one leftover on my first pass (`statGloss.ts:79`, row 5). "every aspect" cannot be proven by grep |
| 34 | *"make trade goods in blocks as well, not all alligned in sentences - horizontally"* | DONE — verified | **TRUE** — and I checked this one twice because I was told it was false | `src/components/ui/goodTileLayout.ts:11` returns `grid grid-cols-2 items-stretch gap-2 sm:grid-cols-3 xl:grid-cols-4`. **MARKET uses it at `MarketScreen.tsx:518`**, inside `GoodsBlock`, which every band renders through (`:413`). The Codex uses the same helper at `CompendiumScreen.tsx:577`. The earlier "zero grid on MARKET" finding came from a case-sensitive grep that missed `goodTileGridClass` |
| 35 | *"read again on top left of the game is useless. remove it"* | DONE — verified | **TRUE** | No such control exists anywhere; five files record the deletion (`CommandScreen.tsx:362`, `FleetsScreen.tsx:78`, `LedgerScreen.tsx:131`, `CompendiumScreen.tsx:187`, `command/README.md:153`). The screen-specific reads behind it survive (`AppShell.tsx:69`, `:80`) |
| 36 | *"do the work properly. do the work all. do not leave anything behind. double check. always work with rules."* | STANDING | **PARTLY TRUE** | Same as row 23 — this file is the double check, and it found one row wrong and eight partial |
| 37 | *"why are there only 70 trade goods? there should be thousand. real-life trading by regions + 대항해시대 오리진 + 대항해시대"* | IN PROGRESS | **TRUE as stated — 243, not 1,000** | `data/goods.json` holds exactly **243** goods (measured). Migration 0041 carried +173 into the deployed world. **"by regions" is NOT built**: goods carry `id, name, category, valueBand, baseValue, note` and **no region field at all**. The one regional mechanism that exists, `goods.culture_mask`, is used by **6 goods out of 243** — wine (`0003`) and five alcohols (`0041:73-77`), all masked `{islamic,swahili}` |
| 38 | *"each cities max 9 trade goods... Min 4, max 9. Add real islands... JEJU island might have korean gochujang"* | IN PROGRESS | **PARTLY TRUE** | The islands and the rosters landed in 0041, and its self-assert prints *"all % harbours sit in the owner's 4-9 offers-by-size band"* (`0041:5078`). **But "korean gochujang" does not exist** — no good in `data/goods.json` matches `gochu`; Jeju's authored roster is `horses, dried-abalone, dried-fish, seaweed`. The nearest Korean good in the catalogue is Ginseng. The 4-9 band is since superseded by your row-48 rule |
| 39 | *"in map - make a small miniturized map at the corner of the map, that shows where my fleets are in color + symbol"* | DONE — verified | **TRUE** | `src/chart/Minimap.tsx`, drawn at `MapScreen.tsx:420`; fleet marks at 0.8× (`Minimap.tsx:85`); tapping it is `surface.centreOn`, the same camera move (`:66`), so nothing is restructured |
| 40 | *"this game might need OSN system as well as other system built in byeharu... audit and implement it so that later on, combat, exploration, npcs can be added"* | AUDIT DONE · FOUNDATION BUILT · OSN REFUSED | **TRUE as stated** | `docs/PLATFORM.md` is the audit, and it says out loud which questions it refuses and why (`:1-18`). Migration 0035 is the whole of the code — "It adds no combat, no NPC" (`0035:21`), just the event-kind catalogue with a foreign key |
| 41 | *"i don't want the fleet to ever touch land"* | LAW — BUILT AND PROVEN | **TRUE** | `voyage.path_refusal` is created at `0046:357` and every voyage passes through it. It is proven non-vacuously in its own transaction: `0046:608-617` plants a straight Lisbon→Cádiz course and requires the refusal to catch it |
| 42 | *"it should go by sea without the fixed route - but fastest way possible. Also, in map, i should be able to pinpoint anywhere in the ocean to make a fleet move."* | BUILT — 0046/0047 | **TRUE** | The old graph is deleted, not deprecated: `0049:33` drops `voyage.convert_leg_path`, `0049:70` drops `public.legs`, and `data/sea-routes.json` no longer exists on disk |
| 43 | *"sea is a free plane... wind and current will make the speed of ship differ - hence provision risk... encounters - npc will be randomly distrubutely, and then there will be a small tab on the map itself, showing the npc and its distance. i click on it to engage..."* | DESIGN SPEC — authoritative | **PARTLY TRUE** — the record is accurate, but most of what you specified is not built, and you should know which parts | Free plane and pathfinding: **built** (rows 41/42). **Wind: NOT built** — `wind_mult_v0` is pinned at 1.00 (`0001:176`, `0006:357`), so no passage is slow or fast. **NPCs: NOT built** — no actor exists (`0035:21`). **The map panel is not a contacts panel**: `src/features/map/WatersAhead.tsx:9-14` says so itself — it lists the *seas* ahead and their distance because there are no ships to list. **Disasters: the mix is now LIVE** (migration 0059 lit 0055) — but nothing on screen shows it: `watersRows.ts` carries no mix, so the fourth fact 0055 promised is still missing from the panel |
| 44 | (found by the coordinator, not asked for) The world expansion cannot reach production | RESOLVED 2026-08-24 | **TRUE** | `scripts/db/world-guard.mjs:2` — "the applied world must EQUAL `data/*.json`, or the run fails", and it throws (`:131`, `:171`, `:181`). 0041 carried the growth |
| 45 | *"when i want to move ship using sail, i want issue this order to be at the bottom of the location i click on it, unfolding it, but without making a new screen."* | DONE — VERIFIED ON PRODUCTION BY DRIVING IT | **TRUE** (built). The drive is your own | The code is there: `ArgPickers.tsx:278-279` chunks the grid into rows so the confirm lands after the whole row containing the chosen tile. **CANNOT VERIFY the drive — claimed driven by you on 2026-08-25**, which is the strongest evidence available and I am not second-guessing it |
| 46 | *"in map, instead of send gaviota tab, i want to press send fleet, then it will unfold to my fleets, then when i press fleet, it will show how i can set my cargo/provision ratio. then i will press and it will send, without going to another screen"* | DONE — VERIFIED ON PRODUCTION (ratio control NOT driven) | **TRUE** (built), and the ratio control is better tested than the row admits | `src/features/map/SendFleet.tsx`, 622 lines. The ratio fold is at `:508-548` — hero figure, Gauge, two steppers, `Keep N & send`. It composes 0034's presets rather than minting a second ratio (`:44`, `:133-137`). **`tests/map.sendfleet.spec.ts:115` drives it in a real browser** — "a harbour is tappable by its name, and a ratio can be set without sailing" — against PGlite, not production. So: built, browser-tested, not production-driven |
| 47 | *"Gaivota carries 2.9 days of stores, and there is no chandler… - too long. make it very concise. This concise concept will have to be applied to all aspects of the game. Always show in graphics, concisely."* | LAW — BUILT both halves (0050); NOT VERIFIED IN THE RUNNING GAME | **TRUE** for the refusal renderer; the whole-game reach is unprovable | One renderer: `src/components/ui/RefusalNote.tsx:49-72` draws the bar and the two figures; three surfaces draw through it (`OrderQueue.tsx:86`, `PreviewPanel.tsx:75`, `SendFleet.tsx:3`). The server serves the figures — `cmd.figures` is created at `0050:195`, `public.orders.error_figures` at `0050:179` — and the client reads them without parsing prose (`src/lib/rpc/result.ts:122`, `:162`). 0050 is applied to production. **A comment in `RefusalNote.tsx:23` still says "until the serving migration lands" — that comment is stale, 0050 landed** |
| 48 | *"i told you, min 4, max 10 trades goods per city. there should be a purpose to go to a city that is far away to get rare trade goods... capital cities - 10 items, mid sized cities - 4~8, small cities 4, randomly distributed"* | REOPENED 2026-08-26 (was BUILT) | **NOT TRUE** — and I re-derived it independently | `public.port_goods` is built by a **`cross join`** of every port against every good: `0005:272-292` and again `0041:2092`. 0041's own self-assert prints *"% market rows = harbours × goods"* (`0041:5011-5013`), which is the cross join stating itself. A good is hidden only when the culture mask excludes it (`0009:135`, `0019:602`), and **only 6 of 243 goods carry a mask**. So every city offers essentially all 243 goods. What 0058 built is `port_specialties` — price affinity only (`0058:329-341`). **The roster you asked for is already authored in `data/ports.json`**: 224 ports, 1,288 pairs, tier 1 = exactly 10 (35 ports), tier 2 = 4-7 (79), tier 3 = exactly 4 (110). Nothing sells from it |

---

## 2. The things that are NOT done

Read this section alone and you know what is outstanding. Ordered by how much it changes playing
the game.

1. **A city still sells all 243 goods (row 48).** The single biggest one, and the one you found.
   Every port's market is identical in *what* it offers; only the prices differ. The roster you
   specified — 10 / 4-8 / 4 by city size — is authored in `data/ports.json` and used only to set
   price affinity, never to decide what is on the quay. There is no reason to sail far for a rare
   good, which is the exact point you gave in the same breath. Being fixed as migration 0061.

2. **Wind and current do nothing (row 43).** You specified that they change ship speed and that the
   point of that is provision risk. `wind_mult_v0` is pinned at 1.00 (`0001:176`). Every passage
   takes exactly as long as the quoted estimate, so there is no risk to provision against and no
   tension in a long crossing. The seam for it is written down; the slice is not built.

3. **There are no NPCs, and no contacts panel (row 43).** You asked for NPCs distributed by area
   with levels, a panel on the map listing nearby ones and their distance, clicked to engage.
   None of it exists. `WatersAhead.tsx` lists *seas*, not ships, and it says so in its own header.
   An event at sea has no actor — `PLATFORM.md` §3 names the missing table.

4. **What the sea breeds is live on the server but invisible on screen (row 43).** Migration 0059
   lit the ten per-sea encounter mixes on production. The map panel was supposed to gain the mix as
   a fourth fact per row. `src/features/map/watersRows.ts` has no mix in it, so the game now rolls
   different dangers in different waters and never tells you which waters those are.

5. **Goods have no regional identity (row 37).** You asked for real-life trading by regions.
   `data/goods.json` has no region field; the one regional mechanism, `culture_mask`, is used by 6
   goods out of 243 (wine and five alcohols, all "not sold to Islamic and Swahili ports"). Ports
   carry 25 regions, goods carry none.

6. **243 goods, not the thousand you asked for (row 37).** Honestly labelled IN PROGRESS in the
   ledger. Whether 243 is enough is your call, not mine.

7. **"korean gochujang" does not exist (row 38).** You named it as the example of what an island
   should carry. It is not in the catalogue. Jeju carries horses, dried abalone, dried fish and
   seaweed.

8. **One string still calls the crew "hands" (row 5).** `src/domain/fleet/statGloss.ts:79` — the
   explanation you open on the crew figure. Small, but it is the exact word you objected to.

9. **A stale comment claims a migration has not landed (row 47).** `RefusalNote.tsx:23` says the
   serving migration has not landed. It landed as 0050 and is on production. Nothing is broken;
   the next person to read that file will be misled.

10. **Two things I could not settle at all:** whether the GitHub repo secrets and Pages source are
    set (row 1), and whether the Supabase token on this machine is still valid (row 14).

---

## 3. How the ledger drifted

For every row where the claim and the reality disagree, one line on how it came to say what it said.
This is the part that stops it happening again.

| # | How it drifted |
|---|---|
| 48 | **A near-miss was accepted as a hit.** 0058 built a real, well-proven roster — and put it in `port_specialties`, which sets price affinity, not `port_goods`, which sets what is on the quay. The migration's self-assert proved *its own* claim perfectly and never asked the instruction's question: "does a city now sell 4-10 goods?" A self-assert can only be as honest as the claim it is written against |
| 5 | **The sweep was done where it was hard and skipped where it was easy.** The server strings got a whole migration with a positive control. `statGloss.ts` is a plain data table of explain-lines and was never in the sweep's scope |
| 8, 33 | **"Verified" meant "an agent reported a percentage".** Row 8's note says the sweep found the app *"~95% compliant"*. 95% is not verified, it is an estimate, and it was recorded in a column that means done |
| 19 | **Drifted the other way — nobody came back to close it.** The row named one outstanding served string (`0021:297`). Migration 0033 fixed exactly that string on the same day and the row was never updated. It has read PART DONE for three days while being complete |
| 22 | **A deploy blocker was recorded and then outlived by the deploy.** The row correctly said 0051 was not on production on 2026-08-25. Production reached 0059 on 2026-08-26 and no row was re-read against the new head |
| 6, 28 | **A measurement of the defect was filed as proof of the fix.** *"140 price cells before, 0 after"* is a description of the bug. It reads, in the DONE column, like evidence the bug is gone. It also silently went stale when the catalogue grew from 70 goods to 243 |
| 47 | **The code was updated, the comment beside it was not.** 0050 landed; `RefusalNote.tsx:23` still tells the reader it has not |
| 1 | **A blocker list was written once and never re-checked.** Of its three blockers, one is definitively cleared and the other two live outside the repo, where no one thought to look again |
| 38 | **The illustrative example was dropped and nobody noticed.** "JEJU island might have korean gochujang" — the islands were built, the good was not, and no one checked the sentence's second half |

**The pattern, in one line:** every drift here is a row closed against *what an agent built* rather
than against *what you asked for*. Rule 2 of `OWNER_REQUESTS.md` already says that. It was written
down and not obeyed.

---

## 4. What I did NOT check, and why

Saying this plainly is worth more than papering over it.

* **I never ran the game.** No browser, no production login. So every claim that depends on pixels
  or a live server is unverified by me: the *"140 price-cell buttons, min height 75.7px"* of row 6,
  the *"2,112px down"* of row 25, the *"144×52px, 2.27% of the screen"* of row 39, the nav bar's
  *"56px, one row"*. The code that produces them is there; the numbers are not re-derived. Running
  `npx playwright test tests/layout.spec.ts tests/nav.geometry.spec.ts` would settle most of them.
* **I never queried production.** Everything about the live database is inferred from `RESUME.md`'s
  statement that it is at head 0059, 53 of 53 — which I trusted because it says it was verified on
  the target. If that statement is wrong, several TRUE verdicts above weaken to CANNOT VERIFY.
* **Rows 45 and 46 rest on your own drive**, not on mine. I read the code and it matches what you
  described; I could not repeat the drive.
* **I did not read every screen for long sentences without an Explain dot** (row 8) or for surviving
  jargon (row 33). I sampled — and the sample found one leftover, which suggests a full read would
  find a few more.
* **I did not re-run the migration chain.** I read what each migration says and what its self-assert
  refuses to let pass. A migration whose self-assert is vacuous would read as sound to me. `npm run
  db:proof` is the check that would catch that, and CI's apply-proof job is the one that catches it
  against real Postgres.
* **I did not audit `supabase/migrations/`, `scripts/sea-grid.mjs` or `src/features/market/` for
  in-flight changes** — other agents are editing those right now, so anything I say about them is
  true of the tree as it stood at commit `b169ab6`.
