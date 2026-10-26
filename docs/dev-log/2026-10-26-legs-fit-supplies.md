# 2026-10-26 — 0231: her legs fit her supplies (`osn-legs-fit-supplies`, owner row 208)

**The owner (row 208).** *"Tsushima — longest leg 7.1 days, supplies last 4.3 days ... then the trip should
automatically be made within 4 days right? why it doesnt do that?"*

**Why (prod, read-only, head 0226).** `voyage.reach_passage` searched the shortest miles with one leg cap, her
navigation (`passage_reach_nm`). It never read her supplies. `world.good_board` judged them only afterwards
(`sailable = supply_need(fleet, longest leg).fits`). The owner's fleet Gaivota (`51b8f474…`, Havana, hold 178.8 of 180
t) was offered Tsushima through 15 stops with a 1,677-mile leg (7.07 days), marked unsailable, and no other route was
tried. Today, 219 of that board's sell rows are like this: a route is shown, and it is unsailable.

## 1. What changed (migration `20260818000231_her_legs_fit_her_supplies.sql`)

| Part | What |
|---|---|
| NEW `public.supply_reach(fleet)` → `(carry_days, cap_nm)` | Each hull is topped up as far as the room beside her cargo allows (`public.stores_topup`, the one top-up, asked for more days than any room holds). `carry_days` is the shortest hull's days × `voyage.endurance_mult`. `cap_nm` is the miles those days cover, at `voyage.stores_need_days`'s days per mile, so there is no second copy of `endurance_margin`. Asserted: `supply_need(cap).fits` is true and a leg just past the cap does not fit. Server-only. |
| NEW `voyage.leg_refusal(fleet, dest, nm, course)` | **The one leg judge** (ROUTE_BUILDER §3): `passage_gate`, then `E_ENDURANCE` when `supply_need(fleet, nm).fits` is false. Its figures are `{nm, leg_days, need_days, carry_days, cap_nm}`. Server-only. The route builder's B1 reuses it and has no hunks of its own for it. |
| `voyage.reach_passage(player, fleet, from, p_cap_nm numeric DEFAULT NULL)` | The old 3-argument version is dropped. The ACL (`{postgres=X/postgres}`), volatility, definer and config (`plan_cache_mode=force_custom_plan`) are carried over and asserted. A leg is open within `least(navigation, p_cap_nm)`. A null cap gives the old search, row for row (asserted against the pre-image). The new column `shut_leg_nm`: for a harbour that no capped route reaches but one within her navigation would, it is the least "longest leg" such a route needs (a minimax pass over the same matrix). That pass runs only when the cap is below her navigation and has left a harbour unreached. 5 hunks. |
| `world.good_board` | Reads `supply_reach` once and passes the cap to both searches (from where she sails, and from the buy city). Each buy and sell row gains `shut`: `voyage.leg_refusal`'s `E_ENDURANCE` for that least longest leg, called once per distinct length. The board's `supplies` gains `carry_days`. 10 hunks. Every other key keeps its old meaning, now read from the capped search. |

**Client.** `reachBoard` reads `supplies.carry_days` (falling back to `days`). `desk.suppliesOnly` now says
"{leg}, can carry {days}" (KO "{leg}, 보급 최대 {days}"). New `desk.holdTooFull`: "Hold too full: {carry} of
supplies, crossing needs {need}" (KO "화물 과다: 보급 {carry}, 횡단엔 {need} 필요"). `reachWords` prints it when the
row's `shut.code` is `E_ENDURANCE`. `SellList` shows "Cargo full" instead of "Too far" for those rows. The types are
`BoardShut` and `supplies.carry_days`. `tests/planWords.spec.ts` has +2 cases, and the "supplies last" case now reads
"can carry".

**Decided by default.**
- The cap uses the cargo she holds now (the hold that `fits` already judges). A buy row's purchase is not
  subtracted. The sell row's `supplies.units_fit` (0225) already says how much she may load and still sail that
  row's longest leg, so no second, cargo-aware search runs.
- `leg_refusal` takes the argument order that ROUTE_BUILDER names, `(fleet, dest, nm, course)`, not `(fleet, from,
  to, nm)`. Nothing about the origin is asked.
