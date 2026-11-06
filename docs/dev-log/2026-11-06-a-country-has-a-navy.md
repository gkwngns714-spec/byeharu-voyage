# A country has a navy (W12, migration 0331, owner row 285, dark)

Built as 0329 and renumbered to 0331 on the coordinator's word: W15 (0330, #536) deploys first. Proof number stays 37.

Owner: *"each country will also have battle ships. they defend or attack pirates"*.

**State: built, dark, PR open, not deployed.** `navy_enabled` false. No row is written and the sea reads the same until the owner lights it. This slice is ships and patrol: they join no battle (W13), hunt nobody (W14, W19), and cannot be attacked yet (see "Owner must see").

## What it does, lit

- A great power keeps `min(24, 2 + floor(sqrt(purse / 25 M)))` ships, read daily. Purse: the summed `treasury_balance` of its harbours (`public.realm_purse`, lifted out of the cargo curve so it has one copy).
- Stations are computed: capital first, then whichever harbour covers the most uncovered cities within 2,400 sailed miles, until all are covered. Re-run after a flag change, one country a run. Ship `ord` n serves rank n, wrapping.
- Each station has a patrol: its 3 nearest harbours in reach, own flag first, and home. The legs come from `public.cargo_circuit_plan`, so there is one path walker. One station is written a run.
- A ship sails her patrol through the real voyage engine: hands from the quay above its floor, free stores to `navy_store_days`, no wage, no dock fee. Home, she is mended free and starts again.
- Over the number, unpaid, or with the switch off, she leaves her patrol at the next port, sails straight to her station and is **laid up**: never deleted, one path for all three.
- A wreck goes to her station, which pays the `REFIT` through the existing rule.

## What happens when a capital cannot pay (owner question 9)

**Nothing is minted, nothing is owed, nothing raises.**

- **Build:** a capital pays the galion's 1,156,000 d. to its yard only when its **surplus** covers it. If not, the job writes nothing and asks again next minute. A hull appears on the run its capital can pay, at most one a country a day.
- **Pay:** hourly, it pays the ships its surplus covers, lowest number first. The rest are marked unpaid, go home and lie up. No slice is carried, so there is no debt to clear.
- **Wake:** a laid-up ship inside the number wakes when the capital can pay her next hour, at most one a day. Same fleet, same house.
- **Busy capital:** skipped for that run, never waited for.

### Today's purses (prod, read only, 2026-11-06, head 0328)

| Power | Realm purse | Ships | Capital | Capital's surplus | Can build? | Aid target |
|---|---:|---:|---|---:|---|---:|
| PRT | 4,384 M | 15 | LIS | 308,053,940 | **Yes** | 50,000 |
| FRA | 3,360 M | 13 | MRS | -4,150 | No | 50,000 |
| ESP | 2,408 M | 11 | SVQ | 483,168,493 | **Yes** | 92,658 |
| NLD | 1,598 M | 10 | AMS | -88,280 | No | 88,503 |
| MNG | 642 M | 7 | GUA | 643,269 | No | 50,000 |
| OTT | 353 M | 5 | IST | 563,110 | No | 148,812 |
| JPN | 297 M | 5 | SAK | 241,366,219 | **Yes** | 378,588 |
| MUG | 104 M | 4 | KAR | 491,748 | No | 50,000 |
| ENG | 72 M | 3 | LON | 1,084 | No | 50,000 |
| JOS | 12 M | 2 | BUS | 68,708 | No | 50,000 |

So **lit today, 31 of 75 hulls get built (15 days, one a day) and seven countries get none.**

**The design's way out does not work as written.** It says cargo ships top poor capitals up first. A cargo ship tops a city up to `city_aid_target`, here 50,000 to 148,812 d., and a galion costs 1,156,000 d. So aid alone never lifts those capitals to a hull. France's realm holds 3.4 B d. and its capital is at -4,150. The money is in the realm, not the capital. **That is the owner's question 9, still open:** let the realm's richest city pay, as `convoy_rich_enabled` does for cargo, or lower the class, or accept it. I did not change who pays.

