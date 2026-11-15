# 0430: a hundred cargo ships, shared by size; an empty cargo ship sails home (owner row 348)

## The owner, 2026-11-15

- "make it so that pirates are active, we don't need 372 cargo ships... make it 150, reduce them but remember, each countries including pirates
  should have cargo ships that are proportional to their size."
- "i see cargoships without money, just roaming around in ocean, wtf is this/"
- "fix the issue. cargo ships are used for cities to deliver gold to poorer cities. reduce the cargo ship number to 100 appropriately."
  (The 100 overrides the 150.)

## What prod looked like (the lead's reads, 2026-11-15)

- 372 cargo ships: 120 at sea, ~236 idle at home with nothing to carry, 11 laid up over their country's number.
- Later the same morning: 136 sailing, 57 with funds, **79 empty, 77 of them not heading home**: each sailing between her own country's cities
  after a DELIVERED (LIS RIO->CAP after SLV; LIS NAM->MCH after DIU; BSR ACC->ANG after KAN; MLE THA->HAG after MUS; SAK TSU->COQ).

## Root cause of the roaming

`public.cargo_ship_step` (0309, 0324), away from home: after a city's delivery she always takes the next leg of her circuit,
`v_leg := c.leg + 1`, whether or not anything is left aboard. A circuit visits every city of her realm and only its last leg comes home, so a ship
emptied at her first city sails the whole rest of the circuit with nothing aboard. With 100,000 loads (0426) most ships empty at their first or
second city, so most of the circuit was sailed empty.

## What 0430 does

1. **The share** (`public.convoy_ships_wanted`, re-cut whole). Size is a country's **harbours**: the harbours under its flag
   (`port_allegiance`, kind HARBOUR). Decided by default: it is the count the cash of a country is already summed over
   (`public.realm_purse`), it is what "size" means on the map, and unlike the purse (which swings by millions an hour and was the old curve's
   input) it moves only when a harbour changes flag. Every great power with a harbour, the pirates included, keeps 1; the rest of
   `cargo_fleet_total` (100) is shared by harbours, whole ships by the largest remainder, so the shares sum to 100 exactly.
2. **The number is the share** (`public.convoy_fleet_settle`): written exactly each hour; no dead band (a band would let the total drift); a
   power with no harbour loses its row and `public.convoy_ships_of` answers 0.
3. **The surplus retires safely**, by 0326's path (`public.cargo_ships_retire`): only a ship over her share that lies DOCKED at her home with no
   lap and nothing aboard; highest ord first, `convoy_retire_per_run` 3 -> 10 a minute. A ship at sea or with funds aboard takes no new load and
   lays up when home and empty. Laying up writes `laid_up_at` only: no gold, goods or ledger row moves; the hull stays hers (hulls are free).
4. **An empty ship sails home** (`public.cargo_ship_step`, 2 hunks): away on a lap with nothing left aboard after the city's delivery, she sails
   one leg straight home (`public.cargo_circuit_plan`, the course a rebase leg takes) and closes her lap there (HOME). With funds aboard she goes
   on to the next city as before. Her one job stays carrying gold from the richer cities to the poorer ones (0307's loads, unchanged).
5. Knobs: + `cargo_fleet_total` 100; retired `convoy_ships_min`, `convoy_ships_max`, `convoy_ships_span`, `convoy_ships_band` (no body reads
   them after the file; the self-assert and proof 131 scan the catalog).

## The shares (local world = the chain's flags; prod's are read by `scripts/ops/harness/cargo-150/before.sql`)

| country | harbours | share |
|---|---|---|
| Castile-Spain (ESP) | 40 | 26 |
| Portugal (PRT) | 25 | 17 |
| Ottoman Empire (OTT) | 20 | 14 |
| Japan (JPN) | 11 | 8 |
| The Brethren (PIR, the pirates) | 9 | 7 |
| France (FRA) | 8 | 6 |
| England (ENG) | 8 | 6 |
| Joseon (JOS) | 7 | 5 |
| Ming China (MNG) | 5 | 4 |
| Mughal India (MUG) | 5 | 4 |
| The Netherlands (NLD) | 4 | 3 |
| **total** | 142 | **100** |

## The pirates

Their share is written (`public.convoy_ships_of(<the Brethren>)`), but the crown cargo job makes no ship for them (0338: no circuit, no
commission). So until the pirates' own gold ships exist (0429: five from Port Royal), the world sails 100 less the pirates' share.
**Hook for 0429 or its follow-up:** the pirates' gold ships count inside their share; their number reads `public.convoy_ships_of(<pirates>)`, not a
flat 5 (the share is 7 on the chain's flags).

## Rows

- No ship is deleted: a ship's house and fleet are named by append-only rows (`convoy_cargo`, `events`), so 0326's law stands (laid up, never
  deleted). The database does not shrink by rows; it stops growing: no cargo ship is made again until a share rises above the laid-up ords.
- Lay-ups: 1 row each, at most 10 a minute while the surplus comes home, then none.
- The homeward legs replace the rest of each circuit: fewer legs (voyages, stores, arrivals) a minute than today. With ~90 ships in service
  instead of ~360, the job's idle steps fall by about three quarters.

## Proofs

- Proof 131 (new): C100_SHARE, C100_SETTLE, C100_KNOBS, C100_RETIRE, C100_HOMEWARD: all green locally.
- Proof 35: SIZE_CURVE and SIZE_BAND left with the curve (proof 131 proves the number); the other seven markers green.
- Proof 45: the pirates now hold a share but still no circuit or ship. Proofs 19, 32, 36: an emptied ship's lap may now end HOMEWARD (36's
  ARMED_LAP: every stop in order until she is empty, then home). Proofs 18, 20, 30, 37, 50, 51, 73, 116, 127 green on the file.

## Prod checks

`scripts/ops/harness/cargo-150/before.sql` before the deploy (the shares on prod's flags, what retires now and later, the roaming count, and that the
four live bodies are the text 0430 was cut from), and the same file after (`applied` true, `bodies_post` true; `roaming` falls to ~0 within a
lap; `in_service` falls toward 100 less the pirates' share at up to 10 a minute). Forward rollback draft: `rollback-0430.sql`.
