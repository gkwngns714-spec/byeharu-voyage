-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights rounds_enabled)
-- 0535 - ROUNDS, BY SEA  (dark behind rounds_enabled, 0518; the client of rounds needs it: docs/design/rounds-2026-11-25.md, slide 5)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER: "COMBAT: choose a SEA", then see what a round costs. 0519 served the cost in the sea of the harbour she lies in alone.
--   world.rounds(fleet) gains `seas`: for a fleet of hers that lies in a harbour, each sea with the nearest harbour of it the world remembers a course to (her own sea: where
--     she lies): {sea, name, base, nm, pirates}. `base` is what cmd.set_fleet_job {work, base} takes. No strength and no odds are served.
--   world.round_quote(fleet, work, base, stop)   what a Send from that base would cost a round there, and the most rounds (public.round_terms, with `base` in its
--     stop: one hunk). Asked when she picks a sea or a work. The fights it plays are the Send's own (0521), never served.
--   THE LOG WHILE SHE IS OUT: a run's card (public.round_run_card, one hunk) lists the rounds that have passed whether or not they are booked yet (public.round_log_of:
--     the lines the settle will write, from the frozen terms), so the log moves while she works and no read writes.
-- A read; writes nothing. ROWS: none. -- budget: none. -- retention: none.
-- LOCKS: CREATE FUNCTION x3, CREATE OR REPLACE x4 by hunks. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a migration reversing the hunks.
-- VERSION: 0535 (stacked on 0524; 0531 is the land's, whose hunks are in other bodies or other lines).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_terms(uuid,text,jsonb)', 'world.rounds(uuid)', 'public.client_rpc_entry_points()', 'public.round_run_card(uuid)']::text[];
  c_new    constant text[] := array['public.round_seas_for(uuid)', 'public.round_log_of(uuid,integer)']::text[];
  c_doors  constant text[] := array['world.round_quote(uuid,text,text,jsonb)']::text[];
  c_knobs  constant text[] := array[]::text[];
  c_ua     constant uuid := '00000000-0535-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.round_quote(uuid,text,text,jsonb)') is not null then
    raise exception '0535 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.round_fights(uuid,uuid)') is null or to_regprocedure('public.artifacts_on()') is null then
    raise exception '0535 refuses: the rounds (0518 to 0524) are not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0535 (fn text primary key, def text) on commit drop;
  insert into pre_0535 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  execute $f$
