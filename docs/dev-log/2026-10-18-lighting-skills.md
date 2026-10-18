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