## Stations on today's flags

A local run of the same greedy over prod's `sea_reaches` and flags, read only: **46 stations, as the design says.** The world in the proof holds fewer flags, so `public.navy_station_plan` itself has not run on prod's data.

| Power | Stations, in order (cities each adds) |
|---|---|
| ENG | LON 16, CAL 2, NEW 2, GIB 1 |
| ESP | SVQ 15, BRI 10, CLL 10, BUE 2, OUI 1, PLO 1 |
| FRA | MRS 10, BEL 1, BOR 1, LAG 1, QUE 1 |
| JOS | BUS 8, MLE 7 |
| JPN | SAK 18, KOZ 6, AMB 2, COQ 1, MAS 1 |
| MNG | GUA 12, BNT 3, AST 2, HOB 2 |
| MUG | KAR 10, NAV 4, GOR 3, CPT 2, MAK 2 |
| NLD | AMS 15, CAP 3, SGO 2, JAK 1, SFR 1 |
| OTT | IST 25, ADE 5, NUU 5, ELM 1 |
| PRT | LIS 6, MOG 8, REC 3, LUA 2, MAC 2, COL 1 |

A few differ from the design's table (FRA QUE for NUU, MNG BNT for GAL, NLD SGO for STA, OTT ADE, NUU for HAD, PON): flags and ties. JOS and ENG cover all their cities here; the design said part.

## The job: bound from the start, cost projected against 75 hulls

`public.tick_navy`, `byeharu-voyage:navy`, every minute, never in the beat. **Per run: at most `navy_steps_per_run` (40) ships, turned by the minute; one plan step; one ship added; one country paid.** Purses come last, so a capital's lock is held only to the commit. Dark it reads one knob and one empty view.

Measured on PGlite, this PC, the probe world, 75 hulls at the design's ship counts (`proof-0331.mjs --cost`, one session). **The scale:** the same idle cargo step is 1.5 ms there and about 10 ms on prod (0326's dev-log), so about × 6.7. The prod column is that arithmetic, not a measurement.

| Run | PGlite | Projected prod |
|---|---:|---:|
| Dark, no ship | 0.6 ms | 4 ms |
| Quiet, all at sea | 6 ms | 40 ms |
| Quiet, one country paid | up to 139 ms | up to 0.9 s |
| Writing one patrol (46 runs, once) | up to 133 ms | up to 0.9 s |
| 75 all due, no bound | 260-313 ms | 1.7-2.1 s |
| 75 all due, bound at 40 | 155-171 ms | 1.0-1.1 s |
| One departure, steady | 3.5-4.2 ms | 25 ms |

**Steady state:** about 7 departures a minute, so about 0.2 s a minute. It fits its minute by a wide margin. The bound is there for the day after an outage. Note 139 and 133 ms are maxima over 12 runs.

**The beat:** prod reached 7,639 arrivals in the last hour, 127 a minute. The design's "57 + 5" is out of date. 75 ships at about 7 a minute add about 5.5 %. Not measured.

**Rows:** about 10,000 voyages a day (compacted with every NPC house), and about 1,300 `treasury_flows` rows a day: one out and one a harbour, each country hourly, whatever the ships. **Dark cost on the beat:** one extra indexed read in `fleet_kind` for a company's fleet with hands, none for a merchant, a cargo ship or an empty read. No cost measured on prod.

## Hot bodies re-cut (16 hunks, each once, each reversing, read on prod at head 0328)

`fleet_kind` (2), `fleet_origin` (2), `sea_houses` (2), `fleet_wage` (1), `port_fee` (1), `stats_live_track` (1), `stats_live_fold` (1), `convoy_ships_wanted` (1), `cargo_upkeep` (2), `cargo_ship_step` (1), `client_rpc_entry_points` (1), `cargo_figures` (1).

