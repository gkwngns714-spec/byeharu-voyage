# RESUME — NPC traders (branch `osn-npc-traders`)

Stopped by the owner 2026-10-08 17:12 KST. This file is the resume anchor; delete it in the commit that opens the PR.

## State

- Branch head before this file: `967c726`, 12 commits on top of main `b48b960`. Plan = `docs/NPC_TRADERS.md`.
- Built: 0096-0099, proof 12, client slices 4 (chart + read-only merchant sheet) and 5 (PORT list), words, docs, screenshots in `docs/npc-traders/`. Dark behind `npc_traders_enabled`.
- The implementer reported every local gate green (db:apply, db:proof, db:check-versions, lint, typecheck, build, Playwright merchant + layout + flicker + route). Re-run them before the PR — that was its report, not re-verified by the main session.
- Fable adversarial review DONE (findings below). The fix step had only read code; **no fix is applied**. No PR opened. Nothing deployed; prod head is still 0095.

## Next steps, in order

1. Fix every finding below (blocker + majors mandatory; minors when correct). 0097 is unreleased, so edit it in place; regenerate 0098 with `scripts/build-npc-0098.mjs` if 0097 changes what it measures.
2. Fix the owner-visible problems found in the screenshots, which the reviewers missed:
   - map looks sparse: only 2 merchants in the whole Iberia view at 1280 — the sea must look busy;
   - at 1280 the merchant sheet covers the top-right `Regions` button;
   - at 390 an empty outlined box frames the sheet's drag handle;
   - `Last lap` lines read "a sale of the cargo passed over at Lisbon" — sounds like it was skipped; reword;
   - the earnings screenshot shows 0 / "no lap yet" — re-shoot with a merchant that has real earnings/day.
3. Audit two test edits the implementer made to get green: `a038f69` (proof 11 changed for interval pacing) and `feeec66` (merchant spec now taps *any* merchant in view). Confirm neither weakens what the test proves.
4. All gates again, new screenshots, push, open a DRAFT PR. Do not merge or deploy without the owner.

## Fable review findings (verbatim)

### [blocker] `supabase/migrations/20260818000097_a_company_the_world_keeps.sql:656`

A merchant route paused `laid_up` can never be resumed or started by `npc_tend`, so the self-heal the plan promises (§4.5) does not exist. The upkeep re-plans an eligible laid-up route with `npc_plan(p_now, sr.id)`, and the planner's successful save (`cmd.standing_route_save_for`, 0096:827) sets `updated_at = now()`; the very next test `if sr.paused_reason = 'laid_up' and sr.updated_at >= p_now - v_laid then continue` is then always true (p_now = now() in production), so the route is skipped, never resumed, and the `resumed`/`started` branches are unreachable for this reason. Verified on the applied chain in PGlite: switch on, a route with 4 BUY lines laid up 7 h ago, three `npc_tend(now())` passes (ageing the pause 7 h between each) -> still `laid_up`, `updated_at` age 0 s after every pass, fleet DOCKED, `resumed=0 started=0`. Every path that lays a route up is affected: 'No cargo pays on any leg' at the switch minute (an unstarted route is never started), the third consecutive clear, the refound cap's alternate-loop re-cut (0097:735), and `npc_plan`'s own laid_up. 0097's self-assert only tests the `error` resume (which does not hit this branch), and proof 12 tolerates fleets laid up for want of cargo, so the net lets it through. Over days every losing or briefly unprofitable merchant accumulates in `laid_up` and stays there for ever.

**Fix:** Decide 'the plan laid her up THIS call' from the plan's own receipt, not from `updated_at`: `if sr.paused_reason = 'laid_up' and coalesce((v_res->>'laid_up')::int, 0) > 0 then continue; end if;` (or capture `v_was := sr.updated_at` before the plan and compare against that). Then the existing `sr.fleet_id is null -> assign` / `paused -> pause_for(false)` branches run. Add to 0097's self-assert: a probe route laid up 7 h ago on a paying market is resumed by one `npc_tend` (positive control: laid up on a market where nothing pays stays laid up), and make proof 12 fail on any fleet still `laid_up` after a later reconcile pass once its leg pays again.

### [major] `src/chart/liveWorld.ts:95`

