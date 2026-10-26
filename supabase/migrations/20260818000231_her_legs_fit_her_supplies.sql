-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0231 — HER LEGS FIT HER SUPPLIES  (the desk's passages keep every leg within the stores her hold can carry beside
--        her cargo, so a far city is reached by stopping to resupply — or is shut, and the row says why)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md, row 208, 2026-10-26) ──────────────────────────────────────────────────────
-- *"Tsushima — longest leg 7.1 days, supplies last 4.3 days ... then the trip should automatically be made within
--  4 days right? why it doesnt do that?"*
--
-- ── WHY (measured on prod, read-only, head 0226) ─────────────────────────────────────────────────────────────────
-- voyage.reach_passage (0188) searches the shortest miles over public.sea_reaches with ONE leg cap: her navigation
-- (public.passage_reach_nm). It never read her supplies; world.good_board judged them only afterwards (`sailable` =
-- public.supply_need(fleet, longest leg).fits, 0225). So a passage was offered with a 7.1-day leg to a fleet whose hold
-- (178.8 of 180 t) holds 4.3 days of stores, and marked unsailable, with no second passage tried.
--
-- ── WHAT THIS FILE DOES ──────────────────────────────────────────────────────────────────────────────────────────
-- (1) THE LONGEST LEG HER STORES COVER. NEW public.supply_reach(fleet) → (carry_days, cap_nm): every hull topped up
--     as far as the room beside her cargo reaches (public.stores_topup, the one top-up — the very call supply_needs
--     makes, asked for more days than any room holds), the shortest hull's days times voyage.endurance_mult (the
--     reading `fits` makes), and the miles those days cover at the door's measure (voyage.stores_need_days — its
--     days per mile at her speed; no second copy of endurance_margin). Asserted against supply_need: a leg of
--     cap_nm fits, one a shade longer does not.
-- (2) THE ONE LEG JUDGE. NEW voyage.leg_refusal(fleet, dest, nm, course): public.passage_gate (her navigation, and
--     lit the seas), else E_ENDURANCE when public.supply_need(fleet, nm).fits is false — with the figures the row
--     prints (leg days, the days of stores it asks, the days her hold can carry). docs/ROUTE_BUILDER.md §3 names it;
--     world.route_legs, cmd.issue_lines and the route save reuse it in B1. Here good_board reads it for a shut row.
-- (3) THE SEARCH TAKES THE CAP. voyage.reach_passage(player, fleet, from, p_cap_nm numeric DEFAULT NULL): a leg is
--     open within least(her navigation, p_cap_nm) — the old signature is dropped, its ACL, volatility, definer and
--     config (plan_cache_mode included) carried over and asserted; a null cap is the old search exactly (asserted
--     row for row against the pre-image). It also serves `shut_leg_nm`: for a harbour no capped passage reaches but
--     one within her navigation would, the least longest leg such a passage asks (a minimax pass over the same
--     matrix, the same edges; run only when the cap binds and shuts something).
-- (4) THE BOARD PASSES IT. world.good_board reads supply_reach once, searches with that cap (from where she sails,
--     and from the buy city when it must be bought first), and every buy and sell row gains `shut`: for a city no
--     passage within her stores reaches, voyage.leg_refusal's E_ENDURANCE for that least longest leg (once per
--     distinct length). The board's `supplies` gains `carry_days` (the "can carry X days" the desk prints instead
--     of "supplies last X"). Every other key is its pre-image's reading under the capped search.
--
-- ── NOT THE OWNER'S — CONFIRM ────────────────────────────────────────────────────────────────────────────────────
-- * The cap reads the cargo she holds NOW — the hold `fits` already judges (0225). A buy row's purchase is not
--   subtracted from it; the sell row's `supplies.units_fit` (0225) already says how much of the good a BUY may load
--   and still sail that row's longest leg, so a second, cargo-aware search is not run.
-- * leg_refusal takes (fleet, dest, nm, course) as docs/ROUTE_BUILDER.md names it, not (fleet, from, to, nm): the
--   origin is asked of nothing (the gate and the stores judge the leg's length, dest and course).
-- * The owner's "within 4 days" is the stores' days; a leg asks endurance_margin (1.15) more stores than its days at
--   sea, so a 4.3-day hold carries legs of 3.7 days at sea. The shut row prints the stores against the stores.
--
-- ── LOCKS AND TIME ───────────────────────────────────────────────────────────────────────────────────────────────
-- CREATE FUNCTION ×2, DROP + CREATE ×1 (reach_passage, by hunks), CREATE OR REPLACE ×1 (good_board, by hunks). The
-- probes run on their own company inside a sub-block rolled back whole; only their rows are counted. No LOCK TABLE,
-- no set role, no set local, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0226, LF-normalised, each asserted to occur exactly
-- once and to reverse to its pre-image, ACL unchanged): see hunks_0231 below.
-- ROLLBACK: a forward slice reverses the hunks (each OLD text is here verbatim; reach_passage is dropped and the
-- pre-image re-created with its ACL), then supply_reach and leg_refusal may be dropped.
-- VERSION: 0231 (numbered by the coordinator: 0227–0230 deploy first, none of them touches the two bodies cut here;
--          the hunks were sliced from prod head 0226 and assert themselves on the body live when this applies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0231(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0231 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE LONGEST LEG HER STORES COVER ─────────────────────────────────────────────────────────────────────────
create function public.supply_reach(p_fleet uuid)
returns table (carry_days numeric, cap_nm numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0231 (owner row 208): THE DAYS OF STORES HER HOLD CAN CARRY BESIDE HER CARGO, AND THE LONGEST LEG THEY COVER.
  --   carry_days  every hull topped up as far as the room beside her cargo reaches — public.stores_topup, the one
  --               top-up (as public.supply_needs and cmd.do_provision call it), asked for more days than any room
  --               holds — the shortest hull's days times voyage.endurance_mult (the reading `fits` makes)
  --   cap_nm      the miles those days cover at the sail door's measure: voyage.stores_need_days is linear in the
  --               miles, so its days for one mile at her speed is the rate (no second copy of endurance_margin)
  -- A leg of cap_nm fits (public.supply_need), a longer one does not (asserted, 0231). Null for a fleet with no hull.
  -- Read by world.good_board (the cap its passages keep within) and voyage.leg_refusal (the days in its words).
  select d.days,
         d.days / voyage.stores_need_days(1, greatest(voyage.fleet_speed(p_fleet), 0.1))
    from (select min(t.days) * voyage.endurance_mult(p_fleet) as days
            from public.ships s
           cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t,
                                                  public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id),
                                                  1000000, public.ship_hold_capacity(s.id) * s.store_ratio) t
           where s.fleet_id = p_fleet) d
$$;
revoke all on function public.supply_reach(uuid) from public, anon, authenticated;
comment on function public.supply_reach(uuid) is
  '0231: the days of stores a fleet''s hold can carry beside her cargo, topped up as every SAIL tops them, and the longest '
  'leg they cover (supply_need fits it). Read by world.good_board and voyage.leg_refusal. Server-only.';

-- ── 2. THE ONE LEG JUDGE ────────────────────────────────────────────────────────────────────────────────────────
create function voyage.leg_refusal(p_fleet uuid, p_dest uuid, p_nm numeric, p_course jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0231 (owner row 208; docs/ROUTE_BUILDER.md §3): MAY THIS FLEET SAIL A LEG OF p_nm TO p_dest ON p_course? Null when
-- she may; otherwise a cmd.refusal. The SAIL's own gate in the order it applies them: public.passage_gate (her
-- navigation; lit, the seas of the destination and the course), then whether the stores the leg asks FIT her hold
-- beside her cargo (public.supply_need — the rule cmd.do_sail tops her up by and voyage.sail_refusal then judges:
-- E_ENDURANCE). A null dest and course ask the length alone. Read by world.good_board (why a city is shut); B1's
-- world.route_legs, cmd.issue_lines and the route save reuse it. Judged against her hold as it is now.
declare
  v_player uuid;
  v_gate   jsonb;
  v_need   record;
  v_reach  record;
  v_speed  numeric;
  v_leg    numeric;
begin
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  v_gate := public.passage_gate(v_player, p_fleet, p_nm, p_dest, p_course);
  if v_gate is not null then
    return v_gate;
  end if;
  if coalesce(p_nm, 0) <= 0 then
    return null;
  end if;
  select * into v_need from public.supply_need(p_fleet, p_nm);
  if v_need.fits then
    return null;
  end if;
  select * into v_reach from public.supply_reach(p_fleet);
  v_speed := greatest(voyage.fleet_speed(p_fleet), 0.1);
  v_leg   := round(p_nm / v_speed / 24, 1);
  return cmd.refusal('E_ENDURANCE',
           format('that leg is %s days at sea and asks %s days of supplies; beside the cargo the hold carries %s — sell some, or stop to resupply',
                  v_leg, round(v_need.need, 1), round(coalesce(v_reach.carry_days, 0), 1)),
           jsonb_build_object('nm', round(p_nm), 'leg_days', v_leg, 'need_days', round(v_need.need, 1),
                              'carry_days', round(coalesce(v_reach.carry_days, 0), 1), 'cap_nm', round(v_reach.cap_nm)));
end $$;
revoke all on function voyage.leg_refusal(uuid, uuid, numeric, jsonb) from public, anon, authenticated;
comment on function voyage.leg_refusal(uuid, uuid, numeric, jsonb) is
  '0231: the one leg judge — passage_gate, then E_ENDURANCE when the stores the leg asks do not fit beside her cargo '
  '(supply_need). Read by world.good_board; reused by the route builder (docs/ROUTE_BUILDER.md). Server-only.';

-- ── 3. THE PRE-IMAGES ───────────────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0231 on commit drop as
select f.ord, f.fn, f.new_fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'voyage.reach_passage(uuid,uuid,uuid)',          'voyage.reach_passage(uuid,uuid,uuid,numeric)'),
               (2, 'world.good_board(uuid,uuid,uuid,numeric)',      'world.good_board(uuid,uuid,uuid,numeric)')) f(ord, fn, new_fn);

