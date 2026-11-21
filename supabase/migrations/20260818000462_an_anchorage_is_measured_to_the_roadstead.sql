-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0462 - AN ANCHORAGE IS MEASURED TO THE ROADSTEAD  (the way in from her anchor: the board and the SAIL read one place; 0459 "Not changed")
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE FAULT (reproduced on the local chain at 0461 by a scratch run of proof 162's anchorage block, before this file; docs/dev-log/2026-11-20-anchor-quote.md):
--   For a ship lying at an anchorage, Trade's board measured the first leg as the way in to the harbour's QUAY: world.board_origin chose "the
--   nearest harbour" by the great-circle miles to the port's own coordinate (ports.lat, ports.lon) and made those miles the lead (lead_nm), whose
--   days, stores, wages and arrival every Trade row then carried. The SAIL (cmd.do_sail, 0076) does not go to the quay: a course ends at the
--   harbour's ROADSTEAD, the one point of open water a harbour is reached from (public.sea_reaches). Proof 162's anchorage, 0.4 degrees west of
--   Lisbon's roadstead: the board said 42 nm in (0.12 d); the SAIL to Lisbon was 18.8 nm.
-- THE FIX (decided by default; one authority for where a leg ends): world.board_origin reads the same place the SAIL does, sea_reaches' roadstead of
--   each harbour: the nearest harbour is the one whose ROADSTEAD is nearest her anchor, and the lead is the great-circle miles to that roadstead.
--   Nothing else changes: every other reader (world.board_trips, board_sell, good_board, best_sales) already reads board_origin's lead_nm and lead_at.
--   One body, one hunk, once and reversing:
--   RE-CUT world.board_origin   the at-anchor select of the nearest harbour and its lead.
-- WHAT A PLAYER SEES CHANGE: from an anchorage, Trade's days, arrival, stores and wages for a trip count the way in to the roadstead, as the SAIL
--   will sail it (shorter than the way to the quay: in the proof 42 nm to 18.8). From a harbour, or under sail: nothing.
-- NOT CHANGED: the SAIL, the sailed-distance table, the roadsteads, any course. A client-drawn course may bend round land and then be longer than the
--   straight miles the board reads; that was so before. The longest leg's days and `supplies.days` / `fits` (public.supply_needs) are still at her speed now.
-- ROWS: none. No table, job, knob or cron. -- budget: none (no table, no job, no index). -- retention: none.
-- COST: board_origin's at-anchor select joins 254 harbours to their roadsteads (a join on the key) instead of reading 254 harbours; a read a player makes.
-- LOCKS: CREATE OR REPLACE x1 by hunk. No new function, so no new grant: the self-assert checks board_origin's grants, volatility, definer, search path
--   and owner are as they were. TIME: under 5 s. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a new migration reversing the hunk (its OLD text is below verbatim).
-- SELF-ASSERT: the hunk once and reversing; no other function moved; board_origin's grants etc. as before. THE PROBE (rolled back; it sails nothing
--   and rolls no dice): a probe house's barca (1) docked at Lisbon: board_origin's whole answer is the same before and after; (2) at anchor 0.4
--   degrees west of Lisbon's roadstead: before, the lead is the great-circle miles to the nearest harbour's quay; after, it is the miles to the
--   nearest roadstead, from the harbour that roadstead belongs to, whose passages are the passages the harbour has.
-- VERSION: 0462 = prod head 0461 + 1.
-- news: none (a repair: Trade quotes an anchorage's way in as the SAIL then sails it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_def       text;
  v_pre       text;
  v_old       text;
  v_new       text;
  v_n         int;
  v_d0        text;
  v_d1        text;
  v_a0        jsonb;
  v_a1        jsonb;
  x           record;
  c_recut     constant text[] := array['world.board_origin(uuid)'];
  c_auth      constant uuid := '00000000-0462-4000-8000-0000000000aa';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_recut || array['world.board_passages(uuid,uuid,uuid,numeric)', 'voyage.gc_distance_nm(double precision,double precision,double precision,double precision)',
                                                   'cmd.assume_identity(uuid)', 'public.form_fleet(uuid,text,uuid)']) f
              where to_regprocedure(f) is null) then
    raise exception '0462 refuses: the board (0348) or an authority it composes is not in this world';
  end if;
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id)) then
    raise exception '0462 refuses: a harbour has no roadstead (public.sea_reaches), the place a SAIL ends at';
  end if;

  -- ── 1. THE PRE-IMAGES, and what must not move ──
  create temp table pre_0462 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0462
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f));

  -- THE PROBE (one body, run before and after): a probe house's barca at Lisbon, docked and then at anchor west of its roadstead
  execute $f$