The open merchant's hull is placed from her CARD's voyage (position included), not from the traffic row. The card is re-asked on the beat and lands after `readAt`, so on every 3-s beat the selected hull is first drawn from the previous card (≈one beat stale) and then, when the new card lands, leaps forward. Measured on the 4292 preview at 390px with a rAF sampler (tests probe, since deleted): the selected hull stepped backwards −25.2 px, −20.0 px, −6.5 px on three successive beats (t=1707/4618/7549 ms) each followed ~70 ms later by a +24.6/+20.9/+20.9 px leap; the unselected control hull never moved backwards. On the cloud, the card's round trip is longer than PGlite's, so the backward hop lasts longer. This is exactly the 'teleporting marker' drift.ts was written to remove, reintroduced for the one hull the player is looking at (MapScreen.tsx:145 hands the card's `voyage` to `mapTrafficOf`).

**Fix:** Never let the card move a hull. In `mapTrafficOf` keep the traffic row's voyage (position, legFrac, segNm, eta, nm figures) and take ONLY the card's full `course` for the track: find the traffic row's 2-point segment inside the card course (or have `sea_traffic` serve the un-rebased `seg_index` alongside the re-based one) and build the track with `buildTrack(fullCourse, at, segIndexInFull)`; `placeSailing` then places her from the same row as every other merchant. Re-run the sampler: zero backward steps on the selected hull.

### [major] `src/live/worldStore.ts:817`

Stale traffic is painted on return to MAP, then every hull teleports and snaps back. `wantTraffic`'s release only decrements the counter; the last `traffic` reading is kept and MapScreen.tsx:91 draws it as soon as the chart mounts. Measured (in-app nav Map → Fleets, 20 s, → Map): all 32 hulls were first painted with transforms identical to the ones from before leaving, stayed there for ~2.3 s, then leapt 40–195 px when the mount-time read landed (t≈2292–2421 ms), and ~0.5 s later nearly every hull stepped BACK 5–20 px (t=2960 ms) — because the mount-time read lands after the beat's `readAt`, so drift extrapolates from an older instant than the served position and overshoots until the next beat corrects it. A fresh page load showed no backward steps, so this is specific to the mount-time read. On production the away time can be minutes, so the leap is arbitrary.

**Fix:** (1) Clear the reading when the last wanter releases (`set({ traffic: null })` at count 0) so a remounted MAP/PORT shows no merchants until a fresh reading, and/or ignore a reading whose `at` predates `readAt`. (2) Do not issue a lone read outside the beat: let the first reading ride the next `refresh()` (≤3 s) so `readAt` and the traffic position come from the same beat; or carry the traffic's own served `at` into the Drift used for `placeSailing` of merchants. Verify with the same sampler: first frame after return has no hulls or current hulls, no backward step at the next beat.

### [major] `src/live/MerchantSheet.tsx:110`

The headline figure the owner asked for ('how much it is earning per day') reads as a large loss for the first hours of every merchant fleet (and after every refound). The committed screenshot docs/npc-traders/merchant-sheet-full-390.png shows 'So far today −116,690 🪙 / A lap ≈ −116,690 🪙 / Last laps −116,690 🪙 / 1 lap' for Carreira do Brasil, whose cargo is sold on the NEXT lap for +139,165 — the lap closes at arrival home, before the home sale, so the cost lands on lap N and the revenue on lap N+1 (`public.route_earnings` 0097:185, lap close in the executor). The implementer recorded this instead of fixing it; it is the sign/window problem the review was asked to hunt, and '≈ −116,690 a lap' from a single partial lap is not an estimate, it is wrong.

**Fix:** Fix it in the one authority, not on the client: close a lap AFTER the home stop's SELL lines have executed (the executor's stop-0 orders), or attribute a leg's purchase to the lap in which it is sold. Until then the sheet must not present a single closed lap as 'A lap ≈': with `laps_done < 2` print 'first lap under way' for the lap row and label the day row by its actual window ('since 13:05') rather than 'So far today', and the `laps_recent` list should carry the newest-first order explicitly (line 128 joins them with ' · ' and readers take left-to-right as chronological).

### [major] `supabase/migrations/20260818000097_a_company_the_world_keeps.sql:786`

Flag-off is not inert: `npc_compact` has no `npc_traders_on()` gate and `tick_reconcile` (hunk at 0097:901-905) calls it every hour from the moment 0098 lands. Six hours after deploy, while `npc_traders_enabled` is still false, the compactor DELETEs the 23 seeded companies' FOUNDING / OFFICER_WAGE / TUITION ledger rows and replaces them with one `NPC_CARRIED` row each, exercising the `forbid_mutation` DELETE exemption on production's append-only ledger before the owner has flipped anything. Verified in PGlite on the applied chain with the switch OFF: `npc_compact(now() + 7h)` returned `ledger_rolled: 191` and the merchant ledger went from 191 rows to 23 carried rows. The books still reconcile (Σ delta is kept), so the damage is to the dark contract, not the purse, but §9 says 'Off: nothing moves' and the 0097 'DARK' assert only checks plan/tend, never compact.

**Fix:** Gate the compactor like the other two: `if not public.npc_traders_on() then return jsonb_build_object('enabled', false); end if;` at the top of `npc_compact` (residual rows after a switch-off are bounded by the window, or allow one pass when merchant rows newer than the cut exist). Extend the 0097 'DARK' assert: `npc_compact(now() + interval '7 hours')` while off must roll nothing and leave the founding ledger rows intact.

### [minor] `src/chart/hitTest.ts:95`