create temp table hunks_0231 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0231 values
-- voyage.reach_passage: the cap, and why a harbour it shuts is shut
('voyage.reach_passage(uuid,uuid,uuid)', 1,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_fleet uuid, p_from uuid)
 RETURNS TABLE(port_id uuid, code text, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
$h$,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_fleet uuid, p_from uuid, p_cap_nm numeric DEFAULT NULL::numeric)
 RETURNS TABLE(port_id uuid, code text, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 2,
$h$  v_reach float8 := public.passage_reach_nm(p_player)::float8;
$h$,
$h$  -- 0231 (owner row 208): a leg is open within her navigation AND within p_cap_nm — the longest leg her stores can
  -- cover beside her cargo (world.good_board passes public.supply_reach); least() of the two, a null cap is no cap
  v_nav   float8 := public.passage_reach_nm(p_player)::float8;
  v_reach float8 := least(v_nav, p_cap_nm::float8);
  bn      float8[];           -- 0231: the least longest leg of a passage within her navigation (only when the cap shuts one)
  v_shut  boolean := false;   -- 0231: the cap left a harbour unreached
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 3,
$h$      select r.port_id, r.code, r.nm, r.nm, '{}'::text[], r.nm
$h$,
$h$      select r.port_id, r.code, r.nm, r.nm, '{}'::text[], r.nm, null::numeric   -- 0231: nothing is shut
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 4,
$h$  for j in 1 .. v_n loop
    continue when j = v_s;
    v_path := null;
$h$,
$h$  -- 0231: WHY A HARBOUR THE CAP SHUTS IS SHUT. When her stores cap the legs below her navigation and the capped
  -- search left a harbour unreached, a second pass over the same matrix (the same edges, open by the same sea rule)
  -- finds for every harbour the least longest leg a passage within her navigation asks: a minimax Dijkstra.
  if v_reach < v_nav or (v_nav is null and v_reach is not null) then
    for j in 1 .. v_n loop
      if j <> v_s and dist[j] is null and v_open[j] then
        v_shut := true;
        exit;
      end if;
    end loop;
  end if;
  if v_shut then
    bn   := array_fill(null::float8, array[v_n]);
    done := array_fill(false, array[v_n]);
    bn[v_s] := 0;
    loop
      u := 0;
      best := null;
      for i in 1 .. v_n loop
        if not done[i] and bn[i] is not null and (best is null or bn[i] < best) then
          u := i;
          best := bn[i];
        end if;
      end loop;
      exit when u = 0;
      done[u] := true;
      for j in 1 .. v_n loop
        if not done[j] and v_open[j] and (ok is null or ok[(u - 1) * v_n + j]) then
          w := d[(u - 1) * v_n + j];
          if w is not null and (v_nav is null or w <= v_nav) then
            nd := greatest(best, w);
            if bn[j] is null or nd < bn[j] then
              bn[j] := nd;
            end if;
          end if;
        end if;
      end loop;
    end loop;
  end if;

  for j in 1 .. v_n loop
    continue when j = v_s;
    v_path := null;
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 5,
$h$    max_leg_nm := case when dist[j] is null then null else round(maxl[j]::numeric, 1) end;
$h$,
$h$    max_leg_nm := case when dist[j] is null then null else round(maxl[j]::numeric, 1) end;
    -- 0231: no capped passage reaches it, one within her navigation would: the least longest leg that one asks
    shut_leg_nm := case when dist[j] is null and v_shut then round(bn[j]::numeric, 1) end;
$h$),
-- world.good_board: the passages keep within her stores; a shut row says why; the board says what she can carry
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$  v_bpart   jsonb;                  -- 0219: the route to the buy city, when it must be bought first
begin
$h$,
$h$  v_bpart   jsonb;                  -- 0219: the route to the buy city, when it must be bought first
  v_carry   numeric;                -- 0231: the days of stores her hold can carry beside her cargo (public.supply_reach)
  v_cap     numeric;                -- 0231: the longest leg those stores cover: every passage below keeps within it