Moved, same statements, one copy each: `public.realm_purse` (from the curve), `public.fleet_stores` (from `cargo_upkeep`), `public.fleet_patched` (from `cargo_ship_step`), `public.crown_house` (three bodies held half of it).

New: 5 relations (`navy_ships`, `navy_ships_in_service`, `navy_realms`, `navy_stations`, `navy_patrol_legs`), 20 functions, 12 knobs, two moved kinds (`BUILD_NAVY`, `NAVY_PAY`), one cron job.

Client, landing together: `KIND_LOOK.navy`, `NAVY_HULL`, `navyHullPath`, the `stripe` mark, `--color-navy-hull`, `NavySheet`, `useNavyShipCard`, `worldNavyShipCard`, the Codex entry, EN and KO words, Money log (`NAVY_PAY` under Wages, `BUILD_NAVY` unfiled, as moved city money).

## Her look (section 9, spec `tests/map.kinds.spec.ts`)

A violet dart, `#c4a1ff`, day and night, whatever her nation, with one dark stripe bow to stern. Pictures: `docs/dev-log/2026-11-06-cargo-colour/kinds-1x.png`, `kinds-2x.png` (row NAVY).

Contrast read from the built CSS: fill on day deep 3.88, keyline on shallows 8.81, mark on fill 7.68. All grounds and twilight pass the 3 : 1 law. Teal is a colour distance over 100 away; at least 20 % of her area differs from cargo and every merchant hull at 1x and 2x.

**Differs from the design:** violet, not nation ink, following the owner's *"unify the color of cargoship"*. Beam 0.4, not 0.32: at 0.32 the 2 px stripe took nearly her whole deck at 1x and her colour went with it.

## Dark

`scripts/ops/harness/navy/dark-scene.sql` (16 lines): `world.sea_roster` hashed with clock and new ids out, the same merchant's row byte for byte, `world.sea_traffic`, `sea_houses`, kinds, origins, wages, fees, stores, the patch, the curve, the fold, the figures, the job. Equal before and after the file, with the `rich-cities` (15 lines) and `armed-cargo` (5 lines) scenes.

## Proof

- `scripts/db/proofs/37_a_country_has_a_navy.sql`: 20 markers, the real job, voyage engine, refit and purses, economy CLOSED as prod, and `NAVY_OPEN` with it open, as CI's own world.
- `scripts/ops/harness/navy/proof-0331.mjs`: red first (fails with no file), scenes equal, real file green, 60 mutations each red for its own reason, on the world at head 0328.
- First runs found: a proof reading a stable function beside a volatile call in one expression (the same trap as 0328); `<>` on a null passing where `is distinct from` fails (three asserts); and that a capital left with 0 d. after a build lays its new ship up on the same run. That last is the rule working, so the proof gives the capital an hour's pay.
- `tests/map.kinds.spec.ts` gains the row: 33 passed with `stats.moneySectors` and `cargo.design`. `tsc`, `eslint`, `vite build` clean.
- Self-assert: catalog, stable reads and arithmetic on probe purses, no row, no game step, under 200 ms locally on the proof world, not on a populated one.
- `scripts/ops/harness/navy/before.sql` on prod at head 0328: all 16 hunks once, no navy key, word or table, ords 52 and 53 free.

## Decided by default

