# 2026-10-18 — lighting the switches: `skills_bite` (0178), then `crew_bite` — `osn-light-skills`

The owner's order (2026-10-17): research Origin's captains and EVE's skills *"to the fullest … apply it to the
game as well"*. Every skill and captain slice (K0–K10, S12–S18) is live and dark. `docs/SKILLS_AND_CAPTAINS.md` §8
"Lighting order": K0 → `skills_bite` (after §7.6's check) → … → `crew_bite`. One switch at a time, each a tiny
migration, never a raw UPDATE. `combat_bite` and `armour_turns_pct` are NOT lit here (S4's open owner questions).

## Switch 1 — `skills_bite` (0178, `a_company_uses_what_it_has_learned`)

**Not deployed.** Built on origin/main `9260b6b` (prod head 0177); number 0178 = prod head + 1 (renumber if the
head moves before the push).

### Before — what the switch turns on

Read from the LIVE bodies (prod `pg_get_functiondef`, read-only): 41 functions read `skills_bite`. Lit, they:

- add the per-level ship / fitting bonuses of `skill_effects` to a company's own hulls (`world.skill_bonuses` →
  `world.ship_stats`, `world.ship_budget`, `world.ship_view`; 0133, 0149 K0, 0151 K1);
- make `skill_requirements` COUNT the levels held (`public.requirements_unmet`). Dark, no level counts, so a gated
  hull or item cannot be built or fitted by anyone; lit only loosens (whoever holds the levels may);
- turn on the K2 house effects: Factorage, Pursership, Etiquette, Recruiting, Shipwright, Weather Lore, Light-air
  (read at the voyage's departure), Command (hull cap, captains' bonus), Leadership;
- count the K1 company skills (Wholesale, Negotiation, Provisioning, Celestial Navigation). The four live company
  skills (ACCOUNTING, HAGGLING, NAVIGATION, SEAMANSHIP) were never gated and answer as before.

### Before — prod, read-only (2026-10-18 03:14 UTC, head 0177)

**Arrivals sweep** (`cron.job_run_details`, job 1):

| window | runs | avg | p95 | max | failed |
|---|---|---|---|---|---|
| last 30 min | 116 | 2.71 s | 3.87 s | 9.00 s (one run) | 0 |
| since 01:00 UTC | ~530 | 2.7–2.8 s | 3.7–4.2 s per hour | 5.7 s, and the one 9.00 s | 1 ("job canceled", 01:57) |
| last 24 h | 5,441 | 3.20 s | 6.06 s | 21.78 s | 11, all "job canceled" |

§7.6's gate is "p95 under 5 s and max under 8 s" over 24 h. The 24 h window fails it, because it holds the
17:00–23:00 UTC stretch of the 0172–0174 pushes (hourly p95 up to 10.2 s). The hours since 01:00 UTC pass the p95
gate. The max gate is passed in every hour except one 9.00 s run at ~03:0x. Stated, not hidden: **lighting now is
inside §7.6 for the last two hours, outside it for the last 24.**

**Who is affected:**

- **Players**: 17 houses, 20 hulls (18 barca, 2 caravela latina). One skill level between them (NAVIGATION I, a
  live company skill), 0 queue rows, 0 banked SP. **Every player answer is unchanged** (speed, cargo space, stores,
  wage, hiring, hull cap, routes). From the flip on, a skill they learn bites. The refusal sentence drops its
  "— ship skills are not in use yet" tail.
- **Merchants**: 821 houses, 837 fleets, 892 hulls. The four company skills (unchanged), plus S18's hull-line
  skills for the 57 English and French houses (ENG_SMALL/LIGHT/MEDIUM, FRA_SMALL/LIGHT/MEDIUM, I–III). Computed on
  prod from `skill_effects` by each hull's profile (the rule `world.skill_bonuses_at` applies):

  | stat | hulls | fleets | per cent |
  |---|---|---|---|
  | speed (English lines) | 10 | 9 | +2 |
  | handling (French lines) | 52 | 49 | +4 to +12 |
  | reach (French lines) | 52 | 49 | +4 to +12 |
  | accuracy (English lines) | 10 | 9 | +4 |

  Handling, reach and accuracy feed no roll today (only `world.ship_view` shows them; `voyage.escort_score` reads
  `attack`, which no merchant skill touches). No merchant holds a hold, fitting or house skill.

**What changes in answers (expected):** merchant cargo space, stores, wages, haggle, spread, hiring cost, hull
cap, routes: **0 %**. Merchant speed: **+2.07 % on at most 9 fleets** (fleet speed is the slowest hull's), 0 on
the other 828. So **lap profit is unchanged** for 828 fleets and about +2 % (shorter laps, so fewer wage-days) for
9. Players: **0 %** today. Nobody loses a ship, money or an answer. Lit refuses nothing dark allowed.

### Before — simulated (cached world image, origin/main + nothing, PGlite)

`sim-switch.mjs` (scratchpad): every fleet's answers dark, then the switch lit, then again.

- Merchants (837 fleets): speed moved on 9 (max +2.07 %); stores, wage, cargo space, captains' per cents, hull
  cap, routes, 10-hand hiring quote, ship budgets: 0 moved; 300 sampled quay spreads: 0 moved; ship stats
  moved on 58 fleets' hulls (accuracy +4.8 %, handling +4–12 %, reach +4–4.3 %, speed +2–2.07 %).
- Players (13 fleets in the local world): 0 moved.
- Read cost, fastest of 2: merchant speed + cargo space 575 → 797 ms; ship_view 1,385 → 1,908 ms;
  endurance + wage 211 → 238 ms. The extra is the 57 S18 houses' hulls (they hold a SHIP skill, so they take
  the lit branch); every other merchant leaves at K0's probe. Over K0's bound (lit ≤ dark × 1.15 + 50 ms) in
  aggregate, because the lit branch is now run on 58 fleets that K0's measure did not have.
- **The sweep itself** (`sim-tick.mjs`): merchants and city purses switched on as on prod, `time_compression`
  960 as on prod, the backlog drained, then the SAME 15 sailing merchant fleets landed through
  `public.tick_arrivals`, dark and lit, in rolled-back transactions. Clean rounds (before real-time arrivals mixed
  in): dark 1,317 / 2,794 / 2,606 ms vs lit 1,348 / 2,669 / 2,460 ms. **No measurable difference** (±5 %). From
  round 4 on, real arrivals joined the batch and the pairs are not comparable.

Verdict: **no breaking effect.** No merchant economy collapse (one stat moves, by 2 %, on 1 % of fleets), the
sweep does not move measurably, and no player loses a ship. Lighting.

### Flip — 0178

`supabase/migrations/20260818000178_a_company_uses_what_it_has_learned.sql`:

1. Refuses to run if `skills_bite` is already on (its pre-image must be the dark world).
2. Takes every live fleet's answers dark (speed, stores, wage, cargo space, 10-hand hiring quote, the four live
   captains' per cents, hull cap, route cap, ship budgets), every hull's stats, 300 merchant quay spreads, and
   every (player house, requirement subject) unmet count. Times merchant speed + cargo space and ship_view.
3. `update public.world_config set value = 'true'` for `skills_bite` (with its description).
4. Takes the same answers lit, and times them again.
5. A probe on its own throw-away house at Lisbon (rolled back): PRT Small III, Cargo Stowage II, Merchant
   Ships II, Command II, Factorage II, Pursership V, plus every level a gated PRT size-4 hull asks.
6. Asserts:
   - every live merchant fleet's speed is in [dark, dark × 1.05] (S18's ±5 % bound);
   - for every merchant fleet, everything else is the exact pre-image;
   - the 300 sampled spreads are unmoved;
   - no player fleet reads a worse answer;
   - no (player, subject) pair gains an unmet requirement;
   - no hull loses a stat, and no merchant hull's rated hold moves;
   - the probe reads the plan's rows (S11: speed × 1.06, sighting × 1.12; Cargo Stowage + Merchant Ships: hold
     × 1.12; Command II: hull cap + 2; K2: Factorage II gives 2 more routes and Pursership V takes 15 % off the
     wage);
   - the gated hull is refused dark with every level held, and buildable lit;
   - a house that learned nothing reads the same, dark and lit.