begin
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  v_margin := public.wc_num('endurance_margin');
$h$,
$h$  v_margin := public.wc_num('endurance_margin');
  -- 0231 (owner row 208): HER LEGS FIT HER SUPPLIES. Every SAIL tops her stores up to the room beside her cargo (0225),
  -- so the longest leg she can sail is the one those stores cover (public.supply_reach — the rules `fits` reads). The
  -- passages are searched with every leg within it: a far city is reached by stopping to resupply, or is shut and
  -- says why (`shut`, voyage.leg_refusal).
  select sr.carry_days, sr.cap_nm into v_carry, v_cap from public.supply_reach(p_fleet) sr;
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$  select coalesce(jsonb_agg(jsonb_build_object('port_id', r.port_id, 'nm', r.nm, 'direct_nm', r.direct_nm,
                                               'stops', r.stops, 'max_leg_nm', r.max_leg_nm)), '[]'::jsonb)
    into v_passages
    from voyage.reach_passage(v_player, p_fleet, v_origin) r;   -- 0216: + her fleet (the sea conditions)
$h$,
$h$  select coalesce(jsonb_agg(jsonb_build_object('port_id', r.port_id, 'nm', r.nm, 'direct_nm', r.direct_nm,
                                               'stops', r.stops, 'max_leg_nm', r.max_leg_nm,
                                               'shut_leg_nm', r.shut_leg_nm)), '[]'::jsonb)   -- 0231
    into v_passages
    from voyage.reach_passage(v_player, p_fleet, v_origin, v_cap) r;   -- 0216: + her fleet; 0231: + the legs her stores cover
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 4,
$h$    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)   -- 0205
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end
     where v_origin is not null
  ), sellers as materialized (
$h$,
$h$    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg,
           r.shut_leg_nm as shut_leg   -- 0231
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)   -- 0205
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end, null
     where v_origin is not null
  ), shuts as materialized (
    -- 0231: why a city no passage within her stores reaches is shut — voyage.leg_refusal (THE leg judge) for the least
    -- longest leg a passage within her navigation would ask, once per distinct length
    select u.nm, voyage.leg_refusal(p_fleet, null, u.nm, null) as refusal
      from (select distinct x.shut_leg from reach x where x.nm is null and x.shut_leg is not null) u(nm)
  ), sellers as materialized (
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 5,
$h$           'units', s.units, 'cost', s.total, 'price_each', s.avg_price, 'stock', s.stock,
$h$,
$h$           'shut', (select sh.refusal from reach x join shuts sh on sh.nm = x.shut_leg where x.port_id = s.id and x.nm is null),   -- 0231
           'units', s.units, 'cost', s.total, 'price_each', s.avg_price, 'stock', s.stock,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 6,
$h$    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end
     where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm, r.direct_nm, r.stops, r.max_leg_nm as max_leg
      from (select id from src where id is distinct from v_origin) s
     cross join lateral voyage.reach_passage(v_player, p_fleet, s.id) r   -- 0216
    union all   -- 0205: bought where she sails from — those are the passages asked once, above
    select x.port_id, x.nm, x.direct_nm, x.stops, x.max_leg_nm
      from src cross join jsonb_to_recordset(v_passages) x(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
     where src.id = v_origin
    union all select id, 0, 0, '{}'::text[], 0 from src
$h$,
$h$    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg,
           r.shut_leg_nm as shut_leg   -- 0231
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end, null
     where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm, r.direct_nm, r.stops, r.max_leg_nm as max_leg, r.shut_leg_nm as shut_leg   -- 0231
      from (select id from src where id is distinct from v_origin) s
     cross join lateral voyage.reach_passage(v_player, p_fleet, s.id, v_cap) r   -- 0216; 0231: + the legs her stores cover
    union all   -- 0205: bought where she sails from — those are the passages asked once, above
    select x.port_id, x.nm, x.direct_nm, x.stops, x.max_leg_nm, x.shut_leg_nm
      from src cross join jsonb_to_recordset(v_passages) x(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
     where src.id = v_origin
    union all select id, 0, 0, '{}'::text[], 0, null from src
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 7,
$h$           case when v_basis = 'on_board' then rc.max_leg
                else greatest((select rc1.max_leg from reach rc1 where rc1.port_id = (select id from src)), r2.max_leg) end as max_leg
      from public.ports p
$h$,
$h$           case when v_basis = 'on_board' then rc.max_leg
                else greatest((select rc1.max_leg from reach rc1 where rc1.port_id = (select id from src)), r2.max_leg) end as max_leg,
           -- 0231: no passage within her stores, one within her navigation would: the least longest leg it asks (bought
           -- first elsewhere: each part's longest leg, or the leg that shuts it; null when her navigation shuts a part)
           case when v_basis = 'on_board' then case when rc.nm is null then rc.shut_leg end
                when r2.nm is not null and (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) is not null then null
                else (select greatest(a.v, b.v)
                        from (select case when rc1.nm is null then rc1.shut_leg else rc1.max_leg end as v
                                from reach rc1 where rc1.port_id = (select id from src)) a
                       cross join (select case when r2.nm is null then r2.shut_leg else r2.max_leg end as v) b
                       where a.v is not null and b.v is not null) end as shut_leg
      from public.ports p
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 8,
$h$  ), free as materialized (
$h$,
$h$  ), shuts as materialized (
    -- 0231: why a city no passage within her stores reaches is shut — voyage.leg_refusal, once per distinct length
    select u.nm, voyage.leg_refusal(p_fleet, null, u.nm, null) as refusal
      from (select distinct c.shut_leg from cand c where c.nm is null and c.shut_leg is not null) u(nm)
  ), free as materialized (
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 9,
$h$           'stock', r.stock, 'stock_target', r.stock_target,   -- 0183
$h$,
$h$           'shut', (select sh.refusal from shuts sh where sh.nm = r.shut_leg and r.nm is null),   -- 0231
           'stock', r.stock, 'stock_target', r.stock_target,   -- 0183
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 10,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
$h$,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin,   -- 0188
                                   'carry_days', round(v_carry, 1)),   -- 0231: the days her hold can carry beside her cargo
$h$);

-- the pre-images under pg_temp names, for the parity proofs and the positive controls
do $$
begin
  if (select count(*) from defs_before_0231 where def is not null) <> 2 then
    raise exception '0231 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0231 where def is not null);
  end if;
  execute replace((select def from defs_before_0231 where ord = 1),
                  'CREATE OR REPLACE FUNCTION voyage.reach_passage(', 'CREATE OR REPLACE FUNCTION pg_temp.reach_passage_old_0231(');
  -- the pre-image board on the pre-image search (a null cap after the swap is asserted equal to it, row for row)
  execute replace(replace((select def from defs_before_0231 where ord = 2),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0231('),
                  'voyage.reach_passage(', 'pg_temp.reach_passage_old_0231(');
end $$;

-- ── 4. THE NEW BODIES ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  g     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0231 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0231 where fn = d.fn order by n loop
      if pg_temp.occurs_0231(v_def, h.old) <> 1 then
        raise exception '0231 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0231(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0231 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- a widened signature is a new function: the old one is dropped first (its callers name it by its first three
    -- arguments, which the new one takes with the same names and positions, the cap through its default)
    if d.fn <> d.new_fn then
      execute format('drop function %s', d.fn);
    end if;
    execute v_def;
    if d.fn <> d.new_fn then
      execute format('revoke all on function %s from public', d.new_fn);
      for g in select r.rolname from pg_roles r where r.rolname in ('anon', 'authenticated', 'service_role') loop
        execute format('revoke all on function %s from %I', d.new_fn, g.rolname);
      end loop;
      for g in select distinct case when a.grantee = 0 then 'public' else a.grantee::regrole::text end as who
                 from pg_proc pp, aclexplode(coalesce(nullif(d.acl, '')::aclitem[], '{}'::aclitem[])) a
                where pp.oid = d.new_fn::regprocedure and a.grantee <> pp.proowner and a.privilege_type = 'EXECUTE' loop
        execute format('grant execute on function %s to %s', d.new_fn, g.who);
      end loop;
    end if;
    v_rev := replace(pg_get_functiondef(d.new_fn::regprocedure), E'\r', '');
    for h in select * from hunks_0231 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0231(v_rev, h.new) <> 1 then
        raise exception '0231 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0231 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.new_fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0231 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 2 then
    raise exception '0231 self-assert FAIL: % bodies re-cut, not 2', v_n;
  end if;
  if exists (select 1 from pg_proc pp join pg_namespace ns on ns.oid = pp.pronamespace
              where (ns.nspname, pp.proname) in (('voyage', 'reach_passage'), ('voyage', 'leg_refusal'), ('public', 'supply_reach'))
              group by ns.nspname, pp.proname having count(*) <> 1) then
    raise exception '0231 self-assert FAIL: an old signature survived beside the new one';
  end if;
  -- the two new functions are the server's: no client role may run them
  if has_function_privilege('authenticated', 'public.supply_reach(uuid)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'public.supply_reach(uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'voyage.leg_refusal(uuid, uuid, numeric, jsonb)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'voyage.leg_refusal(uuid, uuid, numeric, jsonb)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'voyage.reach_passage(uuid, uuid, uuid, numeric)'::regprocedure, 'execute') then
    raise exception '0231 self-assert FAIL: supply_reach, leg_refusal or reach_passage is executable by a client role';
  end if;
  -- ONE SEARCH CALLER: only world.good_board asks voyage.reach_passage (the route builder's B1 will be the second)
  if exists (select 1 from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world') and pp.prosrc like '%voyage.reach_passage(%'
                and not (n.nspname = 'world' and pp.proname = 'good_board')) then
    raise exception '0231 self-assert FAIL: a live body other than world.good_board calls voyage.reach_passage';
  end if;
  -- ONE MEASURE (0203's guard, kept): no live body but voyage.stores_need_days applies endurance_margin
  if exists (select 1 from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and pp.prosrc ~ '[*/]\s*(v_margin|v_emargin|public\.wc_num\(''endurance_margin''\))' and pp.proname <> 'stores_need_days') then
    raise exception '0231 self-assert FAIL: a copy of the stores measure appeared';
  end if;
end $$;

-- ── 5. THE PROBES: one company of this file's own, inside a sub-block that is rolled back whole ─────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0231-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_good    uuid;
  v_gcode   text;
  v_bulk    numeric;
  v_board   jsonb;
  v_old     jsonb;
  v_carry   numeric;
  v_cap     numeric;
  v_nav     numeric;
  v_speed   numeric;
  v_room    numeric;
  v_ref     jsonb;
  v_dest    uuid;
  v_dcode   text;
  v_course  jsonb;
  v_cnm     numeric;
  v_res     jsonb;
  v_n       int;
  v_rerouted int;
  v_bug     int;
  v_shut    int;
  v_ms      numeric[] := '{}';
  v_ms_old  numeric[] := '{}';
  v_ms_e    numeric[] := '{}';
  v_ms_eold numeric[] := '{}';
  v_ms_rp   numeric[] := '{}';
  v_t       timestamptz;
  v_hazard  jsonb;
  k         int;
  r_a text; r_b text; r_c text; r_d text; r_e text; r_f text;
begin
  select value into v_hazard from public.world_config where key = 'hazard_p_max';
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(c_auth, 'Probe 0231', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    if (select port_id from public.fleets where id = v_fleet) <> v_lis then
      raise exception '0231 self-assert FAIL: the probe company was not founded at Lisbon';
    end if;
    select g.id, g.code, g.bulk into v_good, v_gcode, v_bulk
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and pg.stock > 0 and public.port_offers(v_lis, g.id)
     order by g.code limit 1;
    if v_good is null then
      raise exception '0231 self-assert FAIL: Lisbon offers no good in stock';
    end if;
    perform cmd.assume_identity(c_auth);
    v_nav := public.passage_reach_nm(v_player);

    -- (a) A NULL CAP IS THE OLD SEARCH, row for row; an empty hold's cap is past her navigation, so the board is its
    --     pre-image plus `shut` (null everywhere) and `carry_days`
    if exists ((select port_id, code, nm, direct_nm, stops, max_leg_nm from pg_temp.reach_passage_old_0231(v_player, v_fleet, v_lis)
                except
                select port_id, code, nm, direct_nm, stops, max_leg_nm from voyage.reach_passage(v_player, v_fleet, v_lis, null))
               union all
               (select port_id, code, nm, direct_nm, stops, max_leg_nm from voyage.reach_passage(v_player, v_fleet, v_lis, null)
                except
                select port_id, code, nm, direct_nm, stops, max_leg_nm from pg_temp.reach_passage_old_0231(v_player, v_fleet, v_lis)))
       or exists (select 1 from voyage.reach_passage(v_player, v_fleet, v_lis, null) where shut_leg_nm is not null)
       or (select count(*) from voyage.reach_passage(v_player, v_fleet, v_lis, null))
          <> (select count(*) from pg_temp.reach_passage_old_0231(v_player, v_fleet, v_lis)) then
      raise exception '0231 self-assert FAIL: reach_passage with a null cap is not its pre-image';
    end if;
    select sr.carry_days, sr.cap_nm into v_carry, v_cap from public.supply_reach(v_fleet) sr;
    if v_cap is null or v_cap <= v_nav then
      raise exception '0231 self-assert FAIL: an empty hold''s cap (% nm, % days) is not past her navigation (% nm)', round(v_cap), round(v_carry, 1), v_nav;
    end if;
    for k in 1 .. 6 loop
      v_t := clock_timestamp();
      v_board := world.good_board(v_good, v_fleet, null, null);
      v_ms_e := v_ms_e || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    for k in 1 .. 3 loop
      v_t := clock_timestamp();
      v_old := pg_temp.good_board_old_0231(v_good, v_fleet, null, null);
      v_ms_eold := v_ms_eold || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    if (select jsonb_agg(e - 'shut') from jsonb_array_elements(v_board->'sell') e) <> (v_old->'sell')
       or (select jsonb_agg(e - 'shut') from jsonb_array_elements(v_board->'buy') e) <> (v_old->'buy')
       or exists (select 1 from jsonb_array_elements(v_board->'sell') e where jsonb_typeof(e->'shut') <> 'null')
       or exists (select 1 from jsonb_array_elements(v_board->'buy') e where jsonb_typeof(e->'shut') <> 'null')
       or (v_board - 'buy' - 'sell' - 'supplies') <> (v_old - 'buy' - 'sell' - 'supplies')
       or (v_board->'supplies') - 'carry_days' <> (v_old->'supplies')
       or (v_board->'supplies'->>'carry_days')::numeric is distinct from round(v_carry, 1) then
      raise exception '0231 self-assert FAIL: with an empty hold the board is not its pre-image plus shut (null) and carry_days';
    end if;
    r_a := format('empty hold: reach_passage(null cap) = its pre-image row for row (%s harbours); her stores carry %s days (cap %s nm > navigation %s nm); the board = its pre-image + shut (null on every row) + carry_days; good_board %s ms (pre-image %s ms)',
                  (select count(*) from voyage.reach_passage(v_player, v_fleet, v_lis, null)), round(v_carry, 1), round(v_cap), v_nav,
                  array_to_string(v_ms_e, ', '), array_to_string(v_ms_eold, ', '));

    -- THE OWNER'S CASE: her casks dry and her hold all but full of the good — room beside the cargo for the stores of a
    -- ~600-mile leg at her speed (the hold the owner's Gaivota had at Havana: 178.8 of 180 t)
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;
    v_speed := greatest(voyage.fleet_speed(v_fleet), 0.1);
    update public.ships s
       set cargo = jsonb_build_object(v_gcode, floor(greatest(0, public.ship_hold_capacity(s.id)
                     - s.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'))
                       * voyage.stores_need_days(600, v_speed)) / greatest(v_bulk, 0.001)))
     where s.fleet_id = v_fleet;
    select sr.carry_days, sr.cap_nm into v_carry, v_cap from public.supply_reach(v_fleet) sr;
    v_room := (select sum(public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)) from public.ships s where s.fleet_id = v_fleet);
    if v_cap is null or v_cap < 300 or v_cap > v_nav * 0.8 then
      raise exception '0231 self-assert FAIL: the loaded probe''s cap is % nm (% days, % t of room) — a cap between 300 nm and 80%% of her navigation (% nm) was the precondition', round(v_cap), round(v_carry, 2), v_room, v_nav;
    end if;

    -- (b) THE CAP IS supply_need's EDGE: a leg of cap_nm fits, a shade longer does not
    if (select fits from public.supply_need(v_fleet, v_cap)) is not true
       or (select fits from public.supply_need(v_fleet, v_cap * 1.01 + 2)) is not false then
      raise exception '0231 self-assert FAIL: supply_need does not fit a leg of the cap (% nm) and refuse one just past it', round(v_cap, 1);
    end if;
    r_b := format('hold %s t free: carry %s days, cap %s nm; supply_need fits %s nm and refuses %s nm', round(v_room, 2), round(v_carry, 2), round(v_cap, 1), round(v_cap, 1), round(v_cap * 1.01 + 2, 1));

    -- (c) THE BOARD ROUTES WITHIN IT. Every row the capped search reaches has every leg within the cap and is
    --     sailable; at least one row the pre-image offered with a leg too long for her stores now sails by stopping to
    --     resupply (positive control: the pre-image marked it unsailable WITH a passage — owner row 208's bug)
    for k in 1 .. 6 loop
      v_t := clock_timestamp();
      v_board := world.good_board(v_good, v_fleet, null, null);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    for k in 1 .. 3 loop
      v_t := clock_timestamp();
      v_old := pg_temp.good_board_old_0231(v_good, v_fleet, null, null);
      v_ms_old := v_ms_old || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    if v_board->'qty'->>'basis' <> 'on_board' then
      raise exception '0231 self-assert FAIL: the loaded board reads basis %, on_board expected', v_board->'qty'->>'basis';
    end if;
    select count(*) into v_n from jsonb_array_elements(v_board->'sell') e
     where jsonb_typeof(e->'miles') = 'number' and e->>'port' <> 'LIS'
       and ((e->'longest_leg'->>'miles')::numeric > v_cap + 0.5 or (e->>'sailable')::boolean is not true);
    if v_n > 0 then
      raise exception '0231 self-assert FAIL: % sell row(s) with a passage have a leg past the cap (% nm) or are not sailable: %', v_n, round(v_cap),
        (select jsonb_agg(jsonb_build_object('port', e->>'port', 'leg', e->'longest_leg', 'sailable', e->'sailable')) from jsonb_array_elements(v_board->'sell') e
          where jsonb_typeof(e->'miles') = 'number' and e->>'port' <> 'LIS' and ((e->'longest_leg'->>'miles')::numeric > v_cap + 0.5 or (e->>'sailable')::boolean is not true));
    end if;
    select count(*) into v_bug from jsonb_array_elements(v_old->'sell') o
     where jsonb_typeof(o->'miles') = 'number' and (o->>'sailable')::boolean is false;
    select count(*) into v_rerouted from jsonb_array_elements(v_old->'sell') o
      join jsonb_array_elements(v_board->'sell') e on e->>'port' = o->>'port'
     where jsonb_typeof(o->'miles') = 'number' and (o->>'sailable')::boolean is false
       and (e->>'sailable')::boolean is true and cardinality(array(select jsonb_array_elements_text(e->'stops'))) > cardinality(array(select jsonb_array_elements_text(o->'stops')));
    if v_bug = 0 or v_rerouted = 0 then
      raise exception '0231 self-assert FAIL: positive control — the pre-image offered % unsailable passage(s); % now sail by more stops', v_bug, v_rerouted;
    end if;
    -- every row the pre-image offered unsailable is now sailable by stops, or shut with the stores' reason
    if exists (select 1 from jsonb_array_elements(v_old->'sell') o
                 join jsonb_array_elements(v_board->'sell') e on e->>'port' = o->>'port'
                where jsonb_typeof(o->'miles') = 'number' and (o->>'sailable')::boolean is false
                  and not ((e->>'sailable')::boolean is true or e->'shut'->>'code' = 'E_ENDURANCE')) then
      raise exception '0231 self-assert FAIL: a row the pre-image offered unsailable is neither sailable nor shut by the stores';
    end if;
    r_c := format('loaded: the pre-image offered %s sell passage(s) she could not sail (a leg past her stores); now %s of them sail by more stops, the rest are shut with E_ENDURANCE; every routed row''s longest leg is within %s nm and sailable; good_board %s ms (pre-image %s ms; %s sell rows)',
                  v_bug, v_rerouted, round(v_cap), array_to_string(v_ms, ', '), array_to_string(v_ms_old, ', '), jsonb_array_length(v_board->'sell'));

    -- (d) A SHUT ROW SAYS WHY, in the server's figures: E_ENDURANCE, its leg past the cap and within her navigation,
    --     the days it asks above the days she can carry (= the board's carry_days)
    select count(*) into v_shut from jsonb_array_elements(v_board->'sell') e where e->'shut'->>'code' = 'E_ENDURANCE';
    if v_shut = 0 then
      raise exception '0231 self-assert FAIL: no sell row is shut by her stores with a cap of % nm', round(v_cap);
    end if;
    if exists (select 1 from jsonb_array_elements(v_board->'sell') e
                where jsonb_typeof(e->'shut') = 'object'
                  and (e->'shut'->>'code' <> 'E_ENDURANCE' or jsonb_typeof(e->'miles') = 'number'
                       or (e->'shut'->'figures'->>'nm')::numeric <= v_cap or (e->'shut'->'figures'->>'nm')::numeric > v_nav + 0.5
                       or (e->'shut'->'figures'->>'need_days')::numeric < (e->'shut'->'figures'->>'carry_days')::numeric
                       or (e->'shut'->'figures'->>'carry_days')::numeric <> (v_board->'supplies'->>'carry_days')::numeric))
       or exists (select 1 from jsonb_array_elements(v_board->'buy') e
                where jsonb_typeof(e->'shut') = 'object' and (e->'shut'->>'code' <> 'E_ENDURANCE' or jsonb_typeof(e->'miles') = 'number')) then
      raise exception '0231 self-assert FAIL: a shut row''s refusal is not E_ENDURANCE with a leg past the cap, within her navigation, asking more than she carries';
    end if;
    -- a row her NAVIGATION shuts is not blamed on her stores
    if exists (select 1 from jsonb_array_elements(v_board->'sell') e
                 join voyage.reach_passage(v_player, v_fleet, v_lis, null) r on r.code = e->>'port'
                where r.nm is null and jsonb_typeof(e->'shut') = 'object') then
      raise exception '0231 self-assert FAIL: a row no passage within her navigation reaches was blamed on her stores';
    end if;
    r_d := format('%s sell row(s) shut with E_ENDURANCE, e.g. %s', v_shut,
                  (select e->>'port' || ' ' || (e->'shut'->'figures')::text from jsonb_array_elements(v_board->'sell') e
                    where e->'shut'->>'code' = 'E_ENDURANCE' order by (e->'shut'->'figures'->>'nm')::numeric desc limit 1));

    -- (e) THE ONE JUDGE: a leg within the cap is open, one past it E_ENDURANCE, one past her navigation E_LEG_TOO_FAR;
    --     and the SAIL refuses a held course past the cap with the same code leg_refusal gives it
    if voyage.leg_refusal(v_fleet, null, v_cap * 0.95, null) is not null
       or voyage.leg_refusal(v_fleet, null, v_cap * 1.01 + 2, null)->>'code' is distinct from 'E_ENDURANCE'
       or voyage.leg_refusal(v_fleet, null, v_nav + 10, null)->>'code' is distinct from 'E_LEG_TOO_FAR' then
      raise exception '0231 self-assert FAIL: leg_refusal does not open a leg within the cap, refuse E_ENDURANCE past it and E_LEG_TOO_FAR past her navigation';
    end if;
    select c.to_port, p.code, c.course, c.nm into v_dest, v_dcode, v_course, v_cnm
      from public.npc_courses c join public.ports p on p.id = c.to_port
     where c.from_port = v_lis and c.nm > v_cap * 1.05 and c.nm < v_nav * 0.95
     order by c.nm, p.code limit 1;
    if v_dest is null then
      raise exception '0231 self-assert FAIL: public.npc_courses holds no course out of Lisbon between % and % nm', round(v_cap * 1.05), round(v_nav * 0.95);
    end if;
    v_ref := voyage.leg_refusal(v_fleet, v_dest, v_cnm, v_course);
    v_res := cmd.issue(v_fleet, 'SAIL TO ' || v_dcode, null, v_course);
    if coalesce((v_res->>'ok')::boolean, false) or v_res->>'error_code' <> 'E_ENDURANCE' or v_ref->>'code' <> 'E_ENDURANCE' then
      raise exception '0231 self-assert FAIL: SAIL LIS -> % (% nm) answered %, leg_refusal %; E_ENDURANCE from both expected', v_dcode, round(v_cnm), v_res, v_ref;
    end if;
    r_e := format('leg_refusal: %s nm open, %s nm E_ENDURANCE, %s nm E_LEG_TOO_FAR; SAIL LIS -> %s (%s nm) refused E_ENDURANCE, as leg_refusal said (%s)',
                  round(v_cap * 0.95), round(v_cap * 1.01 + 2), v_nav + 10, v_dcode, round(v_cnm), v_ref->>'sentence');

    -- (f) THE SEARCH'S COST: the capped search (with its minimax pass) beside the uncapped, same session
    for k in 1 .. 3 loop
      v_t := clock_timestamp();
      perform count(*) from voyage.reach_passage(v_player, v_fleet, v_lis, v_cap);
      v_ms_rp := v_ms_rp || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
      v_t := clock_timestamp();
      perform count(*) from voyage.reach_passage(v_player, v_fleet, v_lis, null);
      v_ms_rp := v_ms_rp || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    r_f := format('reach_passage capped / uncapped ms, in pairs: %s', array_to_string(v_ms_rp, ', '));

    raise exception 'ROLLBACK_0231';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0231' then
      raise;
    end if;
  end;
  if exists (select 1 from public.players where id = v_player) or exists (select 1 from public.ledger where player_id = v_player)
     or (select value from public.world_config where key = 'hazard_p_max') <> v_hazard then
    raise exception '0231 self-assert FAIL: the probe did not roll back whole';
  end if;
  raise notice '0231 probe (a): %', r_a;
  raise notice '0231 probe (b): %', r_b;
  raise notice '0231 probe (c): %', r_c;
  raise notice '0231 probe (d): %', r_d;
  raise notice '0231 probe (e): %', r_e;
  raise notice '0231 probe (f): %', r_f;
  raise notice '0231 self-assert ok: HER LEGS FIT HER SUPPLIES. public.supply_reach names the longest leg her stores cover beside her cargo; voyage.reach_passage keeps every leg within it (a null cap is the old search) and names the leg that shuts a city; world.good_board passes it, serves carry_days and a shut row''s reason from voyage.leg_refusal, the one leg judge. % s.',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0231)), 1);
end $$;
