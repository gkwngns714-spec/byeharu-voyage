# 2026-10-30 — a ship that runs dry is forced home (owner row 223)

**Slice:** `osn-stranded` — migration **20260818000279_a_dry_ship_is_forced_home.sql** + the client's one
feed line. Design: `docs/STRANDED_AT_SEA.md` (authoritative). Owner row 223, 2026-10-30:

> *"then the ships need to be fixed and be set on a right course. i mean if there is no provision left at
> sea - long time voyage, you will be forced back to the closest city, losing all of your cargo, damaged
> ship, but at that city you will receive your insurance if you've paid for it, and if it is too much to
> handle, the city should give donations."*

**The root.** Since 0007, `voyage.settle` drinks each settled voyage-day's `water_t` / `food_t` and floors
them at 0 with `greatest(0, …)` — and then nothing. A fleet at 0 stores sails on at SHORT_RATIONS' ×1.5
wages until she arrives. 0213 reserved this slice in so many words: *"a later loss writer calls
public.insurance_claim"*. 0279 is that writer: a ran-dry branch in the settle, and the chain the owner
named around it.

## What was built (one migration + the client; nothing else moves)

- **The trigger — one hunk in `voyage.settle`.** After the day's consumption and wages, before the hazard
  roll: `voyage.endurance_days(fleet) = 0` (THE endurance figure, the same one SHORT_RATIONS reads the day
  before) with a crewed hull aboard and `d < voyage.total_days`. The voyage is cut that day: the day's
  wage is still owed, the day's hazard is not rolled, the day's `voyage_events` row is `FORCED_HOME`, and
  settle returns.
- **`voyage.forced_home(voyage, day, fleet)` — the chain, one function, server-only:**
  1. the whole hold leaves through **`public.fleet_unload`** (the one unload), named `cargo_lost` in the
     day's payload exactly as 0213's `raid_takes` names it;
  2. **`public.insurance_claim(voyage, day, lost, 'FORCED_HOME')`** pays it at the policy's basis less the
     keep pct, from the insuring city's surplus — only when the voyage was insured;
  3. **hull damage**: a storm's shape (`0.08 + 0.17 × voyage.rng(voyage, day, 'forced_home')` of each
     hull's own rolled max, through `public.armour_turns`), and **never to 0 by itself** — a hull loses at
     most `durability − 1`, and a hull already at 0 is left alone for 0152's tow;
  4. **brought in**: `DOCKED` at the closest city (`UNABLE_TO_SAIL` when her flagship was already a wreck),
     lat/lon cleared, her queue released like a tow's (`cmd.clear_for`);
  5. **the city's donation**: the yard's quote (`public.fleet_repair_due` → the one price) less her purse
     (the insurance has already landed in it), given through **`public.city_pays` kind `DONATION`** —
     capped by `public.city_surplus` while the purses are lit, paid in full while they are dark (0213's
     own rule);
  6. one **`FORCED_HOME`** event through `public.emit_event`, carrying the whole chain;
  7. `voyages.status = 'ABORTED'` (the existing "ended early" status).
- **`voyage.strand_port(voyage, day)` — THE closest city**, server-only, stable. Measured from the leg's
  two roadsteads — its origin and its destination — against the reach table `voyage.reach_from` (the
  figure the tow reads): `least(miles spent + reach(origin → H), miles left + reach(H → destination))`,
  the leg's own ends at 0, open HARBOURS only.
- **`public.fleet_repair_cost(fleet, points, gear)` — THE yard's price**, lifted out of `cmd.do_repair`
  (one hunk re-cuts that body to call it) so the captain's repair and the city's donation weigh one line,
  never two.
- **A new voyage event kind `FORCED_HOME`** (ordinal 16, never rolled, not in the sea mix) with its prose.
- **A repair fix carried in the same function** (see the defect section below): 0276 left a set-returning
  call in `cmd.do_repair`'s UPDATE target list, so every REPAIR has raised since then. One more hunk
  re-spells it as the scalar subselect 0276's own sibling readings use.