Receipt on the cached world (origin/main + 0178, PGlite, 13.0 s):

```
0178 self-assert ok: A COMPANY USES WHAT IT HAS LEARNED — skills_bite thrown true. MERCHANTS (837 fleets): 9 read
a faster speed (max +2.070 %, bound +5 %), 0 moved cargo space, stores, wage, hiring, captains' per cents, caps or
budgets; 0 of 300 sampled quay spreads moved. PLAYERS (13 fleets): 0 moved, 0 worse; requirements over 3809
(player, subject) pairs: 0 tighter, 0 looser. HULLS (908): 62 stats moved (62 merchant: combat stats + the English
lines' speed), 0 fell, no merchant hold moved. PROBE (barca-class, own house, rolled back): lit speed 5.00 → 5.30,
sighting 8.0 → 9.0, hold 60 → 67 (the plan's +6 / +12 / +12 %), fleet 4.9125 → 5.2169 kn; Command II hull cap
8 → 10; Factorage II routes 3 → 5; Pursership V wage 10 → 9; gated hull galeao refused dark with every level held
("Galeão needs Portuguese Heavy Hulls I and Portuguese Medium Hulls III and Ships of War I — ship skills are not in
use yet"), buildable lit; a house that learned nothing reads the same. READ COST over the live merchants (fastest
of 2, notice only): speed + cargo space 577.0 → 744.0 ms, ship_view 1317.0 → 1527.0 ms.
```

