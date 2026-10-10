-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0099 — THE SEA SHOWS WHO ELSE SAILS
--        docs/NPC_TRADERS.md §7, §11 "0099" (slice 3, the reads). The owner, 2026-10-08: "add npc
--        to and show movement on map to make this game feel more alive" and "by clicking the npc
--        ship, it will show how much it is earning per day or so" / "i will be able to click on
--        fleet, see ships, captains, skills etc." Two reads, both DARK until npc_traders_switch(true):
--          world.sea_traffic()        where every merchant fleet is now, in the voyage shape the
--                                     chart already draws (the shell's beat, while MAP/PORT is up)
--          world.npc_fleet_card(id)   everything a player may know about ONE merchant fleet (a tap)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS FILE SUPERSEDES — SLICED, NOT RETYPED (the 0096 method) ─────────────────────────
--   world.fleets()            its `'voyage', (select jsonb_build_object(…) from public.voyages v …)`
--                             sub-select MOVES, verbatim (cut from pg_get_functiondef here, not
--                             retyped), into world.voyage_view(voyage, full). world.fleets calls it
--                             with full = true; its output for a fleet at sea is asserted
--                             byte-identical before and after. sea_traffic calls it with full =
--                             false: the CURRENT SEGMENT only, no waters and no voyage id (a served
--                             voyage id would be a callable handle: voyage.position is executable by
--                             authenticated, 0088). ONE builder serves both shapes.
--   world.standing_routes()   its derived `'state'` case MOVES, verbatim, into
--                             public.standing_route_state(route, on), because the merchant card
--                             prints the same word for a merchant's route. Output asserted identical.
--   public.client_rpc_entry_points()  two rows after 0092's last.
--
-- ── THE PRIVACY RULE ───────────────────────────────────────────────────────────────────────────
-- Both reads join `players p … and p.is_npc` — THE one predicate (0096). A player's fleet is never
-- a row of sea_traffic, and the card answers E_NOT_FOUND for a player's fleet exactly as for a
-- uuid that names nothing (a player's fleet id reveals nothing, not even that it exists). The key
-- sets are the contract and are asserted exactly (the 0025 discipline): no queue, no orders, no
-- cargo basis, no version, no reserve, no provision figures, no ledger lines. A merchant's
-- FORTUNE is served: a company the world keeps has no privacy, and its rise and fall is what the
-- owner asked to watch.
--
-- ── IT DOES NOT SETTLE ─────────────────────────────────────────────────────────────────────────
-- The arrivals job settles merchants every minute; voyage.position is closed-form, so between ticks
-- a hull still moves correctly. A viewer-side settle would put every viewer's beat on the row locks
-- of every merchant (docs/NPC_TRADERS.md §7.2 has the numbers). Locally, where there is no pg_cron,
-- src/lib/rpc/localBackend.ts plays the job's part before this read.
--
-- Depends on: 0028/0088 (world.fleets), 0092-0094 (world.standing_routes), 0096-0098.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create temporary table hunks_0099 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));
create temporary table defs_before_0099 (fn text primary key, def text not null, acl text not null);
insert into defs_before_0099
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from unnest(array['world.fleets()', 'world.standing_routes()', 'public.client_rpc_entry_points()']) f(fn);

-- ── 1. THE MOVED REGIONS, read off the live bodies ─────────────────────────────────────────────
create temporary table moved_0099 (k text primary key, region text not null);
do $$
declare
  v_def   text := (select def from defs_before_0099 where fn = 'world.fleets()');
  v_head  text := '''voyage'', (select ';
  v_tail  text := E'\n                 from public.voyages v where v.fleet_id = f.id and v.status = ''SAILING''),';
  v_a     int;
  v_b     int;
  v_sr    text := (select def from defs_before_0099 where fn = 'world.standing_routes()');
  v_sa    text := E'''state'', ';
  v_sb    text := E',\n        ''paused_reason'', sr.paused_reason,';
