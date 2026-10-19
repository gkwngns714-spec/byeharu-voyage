# Owner instruction audit: 2026-10-18 ~13:55 UTC

**Trigger:** the owner, 13:31 UTC: *"and where is the flag? i mean i told many things, wtf? you leaving out things that i say?"*

**Sources:**
- Every owner turn in the coordinator transcript `b98cedb0…jsonl` (2026-10-16 11:25 → 2026-10-18 13:31): 60 distinct typed turns plus 20 queued mid-work messages, de-duplicated.
- `docs/OWNER_REQUESTS.md` (origin/main `440dfb8`), `docs/WORK_QUEUE.md` (untracked), `docs/RESUME.md`.
- Prod read-only checks, all inside `begin transaction read only`, catalog and table reads only:
  - prod head **0181**, with no 0182;
  - `world_config`;
  - `pg_proc` callers;
  - `cron.job_run_details`;
  - `standing_route_laps`.

**Biggest structural finding:** `OWNER_REQUESTS.md` stopped being the ledger. It has **no row** for most of the 2026-10-17/18 instructions:
- `native`;
- the losing routes;
- the CI law;
- shells;
- deleting the companies;
- the `!` steps;
- fable;
- the map blinks;
- the rejected sinks;
- auto-fight;
- the waiting-merchant re-plan.

Rows 138–140 still say "NOT merged, NOT on prod" although 0172, 0173 and the flags are live. Instructions held only in chat and in an untracked queue are how things get left out. That is exactly the failure the file's own preamble describes.

## Open: NOT DONE / PARTIAL

