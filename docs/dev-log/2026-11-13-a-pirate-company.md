# A pirate company, walked lit (migrations 0380 and 0381; owner rows 284 and 324)

Owner, 2026-11-05 (row 284): a player may join the pirates, *"yes they can"*; a pirate player attacking other players is *"not for now"*. Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."*

`pirates_joinable` (0338) has been false since it shipped. Proof 45 and `tests/greatPowers.spec.ts` cover the founding only. Nobody had played a company under the skull. This is that walk, what it found, what was fixed, and the file that lights the knob.

**State: built, two PRs, NOT deployed, nothing lit.** No production read or write was made for this slice. Every figure below is from a throwaway local world (the cached chain at 0367, restored, never replayed from zero), with the switches production runs lit (`economy_closed`, `city_treasury_enabled`, `influence_enabled`, `pirates_bite`, `navy_enabled`, `crew_bite`, `combat_bite`, `levels_bite`, `reputation_on`, `standing_routes_enabled` and the rest of the list in the audit), plus `regard_enabled` (to be lit before this) and `pirates_joinable`.

## What a player sees when it is lit

- **Start** and **Profile > Country** offer eleven flags; the eleventh is The Brethren (해적단), the skull.
- Choosing the skull prints one line under the picker before she presses anything: *"At war with every country: their ports tax you more and charge more to dock. Pirate ports are free. Their ports have no yard."* (Korean: *"모든 나라와 전쟁 중: 다른 나라 항구는 세금과 입항료가 더 비쌈. 해적 항구는 무료. 해적 항구에는 조선소 없음."*)
- "How you begin" then reads *One ship, Gaivota, and 40,000 ducats at Port Royal.*
- She starts at Port Royal with the same Barca and the same 40,000 d. as anyone. Closed, Port Royal's purse pays it (no gold is made).
- The news gets one row: **Pirates: join them** / **해적단: 가입 열림**.

## The walk (real commands, one rolled-back transaction a scene)

| Step | What happened | Verdict |
|---|---|---|
| Found under the skull (`cmd.found_house`, `PIR`) | ok. One fleet docked at Port Royal, 40,000 d., title Apprentice. Closed: every purse plus every company holds the gold it held | works |
| Read every page's data as her, at Port Royal and at Havana (64 `world.*` readers) | every one answers; none refuses, none is null | works |
| Buy at Port Royal | untaxed (tax 0, as for anyone: the four homes are free ports) | works |
| Dock at a pirate home | fee 0; stance "home"; "Tax 0x (home), Dock fee 0, Friendly 200" | works |
| Sail to Havana (Spain), sell 80 allspice | see the table below: she is not turned away and not fined; she is taxed and charged at the war rate | works, costly |
| Standing route (saved, assigned; it bought at Port Royal, sailed and sold at Havana; the return leg was not waited for), captains at Port Royal's inn (five on offer, one hired and seated), invest and donate at Port Royal, insurance quote | all work as for any company. A small cargo loses money at a crown port: 40 annatto bought for 4,499 d. sold for 4,489 d. net and the dock fee was 681 d. Her gifts make influence for the Brethren; she can become mayor of a pirate home; `set_tax` there answers "a pirate port has no tax" | works |
| Build a ship | **No pirate port has a yard** (all four are size 2, yard tier 0; Port Royal says "This city has no yard."). She builds at any crown's yard under the rule every company has (the hull's line against the yard's country). At Havana, 726 nm away: Barca, Chalupa, Patache, Carabela, Carlat, Dunkirk and Zabra are in the yard's reach; 139 of the 157 hulls (0366's 54 among them) belong to other countries' yards, exactly as for a Spanish company there. The Brethren's own ships are laid down at the nearest crown yard too (`public.refit_yard`) | no dead end; no pirate yard (decided by default, below) |
| Go broke | Port Royal gifts her 40,000 d. as a capital gifts any company of its country | works |
| Levels, Reputation | levels and reputation move as for anyone (first landfall: +25, a level: +20). The Countries list shows all ten crowns "Wary -200" | works |
| Met by the navy | not hunted. `navy_hunt_per_day` is 0; if it is ever raised a navy meets a company that is Hostile (-300 or under) or wanted. She starts at -200, Wary. One attack on a cargo ship (-150) makes her Hostile with that country | works as built |
| Raided | **Yes, she is raided like anyone**, by the unnamed raiders of a dangerous sea and by the Brethren's own named ships (`voyage.freeze_raiders` spares only a pirate SHIP's own voyage). What is taken goes to the pirates' hoard, which is her own capital's purse. The Brethren's NPC merchants are raided the same way today, so this is the world's standing rule, not a gap of the knob. 20 trips Port Royal to Havana: no raid for her or for a Spanish control (risk quoted 0.04 % a trip there) | left as it is (decided by default, below) |
| Attack (with `attack_enabled` lit in the scene) | A company: refused, `E_HUMAN_TARGET`, "no player attacks another player". A company attacking hers: refused, the same. A merchant: `E_NOT_A_TARGET`. A ship of the Brethren: `E_YOUR_OWN_COUNTRY`. A crown's cargo ship or navy ship: allowed at sea (docked: "a harbour keeps the peace"), at the regard every company pays | the no-PvP law holds both ways |
| Change country | Her first change is at once (to Spain: the war ends there at once). Back under the skull: `E_TOO_SOON`, 7 days. A Spanish company lying at Seville that changes to the Brethren is taxed 35 % at Seville from that moment | works |
| Knob off again | She stays a company of the Brethren; a new founding under the skull is refused `E_MINOR_POWER` | works |