create function pg_temp.probe_0462(p_auth uuid)
returns table(docked text, anchored jsonb)
language plpgsql
as $body$
declare
  v_pl    uuid;
  v_fl    uuid;
  v_lis   uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_o     jsonb;
begin
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (p_auth, 'Probe 0462', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false) returning id into v_pl;
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_fl := public.form_fleet(v_pl, 'Probe 0462', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Probe 0462', true, true);
  -- the hull as her class is drawn (commission_ship rolls a new hull), whole
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1,
         crew = greatest(s.crew, c.crew_required), water_t = 0, food_t = 0, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  perform cmd.assume_identity(p_auth);
  -- DOCKED: the whole answer (it carries now(), fixed inside the transaction)
  docked := md5(world.board_origin(v_fl)::text);
  -- AT ANCHOR, west of Lisbon's roadstead, in open water
  select sr.roadstead_lat, sr.roadstead_lon - 0.4 into v_lat, v_lon from public.sea_reaches sr where sr.code = 'LIS';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = v_lat, lon = v_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = v_fl;
  v_o := world.board_origin(v_fl);
  anchored := jsonb_build_object(
    'lead_nm', (v_o->>'lead_nm')::numeric,
    'via', v_o->'where'->>'via',
    'kind', v_o->'where'->>'kind',
    'origin', (select p.code from public.ports p where p.id = (v_o->>'origin')::uuid),
    'passages', md5((v_o->'passages')::text),
    'quay_nm', (select min(voyage.gc_distance_nm(v_lat, v_lon, p.lat, p.lon)) from public.ports p where p.kind = 'HARBOUR'),
    'quay_port', (select p.code from public.ports p where p.kind = 'HARBOUR' order by voyage.gc_distance_nm(v_lat, v_lon, p.lat, p.lon), p.code limit 1),
    'road_nm', (select min(voyage.gc_distance_nm(v_lat, v_lon, sr.roadstead_lat, sr.roadstead_lon)) from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.kind = 'HARBOUR'),
    'road_port', (select p.code from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR'
                   order by voyage.gc_distance_nm(v_lat, v_lon, sr.roadstead_lat, sr.roadstead_lon), p.code limit 1));
  return next;
end
$body$
  $f$;
  begin
    select v.docked, v.anchored into v_d0, v_a0 from pg_temp.probe_0462(c_auth) v;
    raise exception sqlstate 'BV462' using message = 'before';
  exception when sqlstate 'BV462' then
    null;
  end;

  -- ── 2. THE HUNK (the one body, one hunk: each OLD text occurs once in the live body and the new body reverses to it) ──
  create temp table hunks_0462 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0462 values
  ($h$world.board_origin(uuid)$h$, 1,
$h$      select p.id, voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)
        into v_origin, v_lead_nm
        from public.ports p
       where p.kind = 'HARBOUR' and f.lat is not null and f.lon is not null
       order by voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon), p.code
       limit 1;