- **The client:** the feed's one sentence (`src/features/ledger/headline.ts`, filed under the Voyage face
  in `LedgerScreen.tsx`), EN + KO through `src/lib/i18n/dict/history.ts`. The money is on its own lines:
  the insurance payout is 0213's `INSURANCE_PAID` (cause `FORCED_HOME`) and the city's gift is the
  `DONATION` movement the ledger already names.

## Decided by default (the owner may reverse each)

- **"Closest city" is measured from the leg's two roadsteads** — the design's own rule — as miles spent +
  reach from the origin against miles left + reach from the destination. Her own ends cost 0.
- **The closest OPEN HARBOUR, not the closest shipyard.** The owner said "closest city"; 0152's yard filter
  belongs to wrecks. A city with no yard quotes no repair, so it donates nothing; she lies DOCKED and can
  sail on for a yard.
- **Damage is a share, never to 0 by itself** — the owner said "damaged ship", not "wrecked". A wreck still
  comes only from the existing paths, and 0152's tow takes her.
- **The trigger is `endurance_days = 0` after the day's consumption, with a crewed hull aboard.** A fleet
  with nobody aboard can never run dry (`endurance_days` reads an uncrewed hull as 9999 days).
- **A dry FINAL day is an arrival, not a stranding** (`d < total_days`): `day_ends_at` clamps the last day
  at the ETA, so a ship that drinks her last cask entering harbour docks there.
- **The dry day is cut BEFORE the hazard roll; the day's wage is still owed** (a dry day is a day at sea).
- **The voyage ends `ABORTED`**, the existing early-end status DIVERT and the merchant loops already use.
  The reason is the event kind, not a fourth status value.
- **The donation pays the yard's QUOTE less the purse; it does not press REPAIR for her.** A player presses
  REPAIR (or keeps the coin and sails damaged); a merchant's loop, chosen afresh from where she lies
  (0152's off_route branch), carries her to a stop with a yard where its REPAIR line already fires. She is
  DOCKED and paid, never parked.
- **A passage with no roadstead at either end gets no forced home** (nothing to measure from): the day
  settles as it always did.
- **Her queue is released** like a tow's: orders written for the old voyage's destination must not run at
  the port she was blown into.
- **A city's gift is booked as a negative `DONATION` treasury flow**, so it also reads as a withdrawal from
  that city's invested base (`public.tick_city`'s own inflow sum) — the money left the city, and the book
  says so.

## The proof (local, 2026-10-30)

- **The chain applies.** `node scripts/db/apply-chain.mjs`: 267/267 migrations, **267 self-assert receipts**
  (273 receipt lines across the chain), the world-guard equal to `data/*.json`. The prefix cache restored
  266 (the 0278 chain) in 2.8 s and applied 0279 in ~6 s; the snapshot after 267 files round-trip-verified.
- **`node scripts/db/proof.mjs standing` — 5/5 PASS markers.** `node scripts/db/proof.mjs merchant` — **6/6**
  (55.8 s). Nothing in either proof moved.