begin
  -- world.fleets: the voyage object, `jsonb_build_object(… seg_nm …)` up to the FROM.
  if (length(v_def) - length(replace(v_def, v_head || 'jsonb_build_object(', ''))) / length(v_head || 'jsonb_build_object(') <> 1
     or (length(v_def) - length(replace(v_def, v_tail, ''))) / length(v_tail) <> 1 then
    raise exception '0099 slice: world.fleets'' voyage sub-select is not where this migration expects it';
  end if;
  v_a := strpos(v_def, v_head || 'jsonb_build_object(') + length(v_head);
  v_b := strpos(v_def, v_tail);
  insert into moved_0099 values ('voyage', substr(v_def, v_a, v_b - v_a));
  insert into hunks_0099 values ('world.fleets()', 1, v_head || substr(v_def, v_a, v_b - v_a) || v_tail,
    v_head || E'world.voyage_view(v.id, true)   -- 0099: the voyage object is world.voyage_view''s' || v_tail);

  -- world.standing_routes: the derived state word.
  if (length(v_sr) - length(replace(v_sr, v_sa || 'case when not v_on', ''))) / length(v_sa || 'case when not v_on') <> 1
     or (length(v_sr) - length(replace(v_sr, v_sb, ''))) / length(v_sb) <> 1 then
    raise exception '0099 slice: world.standing_routes'' state case is not where this migration expects it';
  end if;
  v_a := strpos(v_sr, v_sa || 'case when not v_on') + length(v_sa);
  v_b := strpos(v_sr, v_sb);
  insert into moved_0099 values ('state', substr(v_sr, v_a, v_b - v_a));
  insert into hunks_0099 values ('world.standing_routes()', 1, v_sa || substr(v_sr, v_a, v_b - v_a) || v_sb,
    v_sa || 'public.standing_route_state(sr.id, v_on)' || v_sb);   -- 0099: the derived word is public.standing_route_state's
end $$;

insert into hunks_0099 values
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'standing_route_pause',  'uuid, boolean')
    ) as t(s, f, a)$h$,
$h$      ('cmd',         'standing_route_pause',  'uuid, boolean'),
      -- 0099: the merchants at sea and in port, and one merchant fleet's card. Reads, no player id,
      -- dark until npc_traders_switch(true); neither answers for a player's fleet.
      ('world',       'sea_traffic',           ''),
      ('world',       'npc_fleet_card',        'uuid')
    ) as t(s, f, a)$h$);


-- ── 2. THE ONE VOYAGE BUILDER ──────────────────────────────────────────────────────────────────
do $$
begin
  execute format($f$
create or replace function world.voyage_view(p_voyage uuid, p_full boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $vv$
-- 0099: THE VOYAGE OBJECT, ONE BUILDER. The expression below was world.fleets' own sub-select
-- (0028, re-cut through 0088), moved verbatim. p_full = true is that object exactly (world.fleets,
-- world.npc_fleet_card). p_full = false is the CURRENT SEGMENT ONLY — course = [course[seg],
-- course[seg+1]], seg_index re-based to 0, no waters, and NO voyage id (a served id is a callable
-- handle) — which is exactly what the chart's drift needs to move a hull between reads, in about
-- 200 bytes instead of a whole polyline (world.sea_traffic).
declare
  v_full jsonb;
  v_seg  int;
begin
  select %s into v_full
    from public.voyages v where v.id = p_voyage;
  if v_full is null or coalesce(p_full, true) then
    return v_full;
  end if;
  v_seg := (v_full->'position'->>'seg_index')::int;
  return jsonb_build_object(
    'to', v_full->'to', 'dest_point', v_full->'dest_point',
    'course', case when v_seg is not null
                   then jsonb_build_array(v_full->'course'->v_seg, v_full->'course'->(v_seg + 1)) end,
    'eta', v_full->'eta', 'total_nm', v_full->'total_nm', 'nm_done', v_full->'nm_done',
    'waters', '[]'::jsonb, 'departed_at', v_full->'departed_at',
    'position', case when v_full->'position' is not null
                     then (v_full->'position') || jsonb_build_object('seg_index', 0) end);
end $vv$;
$f$, (select region from moved_0099 where k = 'voyage'));

  execute format($f$
create or replace function public.standing_route_state(p_route uuid, p_on boolean)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $st$
-- 0099: THE ROUTE'S DERIVED WORD (off / unassigned / paused / stopped / blocked / waiting /
-- sailing / in_port), moved verbatim out of world.standing_routes (0092, re-cut 0093) so the
-- merchant card prints the same word for a merchant's route. STATE IS DERIVED, never stored.
declare
  v_on boolean := p_on;
  sr   public.standing_routes%%rowtype;
  f    public.fleets%%rowtype;
  fo   public.orders%%rowtype;
begin
  select * into sr from public.standing_routes where id = p_route;
  select * into f from public.fleets where id = sr.fleet_id;
  select o.* into fo from public.orders o
   where o.fleet_id = sr.fleet_id and o.status = 'failed'
   order by o.seq limit 1;
  return %s;
end $st$;
$f$, (select region from moved_0099 where k = 'state'));
end $$;

