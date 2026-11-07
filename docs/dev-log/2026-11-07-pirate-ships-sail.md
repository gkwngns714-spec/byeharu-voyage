# Pirate ships sail (W17, migration 0339, owner row 284): the Brethren's ships, the hazard hand-off, stow, RANSOM, LOOT

Owner, 2026-11-05: *"pirate headquarters with pirate cities, npcs that attack these ships as well as merchants"*; *"pirates are like countries - power, where they can also invest. pirate merchants too"*. 2026-11-06 (row 306): *"use your recommended defaults for the rest"*. 2026-11-07: *"do it fast"*; and, while this was built, *"you need to make a build for pirate ships as well"* (row 291's words on looks: *"the ship type should be distinguished, as in graphics or as in color. day and night"*). Step 2 of 4 (W16 to W19) of `docs/WORLD_POWERS.md` Part 5; the design row is 7.7 W17: "Kind, size, map, hazard hand-off, stow, RANSOM, book". Built on W16 (0338), which was deployed while this was being built: prod head read `20260818000338` at the PROD CHECK below.

**State: built, dark, PR not yet open (the coordinator opens it after #552's merge is confirmed), not deployed.** `pirates_bite` ships false; nothing changes in play until the owner lights it in a window of his own.

## What a player sees after the deploy

- Nothing, until `pirates_bite` is set true. Then, within the hour: Port Royal builds a **xebec** (the hoard pays Santiago's yard 160,000 d.), and one a day until the Brethren rest at their number (hoard 993.6 M d. today: 13 ships; 4 at a hoard of 0, 30 at 2.6 B). Ord 1 sails from Port Royal, 2 from Djerba, 3 from Goto, 4 from Lingga, 5 from Port Royal again.
- **On the map, the sea roster and the Codex:** a **coral fish-tailed hull with an X on her deck**, by day and by night, named *Pirate ship N* under the skull. Tapping her opens her sheet: home, Out/Home, the haunt she cruises, her hull. Codex > Ships gains a *Pirate ship* card with their count while any is at work. The picture: `docs/dev-log/2026-11-07-pirate-ships-sail/four-kinds-day-night-2x.png` (the real chart renderer, the built stylesheet, DPR 2, the four kinds side by side at night, twilight and day).
- **Where she goes:** out of her home to the harbour one merchant course away whose sea is the most dangerous (Port Royal's is Paramaribo; Goto's Nagasaki, Hirado or Kagoshima; Djerba's Tripoli, Valletta or Tunis; Lingga's Malacca, Banten or Jakarta), lies there 12 hours, sails home, is mended, sails again. While she is out, her sea is half again as dangerous (`sea_danger` x 1.5) and **every fleet that leaves port with a leg through that sea has her name frozen on that leg**: a PIRATES day there is fought against her (one xebec: strength 12.7 against the anonymous 18-28 of the Caribbean), not the anonymous xebecs.
- **What a raid costs now:** plundered goods land in her home's market (up to twice its target; the rest is lost at sea), so Port Royal, Goto, Lingga and Djerba get cheap plunder to sell. A ship that pays her off pays **8 % of her cargo's cost basis** from her company's purse to the pirate home (RANSOM; a purse that cannot pay pays what it holds). A crown's cargo ship plundered loses the day's share of the funds aboard to the pirate home (LOOT). Nothing is minted: W is the same to the ducat.
- Her home's market **stops regenerating** (stock is plunder, not production) while the switch is on.
- A player with guns at sea within 240 nm may attack her once attacks are lit (`attack_enabled`, still false): regard -50 with the Brethren, no WANTED. She carries no gold to loot (below).
- The owner's window: `pirates_bite` true is one knob write; false again sends every ship home and lays her up, names nobody on new departures, empties the sea's pressure, and the homes regenerate again. Hulls remain.

## CONTRACT (what W18 and W19 may rely on): as committed at `1e572a5d`, with these changes

The contract text committed first (`W17 contract`, 2026-11-07) stands as written in that commit, with exactly these changes made while building:

| Contract said | Built | Why |
|---|---|---|
| `voyage.freeze_raiders(p_segments)` | `voyage.freeze_raiders(p_segments jsonb, p_fleet uuid)` | a pirate ship's own departure must not name herself (pirates do not raid pirates) |
| `public.pirate_side(p_fleet)` | **not added**: W19 passes `voyage.fleet_hulls(pirate)` (0323's one builder of a side) | a wrapper would be a second copy of one rule |
| `public.pirate_loot_book` opens a book on her (stage LOADED) delivered at home | `public.pirate_loot_book(p_fleet, p_victim, p_share, p_event)` keeps the name and the signature; the gold is her **home's purse at once** (LOOT, moved); she carries no book | the design's book needed a fifth `convoy_cargo` stage, two trigger hunks and three readers for one sum; nothing of W18/W19 reads it |
| `pirate_ships.sea_id` is "the sea she is cruising (set as she leaves home, cleared as she docks home)" | **`sea_id` is her sea WHILE SHE CRUISES OUT AND LIES AT HER HAUNT; on the home leg she is in no sea** (it is nulled as she sails for home): she names nobody, adds no pressure, and W19's hunt cannot find her on the way home. In any port that is not her haunt (her home, a wreck's respawn at it, a stranding) `pirate_ship_step` clears `sea_id`, `haunt_port`, `haunt_since` and sets mission HOME before anything else. | the review (2026-11-07): a wreck respawned home kept a stale `sea_id`, so every departure through that sea was frozen with a 0-hull raider while the sea stayed x1.5 |
| `pirate_ship_in_sea` excludes IN_BATTLE | reads **`public.pirate_ships_cruising`**, THE ONE RULE of "she is in a sea" (a view: at work, `sea_id` set, `fleets.status` in SAILING / DOCKED / ANCHORED, a hull with durability > 0), so a wreck, a ship under repair, one in a battle and a hulk are never named; `pirate_pressure_write` counts the same view, so what cannot be named presses on nothing. W19 asks `pirate_ship_in_sea(sea)` exactly as contracted. | same review |
| `pirate_size_for(bigint)` | added beside `pirate_size()` (the formula on a figure, for the self-assert) | |
| `public.pirate_pay(p_kind, p_amount, p_now, p_port, p_player)` | as said; **paying the capital itself answers the amount and writes nothing** | the navy's rule |
| `pirate_ships.ord` | unique over the whole power, homes by `public.pirate_home_of(ord)`: capital first, then by code, wrapping | |
| `world.pirate_ship_card` fields | `fleet, nation_code, home, haunt, mission (HOME/CRUISE), laid_up, to, eta, ships, attack?` | |
| `tick_pirates` answers `{steps, added, paid, pressure}` | as said | |

Everything else (tables, knobs, the money kinds, `pirates_on`, `pirate_nation`, `pirate_capital`, `pirate_hoard`, `pirate_spend_room`, `pirate_ship_in_sea`, `voyage.pirate_strength`, `voyage.leg_raider`, `pirate_stow`, `pirate_ransom`, `pirate_pressure_write`, `pirate_commission`, `pirate_add`, `pirate_pay_hour`, `pirate_ship_step`, the hunks) is as the contract says. `voyage.plunder_share(voyage, day, outcome)` was added (lifted out of `raid_takes`) so the goods' share and the gold's are one roll.

## The review's two lit-only defects, fixed before the deploy (read-only Fable review of the file, 2026-11-07)

1. **Stale position.** `sea_id` was set only as she sailed and never cleared when she was found in a port; a wreck respawned at her home (0322 + the `fleet_origin` hunk) kept `sea_id = S`, so every departure through S would have been frozen with her as raider at `voyage.pirate_strength` 0 (a 0-hull squadron: every PIRATES day there a free win) while `pirate_pressure_write` kept S at x1.5; the same for a ship stranded at a port with no stored course home. Fixed in the NEW functions only (no hunk moved; the 14 md5 pairs stand): the one rule of "she is in a sea" is the view `public.pirate_ships_cruising` (at work, `sea_id` set, free to fight, a hull left), read by `pirate_ship_in_sea` and `pirate_pressure_write` and by nothing else (the self-assert counts its readers); the step clears her position in any port that is not her haunt. Proof 46: PIR_WRECK (a wreck with a stale position names nobody, presses on nothing, a departure through its sea is frozen with no raider, the step clears her) and PIR_POSITION (a hulk, a ship under repair, one in a battle: not in her sea; free again: in it; stranded: cleared; on the home leg: in no sea). Mutations: "a hulk is named", "a wreck keeps her position", "the pressure skips the one rule".
2. **`pirate_stow` locked the goods catalogue**: `select ... for update` over `port_goods join goods` inside `voyage.settle` (inside the beat) took a lock on the `goods` row too. Now `for update of pg`: the market row alone. The self-assert reads the function's text for it; mutation "the stow locks the catalogue".
3. **The contract's words** (above): her position holds while she cruises out and lies at her haunt, not "to the moment she docks home".

Two notes the review asked to be said: only the NAMED raider is suppressed on a pirate ship's own voyage (`voyage.freeze_raiders` skips a pirate fleet), so the anonymous PIRATES hazard of the sea can still plunder or wreck her, which is the path into finding 1 (a wreck respawns home: now with no position). And a human house named exactly "Brethren ship N" would make `pirate_commission`'s insert into `players` fail on that ord: the same exposure the navy has with "Crown Navy XXX N" (a warning a minute in the job's log, nothing else; the next ord is unaffected).

## Decided by default (the owner may reverse any)

- **No book on a pirate ship.** The gold she takes from a cargo ship is her home's at once. A player boarding her finds nothing yet; a later slice can give her a book when the navy hunts her (W19) and the attack is lit.
- **A named raider fights at her own strength**, whatever the day's magnitude (one xebec: 12.7). The anonymous day is today's figure to the digit. With one xebec she is weaker than the Caribbean's anonymous band (18 to 28 at magnitude 0.5), and stronger than a quiet sea's; the owner's knob `pirate_ship_class` makes her a bigger hull.
- **Stow and RANSOM only when the raider is named**: an anonymous xebec has no home.
- **The cruise is one stored merchant course out and back** (`public.npc_courses`, the way home required), the most dangerous sea first, spread by ord. No multi-leg patrol yet: the three new homes have three courses each, Port Royal two.
- **The hoard's purse is the pirate capital** (Port Royal), and the yard it pays is the nearest by sea, whoever holds it (a pirate home has none): the hoard really leaves the Brethren.
- **The navy's knobs are reused**, not copied: `navy_upkeep_day` (60,000 d. a ship a day), `navy_build_hours`, `navy_reach_nm`, `navy_store_days`, `navy_steps_per_run`.
- **`regard_pirate` -50** with the Brethren for a player's attack on her; **the pirates write no WANTED row** (they have no navy to answer). The hunt's regard with the ten is W19's.
- **A voyage frozen lit and settled dark fights what it departed into** (DESIGN D.2), as W14 decided: the rollback stops new departures naming her; a voyage already out keeps its segment.
- **Her colour is coral `#ff9696`, not the design's `#ff6b6b`**: measured below.
- **Her hull is a fish with a crescent tail**, 7 CSS px half-length like the navy's, beam 0.46, waist 0.4 of it, a forked stern; her mark is an X of two 2.1 px bars.

## The consumer audit (every reader of a ship kind, and what each does with a pirate ship after this slice alone)

Server (the live bodies of the cached head world at 0338, function by function):

| Consumer | With a PIRATE row | Action |
|---|---|---|
| `public.fleet_kind` | would answer COMPANY (a human's) | **re-cut: PIRATE**, after the navy test |
| `public.fleet_origin` | null: a wreck would raise E_NO_ORIGIN | **re-cut: her home**, so 0322's wreck and refit take her unchanged (REFIT from her home's purse; patched free while the rule is dark) |
| `public.crown_house` (dock fee, the stats' merchant count) | she would pay dock fees and count as a merchant at sea | **re-cut: true for her house** |
| `public.crown_nation` (attack_for's own-country test, attack_close's regard and wanted) | null: `regard_add` with a null nation, and a null in the wanted mark | **re-cut: the Brethren** |
| `public.sea_houses` (the map's two reads, the roster) | not on the sea at all | **re-cut: her house, kind PIRATE, while at work**; `world.sea_roster` and `world.sea_traffic` serve `kind` from here with no change |
| `public.fleet_wage` | she would owe her hands a wage | **re-cut: 0, as a navy ship's** |
| `public.cargo_figures` (Codex) | no entry | **re-cut: `pirate_ships` while one is at work** |
| `public.client_rpc_entry_points` | no card | **re-cut: `world.pirate_ship_card`** |
| `voyage.depart` | no raider frozen | **re-cut: `freeze_raiders` after `freeze_danger`** |
| `voyage.settle` PIRATES arm | anonymous | **re-cut (5 hunks)**: the named raider's strength, stow, LOOT, RANSOM, the payload's `pirate` key (absent on an anonymous day) |
| `voyage.raid_takes` | | **re-cut: the share lifted** into `voyage.plunder_share` |
| `public.attack_for` | E_NOT_A_TARGET | **re-cut: kind PIRATE**, `regard_pirate`, reason ATTACK_PIRATE |
| `public.attack_close` | a WANTED row for the Brethren | **re-cut: none for the pirates** |
| `public.tick_market_drift` | the homes regenerate | **re-cut (3 hunks): held while lit**, one constant and no call dark |
| `public.npc_wrecked`, `npc_refit_step`, `voyage.npc_wreck`, `fleet_patched`, `fleet_mend` | read `fleet_origin` | take her through the re-cut; no change |
| `public.fleet_hands`, `fleet_stores`, `voyage.fleet_speed`, the voyage engine | a fleet is a fleet | no change |
| `public.port_fee`, `stats_live_track`, `stats_live_fold` | read `crown_house` | no change |
| `public.navy_call`, `battle_open`, `battle_resolve`, `battle_stop`, `tick_battles` | a defender at sea; her country has no navy ship | no change (proved: a battle on her resolves; no call) |
| `public.loot_take` (a player boards her) | `cargo_ships` has no row: 0 | no change (she carries no book) |
| `world.fleets`, `world.navy_ship_card`, `world.cargo_ship_card`, `world.npc_fleet_card` | not hers | no change; her card is her own |
| `world.sea_danger` (Z2, not open) | `reason` null | no change; her presence shows through the level |
| `public.tick_navy`, `navy_*` | loop their own tables | no change; W19 adds the hunt |
| `public.funds_aboard` | reads cargo ships' books | no change (she has none) |

Client, scripts and tests:

- **Changed**: `src/chart/glyphs.ts` (`ShipKind` + `pirate`, `KindMark` + `x`, `KIND_LOOK.pirate`, `PIRATE_HULL`, `pirateHullPath`, `kindMarkPath('x')`, `shipKindOf` reads `pirate`), `liveWorld.ts` (kind PIRATE → her hull and `pirate: true`), `mapTypes.ts`, `chart/index.ts`; `src/lib/rpc/types.ts` (`kind` union, `PirateShipCard`, `StatsNow.pirate_ships`), `catalog.ts` and `index.ts` (`worldPirateShipCard`); `src/index.css` (`--color-pirate-hull`); `src/live/CargoHull.tsx` (`PirateHull`), new `PirateSheet.tsx` and `usePirateShipCard.ts`; `MapScreen.tsx` (a tapped PIRATE row opens her sheet); `ShipsFace.tsx` (the Codex card); the dictionaries (`map.pirateShip` 해적선, `pirateHome` 본거지, `haunt` 출몰지, `mission_CRUISE` Out 출항, `mission_HOME` Home 귀항; `codex.pirateNote`; `feed.k_RANSOM` 몸값); `tests/map.kinds.spec.ts` (her rows: the contrast law on every ground, her own colour, the silhouette law against every hull, the mark width, the parity row, the four-kinds picture).
- **Fine as they are**: `FleetsLayer.tsx` (one `hullPath`, one `HullGroup`, `kindMarkPath` once, no kind named: the spec holds it), `shipMarks.ts` (reads `KIND_LOOK[...].thin`), `AttackSection` (any card with `fleet.id` and `attack`), `HullCountry` (the skull), the feed's headline (the server's sentence), `crownWord.ts` (`CrownHull` is what a player may build: not her).
- **Not changed, named**: the Korean sweep does not cover the new sheet; the words are in the dictionary and `tests/i18n.keys.spec.ts` holds EN and KO equal.

## The 21 hunks over 14 live bodies (each once, each reversing; prod's bodies at 0338 are the pre-images: `before.sql` printed `[ord, 1, 0]` for every one)

`public.fleet_kind` 1, `public.fleet_origin` 1, `public.crown_house` 1, `public.crown_nation` 1, `public.sea_houses` 1, `public.fleet_wage` 1, `public.cargo_figures` 1, `public.client_rpc_entry_points` 1, `voyage.raid_takes` 1, `voyage.depart` 1, `voyage.settle` 5, `public.attack_for` 2, `public.attack_close` 1, `public.tick_market_drift` 3. New: 26 functions (listed in the file's `c_new_fns`), 3 tables (`pirate_ships`, `pirate_spend_day`, `pirate_clock`), 1 view, 10 knobs, the word RANSOM (moved), the cron job `byeharu-voyage:pirates`.

## The look, measured (`tests/map.kinds.spec.ts`, the built stylesheet, 23 passed)

| Ground | fill | keyline | mark on fill |
|---|---:|---:|---:|
| night sea (both schemes) | **9.38** | 1.00 | 9.20 |
| day sea | 2.15 | **3.63** | 7.81 |
| day deep | **3.94** | 1.98 | 7.81 |
| day shallow | 1.13 | **8.81** | 7.81 |
| twilight 0, 0.25, 0.5, 0.75, 1 | fill or keyline 3 : 1 at each | | |

Why coral and not the design's `#ff6b6b`: on the day deep and at twilight 0.25 the dark keyline cannot carry a hull (1.98 and about 2.5 to 1), so the fill must, and that takes a luminance near the navy violet's 0.44; `#ff6b6b` is 0.33 (2.97 on deep, failed), `#ff9696` is 0.45. Her fill is one colour whatever her nation, day and night, and a hue apart from cargo teal (219 of 441), navy violet (121) and the merchant blue (224). Silhouette: her pixels differ from every other hull's by **30 % or more** of her area at 1x and 2x (navy 0.40, cargo 0.93, the nearest capital hull `fore-5` 0.30). Her X: two bars 2.1 CSS px thick at her shortest 7. Pictures: `docs/dev-log/2026-11-07-pirate-ships-sail/four-kinds-day-night-2x.png` (DPR 2, the owner's laptop; night, twilight, day; chart size at two headings and 4x) and the kinds table in `docs/dev-log/2026-11-06-cargo-colour/kinds-{1x,2x}.png`, re-rendered with her row.

## Proof

- **The migration's own self-assert** (catalog, stable reads and arithmetic; one `do` block, 150 ms locally): every hunk once and reversing; md5 over every other function unmoved; config, words, the ACL/volatility/definer/config of the 14 unmoved; the cron job alone added; the switch off; no row written but the one clock row; `pirate_ship_class` is the raider's armed class with a price; the size formula on seven probe hoards (`4,4,4,5,13,30,30`); dark, the freeze is the identity on a probe path and no sea has a ship; `voyage.plunder_share` is 0213's arithmetic on a probe voyage; the room, the capital, the first home; 15 readers stable; every new function server-only but the card, which is exactly authenticated-only and registered; no client can read a pirate table. A second apply refuses.
- **Proof 46** (`scripts/db/proofs/46_pirate_ships_sail.sql`, 20 markers, 1.0 s on the cached world): PIR_DARK (off: the job writes nothing; a departure's path is `freeze_danger`'s byte for byte; a PIRATES day is the anonymous 18.00 with no `pirate` key; kinds, origins, houses, the sea, the card), PIR_NEEDS_PURSES, PIR_BROKE (hoard 0: room 0, no hull, no flow), PIR_SIZE (4 at 0, 7 at 300 M), PIR_BUILD (160,000 d. POR → SGO, two moved rows, no ledger row; one crewless xebec at Port Royal, her house PIR at 0; one a day; the spend written and the room fallen by it), PIR_SPEND (a payee house paid whole from the room or not at all; W unchanged), PIR_KIND, PIR_CRUISE (she sails for Paramaribo in the most dangerous sea in reach; `sea_id`, CRUISE, named in it; her own voyage names nobody), PIR_PRESSURE (0.12 x 1.5 = 0.18), PIR_RAID (a company's fleet leaving while she cruises has her name frozen on the segment of her sea; a real PIRATES day through `voyage.settle` at her strength 12.70; PLUNDERED, 10 abaca taken, 3 stowed: the cap 2 x target holds, the rest lost; the payload names her and her home), PIR_LOOT (a crown's cargo ship plundered: 318,827 of 1,000,000 aboard, LOOTED on her book, LOOT at Port Royal, set aside down by it, W unchanged), PIR_RANSOM (paid off through the real settle: 50,000 of the 80,000 asked, company to Port Royal, kind RANSOM on both books; direct 80,000 on 1,000,000; nothing at the cap), PIR_REGEN (lit: Port Royal held at 50, Lisbon moved; off: Port Royal moved), PIR_PAY (2,500 d. to Paramaribo, once an hour, nothing at the capital; unpaid she went home and was laid up; woken), PIR_OFF (switch off with her out: home, laid up, nobody named, pressure gone, nothing paid), PIR_WRECK (a wreck respawned home with the position of her lost cruise: `pirate_ship_in_sea` names nobody, `pirate_pressure_write` writes no row, a departure through that sea is frozen with no raider, and the step clears her position; patched free dark; lit, Port Royal paid 40,000 d. REFIT, moved), PIR_POSITION (lying at her haunt with a hull: named, one pressure row; a hulk, a ship under repair, one in a battle: not named, no row; free again: named; stranded at Lisbon with a position still set: the step clears it, IDLE), PIR_CARD, PIR_ATTACK (attacks lit: a war fleet at sea attacks her: regard -50 with the Brethren, ATTACK_PIRATE; the battle resolves PLUNDERED; no WANTED row), PIR_MONEY (W unchanged to the ducat).
- **Harness** `scripts/ops/harness/pirate-ships-sail/proof-0339.mjs` (local, cached world, nothing from zero, nothing written to the cache): RED FIRST (proof 46 on the world with no file: red); DARK PARITY (`dark-scene.sql`, 21 lines before and after the file: the map's two reads, who is on the sea, kinds, origins, crowns, wages, fees, a 960-day departure's frozen path byte for byte, **960 raid days settled through the real engine with the voyage id pinned, every payload digested**, the lifted share's stream, a pirate home's regen at a pinned clock, the money figures, the attack door's refusal of a merchant, the job with the switch off); the real file and proof 46; `--cost`; the mutation controls (`mutations-0339.mjs`). The first run found the scene's own hull rolling her figures (0276): pinned. Results: see the lines under "Harness run" below.
- `tsc -b` clean; eslint clean on every touched file; `tests/sections.spec.ts`, `tests/duplication.spec.ts` ("every migration proves itself", "a re-cut declares the supersede"), `tests/i18n.keys.spec.ts`: 23 passed; `tests/map.kinds.spec.ts`: 23 passed on the built stylesheet; `db:check-versions` ok (323 migrations, no collision); `vite build` ok.

## Hot paths, priced

`voyage.depart` dark gains one stable call that returns its argument (`freeze_raiders`: one knob read); `voyage.settle`'s PIRATES arm gains one jsonb key read on a PIRATES day; `tick_market_drift` gains one constant column per harbour (no call while dark). The `--cost` lines of the harness run are below.

## Harness run (`proof-0339.mjs --cost`, 2026-11-07, the cached head world at 0338, 322 of 322 restored, 0 applied)

- **RED FIRST, no file:** red (`world_config key pirate_ship_class does not exist`).
- **DARK PARITY:** 21 scene lines before (45 s) and after (44 s), **every one equal**: roster `31d56e47…`, roster keys, the merchant's row, traffic 240 / 847, houses, figures, kinds `CARGO_SHIP MERCHANT COMPANY`, origins, crown, wage `0 / 180 / 60`, fee `0 / 255 / 64`, **path `31e9227f…` (960 segments)**, share, **raids 960 / 960 `5234fa5c…`** (outcomes EVADED 873, RANSOM 8, DRIVEN_OFF 79; the hull and hands after: 1800, 60), regen `dbb861c5…`, at_sea, fold, attack_merchant `E_NOT_A_TARGET`, moved 1 / 1.
- **POSITIVE CONTROL:** the file (self-assert ok, 75 ms) and proof 46, 20 of 20 markers, 670 ms.
- **COST (dark, ms a call, before → after):** first run `voyage.depart` 1.48 → 1.68 (200 calls: the one knob read); a PIRATES day through `voyage.settle` 5.92 → 6.00 (12 days); `tick_market_drift` on one harbour 19.0 → 9.3 (3 runs; the first run warms the cache: noise, not a gain). The run after the review fixes, on a busier machine: 1.72 → 2.14, 8.33 → 6.17, 20.0 → 9.7. A stopwatch on wasm, read for the order of the cost: a departure dark costs one knob read more.
- **MUTATION CONTROLS: 40 red as required** (36 in the first run, which found 7 wrong: three holes in the proof, a null compared with `<>`, only the first segment read, no gold during the dark tick; a regex; three controls that did not break anything; each fixed in the proof or the control, never in the file; four more with the review's fixes: a hulk is named, a wreck keeps her position, the stow locks the catalogue, the pressure skips the one rule).
- **After the review's fixes** (the same run on the file as it stands): red first; the 21 dark-parity lines equal; proof 46 20 of 20; 40 controls red; **all 43 older proofs (01 to 45) green** on the chain with the file, each in a rolled-back transaction, proofs 30 and 38 with their allow-lists (a planted third caller of `ransom_take` and a planted second writer of `sea_pressure` each turn its marker red, naming the planted function).

## PROD CHECKS (read-only; each file is one statement; run from the worktree, `supabase/.temp` copied in)

Volatility first: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-ships-sail/volatility.sql` (wanted: every value `s` or `i`; the new readers null before the deploy, `s` after). **Run 2026-11-07 ~12:30 UTC at head 0338:** `md5` i, `pg_get_functiondef` s, `to_regprocedure` s, `replace` i, `treasury_balance` s, `realm_purse` s, `port_is_free` s, `client_rpc_entry_points` s; the new readers null.

- **Before:** `scripts/ops/harness/pirate-ships-sail/before.sql`. **Run 2026-11-07 ~12:30 UTC at head `20260818000338`:** every `fns[].times` entry `[ord, 1, 0]` (the 21 hunks' old text once, the new never: prod's bodies are the pre-images); `absent` all true; `sea_pressure_rows` 0; pirate PIR, capital POR, homes DJE GOT LGA POR, held 4, **hoard 993,596,028** (the formula would keep 13; room 4,967,980 a day); raider class xebec (attack 60, hull 530, 35 hands, tier 2, 160,000 d.); courses out of the homes DJE 3, GOT 3, LGA 3, POR 2; LOOT moved; knobs: purses lit, closed, `combat_bite` true, `navy_enabled` false, `attack_enabled` false, `regard_enabled` false, **`npc_refits_enabled` true** (a wrecked pirate ship is refit from Port Royal's purse on prod, REFIT), `pirate_ports_free` true, `pirates_joinable` false.
- **After:** `scripts/ops/harness/pirate-ships-sail/after.sql`. Wanted: head `20260818000339`; every `fns[].times` entry `[ord, 0, 1]` **except** the hunks whose old text sits inside the new (`fleet_kind` 1, `fleet_origin` 1, `crown_house` 1, `crown_nation` 1, `sea_houses` 1, `cargo_figures` 1, `client_rpc_entry_points` 1, `settle` 1 and 3 and 5, `tick_market_drift` 1: those print `[ord, 1, 1]`); `now_md5` = before's `with_hunks_md5` and `without_hunks_md5` = before's `now_md5`; `attr_md5` equal to before's; `present` all true; `switch` false; `pirates_on` false; the ten knobs as shipped; word `["moved","Ransom",54]`; cron `[["* * * * *","select public.tick_pirates()",true]]`; `pirate_ships` 0; `spend_rows` 0; `clock` `[[true,null,null]]`; `sea_pressure_rows` 0; `size` 13 and `room` floor(hoard x 0.005) at the hoard of the moment; capital POR; first_home POR; `ship_in_any_sea` 0; `freeze_identity` true; `entry_point` 1; `card_grants` `[true,false]`; `client_can_call_a_pirate_fn` 1 (the card).

The 14 live bodies, hashed on prod at head 0338 by `before.sql` (the first 10 hex of each md5), and what each must hash to after the deploy:

| function | live now (prod 0338) | wanted after the deploy |
|---|---|---|
| `public.attack_close` | 327e46e121 | d3fde1e3fe |
| `public.attack_for` | adcf4f5918 | 53309a5e81 |
| `public.cargo_figures` | 9a75db134d | bb9f749b67 |
| `public.client_rpc_entry_points` | d6d4c4ebc7 | afa5be7ee6 |
| `public.crown_house` | 8dbdcc6980 | 53640f966f |
| `public.crown_nation` | c6c3a26971 | 066a4d61ea |
| `public.fleet_kind` | 0506d1d6ee | 33a146d87e |
| `public.fleet_origin` | ff2d42f9c5 | 6589a23428 |
| `public.fleet_wage` | 39aea38cf3 | 8b6ff54d4c |
| `public.sea_houses` | e53087e5d8 | 94ea8562bb |
| `public.tick_market_drift` | 74d3152f10 | e61a9c644c |
| `voyage.depart` | 06e9b69d17 | d8cb03b14d |
| `voyage.raid_takes` | 73437e04a0 | b05fa92594 |
| `voyage.settle` | e62b827887 | 4cf174adb4 |

- `bash scripts/ops/health.sh` after the deploy. The deploy itself changes no play (dark): the job runs every minute and reads one knob and one empty table.

**When the owner lights `pirates_bite`: a 30-minute after-check** (the first hull within a minute, the first cruise within the hour): `tick_pirates` duration in the job log, `E_*` in the order log, Port Royal's purse and flows (BUILD_NAVY, NAVY_PAY), `pirate_ships` rows and `sea_pressure`, the arrivals beat unchanged. **Forward rollback, ready:** `update public.world_config set value = 'false'::jsonb where key = 'pirates_bite'` (owner only): every ship sails home and is laid up, no new departure names her, the pressure empties, the homes regenerate again.

## Not verified

- The migration on a real Postgres with the clock unwound: PGlite is Postgres 18 compiled to wasm; CI's `disposable-chain` is the real engine for this file.
- What 13 pirate ships do to the four homes' markets and purses over a day, lit: the after-check reads it. Lit, the job costs about one navy ship's step a ship a minute (the same functions); dark it is one knob read.
- A ship on prod's map is not seen until the owner lights the switch: the pictures are the real renderer on the real sea with the four kinds placed, not a row the job built.
- The RANSOM band through the real fight depends on the sides: the proof sweeps a probe crew of 60 to 149 and found it at the first try twice; a fight is a fight.

## Rollback

Dark: nothing to switch off. Lit: the knob (above). To remove: a NEW migration swapping the hunks (each OLD text is in the file), dropping the functions, the tables, the knobs, the word and the cron job; owner only.
