# The navy hunts (W19, migration 0341 provisional, owner rows 284, 285): the Hunt mission, navy against pirate, the pirate regard row

Owner, 2026-11-05: *"npcs that attack these ships as well as merchants"*; *"each country will also have battle ships. they defend or attack pirates"*; players may attack navy ships (yes). 2026-11-06 (row 306): *"use your recommended defaults for the rest"*. 2026-11-07: *"do it fast"*. Step 4 of 4 (W16 to W19) of `docs/WORLD_POWERS.md` Part 5; the design row is 7.7 W19: "Hunt mission, navy against pirate, regard hooks"; its proof: "At most once an hour; fight written on both hulls; arrivals bound". Built on W16 (0338, PR #552) and on W17's CONTRACT (`docs/dev-log/2026-11-07-pirate-ships-sail.md`, "What W19 may rely on, exactly"), nothing else of W17.

**State: built, rebased on 0339 (`pirate-ships-sail` at `d516e4ef`, itself on origin/main) and proved on it; branch `navy-hunts`, no PR yet (it opens after W17 and W18 are merged).** Built first against W17's contract on a local stub of it, then on W17's own file (its three differences below). Prod head 0338 at ~12:20 UTC (0337 when the build began; `navy_enabled` false, `npc_refits_enabled` true, `regard_enabled` false, `attack_enabled` false, no navy ship). `before.sql` run on prod at head 0338: every one of the 8 hunks occurs exactly once in prod's own live bodies, so the hunks were cut against prod's text. The number 0341 is provisional (W18 is 0340 unless it is ready later); it stands in the file's name, this log, `scripts/ops/harness/the-navy-hunts/proof-0341.mjs` and the self-assert's messages, nowhere else.

## Where W17's file differs from its contract (read from `wt-pirate-ships`' draft 0339, 2026-11-07 ~12:30 UTC; nothing of it edited)

1. **No `public.pirate_side`.** The draft has `voyage.pirate_strength` for the hazard and no side builder. So the pirate ship's side is `voyage.fleet_hulls(pirate)`, THE one builder of a fleet as a side (0323, what every battle builds its sides with); a second builder would be a second authority. The fight call is otherwise the contract's: `fight_sides(navy fleet, UTC hour, pirate hulls, navy hulls, '{}')`. The guard no longer asks for `pirate_side`.
2. **The knob name `regard_pirate` is 0339's:** the press-time cost with the Brethren (-50, reason `ATTACK_PIRATE`, in `attack_for`), with the comment "the hunt's regard with the ten is W19's". The design's row names `regard_pirate` for the +30; this file's knob is **`regard_pirate_beaten`** (30): the close's reward with every great power but the pirates. Two knobs, two different things, one name each.
3. **`public.crown_nation` answers the Brethren for a pirate ship** (0339's hunk), so 0333's sink line in `attack_close` writes `regard_sink` (-100) with the Brethren when a company sinks her, and 0339's own `attack_close` hunk keeps the pirates off the WANTED list. This file changes neither: a pirate sunk costs regard with the Brethren by 0333's line and 0339's nation, and earns `regard_pirate_beaten` with the ten by this file's hook. Proof 48 (NH_REGARD) asserts exactly that: ten DROVE_OFF lines, one SINK line and it with the Brethren, none of the ten's with the Brethren.

## What it does, lit (both `navy_enabled` AND `pirates_bite`; dark it is byte-identical, below)

**The Hunt** (6.4: *"Sails to the sea with the highest sea_danger in reach"*). A navy ship at her station, on duty, reads every sea within `navy_reach_nm` sailed of the station (her own too), each at `voyage.sea_danger` NOW, so a pirate ship's pressure (W17 writes `sea_pressure`) counts, the most dangerous first (`public.navy_hunt_targets`, STABLE, so a prod check may ask it). Her own sea the most dangerous: she lies at her station, watching, for `navy_hunt_hours` (6). Another sea: she sails for its nearest open harbour a course reaches (the first three seas are tried), a real voyage through `public.navy_sail` (hands, free stores, `voyage.depart`), mission **HUNT**, and lies there `navy_hunt_hours` from her arrival; then she sails home and picks again. Nothing in reach, or the pirates dark: she patrols as before. She is never turned at sea (W13's rule): the hunt is decided in port, as every step of hers. She is mended free at her station as she sets out, as a patrol's end mends her.

**Navy against pirate** (6.4: *"both in one sea at a job pass: one fight_sides, no timer, nobody watching, at most once an hour a ship"*). `public.navy_hunt_pass`, from `public.tick_navy` every minute before the ships' steps, at most `navy_hunts_per_run` (5) fights a run. For each navy ship at work and on duty, in no battle, with a hull left and no fight inside the hour: her sea now (`public.fleet_sea`: her port's sea in port; at sea the sea of her voyage's current segment, `voyage.position`'s closed form; at anchor the sea of her point), then THE reader of who is there, `public.pirate_ship_in_sea(sea)` (W17's). Null: no fight. Found, whole, in no battle, no fight of hers inside the hour: both rows taken `SKIP LOCKED`, both settled (D.2), then `public.navy_fight`:

- ONE `public.fight_sides(p_seed := her fleet, p_round := the UTC hour, p_a := voyage.fleet_hulls(pirate), p_b := voyage.fleet_hulls(navy), '{}')`, as the contract says (its `pirate_side` is not in 0339: both sides come from the one builder). The same hour fought twice is the same fight.
- Hull loss lands on BOTH through `public.fight_hulls_write`, THE hull writer, lifted from `public.battle_resolve` (the statement 0323 wrote and every battle closes with). One copy.
- **The hour.** `navy_ships.fought_at` (new, this file's) and `pirate_ships.fought_at` (W17's column, W19's to write) are both stamped; a ship with either stamp inside the hour is passed over. Both stamps, because the rule is "a ship", and a second navy ship meeting the same pirate inside the hour must not fight her either. No table of fights: one row each.
- After the hulls, the lines a battle's close uses and no new path: a ship in port whose flagship is at 0 is `UNABLE_TO_SAIL` (0323's line); every hull at 0 at sea under 0322's rule is `voyage.npc_wreck` at once (0333's lines): a pirate ship respawns at her home, and `public.npc_refit_step` pays her REFIT from her home's purse (W17's `fleet_origin`); a navy ship at her station's cost. A wreck in port is found by her step (`navy_ship_step` answers WRECK; W17's step the same).
- **Reported.** One public event, `public.emit_event(null, 'NAVY_FIGHT', {navy{fleet, name, nation}, pirate{fleet, name, home}, sea, at, result, outcome, hull_lost{navy, pirate}, sunk{navy, pirate}})`: the world's own line, player null, as `ECONOMY_SWITCH` is (DESIGN J.3 names a world feed of public events in the Ledger; it is not built: see "Decided by default"). And her last fight on her card: `navy_ships.fought {at, result, foe, sea}`, served as `fought` by `world.navy_ship_card` only after one. `result`: **WON** (she boarded, or was paid off), **LOST** (thrown back, or she broke off hurt), **DREW** (stood off, slipped, nobody touched), **SUNK** (every pirate hull at 0).
- No gold moves in a fight: no purse, no book, no ledger row. W (players + merchants + purses + set aside + funds aboard) is unchanged, proved in every scene.