-- ── 3. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0099(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0099 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0099 slice: hunk % of % occurs % time(s), expected exactly 1', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- The effect is read through the OLD bodies and the NEW ones inside ONE probe below, so the old
-- bodies are kept for it under pg_temp names first.
do $$
declare
  v_def text;
begin
  v_def := (select def from defs_before_0099 where fn = 'world.fleets()');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.fleets()', 'CREATE OR REPLACE FUNCTION pg_temp.fleets_before_0099()');
  execute v_def;
  v_def := (select def from defs_before_0099 where fn = 'world.standing_routes()');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.standing_routes()', 'CREATE OR REPLACE FUNCTION pg_temp.routes_before_0099()');
  execute v_def;
end $$;

select pg_temp.recut_0099(fn) from (select distinct fn from hunks_0099) x order by fn;

-- ── 4. THE TWO READS ───────────────────────────────────────────────────────────────────────────
create or replace function world.sea_traffic()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0099: WHERE EVERY MERCHANT FLEET IS RIGHT NOW (docs/NPC_TRADERS.md §7.2). At sea: the current
  -- segment of her voyage (world.voyage_view(…, false)), which is all the chart's drift needs. In
  -- port: the harbour and its SERVED roadstead point, where the chart draws her at anchor. The one
  -- predicate is players.is_npc; a player's fleet is never a row. Dark: {enabled:false, fleets:[]}.
  select case when not public.npc_traders_on()
    then jsonb_build_object('enabled', false, 'at', now(), 'fleets', '[]'::jsonb)
    else jsonb_build_object('enabled', true, 'at', now(), 'fleets', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', f.id, 'company', p.company_name, 'nation_code', n.code, 'ink', h.ink,
               'name', f.name, 'status', f.status,
               'ships', (select count(*) from public.ships s where s.fleet_id = f.id),
               'port', po.code,
               'roadstead', case when f.port_id is not null
                                 then jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) end,
               'anchor', case when f.lat is not null then jsonb_build_array(f.lat, f.lon) end,
               'voyage', (select world.voyage_view(v.id, false) from public.voyages v
                           where v.fleet_id = f.id and v.status = 'SAILING'),
               'next_lap_at', case when sr.hold_until > now() then sr.hold_until end)
             order by nf.roster_ord, f.id)
        from public.fleets f
        join public.players p on p.id = f.player_id and p.is_npc
        join public.npc_houses h on h.player_id = p.id
        left join public.npc_fleets nf on nf.fleet_id = f.id
        left join public.standing_routes sr on sr.id = nf.route_id
        left join public.nations n on n.id = p.nation_id
        left join public.ports po on po.id = f.port_id
        left join public.sea_reaches rs on rs.port_id = f.port_id), '[]'::jsonb)) end
$$;

create or replace function world.npc_fleet_card(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0099: EVERYTHING A PLAYER MAY KNOW ABOUT ONE MERCHANT FLEET (docs/NPC_TRADERS.md §7.3). Refuses
-- E_NOT_FOUND for a fleet whose company is not a merchant — in the same words as for a uuid that
-- names nothing — and while the switch is off. The key set is the contract (asserted exactly).
-- Ships are printed by the derivations a player's own fleet card uses (ship_hold_capacity,
-- voyage.ship_speed); fittings are served here because ship_fittings_read checks auth.uid().
declare
  f   public.fleets%rowtype;
  p   public.players%rowtype;
  h   public.npc_houses%rowtype;
  nf  public.npc_fleets%rowtype;
  sr  public.standing_routes%rowtype;