Merchants held in one port are all drawn at the single roadstead point (liveWorld.ts:100), stacked bow-north and indistinguishable; the strict `<` here always returns the first in roster order, so the others can never be opened from the map. At wide zooms the 13-px hull covers the port's dot entirely, and the merchant keeps the full 38-px reach while a dot answers only within 22 px, so a tap on a dot city with a merchant lying there opens that merchant rather than the city. (At the opening zoom this is fine: measured 12.7 px between Lisbon's mark and the anchored hull, and taps within ±6 px of the mark opened the port/own tray every time.)

**Fix:** Fan docked merchants round the roadstead with small deterministic offsets by index (or draw one hull with a count and let PORT's 'Merchants in port' list them), and give an anchored merchant the dot's reach when her berth's mark is within `dotHitRadius`, so the harbour wins a tap on its own dot.

### [minor] `src/live/MerchantSheet.tsx:148`

'refounded once, last 14:32' prints `formatClock` — a time of day with no date — for an event that may be days or weeks old, so the Fortune row implies a refound happened today.

**Fix:** Use the relative form the rest of the sheet uses (`formatRealShort(nowMs − at)` ago) or a dated form; a clock time is only honest within the current day.

### [minor] `supabase/migrations/20260818000099_the_sea_shows_who_else_sails.sql:282`

`world.npc_fleet_card` serves `voyage_view(v.id, true)`, whose object carries the voyage `id` — the very 'callable handle' 0099's own header and §7.1 say must not be served (`voyage.position(uuid)` is executable by `authenticated`, 0088:184). The card's forbidden-key assert lists `voyage_id` but not `id`, so it passes. Verified: as `authenticated`, `world.npc_fleet_card(<merchant fleet>)` returned `"voyage":{"id":"d727c289-…"}`. The exposure is a merchant's position only (not player data), so this is a contract inconsistency rather than a leak.

**Fix:** Strip the id in the card (`(select world.voyage_view(v.id, true) - 'id' …)`) or give `voyage_view` a third shape, and add `'id'` under `voyage` to the card's forbidden-key scan so the assert can see it.

### [minor] `supabase/migrations/20260818000097_a_company_the_world_keeps.sql:815`

The carried row's `balance_after` is picked by `order by created_at desc, balance_after desc limit 1`. Every ledger row written inside one tick shares `created_at` (= transaction `now()`), so among the last tick's rows the HIGHEST balance wins, not the last. Verified in PGlite: two credits in one transaction (+500 then −700), compact -> purse 103,800, carried row `balance_after` 104,500. `assert_ledger_reconciles` checks only Σ delta, so nothing raises, but the carried row's running balance is wrong and will drift further every hour.

**Fix:** Order by the ledger's insertion order rather than the timestamp tie — e.g. carry `balance_after` = the company's purse at the time of the last collapsed row computed as `(select ducats from players) - Σ(delta of rows >= v_cut)`, which is exact by construction; or add a `seq`/identity ordering to the pick.

### [minor] `supabase/migrations/20260818000097_a_company_the_world_keeps.sql:1201`

The 'stock floor' self-assert (`v_stock < v_floor - step` → FAIL, floor = target/(1+patience)² = 0.59·target) cannot fail for the reason it claims: the planner's parcel is capped by `world.daily_cap_remaining` at 0.35·target per company per game-day, so stock never drops below 0.65·target whether or not the BUY ceiling (`price_limit`) does anything. It is a self-assert with no positive control over the ceiling itself (NO_SPAGHETTI §4 / N19).

**Fix:** Prove the ceiling directly: issue a BUY with qty above the cap-free amount (or lift `daily_cap_fraction` for the probe) at `price_limit = npc_buy_ceiling(...)` and assert the fill stops at the first step whose price exceeds the ceiling, with a positive control that the same qty at no limit buys more; or state the assert as 'the cap bounds the parcel' and drop the floor claim.

### [minor] `supabase/migrations/20260818000097_a_company_the_world_keeps.sql:520`

Every merchant stop is saved with `crew_up = true` (npc_plan and npc_found), so after any raid loss (`voyage.settle` on DRIVEN_OFF/PLUNDERED/STRIPPED, hazards ON in production) the merchant's HIRE draws `ports.crew_pool`, which no tick regenerates (only `do_hire`/`do_dismiss` write it). 32 merchant fleets hiring at ~90 stops for weeks will drain the quays players hire from; the 0098 '20 % of the crew' check is a one-time founding condition, not a bound over time. §13 states 'crew_pool never regenerates' but the player-facing consequence (a merchant stop with no hands for anyone) is unbounded and irreversible without a migration.

**Fix:** Before the switch, either bound merchant hiring (e.g. refuse HIRE when it would take the pool below a floor such as 50 % of the port's starting pool, inside `cmd.standing_route_tail`/`fleet_crew_shortfall` for merchants only via `players.is_npc`), or add crew-pool regeneration as its own small migration, and have slice 6 record per-port `crew_pool` minima over the soak with a fail threshold.
