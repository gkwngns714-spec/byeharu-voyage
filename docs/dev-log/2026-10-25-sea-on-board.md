# 2026-10-25 — 0218: the board reads the sea (`osn-sea-on-board`)

> *"It should show restrictions – if whether my level, my class, my ship can go to that location."* (the owner,
> 2026-10-20, docs/OWNER_REQUESTS.md row 183)

The read that `docs/dev-log/2026-10-25-plan-tab.md` ("The missing server read") named. Prod head 0216; another routine
writes 0217 (new harbours), so this file is **0218** and renumbers to the prod head + 1 at push. `sea_conditions_bite`
stays dark.

## What changed

| Part | Where | What it does |
|---|---|---|
| The route of a row | `public.sea_route_stops(from, stops, to)` (new, immutable, server-only) | A served row's route as harbour codes: where she sails from, its stops, the city. A row with no passage (no miles) is the direct leg. |
| What its seas ask | `public.sea_routes(title, wave, routes)` (new, stable, server-only) | Per route `{ zone, zone_name, needs_title, needs_wave, refusal }`. needs = the most any leg asks in `public.sea_leg_asks` (0215, the one derivation). The verdict is `public.sea_refusal` (THE ONE RULE) over the route's zones: every harbour's own (`harbour_zone`), plus, only for a leg that asks more than both its harbours (an open-water crossing), the zones `course_zones` finds on the straight line between the roadsteads (the line `sea_leg_asks` was derived from). Nothing is compared outside the rule. `zone` = the refusing zone, else the most demanding. A route with no leg (the city she is at) is `null`. |
| The board | `world.good_board` (3 hunks) | Her title and her fleet's wave read once; every buy row gets `sea` for its route from where she sails; every sell row for its route through the buy city when it is bought first (the buy row's route, then the sell row's stops from there). The board gains `sea: { bite, title, wave }`. **Served dark too**: the refusal is then what the rule will answer. Lit, a city the sea closes has no passage (0216) and its row now says why. Every figure the board served before is unchanged (asserted). `plan_cache_mode = force_custom_plan` kept (asserted). |
| The wording | `planLines.ts`: `seaAsksWords` (new, THE wording), `reachWords`, `ReachBoard.seaBite` | Lit and refused: `reachWords` says "this sea asks title 2 and wave resistance 10 (Macaronesia and the Canary Current): you are title 1 and your fleet holds 12" instead of "too far to sail in one go". Dark it keeps the reach's wording: the sea is not the reason yet. |
| The Plan tab | `PlanVoyage.tsx`, "Can you go there?" | Per city the plan sails to: "Las Palmas — this sea asks title 2 and wave resistance 10 (…): more than you hold, but sea conditions are not in force yet." or "… the seas on the way ask title 1 and wave resistance 0: you hold enough." Lit and closed: printed once, as the reach note. The header's sentence "which seas each leg crosses is not served" was false after this, so it is replaced. |
| Types, words | `src/lib/rpc/types.ts` (`BoardSea`, `SeaRefusal`, `GoodBoard.sea`), `src/lib/i18n/dict/desk.ts` (en + ko) | |

## Why only the crossings are sampled (the hot path)

`good_board` is ~2 s on prod (0206). `course_zones` samples every 30 nm through `sea_zone_at`; sampling every leg of
every row would add hundreds of milliseconds. It is not needed: `sea_leg_asks` already holds each leg's maximum,
and both roadsteads are samples of that line, so a leg that asks no more than its two harbours' zones adds no zone
the rule could need. Only a leg that asks MORE (an open-water crossing) is sampled, once per distinct leg on the
whole board. **Exact**: the zone set reaches each leg's maximum, so `sea_refusal` refuses exactly when a leg asks
more than she holds; when several zones refuse, the one named is the first in requirement order among them.

## Decided by default