begin
  select x.* into f from public.fleets x
    join public.players pl on pl.id = x.player_id and pl.is_npc
   where x.id = p_fleet;
  if f.id is null or not public.npc_traders_on() then
    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  select * into p from public.players where id = f.player_id;
  select * into h from public.npc_houses where player_id = p.id;
  select * into nf from public.npc_fleets where fleet_id = f.id;
  select * into sr from public.standing_routes where id = nf.route_id;

  return jsonb_build_object(
    'company', jsonb_build_object(
      'name', p.company_name,
      'nation_code', (select code from public.nations where id = p.nation_id),
      'ink', h.ink, 'blurb', h.blurb, 'master', h.master,
      'fortune', p.ducats,
      'refounded', (select count(*) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),
      'refounded_at', (select max(e.created_at) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED')),
    'fleet', jsonb_build_object(
      'id', f.id, 'name', f.name, 'status', f.status,
      'port', (select code from public.ports where id = f.port_id),
      'roadstead', (select jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon)
                      from public.sea_reaches rs where rs.port_id = f.port_id),
      'anchor', case when f.lat is not null then jsonb_build_array(f.lat, f.lon) end,
      -- THE FULL COURSE, AND NOT THE VOYAGE'S ID. voyage_view(…, true) is the whole object world.fleets
      -- serves a player about her own fleet, and it carries the voyage `id` — a CALLABLE handle
      -- (voyage.position(uuid) is executable by authenticated, 0088:184), which this file's own header
      -- and §7.1 say the card must not serve. Stripped here, and the card's voyage key set is asserted
      -- exactly below so it cannot come back (the deep forbidden-key scan cannot ban 'id': fleet.id is
      -- served on purpose).
      'voyage', (select world.voyage_view(v.id, true) - 'id' from public.voyages v
                  where v.fleet_id = f.id and v.status = 'SAILING')),
    'route', case when sr.id is not null then jsonb_build_object(
      'name', sr.name,
      'stops', (select coalesce(jsonb_agg(po.code order by s.ord), '[]'::jsonb)
                  from public.standing_route_stops s join public.ports po on po.id = s.port_id
                 where s.route_id = sr.id),
      -- HER WHOLE LOOP, LEG BY LEG (owner row 112, 2026-10-10: "show routes for the ships of npcs
      -- as well"). Every leg is the BAKED course the route sails — the same verified water path
      -- cmd.do_sail hands to voyage.depart, authored once by 0098 and never re-derived — so the
      -- chart draws the water she actually follows rather than a straight line between two dots.
      -- Served on the CARD, which is read at tap time, and never on world.sea_traffic, which is
      -- read on every beat by every player with the map open: a loop is a polyline of hundreds of
      -- points and that is the difference between a 12 KB read and a 2 MB one.
      'legs', (select coalesce(jsonb_agg(jsonb_build_object(
                        'from', pf.code,
                        'to', pt.code,
                        'course', s.course) order by s.ord), '[]'::jsonb)
                 from public.standing_route_stops s
                 join public.ports pf on pf.id = s.port_id
                 join public.standing_route_stops s2
                   on s2.route_id = s.route_id
                  and s2.ord = (s.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = sr.id)
                 join public.ports pt on pt.id = s2.port_id
                where s.route_id = sr.id and s.course is not null),
      'lap_no', sr.lap_no,
      'state', public.standing_route_state(sr.id, public.standing_routes_on()),
      'next_lap_at', case when sr.hold_until > now() then sr.hold_until end,
      'paused_reason', sr.paused_reason,
      'last_skipped', coalesce((select x.skipped from public.standing_route_laps x
                                 where x.route_id = sr.id and x.closed_at is not null
                                 order by x.lap_no desc limit 1), '[]'::jsonb)) end,
    'earnings', case when sr.id is not null then public.route_earnings(sr.id) end,
    'ships', (select coalesce(jsonb_agg(jsonb_build_object(
               'name', s.name, 'class', c.name, 'is_flagship', s.is_flagship,
               'durability', s.durability, 'max_durability', c.durability,
               'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
               'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
               'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,
               'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
               'fittings', (select coalesce(jsonb_agg(jsonb_build_object('name', ik.name, 'qty', sf.qty)
                                                      order by ik.slot, ik.name), '[]'::jsonb)
                              from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
                             where sf.ship_id = s.id))
               order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s join public.ship_classes c on c.id = s.class_id
               where s.fleet_id = f.id),
    'officers', (select coalesce(jsonb_agg(jsonb_build_object(
                   'name', o.name, 'specialty', o.specialty, 'bonus_pct', o.bonus_pct,
                   'nation', (select code from public.nations where id = o.nation_id),
                   'home_port', (select code from public.ports where id = o.home_port_id))
                   order by o.specialty, o.name), '[]'::jsonb)
                   from public.player_officers po join public.officers o on o.id = po.officer_id
                  where po.player_id = p.id and po.fleet_id = f.id),
    'skills', (select coalesce(jsonb_agg(jsonb_build_object(
                 'code', sk.code, 'name', sk.name, 'level', coalesce(ps.level, 0),
                 'max', public.wc_int('skill_max_level')) order by sk.code), '[]'::jsonb)
                 from public.skills sk
                 left join public.player_skills ps on ps.skill_id = sk.id and ps.player_id = p.id));
end $$;

-- ── 5. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function world.voyage_view(uuid, boolean)        from public, anon, authenticated;
revoke all on function public.standing_route_state(uuid, boolean) from public, anon, authenticated;
revoke all on function world.sea_traffic()                     from public, anon;
revoke all on function world.npc_fleet_card(uuid)              from public, anon;
grant execute on function world.sea_traffic()                  to authenticated;
grant execute on function world.npc_fleet_card(uuid)           to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.keys_0099(p jsonb)
returns text[]
language plpgsql
as $$
-- every object key anywhere in the tree
declare
  v_out text[] := '{}';
  v_k   text;
  v_v   jsonb;
begin
  if jsonb_typeof(p) = 'object' then
    for v_k, v_v in select key, value from jsonb_each(p) loop
      v_out := v_out || v_k || pg_temp.keys_0099(v_v);
    end loop;
  elsif jsonb_typeof(p) = 'array' then
    for v_v in select value from jsonb_array_elements(p) loop
      v_out := v_out || pg_temp.keys_0099(v_v);
    end loop;
  end if;
  return v_out;
end $$;

create or replace function pg_temp.okeys_0099(p jsonb)
returns text[]
language sql
immutable
as $$
  -- one object's own keys, in byte order (collation-proof)
  select coalesce(array_agg(k order by k collate "C"), '{}') from jsonb_object_keys(p) k
$$;

do $$
declare
  c_auth    constant uuid := '00000000-0099-4000-8000-0000000000e1';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_player  uuid;
  v_fleet   uuid;
  v_leg     jsonb;
  v_route   uuid;
  v_res     jsonb;
  v_before  jsonb;
  v_after   jsonb;
  v_r_bef   jsonb;
  v_r_aft   jsonb;
  v_tr      jsonb;
  v_row     jsonb;
  v_card    jsonb;
  v_mfleet  uuid;
  v_full    jsonb;
  v_slim    jsonb;
  v_vid     uuid;
  v_keys    text[];
  v_bad     text[];
  v_err     text;
  v_rows    int;
  v_at_sea  int;
  v_docked  int;
  v_ms      numeric;
  v_t0      timestamptz;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved.
  for v_fn in select distinct fn from hunks_0099 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0099 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0099 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0099 where fn = v_fn) or v_def = v_back then
      raise exception '0099 self-assert FAIL: % is not its pre-image plus only 0099''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0099 where fn = v_fn) then
      raise exception '0099 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  -- ...and each moved region lives, to the character, in its new home.
  if strpos(pg_get_functiondef('world.voyage_view(uuid, boolean)'::regprocedure), (select region from moved_0099 where k = 'voyage')) = 0
     or strpos(pg_get_functiondef('public.standing_route_state(uuid, boolean)'::regprocedure), (select region from moved_0099 where k = 'state')) = 0
     or length((select region from moved_0099 where k = 'voyage')) < 400
     or length((select region from moved_0099 where k = 'state')) < 200 then
    raise exception '0099 self-assert FAIL: a moved region is not verbatim in its new function';
  end if;

  -- (b) THE REGISTRY AND THE GRANTS.
  if not has_function_privilege('authenticated', 'world.sea_traffic()', 'execute')
     or not has_function_privilege('authenticated', 'world.npc_fleet_card(uuid)', 'execute')
     or has_function_privilege('anon', 'world.sea_traffic()', 'execute')
     or has_function_privilege('anon', 'world.npc_fleet_card(uuid)', 'execute')
     or has_function_privilege('authenticated', 'world.voyage_view(uuid, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.standing_route_state(uuid, boolean)', 'execute') then
    raise exception '0099 self-assert FAIL: the reads are not exactly authenticated-only, or a helper is reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.function_name in ('sea_traffic', 'npc_fleet_card') and e.fn is not null) <> 2
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0099 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (c) THE PROBES: a player's fleet at sea, merchants switched on; then rolled back.
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';

    -- DARK: both reads are empty or refuse, whatever exists.
    v_tr := world.sea_traffic();
    if (v_tr->>'enabled')::boolean or jsonb_array_length(v_tr->'fleets') <> 0 then
      raise exception '0099 self-assert FAIL: sea_traffic served merchants while dark: %', left(v_tr::text, 300);
    end if;
    select nf.fleet_id into v_mfleet from public.npc_fleets nf order by nf.roster_ord limit 1;
    if v_mfleet is null then
      raise exception '0099 self-assert FAIL: no merchant fleet exists to read (0098 founds them)';
    end if;
    begin
      perform world.npc_fleet_card(v_mfleet);
      raise exception '0099 self-assert FAIL: the card answered while dark';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
    end;

    -- A PLAYER at sea, Lisbon to Funchal, with one route on and one off.
    perform cmd.assume_identity(c_auth);
    v_res := cmd.found_house('Casa da Leitura', 'PRT');
    v_player := (v_res->>'player_id')::uuid;
    select id into v_fleet from public.fleets where player_id = v_player;
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
    perform cmd.provision_preset_apply(v_fleet, ((cmd.provision_preset_save(null, 'Leitura', 9))->>'id')::uuid);
    v_route := ((cmd.standing_route_save(null, 'Leitura', jsonb_build_array(
                  jsonb_build_object('port', 'LIS', 'course', v_leg),
                  jsonb_build_object('port', 'FNC', 'course', jsonb_build_array(v_leg->1, v_leg->0))), 0, 20))->>'id')::uuid;
    perform cmd.standing_route_save(null, 'Por assignar', jsonb_build_array(
                  jsonb_build_object('port', 'LIS', 'course', v_leg),
                  jsonb_build_object('port', 'FNC', 'course', jsonb_build_array(v_leg->1, v_leg->0))), 0, 20);
    perform cmd.standing_route_assign(v_route, v_fleet);
    if (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0099 self-assert FAIL: the probe player did not put to sea';
    end if;

    -- (c1) world.fleets and world.standing_routes answer exactly as before the re-cut.
    v_before := pg_temp.fleets_before_0099();
    v_after  := world.fleets();
    if v_after is distinct from v_before or v_after->0->'voyage'->'position' is null then
      raise exception '0099 self-assert FAIL: world.fleets changed: before % after %', left(v_before::text, 400), left(v_after::text, 400);
    end if;
    v_r_bef := pg_temp.routes_before_0099();
    v_r_aft := world.standing_routes();
    if v_r_aft is distinct from v_r_bef
       or (select count(distinct x->>'state') from jsonb_array_elements(v_r_aft->'routes') x) < 2 then
      raise exception '0099 self-assert FAIL: world.standing_routes changed, or the probe did not reach two states: % / %',
        left(v_r_bef::text, 300), left(v_r_aft::text, 300);
    end if;

    -- (c2) the slim voyage: the current segment, re-based, and no id.
    select id into v_vid from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    v_full := world.voyage_view(v_vid, true);
    v_slim := world.voyage_view(v_vid, false);
    if v_slim ? 'id' or jsonb_array_length(v_slim->'course') <> 2
       or v_slim->'course'->0 is distinct from v_full->'course'->((v_full->'position'->>'seg_index')::int)
       or v_slim->'course'->1 is distinct from v_full->'course'->((v_full->'position'->>'seg_index')::int + 1)
       or (v_slim->'position'->>'seg_index')::int <> 0
       or v_slim->'position'->'lat' is distinct from v_full->'position'->'lat'
       or v_slim->'eta' is distinct from v_full->'eta'
       or jsonb_array_length(v_slim->'waters') <> 0
       or v_full->>'id' <> v_vid::text then
      raise exception '0099 self-assert FAIL: voyage_view(false) is not the current segment: % vs %', v_slim, left(v_full::text, 300);
    end if;

    -- (c3) THE SWITCH: merchants at sea and in port; the reads answer for merchants only.
    perform public.npc_traders_switch(true);
    v_tr := world.sea_traffic();
    v_rows := jsonb_array_length(v_tr->'fleets');
    select count(*) filter (where x->'voyage' is not null), count(*) filter (where x->>'status' = 'DOCKED' and x->'roadstead' is not null)
      into v_at_sea, v_docked from jsonb_array_elements(v_tr->'fleets') x;
    if not (v_tr->>'enabled')::boolean or v_rows <> (select count(*) from public.npc_fleets) or v_at_sea < 1 then
      raise exception '0099 self-assert FAIL: sea_traffic on served % row(s) (% at sea) for % merchant fleet(s)',
        v_rows, v_at_sea, (select count(*) from public.npc_fleets);
    end if;
    if exists (select 1 from jsonb_array_elements(v_tr->'fleets') x
                where not exists (select 1 from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
                                   where f.id = (x->>'id')::uuid))
       or exists (select 1 from jsonb_array_elements(v_tr->'fleets') x where (x->>'id')::uuid = v_fleet) then
      raise exception '0099 self-assert FAIL: sea_traffic served a fleet that is not a merchant''s';
    end if;
    -- the exact key sets
    select x into v_row from jsonb_array_elements(v_tr->'fleets') x where x->'voyage' is not null limit 1;
    v_keys := pg_temp.okeys_0099(v_tr);
    if v_keys <> array['at', 'enabled', 'fleets'] then
      raise exception '0099 self-assert FAIL: sea_traffic top-level keys %', v_keys;
    end if;
    v_keys := pg_temp.okeys_0099(v_row);
    if v_keys <> array['anchor', 'company', 'id', 'ink', 'name', 'nation_code', 'next_lap_at', 'port', 'roadstead',
                       'ships', 'status', 'voyage'] then
      raise exception '0099 self-assert FAIL: a traffic row''s keys are %', v_keys;
    end if;
    v_keys := pg_temp.okeys_0099(v_row->'voyage');
    if v_keys <> array['course', 'departed_at', 'dest_point', 'eta', 'nm_done', 'position', 'to', 'total_nm', 'waters'] then
      raise exception '0099 self-assert FAIL: a traffic voyage''s keys are %', v_keys;
    end if;
    v_bad := array(select k from unnest(pg_temp.keys_0099(v_tr)) k
                    where k in ('queue', 'orders', 'cargo', 'cargo_basis', 'version', 'reserve', 'ducats', 'fortune',
                                'ledger', 'provision', 'endurance_days', 'voyage_id'));
    if cardinality(v_bad) > 0 then
      raise exception '0099 self-assert FAIL: sea_traffic serves forbidden key(s) %', v_bad;
    end if;

    -- the card: a merchant's answers, with the contract's keys; a player's and a stranger's refuse
    select (x->>'id')::uuid into v_mfleet from jsonb_array_elements(v_tr->'fleets') x where x->'voyage' is not null limit 1;
    v_card := world.npc_fleet_card(v_mfleet);
    if pg_temp.okeys_0099(v_card)
         <> array['company', 'earnings', 'fleet', 'officers', 'route', 'ships', 'skills']
       or pg_temp.okeys_0099(v_card->'company')
         <> array['blurb', 'fortune', 'ink', 'master', 'name', 'nation_code', 'refounded', 'refounded_at']
       or pg_temp.okeys_0099(v_card->'fleet')
         <> array['anchor', 'id', 'name', 'port', 'roadstead', 'status', 'voyage']
       or pg_temp.okeys_0099(v_card->'route')
         <> array['lap_no', 'last_skipped', 'legs', 'name', 'next_lap_at', 'paused_reason', 'state', 'stops']
       -- HER LOOP IS WHOLE AND IT IS THE BAKED WATER: one leg per stop, each one's `from` the stop
       -- before and `to` the stop after it round the ring, each course a polyline of at least two
       -- points. A loop drawn from anything but these is a line over land.
       or jsonb_array_length(v_card->'route'->'legs') <> jsonb_array_length(v_card->'route'->'stops')
       or exists (select 1 from jsonb_array_elements(v_card->'route'->'legs') l
                   where jsonb_array_length(l->'course') < 2
                      or pg_temp.okeys_0099(l) <> array['course', 'from', 'to'])
       or (v_card->'route'->'legs'->0->>'from') <> (v_card->'route'->'stops'->>0)
       or pg_temp.okeys_0099(v_card->'earnings')
         <> array['day', 'day_full', 'day_laps', 'day_since', 'lap', 'lap_basis', 'laps_done', 'laps_recent']
       -- THE CARD'S VOYAGE, KEY FOR KEY: the full object MINUS the voyage id. Written out rather than
       -- left to the forbidden-key scan, which cannot ban 'id' (the fleet's own id is served).
       or pg_temp.okeys_0099(v_card->'fleet'->'voyage')
         <> array['course', 'departed_at', 'dest_point', 'eta', 'nm_done', 'position', 'to', 'total_nm', 'waters']
       or pg_temp.okeys_0099(v_card->'ships'->0)
         <> array['cargo', 'cargo_tuns', 'class', 'crew', 'crew_max', 'crew_required', 'durability', 'fittings',
                  'hold', 'hold_rated', 'is_flagship', 'max_durability', 'name', 'speed', 'speed_rated']
       or jsonb_array_length(v_card->'skills') <> (select count(*) from public.skills)
       or pg_temp.okeys_0099(v_card->'skills'->0) <> array['code', 'level', 'max', 'name']
       or v_card->'fleet'->'voyage'->'position' is null
       or v_card->'route'->>'state' <> 'sailing' then
      raise exception '0099 self-assert FAIL: the card''s contract: %', left(v_card::text, 600);
    end if;
    if exists (select 1 from jsonb_array_elements(v_card->'officers') o
                where pg_temp.okeys_0099(o) <> array['bonus_pct', 'home_port', 'name', 'nation', 'specialty']) then
      raise exception '0099 self-assert FAIL: an officer row''s keys';
    end if;
    v_bad := array(select k from unnest(pg_temp.keys_0099(v_card)) k
                    where k in ('queue', 'orders', 'cargo_basis', 'version', 'reserve', 'ducats', 'ledger',
                                'provision', 'water_t', 'food_t', 'endurance_days'));
    if cardinality(v_bad) > 0 then
      raise exception '0099 self-assert FAIL: the card serves forbidden key(s) %', v_bad;
    end if;
    foreach v_vid in array array[v_fleet, '00000000-0099-4000-8000-00000000dead'::uuid] loop
      begin
        perform world.npc_fleet_card(v_vid);
        raise exception '0099 self-assert FAIL: the card answered for % (not a merchant fleet)', v_vid;
      exception when sqlstate 'P0001' then
        if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
        v_err := coalesce(v_err, sqlerrm);
        if sqlerrm <> v_err then
          raise exception '0099 self-assert FAIL: a player''s fleet and a stranger uuid are refused differently';
        end if;
      end;
    end loop;

    -- (c4) the cost, timed (the slice-6 figure is measured on the soak; this is the chain's own)
    v_t0 := clock_timestamp();
    for v_n in 1 .. 20 loop
      v_tr := world.sea_traffic();
    end loop;
    v_ms := round((extract(epoch from clock_timestamp() - v_t0) * 1000 / 20)::numeric, 2);

    -- OFF again: empty, and the card refuses.
    perform public.npc_traders_switch(false);
    if jsonb_array_length(world.sea_traffic()->'fleets') <> 0 then
      raise exception '0099 self-assert FAIL: sea_traffic served merchants after the switch went off';
    end if;

    raise exception using errcode = 'P0990', message = '0099 probe rollback';
  exception when sqlstate 'P0990' then
    null;
  end;

  if public.npc_traders_on() or exists (select 1 from public.players where auth_uid = c_auth) then
    raise exception '0099 self-assert FAIL: the probe leaked, or the switch is on';
  end if;

  raise notice '0099 self-assert ok: THE SEA SHOWS WHO ELSE SAILS. world.fleets, world.standing_routes and client_rpc_entry_points reverse to their pre-images hunk by hunk, ACLs unmoved; the voyage object (% chars) lives verbatim in world.voyage_view and the route''s state word (% chars) in public.standing_route_state; world.fleets and world.standing_routes answered a probe player at sea byte-identically before and after; voyage_view(false) is the current segment re-based to 0 with no id and no waters; sea_traffic and npc_fleet_card are authenticated-only and registered, the helpers are server-only, no client write grant or unregistered writer. Dark: both empty or refusing. On: % merchant row(s) (% at sea, % docked at their roadsteads), none a player''s, the exact key sets, no forbidden key anywhere in either tree; the card refuses a player''s fleet and a stranger uuid in the same words. sea_traffic took % ms a call over 20 calls with the roster just put to sea. Rolled back; the switch ships OFF.',
    length((select region from moved_0099 where k = 'voyage')), length((select region from moved_0099 where k = 'state')),
    v_rows, v_at_sea, v_docked, v_ms;
end $$;