create function public.round_seas_for(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0535: THE SEAS A FLEET MAY BE SENT TO WORK from where she lies: her own sea (base: here) and every other, by the nearest harbour of it the world remembers a
  -- course to. pirates: whether any sail it (the work's own refusal), never how many. A fleet not in a harbour: none.
  select coalesce(jsonb_agg(jsonb_build_object('sea', q.sea, 'name', q.name, 'base', q.code, 'nm', q.nm, 'pirates', coalesce(voyage.sea_danger(q.sea, now()), 0) > 0) order by q.nm, q.code), '[]'::jsonb)
    from (select distinct on (z.sea) z.sea, s.name, z.code, z.nm
            from (select h.sea_id as sea, h.code, 0::numeric as nm from public.fleets f join public.ports h on h.id = f.port_id and h.kind = 'HARBOUR' where f.id = p_fleet
                  union all
                  select h.sea_id, h.code, round(k.nm) from public.fleets f cross join lateral public.npc_known_legs(f.port_id) k join public.ports h on h.id = k.to_port and h.kind = 'HARBOUR' where f.id = p_fleet) z
            join public.seas s on s.id = z.sea
           order by z.sea, z.nm, z.code) q
$body$
  $f$;
  execute $f$
create function public.round_log_of(p_fleet uuid, p_rounds integer)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0535: the last 20 lines of a run with the rounds passed and not booked yet (the settle's own lines, from the frozen terms). Writes nothing.
  select coalesce(jsonb_agg(z.l order by z.o), '[]'::jsonb)
    from (select q.l, q.o from public.round_runs r cross join lateral (
            select e.l, e.o from jsonb_array_elements(r.log) with ordinality e(l, o)
            union all
            select jsonb_build_object('r', g, 'at', r.sent_at + make_interval(secs => (g * (r.terms->>'seconds')::numeric)::double precision),
                                      'crew', (floor((r.terms->>'crew')::numeric * g) - floor((r.terms->>'crew')::numeric * (g - 1)))::int)
                   || case when r.terms ? 'fight' then jsonb_build_object('crew', r.terms #> array['fight', 'c', (g - 1)::text], 'hull', r.terms #> array['fight', 'l', (g - 1)::text],
                                                                          'won', r.terms #> array['fight', 'w', (g - 1)::text]) else '{}'::jsonb end, 1000000 + g
              from generate_series(greatest(r.booked + 1, p_rounds - 19), least(p_rounds, (r.terms->>'most')::int)) g
             where r.state = 'out') q
           where r.fleet_id = p_fleet order by q.o desc limit 20) z
$body$
  $f$;
  execute $f$
create function world.round_quote(p_fleet uuid, p_work text, p_base text, p_stop jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0535: WHAT A ROUND OF A WORK WOULD COST a fleet of hers from a base, with a stop rule: {on, terms} (public.round_terms; its fights are never served). Dark {on:
-- false}; not hers, or no such work or harbour: terms null. Writes nothing.
begin
  if not public.rounds_on() then
    return jsonb_build_object('on', false);
  end if;
  if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = public.current_player_id())
     or not exists (select 1 from public.ports h where h.code = p_base and h.kind = 'HARBOUR') or jsonb_typeof(coalesce(p_stop, '{}'::jsonb)) <> 'object'
     or exists (select 1 from jsonb_each(coalesce(p_stop, '{}'::jsonb)) e where jsonb_typeof(e.value) not in ('number', 'null')) then
    return jsonb_build_object('on', true, 'terms', null);
  end if;
  return jsonb_build_object('on', true, 'terms', (select public.round_terms(p_fleet, w.code, coalesce(p_stop, '{}'::jsonb) - 'light' || jsonb_build_object('base', p_base)) - 'fights' - 'strength'
                                                    from public.round_works w where w.code = p_work and (w.lit_by is null or public.wc(w.lit_by) = 'true'::jsonb)));
end
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;
  create temp table hunks_0535 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0535 values
  ('public.round_terms(uuid,text,jsonb)', 1,
$h$    v_x := public.round_fights(p_fleet, (select h.sea_id from public.fleets f join public.ports h on h.id = f.port_id where f.id = p_fleet));
$h$,
$h$    -- 0535: in the sea of a named base (world.round_quote), else of the harbour she lies in
    v_x := public.round_fights(p_fleet, coalesce((select h.sea_id from public.ports h where h.code = p_stop->>'base' and h.kind = 'HARBOUR'),
                                                 (select h.sea_id from public.fleets f join public.ports h on h.id = f.port_id where f.id = p_fleet)));
$h$),
  ('public.round_run_card(uuid)', 1,
$h$'log', r.log)
$h$,
$h$'log', public.round_log_of(r.fleet_id, (p->>'rounds')::int))   -- 0535: with the rounds not booked yet
$h$),
  ('world.rounds(uuid)', 1,
$h$           'works', case when exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_me) then public.round_works_for(v_me, p_fleet) else '[]'::jsonb end);
$h$,
$h$           'works', case when exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_me) then public.round_works_for(v_me, p_fleet) else '[]'::jsonb end,
           'seas', case when exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_me) then public.round_seas_for(p_fleet) else '[]'::jsonb end);   -- 0535
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'rounds',                'uuid'),
$h$,
$h$      ('world',       'rounds',                'uuid'),
      -- 0535: what a round would cost from a base (dark {on: false}); never its fights
      ('world',       'round_quote',           'uuid, text, text, jsonb'),
