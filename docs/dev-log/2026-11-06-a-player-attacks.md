# A player attacks (W11, migration 0327, owner rows 283, 285, dark)

**State: built, dark, PR open, not deployed.** `attack_enabled` is false since 0323 and this file does not touch it. Nothing changes for anyone until the owner lights it, and the design says that comes after W12-W14.

## What it does, lit

A fleet with guns and an empty hold attacks a cargo ship of another country, at sea, within 240 miles. A 10-minute battle opens. Regard falls at once. At the end, by the fight's outcome:

| Outcome | Gold | Attacker's hands | Her hands |
|---|---|---|---|
| Boarded | 15 % of what is aboard, capped | None | -10 % |
| She paid off | `ransom_share`, 8 %, capped alike | None | None |
| Beaten, or broke off | None | -10 % | -2 % |
| She slipped away | None | None | None |

Every hull at 0: regard falls 100 more; with `npc_refits_enabled` lit she goes home a wreck, after the loot. Caps: 60,000 d. a ship, 240,000 d. a company in any 24 hours, and never more than is aboard.

## What was built

| Part | Where |
|---|---|
| The one attack, every refusal | `public.attack_for` |
| The doors | `cmd.attack`, `cmd.preview_attack` (the real attack, rolled back) |
| What the end does | `public.attack_close`, called by `public.battle_resolve` for kind ATTACK |
| Gold | `public.loot_take`, `public.loot_due`, `public.loot_today`; `public.convoy_book` stage `LOOTED`; kind `LOOT`, moved |
| Words of a preview | `public.attack_word`, `public.funds_band` |
| Where a fleet is | `voyage.fleet_point` |
| Laps | `cargo_ships.last_attacked_lap` |
| The card | `src/live/AttackSection.tsx`, inside `CargoSheet`, served by `card.attack` |
| Words | EN and KO: refusal codes, card, Loot in the Money log, History's line |

New knobs, none on an existing key: `loot_share` 0.15, `loot_per_ship` 60000, `loot_per_company_day` 240000, `attack_reach_nm` 240, `attack_cooldown_minutes` 30, `attack_crew_lost` {beaten 0.10, boarded 0.10, drove_off 0.02}, `attack_word_bands` [0.7, 1.3, 2], `regard_attack_cargo` -150, `regard_sink` -100.

## Bodies re-cut (hunks, each once and reversing)

`public.battle_open` (1), `public.battle_resolve` (3), `public.convoy_book` (1), `world.cargo_ship_card` (1), `public.client_rpc_entry_points` (1). `public.tg_convoy_cargo_closes` needs no hunk: it counts every row of a load, whatever its stage. #525 (0324) cuts none of these. #527 (Levels) cuts `client_rpc_entry_points` on another line.

The only readers of `convoy_cargo` are `cargo_ship_aboard`, `convoy_book` and the trigger, read from the catalog, so a `LOOTED` row needs nothing else.

## Win rates (`node scripts/ops/harness/raid/sim.mjs --sides 500`)

The run the doc requires before lighting. 500 fights each, W5's core, prod's class figures read 2026-11-06, whole hulls, level 1, no captain, no gear. `won` pays gold. **One sample, not a balance claim.** The last four rows are added: they are the ship that sails today.

| Attacker | Target | Won % | Boarded | Paid off | Driven off | Slipped or broke off | Her hull lost % | Attacker's hull lost % |
|---|---|---|---|---|---|---|---|---|
| 1 xebec | navire | 0.0 | 0.0 | 0.0 | 21.0 | 79.0 | 0.5 | 17.1 |
| 2 xebecs | navire | 22.0 | 0.0 | 22.0 | 33.6 | 44.4 | 2.1 | 14.1 |
| 1 nau | navire | 77.0 | 0.0 | 77.0 | 17.2 | 5.8 | 7.7 | 10.5 |
| 2 galion | navire | 100.0 | 100.0 | 0.0 | 0.0 | 0.0 | 47.0 | 2.0 |
| 1 xebec | galion | 0.0 | 0.0 | 0.0 | 9.6 | 90.4 | 0.1 | 26.8 |
| 2 xebecs | galion | 0.0 | 0.0 | 0.0 | 28.4 | 71.6 | 0.5 | 18.7 |
| 1 nau | galion | 0.0 | 0.0 | 0.0 | 53.2 | 46.8 | 1.8 | 15.7 |
| 2 galion | galion | 99.6 | 99.6 | 0.0 | 0.4 | 0.0 | 28.5 | 7.1 |
| 1 xebec | crewless qpinnace | 92.4 | 92.4 | 0.0 | 0.0 | 7.6 | 19.0 | 0.0 |
| 2 xebecs | crewless qpinnace | 95.8 | 95.8 | 0.0 | 0.0 | 4.2 | 41.0 | 0.0 |
| 1 nau | crewless qpinnace | 100.0 | 100.0 | 0.0 | 0.0 | 0.0 | 68.3 | 0.0 |
| 2 galion | crewless qpinnace | 100.0 | 100.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0.0 |

## What the owner should see before lighting (not now)

- **Today's cargo ship cannot fight back.** She is a crewless `qpinnace` with no guns: every side wins at least 92 % and takes no hit. Light attacks before W8 and it is free gold: 240,000 d. a company a day, at no risk.
- **Against an armed `navire`, a xebec never wins.** The cheapest armed hull (160,000 d.) loses to the hull W8 plans. Side `b` breaks off at 15 % of its hull lost, so a small attacker leaves. A `nau` wins by a ransom, not a boarding. Only 2 `galion` board.
- **The card already prints her exact funds** (0310). The preview's band ("Light", "Heavy") hides nothing while that line stands. It is left as it is: changing it is a play change the owner did not order.
- **`regard_enabled` is its own switch.** Lit attacks with dark regard cost no regard at all.
- **`npc_refits_enabled` is its own switch.** Dark, a sunk ship sails on at hull 0, and is patched free where she docks.