**The regard hook** (2.1, the pirate row that is a fight's: *"Drive off a pirate ship | +30, every great power"*). In `public.attack_close`: a company whose attack beat a pirate ship (boarded, paid off, or every hull at 0) earns `regard_pirate_beaten` (30; the design's name `regard_pirate` is 0339's press-time knob, above) with EVERY great power but the pirates, reason `DROVE_OFF_PIRATE`, once a battle, through `public.regard_add` (dark with `regard_enabled`: writes nothing). Beaten by her: nothing. Sinking her also costs `regard_sink` with the Brethren, by 0333's sink line and 0339's `crown_nation`, not by anything here. A navy's own fight moves no regard (no company is party to it).

**The player sees** (after the deploy, lit): on a navy ship's card, Duty **Hunt / 소탕** while she hunts, and after a fight a line **Last fight / 최근 교전 · Won / 이김 (Lost / 짐, Broke off / 물러남, Sunk her / 격침) · Pirate ship 3**. On the map: the navy ship sailing for a pirate's sea and lying at a harbour there; nothing animates (law 4). Dark: nothing, anywhere.

## Arrivals bound

A patrol is `navy_patrol_stops` + 1 legs (4) in about 45 minutes. A hunt is 2 legs (out and home) and a lie of `navy_hunt_hours` (6 h), or 0 legs and a lie at her station. So a hunting ship makes FEWER arrivals than a patrolling one: the design's estimate for 75 ships (about 7 arrivals a minute, 6.5) stands as the bound, and proof 48 (NH_ARRIVALS) counts a hunter's legs in her hunt's window (2) against her patrol's (4 on the probe world). The fight itself is no voyage and no arrival.

## Consumer audit (every reader of a navy fight, of the feed's kinds, and of the navy's missions, and what each does with a navy-against-pirate fight after this slice alone)

Read from the live bodies at head 0338 and from `src/`, `tests/`:

| Consumer | With a navy-against-pirate fight | Action |
|---|---|---|
| `public.battle_resolve` (0323, 0333) | writes a battle's hulls | **re-cut**: the statement lifted into `public.fight_hulls_write`, the one writer; a battle closes as before |
| `public.attack_close` (0327, 0333, 0334) | gold, hands, the sink, WANTED | **re-cut**: the pirate regard row before 0334's mark; `crown_nation` null for a pirate ship keeps the sink and the mark silent |
| `public.navy_close`, `public.battle_sides_come`, `public.battle_navy_served`, `world.fleets` (`navy_at`) | battles only (`battles`, `battle_sides`) | none: the navy's fight with a pirate is no battle row, has no sheet and no clock |
| `public.tick_navy` (0331) | the job | **re-cut**: the hunt pass, lit only; `fights` key only when it ran |
| `public.navy_ship_step` (0331, 0333) | her step in port | **re-cut**: the hunt's step after her home is read; WRECK for a hull at 0 as before |
| `public.navy_call`, `public.navy_escort_step`, `public.navy_reinforce` | a called or escorting ship | none: a ship with `battle_id` is not fought; an escort in a pirate's sea is (she is at work) |
| `public.navy_add`, `public.navy_pay` (0331, 0335) | duty, pay | none: a hunter is paid as a patroller, by ord; an unpaid ship hunts nothing (`navy_on_duty`) |
| `world.navy_ship_card` (0331, 0333) | her card | **re-cut**: `fought` after a fight only; `mission` serves HUNT |
| `public.sea_houses`, `world.sea_roster`, `world.sea_traffic` (0310, 0331) | the map's rows | none: kind NAVY and her house are what they were; a hunt is a voyage like a patrol |
| `public.fleet_kind`, `fleet_origin`, `crown_house`, `crown_nation` | what she is | none |
| `public.npc_wrecked`, `voyage.npc_wreck`, `public.npc_refit_step`, `public.tick_npc_refits` (0322) | a wreck | none: the fight calls them as 0333's sink does; the hourly job finds a wreck in port |
| `public.stats_live_track`, `stats_live_fold`, `cargo_figures` | counts of ships at sea, the Codex | none: a navy ship at sea is counted as before, fighting or not |
| `public.regard_add`, `regard_of`, `world.levels` | regard | the hook writes `DROVE_OFF_PIRATE` lines with the ten; 0333's sink line writes `SINK_CARGO` with the Brethren (0339's nation); dark, nothing |
| `public.events`, `public.emit_event` (0004) | the record | one more public kind, `NAVY_FIGHT`, player null, beside `ECONOMY_SWITCH` |
| `world.ledger` (0009) | a company's History | none: it serves `player_id = the caller` only, so a public line is never served to anyone (RLS `events_read_own` the same) |
| `src/features/ledger/headline.ts`, `ledgerFigures.ts` (the feed's kinds) | a company's History rows | none: `NAVY_FIGHT` never reaches a company; an unknown kind would fall to its name, legibly |
| `src/app/TopBar.tsx` (`CAPITAL_GIFT`) | one kind | none |
| `src/live/NavySheet.tsx`, `src/lib/rpc/types.ts` (`NavyShipCard`) | the card | **changed**: `mission` HUNT with its word; the Last fight row, `map.fight_*` |
| `src/lib/i18n/dict/map.ts` | the words | **changed**: Hunt 소탕, Last fight 최근 교전, Won 이김, Lost 짐, Broke off 물러남, Sunk her 격침 |
| `tests/rpc.attack.spec.ts` | the mission words | **changed**: `mission_HUNT` and the fight words checked in both languages, the card's `fought` read back through the client's RPC layer |
| `tests/rpc.surface.spec.ts` | the client-callable surface | none: every new function is server-only; the card's signature is unchanged |
| `scripts/ops/harness/navy/dark-scene.sql`, `navy-comes/dark-scene.sql` | parity scenes | unchanged, run before and after this file: equal |
| `world.sea_danger()` (`reason`, W17's) | the map's danger levels | none |

## Decided by default (the owner may reverse any)

- **Where the hour-stamp lives:** on BOTH ships (`navy_ships.fought_at`, mine; `pirate_ships.fought_at`, W17's column that the contract gives W19 to write), because "at most once an hour a ship" is a rule about each ship, and only a stamp on the pirate keeps a second navy ship off her inside the hour. The hour itself is no knob: the contract keys the fight by the UTC hour, so a shorter interval would fight the same fight twice.
- **The world feed.** DESIGN J.3 names "a world feed of notable public events" in the Ledger; nothing serves public events to a client today (`world.ledger` and RLS serve a company its own rows). So the fight is written as a public event (`NAVY_FIGHT`, player null, the shape a feed will read) and shown where a player looks today: her card's Last fight. Building the feed is a screen of its own, not this slice.
- **The Hunt replaces the patrol while lit**, not beside it: a ship on duty at her station hunts when the pirates are lit and patrols when they are not. Her own sea the most dangerous: she lies at her station rather than sailing to a neighbour of the same sea. `navy_hunt_hours` 6: half a pirate's haunt (`pirate_haunt_hours` 12), so a haunt sees two lies.
- **Who fights:** on duty only (`navy_on_duty`), as the call does; an escort, a patroller and a hunter alike, in port or at sea, at anchor too. A ship in a battle, or whose pirate is in one, waits. A wreck fights nobody.
- **The pass runs before the steps**, so a ship sunk in port this minute is found by her step the same run.
- **The result words** are the navy's view of `fight_sides`' outcome from the pirate's side: PLUNDERED and RANSOM are WON, DRIVEN_OFF is LOST, EVADED is DREW, every pirate hull at 0 is SUNK.
- **The regard hook is at the close, not the press**, because the design's word is *drive off*, and a press that paid would be farmed (press, lose, press again, each hour, ten powers). 0339's press-time line is a COST with the Brethren (-50), not a reward, so the two do not overlap: a press costs, a win pays. The trade row (-5 at a pirate port, 7.6) is the pirate port's limit, W18's table.
- **No gold anywhere:** a navy's fight moves none, by construction; a refit after it is 0322's, moved.
- Knobs the design did not name: `navy_hunt_hours` 6, `navy_hunts_per_run` 5. `regard_pirate_beaten` 30 is the design's +30 under its own name.

## Bodies re-cut (8 hunks, each once, each reversing; read on the world at head 0338 + the W17 stub)

`public.tick_navy` (3), `public.navy_ship_step` (2), `public.battle_resolve` (1), `public.attack_close` (1), `world.navy_ship_card` (1). Lifted, same statement, one copy: `public.fight_hulls_write` (from `battle_resolve`). New: 7 functions, 4 columns, 3 knobs. No job, no entry point, no money word.

## Dark

- Both switches off: `tick_navy` answers `{plan, steps, added, paid}` as before (the `fights` key is served only when the pass ran); a ship's step reaches the hunt only on duty with the pirates lit; the card serves `fought` only after a fight; a battle's hulls are written by the same statement, lifted.
- `scripts/ops/harness/the-navy-hunts/dark-scene.sql` (12 lines): both darks (navy off; navy on, pirates off): the job's whole answer and its keys, her step, her row, her card's keys, a PROBE battle resolved through the real bodies. Equal before and after the file, with the `navy` (16) and `navy-comes` (10) scenes.

## Proof

- `scripts/db/proofs/48_the_navy_hunts.sql`: 12 markers, the real job, step, voyage engine, fight writer, wreck and refit, economy CLOSED as prod. The fight is asked for by name where a scene needs a known loss (HIT: 10 off every pirate hull, 7 off every navy hull; SUNK; NAVY_SUNK), as proof 40 asks it; NH_REAL takes the real engine. Pirate ships are made by the hands every fleet is made by and their rows written straight: W17's own doings are W17's proof's.
- `scripts/ops/harness/the-navy-hunts/proof-0341.mjs`, run 2026-11-07 ~13:05 UTC on the cached world at head 0338 with W17's 0339 applied on it (322 of 323 restored, one applied; the same run at ~12:15 on a local stub of the contract, `--first=`, gave the same lines): **RED FIRST** (proof 48 with no file: `column n.fought_at does not exist`); **DARK PARITY** equal, the `navy` scene (16 lines), the `navy-comes` scene (10) and this slice's own (11), before and after the file; **the real file and proof 48 green**, 12 of 12 markers, the whole in 1.2 to 1.8 s; **OLD PROOFS** 31, 34, 37 and 40 green on the file (0.3, 2.6, 1.7, 2.2 s); **34 mutations red, each for its own reason** (`mutations-0341.mjs`). The first run found six holes in the proof, each closed before anything was committed: four null-comparison traps (`<>` against a stamp or a card key that was not there passed, the trap 0328 and 0331 met: `is distinct from` now), one rule unproved (the navy ship's own stamp holding her when the pirate's was wiped: NH_ONCE tests it with the second ship laid up), one unproved (an unpaid ship at her station hunting: NH_LIES tests it), and one mutation that was no breakage (a comment change), replaced by a battle that writes no hull.
- **The real engine** (NH_REAL): a galion against a xebec came out WON and SUNK on two runs (the seed is the battle's id and the hour); hull_lost added up to the hull lost on both sides, both stamps, W unchanged to the ducat.
- **Self-assert**: catalog and stable reads, 69 to 138 ms locally; Lisbon reads 12 seas in reach.
- **Cost** (`--cost`, PGlite, this PC, the probe world): the pass **dark 0.00 ms** (one knob read: it is not called at all with the navy off, and answers null after one read with the pirates off); **lit with no pirate ship out 0.00 ms** (one read of W17's view); **lit with the design's 75 navy hulls in port and 30 pirate ships cruising other seas 3 to 6 ms** a pass (every ship reads her sea and asks `pirate_ship_in_sea`; nobody fights); `navy_hunt_targets` 1 to 2 ms a station, read once per pick (every 6 hours a ship at most). At 0331's PGlite-to-prod ratio of about 6.7, the lit pass is about 20 to 40 ms a minute on prod with every hull at work, under the navy job's own 0.2 s a minute. A fight itself is one `fight_sides` (a raid's cost) plus two settles, at most 5 a run.
- `tsc -b` clean; eslint clean on the touched files; `db:check-versions` ok (323 files, no collision; it does not read the gap at 0339 / 0340); `tests/i18n.keys.spec.ts` and `tests/sections.spec.ts` 12 passed. `tests/rpc.attack.spec.ts` gains the HUNT and Last fight words and the card's `fought` read back through the client's RPC layer: it needs the built world, which needs 0339 in the tree (this file refuses a world without W17), so it runs after the rebase.

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/the-navy-hunts/before.sql`. Every `times` 1, `keys` 0, `columns` 0, `fn_pass` null, `navy_on` false, `pirates_bite` false, every `pirate_objects` value present (W17 deployed), `navy_ships` 0, `hunt_rows` 0, `public_fights` 0, head = the file before this one.
- After deploy: `scripts/ops/harness/the-navy-hunts/after.sql`. `navy_on`, `pirates_on`, `hunts_on` false; `keys` 3 with the knobs as shipped; `columns` 4; `fns` 7; `client_callable` 0; `navy_ships` 0; `hunt_rows` 0; `fought` 0; `public_fights` 0; `lisbon_targets` > 1 with `lisbon_own` true; head this file.
- `bash scripts/ops/health.sh`. No after-check window is owed: nothing changes while dark.

## Rollback

Forward, owner only: `pirates_bite` false: no hunt and no fight; a ship out on a hunt sails home at her next port and patrols. `navy_enabled` false: 0331's rollback. To remove: a NEW migration swapping each hunk's old and new (every OLD text is in the file) and dropping what it created.

## Not verified

- Anything on prod beyond the read-only state above (no navy ship exists there; both switches are off).
- Real-Postgres behaviour is CI's `disposable-chain`; local runs are PGlite, on 0339 as committed at `d516e4ef` (and before that on a stub of its contract). `npm run build` (the world image with 0341 on the chain, 28.5 s) and `tests/rpc.attack.spec.ts` (6 passed: the HUNT and Last fight words in both languages, the card's `fought` read back through the RPC layer) ran on that chain.
- Two real sessions on the two `SKIP LOCKED` rows: reasoned, not raced.
- The pass's cost on prod with 75 hulls and 30 pirate ships: projected from PGlite (below), not measured.
- The Last fight row in a browser: type-checked, built, the words checked in a spec; no row is NAVY dark, so no picture exists.