### What a crown port asks of her (one sale: 80 allspice bought at Port Royal for 39,463 d., sold at Havana for 57,332 d.; profit before tax 17,869 d.)

| Company | Stance at Havana | Tax rate | Tax paid | Dock fee | Kept of the profit |
|---|---|---|---|---|---|
| Spanish (home) | home, Friendly | 3.375 % | 603 | 101 | 17,165 (96 %) |
| A crown at peace with Spain (worked out from the knobs, not sailed) | peace | 15 % | 2,680 | about 450 | about 14,740 (82 %) |
| **The Brethren** | war with all ten, Wary | **35 %** (15 % x 2 war x 1.25 Wary, held at the cap) | 6,254 | about 1,120 (x2.5) | 10,495 (59 %) |

So the skull is a hard choice, not an edge: she keeps about three fifths of a profit a home company keeps whole, at every port a crown holds; the four pirate ports are free, but they are free to everybody. She gains nothing a crown company lacks except that every crown's cargo ship and navy ship is a legal target once attacks are lit (a crown company may not attack its own country's). No unfair edge was found.

## What was wrong, and what was done

| # | Found | Fix |
|---|---|---|
| 1 | The picker offered the skull and said nothing of what it costs; she learnt it at her first sale (tax 35 %) | **0380**: `world.snapshot` names the pirate power (`pirate` on each nation, `public.pirate_power`). The picker prints one line under the grid when it is chosen, at Start and in Profile, EN and KO |
| 2 | Levels > Countries printed the server's English names and flag letters in Korean ("⚔ Castile-Spain 경계 -200") | The rows use the game's own flag-and-name (`HullCountry`), so they read 카스티야-에스파냐 and show the flag picture. This was wrong for every company once `regard_enabled` is lit, not only for a pirate |
| 3 | Her own free port said "Your tax here 0.0% (half: your country)" | The "half" words are printed only beside a tax above 0 |
| 4 | Proof 45 and `tests/greatPowers.spec.ts` assert the knob is false | The lighting PR changes both: proof 45 sets the knob false itself and then lights it; the spec expects eleven on the picker |

## Decided by default (the owner may reverse any)