$h$);

  for x in select distinct h.fn from hunks_0535 h loop
    v_pre := (select p.def from pre_0535 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0535 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0535 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0535 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0535 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0535 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0535 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0535 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0535 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0535 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;


  -- ── THE PROBE ──
  begin
    declare
      v_pl uuid; v_fl uuid; d jsonb; a jsonb; q0 jsonb; q1 jsonb; v_sea uuid; v_far jsonb; v_o jsonb; v_log jsonb; v_log2 jsonb;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0535', 'PRT');
      select f.id, h.sea_id into v_fl, v_sea from public.fleets f join public.ports h on h.id = f.port_id where f.player_id = v_pl;
      update public.ships s set class_id = (select k.id from public.ship_classes k where k.code = 'xebec') where s.fleet_id = v_fl;
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 60, water_t = 90, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_fl;
      perform cmd.assume_identity(c_ua);
      d := world.round_quote(v_fl, 'pirates', 'LIS', '{}');
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'combat_rounds_enabled');
      a := world.rounds(v_fl)->'seas';
      select e into v_far from jsonb_array_elements(a) e where (e->>'sea')::uuid <> v_sea order by (e->>'nm')::numeric limit 1;
      delete from public.sea_pressure where sea_id in (v_sea, (v_far->>'sea')::uuid);
      update public.seas set piracy_index = 0.05 where id = v_sea;
      update public.seas set piracy_index = 0.4 where id = (v_far->>'sea')::uuid;
      q0 := world.round_quote(v_fl, 'pirates', 'LIS', '{"days": 0}');
      q1 := world.round_quote(v_fl, 'pirates', v_far->>'base', '{"days": 0}');
      perform public.round_send_for(v_pl, v_fl, 'pirates', '{"days": 0, "hull": 10}', now() - interval '25 minutes');
      v_log := world.rounds(null) #> '{runs,0,log}';
      perform public.round_settle(v_fl, now());
      v_log2 := world.rounds(null) #> '{runs,0,log}';
      v_o := world.round_quote(gen_random_uuid(), 'pirates', 'LIS', '{}');
      raise exception using errcode = 'ZX534', message = jsonb_build_object('dark', d, 'seas', jsonb_array_length(a), 'first', a->0, 'q0', q0, 'q1', q1, 'other', v_o, 'lines', jsonb_array_length(v_log), 'same', v_log = v_log2, 'bad', world.round_quote(v_fl, 'pirates', 'LIS', '{"days": "x"}'))::text;
    end;
  exception when sqlstate 'ZX534' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce(v_l->'dark' = '{"on": false}'::jsonb and (v_l->>'seas')::int >= 2 and (v_l #>> '{first,nm}')::numeric = 0 and v_l #>> '{first,base}' is not null
       and (v_l #>> '{q1,terms,hull}')::numeric > (v_l #>> '{q0,terms,hull}')::numeric and not (v_l #> '{q1,terms}') ?| array['fights', 'fight', 'strength']
       and (v_l->>'lines')::int between 1 and 2 and (v_l->>'same')::boolean and v_l #> '{other,terms}' = 'null'::jsonb and v_l #> '{bad,terms}' = 'null'::jsonb, false) then
    raise exception '0535 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0535') or public.rounds_on() then
    raise exception '0535 self-assert FAIL: the probe left rows behind, or the switch is not as it was';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0535 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0535 self-assert ok: ROUNDS, BY SEA (dark). Four hunks once and reversing; no other function moved; two functions server only, one read for the signed-in company. Probe (rolled back): % seas from Lisbon; a round''s hull % here, % in another sea (%). % ms.',
    v_l->>'seas', v_l #>> '{q0,terms,hull}', v_l #>> '{q1,terms,hull}', v_l #>> '{q1,terms,kind}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0535;
  drop table pre_0535;
end $m$;
