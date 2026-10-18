# 2026-10-18 — 0189: a raid is fought in rounds (DARK), and 0190: the raids are fought (the switch) — `osn-auto-fight`

**The owner, 2026-10-18 ~13:40 UTC (verbatim):** *"yes lets do a automatic fight, so that range and accuracy is
an important factor. … yes shoals and damage too."*

Text and tabs; no visual combat, ever; the map only shows. Today a raid is DESIGN B.6's one ratio in
`voyage.settle`'s PIRATES arm: escort against raider, five bands. 0168 (S4 + K10,
`2026-10-18-s4-k10-combat-stats.md`) made the escort read what a ship carries and added
`voyage.escort_score`, `public.armour_turns` and the Gunner / Boarder ship effects, all behind `combat_bite`
(off) and `armour_turns_pct` (0). Its "not in this slice" list is this slice: accuracy, reach and sighting
fed no roll, and SHOAL_WATER's loss was un-armoured.

**Numbers.** First cut as 0183, then 0185 and 0187 as main moved. The coordinator then fixed the deploy
order: 0187 great powers, 0188 plan-reach-2, **0189 this dark slice**, **0190 its switch**, 0191 P2 volume,
0192 P3 stake. **Not deployed.** 0190 is on its own branch and goes in only after 0189 is live and measured.
Both are rebased onto main once 0188 is live, and their hunks are re-checked then (the great powers touch
`world.snapshot` and `allegiance`, not these bodies).

## The design — one combat authority, three functions

| Concept | Its one home | Read by |
|---|---|---|
| the fight | `voyage.fight_resolve(voyage, day, raider, escort, ships)`: a pure function of its arguments, the `fight_*` knobs, `armour_turns_pct` and the world secret | `voyage.fight` |
| the fleet, as the fight sees it | `voyage.fight(voyage, day, fleet, raider)`: `world.ship_stats` for every hull (class, gear, company skills, seated captains), her hull and crew, the Boarder's share (`crew_pct 'attack'`, K10), the Boarder and the Gunner by name, and the gear whose `item_use.trigger` is PIRATES. Refused while `combat_bite` is off. | `voyage.settle` (PIRATES, lit) |
| the armour formula | `public.armour_soak(armour, loss)`: loss × (1 − armour / 100 × `armour_turns_pct`), ≥ 0. `public.armour_turns` (0168) now composes it, for a hull. | `armour_turns`, `fight_resolve` (for the raiders, who are not a hull) |

**A fight, in order** (all chances are `voyage.rng` streams of (voyage, day), like the hazard roll, so a
re-settle writes the same fight word for word):

1. **The raiders.** The hazard's strength is unchanged: DESIGN B.6's `piracy × 40 × (0.5 + magnitude)`. It is
   read as hulls of one class (`fight_raider_class`, the xebec): strength ÷ that class's own escort score.
   Their accuracy, reach, armour, sighting, attack, hull and crew are that class's figures. Nothing new is
   invented.
2. **Sizing up.** Raiders do not close on a fleet whose escort is `fight_standoff_ratio` (2.0, DESIGN B.6's
   own EVADED band) times their strength. Result: EVADED, no shot fired.
3. **Sighting.** The better lookout gets the first round alone: the fleet's best sighting against the class.
   A lead may let the fleet slip away (`fight_evade_per_sighting` per point, capped at `fight_evade_max`).
4. **The rounds.** `fight_ranges`: 3 × LONG (0.6), 2 × MEDIUM (0.8), 1 × CLOSE (1.0).
   - **Range** decides who fires. At LONG range only guns whose reach is at least the other side's fire.
   - **Accuracy** decides the hit: accuracy / 100 × the range's share, 5–95 %.
   - **Attack** decides the damage: attack × `fight_damage_per_attack` × (0.75–1.25).
   - **Armour** soaks it (`armour_soak`).
   - The raiders' shots fall on the hulls by their size.
   - They break off at `fight_raider_break` of their hull lost: EVADED if they never touched the fleet,
     DRIVEN_OFF if they did.