(That run printed "max +%2.070": a format slip, fixed before the commit. The build below applied the fixed file.)

**Rollback** (a forward migration, never a raw UPDATE on prod):
`update public.world_config set value = 'false'::jsonb where key = 'skills_bite';` — a house that built or fitted
a gated subject while lit keeps it; a house grown past ship_max under Command is refused `E_SHIP_MAX` on its next
transfer (0133's note).

### Verification (once, fresh worktree, real `npm ci`, warm `node_modules/.cache`, no `.env.local`)

- Cached-prefix `npm run build` (includes `tsc -b`): 169/170 restored from the prefix cache, 0178 applied, world
  guard ok, built. Exit 0. 35.8 s.
- `eslint .`: 0. `npm run db:check-versions`: 170 distinct versions, ok.
- No client change: the client prints what the server serves (`takes_effect`, `bonuses`, the refusal sentence).
  No spec asserts the dark text of `skills_bite`. `tests/ship.cabins.spec.ts` asserts *"Cabin rates are not in use
  yet."*, which is `crew_bite`'s (switch 2), not this one's.

### After (once live) — to measure for 30 min, read-only

Baseline taken at 03:3x UTC, last 30 min: 785 merchant laps closed; 67.0 % at zero or negative net; mean net
5,000.8; mean lap 31.1 min. The same queries after the push: arrivals avg / p95 / max / failed, laps (count,
zero-net share, mean net, mean minutes), and the cron `return_message` of every failed run.

## Switch 2 — `crew_bite` (before only; not built until 0178 is live)

Prod, read-only:

- 511 merchant signings: all seated, each with exactly one active trait (her job, 0 others), all in a full-rate
  seat (210 exploration-in-exploration, 299 trading-in-trading, 2 in the Captain's cabin), 0 with a
  `captain_state` row (so never homesick, never above birth grade).
- 1 player signing: not seated. So lit it adds nothing to any player fleet today.
- Effects of the merchants' jobs: NAVIGATOR → speed, PURSER → spread, QUARTERMASTER → hold, SURGEON → crew_saved
  (all live) and homesick_relief (counted only for a homesick captain, never for a merchant).

Simulated on the cached world with 0178 applied (skills lit): every merchant and player answer unmoved (speed,
stores, wage, cargo space, the four per cents, supplies, caps, hiring, budgets, stats, 300 spreads). Read cost:
merchant speed + cargo space 734 → 891 ms (+21 %), endurance + wage 189 → 248 ms (+31 %, `crew_pct('supplies')`
now walks the lit terms), ship_view 1,623 → 1,648 ms.

## Switch 1 — after: 0178 LIVE (prod head 0178, `skills_bite` true, read at 03:51 UTC; 8 cron jobs active)

Read-only, 30 min after (03:52–04:22 UTC) against the 30 min before (03:20–03:50 UTC):

| measure | before | after | bound | holds |
|---|---|---|---|---|
| arrivals runs | 116 | 121 | — | |
| arrivals avg | 2.74 s | 2.91 s | ≤ 3 s (§11) | yes |
| arrivals p95 | 3.90 s | 3.91 s | < 5 s (§7.6) | yes |
| arrivals max | 4.66 s | 9.56 s, one run at 03:52:55, in the push (03:50:55 and 03:51:10 ran 10.3 s) | < 8 s | once, at the push; 0 runs over 8 s after it |
| failed cron runs, every job | 0 | 0 | 0 | yes |
| merchant laps closed | 726 | 798 | — | |
| zero-or-negative net | 68.5 % | 67.0 % (baseline 67.0 %) | unchanged | yes |
| mean lap net | 3,980 | 6,305 | not lower | yes |
| mean lap | 30.1 min | 31.2 min | — | |
| refusals (skipped lines) | E_UNAVAILABLE 297, E_PRICE_LIMIT 258, E_HOLD_FULL 49, E_NO_CARGO 23, E_INSUFFICIENT_FUNDS 6 of 2,584 done | 643, 443, 65, 23, 14 of 5,114 done | same shares | yes (11.5 → 12.6 %, 10.0 → 8.7 %) |
| E_ENDURANCE SAILs | ~10–14 an hour since 22:00 UTC yesterday | 8 in 30 min, the same fleets (c4e54338, 4476d661, 92fdecc4, daafd9e8 …) | — | not caused by 0178 (stores asserted unmoved for every merchant) |

- **Order volume** doubled across the window (2,584 → 5,114 done). It has been climbing since 02:00 UTC (140 → 2,261 per
  10 min), so the climb started before 0178.
- **E_ENDURANCE status**: the eight after 04:07 read `failed` instead of `cancelled`. That is their age: 0150 leaves a
  refused lap `failed` until the next clear answers it. Every older one has been answered.
- **The 9 faster English fleets**: speeds now 5.04–6.45 kn. Each closed 0–1 laps in the window, so the sample is too
  small for lap economics. Lap minutes equal or shorter (25.8 vs 23.7, 32.5 vs 35.3, 25.0 vs 25.8, 26.0 vs 26.2, 108.2
  vs 108.5, 24.8 vs 25.1).
- Two of the nine (4476d661, 92fdecc4) are among the E_ENDURANCE fleets, before and after the flip alike.

**Verdict: every bound holds. No rollback.**

## Switch 2 — `crew_bite` (0179, `a_captain_works_where_she_sits`)

**Not deployed.** Built on origin/main `d432aaf` (prod head 0178); number 0179 = prod head + 1.

### Flip — 0179

1. Refuses to run if `crew_bite` is already on, or if `combat_bite` is on.
2. For every live fleet, takes these answers dark:
   - speed, stores, wage, cargo space;
   - the captains' per cents for speed, spread, hold, crew_saved, supplies and storm;
   - every live-effect crew term, row by row, rounded to 8 places (the dark and lit branches differ only in numeric
     scale).
   Also takes 300 merchant quay spreads, and times merchant speed + cargo space and endurance + wage.
3. Throws `crew_bite` true (its description says so).
4. Takes the same answers lit, and times them again.
5. A probe on its own house at Lisbon (rolled back). It signs a Navigator who speaks Lisbon's language and seats her:
   - in the Captain's cabin: 100 %;
   - in an off-focus cabin: × `cabin_off_focus_pct`, 50 %;
   - homesick for 73 h with no Surgeon: × (1 − 20 %);
   - haggle odds with her fleet: + `language_haggle_points`.
   Dark, the same three states read her whole job value and the odds unchanged. The cabins note is gone lit and
   present dark.
6. Asserts for every live merchant fleet: every answer and every live-effect term is the exact pre-image (K5's row);
   0 of 300 spreads moved. Players are reported, not bounded.

The Surgeon's `homesick_relief` term appears in the lit term list for the 12 merchant fleets that carry one. It is
read only for a homesick captain, and no merchant has a home clock (O8). So it is left out of the row-by-row
comparison and said so in the file. The answers it could move (crew_saved, the homesick factor) are compared.

Receipt on the cached world (origin/main + 0179, PGlite, 8.1 s):

```
0179 self-assert ok: A CAPTAIN WORKS WHERE SHE SITS — crew_bite thrown true. MERCHANTS (837 fleets, 498 with
captains): 0 moved (…); 0 of 300 sampled quay spreads moved. PLAYERS (13 fleets): 0 moved. PROBE (own house,
CABRALNAV on a barca, rolled back): Captain's cabin speed 0.075 (job 7.50 %, dark and lit); off-focus cabin 2 →
0.0375 lit (× 50 %), 0.075 dark; homesick 73 h 0.060 lit (× 80 %), 0.075 dark; speaks Lisbon's language: odds
0.4500 → 0.5000 with her fleet lit, unchanged dark; the cabins note gone. READ COST over the live merchants
(fastest of 2, notice only): speed + cargo space 662.0 → 862.0 ms, endurance + wage 193.0 → 265.0 ms.
```

**Client seam**: `world.ship_seats` stops serving "Cabin rates are not in use yet." The ship panel prints the server's
note, so `tests/ship.cabins.spec.ts` now asserts that the sentence is absent. That lands in the same PR. No client
code changes.

**Rollback** (a forward migration): `update public.world_config set value = 'false'::jsonb where key = 'crew_bite';`.
No table changes here, so nothing written lit is unreadable dark.

### Verification (once; worktree re-made off `d432aaf`, real `npm ci`, prefix cache from `bv-circ`, no `.env.local`)

- Cached-prefix `npm run build` (with `tsc -b`): 170/171 restored, 0179 applied, world guard ok. Exit 0.
- `eslint .`: 0. `db:check-versions`: 171 distinct, ok.
- `tests/ship.cabins.spec.ts` on a local PGlite preview (`localhost:4247`): 1 passed, 0 skipped.

### #208 round 2 — proof 6 red, and the merchant sheet spec

**Proof 6 red** (`pglite-gate (the rest)`, run 39096990249):

```
PROOF 6 FAILED: with a 25 per cent purser and a 0.75 concession the executed spread is 0.005… and the floor is 0.004…; the floor did not hold
```

- **The cause, from the code:** it is (a), the intended lit rule. It is not a defect.
  - Lit, `public.crew_terms` counts a captain through the traits she USES, joining `public.captain_active` (D15 / §4.2:
    she knows 4–10 traits and uses 2–5).
  - Dark, it reads her job alone.
  - Proof 6 authors its 25 % purser by hand (officers + profile + traits + signing + seat) and never writes a
    `captain_active` row. So lit she uses no trait and gives 0 %. That is why the spread stayed at the
    concession-only 0.005, above the floor.
- **No real path writes a signing without active traits.** `sign_officer` makes her first traits active (K5). On
  prod, every one of the 512 signings (511 merchant, 1 player) has an active row.
- **The fix is in the proof:** it now states the precondition itself (`captain_active (signing, 'PURSER')`). She sits in
  the Captain's cabin (100 %), has no home clock (never homesick), and is at her birth grade. So dark and lit she
  gives the same 25 %, and the floor assertion is unchanged.
- **The whole class:** the only other hand-authored signing is in `03_grant_lockdown.sql:393`. It passed in CI, because
  it tests a grant, not a bonus. No spec inserts `player_officers`.
- **Why my checks missed it:** the cached-prefix `npm run build` applies migrations and runs their self-asserts. It
  does not run `scripts/db/proofs/*` — that is `npm run db:proof`, which I never ran for 0178 or 0179. My checklist
  had build, tsc, eslint and the one changed spec, but not the proof suite. A migration that flips a switch changes
  the world every proof runs in, so the proof suite belongs in the checklist for every switch-flip.

**`tests/map.merchants.spec.ts`**: "… a tap opens a read-only sheet" expected 4 `skill-*` tiles and got 6.

- **The sheet is right.** `world.npc_fleet_card` serves the four skills that need no enrolment plus every skill the
  house HOLDS, and it does not read `skills_bite`. S18 (0167) fixed hull-line skills for the English and French
  houses. On prod, 764 merchant houses' cards serve 4 tiles, 14 serve 5 and 43 serve 6, whatever the switch says.
- **The pinned 4 was an ambient-default assertion.** It held only while the merchant the spec happens to open was a
  four-skill house. My inference, not proven: lit speed changed which merchant that was.
- **The spec now derives the truth:**
  - every `enrol: "none"` skill of `data/skills.json` has its tile;
  - there are at least that many tiles;
  - every other tile is a skill she holds (its bar reads level ≥ 1).
- It lands in #208, because it is the same lit-world class.

**Round-2 checks (once):**

- **The whole proof set on the 0179 chain: 12/12 files green, every declared marker.**
  - World: the cached BROWSER world image (origin/main + 0179). Fixtures: `proof-courses` and `market-fixture`
    installed as `proof.mjs` installs them. Each file ran in begin … rollback, judged by its own `@pass` markers.
    Runner: a scratchpad copy of `proof.mjs`'s rule. Wall clock: 8 m 52 s.
  - Results: 01 6/6, 02 6/6, 03 12/12, 04 9/9, 05 5/5, 06 10/10, 07 6/6, 08 6/6, 09 4/4, 10 10/10, 11 5/5, 12 6/6.
- **`npm run db:proof` itself (the preamble variant) could not build a world here, and that is a separate finding.**
  - This machine had no preamble prefix past 0128. From zero (33 min), and again from the 0128 snapshot it wrote, it
    fails in **0137**: `0137 self-assert FAIL: the quay probe priced 4 / 4 of 4 harbour(s), or one served no goods`.
  - It failed the same way twice. CI passes only because it restores a prefix past 0137.
  - That is an old migration whose self-assert does not reproduce on a fresh apply today. The nightly from-zero run
    (`23 18 * * *`) may meet it too. Not caused by 0178 / 0179; reported.
- `tests/map.merchants.spec.ts` "… a tap opens a read-only sheet" on a local PGlite preview (`localhost:4248`):
  1 passed. The tapped merchant's tile count is not printed, so this run does not show whether the >4 branch ran.
- `eslint tests/map.merchants.spec.ts` and `tsc -b`: 0.