- The stores are compared with the stores. A leg needs `endurance_margin` (1.15) times its days at sea in supplies,
  so a 4.3-day hold carries legs of 3.7 days at sea. The shut row prints the supplies the crossing needs (7.8 days for
  Tsushima from Havana), not its 6.8 days at sea.

## 2. Measured (local PGlite, merged with main at 0227: 218 of 219 files restored from the prefix cache, 0231 applied, self-assert 18.4 s)

```
0231 probe (a): empty hold: reach_passage(null cap) = its pre-image row for row (245 harbours); her stores carry 642.9 days (cap 200068 nm > navigation 1700 nm); the board = its pre-image + shut (null on every row) + carry_days; good_board 1122.0, 976.0, 923.0, 931.0, 892.0, 914.0 ms (pre-image 919.0, 909.0, 925.0 ms)
0231 probe (b): hold 0.60 t free: carry 2.14 days, cap 503.4 nm; supply_need fits 503.4 nm and refuses 510.4 nm
0231 probe (c): loaded: the pre-image offered 208 sell passage(s) she could not sail (a leg past her stores); now 72 of them sail by more stops, the rest are shut with E_ENDURANCE; every routed row's longest leg is within 503 nm and sailable; good_board 760.0, 759.0, 767.0, 775.0, 742.0, 769.0 ms (pre-image 709.0, 708.0, 685.0 ms; 246 sell rows)
0231 probe (d): 136 sell row(s) shut with E_ENDURANCE, e.g. KAG {"nm": 1614, "cap_nm": 503, "leg_days": 6.0, "need_days": 6.9, "carry_days": 2.1}
0231 probe (e): leg_refusal: 478 nm open, 510 nm E_ENDURANCE, 1710 nm E_LEG_TOO_FAR; SAIL LIS -> BIL (580 nm) refused E_ENDURANCE, as leg_refusal said (that leg is 2.1 days at sea and asks 2.5 days of supplies; beside the cargo the hold carries 2.1 — sell some, or stop to resupply)
0231 probe (f): reach_passage capped / uncapped ms, in pairs: 193.0, 179.0, 220.0, 181.0, 196.0, 178.0
```

First run, before the merge and with the machine less busy (same file as 0227): loaded boards 427–592 ms against the pre-image's 406–600 ms; capped search 151–173 ms against 133–157 ms uncapped.

**Timing.** The board costs about the same. Loaded: 742–775 ms against the pre-image's 685–709, about +60 ms. Empty hold: 892–1,122 against 909–925, no change. The capped search, with its minimax pass, takes 193–220 ms against 178–181 uncapped, about +15 to +40 ms. On prod (about 1.7× this machine) that is under +0.1 s a board, well inside the +0.5 s budget. No buy-here case needs a second search (see §1, "decided by default").

## 3. PROD CHECKS (read-only; run by me on 2026-10-26 at head 0226; pasted results)

The checks are pure SELECTs, one statement per block. The functions called are `pg_get_functiondef`,
`to_regprocedure`, `replace`, `length`, `public.stores_topup`, `voyage.endurance_mult`, `voyage.stores_need_days`,
`voyage.fleet_speed`, `public.ship_hold_capacity`, `public.ship_cargo_tuns`, `public.passage_reach_nm` and
`public.supply_need`. All of them have `provolatile` 's' (3b shows them).

### 3a. Preconditions. Expect head `20260818000226`, one `reach_passage` with ACL `{postgres=X/postgres}` and `plan_cache_mode`, no `leg_refusal` / `supply_reach`, and `good_board` as the only caller.

```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select string_agg(p.oid::regprocedure::text || ' ' || coalesce(p.proacl::text, '') || ' ' || coalesce(p.proconfig::text, ''), '; ')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'voyage' and p.proname = 'reach_passage') as reach_passage,
       (select count(*) from pg_proc p where p.proname in ('leg_refusal', 'supply_reach')) as new_names_taken,
       (select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'voyage', 'world') and p.prosrc like '%reach_passage(%') as callers
```
Result:
```
head 20260818000226
reach_passage voyage.reach_passage(uuid,uuid,uuid) {postgres=X/postgres} {"search_path=public, pg_temp",plan_cache_mode=force_custom_plan}
new_names_taken 0
callers world.good_board(uuid,uuid,uuid,numeric)
```