- `navy_on` needs the city purses: with none, nothing could pay for a hull.
- Laid up is one path for over the number, unpaid, and switch off. She sails straight to her station, a leg read from the plan, rather than finishing the patrol.
- No dead band on size: a daily read, a root, and one ship a day made one unneeded. Wake is free; a built hull is paid once.
- One add a day counts a wake as much as a build.
- A build needs the surplus for the hull only, not her first hour.
- Yard: `public.refit_yard(capital)`, own country first, else nearest. Nearest foreign yard if the realm has none.
- Crew: laid crewless. Hands at each departure from the quay she leaves, free, above the floor; a quay at its floor gives none and she sails short. Laid up she keeps her hands.
- Mended free at the end of each patrol, as a cargo ship's lap. With `npc_refits_enabled` dark, a ship reaching 0 is patched free where she lies, as cargo.
- Pay is hourly, one country a run. A ship at the capital costs it nothing and moves nothing, but counts against what it can pay.
- A patrol's stops: own flag first, so upkeep stays in the realm where it can. A foreign stop is paid like any other.
- Knobs the design did not name: `navy_min`, `navy_purse_unit`, `navy_size_read_minutes`, `navy_build_hours`, `navy_patrol_stops` 3, `navy_store_days` 90, `navy_steps_per_run` 40.
- `navy_store_days` 90: a move between far stations of one realm, not a patrol, is what needs it.
- Words: Navy ship 군함, Station 기지, Duty 임무, Patrol 순찰, Laid up 정박 중, Navy build 군함 건조, Navy pay 해군 급여.

## Owner must see

1. **31 of 75 hulls.** Above. Lit today seven countries get no ship, and aid alone cannot fix it.
2. **Attacking a navy ship is not built.** Owner said yes; the design's section 4 said it comes with W12, but W12's row does not list it. `public.attack_for` still refuses her and `regard_attack_navy` does not exist. It belongs with W13 or W14, before `attack_enabled` is lit. The design is marked.
3. **W9 is not lit,** and this does not need it.

## Not verified

- Anything on prod, lit or dark, beyond `before.sql`. Real-Postgres behaviour is CI's disposable-chain; local runs are PGlite.
- The projection: it scales one step by a ratio. Arrivals cost and compaction with 75 more ships were not measured.
- `public.navy_station_plan` and `public.cargo_circuit_plan` patrol legs on prod's full flags and 1,253 courses.
- Two real sessions on a capital's lock: the busy capital is stubbed.
- Whether a galion sailing short on a quay at its floor keeps her patrol at a sensible speed.
- `NavySheet` and the Codex entry were type-checked and built, not opened in a browser: no served row is NAVY dark, and no spec drives a lit map. The map row is proved by `mapTrafficOf` and the real `FleetsLayer`.
- Hands: the manned stations hold about 7,400 hands above floor against 9,750 wanted; how fast a quay refills was not read.
- Whether a player's trade changes around these ships, or their pay moves a harbour's prices.

## Rows for the coordinator (not written here)

**docs/OWNER_REQUESTS.md row 285:** `PART BUILT - W12 navies, migration 0331, dark behind navy_enabled, PR open, not deployed. OPEN: owner question 9 (only 3 capitals can pay, 31 of 75 hulls); attacking a navy ship; W13, W14, W19.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **A COUNTRY HAS A NAVY (W12, owner row 285) - migration 0331, DARK behind navy_enabled, PR open, NOT deployed, follows 0330:** real ships at computed stations, patrol, paid by the capital, a build waits for money and never mints. Read before lighting: only LIS, SVQ and SAK can pay today, so 31 of 75 hulls; cargo aid alone cannot lift the other capitals (target 50,000-148,812 d., a galion 1,156,000 d.). Dev-log docs/dev-log/2026-11-06-a-country-has-a-navy.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/navy/before.sql`. Every `times` 1, `navy_keys` 0, `navy_words` 0, `navy_table` null, `class_ok` 1, `word_ords` 0, head 0330.
- After deploy: `scripts/ops/harness/navy/after.sql`. `navy_on` false, every count 0, `job_active` true, `job_failed` 0, `figure_served` false, sizes as above for the day's purses.
- `bash scripts/ops/health.sh` (a new cron job is a load change, docs/OPS_HEALTH.md section 2; dark it reads one row).

## Rollback

Forward, owner only: `navy_enabled` false. Nothing is built or paid. Each ship sails to her station and lies up. Hulls remain.
