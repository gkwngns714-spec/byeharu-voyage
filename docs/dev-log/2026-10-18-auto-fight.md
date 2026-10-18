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