## Decided by default (the owner may reverse)

From the brief, standing: no attack on ordinary merchants; none on your own country's ships; no player attacks a player; loot gold only, 15 %, 60,000, 240,000; reach 240 miles, 30-minute cooldown, one attack a ship a lap; a docked fleet is never attacked.

Decided here:
- **A door, not a verb of `cmd.parse`.** The design's 4.2 says verb, its slice row says `cmd.attack`. A queue runs only in port, so a verb could never fire at sea.
- A ransom a player takes is `LOOT`, under the same caps. The doc's `RANSOM` kind is a company paying pirates.
- The company cap is a rolling 24 hours, read from the ledger.
- The crew rates are one new knob, through `public.raid_crew_lost`, so a Surgeon saves hands here too.
- A ship that slipped away costs nobody a hand: nothing was fought. The doc's row says "beaten or broke off".
- A docked fleet may attack, and goes `IN_BATTLE`. The doc measures reach from a port, and it is never a target.
- A ship with no lap (no `out_load`) counts as lap 0: she takes one attack until she next loads.
- `E_NOT_IN_USE` at the door, as the doc says. `public.battle_open`'s own `E_NOT_YET` stands behind it.
- Funds band: None, Light, Heavy, where Heavy means a boarding would reach `loot_per_ship`. No new knob.
- Word bands 0.7, 1.3, 2, the last being `fight_standoff_ratio`'s figure. A knob.
- A running battle still pays after the switch goes off, as 4.6 says.
- The battle's gold reads at the end, not the start. If the job lags past the hold she may have delivered some, and the loot is a share of what is left.

Not built, on purpose: Break off (`BROKEN_OFF` still has no writer), the War fleet label, combat points for levels, `regard_attack_navy`, `regard_pirate`, "Navy arrives": none has a target or a slot in this slice's row.

## Proof

- `scripts/db/proofs/34_a_player_attacks.sql`, 15 markers, **economy closed**, real `voyage.settle`, real cargo step, real battle close, real job. The outcome is asked for by name so each row of the table has its own test; `ATTACK_REAL_FIGHT` takes the real engine.
- `scripts/ops/harness/attacks/proof-0327.mjs`: red on the world without the file; 49 mutations each red; real file and proof green, also with 0324 applied first. Five mutations first came back wrong, and three of those were the proof's fault: the live figure was read only after a fold, a null slipped past `<>`, and a probe's close was not proved here. All fixed.
- One mutation was dropped: skipping `attack_for`'s settle cannot go red, because `battle_open` settles again and refuses the same way. The settle stands, as D.2 orders.
- `tests/rpc.attack.spec.ts`: the seam, through the client's RPC layer, and `AttackSection` rendered to nothing while dark.
- Self-assert: catalog and `loot_due`'s arithmetic only, about 120 ms locally. No game step.
- **Dark parity:** proof 34 puts the old card and the old book back and compares: every cargo ship's card, and the book's two closing stages. Proof 31 runs the probe path on the new body in CI.
- **The race (one attack a lap, one day's room):** PGlite has one connection, so this is reasoned, not raced. The fleet row is locked before a lap or a load is read; the house is locked before the day is read; two attacks on one ship meet on her fleet row.

## Load

`docs/OPS_HEALTH.md` section 2: no cron change, no new job, no hot body. `attack_for` and `attack_close` run only on a press and on a battle's end. The file re-checks `battles_kind_check` and `convoy_cargo_stage_check` over their tables (438 and few rows on prod at reading). Not measured on a populated world.

## PROD CHECKS (read-only, `scripts/ops/harness/attacks/before.sql`, one SELECT, no volatile game function)

Run 2026-11-06 at head 0323: every hunk once, nothing of 0327 there, `attack_enabled` false, no ATTACK battle, 100 cargo ships, 438 book rows. **Run it again before deploying, at the head before 0327.** After the deploy: `attack_enabled` false, 0 `LOOTED` rows, 0 ATTACK battles. No after-check window is owed: nothing changes while dark.

## Rollback

`attack_enabled` stays false. To remove: a new forward migration swaps the file's old and new, then drops what it created. Regard and loot already written stay.

## Not verified

- Nothing has run on prod.
- The Attack section in a real browser: no screen was opened. It is rendered dark in a spec; lit, the button's look, its wrap and the phone layout are unseen. No picture exists.
- A real 10-minute battle by the real clock, or the job firing: the proof hands every call its instant.
- Two real clients racing.
- A cargo ship's real next stop after a loot: the proof closes the rest of her load through the book, not through a sailed lap.
- A wreck's insurance day on a held voyage: a cargo ship is not insured, so it does not arise here.
- W5's raid replay in `sim.mjs`: only `--sides` was run. The sim has no gear, captains or levels.
- `disposable-chain` on real Postgres roles until CI says so; see the PR.

## Rows for the coordinator (not written here, parallel PRs)

**docs/OWNER_REQUESTS.md rows 283, 285:** `PART BUILT - W11 player attacks, migration 0327, dark, PR open, not deployed. OPEN: navies, W12-W14; lighting is the owner's, after W8 arms the cargo ship.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **A PLAYER ATTACKS (W11, owner rows 283, 285) - migration 0327, DARK, PR open, NOT deployed, follows 0326:** cmd.attack, preview, loot moved not minted, regard hooks, card button, report, words. attack_enabled false. Read before lighting: today's crewless cargo ship loses at least 92 % of fights and never fires. Dev-log docs/dev-log/2026-11-06-a-player-attacks.md.`