- **`npx tsc -b`, `npx eslint` on the three client files, `npx vite build`** — all green (build 2.46 s).
- **The migration's own self-assert (8 probes + the receipt), every probe on its own company, every block
  rolled back whole.** The measured answers:

  - **P1 — the whole chain.** A probe house at Lisbon, a barca laden with 40 almonds and 10 anchovies
    (worth 2,000) sailing LIS → FNC, insured. Stores zeroed, the day settled at day 1's boundary: the day's
    `voyage_events` row is **FORCED_HOME**; the closest city was **Funchal** (this leg is past half way at
    day 1 — the probe computes the same answer independently from `public.sea_reaches`); `cargo_lost` is
    `{almonds 40, anchovies 10}`; the hulls went **437.60 → 339.25** (98.35 lost, every hull still afloat);
    the policy paid **1,800 of the 2,000** (10 % kept), on the ledger; the fleet is **DOCKED at Funchal**,
    lat/lon null; the voyage is **ABORTED** on day 1; **one** FORCED_HOME event; a second settle returns 0
    and writes none. The **pre-image body**, run on its own company with the same setup, has no branch: she
    is still **SAILING with her 40 almonds**.
  - **P2 — the control.** A sound larder: day 1 is **CLEAR**, the hold intact (40), no event.
  - **P3 — no policy, no payout.** Uninsured: `insurance` is null, 0 policies, 0 on the ledger, the hold
    still lost, the whole yard's quote left to her.
  - **P4 — the city donates the shortfall.** Purse emptied after she sailed; a dear yard (the rate knob
    raised inside the block only): quote **74,888,000**, purse **1,800**, short **74,886,200**, and the city
    (the probe's computed home, funded to 10,000,000 with no reserve) **gives 10,000,000** — capped by its
    surplus; ledger **+10,000,000**, treasury **−10,000,000**, purse **+10,001,800** (the insurance plus the
    gift). The hulls stay at 1: the city pays for a repair, it does not press it.
  - **P5 — never to 0 by itself.** Every hull at 1 loses **0.00** and she is DOCKED; a flagship already at 0
    is left at 0 and the fleet is **UNABLE_TO_SAIL** — 0152's tow takes her.
  - **P6 — the merchant.** An NPC house with a laden voyage and no INSURED flag: **1 policy** written by
    `insure_voyage` (0213), **1,800 paid**, DOCKED, ABORTED, one event — the same chain, not parked.
  - **P7 — no roadstead.** A passage with both ends null: `strand_port` answers null, the day is
    SHORT_RATIONS, the hold stays at 40, no event.
  - **P8 — the yard's price is one line.** `public.fleet_repair_cost` = the old formula to the ducat
    (74 = 74 on a 200-point hull) and `cmd.do_repair` quotes exactly it.

## A LIVE DEFECT FOUND AND FIXED IN THIS SLICE: every REPAIR has raised since 0276

P8 calls `cmd.do_repair` — and on the chain as it stood, it raised **`set-returning functions are not allowed
in UPDATE`**. The root: 0276's hunk wrote

```sql
update public.ships s set durability = greatest(s.durability, (public.ship_base(s.id)).durability * v_to / 100)
```

into `cmd.do_repair`'s body. `public.ship_base` returns a TABLE, and PostgreSQL refuses a set-returning call in
an UPDATE's target list **at parse time** — the same reason 0276's own sibling readings (`public.fleet_repair_due`)
spell it as a scalar subselect. Since 0276 was applied, every REPAIR — a player's, a merchant's after a tow —
has raised. Nothing in 0276's gate called `cmd.do_repair`, so it shipped.

0279 fixes it in the same function it already re-cuts (hunk 2): the one expression becomes
`(select b.durability from public.ship_base(s.id) b)`. The probe proves the repair now runs and charges the
same price (`points 200.0`, `cost 74`, `sim_hours 20.0`). **The owner should be told: repair has been broken
live since 0276, and this PR repairs it.** The PROD CHECKS below read the live body to confirm it is the
broken one before the push.


## PROD CHECKS (before the push; read-only, in the PR body)

Read-only (`begin transaction read only`); every function called is `s`/`i` volatility.

```sql
-- the two live bodies ARE the ones the hunks were cut against (each anchor exactly once)
select (length(d) - length(replace(d, 'v_taken   jsonb;', ''))) / length('v_taken   jsonb;') as settle_decl,
       (length(d) - length(replace(d, 'select * into h from voyage.hazard_roll(v.id, d);', '')))
         / length('select * into h from voyage.hazard_roll(v.id, d);') as settle_hazard
  from (select pg_get_functiondef('voyage.settle(uuid,timestamptz)'::regprocedure) d) x;
select (length(d) - length(replace(d, 'v_cost := v_cost + coalesce((v_gear->>''cost'')::bigint, 0);', '')))
         / length('v_cost := v_cost + coalesce((v_gear->>''cost'')::bigint, 0);') as repair_price,
       -- 0276's live bug, expect exactly 1: the set-returning form 0279 replaces (if this reads 0,
       -- the live body is not the one this file was cut against, and the defect is already fixed)
       (length(d) - length(replace(d, '(public.ship_base(s.id)).durability * v_to / 100', '')))
         / length('(public.ship_base(s.id)).durability * v_to / 100') as repair_srf
  from (select pg_get_functiondef('cmd.do_repair(uuid,jsonb)'::regprocedure) d) x;
-- nothing of 0279 exists yet
select (select count(*) from public.voyage_event_kinds where code = 'FORCED_HOME') as kind_rows,
       (select max(ordinal) from public.voyage_event_kinds) as max_ordinal,
       (select count(*) from public.events where kind = 'FORCED_HOME') as events_rows,
       to_regprocedure('voyage.strand_port(uuid,integer)') is null as no_strand_port,
       to_regprocedure('public.fleet_repair_cost(uuid,numeric,jsonb)') is null as no_repair_cost;
-- the blast radius on the day the branch goes live: fleets at sea that are ALREADY dry, whether the
-- voyage is insured, and what their holds are worth (a measured list, not a guess)
select count(*) as dry_at_sea,
       count(*) filter (where i.voyage_id is not null) as dry_insured,
       coalesce(sum(public.fleet_stock_at_cost(v.fleet_id)), 0) as dry_hold_cost
  from public.voyages v
  left join public.insured_voyages i on i.voyage_id = v.id
 where v.status = 'SAILING' and voyage.endurance_days(v.fleet_id) = 0;
-- the stated edge: passages with no roadstead at either end (they get no forced home)
select count(*) as no_roadstead from public.voyages
 where status = 'SAILING' and origin_port_id is null and dest_port_id is null;
```

## After-check (30 minutes, from the deploy)

1. **The first forced homes.** `select count(*), min(created_at), max(created_at) from public.events where
   kind = 'FORCED_HOME' and created_at > now() - interval '30 minutes'` — and each payload read whole:
   `port` names an open harbour; `cargo_lost` is the hold; `insurance` is null or `{owed, paid, short}`;
   `repair` is null or `{points, cost, purse, short, donated}` with `donated ≤ short`.
2. **No hull was sunk by the rule.** For every forced-home fleet, `min(durability) ≥ 1` unless it was
   already 0 before (the fleet is then `UNABLE_TO_SAIL` and 0152's tow takes it). Read:
   `select f.name, f.status, f.port_id, min(s.durability) from public.fleets f join public.ships s on
   s.fleet_id = f.id where f.id in (…) group by 1,2,3`.
3. **The dry count falls.** The pre-deploy `dry_at_sea` reading above should shrink to zero within a couple
   of settle ticks; none should stay SAILING at 0 stores with crew.
4. **Money adds up.** Each forced home with `insurance.paid > 0` has a matching `INSURANCE_PAID` ledger row
   (cause `FORCED_HOME`); each with `repair.donated > 0` has a `DONATION` ledger row of that amount and a
   `treasury_flows` row of `−donated` at that harbour; no harbour's balance falls under its reserve.
5. **No settlement errors.** The tick receipts (settle / advance) show no error rows in the window; the
   hourly merchant upkeep keeps counting routes (a merchant forced home is DOCKED and re-planned, not
   parked — `off_route` notes appear, then her route resumes).
6. **The feed reads.** The History tab shows the FORCED_HOME line with the city and (where paid) the
   gift; EN and KO both.

**Forward rollback** (if the rule misbehaves): reverse the two hunks (old and new swapped) on
`voyage.settle` and `cmd.do_repair`; drop `voyage.strand_port`, `voyage.forced_home`,
`public.fleet_repair_cost`; delete the `FORCED_HOME` kind row. Nothing else references them; events
already written keep their kind string and read as an unfiled row on the ledger (the honest fallback).
