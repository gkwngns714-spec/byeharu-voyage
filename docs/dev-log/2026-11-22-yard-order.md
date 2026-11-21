# 2026-11-22 · The yard takes an order (migration 0465, proof 168) — DARK behind `yard_order_enabled`

Slice C of `docs/design/content-plan-2026-11.md` (5.3 item 3, 5.4 row C; the problem in 3.4 and 3.5: the second ship is an 85-minute
errand and coin buys nothing). The owner, 2026-11-22: "make this game a proper game", which settles the plan's open decision (5.6:
yes, at half again the price and with a real wait; the materials stay cheaper and instant).

## What the switch hides (while `yard_order_enabled` is false)

- **Nothing a player sees moves.** `world.building_yard` serves exactly what it served (the 0465 self-assert reads a new Lisbon
  company's yard BEFORE the hunk and after it, dark, and they are the same text); the new key `order` is served only while lit.
- `world.hull_quote` answers `{on: false}`; `cmd.order_hull` refuses `E_NOT_IN_USE` before it writes. The client offers Order only
  when the yard read carries `order`, so dark the Yard shows no Order button (tests/yard.order.spec.ts, "dark").
- Lighting it is the owner's: `update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled'`. False again is
  the rollback; an order already paid keeps its row and still launches (`cmd.launch_hull` is not behind the switch: proof 168
  ORDER_DARK_LAUNCH).

## What landed

| Part | Server (0465) | Client | Words (EN / KO) | Proof |
|---|---|---|---|---|
| The switch and knobs | `yard_order_enabled` false; `yard_order_fee_pct` 50; `yard_order_minutes_per_hour` 1.25 | | | self-assert, ORDER_DARK |
| The table | `public.hull_orders` (one open a company a yard: partial unique index; RLS on, no client grant) | | | self-assert |
| The price | `public.hull_order_price(player, port, class)`: `yard_labour` + every good of the hull and her parts at the nearest seller's ask now (`world.yard_sources`, the sheet's own sellers and prices, counted whole) + the fee; minutes = `build_hours` x 1.25 | `world.hull_quote` read when a sheet opens (lit only) | Wait / 대기 | ORDER_PRICE |
| Order | `cmd.order_hull(port, class)` → `public.hull_order_for`: do_build's gates (each the same function), one open order a yard, one famous ship to a house counting orders, the purse; paid whole to the city (`pay_city`, kind BUILD), event HULL_ORDERED | a second press under the sheet's one button, "Order · price"; the press closes the sheet | Order / 주문, Order · {price} / 주문 · {price}, Ordering… / 주문하는 중… | ORDER_PAID, ORDER_GATES |
| The countdown | `world.building_yard` gains `order` {on, fee_pct, open, elsewhere} (`public.hull_order_card`) | the top of the yard: "On order · Barca", Ready in 12m, then Ready; your orders at other yards under it | On order / 주문함, Ready in {t} / {t} 후 완성, Ready / 완성 | ORDER_PAID, ORDER_ELSEWHERE |
| Launch | `cmd.launch_hull(fleet, name)` → `public.hull_launch_for`: a fleet of yours docked at that yard, the order ready, named as do_build names; `commission_ship` (empty, uncrewed; the ship cap's trigger), Reputation and Shipbuilding as do_build; event HULL_LAUNCHED | a name and Launch on the order once ready; "{name} launched" | Launch / 진수, Launching… / 진수하는 중…, {name} launched / {name} 진수 | ORDER_LAUNCH |
| Retention | the company's next order deletes its launched orders older than 7 days | | | ORDER_RETENTION |

The local backend runs the same SQL (the catalogue rows `worldHullQuote`, `cmdOrderHull`, `cmdLaunchHull`; `src/lib/rpc/localBackend.ts`
builds its call from the catalogue, so nothing there changed). `public.client_rpc_entry_points` registers the three; the cores and
readings are server only, `service_role` included (the platform grants it execute on a new public function by default).

## Measured (the chain's world)

- **A Barca at Lisbon: labour 15,000 + materials 2,614 + fee 8,807 = 26,421, ready in 30 minutes** (the self-assert and proof 168). The
  plan's "about 26,000" holds. The materials route for the same hull costs 17,614 when everything is bought at the nearest sellers, so
  the order is dearer by exactly the fee, and slower by 30 minutes against an instant build once the goods are stored.
- The wait runs from 30 minutes (`build_hours` 24) to 7.5 hours (360, the biggest hulls).

## Decided by default (the owner may reverse any)

1. **The wait is `build_hours` x 1.25 minutes.** The plan said "a barca in about half an hour, a caravel in two hours, a nau in eight, a
   great ship in a day". `ship_classes.build_hours` (24 to 360, by size) is the column the plan names as "present; read by no rule", so it
   is the one reading; at 1.25 a Barca is 30 minutes and the biggest hull 7.5 hours (not a day). The knob `yard_order_minutes_per_hour`
   turns it.
2. **Materials priced whole** (every unit at the nearest seller's ask now), not net of what the company already stores at the yard:
   the yard buys its own; what is in storage stays the company's.
3. **No Cancel.** The plan names two doors; an order is paid and built.
4. **Launch needs a fleet of yours docked at that yard** (as do_build: "she joins the fleet lying here"), and is not behind the switch.
5. **No fleet is needed to order**: a company may order at any yard whose gates it passes (the sheet is read from a harbour where a
   fleet of yours lies).
6. **The price goes to the city** (`pay_city`, kind BUILD), as a hull's labour does; with the city purses dark (the local world) only
   the company's ledger moves.

## Not done

- **"The planned trip stops sailing past its materials" (5.3, 3.4).** Not small: either Plan trip must carry the BUY lines per stop
  (the route builder takes stops only, `features/map/routeSeed.ts`, and a standing BUY per leg is the route's own order shape) or the
  sail must wait at a stop where a material is short (a server rule in the voyage). Left for its own slice.

## Checks

- `tsc -b`, `eslint`, `vite build` (world image with 0465): green.
- `node scripts/db/proof.mjs 168_`: 8/8 PASS.
- `tests/yard.order.spec.ts` against `vite preview`: dark, lit (Order → countdown → Ready → Launch), Korean.