### 3b. Volatility of every function the checks call. Expect every row 's'.

```sql
select p.oid::regprocedure::text as fn, p.provolatile from pg_proc p
 where p.oid in (to_regprocedure('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)'), to_regprocedure('voyage.endurance_mult(uuid)'),
                 to_regprocedure('voyage.stores_need_days(numeric,numeric)'), to_regprocedure('voyage.fleet_speed(uuid)'),
                 to_regprocedure('public.ship_hold_capacity(uuid)'), to_regprocedure('public.ship_cargo_tuns(uuid)'),
                 to_regprocedure('public.passage_reach_nm(uuid)'), to_regprocedure('public.supply_need(uuid,numeric)'))
```
Result: all 8 rows `s`.

### 3c. The hunks occur once on the LIVE bodies

I dumped both live bodies with `pg_get_functiondef` (LF-normalised) and matched every hunk's OLD text against
them in order, with a small node script. Result: all 15 hunks (reach_passage 1–5, good_board 1–10) occur exactly
once, and every NEW text occurs once in the result. The key old-only lines, checked on prod. Expect `1, 1, 1, 1, 0`:

```sql
select (length(rp) - length(replace(rp, 'v_reach float8 := public.passage_reach_nm(p_player)::float8;', ''))) / length('v_reach float8 := public.passage_reach_nm(p_player)::float8;') as rp_reach,
       (length(rp) - length(replace(rp, 'max_leg_nm := case when dist[j] is null then null else round(maxl[j]::numeric, 1) end;', ''))) / length('max_leg_nm := case when dist[j] is null then null else round(maxl[j]::numeric, 1) end;') as rp_maxleg,
       (length(gb) - length(replace(gb, 'from voyage.reach_passage(v_player, p_fleet, v_origin) r;', ''))) / length('from voyage.reach_passage(v_player, p_fleet, v_origin) r;') as gb_search,
       (length(gb) - length(replace(gb, 'cross join lateral voyage.reach_passage(v_player, p_fleet, s.id) r', ''))) / length('cross join lateral voyage.reach_passage(v_player, p_fleet, s.id) r') as gb_search2,
       (length(gb) - length(replace(gb, 'supply_reach', ''))) / length('supply_reach') as gb_new_already
  from (select replace(pg_get_functiondef(to_regprocedure('voyage.reach_passage(uuid,uuid,uuid)')), chr(13), '') as rp,
               replace(pg_get_functiondef(to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)')), chr(13), '') as gb) d
```
Result: `1, 1, 1, 1, 0`.

### 3d. The new rule, on prod's own fleets: what each docked human fleet with cargo can carry, and its cap (supply_reach's body as a SELECT)

```sql
select f.id, p.code as port, round(public.passage_reach_nm(f.player_id)) as nav, round(voyage.fleet_speed(f.id), 3) as kn,
       (select round(sum(public.ship_cargo_tuns(s.id)), 1) from public.ships s where s.fleet_id = f.id) as cargo_t,
       round(d.days, 2) as carry_days, round(d.days / voyage.stores_need_days(1, greatest(voyage.fleet_speed(f.id), 0.1)), 1) as cap_nm
  from public.fleets f join public.players pl on pl.id = f.player_id and not pl.is_npc join public.ports p on p.id = f.port_id
 cross join lateral (select min(t.days) * voyage.endurance_mult(f.id) as days from public.ships s
                      cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id), 1000000, public.ship_hold_capacity(s.id) * s.store_ratio) t
                      where s.fleet_id = f.id) d
 where f.status = 'DOCKED' and exists (select 1 from public.ships s where s.fleet_id = f.id and public.ship_cargo_tuns(s.id) > 0)
 order by cargo_t desc limit 12
```
Result:
```
51b8f474… HAV nav 1700  9.881 kn cargo 178.8 t carry   4.28 d cap    883.3 nm   (the owner's Gaivota)
a49d4a64… LIS nav 1700 14.238 kn cargo  32.4 t carry 527.14 d cap 156629.8 nm   (a light hold)
fc1e69b7… LIS nav 1700 14.663 kn cargo  12.0 t carry 600.00 d cap 183600.0 nm
24a94a0f… LIS nav 1700 14.704 kn cargo  10.0 t carry 607.14 d cap 186313.7 nm
97d80973… SAK nav 1700 14.704 kn cargo  10.0 t carry 607.14 d cap 186313.7 nm
```