5. **The boarding** comes if they have not broken off. Each side's hulls count (crew × `fight_hand_value` ×
   (1 + the Boarder's share) + tier × 3) × the share of hull left. These are DESIGN B.6's crew and size
   terms, with a hand weighed for a fight hand to hand. The ratio is read against `fight_board_bands`
   (DESIGN B.6's own 1.2 / 0.7 / 0.3): DRIVEN_OFF, RANSOM, PLUNDERED, STRIPPED.

**What an outcome costs stays DESIGN B.6's**, in `voyage.settle`: crew by `raid_crew_lost` (2 / 10 / 30 %,
with the Surgeon), and cargo stripped on STRIPPED. Two things change, lit only:
- **Hull.** The fight writes each hull's loss from the hits it took, whatever the outcome. Dark, it is
  DESIGN's fixed 5 % / 20 %, as before.
- **The day's sentence.** It is the fight's own, true of that fight: "They came alongside and we threw them
  back.", "They broke off and ran.", and so on. The table's "We fired twice and they sheered away." would
  contradict the rounds printed under it. The first canary drive showed exactly that, and this was changed
  because of it.

**Every consumer of the outcome is unchanged**, because the five outcomes are unchanged: `fight_points`
(experience and the Combat track), `wear_units_for` (PIRATES days), `voyage_xp_tracks`, `report_line`
(PIRATES prose: `prose`), `raid_crew_lost`.

**Shoals** (the owner's "yes shoals and damage too"): SHOAL_WATER's loss now goes through
`public.armour_turns`, as STORM's does. At `armour_turns_pct` 0 it is the loss itself.

## The battle report

- **The day's payload** (PIRATES, lit only) carries `rounds`: a list of sentences, plain words per
  `docs/WORDS.md`. It also carries `fight`: {raiders {class, ships, crew, damaged_pct}, first, rounds_fought,
  hits, hull_lost}. Its `prose` is the fight's own sentence.
- **The VOYAGE_REPORT** carries `fights`: [{line, rounds}], where `line` is the index into `lines` of that
  day's "Day N. Sail sighted …" sentence. It is present only when a fight was fought, so **a dark report is
  the old report to the byte**.
- **The History tray** (`LedgerScreen.tsx`, reader `payloadFights` in `headline.ts`) hangs each fight under its
  day's line as an indented list, one round to a line. It is client text only: the server's words, never
  re-worded.

A real fight from the probe (0189's receipt on the 0184 world, lit, rolled back):

```
Day 1. Sail sighted to windward. They came alongside and we threw them back.
  Raiders: one small Galeão, 14 crew.
  Ready for them: Prova Nau (Broadside Guns).
  Niccolò Tartaglia lays the guns on Prova Nau.
  Both sides saw each other at the same moment.
  Round 1 · close range — you miss with 1 shot; they hit Prova Nau for 1% damage (armour turned 15%).
  Round 2 · close range — you hit with 1 of 1 shot; they miss. The raiders are 41% damaged.
  Round 3 · close range — you hit with 1 of 1 shot; they hit Prova Nau for 1% damage (armour turned 15%). The raiders are 67% damaged.
  Close quarters: they come alongside — your 68 crew against their 5. Turgut Reis leads the crew on Gaivota (+9%). You throw them back.
```

(The probe forces galleon raiders, close range and no break-off, so its fights always take some hull to
count. The live knobs are in the table below.)

**In the game** (a canary build, not committed: the dist built with one extra local file that lights combat
and makes every sea-day a raid; a fresh browser world; the founding barca Gaivota sent Lisbon → Cadiz from
the map; History opened on the arrival): `2026-10-18-auto-fight/battle-report-390.png` and
`battle-report-1440.png`. The barca has no guns, so it reads "you have no guns to answer with" and is
decided at the boarding. Day 1 is "They came alongside and we paid them off." and day 3 is "They came aboard
and took what they could carry. We buried 1 of the crew."

## Balance — measured, not reasoned

Production's real fleets, exported read-only on 2026-10-18 13:39 UTC (`begin transaction read only`; every
function called is `provolatile` s or i):

- 854 fleets, 915 hulls, every hull's `world.ship_stats`.
- 830 hulls carry gear that works on a PIRATES day.
- No Gunner or Boarder is seated anywhere.

There are two samples:

- **PROD RAIDS**: production's own 303 PIRATES days (2026-10-16 14:40 → now; all merchants), each replayed
  with its recorded raider strength.
- **SYNTH**: every fleet × 24 raider strengths drawn from those 303.

**BEFORE** is what production rolls today: DESIGN B.6's table on the dark escort. **AFTER** is the fight
with the knobs below and `armour_turns_pct` 0.5. The simulator is scratchpad `fight/sim.mjs`: PGlite on the
0181 world image, with 0189's readings applied. It calls `voyage.fight_resolve` on the exported hulls.

**The knobs, as landed** (every one **NOT the owner's — confirm**). Tuned over 11 settings:

| knob | value | why |
|---|---|---|
| `fight_raider_class` | xebec | the Barbary corsair; its own figures |
| `fight_ranges` | 3 × LONG 0.6, 2 × MEDIUM 0.8, CLOSE 1.0 | enough long-range rounds that reach matters |
| `fight_damage_per_attack` | 0.7 | hull lost overall stays near today's |
| `fight_raider_break` | 0.15 | gunnery can end a fight (at 0.35 almost every fight went to a boarding and guns barely counted) |
| `fight_hand_value` | 0.15 | a xebec carries 35 hands to a carlat's 12; heavier hands strip more merchants (0.2: stripped 14.6 %, 0.3: 15.1 %) |
| `fight_standoff_ratio` | 2.0 | DESIGN B.6's EVADED band |
| `fight_evade_per_sighting` / `fight_evade_max` | 0.03 / 0.30 | |
| `fight_board_bands` | 1.2 / 0.7 / 0.3 | DESIGN B.6's bands |

**Outcome shares, BEFORE → AFTER (%):**

| sample | n | evaded | driven off | ransom | plundered | stripped |
|---|---|---|---|---|---|---|
| PROD RAIDS | 303 | 21.8 → 43.2 | 24.1 → 12.9 | 20.1 → 13.9 | 25.7 → 20.1 | 8.3 → 9.9 |
| SYNTH, merchants | 20,088 | 21.4 → 44.0 | 23.6 → 12.4 | 17.2 → 10.7 | 30.2 → 22.0 | 7.6 → 10.9 |
| SYNTH, players | 408 | 3.2 → 3.4 | 3.9 → 11.3 | 16.7 → 24.5 | 38.0 → 30.4 | 38.2 → 30.4 |

**Loss rates, BEFORE → AFTER:**

| sample | crew lost (% of hands, per raid) | hull lost (% of the fleet's, per raid) |
|---|---|---|
| PROD RAIDS | 5.53 → 5.24 | 6.08 → 7.75 |
| SYNTH, merchants | 5.78 → 5.72 | 6.92 → 7.66 |
| SYNTH, players | 15.35 → 12.38 | 7.76 → 13.43 |

**Win rate (evaded + driven off) by fleet strength (dark escort), SYNTH:**

| escort band | n | won | lost (plundered + stripped) | hull lost % |
|---|---|---|---|---|
| < 5 (barcas: no guns) | 3,600 | 1 → 8 | 85 → 68 | 7.8 → **15.1** |
| 5–10 (carlats) | 11,952 | 43 → 54 | 40 → 37 | 9.1 → 8.5 |
| 10–20 | 480 | 63 → 78 | 11 → 8 | 3.1 → 3.2 |
| 20–40 (naus) | 4,296 | 80 → 96 | 0 → 0 | 1.0 → 0.4 |
| 40+ | 168 | 100 → 100 | 0 → 0 | 0.4 → 0 |

**Better guns, accuracy and range win more often.** Production's commonest hull (a lone carlat with
Boarding Gear) is tested against its 10,608 synth raids with one figure changed:

| variant | won % | lost % | hull lost % |
|---|---|---|---|
| as it is (attack 55, accuracy 40, reach 25, armour 12, crew 12, sighting 10) | 54.0 | 36.7 | 8.6 |
| reach 60 (outranges the xebec's 26) | 61.2 | 31.3 | **4.7** |
| accuracy 70 | 64.9 | 30.1 | 8.5 |
| attack × 2 | 71.9 | 25.4 | 7.1 |
| armour 40 | 54.2 | 36.1 | 7.3 |
| crew 30 | 57.7 | 27.8 | 8.5 |
| sighting 16 | 60.9 | 31.0 | 6.3 |

**Verdict.**

- **Overall, loss rates are in the same band.**
  - Crew lost per raid is unchanged: 5.8 → 5.7 % for merchants.
  - Hull lost rises a little: 6.9 → 7.7 %.
  - More raids end with nothing taken: 38 → 33 % lost for merchants.
  - Stripped rises a little: 7.6 → 10.9 %.
- **No mass merchant losses.** No outcome takes a ship. The flagship is never taken, as before.
- **Guns, accuracy and range clearly win more often.**
  - Each of attack, accuracy, reach and sighting raises the win rate by 6–18 points.
  - Reach alone halves the hull a carlat loses.
  - Armour lowers hull lost by about 15 %.
  - Crew and a Boarder lower the share lost at a boarding.
- **Two shifts are stated, not hidden:**
  - **An unarmed barca loses twice the hull it did** (7.8 → 15.1 % per raid). The raiders fire every round
    and it cannot answer. It is boarded less successfully, though: lost 85 → 68 %.
  - **The 17 player fleets** (mostly that barca) lose less crew and cargo (stripped 38 → 30 %) and more
    hull (7.8 → 13.4 %).
- **EVADED doubles and DRIVEN_OFF halves.** Lit, the escort counts gear, so raiders stand off from more
  fleets (S4). A raider broken off without landing a hit is EVADED. Combat experience comes from both
  (`fight_points`), so its total moves with those shares.

## Proof — 0189's own receipt

It applied in three worlds, green each time:
- the cached-prefix `npm run build` (main at 0186 + 0189);
- the 0184 browser world;
- the **prod-shaped** world. That is `bv-harness/laps-scratch/prodlike.mjs` on main's 0186 snapshot, with
  prod's knobs, stocks, purses, treasuries and 1,491 loops (prod-state of 2026-10-18 18:26 KST). The receipt
  applied in 32.9 s there.

Each world has its own world secret, so its engine numbers differ; the properties held in all three.

The probe uses its own company at Lisbon: the founding barca, a nau with broadside guns, Turgut Reis (Boarder)
on the barca and Tartaglia (Gunner) on the nau. Its passages Lisbon → Funchal make every day a hazard of one
kind. That is done through **its own voyage's** `hazard_mult`; the other kinds' `mix_base` is set to 0.0001,
the column's least. All of it is rolled back.

- **Dark: three passages settled by the old body and the new alike.** The three are all raids, all shoals,
  and one as the sea deals it. Compared: events, hulls, crew, cargo, report, experience, wear and purse.
- **Lit:**
  - every raid day is fought in rounds;
  - the report's `fights` sit at their days' "Day N. Sail sighted" lines;
  - the hull the fights said they took = the hull that went;
  - one day read twice gives the same fight;
  - the Gunner, the Boarder and the gear are named;
  - shoals lose less with armour at 0.5.
- **The engine** (300 days, fixed seed, a crafted carlat-like hull). Each of these wins more or loses less
  than the base: reach 60, accuracy 70, attack 110, armour 50, crew 40, a +50 % Boarder. An unarmed hull wins
  less; a fleet twice the raiders is never fought; no raiders, no fight.
- **Readers.**
  - `armour_soak` is read by `armour_turns` and the core only.
  - The core is read by `voyage.fight` only.
  - `voyage.fight` is read by `settle` only.
  - `armour_turns` is still read by `settle` alone.
  - A planted reader is seen.
- **Bodies.**
  - Two bodies reverse to their pre-images, with ACL, volatility, definer and config unmoved.
  - Eleven neighbours are untouched.
  - The nine knobs are present.
  - There is no entry point, and no client can execute a new function.
- **Hunks against production** (read-only, 2026-10-19 at head 0186): every hunk (7 in `settle`, 1 in
  `armour_turns`) occurs exactly once in the live `pg_get_functiondef`, and its new text does not occur. The probe's needs are there: LIS and
  FNC anchorages; Turgut Reis and Niccolò Tartaglia; broadside-guns; nau, xebec, galeao and barca; PIRATES
  and SHOAL_WATER in the mix. The probe company id is unused. The `fight_*` knobs are absent.
- **The fleet-gathering read on production** (what `voyage.fight` reads, `crew_pct` aside: it is refused dark):
  915 hulls, 830 with raid gear, 0 Boarders, 0 Gunners, max attack 200, 2.2–2.4 s for all of them.

## Cost — the arrivals sweep

**A fight is read only on a PIRATES day of a fleet that is landing.** On production that is 303 days in 47 h
across every fleet, about 6 an hour, against about 240 sweeps an hour: roughly one fight per 38 sweeps.

**What one fight costs:**
- PGlite (notice of 0189's receipt, over 200 merchant fleets): 13–37 ms. The range is the load on this
  machine during the runs.
- Production, read-only: the same per-hull reads (`ship_stats`, `crew_terms` twice, the gear) for all 915
  hulls took 2.2–2.4 s, about 2.5 ms a hull.

So a landing raid adds a few ms to one sweep in ~40. **Dark, the sweep runs exactly the old arithmetic**, plus
one inlined `combat_bite_on()` read per raid day and one `count(*)` over the landing voyage's events for
`fights`.

**`sim-tick.mjs`** (15 merchant landings, dark vs lit, rolled back, on the prod-shaped clock and switches) was
**not a clean measurement**. The machine was shared with three sibling agents' proof suites. Most sweeps ran
into `arrivals_tick_budget_ms` (10 s) both dark and lit, with a backlog of 16–352 real landings per sweep.
- Normal: avg 8.86 s dark vs 8.80 s lit.
- Every landing day a raid: 10.12 s vs 10.13 s.

Indistinguishable, but budget-bound. **The bound (avg ≤ 3 s, p95 < 5 s) can only be judged on production**:
it is in 0190's 30-minute after-check.

## Verification (once each; worktree off origin/main, real `npm ci`, warm `node_modules/.cache`, no `.env.local`)

- Cached-prefix `npm run build` (with `tsc -b`) on main at 004b906: 176/179 restored; main's 0185 (faith)
  and 0186, then 0189, applied; the world guard ok. Exit 0.
- `eslint .`: 0. `db:check-versions`: 178 distinct.
- `tests/ledger.fights.spec.ts` (new; the seam, node-side on the built image): 2 passed.
  - Lit: every raid day is fought in rounds, and `payloadFights` finds each fight under its "Day N. Sail
    sighted" line.
  - Dark: no rounds and no `fights`.
- `tests/layout.spec.ts` + `tests/wide.layout.spec.ts` (CI rule L, a changed `.tsx`) on a preview at
  `localhost:4300`: 25 passed, 0 skipped, 0 failed.
- `scripts/db/proofs/*` on the built image: see the PR.
- Screenshots at 390 and 1440, from the canary drive above.

## Not the owner's — confirm

- **Every fight knob above**, the raider class first. One class for every sea; a class per sea, such as
  Caribbean or South China Sea raiders, is data the owner may want.
- **Sizing up** (raiders do not attack a fleet twice their strength) and the **boarding formula** (DESIGN's
  crew and tier terms, with a hand weighed 0.15).
- **"Ship taken" is not built.** The brief listed it among the outcomes. DESIGN B.6 says "the flagship is never
  captured", and taking any hull would delete a ship with its gear and captains. That is the owner's call. The
  five outcomes are unchanged.
- **Gear is named, not spent.** The PIRATES gear is named in the report, and its stats count through
  `ship_stats`. Its consumables (shot and powder) are not spent: `gear_actives_bite` has no row, and no gear
  active is invented.
- **Unarmed hulls take more hull damage**: the barca's 7.8 → 15.1 % above.

## 0190 — the switch (separate branch; push only after 0189 is live and measured)

**Receipt on the prod-shaped 0189 world** (applied in 25.2 s): the probe's 5 raid days were fought in rounds;
shoals 940.78 → 821.06 hull. Measured, not asserted (800 merchant fights, raiders 4 / 9 / 16 / 24):
- won 32.1 → 45.0 %;
- lost 43.1 → 40.6 %;
- stripped 7.8 → 14.8 %;
- hull lost 10.1 % of the fleet's;
- a storm over 908 hulls 117,145 → 103,977 hull points.

Its fixed raider set leans heavy (24 is the top of production's range), so its shares sit above SYNTH's, which
draws from production's own raids.

`update world_config` for `combat_bite` true and `armour_turns_pct` 0.5 (SHIPS_AND_GEAR §5's probe value). The
method follows `2026-10-18-lighting-skills.md`:

1. It refuses unless the world is dark and 0189 is present.
2. It measures 200 merchant fleets × 4 raider strengths before (the old roll) and after (the fight), and a
   storm's loss for every hull. These are **notices only**: production's fleets are not its probe rows.
3. It throws the two switches.
4. It asserts on its own probe company (rolled back): a raid passage is fought in rounds with the report's
   fights at their lines, and every shoal day takes exactly what `armour_soak` leaves of the knob-0 loss, and
   less.

**Rollback** is a forward migration with the two UPDATEs back. Nothing written lit is unreadable dark.

**The 30-minute after-check, read-only, against the 30 minutes before:**

- arrivals avg / p95 / max / failed (`cron.job_run_details`, job 1);
- PIRATES days and their outcome shares, `payload ? 'rounds'` on every one;
- hull lost per raid;
- merchant laps (count, zero-or-negative share, mean net);
- REPAIR orders.

**The bounds:**

- arrivals avg ≤ 3 s and p95 < 5 s;
- no failed run;
- lost (plundered + stripped) share not above today's + 5 points;
- crew lost per raid not above today's + 1 point;
- mean lap net not lower.

## Live — 0189 dark, then 0192 lit, and the after-check (2026-10-18, read-only)

0189 went live at ~16:03 UTC, still dark. 0192 went live at ~16:51 UTC: `combat_bite` true, `armour_turns_pct` 0.5.
The windows are 15:30–16:00 (before 0189), 16:05–16:35 (0189 dark) and 16:52–17:22 (0192 lit).

| measure | before | 0189 dark | 0192 lit | bound | holds |
|---|---|---|---|---|---|
| arrivals runs | 116 | 116 | 117 | — | |
| arrivals avg | 2.80 s | 2.95 s | **3.18 s** | ≤ 3 s | **no** |
| arrivals p95 | 3.89 s | 3.98 s | 4.54 s | < 5 s | yes |
| arrivals max | 6.85 s | 6.36 s | 6.77 s | — | |
| failed runs | 1 ("job canceled") | 1 ("job canceled") | 1 ("job canceled") | 0 | as before (one in each window) |
| PIRATES days | 17 | 17 | 24 | — | |
| fought in rounds | 0 | 0 | 24 | every day | yes |
| won (evaded + driven off) | 47.1 % | 58.8 % | 75.0 % | — | |
| lost (plundered + stripped) | 35.3 % | 17.6 % | 20.8 % | ≤ dark + 5 | yes |
| crew lost per raid | 7.35 % | 5.51 % | 5.21 % | ≤ dark + 1 | yes |
| mean hull a fight took | — | — | 27.9 points | — | |
| merchant laps closed | 450 | 470 | 390 | — | |
| lap net ≤ 0 | 52.9 % | 48.3 % | 52.6 % | — | |
| mean lap net | 17,034 | 11,005 | 33,278 | not lower | yes |
| REPAIR orders | 22 | 37 | **70** | — | |
| VOYAGE_REPORTs with `fights` | 0 / 1,095 | 0 / 1,091 | 15 / 987 | — | |

**0189 dark held** in every check:
- No day was fought.
- Every raid outcome is the old ratio table from that day's own escort and raider.
- Every shoal day equals the knob-0 formula.
- No report carries `fights`.

**0192 lit:** every raid was fought in rounds, and the raid bounds held. **The arrivals average broke its bound: 3.18 s
against 3 s.** At the mid-window read (17:07) it was already 3.12 s.

**Cause: not established.**
- Fights alone are about 24 in 30 minutes at a few ms each, which is far less than the 0.2 s per run the average rose by.
- 0193 and 0194 also reached production after 0192 (prod head was 0194 at ~17:25). I did not establish when, so I
  cannot say whether their pushes fell inside the window.
- REPAIR orders doubled (37 → 70). That is consistent with fights now taking hull from more raids (EVADED / RANSOM
  days took no hull before), and repairs are work the arrivals sweep does.

The method says a broken bound is a rollback, so **0195 (`the_raids_are_rolled_back`) puts both switches back** as a
forward migration. Nothing written while lit becomes unreadable: the days keep their rounds, and History keeps
printing them.

## Why the sweep rose — and 0198 (perf, dark), then 0199 (the switch again)

(Numbered 0197 / 0198 when written. 0197 went to "a merchant's route always pays", so these are now 0198 and 0199 by the coordinator's order.)

The clean lit window (17:25–17:52, no deploys) averaged 3.07 s. 0195 rolled the fight back at ~17:52. Dark again
(17:52–18:02), the sweep still averaged 3.04 s. So the fight was not the only cost.

### Production, read-only (`cron.job_run_details`, job 1, 10-minute bins; push times from `~/bv-push-logs`)

| window (UTC) | what was live | avg | p10 | p50 | p90 |
|---|---|---|---|---|---|
| 13:00–14:10 | ≤ 0181 | 2.11 s | 1.38 | 2.07 | 2.98 |
| 15:20–15:50 | 0182–0186 | 2.85 s | 2.22 | 2.80 | 3.65 |
| 16:20–16:45 | 0187–0191, combat dark | 2.80 s | 2.13 | 2.70 | 3.49 |
| 17:55–18:10 | ≤ 0195, combat dark | 2.88 s | 2.20 | 2.85 | 3.69 |

- **The step is at 0182** (pushed 14:18; the 14:20 bin already read 2.74 s, before 0183 at 14:32).
  - The whole distribution moved by ~0.7 s, not a tail: p10 1.38 → 2.22 s.
  - No 10-minute cadence shows in it.
  - 0182 gives each sweep a re-plan batch of waiting merchants, budgeted at `npc_replan_sweep_ms` = 600 ms, and
    its own header says that budget is what holds the average under 3 s. It does, but only just.
- **Nothing deployed after 0182 moved the dark baseline measurably**: 0186, 0190, 0191, 0193 and 0194 included.
- **Lit adds on top of it.** 0192 gave 3.18 s over its contaminated window and 3.07 s over the clean one, against
  2.85–2.88 s dark around it.

### The prod-shaped world (`prodlike.mjs`; prod's knobs, stocks, purses and 1,491 loops)

The sweep is fixed: the SAME 15 merchant landings each round, every other voyage held a day off, each arm rolled
back.

- **Deploy by deploy** (dark, 10 rounds each, one world per step): 0180 890 / 1,051 ms (the same world twice: the
  run-to-run noise is ±15 %), 0184 709, 0189 756, 0192 794, 0194 738, 0195 845, +0196 tariffs 787 ms.
  - No step moves the landing cost beyond that noise.
  - 0182's batch does not show here, because no merchant is laid up in this setup. Production shows it.
- **Dark vs lit, paired in one world** (16 rounds):

  | world | dark | lit | lit + the 0198 guard |
  |---|---|---|---|
  | 0195 | 742 ms | 872 ms (+17.5 %) | 715 ms |
  | 0195 + 0196 + **0198** | 752 ms | **756 ms** (+0.5 %, 8 raids fought) | — |

- **Where lit's cost was:** `world.ship_stats`. While `combat_bite` is on, every call runs
  `public.ship_crew_terms`' K10 loop: `crew_pct` three times, each a full `crew_terms` of the fleet. That is every
  speed, cargo-space and supplies read, for every hull of every landing and every re-plan. For nothing: no hull on
  production has a seated Gunner or Boarder.
  - On the prod-shaped world, lit vs dark: ship_stats over every hull 329 → 1,071 ms; fleet speed + supplies
    1,425 → 3,069 ms; cargo space 526 → 1,293 ms.
  - On production (read-only), 3 × `crew_terms` for 915 hulls took 2.2 s.
  - `voyage.fight` itself (a few per hour) and `armour_soak` on shoals are not where the cost is.

### 0198 — a hull with no fighting captain is read at once (DARK; no knob)

**What it does:** one hunk on `public.ship_crew_terms`. If no captain seated on the hull has a job or an active
trait with a ship-scope effect, it returns the stats as given.

**Why the answer is exactly the old one:** every term `crew_pct` sums for that hull comes from such a captain.

**Its own check:**
- dark, 908 hulls read the same stats;
- lit, every hull's new body = old body;
- a nau with a seated Gunner (her job) and Boarder (a trait in use) still reads through: accuracy 55 → 57, attack
  120 → 125, the same as the old body;
- ship_stats lit over every hull 894 → 219 ms;
- the hunk reverses, and its ACL and volatility are unmoved.

**The fight results are untouched**: `voyage.fight` and `fight_resolve` are not edited, and the stats they read are
asserted equal.

### REPAIR orders (37 → 70), read-only

The repair orders came first, the fight after. Per half hour:

| from | 15:30 | 16:00 | 16:30 | 17:00 | 17:30 |
|---|---|---|---|---|---|
| REPAIR orders | 16 | 26 | 42 | 53 | 64 |
| combat | dark | dark | dark (0192 lit at 16:50) | lit | lit |

The 16:30 bin, with combat still dark, already had 42. Before 15:00 it was 2–14 per half hour.

Classified by the fleet's last arrived voyage before the order (clean lit window, 65 orders):
- 0 followed a fight that took hull;
- 30 followed a storm or shoal;
- 35 followed no hazard at all.

So the fight is not the cause. A repair is due whenever any hull is short of its class durability
(`public.fleet_repair_due`, 0181's "REPAIR only when due"). Merchants' routes reach their repair stops with damage
from earlier passages. My reading is that the rise follows 0181 / 0182's re-planned routes: an inference, not proven.

### 0199 — the switch again

It is 0192's file, re-numbered, after 0198: same refusal, probe, notices, rollback, 30-minute after-check and
bounds. No other deploy goes inside the window.

**Expected on production** (my estimate, not a measurement):
- dark is ~2.85–2.9 s;
- lit with 0198 should be within the run-to-run noise of dark.

So the 3 s bound should hold, but with little room. If it is to have more room, the lever is 0182's
`npc_replan_sweep_ms` (600 ms of every sweep). That is its owner's knob.

## 0199 — a waiting merchant's batch keeps its budget (the coordinator's decision; the owner may reverse it)

Numbering after this change: perf fix 0198, live. This batch fix 0199. The re-light becomes **0200** (#249).

**What it changes:**
- `npc_replan_sweep_ms` goes from 600 to **300**. The file refuses to run unless the pre-image is 600.
- `public.npc_ask_waiting` becomes **strict**. It begins another merchant only if the time the batch has run plus
  the last re-plan's own measured cost (this sweep) stays within the budget.
  - The first merchant of a sweep is begun as before, so a due merchant is never starved.
  - The only overrun left is a single re-plan longer than the whole budget.
- Who is asked, in what order, and what a re-plan answers are unchanged. `npc_tend_route`, `npc_plan` and the queue
  are untouched.

**Its own check:** four merchants of its own (two companies, two fleets each), all due, with a stand-in re-plan of
120 ms:
- the strict batch asked **2 in 245 ms**;
- the old body asked **3 in 365 ms**.

**Cadence on the prod-shaped world.** 0199 applied on main's 0198 world with prod's knobs, stocks, purses and
1,491 loops. 122 merchants were laid up (prod's count at 19:05 UTC), and the kickoff laid up more: 261 were
waiting. Each arm then ran 300 sweeps, one every 15 s (75 game-minutes), from the same start, rolled back:

| | asks | batch avg / p95 / max a sweep | wait between asks avg / **max** |
|---|---|---|---|
| old (600 ms, can overshoot) | 1,365 | 645 / 841 / 1,019 ms | 10.8 / 16.8 min |
| **new (300 ms, strict)** | 570 | **258** / 413 / 561 ms | 20.7 / **34.0 min** |

- **Every waiting merchant is still asked well inside the 60-minute promise.** The hourly reconcile remains the
  backstop for any that are overdue.
- **The batch's mean cost per sweep falls by ~0.39 s.**
- **p95 and max still exceed 300 ms.** That is where one re-plan costs more than the last one did. Strict means "no
  second one past the budget", not "no re-plan longer than predicted".
- **On production** a re-plan takes 170–230 ms (0182's measure), so the batch is about 1–2 re-plans a sweep. At
  today's 122 waiting, my estimate is that each is asked about every 20–30 minutes. That is an inference, not a
  measurement.
- **Expected effect on the arrivals average:** −0.3 to −0.4 s, which would bring the dark ~3.0 s back to ~2.6–2.7 s.
  To be confirmed in the clean 30-minute window after it is live, before 0200.

## 0203 — the raid balance: a crew that cannot hold the deck surrenders (DARK; `osn-raid-balance`)

0200 lit the fight at 20:48 UTC. Its 30-minute after-check (20:50–21:20) broke two raid bounds: lost share
43.8 % against 35.0 % dark, crew lost per raid 12.50 % against 6.43 %. Arrivals held at 2.42 s. 0201 rolls the
switches back. This section is what was measured after, and the one change made.

### The method: production's real raids, replayed

- **Export, read-only** (`begin transaction read only`; every function called is `provolatile` s): all 236
  PIRATES days on production (2026-10-16 14:40 → 2026-10-18 21:21 UTC; 176 dark, 60 lit), each with its voyage,
  day, recorded raider strength, outcome and crew. Also the 192 fleets that met them, each hull read with
  `world.ship_stats` (prod was lit at the export, so these are the lit figures the fight reads).
- **Dark** is DESIGN B.6's table on each raid's dark escort. On all 176 dark days it gives the recorded outcome.
- **Lit** is `voyage.fight_resolve` on the main 0200 world image (PGlite), with prod's fight knobs and
  `armour_turns_pct` 0.5. Each raid is fought 20 times (its own voyage id, then 19 derived ones), so a share is
  not one roll. Crew is counted per hull by `public.raid_crew_lost`'s own floor (no Surgeon is seated on prod).
- The scripts are in `bv-harness/raid-scratch/`: `exp.sql` (the export), `sim.mjs` (the replay),
  `gen-cands.mjs` (the candidate bodies) and `paired.sql` (below).

### The cause

| raids, by target | n | dark lost | lit (0189) lost | dark crew | lit (0189) crew | dark STRIPPED | lit (0189) STRIPPED |
|---|---|---|---|---|---|---|---|
| all | 236 | 27.1 % | 25.2 % | 6.48 % | 7.13 % | 4.7 % | 8.2 % |
| one hull, ≤ 12 crew | 141 | 43.3 % | 40.3 % | 9.76 % | **11.28 %** | 6.4 % | **13.4 %** |
| one hull, > 12 crew | 82 | 0 | 0 | 0.69 % | 0.36 % | 0 | 0 |
| two or more hulls | 13 | 23.1 % | 21.2 % | 7.48 % | 4.79 % | 15.4 % | 2.7 % |

- **Over the whole real mix, 0189 already held both bounds**: lost 25.2 ≤ 32.1, crew 7.13 ≤ 7.48.
- **But a lone hull of 12 crew or fewer (60 % of the raided) buried more.** Crew went 9.76 → 11.28 % and STRIPPED
  doubled. Every one of those STRIPPED days was a boarding below the last band: a 40–70-crew xebec against 8–12
  hands. The crew fought for a deck it could not hold and lost 30 % of its hands.
- **The after-check's window was not a like-for-like comparison.** The dark table on the SAME 16 raids of 0200's
  lit window gives lost **50.0 %** and crew **12.71 %** (`paired.sql`, read-only on prod; current hulls). The fight
  did no worse than the table there (43.8 % / 12.50 %). That window simply met heavier raids on smaller hulls:
  barcas against raider strength 20–25, where the table strips them too. It was compared with a different 19.
- **A window of 16 against a window of 19 is close to a coin toss.** Resampled from this mix, the after-check's
  two bounds both hold only **52 %** of the time for 0189, and **56 %** for the dark table against itself.

### The candidates, measured (the same 236 raids × 20)

| candidate (all NOT the owner's) | lost | crew | crew, ≤ 12 | STRIPPED | paired check holds | windowed check holds |
|---|---|---|---|---|---|---|
| dark table | 27.1 | 6.48 | 9.76 | 4.7 | — | 56 % (vs itself) |
| 0189 as lit | 25.2 | 7.13 | 11.28 | 8.2 | 59 % | 52 % |
| `fight_hand_value` 0.15 → 0.04 | 21.8 | 6.20 | 9.76 | 4.4 | 82 % | 64 % |
| raiders sized to the prey, ≤ 2 × her boarding strength | 24.3 | 5.50 | 8.61 | 0.5 | 86 % | 68 % |
| raiders sized to the prey, ≤ 1.5 × | 22.1 | 5.14 | 8.01 | 0.2 | — | 73 % |
| outnumbered 5 : 1 at the boarding → RANSOM | 16.4 | 4.35 | 6.63 | 1.2 | — | 84 % |
| gives up at sight (escort < 0.3 × raider) → RANSOM | 20.6 | 5.63 | 9.02 | 4.6 | — | 70 % |
| **below the last band the crew surrenders → PLUNDERED (0203)** | **25.2** | **5.47** | **8.56** | **0** | **85 %** | **67 %** |

("paired": 16 raids drawn, lit against the table on those same raids. "windowed": 16 lit against 19 other dark
ones, as the after-check did. 4,000 draws each.)

**Why the surrender was chosen:**
- It is the one rule that removes the measured harm, the 30 % crew loss at a hopeless boarding, and changes
  nothing else. The sighting, every round, the break-off and every fight above the last band are word for word
  the same (0203's own probe asserts this on 960 days).
- So range, accuracy and attack matter exactly as much as they did. The won column is identical to 0189's.
- **It keeps crew meaningful**, as the measurements below show. Sizing the raiders to the prey does not: it fixes
  the boarding ratio of every capped fight, so extra hands buy less.
- Unlike "outnumbered → RANSOM", it keeps the outcome monotone: a weaker crew never fares better than a stronger
  one.
- **Historically** it is the rule, not the exception. A merchant crew that could not hope to hold the deck
  surrendered rather than fight. The pirates' and the corsairs' terror worked by offering quarter to a crew that
  yielded and none to one that resisted, so a prize cost its cargo, not its crew.
- Giving up at sight was rejected: it decides a fight before range or accuracy can count.

**What it costs, stated:** a fight no longer ends STRIPPED (dark, the table still strips: 4.7 %). PLUNDERED keeps
DESIGN B.6's crew −10 %. A lone small hull still loses 11 % of its hull per raid (dark 7.8 %): the rounds are
unchanged, and the hull is not a bound.

### Range and accuracy still decide (0203, the same 236 raids; every hull's figure set as shown)

| every hull's | won | won, one hull ≤ 12 crew | lost | crew |
|---|---|---|---|---|
| reach 5 / 15 / 25 (under the xebec's 26) | 61.6 % | 44.3 % | 25.3 % | 5.56 % |
| reach 40 / 60 (over it) | **68.4 %** | **51.8 %** | 22.6 % | 4.65 % |
| accuracy 20 | 56.8 % | 39.0 % | 26.9 % | 5.62 % |
| accuracy 40 | 63.3 % | 46.1 % | 25.0 % | 5.53 % |
| accuracy 60 | 70.9 % | 55.5 % | 22.1 % | 5.47 % |
| accuracy 80 | **78.7 %** | **66.6 %** | 18.3 % | 5.37 % |
| attack × 0 / 0.5 / 1 / 2 | 51.5 / 56.5 / 63.4 / 73.8 % | 34.1 / 37.1 / 44.3 / 58.5 % | 28.1 → 20.2 % | 5.60 → 5.23 % |
| crew 6 / 12 / 20 / 30 | 61.4 / 63.5 / 66.2 / 68.9 % | 41.8 / 45.2 / 49.1 / 53.2 % | 28.5 → 20.0 % | 7.75 → 2.85 % |

Reach works as a threshold, as 0189 built it: at LONG range a hull fires only if her reach is at least the other
side's. All raiders are xebecs (reach 26), so every reach under 26 reads the same, and so does every reach over it.

### The bounds on production's raid mix (0203 lit vs the dark table, the same raids)

- **Lost share:** 25.2 % vs 27.1 % (bound ≤ 32.1). Holds.
- **Crew lost per raid:** 5.47 % vs 6.48 % (bound ≤ 7.48). Holds, with 2.0 points to spare. For a lone small hull
  it is 8.56 % vs 9.76 %.
- **Better range and accuracy clearly win more often**: see the table above.
- **The arrivals cost is unchanged.** The change is which outcome a boarding below the last band names, with no
  new read and no new loop. Replaying the 4,720 fights took 5.0 s by the old body and 4.4 s by the new on PGlite;
  the difference is noise. `voyage.fight` (the per-hull reads) is untouched.

### 0203 itself

- **Four hunks on `voyage.fight_resolve`**, sliced from the live body (read-only on prod at head 0200: each
  occurs exactly once):
  - the header comment;
  - a `v_surrender` flag;
  - the outcome: below the last band, PLUNDERED;
  - the closing line ("You surrender; they board and take what they can carry.") and the day's sentence ("We
    surrendered, and they took what they could carry.").
- `fight_board_bands`' description says its third band is where the crew surrenders. No knob's value moves, and
  no switch moves: it lands dark. `voyage.fight_resolve` is read only by `voyage.fight`, which is refused while
  `combat_bite` is off.
- **Its own check** (pure engine, its own knob values, rolled back), on a lone carlat and an unarmed barca ×
  raiders 6 / 12 / 18 / 24 × 120 days, old body against new:
  - 485 of 960 days the old body STRIPPED. Each is now PLUNDERED with the same rounds, hits and hull, and the
    surrender's line and sentence.
  - The other 475 days are word for word the same.
  - The new body never strips.
  - Over 300 days, each of reach 60, accuracy 70 and attack 110 wins more than the base, crew 40 loses less, and
    unarmed wins less. One day fought twice is the same fight.
  - The body reverses to its pre-image, with ACL, volatility, definer and config unmoved. Eight neighbours are
    untouched (`voyage.fight`, `voyage.settle`, `armour_soak`, `armour_turns`, `escort_score`, `raid_crew_lost`,
    `fight_points`, `report_line`).
  - The knobs and switches are as before. The core is read by `voyage.fight` alone. There is no entry point.
- It applied green in four worlds:
  - main's 0200 image, lit (3.7 s);
  - main's 0200 image + 0201, dark (3.7 s);
  - the prod-shaped world (`redesign-scratch/setup.mjs`: prod's knobs, stocks, purses, treasuries and 837 loops)
    + 0201 (3.4 s);
  - the cached-prefix `npm run build`.
- **`tests/ledger.fights.spec.ts`** now also asserts that a fought raid never ends STRIPPED.

### For the re-light's after-check: compare like with like

The window-against-window check fails a correct engine about half the time at these sample sizes (above). The
**paired** check compares each lit raid with DESIGN B.6's table on that same raid: `bv-harness/raid-scratch/paired.sql`,
read-only, which takes the window as two timestamps. On 0200's window it reads lost 43.8 % vs 50.0 % and crew
12.50 % vs 12.71 %: both bounds held there. For 0203, resampled, the paired check holds both bounds 85 % of the
time on 16-raid windows. A longer window raises that.

### Not the owner's — confirm

- The surrender rule; its band (the third of `fight_board_bands`, 0.3); and that a fight never ends STRIPPED.
- The words of the surrender: "You surrender; they board and take what they can carry." and "We surrendered, and
  they took what they could carry."