$h$,
$h$      -- 0462: the way in is measured to the harbour's ROADSTEAD (public.sea_reaches), the point cmd.do_sail ends a course at (0076), not to the
      -- port's own coordinate, the quay: the nearest harbour is the one whose roadstead is nearest, and the lead is the miles to that roadstead
      select p.id, voyage.gc_distance_nm(f.lat, f.lon, sr.roadstead_lat, sr.roadstead_lon)
        into v_origin, v_lead_nm
        from public.ports p
        join public.sea_reaches sr on sr.port_id = p.id
       where p.kind = 'HARBOUR' and f.lat is not null and f.lon is not null
       order by voyage.gc_distance_nm(f.lat, f.lon, sr.roadstead_lat, sr.roadstead_lon), p.code
       limit 1;
$h$);

  for x in select distinct h.fn from hunks_0462 h loop
    v_pre := (select p.def from pre_0462 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0462 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0462 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0462 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0462 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0462 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0462) <> 1 or (select count(distinct fn) from hunks_0462) <> cardinality(c_recut) then
    raise exception '0462 self-assert FAIL: the hunks are not the 1 of the 1 re-cut body';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog (no new function, so no grant to make; none may have moved) ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f))) <> v_fn_before then
    raise exception '0462 self-assert FAIL: another function moved';
  end if;
  for x in select p.fn, p.meta,
                  (select coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text
                     from pg_proc q where q.oid = p.fn::regprocedure) as now_meta
             from pre_0462 p loop
    if x.now_meta is distinct from x.meta then
      raise exception '0462 self-assert FAIL: the grants, volatility, definer, search path or owner of % is % and was %', x.fn, x.now_meta, x.meta;
    end if;
  end loop;

  -- ── 4. THE PROBE, AFTER (rolled back by a raised sentinel; it sails nothing and rolls no dice) ──
  begin
    select v.docked, v.anchored into v_d1, v_a1 from pg_temp.probe_0462(c_auth) v;
    raise exception sqlstate 'BV462' using message = 'after';
  exception when sqlstate 'BV462' then
    null;
  end;
  if v_d0 is null or v_d1 is distinct from v_d0 then
    raise exception '0462 self-assert FAIL: a docked board''s origin moved: before %, after %', v_d0, v_d1;
  end if;
  -- before: the old rule (the quay); after: the new (the roadstead), and the passages are those of the harbour it ran through
  if v_a0 is null or v_a0->>'kind' <> 'at_sea' or abs((v_a0->>'lead_nm')::numeric - (v_a0->>'quay_nm')::numeric) > 0.000001
     or v_a0->>'via' is distinct from v_a0->>'quay_port' then
    raise exception '0462 self-assert FAIL: before, the anchorage was not measured to the quay: %', v_a0;
  end if;
  if v_a1 is null or v_a1->>'kind' <> 'at_sea' or abs((v_a1->>'lead_nm')::numeric - (v_a1->>'road_nm')::numeric) > 0.000001
     or v_a1->>'via' is distinct from v_a1->>'road_port' or v_a1->>'origin' is distinct from v_a1->>'road_port'
     or (v_a1->>'lead_nm')::numeric > (v_a0->>'lead_nm')::numeric then
    raise exception '0462 self-assert FAIL: after, the anchorage is not measured to the nearest roadstead: before %, after %', v_a0, v_a1;
  end if;
  if v_a1->>'via' = v_a0->>'via' and v_a1->>'passages' is distinct from v_a0->>'passages' then
    raise exception '0462 self-assert FAIL: the passages from the same harbour moved: before %, after %', v_a0, v_a1;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Probe 0462') then
    raise exception '0462 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0462 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0462 self-assert ok: AN ANCHORAGE IS MEASURED TO THE ROADSTEAD. world.board_origin''s way in from her anchor reads sea_reaches'' roadstead, as cmd.do_sail does: 1 hunk once and reversing; a docked origin the same before and after; at anchor off Lisbon the lead was % nm (to the quay of %) and is % nm (to the roadstead of %); grants as before; % ms',
    round((v_a0->>'lead_nm')::numeric, 1), v_a0->>'quay_port', round((v_a1->>'lead_nm')::numeric, 1), v_a1->>'road_port',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop function pg_temp.probe_0462(uuid);
  drop table hunks_0462;
  drop table pre_0462;
end $m$;