- **She is raided like anyone, the Brethren's own ships included.** It is what the Brethren's NPC merchants already live under, and freeing her of raids would hand her the one edge this walk did not find. If the owner wants "pirates do not raid a pirate company", it is one small change on the fight path (`voyage.settle`'s raid day), with its own window and the fight after-check.
- **No yard was added at Port Royal.** A yard there is a world-data slice (which hulls a pirate yard builds, its tier) and a design question, not a fix. She builds at crown yards, as the Brethren's own ships do.
- **The note is one fixed line**, not figures: the tax a crown port asks depends on that port's own rate and on her regard, and the Town Hall and the Trade cards already print the real figure for the port in hand.
- **Lighting is a migration (0381), not a hand-written knob write**, so the news row is posted, the guards run, and CI sees the lit world. The owner's one-line write is the rollback.
- **`regard_enabled` is expected lit first** (the brief's order). Lit after instead, nothing breaks: her factor at a crown port is x2 until then and x2.5 after.
- **The pirate ship's empty book** ("a player who boards her loots nothing", row 284) is not touched: a company of the Brethren can never board one (`E_YOUR_OWN_COUNTRY`), so it is a gap of `attack_enabled`, not of this knob.
- **Starting ship name** stays Gaivota and the placeholder company name stays "Casa de Aveiro" under every flag.

## What cannot be undone for a player who joined

- Switching the knob off does not take her out: she stays a company of the Brethren until she changes country herself.
- A company that CHANGES to the Brethren waits 7 days (`nation_change_cooldown_days`) before it may change again. A company FOUNDED under the skull may leave at once (its first change), then waits 7 days.
- Influence she gave under the skull stays the Brethren's, and a mayorship ends with her citizenship (0143's rule for every change of country).
- Regard she lost by attacks stays hers under any flag and fades by its half-life (72 h); only the war base (-200 with every crown) goes when she leaves.

## Proof

- **0380's self-assert** (one DO block, 0.6 s locally): the hunk once and reversing; the snapshot's ACL, volatility, definer, config, owner unmoved; every other function, knob, relation and job unmoved; on a rolled-back copy of the old body, the new answer less `pirate` IS the old answer, and `pirate` is `great_powers.pirate` on all 24 nations.
- **0381's self-assert** (0.6 s locally): refuses unless 0338 and 0380 are in, the knob is false, the Brethren hold their capital; on a rolled-back probe with the knob lit, a company is founded under the skull through `cmd.found_house` and lies at the capital, and closed, no gold is made; kept: the one row true, `nation_joinable` and the snapshot say so, nothing else moved, one news row.
- **Proof 69** (`scripts/db/proofs/69_a_pirate_company.sql`, 7 markers: PICKER, FOUNDED, HOME, AT_WAR, TRADES, NO_PVP, LEAVES): the walk above through the real commands beside a control company of the crown that holds Havana. It owns its switches (it runs green with the knob false or true in the chain). **No outcome of a roll is asserted**: what she is ASKED is checked against the knobs; a sale is checked only against what the sale itself reports; if the sea takes her cargo on the way the marker says so and passes.
- **`tests/pirate.company.spec.ts`** (9 tests; 390 x 844 and 1280 x 800, English and Korean, on the built world with the knob lit by `tests/pirateWorld.fixture.ts`): the picker's eleven and the line; a company founded under the skull by the real door; the Levels list in her language; the free port's tax line; a crown company changing to the Brethren through Profile's own button.
- Harness `scripts/ops/harness/pirate-company/`: `gen-checks.mjs` writes every file there from 0380's own hunk.

## PROD CHECKS (read-only, each file one statement; the lead runs them)

For 0380, in order: `volatility.sql` (every value s or i), `before.sql` (old_times 1, new_times 0, keep now_md5), deploy, `after.sql` (new_times 1, without_hunk_md5 = before's now_md5, pirates ["PIR"], joinable 10, knob false), `bash scripts/ops/health.sh`.

For 0381 (its own window, after `regard_enabled` if that is to be lit): `volatility.sql`; `before-light.sql` (snapshot_names_pirates true, knob false, joinable 10, capital POR held by the pirates, pirate_homes 4, **capital_can_pay true**, companies_of_pirates 0, update_rows 0); deploy; `after-light.sql` at once and at +5 and +30 minutes (knob true, joinable 11, update_rows 1, probe_left 0, capital_can_pay true); `bash scripts/ops/health.sh` at +1, +5, +30.

Rollback of the light: the owner's line `update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable'`. Rollback of 0380: `rollback-0380.sql`, a draft (forward migration).

## Not verified

- Nothing was read on production. `before-light.sql` is the first read of Port Royal's purse, the switches and whether any company already sails for the pirates.
- The founding SCREEN's Start button was not pressed under the skull in a browser: the local browser world founds its one captain at boot, so the screen is reached only as a gallery page (`/ui/gates/found`). The picker and its line were driven there; the founding itself was done through `cmd.found_house`, and the change of country through Profile's real button.
- A battle she starts (attacks are dark): only the door's answers were read, at a docked target.
- A raid on her was not observed (20 trips, none); the rule was read from `voyage.freeze_raiders` and `voyage.settle`.
- Korean wording of the new line and the news title is mine, unchecked by a native reader.
- The migrations on a real Postgres: CI's `disposable-chain`.