| # | Owner's words | Status | Evidence | What is missing |
|---|---|---|---|---|
| A1 | *"i see routes and some routes such as Carrera Guayaquil does not earn money"* · *"redesign the routes that are like this, and also that gives negative cash"* (10-17 12:13/12:18) · *"why is there a route that has no profit? this is design defect"* (10-18 13:25) | **NOT DONE** | 0142, 0150, 0180 (lap fix) and 0181 (wait in port) are live. Prod, last 2 h, NPC laps: **1,116 of 2,017 (55.3 %) are net ≤ 0**, 1,110 negative, 625 bought nothing; 281 routes `laid_up`. **Comptoir Chastellain: laps 161–168 (10:11–13:27 UTC) are all net −15/−16**, mostly sold 0 / bought 0. Six of those eight laps closed after 0181 went live. | The owner's design fix: every route is built from a paying trade, and a merchant switches when it stops paying. It sits in worktree `bv-redesign` (`osn-merchant-redesign`), uncommitted, touching only gear files so far. Nothing is on prod. |
| A2 | *"no need to hand in surplus... wtf. no they don't need to build ships … why give 157,500 ducats? hull skills? wtf? no need"* (10-18 13:25) | **NOT DONE** | Still live on prod: `npc_give_above_ceiling` is called by `npc_tend_houses`; `npc_build_for` is called by `npc_tend_route`; `world_config.npc_purse_ceiling = 3`. | A migration that removes sinks (a) and (d) and keeps 0180's purchase-price fix. Nothing is committed. It is bundled behind A1 in the same uncommitted worktree. |
| A3 | *"yes famous gear can be made, but later"* (10-18 13:25) | **NOT DONE** | Same worktree, `data/gear.generated.json` and `scripts/build-gear.mjs` modified, uncommitted. | Famous gear unobtainable until the owner sets its sources. |
| A4 | *"if they wait when there is no profitable route, how long would they wait?"* · *"why once an hour? can it be faster?"* (10-18 13:20) | **NOT DONE** | 0182 `a_waiting_merchant_is_asked_in_turn.sql` is staged in `bv-replan`, not pushed, not on prod. Reconcile on prod: **12.2 s (11:07) → 57.4 s (12:07) → 62.0 s (13:07)**, over its 60 s budget since 0181. | Deploy 0182 (re-plan about every 10 min in small batches). Until then, waiting merchants wait up to an hour and the hourly job is over budget. |
| A5 | *"where is the flag?"* (10-18 13:31) · *"beside the name show flag that are influenced by, when pressing a ship or city, also show flag"* (10-17 23:56, given twice) | **PARTIAL** | #198 is live (23 flags, trays, panels). But `src/chart/labels.ts:482-485` draws a city's flag **only when `showQuietPorts`**, so the world view shows no flags. `public/flags/FRA.svg` is the *Pavillon royal*: white with a fleur-de-lis `<pattern>`, which reads blank at label size. | Flags at every zoom where a name is drawn, and a France flag that reads. `bv-flags2` (`osn-flags-2`) has **0 changes**. |
| A6 | *"when moving map, it isn't smooth"* (10-17 11:48) · *"why is it blinking? when moving map?"* · *"you should move faster"* · *"move the map faster, it will show blink, way faster"* · *"when i move map, there are black blinks that is too disturbing. wtf?"* (10-18 13:30) | **PARTIAL** | #153 (smooth pan, 143 fps) and #197 (blink, 124 → 0 frames) are live. The owner still sees black blinks on the live site after both. The DPR 2 cause is not fixed. | The DPR 2 / fast-pan black blink. `bv-dpr` (`osn-map-dpr2`) has **0 changes**. #197 was measured on a DPR 1 harness and called "FIXED", which the owner's screen contradicts. |
| A7 | *"yes lets do a automatic fight, so that range and accuracy is an important factor … yes shoals and damage too"* (10-18 13:28) | **NOT DONE** | `combat_bite=false` and `armour_turns_pct=0` on prod. `bv-fight` (`osn-auto-fight`) has **0 changes**. | All of it: auto-resolved rounds with range and accuracy, shoals and their damage. Also the zones and pirate-NPC ideas the owner asked for (*"give me an idea about zones, pirate npcs and all"*). Check that they were actually delivered in chat. |
| A8 | *"the ! things that i need to do, i want you to do it by yourself, all you need to do is to put it on the typing"* (10-17 14:09) · *"give me ! step"* (14:14) | **NOT DONE** | The coordinator kept writing "Waiting on you: the `!` allow command" every 10 min from 10-17 13:04 to 10-18 07:22. At 10-17 23:35 it asked *"Shall I put the allow command in your typing box?"* instead of doing it. | It was never put in the typing box. The result is A9. |
| A9 | *"unknown compnaies - hard delete them for now"* · *"delete all"* (10-17 12:33/12:37) · *"deletnig 16 companies, tell me what i need to do, and lets delete them"* (10-18 13:25) | **REVERSED-BY-OWNER, after ~25 h of our non-delivery** | The owner, 10-18 13:28: *"since you are not giving me ! command, leave the 16 companies"*. Prod: 17 houses with logins. | Nothing to build now. But the reversal was forced by A8, not chosen. Worktree `bv-strike` (0 changes) is still standing, against the reversal. The promised fix is unverified: the old migration self-checks were to clean up the test houses they recreate on every rebuild. |
| A10 | *"keep working, don't stop, and when you need permission from me, choose appropriately if i don't answer in 2 min - appropriate means choose yes always"* (10-17 12:41) · *"do not ask me for permission to continue"* (12:36) | **PARTIAL** | Many items were "decided by default", which is correct. But the 10-min reports carried a standing **"Waiting on you:"** block for ~18 h: the combat questions, the deletion, money growth (b)/(c), "your call" on S18 and tuition. | Those should have been defaulted to yes after 2 min, like the rest. |
| A11 | *"and i told you to use fable on things that are more efficient"* (10-17 12:21) · *"use fable appropritely"* (12:38) | **PARTIAL** | Agent dispatches in this transcript: **13 with `model: fable`, 57 with `model: opus`**. The memory rule `use-fable-for-agents` says Fable on every Agent call. | Fable as the default for implementers and fixers. Opus only where justified. |
| A12 | *"remove shells that have been finished"* · *"there is like 11 shells"* (10-17 01:46) · *"close all shell that aren't working"* · *"add it to your rule to close shell commands that are useless and finished always"* (14:10) · *"old work tree? … if not delete them"* (12:33) | **PARTIAL** | No open PRs, and old PRs #59/#84 were closed. Still standing: **7 worktrees**, 5 of them with **0 changes** (`bv-dpr`, `bv-fight`, `bv-flags2`, `bv-strike`, `bv-terminal`), and `bv-strike` belongs to a reversed task. **22 local branches** are already merged into origin/main and not deleted. | Remove `bv-strike` and every idle worktree, and delete the merged branches. Close finished shells every cycle (the rule exists in memory, but the clone shows it is not applied). |
| A13 | *"so fix what needs fix, make everything clean, then merge and deploy"* (10-16 14:00) · *"keep everything going, making it clean"* · *"make it clean or you will face consequences"* (10-17) | **PARTIAL** | Code side: deploys go through `~/bin/bv-deploy.sh`, and main CI is green (11:35 run). Not clean: `OWNER_REQUESTS.md` is stale and missing rows (see top). `WORK_QUEUE.md` still lists finished items as "agent building" (items 1–4, 6) beside their DONE rows, plus two contradictory rows for the 16 companies. 0180 was merged after a failed push (a recorded mistake). | One honest ledger, updated as each instruction lands, and a queue without stale rows. |
| A14 | *"i want you to delete port tab, and focus on command tab … stock trading screen … make the command page stylish - modern - sophisticated yet concise simple"* (10-17 12:45) | **PARTIAL (by its own ledger row)** | D1–D8 are live: 0170, 0171, 0175, 0176, 0177 plus client D3, D5 and D8. PORT is deleted. `OWNER_REQUESTS` row 137 says "open until driven on the live site". `bv-terminal` (`osn-desk-terminal`, 0 changes) suggests the styling work is unfinished. | Drive it on the live site and settle the "stylish" half. Two numbers on the desk are still marked "provisional" (0171, 0176, 0177). |
| A15 | *"do a thorough research … 대항해시대 오리진 … skills and eve-style skill sets, and make them properly. so are captains … apply it to the game"* (10-17 12:35) | **PARTIAL** | Research files and the design (#154) are merged. K0–K10 and S13–S18 are live. `skills_bite=true` and `crew_bite=true` on prod. **`combat_bite=false`, `gear_wear_bite=false`, `levels_bite=false`.** | The combat part (= A7) plus gear wear and levels are still dark. The 15 design DEFAULTs were decided by default and never shown to the owner as a list. |
| A16 | *"any ideas on how to make the economy circulative?"* · *"make the economy circulate"* (10-17 23:48/23:50) | **PARTIAL** | 0172 and 0174 are live: cities +4.4 M/h, 0 refusals. The sinks chosen for it (0180 a + d) were then **rejected** (A2). The owner said money growth: *"leave it"*. | After A2 is removed, circulation has to come from A1 (routes that pay), not from hand-overs. |

## Done or answered

| # | Owner's words | Status | Evidence |
|---|---|---|---|
| B1 | *"the distance ratio should make kimchi higher … korea - london … like 50k each … research 대항해시대 오리진 … trading prices and apply"* (10-17 23:48) | DONE-LIVE | 0173 is on prod; `max(port_goods.haul)=600`. Research: `docs/research/UWO_TRADE_PRICES.md`. The queue's prod reading: London kimchi bid 50,315. |
| B2 | *"Cities are powerful … millions of gold as a start. Especially capitals. Provide capitals to capital cities"* | DONE-LIVE | 0172 on prod (644 M granted; capitals 10 M, others 2 M); `city_treasury_enabled=true`. |
| B3 | *"city economy should open, capital … you calculate what is the best capital city"* (10-17 10:49) | DONE-LIVE | City treasury on; 0140 (Mughal capital → Karachi) on prod. |
| B4 | *"change the light zone dark zone area movement by 2 times slower"* (10-17 10:53) | DONE-LIVE | #146: `GAME_CLOCK_RATE = TIME_COMPRESSION / 8` (`src/lib/format/time.ts:186`). |
| B5 | *"remove native"* (10-17 12:06) | DONE-LIVE | 0141 on prod; no `native` tag in `src/` on main. |
| B6 | *"like uncharted island … influence of major countries … investing and spending money"* · *"country region influences and all"* · *"for all merchant ships, i would be able to press and see flag of their nation too. you will have to distribute them if one side is too over populated"* | DONE-LIVE (owner DEFAULTs unreviewed) | 0143–0148 on prod; `influence_enabled=true`; the merchant tray flag (#198); I3 rebalance. 14 DEFAULTs in `docs/INFLUENCE.md` were decided by default. |
| B7 | *"the CI fix … should never start from scratch … make law"* · *"CI test only … where we made something new"* · *"always make ci fast. save everything when you checked"* (10-17) | DONE-LIVE | #144 (scoped), #149 (PR guard), #170 (main snapshot, nightly from-zero), #215 (db shard 78 → 4 min). Recent PR proofs take 12–14 min. Memory law `ci-never-from-scratch-law`. |
| B8 | *"10-minute status … remind me every 10 min of the current work - and what is left"* (10-17 12:36) | DONE | 150 cron prompts from 10-17 12:41 to 10-18 13:33, no gap over 20 min. Their content broke A10. |
| B9 | *"docks - i told you to leave it"* · *"i will come up with docks"* | DONE (respected) | Docks untouched; the draft gate was removed in 0139. |
| B10 | *"mughal capital work … why from scratch?"* · *"finish works that are meager and avoid doing things from scratch"* | DONE-LIVE | 0140 on prod. |
| B11 | *"old pr … if they are old and are useless, remove them"* | DONE | `gh pr list` shows 0 open. |
| B12 | *"when session is over, you will still have to continue … changing to latest other model(s)"* | Cannot verify from the repo | `WORK_QUEUE.md` exists. The 10-min cron is session-scoped. |
| B13 | Questions (native meaning, number of countries, number of skills, "17 players", profit system, reconciliation time, accuracy/range, shoals, battle board) | Answered in chat | The owner recorded: no battle board; money growth "leave it"; combat waits on pirates. |