### 3e. The light hold's far row fits (the longest leg of its Tsushima route, below). Expect `fits = true`.

```sql
select n.fits, n.need, n.days from public.supply_need('a49d4a64-8c4f-4634-812f-5d4ff85f4468', 1677.4) n
```
Result: `fits true, need 5.65, days 7`.

### 3f. The routes, with the new rule applied offline to prod's own matrix

I pulled `public.sea_reaches` (246 harbours) read-only and ran `reach_passage`'s search with the cap from 3d. The
script (`route.mjs`, not committed) is a line-for-line copy of the Dijkstra plus the minimax pass. The sea is dark on prod, so
every edge is open.

```
HAV -> TSU (the owner's Gaivota): cap 883.3 nm, nav 1700
 today (nav only): 18122.9 nm via STG>STJ>ANG>GOR>CAP>LUA>CPT>SOF>ISL>MOG>MLE>BAN>MAL>HON>XIA>TSU longest leg 1677.4 nm (7.07 d)
 capped: SHUT
 least longest leg within navigation (shut_leg_nm): 1613.6 nm (6.80 d at sea)  -> needs 7.8 d of supplies, she can carry 4.3
 harbours today with a leg past the cap: 219; now rerouted within it: 15; shut: 204; unchanged (already within): 3
LIS -> TSU (a light hold, a49d4a64): cap 156629.8 nm, nav 1700
 today and capped alike: 14735.6 nm via SAI>CAP>LUA>CPT>SOF>ISL>MOG>MLE>BAN>MAL>HON>TSU longest leg 1677.4 nm (4.91 d) — within the cap, and it fits (3e)
```

So, for the owner: no route to Tsushima has every leg within 4.3 days of supplies. The best route still has a
1,614-mile crossing, which needs 7.8 days of supplies. The row will now say **"Hold too full: 4.3 days of supplies,
crossing needs 7.8 days"** instead of offering a route he cannot sail. 15 other cities that used to show an
unsailable route now get a route that stops to resupply within his supplies. A light hold's cap is above its
navigation, so its board does not change.

**This board today (prod, owner's fleet, `on_board` guaiacum, 6 calls in one read-only statement):** 4.45, 4.31,
3.84, 3.24, 4.29 s between calls. The 219 unsailable-with-a-route rows match 3f. The ~1.2 s in the brief was for
other boards. This one is a full sell side for a full hold. 0231 adds about +35 ms to it (§2).

## 4. Proof run here (after `git merge origin/main`, chain head 0227 + this file as 0231)

- Cached-prefix apply (`node scripts/db/build-image.mjs`): 218/219 restored, 0231 applied, self-assert ok (§2). No
  from-zero apply and no full `db:proof`.
- `npx tsc -b` 0. eslint on the 5 touched client/spec files 0. `npm run build` with no `.env.local` 0.
- `tests/rpc.goodBoard.spec.ts`: 5 passed.
- `tests/planWords.spec.ts`: 12 passed with `navigator.language` forced to `en-US`. This machine's Node reports
  `ko-KR`, which makes the English expectations read Korean on main as well, so that is not a regression.
- On my own `vite preview --port 4207 --strictPort --host localhost`, killed afterwards: `desk.plan`,
  `desk.plantab` and `trade.loop` at 1440×900 and 390×844, 5 passed. An earlier run aimed at port 4200 hit another
  worktree's preview (mine had failed to bind), so I discarded it.

## 5. Rollback

Forward slice: reverse the good_board hunks (each OLD text is in the file verbatim). Drop
`voyage.reach_passage(uuid,uuid,uuid,numeric)` and re-create the pre-image (hunks reversed), with `revoke all … from
public, anon, authenticated, service_role`. Then `supply_reach` and `leg_refusal` may be dropped (good_board is
their only reader until B1).
