# WORK QUEUE: the owner's live list (rewritten clean 2026-10-18 ~14:05 UTC)

- 2026-10-28 **0261 beat splits** (`osn-beat-splits`, owner: root cause, no guess-trims): every arrivals beat records where its time went (quay wait, its five loops, the deferred purse checks, the commit, blocks read per table). Results unchanged (old vs new run identical). Found first: the purse checks run at COMMIT, outside `ms`. Deploys after 0260; then 30+ min of splits → the root cause → 0262.
- 2026-10-28 **0259 LIVE (#369, 97ab6f6, main green), 0260 next** (`osn-compact-hold`): 0259's 23:07 run did 21 houses / 2.3 k ledger rows (holds ≤1.23 s); beats p95 4.6 s, max 6.0 s (= the companies step). Backlog GROWS under 0258/0259: ledger 809 k (20:41) → 829 k (22:10) → 848 k (23:10). 0260 = the brief's 5 s hold, 100-house ceiling, receipt adds held_ms / wait_ms.
- 2026-10-28 **0258 LIVE, 0259 next** (#368 fa97e4a, prod head 0258; main Acceptance red AGAIN on city.goodTrades:78, 2nd sighting, recorded, not re-run) (`osn-compact-slices`): 0258's 21:07 run: no batch past the budget (compact 29.9 s), beats in the run p95 13.3 → 5.1 s, max 21.1 → 6.9 s, 0 errors; BUT at the normal cut one house's whole backlog = 3.2 s alone, so only 6 houses / 5.5 k ledger rows (0257: ~25 k) and the backlog grows. 0259 = 0253's 6 h slices back, 0258's clock inside them.
- 2026-10-28 **0258 compactor at the normal cut** (`osn-compact-quarter`): a few houses a transaction, sized by the measured rate to a 1.5 s quay hold (1-25), none started unless it ends inside the 30 s budget; each house rolled once for good; voyages + voyage_events + insurance set-based. Same four-way byte-identical probe as 0257. Prod read-only: old and new keep rules pick the same 199,695 voyages. Local: 821 houses in 39 batches, longest hold 595 ms. After-check: 2 hourly runs.
- 2026-10-28 **0257 compactor batches LIVE** (#367, 4665f63; main Acceptance red once on city.goodTrades:78, an unrelated first-seen flake, green on a diagnostic re-run) (`osn-compact-batch`): 100 houses a transaction, set-based. After-check 18:07 + 19:07: 200 houses / 2 batches a run, 0 failed, 26-30 k ledger + 41-47 k events rolled a run (6x 0253). Backlog 820 k → 802 k ledger, 1.04 M → 0.99 M events. Beats 0 errors; p95 unchanged outside the run, but up to 26-27 s during it (each batch holds the quay ~20 s). ETA ~3-4 days. NEXT: 0258 (batch ~25, normal cut, set-based voyages/voyage_events), see dev-log part 3.
- 2026-10-28: **0256 departure trim** (`osn-departure-trim`, row 224 follow-up): world.spread_effective_pair (a quote's two spreads from one reading), standing_route_lines reads both quays' terms once a stop, do_sail takes her speed from what depart froze. Old vs new identical (self-assert 3,249 + 3,249 questions, 40 SAILs; 129-table end-to-end ×3 starts, control equal). Local: SAIL −10-14 %, arrival −9 %, stop lines −22-33 %, whole beat −2.4 %. LIVE 2026-10-27 17:12 UTC (push landed at head 0256). Prod before: p95 1.72 s, 15 % over 1 s.
- 2026-10-28 **E6b 0255 LIVE, DARK** (#361, 8fc5a54; main Acceptance green; after-check: `wants_lit()` false, 0 wants, 0 markers, drift 0 failed) (`osn-e6b-wants`): every city wants 1–3 far goods, re-drawn twice a game-day, pays ×2 from its purse; flag `city_wants` false (OWNER lights it). Deploys after E6 0254. Sale quote 486 → 478 µs (noise).
- 2026-10-28 **E6 0254 LIVE, DARK** (#360, 1ae85ef; main Acceptance green; after-check: `price_impact_lit()` false, min glut 0, CHECK ±0.5) (`osn-e6-impact`): buy up / sell down inside the walk via the signed press; flag `price_impact` false (OWNER lights it). Deploys after 0253 (#364). Quote cost 408 → 412 µs (noise).
- 2026-10-28 **E5b 0252 LIVE, DARK** (#358, 7caf01f; main Acceptance green; after-check: 0 multiples, 0 base_target, `depth_lit()` false) (`osn-e5b-depth`): max stock moves with investment once a game-day, ±10 %/day; flag `depth_by_investment` false (OWNER lights it). Deploys after 0251. Drift day-run unchanged (4.91 → 4.86 s local).
- 2026-10-27: **0251 near cities priced LIVE** (`osn-near-quote`, #359, owner row 234 / 231): the board prices the 5 nearest sailable cities beside the 10 dearest; the Sell cargo list shows near cities with profit.
- 2026-10-27: **chain baseline S1** (`osn-chain-baseline-s1`, CHAIN_BASELINE.md, DARK): `scripts/db/baseline/` + `chain-baseline.yml` (nightly 04:47 KST / dispatch; artifact only, nothing committed, prod untouched). Two from-zero runs: D-chain = D-base exact, D-base = PGlite beyond a written allow-list, 0018 default ACL proven by behaviour; catalog digest f50c3f9e… identical; prod catalog equal after 2 named platform differences (service_role grants in public, one explicit-default ACL). Seed rows are random per apply, so no row digest is shared. Next: S2 (the cut). Dev-log `2026-10-27-chain-baseline-s1.md`.
- **0250 arrivals trim** (`osn-arrivals-trim`, row 224 follow-up): the same answers for less work (crew_pct skips crew_terms when no seated captain bears the effect; ship_stats / hold read once a hull; goods / skills by key; 3 standing_route_laps indexes). Local −19 to −25 % a beat, old vs new identical (self-assert + 128-table end-to-end). Deploys AFTER 0249. Prod before: p50 0.39 s, p95 1.82 s.
- 2026-10-27 17:10 UTC: **0249 + 0253 LIVE** (reconcile 57-63 s every hour since, was 120 s timeouts; no beat failures). OPEN: compactor drains only 12-34 houses/h because every `ledger_sum` reads a whole uncompacted house ledger from disk; next slice = set-based batch compaction (see dev-log).
- 2026-10-27: **0249 reconcile timeout** (`osn-reconcile-timeout`): the compactor had committed nothing since 10-25 23:07 (943 k events, 742 k ledger rows waiting), so reconcile hit 120 s in 10 of 13 runs; now one house a transaction under a 30 s budget, and beats + upkeep steps share one lock (no deadlock). Dev-log `2026-10-27-reconcile-timeout.md`.

## RESUMED 2026-10-26 ~12:15 UTC (PC gkwng)
- #345 mirrored Buy/Sell MERGED 12:15 UTC (1112dd8, client only).
- Economy watch +5 h 20 min (12:06 count): moved_since_close +138, new_slot 0, under_reserve 118, broke 38, gifts 144 (1.12 M), fees 3,063 (203,855 ducats), debtors 4. All under the switch-back triggers: stays ON.
- **0245 E5 LIVE, DARK** (#346 merged c3e86a5, main Acceptance green; cron 776 ok / 0 failed after). `restock_by_investment` = false: lighting is the OWNER's call. `invested` now rolls hourly (decay + SHARE + DONATION), read by nothing while dark. Not in E5: max stock by investment (`depth_mult`) = slice E5b.
- Owner rows 231 (Sell: can't dock/sail, map moves to pressed city, cargo-first Sell) → `osn-sell-dock-fix`; 232 (tap a Stats chart → large chart, months of data) → folded into N1.
- **0246 N1 LIVE ~14:20 UTC** (#347, every Stats figure folded not dropped; tap a chart → large with 1d…All; owner 232). Cron 1,001 ok / 0 failed after.
- **#348 Sell fix LIVE (109ebf4, owner 231; `cargo-best` verified in the live bundle).** Was: cause = `world.market` lists a carried good only where the city offers it (camphor: 3/246), so every other Sell card read "No buyer". Red once on `desk.sweep` 1440 at 14:30 = the drift-slot-edge freeze (#349's diagnosis), so #349 lands first, then #348 re-checks on main.
- **#349 flakes**: (1) trade.ceiling/desk.sweep = a tray press within seconds of a 15-min slot edge, when the local backend's price-record job blocks the PGlite queue for tens of seconds → `ready(page,{quietMs})` steps over the edge. Product issue flagged: a LOCAL-mode tab across a slot edge freezes the same way. (2) 0019 self-assert = the probe voyage rolls PIRATES/STRIPPED (random voyage uuid → md5 dice) → E_NO_CARGO. Fix = `hazard_p_max` 0 inside the probe; REMOVED from #349 because editing applied 0019 forces CI from zero (owner law). PARKED: fold it into the next PR that edits chain machinery (that one goes from zero anyway).
- **#349 flake fix MERGED** (53abf8b, test fixture only). LOCAL BUILDS BLOCKED on PC gkwng: the shared prefix cache was pruned by the 0019 edit; replay fails 0108's 400 ms `route_board` assert (426/451 ms here). Fix 0108's assert (relative / skip on PGlite) in the next chain-machinery PR, together with the parked 0019 fix.
- **Chain machinery: 0019 + 0108 frozen asserts fixed in the applier, files untouched** (`osn-chain-machinery`, `src/lib/db/frozenAsserts.ts`). Both PGlite appliers (`src/lib/db/applyChain.ts`, `scripts/db/apply-chain.mjs`) read two frozen self-asserts differently: 0019's probe voyage sails with `hazard_p_max` 0 (the pirates roll; positive control: forced pirates reproduce "moved 7424 / <NULL>" unpatched, pass patched) and 0108's `route_board` stopwatch is 1,200 ms not 400 (real Postgres via `supabase db push` keeps 400). Prefix keys, snapshots and the image fingerprint hash the FILES, so no cache moves; but `src/lib/db/**` is chain machinery, so THIS PR's CI ran from zero (the planned exemption).
- NEXT: owner rows open (Casa do Segundo, #268, row 175); E5b depth_mult; E6/E6b; N2–N6; near-city profit in the Sell cargo list needs `good_board_quoted` > 10 (server).
- (done) Building locally (worktrees `~/dev/wt-<branch>`, node_modules junctions): `osn-flaky-1026` (trade.ceiling:267 + 0019 self-assert), `osn-e5-restock` (E5 = 0245, lands DARK), `osn-n1-stats-history` (N1 = 0246).

## HAND-OFF 2026-10-26 ~10:40 UTC (PC 디폴리스 shut down; owner moves to another PC) — READ THIS FIRST
**Prod head 0244. CLOSED ECONOMY ON since 06:52:22 UTC.** Main Acceptance green on a33d77f.
Live today (this PC): 0225 Trade · 0226 price history · 0227 who bought what · 0228/0229 E1/E2 · 0231 legs fit supplies · 0232 Stats live per second · 0233/0234 E3/E4 · 0235 money log · 0236/0237 E4b (dock fee, 1-min port prep, country tax, gifts by cash) · 0238 buy where she can sail (Port Royal) · 0240 E7 guard + switch (LIT) · 0241 sail on credit (debts paid from the next sale; capitals help players) · 0242 arrivals every 1 s (avg 0.73 s) · 0243 stats count adds both halves · 0244 stats filters. Client: #311 #312 #314 #315 #319 #325 #328 #329 #331 #333 #334 #337 #339 #340. Designs merged: ROUTE_BUILDER, CLOSED_ECONOMY (+§3 daily max stock, §4b wants, §4c fees/prep/tax), NEWS_AND_MARKERS, SHIP_STORES_AND_VARIETY.

| next | item | state |
|---|---|---|
| 1 | **#345 mirrored Buy/Sell game screen (owner 229)** | built, CI was running at hand-off: `gh pr checks 345` → green → `gh pr merge 345 --squash` (client only) |
| 2 | **flaky `tests/trade.ceiling.spec.ts:267`** (sell tray Send disabled; failed on #344 and main 68b7817, passed on a33d77f) and **flaky 0019 self-assert in `tests/db.chain.spec.ts:468`** (cold boot; failed once on #343, re-run green) | diagnose, don't re-run until green |
| 3 | **economy watch** (switched on 06:52): runbook + A1–A7 in `docs/dev-log/2026-10-26-econ-e7.md`. At +1 h: world total flat (+138), gifts 34, fees ~4,700/h, laps −12 % (port prep 60 s), **under_reserve 85 → 112** (cities pay more for sales than they take from buys). OWNER-ONLY switch (owner 10-26: "never do something i didn't tell you"). If under_reserve > 150, broke > 120 or purses −5 %/day ×2, REPORT the numbers to the owner; never flip it ourselves | check now |
| 4 | E5 restock + max stock by investment (daily) → E6 prices like stocks → E6b city wants ×2 | build, numbers from 0245 |
| 5 | N1 keep all Stats history (lost daily past 72 h) → N2–N6 news markers | build |
| 6 | merchants' empty lap SELLs (E_NO_CARGO 400 → 10,400 per 15 min since 06:15) · owner's board 3–4.5 s · merchants net +18 M/day (balancing PARKED by owner) | look into |
| 7 | ship stores space + ship variety V1–V4 · route builder B1–B4 · R4 Report · rollover W1–W4 · fleets F1–F7 · sea S3–S6 | queued |
Owner's own company (JOOHOON HA, fleet Gaivota): at Banten with 45,085 cargo, purse 0 — can now sail on credit (0241). Waiting on owner: Casa do Segundo 0224, #268 pirates, row 175.
Rules learned 10-26: renumber migrations to head+1 BEFORE deploy (push refuses a version below head); worktrees need `supabase/.temp` copied for `--linked`; this PC's locale is Korean (plain-Node word specs fail locally, pass on CI); never change live behaviour inside an economy watch window without saying so.

## RESUMED 2026-10-25 (PC gkwng). Read this first
Prod head **0216**; main Acceptance green (0ec8ed1, 10-21). Nothing has landed since 10-21. Of the owner's rows 169–188, these are still open: 169a speed ×3, 173 weekly reset, 175 (blocked on the owner), 180 fleets, 183 Plan tab, 186 harbours.
**In flight (two builds + one design), as CLOUD ROUTINES (the owner's cloud-first order; credit expires 11-05). The 09:14 runs died at once on the WEEKLY usage limit (reset 10:00 UTC); they were RE-FIRED at 10:23 UTC. Follow them on GitHub branches and PRs:**
- Lane A `osn-new-harbours` (trig_017yTwoYS3AoraZWTePMeL9M): row 186, about 8 harbours (northern Russia, Australia, NZ, northern USA) as migration **0217**.
- Lane B: row 183 Plan tab **MERGED** (#292, 2026-10-25 ~11:25 UTC, client only). It left one missing server read, a Lane A item that must land BEFORE `sea_conditions_bite` is lit: add `sea: { zone, zone_name, needs_title, needs_wave, refusal }` to `world.good_board`'s buy and sell rows (read from `sea_leg_asks` and judged by `public.sea_refusal`). Without it, a leg closed by sea reads as 'too far'.
- Lane C: row 180 design **MERGED** (#291, `docs/FLEETS_AND_SLOTS.md`). Its defaults stand unless the owner reverses them: 7 ships per fleet, up to 5 fleets, room opened by level or by gold (the gold is destroyed; 1.37 M for everything), ships move only when docked in the same port, merchants get a flat 2 × 7. Build F1–F7 in Lane A after 0217.

The main session (this PC) only runs the read-only prod checks, the paired sim, and the deploys. Fable credits ran out until 2026-10-25 10:00 UTC, so the routines use Opus.

**Next:** 169a speed ×3 (paired sim) → 173 weekly rollover, keeping history → sea S3–S6 → live prices.

### ~14:30 UTC — owner RULE: do all, merge, deploy, finish, clean without asking (memory: finish-merge-deploy-clean-no-asking)
- **0217 LIVE ~15:00 UTC (#295 merged):** after-check OK: 8 cities × 565 goods, purse 2,000,000 each (the seeded fix mattered), 246 harbours, 138,990 port_goods, +48 courses, cron 55 ok / 0 failed. Earlier: the npc 2/2 red was map.wrap tapping Astoria, which the frozen fixture did not name; fixed by the cloud job (b93b812). **Prod check found a real defect:** 0217 decided "seeded" from SEED flows, which are pruned on prod (0 left), so it would have opened the 8 new cities with empty purses. Fixed to read `port_treasury.seeded_at` (all 238 set on prod), 234e7f2. CI re-running → deploy.
- Prod checks for 0217 all match the dev-log except that one: head 0216, hunk ×1, preconditions true, raster/reaches md5 equal, knobs as expected.
- **Command design MERGED (#297, docs/COMMAND_REDESIGN.md) with its defaults.** Top reach cause: the REGION DOOR (exploration level by nm from Lisbon, 0107:270); a Lisbon starter reaches 111 of 237 harbours, and the Plan wrongly says "too far … Navigation". **R1 build running** in `~/dev/wt-osn-trade-r1` (migration 0220: Trade page, Sell list, automatic supplies, Keep-supplies removed).
- **Deploy order (owner: region door FIRST after 0217):** 0217 harbours → 0218 NO REGION DOOR (`wt-osn-no-region-door`) → 0219 sea board (#293, renumber its file + tags at deploy) → 0220 speed ×3 → 0221 R1 Trade → Stats-every-second → R2–R6 / rollover W1–W4.

### OWNER PLAYTEST 2026-10-25 ~13:30 UTC — OUTRANKS THE LIST BELOW (rows 189–195)
The owner played and could not trade: "this game must be playable". Local agents:
- `~/dev/wt-osn-quick-189-193-195`: 189 flat sell chart (diagnose first), 193 every city labelled at 47 % with no overlap, 195 a Korea (KST) real-time clock beside the game date. One client PR.
- `~/dev/wt-osn-command-redesign`: DESIGN for rows 190–194 (`docs/COMMAND_REDESIGN.md`): buy AND sell from the Plan, the reach diagnosis, a mini route map, Profit → Report persisted by section and by point. Build slice R1 (playable buy → sail → sell) comes FIRST, ahead of the rollover W-slices and fleets.
- 169a speed ×3 (`wt-osn-speed-x3`): **BUILT, PR #296, file 0220** (CI green on the pre-renumber head; the dev-log's PROD CHECKS before deploy). Still running: proof 05 fix (`wt-osn-proof05-margin`, waiting on CI). 0217 #295 CI running → deploy, then 0218 #293.

### 12:35 UTC update (main session, fresh)
- **0217 harbours** routine (cse_01WAoJhjSS2KNx9AGwoZehKG) still running, about 90% done: growth, sea and city self-asserts pass, and so does the world guard. **Proof 05 (first-voyage balance) is on a knife edge**: base 13.47 % long vs 13.00 % short. The new Kola harbour tipped it to 12.71 vs 13.91, so the routine swapped Kola → **Mezen** (White Sea, also real northern Russia). Review that swap on its PR. The next world growth will tip proof 05 again: the proof's margin needs its own fix, and the data must not be bent to pass it.
- **#293 = 0218** green, waits for 0217 (deploy order). Deploy both with `~/bin/bv-deploy.sh`.
- **CLOUD CREDIT GONE (owner, ~12:45 UTC): everything runs LOCALLY now.** 0217 is the last cloud job; the owner said to let it finish. The 169a and 173 routines were turned off before they fired.
- **Lane A build (local agent):** row 169a speed ×3, `osn-speed-x3` in `~/dev/wt-osn-speed-x3` (node_modules is a junction: unlink it before deleting the folder), file 0220 — **BUILT and sim'd locally** (docs/dev-log/2026-10-25-speed-x3.md: one knob `speed_scale` 3 applied to the rows the one formula reads, no body changes; players ×2.3–2.96 ducats per real hour by band, merchants in the dev-log's §4). Deploy AFTER 0217, 0218 and 0219 (the sea board, #293) with `~/bin/bv-deploy.sh`; the dev-log's PROD CHECKS first. Ships at sea at the deploy finish their leg at the old speed (decided by default). (PR #296)
- **Row 173 design MERGED (#294, cfa08f2). The owner ACCEPTED ALL DEFAULTS (2026-10-25):** the week runs Monday 00:00 UTC; the Investors board and route lap counters reset; shares, works, influence and flags do not; no backfill; History tab "History"/"내역", 8 weeks; no cron. Build W1–W4 in Lane A after 0220 (speed ×3).
- **Token rules (owner, 10-25):** fresh session per job; no 10-min reminder; no polling routines (the "PR #293 safety check" routine was disabled); CI is watched with `gh pr checks --watch` in a background shell; routines build locally before pushing and push once.


## WHAT LANDED 2026-10-20 AFTERNOON (cloud session) — read this first

Prod head **0216**, clock **9/9**, main green and published.

| live | what |
|---|---|
| **0214** | the Stats tab's server: `tick_stats` every 15 min, six gated reads |
| **0215** | the seas have conditions (S1) — dark, `sea_conditions_bite` false |
| **0216** | the passage gate reads the sea (S2) — dark |
| #279 | the npc-shard flake fix |
| #280 | the arrival countdown ticks and says "due"; FLEETS gains a cargo breakdown |
| #281 | light map = dark map · the full date in the strip · the YOU tab |
| #282 | map label leader lines · an NPC's name takes you to her |
| #283 | the Stats face: charts, counters that walk, a live band |

After-check for the three migrations is in `docs/dev-log/2026-10-20-cloud-deploys.md`, with the four
things that broke and must not be repeated. Arrivals pace flat (~3.2–3.4 s); 3 failed cron runs of
232, all inside a deploy window, none since.

**In flight now:** #284 double press (red twice on `acceptance-shard (npc 1/2)`, being fixed) ·
`osn-smooth-sailing` (169b) · `osn-city-info` (174, 177) · `osn-prices-both-ways` (178).

**Known CI trap:** a merge made with a session token triggers NO workflow — no Acceptance, no Pages
deploy. Dispatch `deploy-pages.yml` and `acceptance.yml` by hand after any such merge (never
`migrations-apply-proof.yml`: a dispatch sets FROM_ZERO there and rebuilds the world).

**Reading a red CI run from a cloud container:** the job log and the Playwright report are on a
blob host the network policy answers 403 to. The `acceptance` VERDICT job's annotations are
readable and name the shard and the count:
`gh api repos/gkwngns714-spec/byeharu-voyage/check-runs/<id>/annotations`.

## THE OWNER'S NEW ORDER, 2026-10-20 ~14:35 UTC — THIS OUTRANKS "THE LIST" BELOW

Owner: *"what i am saying now is what is important. change it."* Twenty requests arrived this
afternoon (OWNER_REQUESTS rows **169–188**; the words are there verbatim). They outrank the
10-20 04:00 list, which stays below as history. The lane rule still holds: **two builds + one
design in flight**, Lane A = server, one migration at a time in strict number order.

**First, because it is about what just shipped and the owner is unhappy with it:**

| # | Row | Item | Lane | Note |
|---|---|---|---|---|
| 1 | 188 | **Stats tab: charts, moving numbers, modern** | B | 0214 shipped the server and a plain face. The rows are already there (one per 15 min, one per day beyond the fine window) — this is the face, no migration |
| 2 | 187 | **Stats "real time, by seconds"** | B | CONFLICTS with 0214's 15-minute rollup. Decided by default: live reads tick client-side every few seconds; the rollup and the charts stay 15-minute. No per-second writes |
| 3 | 185 | **Map labels: why hidden, show all without overlap** | B | Owner asked WHY — read the declutter rule and answer it, not just change it |
| 4 | 184 | **Click an NPC's name → point me there** | B | Same affordance the city rows have |
| 5 | 186 | **~8 new harbours**: 2 N-Russia, 2 Australia, 2 NZ, 2 N-USA | A+B | Real places, real coordinates; each needs a roadstead, a 0215 sea zone and a power. Check against the 0216 gate |

**Then the morning's fifteen (rows 169–183), in the order they are worth doing:**

| # | Row | Item | Lane | Note |
|---|---|---|---|---|
| 6 | 171, 172, 176, 181 | Light-map colour · coordinate on double press · full date clock · personal-info tab | B | Cheap client work, no migration; do them together |
| 7 | 170 | The "arrives in (min)" wait | ? | READ first: which wait is it? The arrivals job's 15 s, the served ETA, or 0116's rest |
| 8 | 179 | Provisions inside the hold, % breakdown, crew-scaled, minimum crew | A+B | Owner says *"I may be wrong"* — establish the current model before changing it |
| 9 | 174, 178, 177 | City Info tab · both prices always + longer window + draggable chart · goods rarity and class | A+B | |
| 10 | 173 | Weekly reset of investment and lap records + history | A+B | Must ROLL OVER and keep the old week. `events` and the ledger are append-only |
| 11 | 169a | **Ship speed ×3** | A | **BUILT 2026-10-25: migration 0220 on `osn-speed-x3`, paired sim done (docs/dev-log/2026-10-25-speed-x3.md).** Economy change, not cosmetic: laps get ~3× shorter, so earnings per real hour ~3× for players AND merchants |
| 12 | 169b | Smooth (non-tick) ship movement | B | **BUILT — PR #287, `osn-smooth-sailing`, client only, no migration.** What ticked was the MODEL (the shell's 1 s clock), not the read: `src/chart/underway.ts` moves hull, course and name on one animation frame, chasing the served place; stops at arrival; reduced motion unchanged. Dev log: 2026-10-20-smooth-sailing.md |
| 13 | 180 | Multiple fleets, 7 ships each, slots unlocked by gold and level | A+B | Large. Row 1 said 8 ships, this says 7 — unresolved. Gold slots are a new money sink; check against 0212 |
| 14 | 183 | Plan tab: map, provisions, crew, restrictions | B+A | AFTER 0216 — its restrictions ARE the sea gate; building it first writes the rule twice |
| — | 175 | **3× selling price by distance** | — | **BLOCKED ON THE OWNER.** It reverses 0212, which went live 04:27 UTC today to stop far selling printing money (far routes were ~89 % of profit; haul 600 → 3). Queue item 9 is also still HELD by the owner's own *"원거리 판매 기술은 아직 아냐"*. Read by default as "a long route should pay ~3× a short one per day" (today: 1.45×), a measured target, NOT a raw ×3 on price |

**Still in flight from this morning (Lane A, finish before starting another server item):**
0215 Sea S1 (#275) deploying · 0216 Sea S2 (#276, retarget its base to main first).


Standing orders: keep working and never stop; never ask (decide, record it as "decided by default", and the owner may reverse it); give a 10-minute status; make it clean; CI fast and never from scratch; close finished shells and worktrees; use Fable where efficient.

Owner 2026-10-18 ~13:55: **"so fix and do everything"**.

Deploys go through `~/bin/bv-deploy.sh <pr>` only, which merges only after the push lands. Migrations deploy in strict number order.

Prod head: **0213** (0213 insurance LIVE 05:20 UTC, 0212 haul cap 04:27 UTC, 10-20). Earlier: **0211** (2026-10-20: 0209 arrivals 23:43, 0210 running costs 00:35, 0211 round trip 00:52 UTC; all after-checks passed).

## HAND-OFF #3: the owner turned PC 디폴리스 off, 2026-10-20 ~09:00 UTC. START HERE (any PC, or the cloud)
Owner 10-20: *"deploy and merge them if everything is finished, including korean"*, then *"make every procedure so that i can continue from other pc, or even cloud. then turn the pc off"*.

**Live state at hand-off:** prod head **0213**, clock running (8/8 cron jobs active). **Korean (#278) MERGED** to main 08:58 UTC (b1887e1, client only); Pages publishes it. Nothing else landed today after 0213.

**Open, in deploy order (strict number order: 0214 → 0215 → 0216):**
1. **#277 Stats tab, 0214.** `db push` to prod at 08:49 UTC **failed its own self-assert and rolled back** (nothing landed, not merged): the probe city ACA has real trades on prod, so absolute checks (`sold_1d = 50`, `taxes_1d = 100`, SELL `-1234`) are wrong on a live world. Cloud routine `trig_01MnPGoVkQPm2SkiVnjNTGT6` (starts 09:05 UTC) makes them deltas and writes "PROD CHECKS FOR THE MAIN SESSION, 0214" in `docs/dev-log/2026-10-20-stats-tab.md`. Also: the red `acceptance-shard (npc 1/2)` is a flake ON MAIN (`tests/map.merchants.spec.ts:510`); cloud routine `trig_01CKaJUxg8fjL9a5BEtovqVW` fixes it on branch `osn-fix-merchants-flake` (own PR). Prod prechecks already run 08:45 and passed: every live flow kind has a word, goods names unique, registry hunk occurs once, 0214 not applied.
2. **#275 Sea S1, 0215.** Prod prechecks (dev-log §8a + §8b) **all passed** 08:53 UTC. `db push` at ~08:55 **failed: "Connection terminated unexpectedly", at statement 23** (the 1,036,800-row `get_byte` cross-join check after the raster build). Rolled back, not merged. Cloud routine `trig_017qKVVUWsTSDDv7MF5JSPwk` (starts 09:06 UTC) makes 0215 fast (target < 60 s, no long hot-table locks), then rebases #276.
3. **#276 Sea S2, 0216.** Stacked on #275 (base branch `osn-sea-s1`). After #275 merges, retarget its base to `main` (`gh pr edit 276 --base main`) before deploying.

**EXACT DEPLOY PROCEDURE (any PC that has done `docs/NEW_COMPUTER.md`):**
1. `cd ~/byeharu-voyage && git fetch && gh pr list` → read each PR's latest comment from its cloud routine; `gh pr checks <n>`; required = `build` + `disposable-chain` green.
2. Prod head: `npx --yes supabase@2.120.0 db query --linked "select max(version) from supabase_migrations.schema_migrations"` (must be the number just below the PR's migration).
3. Run the PR's dev-log "PROD CHECKS FOR THE MAIN SESSION" blocks read-only (`db query --linked -f <file>`); every row as expected. If one fails, do not push: send it back to a cloud routine.
4. `~/bin/bv-deploy.sh <pr>`: it unwinds the clock, pushes, re-winds, and merges ONLY if `push_rc=0` and head = the PR's migration. On `NOT MERGING`, read `~/bv-push-logs/push-<version>.log` to its last error; never just re-run.
5. After it lands: check the clock (`select count(*) filter (where active) from cron.job where jobname like 'byeharu-voyage:%'` = 8), the Pages deploy (`gh run list --workflow deploy-pages.yml -L 1`), then update this file and `~/bin/bv-queue-push.sh`.

**FROM THE CLOUD (claude.ai/code, repo gkwngns714-spec/byeharu-voyage):** code, tests, PRs work today. **Deploys can't run from the cloud yet:** its environment has no `SUPABASE_ACCESS_TOKEN` (probe `trig_01Y4kboFF5vp35XEDAR7h9Bi`, 08:34: "not set"). One-time unblock (owner): supabase.com/dashboard/account/tokens → new token `claude-cloud`; claude.ai/code → environment selector → this environment's settings → Environment variables `SUPABASE_ACCESS_TOKEN=sbp_…`; Network access **Custom**: `api.supabase.com`, `supabase.co`, `*.supabase.co`, `supabase.com`, `*.supabase.com` + "include default package managers". Then re-run the probe; if it reads head 0213+, a cloud session can follow the procedure above with `bash scripts/ops/bv-deploy.sh <pr>` (repo path differs: edit `~/byeharu-voyage` in the script to the clone's path). Unverified: whether the DB connection (ports 5432/6543) passes the cloud proxy.

**Cloud lessons (10-20):** routines created via the API did not show in the owner's claude.ai list; follow them on GitHub (branches and PR comments). A cloud sandbox builds the PGlite world from zero (~2.5 h): every routine brief says *no from-zero world build; tsc + eslint + build + pure specs; CI proves the chain*.

## THE LIST (tidied 2026-10-20 ~04:00 UTC: the ONE priority order; everything below it is history)
Owner 10-20: *"everything is too much and could be messy … tidy up, prioritize everything … build slowly step by step, but as efficient as possible."*
**Rule: at most TWO builds + ONE design in flight.** Lane A = server (one migration at a time, strict number order). Lane B = screens. Lane C = one design doc. Next item starts only when its lane frees.

| # | Item | Lane | State |
|---|---|---|---|
| 1 | **Insurance** (0213) | A | **LIVE 05:20 UTC** (#274): premium 0.05 % (<500 nm) → 0.56 % (4,000+ nm) of cargo, payout cost basis −10 % from the port's purse, cargo only, merchants always insure, no refound. Also fixed the route.stopface reach race. 30-min after-check running |
| 2 | **Money printing fix** (0212) | A | **LIVE 04:27 UTC** (#273): `haul_max` 600 → 3, far end 300× → 2×; sim: far/short per day 190× → 1.45×, laps ≤ 0 36 → 26 %, lay-ups 11 → 1; prod IMPORT_DEMAND was 22 % of SELL (24 h). 30-min after-check running. Middle distances now earn less per day than short: re-measure with item 9 |
| 3 | **Fleet picker** (screens only) | B | **LIVE 2026-10-20 ~04:50 UTC** (#272 merged 60aa938; Pages deployed) |
| 4 | **Stats tab** + city-investment gating (owner rule) | A+B | RESUMED 10-20 (owner asked "what about the statistics?"); agent building on `osn-stats-tab` (0214, tiers 20k/100k); deploys after 0212/0213, before sea 0215/0216 |
| 5 | **Korean language** | cloud | RUNNING as a CLOUD ROUTINE (trig_01BnN4iumDDH5Gcoq11XF9Vv, session cse_019Ua4Ytkj7ZjCmcygzUdPHP) since 05:13 UTC; owner: cloud credit first for everything |
| 6 | **Sea conditions + Europe-only start** (region unlock) | A+B | design MERGED (#271). Owner 10-20: "lets start by applying the design you've created first, then consider adding more" = all 7 defaults. Agent building S1 (0215, data, dark) + S2 (0216, passage gate behind `sea_conditions_bite`); deploys after 0212/0213. Then S3–S6, C1–C5 |
| 6b | **More conditions** (쇄빙 ice, 돌파 breakthrough as entry conditions; 조력 rowing as a calm-sea speed effect) | – | LATER: owner wants the base design first, then consider |
| 7 | **Capital move** | A+B | after 6 |
| 8 | **Live prices, wider spread** (owner said yes) | A+B | WIP `osn-live-prices`; after 6 |
| 9 | **Far-selling extras** | – | **HELD BY OWNER** 10-20: "원거리 판매 기술은 아직 아냐" (not yet). Don't build; branch `osn-far-selling` stays parked |
| 10 | **Hub design** (Tribal-Wars buildings and resources; ships never go home) | C | after 6's design |
| – | Small: remove PROBE test money (82k) | A | slot in with any migration |
| – | Decide after 2: merchant hoards / money outflow | – | owner decision later |
| – | HELD: pirates #268 · famous gear sources | – | owner |

## (superseded by THE LIST) PLAN 2026-10-20 ~03:00 UTC (owner asked for every planned build; not started, awaiting "go")
1. **Money printing fix** (urgent): far-sale distance premium is minted (IMPORT_DEMAND ≈ 57 % of sale value, ~500–600M/day vs 1.6B world stock; far routes = 89 % of profit). Cut far-end haul 300× → ~4.5× (`haul_max` 600 → 8, 0208's refill pattern). Sim first; after-check IMPORT_DEMAND/SELL.
   - **2026-10-20 ~03:40 UTC: BUILT, PR open (`osn-haul-cap`, migration 0212 (renumbered from 0213), NOT deployed).** Measured first (docs/dev-log/2026-10-20-haul-cap.md): on the far-selling metric 8 leaves a 10k+ route at 6.0 × a short one per day, so the file sets **`haul_max` 3 (far end 2 ×), which gives 1.45 ×** (decided by default; the owner may prefer 8 — one literal + `c_max`). Paired sim: laps ≤ 0 36 → 26 %, lay-ups 11 → 1, no market emptied/over-full; proof 05 18.0 → 18.0. Prod read-only: IMPORT_DEMAND was 22.3 % of SELL over the last 24 h (not the audit's 57 %).
2. **Stats tab** (owner 10-20: "statistic tab along with command, map … world economy, npc economy, cities, trade good stocks … updated regularly"): 15-min snapshot job (read-only), 7 d at 15 min then daily forever; Overview / Markets / Cities / Merchants / Me (others' purses hidden, by default). Server first.
3. **Insurance 0212**: PR pending (agent finishing specs).
4. **Sea entry conditions, 오리진 style** (owner research request 10-20): per named sea a captain level (title, by default) + fleet AVERAGE wave resistance (ship class stat + gear); hard wall at plan time and departure; map shades closed seas. Navigation leg reach STAYS (owner's rule) and composes in passage_gate. NPCs under the same rule (option A) via the merchant planner's feasibility check (0203 npc_feasible_legs); at-sea fleets finish their trip; sim the no-open-loop count first.
5. **Fleet picker** (owner: "good. we need that"): one button (flag, name, status dot, ▾) + dropdown; ← →; phone tray; one shared selection with the map.
6. **Live prices**: owner 10-20 YES to a wider minimum spread for visible ticker moves. Target thinnest round trip ~2 %, flutter ±0.5–0.8 %, slow waves ±3–10 %. Re-cut onto 0211; settle 0194's sell-then-buy loophole here.
7. **Far-selling extras** (saturation in the glut authority, stale far prices, spoilage): re-measure after 1 and 4.
8. **Housekeeping**: remove PROBE_YARD/PROBE_INN credits (82,000); verify the audit's "no human trades since 09-27" (conflicts with the owner's Gaivota play).
9. **Merchant hoards / money outflow**: decide after 1 (owner 10-18 "leave money growth for now").
- **STARTED 2026-10-20 ~03:30 UTC** (owner: "now do what is necessary. start working"): agents on `osn-haul-cap` (build 1, 0213), `osn-stats-tab` (build 2, 0214), `osn-fleet-picker` (build 5), `osn-sea-conditions-design` (docs/SEA_CONDITIONS_AND_REGIONS.md), `osn-korean` (NEW, below). Insurance agent still on 0212.
- **Owner 10-20, Stats rule:** "a statistic info of a city is added only when you invest certain amount". City figures are intelligence bought by investing in that city: world overview, per-good world index, merchants summary and Me are public; per city: locked → tier 1 overview → tier 2 full detail by the viewer's own investment (knobs), enforced server-side. Sent to the stats agent.
- **NEW 10-20: Korean language** (owner: "make language korean available, at least up till what we have made now"): one dictionary authority (en + ko, typed keys), switch in Profile and Sign-the-book, browser default, every existing screen; server refusal codes mapped, uncoded server sentences stay English v1. Branch `osn-korean`. New screens (stats, fleet picker, insurance) need ko keys after they merge.
- **Owner 10-20, regions and hub:** everyone starts in Europe; regions unlock by progress (sea conditions ARE the unlock); the capital can be moved later; the capital becomes a Tribal-Wars-style hub with buildings and resources (LATER, design doc first). Owner-confirmed law: ships never go "home" to act; the hub is the economic base, not a parking spot.
- Checked 10-20: no human trade since 09-27 (JOOHOON HA last ledger 09-27); 3 new accounts 10-14/15 unplayed. The live economy is NPC + cities only.
- **Held:** pirates #268 (owner 10-20: "keep it as it is for now"). Famous gear sources: owner "later".
- 0187 shipped TEN great powers: that follows the owner's own follow-up "in asia add korea, in europe add more" (OWNER_REQUESTS row 161). Not a mismatch.
- The 10-18 "In progress" table below is STALE: all of it shipped (0186, 0188, 0197, 0199, 0183, #240, #227/#228, #225, #218, 0187).

## BILLING NOTE 2026-10-20 ~06:00 UTC
Owner: the WEEKLY allocation is still being used, not the cloud session credit (which expires 2026-11-05). Likely cause: the long LOCAL main session on PC 디폴리스 itself. Main session went quiet. Cloud routines (stats tab, sea S1+S2) run on. Next step, if confirmed: run the coordinator as a claude.ai/code cloud session. Also found: CROWN_AID 4.36M and EARNINGS 1.23M per 30 min after 0213 (maybe minted); trace it later (held).

## CLOUD-FIRST (owner 2026-10-20: "use claude session credit first for all work … until it is exhausted")
- 05:28 UTC every Fable 5.1 session (local agents AND the first cloud routine) stopped: "out of usage credits" (seven_day_overage_included, resets 2026-10-25 10:00 UTC). Opus still runs in the cloud.
- Work moves to CLOUD ROUTINES on Opus (no parallel sub-agents). Code only; the main session on PC 디폴리스 runs the read-only prod checks and the deploys.
- Running: `trig_012R2tAZnDaiCcqcVBcewJJ8` Stats tab finish (osn-stats-tab b054cee) · `trig_01RNBbPQDWzw78pE5cGJP37M` Sea S1+S2 rebase (osn-sea-s1 5278abe, osn-sea-s2). Korean (the first routine's work was lost, nothing pushed) restarts in the cloud after Stats merges.

## RESUMED 2026-10-19 ~23:30 UTC (PC 디폴리스)
Prod head 0208 (checked). Nothing moved during the 15 h gap.
- #267 shard 3/3: READ. Root cause: 0209 drops `npc_buy_ceiling(uuid,uuid,numeric)` and recreates it with 7 args, while `tests/rpc.surface.spec.ts:1650` still named the old signature. Test fixed, hold note lifted (8968c83); **0209 LIVE 23:43 UTC** (#267 merged; Pages + main Acceptance green). 30-min after-check PASSED: 0 failed jobs (all jobs); arrivals avg 2.93 s both sides (before n=138, p50 2.85, max 6.3 · after n=131, p50 2.74, max 5.7). The sim's ×0.79 sweep gain does not show in the cron total (the job does more than the sweep), but nothing got worse.
- **0210 LIVE ~00:35 UTC** (#269 merged): stores, repairs, wages ×0.2 (`running_cost_level`; owed wages scaled exactly). CI 15/15; proof 07 fixed (the proof's top-up cost 1 at ÷5). Paired sim: lay-ups 83→29 at kickoff (61→11 at end), traded-and-lost laps 23→4, median lap net 38→65.5; starter's voyage 18.2 % unchanged. 30-min after-check (00:35–01:05) PASSED: 0 failed of 129 runs; arrivals 2.69 → 2.68 s avg (n=118 each side, max 5.6/5.7); one drift run took 32 s (the 3 h before 0209 also had a 37.5 s one).
- **0211 LIVE 00:52 UTC** (#270 merged, renumbered from 0212): A ROUND TRIP NEVER PAYS. In world.quote_priced, a stock shelf (trade_step_tuns) has one mid whichever way it is walked; buy totals are ceiled, sale totals floored. Its self-assert passed on prod at push (68 probes, 544 pairs). Live effect: a sale's first ten tuns pay one shelf lower (≤ 0.84 %); totals move < 1 ducat. Found, not fixed: 0194's glut makes sell-then-buy ~0.1 % cheaper per cycle at the 0.4 % spread (day-capped); decide with live prices. Live prices must re-slice ONE hunk on top of 0211 (dev-log 2026-10-20-same-port-flip §5).
  30-min after-check (00:52–01:22) PASSED: 0 failed jobs; arrivals 2.51 s avg (n=121, max 6.8); drift 1.6 s; reconcile 11.7 s.
- **Owner 2026-10-20 ~01:40 UTC:** live prices: YES, widen the minimum spread so prices visibly jump like a ticker ("every trade costs slightly more" accepted). Pirates PR #268: "keep it as it is for now", HELD (do not build Z1–Z7). The owner has a new request coming.
- Insurance is now **0212** (`osn-insurance-v1`), rebasing on 0211, PR next.
- Agents running: running-costs 0210 (DONE) (finish proof 07 + sim, PR, no deploy) · insurance 0211 (finish, PR, no deploy) · NEW `osn-same-port-flip` (the buy-then-sell-same-port bug, at the price authority; must land before live prices are lit).

## HAND-OFF #2: the owner moved PCs again, 2026-10-19 ~08:40 UTC (from PC 디폴리스)
**Prod head 0208. Main is green** (Acceptance success on 3cf859f). Nothing is half-deployed. On the old PC, every agent was told to push its WIP plus a "## HAND-OFF" section in its dev-log, then stop; nothing runs there now.

Live today: #257/#260/#266 (main green again; the harbour-list test reads one DOM snapshot); #259 market words; 0205 good switch + 0206 force_custom_plan (board ~2 s steady); 0207 markets ×10; #262 Plans/City/Invest/Profit in place; **0208 economy** (holds ×3, goods prices ×0.2, haul premium ×0.5; after-check passed).

Resume, in deploy order. Each is a branch; read its dev-log "## HAND-OFF" first and `gh pr list`:
1. `osn-running-costs-d5`: supplies, repairs AND wages ÷5 (wages are a flat 1 ducat/crew/day, not a %; including them was decided by default). Owner said "supplies and repairs yes". Measure merchants, then deploy as head+1.
2. `osn-insurance-v1`: the v1 above (10 % deductible, cargo only, NPC houses insure instead of the free refound). Price via a `voyage.risk_quote(...)` so pirates Z1 can swap the danger under it.
3. `osn-live-prices`: a deterministic per-market tick (server = client), lands DARK (`price_tick_on`), then lit with a window.
4. `osn-arrivals-cache`: per-sweep leg-price cache; ship only if plans are identical and the sweep is faster (re-measure on the post-0208 world).
5. `osn-far-selling`: APPROVED by the owner: stale far prices, far-market saturation (one glut authority), perishables spoil; each lands dark; target long ≈1.3–1.5× short profit/day. Baseline first.
   - live-prices WIP 37c8af5: migration 0212 written (NOT FOR DEPLOY), self-assert passed once locally; no client, no parity test, no perf, no PR. Owner decisions before lighting are in its dev-log HAND-OFF (the flutter is tiny at the thinnest spread; the big swings take hours).
**BUG found (pre-existing, not from today's work):** buy 10 then sell in the SAME port prices the sale one stock step better (~5 ÷ stock, 0.8 % at stock 600). At the thinnest 0.2 % spread, a same-port flip can already pay. Fix before lighting live prices.
**Branch heads at the switch (all pushed):**
- running-costs 0c769e4 and insurance 3727dd9: WIP committed by the main session; their agents were stopped mid-work, have NO dev-log hand-off, and are unverified (NOT FOR DEPLOY).
- live-prices 37c8af5.
- arrivals-cache 61e1053: PR **#267**. The per-sweep cache didn't pay; 0209 instead reads each leg's quay figures once plus an index; sweep ×0.70–0.79, 837/837 plans identical. Shard 3/3 is red and UNREAD: read it first.
- far-selling 78bc142: baseline: far selling pays ~200× a short route per DAY (0173's distance premium reaches ~300×), not ~3×; middle distances are already ~1.4–1.6×. Saturation prototype tuned to ~2.7×, target 1.3–1.5× not reached yet. Spoilage rates exist per good but nothing applies them.
6. **Pirates: PR #268** (docs/PIRATES_AND_HAVENS.md). Awaits the owner's answers to 12 questions (defaults in the doc). On "go with the defaults", build Z1→Z7.
Numbers: each migration renumbers to prod head + 1 at push. Rename the tags/temp suffixes/probe ids inside too (duplication.spec checks them).

Lessons from today: test a hot function with 6+ calls in ONE session (0205's generic-plan cliff); the bv-deploy scripts in `~/bin` on PC 디폴리스 were sed-repointed to `~/byeharu-voyage`.

## HAND-OFF: the owner moved to another PC, 2026-10-19 ~03:25 UTC
On the old PC, every agent, timer and worktree was stopped. Nothing runs there. Prod head **0204**, with the fight lit and arrivals at ~2.8 s.

Resume in this order:
1. **#257 `fix-acceptance`** (main's Acceptance has been red since 2026-10-18 14:33). The fixes are pushed:
   - route.stopface (the Edit control in RouteFold/deskView);
   - map.marks spec;
   - map.noblink layers (index.css);
   - select-specs;
   - the flags screenshots.

   It also brings back a `pull_request` trigger on acceptance.yml, ON PURPOSE: it runs only the selected specs and doesn't block, and it is the root-cause fix. The agent was stopped mid-step. Read ALL its checks, confirm `map.noblink` truly passes at ≤ 7 layers, then merge, then confirm main's Acceptance goes green.
   - **2026-10-19 ~03:25 UTC (PC 디폴리스):** on #257's CI, main's 4 failures pass. ONE new failure: `map.merchants.spec.ts:918`, "port:LIS: rows outside every section" (13 against 12). The markup has no row outside a section, so this is the test racing the live npc clock (separate reads). Fixed in b3498db (one atomic DOM read). **#257 MERGED (88321e3).** Main then failed only `map.daylight.raster:83` (a late mask raster counted in the idle window); fix PR **#260** MERGED. **Main's Acceptance GREEN on f1444f6** (first since 10-18 14:33). Item 1 DONE.
   - 0205 (item 2) is being built in parallel by an agent on this PC.
2. **Arrivals fast: PARKED 2026-10-19 (decided by default).** Trade-loops-first (branch `osn-arrivals-fast` 6e3f601, file numbered 0207, marked NOT FOR DEPLOY) made the sweep ×0.85–0.91, but laps ≤ 0 rose (46 → 53/59 %) and lay-ups rose in both paired runs: it fails the ship rule. Prod arrivals sit at ~2–3 s. Next lever, not built: cache each leg's price across one sweep (no merchant's choice changes). Old note: Read `docs/dev-log/2026-10-19-arrivals-fast.md` § HAND-OFF. Knob-only 16 → 8 hurt the laps (33 → 51 % ≤ 0). Finish "trade loops first", re-run the paired sim, and ship only if both arrivals and laps hold.
3. The owner decides: insurance (proposal below), and pirates / zones / dungeons.

## New from the owner, 2026-10-19 (PC 디폴리스)
| Item | Owner's words | State |
|---|---|---|
| Market prices say whose they are; the out-of-reach note in simple words | "not sure if it is buying price or selling price"; "What does this mean? make it in simple words" | **LIVE** 2026-10-19 (#259, site build 351656e) |
| Trade good quantities 10× for all. Decided by default: city stock, normal stock, and their refill/drain flows ×10, from one knob; prices unchanged | "make the trade good quantity 10 times larger for all" | **0207 LIVE 05:19 UTC** (#263). Checked on 30 prod markets: stock and normal ×10.000, mid price ×1.000. 30-min after-check 05:19–05:50 PASSED: 0 failed jobs; arrivals avg 2.53 s (n=121, max 5.9); drift 8.2 s avg (6 h before: 7.8 s). Balance: a starter's best first voyage 19.4 → 21.1 % of the stake; the tray slider gets coarse at 10× stock |
| Switching goods on the desk is slow | "it takes too long to load, any way to fix this?" | **0205 LIVE 04:55 UTC** (#261). After-check (prod, read-only, one session): the first boards ~1 s, then a generic plan decayed reach_passage 175 ms → 8 s and boards to 18 s. With custom plans forced, 2.0–2.9 s steady (was 4.3–6.1 s). **0206 LIVE 05:07 UTC** (#264, `force_custom_plan` on good_board + reach_passage). After-check, same six-board session with no forcing: 2.0–2.8 s each, reach_passage ~190 ms steady. DONE. New order: 0206 fix · 0207 trade ×10 (arrivals PARKED, below) |
| **Economy package (0208):** ship cargo ×3, goods prices ÷5, the 0173 distance premium halved. Decided by default: only GOODS prices change (cash, purses, ship prices, wages, repairs unchanged). Expect each trip to earn ≈60 % or less of today against unchanged costs; balance measured before deploy | "in addition to the 10x goods quantities, enlarge the ships cargo by 3x. reduce the goods price by 5x. distance earning gold diminish by half" | **0208 LIVE 07:05 UTC** (#265). One knob each: hold_scale 3, goods_price_level 0.2, haul_premium_share 0.5. Kept by default: cash, purses, ship prices, wages, provisions, repairs, profit-tax rates; cargo/warehouse cost basis and merchant BUY limits ×0.2. Measured before deploy (paired sim): merchants' total lap nets −75 %, laps ≤ 0 26 → 36 %, lay-ups 26 → 84 of 837; starter's first voyage 21.1 → 18.2 % (in band). Prod prices after: ×0.10–0.20 (median 0.106). After-check 07:05–07:35 PASSED: 0 failed jobs; arrivals avg 2.83 s (n=119, max 9.5); drift 11.0 s avg. Lever if merchants struggle: wages/provisions/repairs ÷5 too |
| **Running costs ÷5** (supplies, repairs; wages decided by default: they are a flat 1 ducat/crew/day, NOT a %) | "supplies and repairs yes"; "wages are in % so it will be same right?" | agent building (`osn-running-costs-d5`, ~0210) |
| **Insurance v1** (decided by default after the owner asked about it twice): port underwriters, premium from the raid danger authority, payout value −10 % from the city purse, cargo only, NPC houses insure instead of the free refound | "what about insurance" | agent building (`osn-insurance-v1`, ~0211) |
| **Pirates / danger zones / havens (dungeons) / escort contracts**: design doc first (docs/PIRATES_AND_HAVENS.md), build order in slices | "what about … pirate zones and dungeons?" | **Design done: PR #268** (docs/PIRATES_AND_HAVENS.md). Slices Z1 danger number (M) · Z2 map shade (S) · Z3 pirate fleets (L) · Z4 havens as places (M) · Z5 ATTACK + loot/famous gear (L) · Z6 escorts (L) · Z7 insurance hook (S); ~7 agent-days. 12 open questions with defaults, awaiting the owner |
| **Live stock-market prices**: a deterministic per-market tick (~10–15 s, amplitude by rarity, mean ≈ 1) inside the ONE price authority, computed identically by server and client (no writes per tick); live chart + green/red flashes; spread beats the swing so no flipping profit; lands DARK (`price_tick_on`) then lit with a window | "would it be possible, for the prices to be like of stock market? like it moves like real-time stock" | agent building (`osn-live-prices`, ~0212) |
| **Far selling: skill, not distance** (proposed 2026-10-19, recommended combo, builds after running costs + insurance unless the owner picks otherwise): (1) far prices are only as fresh as your last visit or a rumour; (2) far markets saturate: an exotic's premium fades per ton sold and recovers over days; (3) perishables spoil per day at sea; (4) distance → danger via insurance/pirates. Target: long route ≈1.3–1.5× a short route's profit PER DAY (measure first, after costs ÷5) | "you receive a lot of cash just by selling far away … it shouldn't be that easy, yet not too hard. any ideas?" | **APPROVED by the owner 2026-10-19 ("is good")**; agent measuring the baseline, then building (`osn-far-selling`, from ~0213; each mechanism lands dark with its own knob) |
| Arrivals: per-sweep leg-price cache (no merchant's choice changes) | (queue item: arrivals fast) | agent building (`osn-arrivals-cache`, **0209**) |
| Plans / City / Invest swap in place on the COMMAND desk: no pop-ups, no new screen | "i want the screen of the original command tab to stay same … reloading on the same page" | **LIVE 05:35 UTC** (#262, site c543c7c): Plans / City / Invest / Profit fill the desk's three panes; no side panel over the screen on a wide glass. Phone: a face press opens no panel; a press on a price/room still raises the bottom tray (tests/layout.spec.ts: a press moves nothing). WATCH: `map.perf.spec.ts:100` "the wheel did not zoom the chart" failed once on #262 (npc shard; the PR touches no map code), passed on the full re-run; first time seen in the last 12 failed runs |

## In progress, in priority and deploy order
| # | Item | Owner's words | State |
|---|---|---|---|
| 0 | **The owner's fleet Gaivota is stuck.** Plan line 29 `SAIL MTY` (14,015 nm) was refused by his Navigation reach (1,700 nm); lines 30–32 are frozen and Skip does nothing. Fix: a failed plan cancels its own lines and the queue frees; the desk checks reach at plan time; multi-leg passages within reach; unblock Gaivota | "Gaivota stopped at order 29 and will not skip it … what is this?" | building (`osn-plan-reach`), slice 1 first |
| 1 | **0182 re-plan batches**: waiting merchants re-checked about every 10 min; reconcile back under its 60 s budget (it was 57.4 s and 62.0 s) | "why once an hour? can it be faster?" | building (`osn-replan-batches`) |
| 2 | **Remove the 0180 sinks** (surplus hand-over, ship building, the knob). Famous gear unobtainable until the owner sets its sources | "no need to hand in surplus… no they don't need to build ships"; "famous gear … later" | building (`osn-merchant-redesign`, slice 1) |
| 3 | **A merchant's route always pays**, by design. The named case is Comptoir Chastellain at −15 a lap; 55 % of laps are still ≤ 0 | "why is there a route that has no profit? this is design defect" | building (`osn-merchant-redesign`, slice 2) |
| 4 | **Black map blinks at DPR 2** (the owner's laptop; #197 was proven only at DPR 1) | "black blinks that is too disturbing" | NOT reproduced on his PC: 0 black frames in 20k+ frames (Chrome 155, Edge, DPR 2; tile memory 142 MB of 546 MB, 0 OOM). **Owner 2026-10-19: it was an OLD build in an unrefreshed tab; now fine.** Adding a "New version, refresh" banner (`osn-new-version-banner`). Fixing the one real waste found, the daylight mask re-rastered every frame (`osn-daylight-raster`) |
| 5 | **Flags:** a France flag that reads (royal blue with gold lilies); flags at every zoom; the flag snug before the name; clearer on ships. City names black in daylight, with a dark pulsing city marker | "flag is too far"; "france flag looks shit"; "make the city name in light touching zone black…" | building (`osn-flags-2`) |
| 6 | **COMMAND desk → a real trading terminal:** three panes, a big chart, a Best-trade ticket, no bare "—", no native scrollbars | "what about the command tab? … like stock trading screen … stylish" | building (`osn-desk-terminal`) |
| 7 | **Automatic fight:** rounds decided by range, accuracy, attack, armour, boarding and sighting; armour also against shoals; a battle report. Lands dark, then lit with a check | "lets do a automatic fight, so that range and accuracy is an important factor"; "shoals and damage too" | building (`osn-auto-fight`) |
| 9 | **7 great powers** like UWO: Portugal, Spain, England (Europe); Ottoman, Mughal (Islamic); Ming, Japan (Asia), decided by default. The other 16 become minor city rulers. 3–4 home cities each; the rest contested; existing state migrated | "make it 7 big power like uncharted island, spread mainly on europe and asia, as well as islamic region" | design + build (`osn-seven-powers`) |
| 8 | `docs/OWNER_REQUESTS.md` brought up to date from the audit (`docs/OWNER_AUDIT_2026-10-18.md`) | "you leaving out things that i say?" | Fable agent (`osn-ledger-1018`) |

## Proposed, awaiting the owner
- **Insurance (owner idea, 2026-10-19):** port underwriters paid from city purses; a premium priced from the voyage's danger; payout on cargo loss with a 10 % deductible; NPC houses insure in place of the free refound. Proposed v1 in chat; build when the owner says.

## Owner decisions on record (2026-10-18)
- **Combat:** automatic fight, no battle board. Pirates and zones: ideas given (danger zones, pirate havens with bosses and famous-gear loot, pirate fleets, escort contracts); the owner hasn't chosen.
- **16 companies:** LEAVE them.
- **Money growth:** leave it for now.
- **Rejected:** the merchant surplus hand-over, merchant ship building, and the 157,500 hull-skill tuition (one-off in 0167; never repeated).
- **Docks:** leave as is.
- **Route-length gate** (Navigation reach, 0107): the owner's own rule (row 113, 2026-10-10).

## Done and live today (2026-10-18)
- 0170–0177 and D3/D5/D8: the COMMAND desk, with PORT deleted.
- 0172: city purses in the millions. 0173: distance pricing. 0174: circulation.
- 0178: skills on. 0179: captains on.
- 0180: BUY lines priced live. 0181: no empty laps; REPAIR only when due.
- Flags (#198); CI 79 → 11 min (#215); flaky specs (#216); from-zero chain (#212); proof 12 (#203).
- Cleanup: 64 merged or closed branches deleted; 25 orphan folders, 90 logs and 5 stale previews removed.

### ~15:00 UTC findings (PR #298: labels at 47 %, KST clock)
- **#298** (rows 193, 195) is ready but held: its only red is `map.merchants.spec.ts:567`, which ALSO went red on main at 13:39 on a docs-only commit = a FLAKE. Being fixed on `osn-merchants-track-flake`. Merge #298 after that lands.
- **Row 189 (flat sell chart) is SERVER-side:** `public.tick_price_snapshot` records only offered pairs (0061:361-363), so a city that only BUYS a good has no history. Needs a migration: sell-side history per (port, good), capped (COMMAND_DESK D4).
- **Row 197 (city info without investment) is SERVER-gated:** `public.stats_city_tier` (0214:303); `world.stats_city` adds overview at tier ≥1 and detail at tier ≥2 (0214:720,748), and `world.stats_cities` (0214:649) likewise. The migration removes the tier gate, and the client lock faces go in the same slice.
- Both join Lane A after 0221: **0222 Stats** (every second + no investment gate) → **0223 sell-side price history**.

### ~16:40 UTC — PROD HEAD 0218 (region door gone)
- **0218 LIVE (#300):** no region door. After-check: regions.min_exploration_level, both knobs and public.exploration_reach are gone; no body names the door; cron 40 ok / 0 failed. Lisbon starter: 222 of 245 harbours (was 111); the rest are past the 1,700 nm leg.
- **Merged:** #299 plain words, #301 proof 05 (home vs world horizon), #302 merchant-track bug (straight legs drew no track), #303 one row primitive + align guard (rows 196/198/199/201), #304 selector rule W (a reworded dictionary value selects the specs that pin it). Main Acceptance green on 3ddca4f.
- **Lesson:** #299 turned main red (layout pins); after every merge, wait for MAIN's Acceptance (memory: verify-on-target).
- **Next deploys:** 0219 #293 (rebased on 0218, CI running) → 0220 speed #296 (green; rebase + re-check after 0219) → 0221 R1 Trade (building).
- **#298** (labels at 47 %, KST clock): the align guard caught TopBar's date line cut at 390 → now through Clip; CI running, merges on green.
- **Server queue after R1:** 0222 Stats every second + no investment gate (rows 197, 200) → 0223 sell-side price history (row 189).

## HAND-OFF 2026-10-26 ~02:00 KST (17:00 UTC) — session limit; resumes ~03:50 KST. READ THIS FIRST
**Prod head 0220.** Live today: 0217 harbours · 0218 no region door · 0219 sea board · 0220 speed ×3 · plain words #299 · aligned lists #303 · selector rule W #304.
**Main Acceptance is RED on tests/desk.plan.spec.ts** since 0218: Queue is disabled because the good page offers a plan from an unsailable row (past the 1,700 nm leg). Fix in progress on `osn-desk-plan-pin` (PR #306, worktree `~/dev/wt-desk-plan`): good page/plan must pick the best SAILABLE rows.

Every job below has its own worktree `~/dev/wt-<branch>` with a node_modules JUNCTION. Unlink it with `cmd //c rmdir` BEFORE deleting the folder, and stop any `vite preview` left inside it first.
| next # | branch / PR | owner rows | state at hand-off | to finish |
|---|---|---|---|---|
| 0221 | `osn-trade-r1` #305 | 190 194 203 | red: proof 03 (RLS on provision_preset_backup_0221) + proofs calling revoked provision_preset_apply/save; agent told the fixes | fix, rebase on main, green → prod checks (dev-log 2026-10-25-trade-r1.md) → `~/bin/bv-deploy.sh 305` |
| 0222 | `osn-board-fast` (no PR yet) | — | good_board 3.2–4.3 s on prod after 0219; target ≤1 s, same output | PR → prod checks → deploy |
| 0223 | `osn-city-open-lap-age` (no PR yet) | 197 206 | city info for all (drop stats_city_tier gate) + "24 min ago" on last laps | PR → deploy |
| 0224 | `osn-stats-live` (no PR yet) | 200 | counters kept per write + world.stats_now() polled 1 s | PR → deploy |
| 0225 | `osn-price-history` (no PR yet) | 189 205 | bid+ask history, hourly 30 d, daily forever, 1D–All charts | PR → deploy |
| — | `osn-quick-189-193-195` #298 | 193 195 | labels at 47 %, KST clock; only red is desk.plan (main's) | merge after #306 lands, then wait for main |
After R1 lands: R3 mini route map (191) → R4 Report (192) → R2 true reasons → rollover W1–W4 (173) → fleets F1–F7 (180) → sea S3–S6 → live prices → far selling. Waiting on owner: #268 pirates, row 175.
**Rules learned today:** deploy only in number order, renumbering file + tags; after EVERY merge wait for main's Acceptance (bv-deploy.sh now does it); a conflicting PR gets no CI, so rebase first; run each prod check from a file (`db query --linked -f`), one statement per file.


### 2026-10-26 ~03:40 UTC: prod head **0231**, main green
LIVE today since 02:30: 0227 who bought what (#320), 0228+0229 economy E1+E2 DARK (#323), 0231 legs fit supplies (#326); #319 main-red fix, #325 ships stay drawn. Next: 0232 stats-all-live (in CI) → 0233/0234 E3+E4 (building, `osn-econ-e3-e4`) → E4b, E5, E6, E6b, E7 → switch on → watch. Then N1 Stats history kept (after 0232). Open: owner's own good_board reads 3.2–4.5 s on prod (look at it). Known: 0226's self-assert fails if CI applies the chain from zero between 01:00 and 01:59 UTC (needs a forward fix in the proof harness, not 0226).

### 2026-10-26 ~02:30 UTC (PC 디폴리스) — EVERYTHING IN FLIGHT, IN ORDER (owner: "do all the work without dropping any")
Prod head 0226. Merged + live today: #311 #312 Stats header/countdown, #314 mini map 0 %, #315 Trade Here = port market. Designs merged: ROUTE_BUILDER (#313), CLOSED_ECONOMY (#316 + §3 daily max stock, §4b city wants, §4c port fee / 1-min port time / tax by country).
| order | item | branch / worktree | state |
|---|---|---|---|
| 1 | main red (priceSeries tier counts, desk.sweep haggle row, layout.spec:206 Markets fold) | `osn-fix-main-red-0226` | agent fixing |
| 2 | row 211 who bought what (server read + client) | `osn-city-good-trades` (migration "0227", renumber at deploy) | agent building |
| 3 | row 213 every Stats figure live to the second, countdown removed | `osn-stats-all-live` ("0227") | agent building |
| 4 | row 208 Tsushima: reach_passage leg cap from supplies at full hold + plain refusal | not started (diagnosis done: see owner row 208) | next free lane |
| 5 | economy E1+E2 (dark) | `osn-econ-e1-e2` ("0228/0229") | agent building |
| 6 | economy E3, E4, E4b (port fee, 1-min prep, country tax + power_relations), E5 (restock + max stock by investment, once a day), E6 (price impact), E6b (city wants ×2 daily), E7 guard → switch on → watch Stats a few days | — | after E1+E2 |
| 7 | row 216 every chart kept + news markers (design MERGED #322, docs/NEWS_AND_MARKERS.md): **N1 first (Stats history is being thrown away daily past 72 h)** right after row 213 lands, then N2–N6 | — | queued after 213 |
| 8 | map ships vanish and come back | — | agent diagnosing (read-only) |
| 9 | route builder B1–B4 (after 0227 judge), R4 Report, R2, rollover W1–W4, fleets F1–F7, sea S3–S6 | — | queued |
Deploy order rule: migrations one at a time in number order via `~/bin/bv-deploy.sh`, prod checks read first (pure SELECTs only). Waiting on owner: Casa do Segundo 0224, #268 pirates, row 175. Owner asked: keep tokens low; work until 15:00 KST 10-26.

### 2026-10-26 (PC 디폴리스): prod head **0226**, main green, Pages deployed
- **0225 LIVE** (#305, 8d38248): supply_need(s) exist, preset doors 0, 1 standing order backed up. Not yet observed: a live SAIL buying its stores.
- **0226 LIVE** (#310, de307c9). Fixed first: local-backend snapshot re-ran a full tick per read (996974b) + layout.spec pressed the span picker. After-check: 67,428 rows all sided (ask = bid = rows), rollup marks this hour/today, 16,496 hourly rows, cron 9/9, 0 failed; price-snapshot 1.3–1.6 s (was 4–6 s before).
- **Next:** R3 route map (191) → R4 Report (192) → R2 → rollover W1–W4 → fleets F1–F7 → sea S3–S6 → live prices.

## HAND-OFF 2026-10-26 ~21:00 UTC (owner moving to another PC) — READ THIS FIRST
**Prod head 0224.** Live today: 0217 harbours · 0218 no region door · 0219 sea board · 0220 speed ×3 · 0222 board 2.6–3.7 s → 1.1–1.3 s · 0223 every city open + "24 min ago" laps · 0224 stats live to the second (stats_now 0.7–5.6 ms, drift 0). Client: plain words #299, aligned lists #303, labels 47 %/KST clock #298, desk.plan fix #306, selector rule W #304. Main Acceptance green.
| next | branch / PR | state | to finish |
|---|---|---|---|
| **0225** | `osn-trade-r1` **#305** (owner 190/194/203: Trade page, auto supplies) | main merged in (no force-push → no from-zero CI); **CI GREEN 15/15 (2026-10-26 ~21:10 UTC)**; NOT deployed (owner moving PCs: avoid two machines deploying); **all 19 prod checks PASS** (read 2026-10-26: head 0224, every hunk ×1, 4 preset doors, 1 human standing order to back up) | when #305 is green: `~/bin/bv-deploy.sh 305` → after-check: supply_need exists, preset doors gone, a SAIL buys stores |
| **0226** | `osn-price-history` (owner 189/205: bid+ask history, hourly 30 d, daily forever, 1D–All) | **PR #310**, renumbered to 0226 and pushed (70038479); the agent was STOPPED at hand-off, so CI and the remaining checks are unverified: read #310's checks first | PR green → read its PROD CHECKS (pure SELECTs only) → deploy |
After those: R3 mini route map (191) → R4 Report (192) → R2 true reasons + rank sailable buyers first (good_board orders the quoted ten by passage, not `sailable`) → rollover W1–W4 (173) → fleets F1–F7 (180) → sea S3–S6 → live prices → far selling. Smaller: board <1 s (the SELL AT part), stats_now price index + players online.
**Waiting on owner:** the stray prod company "Casa do Segundo 0224" (created by a mis-run check: 8,000 founding ducats, 6 Lisbon sales; keep or remove via a reviewed migration) · #268 pirates · row 175 · archive 10 old cloud sessions on claude.ai.
**Rules learned today (all in memory):** no cloud ever · prod checks: READ each block, run only pure SELECTs, never split a begin…rollback, never edit the check text · self-asserts never count/sum a growing table or compare rollup vs live · after every merge wait for main's Acceptance (bv-deploy.sh does it; the repo copy now too) · rebase/merge then check conflicts BEFORE push; never pipe a gating command · prefer merging main into a PR branch over force-push (force-push makes the next CI run from zero) · migrations deploy in increasing number order; gaps are fine.
- 2026-10-26 ~04:20 UTC: #327 (0233 E3 + 0234 E4, dark) all green; deploy AFTER 0232 (E4 needs it). DECIDED BY DEFAULT: "broke" = PURSE (cash) < 20 % of capital, not worth (purse+cargo) — by worth 0 qualify today, by purse 41. Change the gift pass to read purse in a small slice before E7. Owner may reverse.
- 2026-10-26 ~05:15 UTC: MEASURED merchants net ≈ +18 M/day (trade +42.6 M, back to cities ≈ 25 M: donations 19.7, tax 5.2, rest). Port fee as designed returns only ~1–2 M (estimate). Balancing lever (auto-donation of surplus, or profit tax) PARKED by the owner: "keep building for now. this is not important yet". Revisit before/after the switch with E2 watch figures.

### 2026-10-26 06:52:22 UTC — CLOSED ECONOMY SWITCHED ON (`economy_close_switch(true)`), prod head 0240
- Baseline: world 1,986,693,521 · cities 1,133.7 M · merchants 838.8 M · players 0.22 M · broke 36 · under_reserve 85 · new 24 h +77.7 M.
- +15 min (07:08): moved_since_close +138 (flat) · no_new_gold 0 · sells 550 / city_broke 0 · gifts 34 (189 k) · fees 1,288 (97.8 k) · failed 0 · **under_reserve 85 → 99 (watch; switch back > 150)**. +1 h check queued (~07:53).
- Live today also: 0235 money log, 0236/0237 E4b, 0238 buys-where-she-can-sail (Port Royal), 0240 E7; #333 Buy/Sell tabs, #334 drip, #337 log filters, #331 map chart slide. In flight: #339 compact chart, stats filters, ship full path, arrivals every second (+cost compare), then E5/E6/E6b, N1.
- 2026-10-26 08:05 UTC post-switch diagnosis: (1) tick_stats `recent` jsonb_object_agg drops a duplicate (day,kind) key — every :51 counts per-kind/minted wrong since 0214 → fix `osn-fix-stats-recent-sum` (0243); (2) PORT_FEE ~4,700/h, 1:1 with arrivals (treasury_flows is emptied at :37 — count the ledger/daybook); (3) failed SAILs = merchants short (E_ENDURANCE/E_INSUFFICIENT_FUNDS). Laps −12 % (port prep 60 s; tune `port_prep_seconds` if needed). under_reserve 85→112: cities pay more for sales than they get from buys. NEW: lap SELLs of goods not aboard (E_NO_CARGO) rose 400 → 10,400 per 15 min since 06:15 (before the switch) — look into. Deploy order: 0241 stats-filters, 0242 arrivals-every-second (AFTER the economy watch window settles), 0243 stats fix.
- FLAKE FOUND (2026-10-26 ~08:50 UTC): `tests/db.chain.spec.ts:468` cold boot — 0019 self-assert "the quay predicted 6818 out / 7706 in and the orders moved 6818 / <NULL>" failed once on #343 (run 40292383876); the diagnostic re-run of the same commit passed. 0019 is frozen; the fix belongs in the harness/a forward note. Queue it. #343 (0243) green, deploys after 0241 and 0242.