- `needs_title` / `needs_wave` are the ROUTE's most (what she must hold to sail all of it); `zone` is the refusing
  zone, else the route's most demanding zone. When refused the wording prints the refusing zone with its own asks
  (the rule's figures), so the name and the numbers always belong together.
- A row with no passage is judged on its direct leg (lit: the sea closed it, or the reach did). If the direct leg is
  open by the sea, the reason is the reach and the wording stays "too far".
- The lead leg of a fleet at anchor (open sea → nearest harbour) is not judged: `reach_passage` does not judge it.
- A leg with no `sea_leg_asks` row (a harbour added without re-deriving the table) is judged by its harbours' own
  zones; reach_passage treats it as open.

## Self-assert (own probe rows, rolled back)

DARK: the board minus `sea` equals the pre-image's, 6 + 6 calls timed in one session; every row with a leg carries
`sea` whose needs equal the most its legs ask (recomputed independently in the assert), and a refusal exactly when
she holds less (both kinds must be present: the positive control); Las Palmas bought from Lisbon by a title-1 barca
reads E_SEA_CLOSED; the board's `sea` is `{bite: false, title: 1, wave: 12}`. LIT (inside the rollback): Las
Palmas has no passage and says why (NOR-MAC, title 2 asked, 1 held); every buy row WITH a passage is clear (the
board and 0216's reach_passage agree); at title 3 Las Palmas opens and its refusal goes. Walls: both new readers
server-only; the board still the client's; the registry unchanged. Timings are printed by the receipt
(`raise notice '0218 self-assert ok: … TIMING good_board dark old … → new … ms (last 3: …), lit … ms'`).

## What was run here

`npm ci --ignore-scripts`, `npx tsc -b` (clean), `npx eslint .` (clean), the pure specs `planWords` (4 new cases),
`duplication`, `sections`, `i18n.keys`, `words`, `format`: 47 passed. The two new functions were run on a
scratch native PostgreSQL 16 against a four-harbour stub world (zones, asks, a stubbed `course_zones` counting its
calls): the six cases came out as designed (a coastal leg clear; Macaronesia refused at title 1; an ocean crossing
refused at its first zone in order and sampled once per distinct leg; a route with no leg null; title 4 / wave 30
clear, naming the Western Ocean as the most demanding). The re-cut `good_board` body and both self-assert blocks
compile there. **The PGlite world was not built here; the chain and the browser specs run in CI.**

## PROD CHECKS FOR THE MAIN SESSION

Run each block as written (`npx --yes supabase@2.120.0 db query --linked -f <file>`). Every block is a
`begin transaction read only … rollback`, SELECTs only, plus `set local` of the JWT claim in 8c/8d. The functions
called are `pg_get_functiondef`, `to_regprocedure`, `replace`, `length`, `public.port_offers`, `public.harbour_zone`,
`public.course_zones`, `public.sea_refusal`, `public.title_level`, `public.fleet_wave`, `public.sea_conditions_on`
and `world.good_board` — all `provolatile` 's' or 'i' (8b checks it). No EXPLAIN ANALYZE.

### 8a. The hunks. Expect every row `occurs = 1` and `new_already_there = 0` (at head 0216 and at 0217).

```sql
begin transaction read only;
with h(fn, n, old, new) as (values
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$  v_passages jsonb;                 -- 0205: voyage.reach_passage(v_player, v_origin), asked once
begin
$h$,
$h$  v_passages jsonb;                 -- 0205: voyage.reach_passage(v_player, v_origin), asked once
  v_title   int;                    -- 0218: her title (public.title_level), read once
  v_wave    numeric;                -- 0218: her fleet's wave resistance (public.fleet_wave), read once
  v_ocode   text;                   -- 0218: the harbour her passages run from
  v_bpart   jsonb;                  -- 0218: the route to the buy city, when it must be bought first
begin
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  return jsonb_build_object(
    'good', g.code,
$h$,
$h$  -- 0218: WHAT THE SEAS ON THE WAY ASK (docs/dev-log/2026-10-25-sea-on-board.md). Every row gains `sea` for the
  -- route it serves — where she sails from, its stops, the city (no passage: the direct leg); a sell row's route
  -- runs through the buy city when it must be bought first. public.sea_routes reads public.sea_leg_asks along the
  -- legs and judges them by public.sea_refusal, the one rule. Served dark too, as a reading; lit, a row the sea
  -- closes says so instead of arriving as "no passage" with no reason.
  v_title := public.title_level(v_player);
  v_wave  := public.fleet_wave(p_fleet);
  v_ocode := (select code from public.ports where id = v_origin);
  -- a row has a passage when it has miles (a buy row no passage reaches is served `stops: []`, 0188)
  select public.sea_route_stops(v_ocode, case when jsonb_typeof(e->'miles') = 'number' then e->'stops' end, e->>'port') into v_bpart
    from jsonb_array_elements(v_buy) e
   where v_basis <> 'on_board' and e->>'port' = v_src.code;
  select coalesce(jsonb_agg(b.e || jsonb_build_object('sea', s.sea) order by b.i), '[]'::jsonb) into v_buy
    from jsonb_array_elements(v_buy) with ordinality b(e, i)
    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when jsonb_typeof(x.e->'miles') = 'number' then x.e->'stops' end,
                                                             x.e->>'port') order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_buy) with ordinality x(e, i)))) with ordinality s(sea, i) on s.i = b.i;
  select coalesce(jsonb_agg(b.e || jsonb_build_object('sea', s.sea) order by b.i), '[]'::jsonb) into v_sell
    from jsonb_array_elements(v_sell) with ordinality b(e, i)
    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)
                                      || public.sea_route_stops(case when v_bpart is null then v_ocode else v_src.code end,
                                                                -- from the buy city its stops are null when no passage reaches on
                                                                case when v_bpart is not null or jsonb_typeof(x.e->'miles') = 'number' then x.e->'stops' end,
                                                                x.e->>'port') order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_sell) with ordinality x(e, i)))) with ordinality s(sea, i) on s.i = b.i;

  return jsonb_build_object(
    'good', g.code,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
$h$,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
    'sea', jsonb_build_object('bite', public.sea_conditions_on(), 'title', v_title, 'wave', v_wave),   -- 0218: what `sea` was judged for
$h$)
)
select h.fn, h.n,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as occurs,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_already_there
  from h
  cross join lateral (select replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') as def) d
 order by h.fn, h.n;
rollback;
```

### 8b. The preconditions. Expect every row `ok = true` (false rows sort first).

```sql
begin transaction read only;
select * from (
select 'head is 0216 or 0217' as what, max(version) in ('20260818000216', '20260818000217') as ok, max(version)::text as seen
  from supabase_migrations.schema_migrations
union all
select 'no 0218 object yet', to_regprocedure('public.sea_routes(int,numeric,jsonb)') is null
       and to_regprocedure('public.sea_route_stops(text,jsonb,text)') is null, null
union all
select 'sea_conditions_bite is false', not public.sea_conditions_on(), null
union all
select 'good_board keeps plan_cache_mode=force_custom_plan',
       (select coalesce(p.proconfig::text, '') like '%plan_cache_mode=force_custom_plan%' from pg_proc p
         where p.oid = to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)')),
       (select p.proconfig::text from pg_proc p where p.oid = to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)'))
union all
select 'every callee is stable or immutable',
       not exists (select 1 from pg_proc p where p.oid in (to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)'),
                   to_regprocedure('public.harbour_zone(uuid)'), to_regprocedure('public.course_zones(jsonb)'),
                   to_regprocedure('public.sea_refusal(int,numeric,text[])'), to_regprocedure('public.title_level(uuid)'),
                   to_regprocedure('public.fleet_wave(uuid)'), to_regprocedure('public.sea_conditions_on()'),
                   to_regprocedure('public.port_offers(uuid,uuid)')) and p.provolatile not in ('s', 'i'))
       and (select count(*) from pg_proc p where p.oid in (to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)'),
                   to_regprocedure('public.harbour_zone(uuid)'), to_regprocedure('public.course_zones(jsonb)'),
                   to_regprocedure('public.sea_refusal(int,numeric,text[])'), to_regprocedure('public.title_level(uuid)'),
                   to_regprocedure('public.fleet_wave(uuid)'), to_regprocedure('public.sea_conditions_on()'),
                   to_regprocedure('public.port_offers(uuid,uuid)'))) = 8, null
union all
select 'sea_leg_asks covers every harbour pair (0217 adds harbours: it must re-derive)',
       (select count(*) from public.sea_leg_asks) = (select count(*) * count(*) from public.ports where kind = 'HARBOUR'),
       (select count(*) from public.sea_leg_asks)::text || ' of ' || (select (count(*) * count(*))::text from public.ports where kind = 'HARBOUR')
union all
select 'every harbour has a zone', not exists (select 1 from public.ports p where p.kind = 'HARBOUR' and public.harbour_zone(p.id) is null), null
union all
select 'Lisbon is title-1 water; Las Palmas is NOR-MAC; LIS→LPA asks title 2 wave 10',
       public.harbour_zone((select id from public.ports where code = 'LIS')) = 'NOR-EU'
       and public.harbour_zone((select id from public.ports where code = 'LPA')) = 'NOR-MAC'
       and exists (select 1 from public.sea_leg_asks s where s.from_port = (select id from public.ports where code = 'LIS')
                     and s.to_port = (select id from public.ports where code = 'LPA') and s.title_min = 2 and s.wave_min = 10), null
union all
select 'Las Palmas sells a good (the probe''s subject)',
       exists (select 1 from public.port_goods pg where pg.port_id = (select id from public.ports where code = 'LPA')
                 and public.port_offers(pg.port_id, pg.good_id)), null
union all
select 'no probe residue named 0218', not exists (select 1 from public.players where company_name = 'Casa 0218'
       or auth_uid = '00000000-0218-4000-8000-000000000001'), null
union all
select 'the hunks'' anchor text holds (8a) — the body is the one the file was cut against',
       (select pg_get_functiondef(to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)')) like '%voyage.reach_passage(v_player, p_fleet, s.id) r   -- 0216%'), null
) q order by ok, what;
rollback;
```

### 8c. Timing: `world.good_board` ×6 in ONE session (the 0205/0206 generic-plan cliff).

**8c-0, the subject** — the first docked human company (not the owner's own, if you prefer: add `and p.auth_uid <> '<owner>'`),
its fleet and six goods its port sells:

```sql
begin transaction read only;
select p.auth_uid, f.id as fleet, (select code from public.ports where id = f.port_id) as port,
       (select array_agg(x.id order by x.code) from (select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
          where pg.port_id = f.port_id and public.port_offers(f.port_id, pg.good_id) order by g.code limit 6) x) as goods
  from public.players p join public.fleets f on f.player_id = p.id and f.port_id is not null
 where not p.is_npc and p.auth_uid is not null
 order by p.created_at, f.created_at limit 1;
rollback;
```

**8c-1, the boards** — paste `<AUTH_UID>`, `<FLEET>`, `<G1>`…`<G6>`; time the whole file with the shell
(`time npx --yes supabase@2.120.0 db query --linked -f 8c1.sql`). Before 0218 this is the baseline; 0206 measured
~2 s a board, so expect ≈ 12 s for six and **no board past ~3 s** (the cliff read 8–21 s a board).

```sql
begin transaction read only;
set local request.jwt.claims = '{"sub": "<AUTH_UID>"}';
set local request.jwt.claim.sub = '<AUTH_UID>';
select g.n, length(world.good_board(g.good::uuid, '<FLEET>'::uuid, null, null)::text) as bytes
  from (values (1, '<G1>'), (2, '<G2>'), (3, '<G3>'), (4, '<G4>'), (5, '<G5>'), (6, '<G6>')) g(n, good)
 order by g.n;
rollback;
```

### 8d. What 0218 adds, on prod's own data, before the push

The same six boards plus `public.sea_routes`' body,
inlined (the function does not exist on prod yet), over the routes 0218's hunk builds (buy rows from the port she is
docked at; sell rows through `qty.bought_at`). Time it the same way: **8d − 8c-1 is the cost of the sea pass**;
the budget is ≤ 10 % of the boards (≈ 1.2 s for six). The `refusal_rows` column is a sanity read: with a title-1
house in Europe it is the count of rows past home waters.

```sql
begin transaction read only;
set local request.jwt.claims = '{"sub": "<AUTH_UID>"}';
set local request.jwt.claim.sub = '<AUTH_UID>';
with who as materialized (
  select public.title_level(f.player_id) as title, public.fleet_wave(f.id) as wave,
         (select code from public.ports where id = f.port_id) as here
    from public.fleets f where f.id = '<FLEET>'::uuid),
bd as materialized (
  select g.n, world.good_board(g.good::uuid, '<FLEET>'::uuid, null, null) as j
    from (values (1, '<G1>'), (2, '<G2>'), (3, '<G3>'), (4, '<G4>'), (5, '<G5>'), (6, '<G6>')) g(n, good)),
src as (
  select bd.n, case when jsonb_typeof(e->'stops') = 'array' and jsonb_typeof(e->'miles') = 'number'
                    then jsonb_build_array((select here from who)) || (e->'stops') || jsonb_build_array(e->'port')
                    else jsonb_build_array((select here from who), e->'port') end as part, bd.j->'qty'->>'bought_at' as code
    from bd cross join lateral jsonb_array_elements(bd.j->'buy') e
   where bd.j->'qty'->>'basis' <> 'on_board' and e->>'port' = bd.j->'qty'->>'bought_at'),
rr as materialized (
  select jsonb_agg(r.route order by r.n, r.side, r.i) as routes from (
    select bd.n, 0 as side, x.i,
           case when jsonb_typeof(x.e->'stops') = 'array' and jsonb_typeof(x.e->'miles') = 'number'
                then jsonb_build_array((select here from who)) || (x.e->'stops') || jsonb_build_array(x.e->'port')
                else jsonb_build_array((select here from who), x.e->'port') end as route
      from bd cross join lateral jsonb_array_elements(bd.j->'buy') with ordinality x(e, i)
    union all
    select bd.n, 1, x.i,
           coalesce(s.part, '[]'::jsonb)
           || case when jsonb_typeof(x.e->'stops') = 'array' and (s.part is not null or jsonb_typeof(x.e->'miles') = 'number')
                   then jsonb_build_array(coalesce(s.code, (select here from who))) || (x.e->'stops') || jsonb_build_array(x.e->'port')
                   else jsonb_build_array(coalesce(s.code, (select here from who)), x.e->'port') end
      from bd cross join lateral jsonb_array_elements(bd.j->'sell') with ordinality x(e, i)
      left join src s on s.n = bd.n) r),
sea as (
  with rt as materialized (
    select r.i, r.route
      from jsonb_array_elements((select routes from rr))
           with ordinality r(route, i)),
  pt as materialized (
    select r.i, s.k, s.code
      from rt r
     cross join lateral jsonb_array_elements_text(case when jsonb_typeof(r.route) = 'array' then r.route else '[]'::jsonb end)
           with ordinality s(code, k)),
  harbour as materialized (
    select p.code, p.id, z.code as zone, z.title_min, z.wave_min
      from (select distinct code from pt where code is not null) c
      join public.ports p on p.code = c.code and p.kind = 'HARBOUR'
      left join public.sea_zones z on z.code = public.harbour_zone(p.id)),
  leg as materialized (
    select a.i, ha.id as from_id, hb.id as to_id, ha.zone as from_zone, hb.zone as to_zone, s.title_min, s.wave_min,
           coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
                    or s.wave_min > greatest(coalesce(ha.wave_min, -1), coalesce(hb.wave_min, -1)), false) as crosses
      from pt a
      join pt b on b.i = a.i and b.k = a.k + 1
      join harbour ha on ha.code = a.code
      join harbour hb on hb.code = b.code
      left join public.sea_leg_asks s on s.from_port = ha.id and s.to_port = hb.id
     where a.code <> b.code),
  crossing as materialized (
    select d.from_id, d.to_id,
           public.course_zones(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                                 jsonb_build_array(b.roadstead_lat, b.roadstead_lon))) as zones
      from (select distinct l.from_id, l.to_id from leg l where l.crosses) d
      join public.sea_reaches a on a.port_id = d.from_id
      join public.sea_reaches b on b.port_id = d.to_id),
  zone_of as (
    select l.i, l.from_zone as zone from leg l
    union
    select l.i, l.to_zone from leg l
    union
    select l.i, z.zone from leg l join crossing c on c.from_id = l.from_id and c.to_id = l.to_id
     cross join lateral unnest(c.zones) z(zone)),
  judged as materialized (
    select q.i, q.needs_title, q.needs_wave, zs.zones, public.sea_refusal((select title from who), (select wave from who), zs.zones) as refusal
      from (select l.i, max(l.title_min) as needs_title, max(l.wave_min) as needs_wave from leg l group by l.i) q
      left join (select o.i, array_agg(o.zone order by o.zone) filter (where o.zone is not null) as zones
                   from zone_of o group by o.i) zs on zs.i = q.i)
  select coalesce(jsonb_agg(case when j.i is null then null else jsonb_build_object(
           'zone',        coalesce(j.refusal->'figures'->>'zone', top.code),
           'zone_name',   coalesce(j.refusal->'figures'->>'zone_name', top.name),
           'needs_title', j.needs_title,
           'needs_wave',  j.needs_wave,
           'refusal',     j.refusal) end order by r.i), '[]'::jsonb)
    from rt r
    left join judged j on j.i = r.i
    left join lateral (select z.code, z.name from public.sea_zones z
                        where z.code = any(coalesce(j.zones, '{}'::text[]))
                        order by z.title_min desc, z.wave_min desc, z.ord limit 1) top on true
)
select (select count(*) from bd) as boards,
       (select jsonb_array_length(routes) from rr) as routes,
       (select count(*) from jsonb_array_elements((select * from sea)) e where jsonb_typeof(e) = 'object') as rows_with_sea,
       (select count(*) from jsonb_array_elements((select * from sea)) e where jsonb_typeof(e->'refusal') = 'object') as refusal_rows;
rollback;
```

### 8e. After the push (0218 live): the new board ×6, and the after-check

Re-run **8c-1** unchanged: now it times the NEW body. Expect within ~10 % of the 8c-1 baseline and no board past
~3 s. Then read one row back (`select world.good_board(…)->'buy'->0->'sea'`, same session shape): an object with
`zone`, `zone_name`, `needs_title`, `needs_wave`, `refusal` (null in home waters), and `->'sea'` on the board
`{"bite": false, …}`. The switch stays dark; nothing about play changes, so no 30-minute after-check is owed.
**Forward rollback**, if the timing regresses: reverse the three hunks (their OLD text is 8a's `old` column, verbatim)
with `create or replace` from `pg_get_functiondef`, then `drop function public.sea_routes(int, numeric, jsonb),
public.sea_route_stops(text, jsonb, text)`; the client tolerates a board without `sea` (every read is optional).
