# The navy comes (W13, migration 0333, owner rows 285, 286, dark)

Owner: *"if a fight is made in pacifics, it would need a longer time for the navy to defend, which the fight whould be finished before arrival"*; and players may attack navy ships.

**State: built, dark, PR open, not deployed.** It needs `attack_enabled` and `navy_enabled`, both false on prod. Number 0333, after 0332 (#538), which cuts other bodies. W14 (0334, branch `wanted`) lands on top of it, unchanged.

## What it does, lit

A battle of kind ATTACK calls the country of the ship set upon.

1. **Her escort joins at once.** If a navy ship is escorting that very ship, she is on the sheet at the start and is held like the two who started it.
2. **Other ships are sent for.** The soonest `navy_call_ships` (3) on duty make for the harbour nearest the site.
   - In port past her port time, she sails now. That is a real voyage, with hands and stores, as every leg.
   - At sea, she **finishes her leg** and sails from there. Nothing turns a ship.
   - If none can be in time, the soonest sails anyway: she is the late ship.
   - Beyond `navy_reach_nm` (2,400 sailed miles), she is not called.
3. **The join rule, one line:** on the sheet if `arrives_at <= resolves_at`.
   - At the close each called ship is settled and her arrival read again, so a storm counts and the estimate at the call does not.
   - The job running late changes nothing. A ship that docked after the clock is late, even if the job closes the battle after she docked.
4. **At the end:** every called ship is freed, the late ones sail on, and the report has one more line: "The navy came up before it ended.", "The navy came too late.", "Her country's ship fought alone." or "No navy came."
5. **Wanted is W14's.** 0334 marks her when she won, or when no ship of the country reached the sheet in time. This file fills the sheet it reads.

**Escort.** While funds are at sea, the last ship of a realm's line on duty sails for the port the richest cargo ship of her country is bound for, leg after leg, one leg behind. No such ship, or `navy_escorts` 0: she patrols. She is mended free in her own country's harbours.

**Attacking a navy ship.** W14's row does not own this, so it is here. `attack_for` takes kind NAVY. Regard -250 (`regard_attack_navy`), reason `ATTACK_NAVY`. Once in 60 minutes a ship (`attack_ship_minutes`), by anyone: she has no lap. No gold: she carries none. Your own country refused. Sunk: `regard_sink`, reason `SINK_NAVY`, and her station takes her.

**The player sees:** on the Attack section, **Navy arrives / About 6 min**, when a ship would. On the fleet card, **In battle 7:24 · Navy arrives 5:10**. Attack on the navy ship's card. Mission words Escort 호위, Called 출동.

## No ship counted twice

- `navy_ships.battle_id` holds one battle, so she answers one call. A ship with one is not called and cannot be attacked (`E_FLEET_BUSY`).
- The key of `battle_sides` keeps her once on a sheet. An escort is not also a called ship.
- A press takes each ship `SKIP LOCKED`: it never waits on the job, and a ship the job holds just does not answer.

## W14 (0334), read and agreed

Branch `wanted` landed while this was being built, so the one-line hook first written here was taken out. A stub would have clashed with its `create function public.wanted_mark`, and a second decision would have been two authorities.

- **0334 owns all of it:** `public.wanted`, `public.wanted_mark`, `public.navy_arrived` and the decision, in its one hunk in `public.attack_close`.
- **0333 fills what that reads:** `public.battle_sides`, `arrives_at` re-read at the close.
- **Two things kept for its hunk:** the `return` line of `public.attack_close` is left alone, so `public.navy_close` is called from `public.battle_resolve`. And `c.nation_id` is her country for a navy ship too, so its line reads the right nation with no change.
- **Tried together:** `proof-0333.mjs --w14=<copy of branch>` applies 0333 then 0334 at head 0331. Its hunks land, proof 41 is green, and proof 40 is green with the real rows: a late ship and no ship write one row, a ship in time with the attacker beaten writes none. Without 0334, proof 40 checks the same reading.
- **Its rule, not mine:** a navy ship set upon is no answer to her own attack, so if she beats him alone he is still marked.

## Bodies re-cut (19 hunks, each once, each reversing; read on prod at head 0331, `before.sql`, all `times` 1)

These supersede the same lines of 0323, 0327 and 0331.

`public.battle_open` (2), `public.battle_resolve` (3), `public.attack_for` (6), `public.attack_close` (4), `public.navy_ship_step` (2), `world.navy_ship_card` (1), `world.fleets` (1).

Lifted, same statements, one copy each: `public.battle_stop` (from `battle_open`), `public.navy_on_duty` (from `navy_ship_step`).

New: 12 functions, 4 knobs, `battle_sides.how`, `navy_ships.battle_id`, `called_to`, `escort_of`.

Client, landing together: `NavySheet` shows `AttackSection`, which now takes any card with `fleet.id` and `attack`; the preview row; the card clock in `fleetDue`; EN and KO words; `navy_at`, `navy_minutes` and the two new missions in the types.

## Dark

- Kind PROBE never calls. Every OPENED side has `arrives_at` = `joined_at`, so the sheet is the old list in the old order. `navy_ships` is empty on prod, so `navy_ship_step` never runs. A free fleet reads `{}` in `world.fleets` with no query.
- `scripts/ops/harness/navy-comes/dark-scene.sql` (10 lines): a company's `world.fleets`, both doors, a PROBE battle opened and closed through the real bodies, every row it writes. Equal before and after the file, with the `rich-cities` (15), `armed-cargo` (5) and `navy` (16) scenes.
- First version of that scene compared a battle's outcome, which is seeded by a random id, so it differed run to run. It compares presence now.

## Proof

- `scripts/db/proofs/40_the_navy_comes.sql`: 15 markers, the real attack, voyage engine, step and close, economy CLOSED as prod, and `NC_OPEN` with it open, as CI's own world. The fight is asked for by name; `NC_REAL` takes the real engine. Instants are handed to every call.
- **The bar:** `NC_JOINS`, a ship whose arrival equals the clock is in the fight. `NC_ONE_MINUTE`, a ship 60 seconds past is not, whether the job ran before she arrived or 5 seconds after; she stays on the list, is freed, sails on and docks. `NC_WANTED`, with 0334 in the world, the row itself. The probe world's legs are shorter than a minute, so that scene slows her voyage 20 times.
- `scripts/ops/harness/navy-comes/proof-0333.mjs`: red first, scenes equal, real file green, proofs 31, 34 and 37 green on the file, 55 mutations each red for their reason, on the world at head 0331.
- Harness runs found: `f` as a variable clashing with a table alias in `navy_call`; a proof reading a table in the same expression as a volatile call (the trap 0328 and 0331 met); proof ords above the country's number; and eight mutations that passed, each a hole in the proof: speeds are rolled per hull, so "the soonest two" hid a bad ship; a null passed `<>`; nothing tested the harbour away from the capital; nothing tested her fighting alone. All fixed in the proof.
- `tests/battle.hold.spec.ts`: the card clock. `tests/rpc.attack.spec.ts`: her card through the client's RPC layer, every word in both languages.
- Self-assert: catalog and stable reads, no row, no game step, about 150 ms locally.

## Load

No new job, no cron change. Nothing on the beat. `battle_resolve` adds one read of `battle_sides` when a battle closes. `world.fleets` adds a read only for a fleet with a `busy_until`.

A press is the cost. PGlite, this PC, 24 hulls in port, median of 12. The prod column is the × 6.7 of 0331's dev-log, arithmetic, not a measurement.

| | PGlite | Projected prod |
|---|---:|---:|
| `harbour_nearest` | 3.1 ms | 21 ms |
| `navy_arrival` over 24 hulls | 46 ms | 0.3 s |
| One path (`cargo_circuit_plan`) | 24 ms | 0.16 s |
| Escort step, first of the line | 2.5 ms | 17 ms |

**So a press or a preview on a 24-ship realm is about 0.3 s plus 0.16 s a ship in port: about 0.8 s at worst.** The preview is the real attack rolled back, so opening the card pays that too, with `attack_enabled` lit. An escort's plan adds one path a leg, about 15 escorts at a leg in about 11 minutes: about 1.4 paths a minute.

## Decided by default

- **A ship at sea finishes her leg.** Turning needs a path from a point of open sea, and the server has only port to port. `cmd.divert` is a player's, on a player's plotted course. See "Owner must see".
- Reach is `navy_reach_nm`, the 2,400 sailed miles a station covers, from the port she is in or bound for.
- `navy_call_ships` 3. The design names no number. Two `galion` beat one `galion` 99.6 % of the time (W11's table), so one ship would not stop two.
- The harbour nearest the site by the crow, ties by code. She is on the sheet on reaching it, as the design says; the miles from that harbour to the site are not sailed.
- Late ship: one only, the soonest, and only if none can be in time.
- Escort: the last on-duty ship of the line, not the first, so a 2-ship power keeps its capital's station. `navy_escorts` 1.
- She follows the richest ship read at each port, which may change ward.
- Hands and gold stay the ship set upon's. A ship that came loses hull in the fight and no hands.
- A sink's regard counts each defender sunk, so sinking three ships costs three times.
- A ship sunk in port (a called ship waiting) is found by her next step, as any wreck in port.
- A called ship cannot be attacked: `E_FLEET_BUSY`.
- `navy_enabled` off: no call and no escort. `regard_attack_navy` -250 as the design. `E_SHIP_FOUGHT_THIS_LAP` is reused for the hour; its words say "this lap", a small mismatch on a navy ship.
- The report's lines are server sentences in English, as every line of a report.

## Owner must see

1. **Most ships at sea will be late.** A leg is about 11 minutes and a battle 10, and a ship finishes her leg first. So the answer is mostly the ships in port and the one escort. Whether that feels like a navy that comes is only known by playing. Turning a ship is a real slice: it needs a server path from open sea.
2. **Only 31 of 75 hulls can be built today** (W12's question 9). Seven countries have no ship, so "No navy came" and a wanted row is what attacking them gives.
3. **`attack_enabled` is still to be lit by the owner,** after W14. Nothing here lights anything.

## Not verified

- Anything on prod beyond `before.sql`. Real-Postgres behaviour is CI's `disposable-chain`; local runs are PGlite.
- The press cost on prod. The projection scales one ratio.
- `harbour_nearest` and the call on prod's full harbours and 1,253 courses; the probe world's legs are short.
- Two real sessions: PGlite has one connection, so `SKIP LOCKED` is reasoned, not raced.
- A real ten-minute battle by the real clock, or the job firing: the proof hands every call its instant.
- The Attack section and the "Navy arrives" row in a browser: type-checked, built, rendered dark in a spec, not opened lit. No picture exists.
- Whether an escort one leg behind reads as an escort on the map.
- A storm: the proof slows her voyage to stand for one, it does not roll one.

## Rows for the coordinator (not written here)

**docs/OWNER_REQUESTS.md rows 285, 286:** `PART BUILT - W13 the navy comes, migration 0333, dark, PR open, not deployed: a battle calls its country's ships, real voyages, join by the clock, escort, players may attack navy ships. OPEN: W14 (0334) writes wanted; owner question 9; lighting is the owner's.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **THE NAVY COMES (W13, owner rows 285, 286) - migration 0333, DARK, PR open, NOT deployed, follows 0332:** call at battle start, reinforcement voyages, join rule, escort, attack a navy ship. Read before lighting: a ship at sea finishes her leg, so most ships are late. 0334 applies on top unchanged. Dev-log docs/dev-log/2026-11-06-the-navy-comes.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/navy-comes/before.sql`. Every `times` 1, `keys` 0, `how_column` 0, `fn_call` null, both switches false, `ships` 0, `battles_attack` 0, head 0332.
- After deploy: `scripts/ops/harness/navy-comes/after.sql`. Both false, `keys` 4, `how_other` 0, `ships` 0, `called` 0, head 0333.
- `bash scripts/ops/health.sh`. No after-check window is owed: nothing changes while dark.

## Rollback

Forward, owner only: `navy_enabled` false: no call, no escort, and a ship already called sails on and is freed at the close. `navy_escorts` 0: no escort.
