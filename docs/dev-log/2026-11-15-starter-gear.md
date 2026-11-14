# 2026-11-15 — Starter gear at every harbour (migration 0425, owner row 345)

The owner, verbatim: *"and in port, there should be a beginner's gear for ships."*

## Where gear came from before this

- A piece of gear (a "fitting") is MADE at a city's workshop from trade goods in the ship's hold (`cmd.do_make`, 0068; the Craft
  face, `src/live/PortWorkstation.tsx`). It then lies in the company's store at that city (`public.player_items`).
- It is FITTED with the FIT command (`cmd.do_fit` → `public.mount_fitting`, 0126/0132), in any harbour where the fleet is docked:
  no building is needed. It goes in a RACK (High / Mid / Low / Refit / Flourish) and costs Deck and Hands (0132).
- It wears (0158, `gear_wear_bite` on): by the mile, by a fight or by a storm day, by its kind (`public.item_use`), and is repaired
  with the hull. It shows on the ship's sheet.
- No door turns a piece into coin. A piece is fitted, used in a hull's recipe, or spent on a captain's promotion.

So a new company's first ship (a barca: one High place, two Mid, Deck 12, Hands 16) sailed bare until it hauled goods to a workshop.

## What 0425 adds

| piece | rack | effects (as the database holds them) | Deck / Hands | price |
|---|---|---|---|---|
| Starter Guns | High | +30 attack, +8 reach; −30 tons, −3 handling | 3 / 4 | 800 |
| Starter Sails | Mid | +0.90 knots; −4 handling | 2 / 2 | 300 |
| Starter Planking | Low | +5 armour, +80 hull; −18 tons, −0.69 knots | 2 / 0 | 150 |

- **One rule** (`scripts/build-gear.mjs` `STARTER`, `starterDelta`): each is its kind's grade-1 piece (Broadside Guns, Suit of
  Sails, Deal Planking) at HALF: every effect halved (what it gives and what it costs alike), Deck and Hands halved and rounded up.
  The tons and knots are ×3 in the database as every item's (`hold_scale`, `speed_scale`). The planking gets no wave resistance
  (wave is `WAVE_BY_BASE`'s by grade, and a starter piece is no grade of the ladder).
- **Prices** are about 40 % of what the grade-1 piece's goods are worth (`public.item_recipe_value`: guns 1,915, sails 747,
  planking 395). The migration asserts every price is under half of it and every effect at most 55 % of the grade-1's, same sign.
  A barca's set (guns + sails) is 1,100 of a new company's 40,000.
- **Sold at every harbour (254)**, decided by default: fitting needs no building, so neither does the starter gear. It is the new
  **Gear** face (one word: Gear / 장비) on the desk's City and a third row of the City page's Port.
- **Bought and fitted in one press** (`cmd.buy_starter(fleet, ship, item)` → `public.buy_starter_for`): her fleet docked at a
  harbour; the piece goes straight onto the chosen ship through `public.mount_fitting` (rack, place, Deck, Hands as any piece);
  then she pays THAT city (`public.pay_city`, ledger kind GEAR, a 'moved' word: closed economy, nothing minted, nothing burned).
  A refusal (no place, rack full, Deck, Hands, short purse, at sea, a merchant) moves nothing.
- **One of each a ship** (a hunk in `public.mount_fitting`, E_STARTER_ONE): a cheap piece cannot be stacked, not by buying and not
  by FIT from the store. Every other item mounts as before (asserted: two Suits of Sails on one hull).
- **Made nowhere** (`public.item_unmade`): MAKE refuses it, and the workshop does not list it (a hunk in `world.workstation`). Its
  recipe (half the grade-1's goods) is kept as a record and is what its repair is priced from.
- **Wears like its kind** (`public.item_use`): the guns by a fight (and spend shot and powder, as the grade-1), the sails by the
  mile, the planking by a storm day. Proved: 2,000 miles wear the sails 2.00, two storm days the planking 6.00.
- **Resale cannot profit**: there is no item-to-coin door; UNFIT stores the piece for nothing; it is in no hull recipe and is no
  promotion item; a merchant cannot buy one and no merchant loadout names one (NPCs unaffected).

## Decided by default (the owner may reverse)

1. Three pieces, one a rack a new hull has a place in. Refit (permanent hull work) and Flourish (the figurehead, moves no stat):
   none.
2. Every harbour sells them, not only those with a shipyard (117 of 254): fitting needs no building.
3. Half of the grade-1 piece, at about 40 % of its goods' worth; one of each a ship.
4. **A new company does NOT start with a set fitted.** Founding (`cmd.found_house` / `public.new_house`) is not cut: in the closed
   economy a gifted piece is made from nothing, and the founding body is the busiest door. The set is one press in her first
   harbour for 1,100 of her 40,000. To give one at founding is a small later step if the owner wants it.
5. Not limited per company: the one-a-hull rule is the limit, since a piece cannot be sold.

## Checks

- Local chain (prefix cache at 0421 + 0425): `0425 self-assert ok` in ~250 ms (budget 15 s); the face's read 6 ms. The world
  guard equals the data files (228 items, 228 item uses, 14 items made nowhere, the starter prices). Proof 125: 6/6 markers.
- Rollback draft (`scripts/ops/harness/starter-gear/rollback-0425.sql`) run on the local world: three hunks reversed, the door, the
  read and the core dropped.
- Production, read-only (2026-11-15, gate green: beat 89 ms mean, 903 MB, 0 io waits): `before.sql` — head 0421, no starter object,
  each hunk anchor occurs once, the three grade-1 pieces present, 254 harbours, purses lit, wear biting, economy closed, scales 3.
- Screenshots at 320, 390 and 1280, EN and KO (the City page's Gear page, a piece's tray, after a buy; the desk's Gear face):
  `C:\Users\gkwng\dev\starter-gear-shots\`.

## Load

Nothing in any beat or job. A buy is one press: one fitted unit, one event, one ledger row, one city flow. The face's read is three
catalogue rows and her fleet's ships by key. New table: `public.starter_gear`, three rows, bounded by construction.
