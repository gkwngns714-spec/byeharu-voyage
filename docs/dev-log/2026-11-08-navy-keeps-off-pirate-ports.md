# The navy keeps off pirate ports (migration 0342, owner rows 284, 285): a navy ship never sails for a harbour the pirates hold, and her upkeep never reaches their purse

Owner, 2026-11-05: *"each country will also have battle ships. they defend or attack pirates"*; the pirates are a power that holds cities (W16, 0338) and were lit on 2026-11-07 at 17:55 UTC (`pirates_bite` true); the navy is DARK (`navy_enabled` false, the owner's call) and must be safe to light. The W19 review (`docs/dev-log/2026-11-07-the-navy-hunts.md`, "Decided by default") found the LEAK: a navy ship lying at a harbour the pirates hold has her hourly upkeep (`NAVY_PAY`, 0331: capital to the harbour she lies at or last called at) paid INTO THE PIRATES' PURSE, which is their hoard (0339 `public.pirate_hoard` = the purses of every city they hold), and their quay mans her at her departure (`public.fleet_hands`). W19 closed it for the hunt's targets alone (`public.navy_hunt_targets`) and left the rest, named, for a slice of its own. This is that slice.

**State: built on `origin/main` ab9c3758 (prod head 0341, read 2026-11-08 by `before.sql`), branch `navy-off-pirate-ports`, PR open, NOT merged, NOT deployed. DARK: everything behind `navy_enabled` (false on prod; prod has no navy ship). No knob, no table, no column, no word, no job, no client change.**

## The one rule, in one reader

`public.navy_harbour_ok(port)` = the pirates do not hold it (`public.pirate_power` of `public.port_nation`; a harbour nobody holds is open). STABLE, server-only. Every place a navy ship's harbour is CHOSEN reads it, and the two money paths read it:

| Chooser | Live body (newest) | Before | Now |
|---|---|---|---|
| a patrol's stops | `public.navy_patrol_build` (0331) | the `navy_patrol_stops` nearest open harbours in reach, its own crown's first | the same, never a harbour the pirates hold |
| a call's harbour | `public.harbour_nearest` (0333; the call's one reader of "where") | the nearest open harbour to the site | the nearest open harbour the pirates do not hold, read from the nearest outward (fenced with `offset 0`: the holder is asked of the nearest few, not of all 249) |
| a reinforcement's harbour, as she sails | `public.navy_reinforce` (0333) | sails for `called_to` when a course reaches it | the same; `called_to` fallen since the call: freed, `'infinity'` on the sheet, as with no course |
| an escort's stop | `public.navy_escort_step` (0333) | follows the richest cargo ship of her crown at sea with funds | the richest one bound for a harbour the pirates do not hold (fenced the same way) |
| the station a hull is laid at or a ship woken for | `public.navy_add` (0335's body) | `navy_station_of(nation, ord)` | the same; a fallen station: the realm waits for the plan (one realm a run) |
| her home, as she leaves port | `public.navy_ship_step` (0340's body) | the plan's station for her ord, else her last station | the same; fallen: her realm's CAPITAL; no crown harbour at all: she stays where she lies (IDLE) |
| the next stop of a patrol already written | `public.navy_ship_step` | sails leg n+1 | leg n+1's harbour fallen: her patrol ends here (no mend), the station's patrol is DROPPED (`public.navy_patrol_drop`) and written again without it by `public.navy_plan_step`; the first leg fallen at her station: IDLE until it is written again |
| a hunt's harbour | `public.navy_hunt_targets` (0340) | its own copy of the test (`not pirate_power(port_nation(p.id))`) | the reader, one copy; and the read fenced (below: about 300 ms to a few) |
| the hour's pay | `public.navy_pay` (0335's body) | capital to the harbour she lies at or last called at | the same; a harbour the pirates hold: her slice STAYS AT THE CAPITAL, as a ship at the capital's; she counts as paid |
| her hands | `public.navy_sail` (0331) | hands from the quay she leaves | none from a quay the pirates hold: she sails as she is |

## Case (d): a harbour falls to the pirates under her

The daily influence count can hand a crown's city (never a home) to the Brethren. A navy ship may then be lying at it, be bound for it, have it as her station, or have it as a stop of a patrol already written. Decided, with the consequences:

- **Her pay.** Her slice stays in the capital's purse (`navy_pay` pays her as if she lay at the capital: the realm's other cities receive what they did, the hoard receives nothing, nothing is minted). She is marked paid, so she stays on duty and her next step takes her to a crown harbour. The alternative, marking her unpaid so 0331 lays her up, would cost a realm one ship for `navy_build_hours` (24 h) over a flag it did not choose; not taken.
- **Her hands.** `navy_sail` takes none from a quay the pirates hold; she sails with the hands she has (0328's rule for a quay at its floor: she sails short). The one place she can leave such a quay is a harbour that fell under her, since she never sails TO one.
- **Her home.** On duty her home is the plan's station for her ord; `public.navy_stations_build` moves a realm's stations off a fallen city after the flag change (one realm a run, so within about ten minutes for ten realms). Until then, and off duty (0331 sends her to her LAST station to be laid up), her home is her realm's capital instead; her `station_port` moves with her as she leaves (0331's line). With no crown harbour at all (the capital fallen too) she stays where she lies, IDLE, no error.
- **A hull's station.** `navy_add` lays no hull at, and wakes no ship for, a fallen station: the realm waits for the plan. (Without this a crewless hull would be laid INSIDE a pirate port and, with the hands rule, could never man herself there.)
- **A patrol already written.** A stop that fell is never sailed to: she ends her patrol at the stop before it and sails home (the crown's free mend waits for her next finished patrol); the station's patrol is dropped (`public.navy_patrol_drop`: its legs go, `legs_at` null) so `navy_plan_step` writes it again without the stop, one station a run; a sister ship out on that patrol ends hers at her next port, as off her line (0331's path), and sails home. The first stop fallen: she lies at her station (IDLE) until the patrol is written again. A retired station's legs go the same way and the station goes with its last ship, as before.
- **A call's harbour.** Fallen before a called ship sails: she is freed and `'infinity'` on the sheet, exactly as 0333 treats a harbour no course reaches; the join rule reads it. A ship already AT the harbour when it falls waits out the battle there (CALLED), paid at the capital.
- **A hunt's harbour while she lies there.** She lies out her hours (`navy_hunt_hours`, 6), paid at the capital, then sails home; a hunt never picks one (0340, now through the reader).

## Not changed, said plainly

- **The yard.** `public.refit_yard` (0322) names the yard a capital pays for a hull (`BUILD_NAVY`, 1,156,000 d.) and a station pays for a wreck (`REFIT`): a yard of the same crown first, else the nearest, WHOEVER HOLDS IT. Crown gold reaches a yard the pirates hold only when a realm has no yard but its capital's and the nearest foreign yard is a city they won. It is the one rule every merchant's and cargo ship's refit follows (and the pirates pay crown yards by the same rule, 0339), so a change is a slice of its own if the owner wants crowns to buy from no pirate yard. Named here, not changed.
- Pirate ships, pirate merchants, the hunt's fight, `tick_navy`, `world.navy_ship_card`, every switch and knob: untouched. **No new knob:** a rule with no number needs none.

## Bodies re-cut (11 hunks over 9 bodies, each once, each reversing; sliced from the live bodies at head 0341, which `before.sql` showed are prod's own)

`public.navy_patrol_build` (1), `public.harbour_nearest` (1), `public.navy_reinforce` (1), `public.navy_escort_step` (1), `public.navy_ship_step` (3), `public.navy_pay` (1), `public.navy_add` (1), `public.navy_sail` (1), `public.navy_hunt_targets` (1). New: `public.navy_harbour_ok(uuid)` STABLE and `public.navy_patrol_drop(bigint)`, both definer, both server-only. ACL, volatility, definer and config of the nine unmoved (the self-assert's md5 over them; `attr_md5` in the prod checks).

## Dark

With `navy_enabled` false no re-cut body runs: `navy_call` returns before it reads a harbour; the patrol, the add and the pay run lit only; a step, a sail, an escort and a reinforcement need a navy ship, and prod has none. `navy_hunt_targets` answers the same rows (the same test, through the reader). Proved, not argued: `scripts/ops/harness/navy-off-pirate-ports/dark-scene.sql` (11 lines: the job's answer, her step and row with the navy off, the hunt's targets of Lisbon, the call's reader at the Tagus and off the Azores, and with the navy on and the pirates off the capital's patrol as written, her first leg, an hour of upkeep where she lies, the escort's answer for a ward bound for a crown harbour) beside the `navy` (16), `navy-comes` (10) and `the-navy-hunts` (11) scenes: every line equal before and after the file.

## Proof

- **The file's own self-assert** (catalog and stable reads, 67 to 97 ms locally, budget 45 s; no scan of a big table): every hunk once and reversing; md5 over every other function unmoved; no `world_config` row moved (no knob); the nine bodies' attributes unmoved; no cron job moved; the switch off; no navy row; the reader stable and definer, the drop volatile and definer, neither client-callable; the reader false at every harbour the pirates hold (4 on prod and here), true at every crown capital, true at a harbour nobody holds, true for no harbour; the count of harbours it refuses equals the pirates' holdings; the call off Port Royal (their capital since 0338) answers SGO, an open harbour not theirs; the Tagus still answers a harbour.
- **Proof 49** (`scripts/db/proofs/49_navy_keeps_off_pirate_ports.sql`, 11 markers, 2.2 to 4.4 s, the real job, step, builder, call, escort, pay and sail door through the real voyage engine, the economy CLOSED): NP_DARK, NP_PATROL (SET, the builder's first stop, handed to the Brethren: left out of a 13-leg patrol ending at the station; the scene checks it would have been taken without the rule), NP_CALL (LON handed over, the call went to PTH; the second ship's harbour fell before she sailed: freed, `infinity`, nowhere), NP_ESCORT (the richest cargo ship bound for OPO, theirs: not escorted; OPO back: escorted there), NP_HOME (REC fallen: home is the capital and her station moves; no hull laid at REC till it is back, then BUILT there; stop FNC fallen: patrol ended, dropped, written again without it; first stop SET fallen: IDLE, written again, sailed), NP_PAY (2,500 d. a ship: REC and the free harbour AGA paid, fallen SET not, her slice at the capital, the hoard unmoved, every ship paid; at sea with SET her last port the same; SET back: paid), NP_HANDS (from fallen REC she sailed with her 10 hands and the quay kept its 2,000; as a crown harbour it gave 120), NP_TARGETS (TAN handed over is no target of Lisbon, 12 of 12 seas stand), NP_ONLY (every harbour theirs: no leg, no harbour for a call, IDLE where she lies, the hour moves nothing, no error), NP_MONEY (W unchanged over the whole proof). The fixture hands a harbour over the way the count would (its flag row, the home guard disabled by name as 0338 and proof 48 do, the flag clock untouched).
- **Harness** `scripts/ops/harness/navy-off-pirate-ports/proof-0342.mjs` (local, the cached world at head 0341: 322 of 325 restored, 3 applied, about 3 s; nothing from zero, nothing written to the cache): RED FIRST red (the reader is the first thing asked for); DARK PARITY equal on all four scenes; the real file and proof 49 green; the proofs of the bodies it re-cuts and of the attack path that calls the navy green on it: 31 (12 markers), 34 (15), 37 (20), 40 (15), 42 (13), 48 (12); **20 mutations, each red for its own reason** (`mutations-0342.mjs`: one a hunk, the reader refusing nobody, the reader volatile, the drop keeping `legs_at`, the drop keeping the legs, a client reaching either function, a hunk off its line, the switch lit by the file, a knob added by the file).
- **Every older proof 01 to 48 run once after the file (`--all-old`, each in a rolled-back transaction): all 47 green** (05 56 s, 12 53 s, 44 18 s, the rest under 10 s), so no older proof asserts the old world.
- Two traps the first run of the proof itself found, both in the proof: a side-effecting call (`navy_plan_step`, `navy_sail`) inside one `if` expression with a check that depends on it: SQL may evaluate the operands in any order, and did. Every such call is now its own statement.
- `node scripts/db/check-versions.mjs` ok (326, no collision); `tests/duplication.spec.ts` and `tests/sections.spec.ts` 19 passed (the header declares its re-cuts; the self-assert tag opens the FAIL and the receipt). No client file changed, so no browser spec.

## Cost (PGlite, this PC, `--cost`; 0331's PGlite-to-prod ratio is about 6.7)

| Read | Before the file | After |
|---|---|---|
| `harbour_nearest`, the ten capitals' points | 8 to 9 ms | 11 to 14 ms (fenced: the holder is asked of the nearest few) |
| `navy_patrol_build`, Lisbon's station (13 legs, each a `cargo_circuit_plan`) | 52 to 54 ms | 57 to 62 ms |
| `navy_pay`, ten ships at ten harbours | 3 to 4 ms | 2 to 3 ms |
| `navy_hunt_targets`, Lisbon | 3 ms in the cost scene; **290 to 380 ms** read on its own (0340's text, measured today: EXPLAIN shows the planner filtering `ports` first and looping `voyage.reach_from` once a harbour, 245 loops, 193,662 buffer hits, the `nm <= navy_reach_nm` filter re-reading the knob for every row of every loop; the W19 dev-log reported the same 250 to 320 ms) | **3 to 7 ms in both** (1,407 buffer hits): the reach is read once and joined inside `offset 0`, then each surviving harbour's holder is asked |
| `navy_harbour_ok` over every harbour (249) | — | 2 to 3 ms |

So the reader itself is cheap (about 0.01 ms a call here); what costs is where a function test sits in a join, which is why three of the re-cuts are fenced.

## Consumer audit (every reader of a navy ship's harbour or of the navy's money, and what this slice does to it)

| Consumer | Does | Action |
|---|---|---|
| `public.navy_patrol_build` (0331) | writes a station's patrol | **re-cut**: no stop the pirates hold |
| `public.navy_plan_step` (0331, 0338) | one planning step a run | none: it writes a patrol for any station with `legs_at` null, which the drop uses |
| `public.navy_stations_build`, `navy_station_plan`, `navy_station_of` (0331) | the stations | none: a station is a harbour the crown holds, by construction; a fallen one is retired at the next flag change as before |
| `public.harbour_nearest` (0333) | where a call sends a ship (its only caller: `navy_call`; proof 40 predicts a call with it) | **re-cut**: never theirs, fenced |
| `public.navy_call` (0333) | the call | none: it reads `harbour_nearest`; `v_to` null (every harbour theirs) returns the escorts' count, as before |
| `public.navy_reinforce` (0333) | a called ship in port | **re-cut**: a fallen `called_to` frees her |
| `public.navy_arrival`, `battle_sides_come`, `navy_close` (0333) | when she is there; the close | none: `'infinity'` is their existing word for never |
| `public.navy_escort_step` (0333) | the escort | **re-cut**: the ward is bound for an open harbour, fenced |
| `public.navy_ship_step` (0331, 0333, 0340) | her step in port | **re-cut** (3): the next leg, her home, the first leg |
| `public.navy_hunt_step` (0340) | the hunt | none: it receives her home (now never theirs) and reads `navy_hunt_targets` |
| `public.navy_hunt_targets` (0340) | the hunt's harbours | **re-cut**: the reader, fenced |
| `public.navy_add` (0331, 0335) | a hull or a wake | **re-cut**: never for a fallen station |
| `public.navy_commission` (0331) | lays a hull | none: it is handed the station `navy_add` chose |
| `public.navy_pay` (0331, 0335) | the hour | **re-cut**: a slice for a harbour they hold stays at the capital |
| `public.capital_draw`, `crown_call` (0335, 0307) | the realm fills the capital | none: the capital's need is unchanged; what it keeps for a fallen harbour simply is not called next hour |
| `public.navy_sail` (0331) | every leg | **re-cut**: no hands from their quay |
| `public.fleet_hands`, `fleet_stores` (0328, 0331) | hands and stores | none: stores are free and come from no purse |
| `public.refit_yard`, `npc_refit_step` (0322) | who earns a hull or a refit | none (above: named, not changed) |
| `public.tick_navy` (0331, 0340) | the job | none: the same calls, the same answer keys |
| `world.navy_ship_card` (0331, 0333, 0340) | her card | none: `next` reads the legs that exist (empty while a dropped patrol is written again) |
| `public.pirate_hoard`, `pirate_spend_room`, `pirate_pay` (0339) | the pirates' money | none: they receive nothing from a navy now; their own flows are theirs |
| `public.port_nation`, `pirate_power` (0143, 0338) | whose a harbour is; the pirate power | none: composed by the reader |
| `scripts/ops/harness/navy/dark-scene.sql`, `navy-comes/`, `the-navy-hunts/` | parity scenes | unchanged, run before and after this file: equal |
| `src/`, `tests/` | the client | none: no door, no word, no card key changed |

## PROD CHECKS (read-only; each file one statement inside `begin transaction read only; ... commit;`; from the worktree with `supabase/.temp` copied in)

1. `scripts/ops/harness/navy-off-pirate-ports/volatility.sql` first. Run 2026-11-08 at head 0341: `md5` i, `replace` i, `gc_distance_nm` i, `pg_get_functiondef` s, `to_regprocedure` s, `harbour_nearest` s, `navy_hunt_targets` s, `pirate_power` s, `port_nation` s, `realm_capital` s, `sea_danger` s; `navy_harbour_ok` and `navy_patrol_drop` null (not yet deployed). After the deploy: `navy_harbour_ok` s, `navy_patrol_drop` v (never called by a check).
2. **Before the deploy:** `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/navy-off-pirate-ports/before.sql`. **Run 2026-11-08 at head `20260818000341`:** every `fns[]` entry `old_times 1, new_times 0` (the 11 pre-images are prod's own live bodies); every `now_md5` equal to the local dump's; `absent` both true; `premises` all true; `navy_enabled` false; `pirates_bite` true; `navy_ships` 0, `navy_stations` 0, `navy_patrol_legs` 0; `harbours` 249; `pirate_holdings` ["DJE","GOT","LGA","POR"]; **`call_off_por` "POR"** (the leak, measured: today a call off Port Royal would send a navy ship into the pirates' capital); `tagus` "LIS"; `lisbon_targets` 12.

| function | live now (prod 0341) | wanted after the deploy |
|---|---|---|
| `public.harbour_nearest` | a517034a36 | 8e362c7f54 |
| `public.navy_add` | 860769e8f5 | 4e506ed72d |
| `public.navy_escort_step` | 04865a491f | d54c6718e5 |
| `public.navy_hunt_targets` | 8886323bec | e4689bf428 |
| `public.navy_patrol_build` | 8fb7a2e183 | c51103878f |
| `public.navy_pay` | 5287cae6df | 02aba28de5 |
| `public.navy_reinforce` | e8968a8ff2 | 2da5931d96 |
| `public.navy_sail` | a08467d31f | 83315c01be |
| `public.navy_ship_step` | 1d3a866d77 | f9fa3f11de |

(the wanted column is prod's own `with_hunk_md5`, and equals the md5 of each body on the local world after the file.)

3. **After the deploy:** `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/navy-off-pirate-ports/after.sql`. Wanted: `head` `20260818000342`; every `fns[]` entry `new_times 1`, `old_times` 0 except `navy_ship_step` ord 2 (1: the `v_home` line sits inside the new text); `bodies[].now_md5` = the wanted column, `without_hunk_md5` = the live-now column, `attr_md5` equal to before's (`032de395...` for the seven plpgsql bodies, `7d392e0f...` for `harbour_nearest` and `navy_hunt_targets`); `present` {navy_harbour_ok s, navy_patrol_drop v}; `client_callable` 0; `navy_enabled` false; `navy_ships` 0, `navy_stations` 0, `navy_patrol_legs` 0; `pirate_holdings` as before; `reader_refuses` 4 (= the holdings), `por` false, `lis` true, `free` true (or null if every harbour is held), `capitals_ok` true; **`call_off_por` not "POR" and not among the holdings** (SGO on the local world); `tagus` "LIS"; `lisbon_targets` 12 with `lisbon_targets_theirs` 0. Then `bash scripts/ops/health.sh`.

## Deploy order and rollback

- After 0341 (live): `~/bin/bv-deploy.sh <this PR>`, in number order, nothing else between. The file holds no table lock and writes no row; its run is about 0.1 s. No after-check window: nothing changes in play while `navy_enabled` is false; when the owner lights the navy, 0331's 30-minute after-check covers it, and this slice's reads are `navy_pay`'s flows (no `NAVY_PAY` row to a pirate holding, ever) and `navy_ships.station_port` (never a pirate holding).
- **Forward rollback:** `navy_enabled` false is 0331's rollback and holds (she finishes her leg, sails to her station or, if the pirates hold it, to her capital, and is laid up). To remove: a NEW migration swapping each hunk's old and new (every OLD text is in the file) and dropping the two functions.

## Not verified

- The file on prod's real Postgres (PGlite is Postgres compiled to wasm; `disposable-chain` is the real engine). The cost figures are PGlite's; the plan shape (the fence) is the planner's and holds on both.
- Any lit behaviour on prod: no navy ship exists there and the switch is off. The scenes are the local world's (Portugal, Lisbon; the Brethren at Port Royal).
- A real race between `tick_navy` and the daily count handing a city over in the same minute: reasoned (the step reads the flag as it runs; a ship that sailed a minute earlier arrives, is paid at the capital, and leaves at her next step), not raced.
