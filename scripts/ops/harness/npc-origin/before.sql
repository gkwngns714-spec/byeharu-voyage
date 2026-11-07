-- 0322 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/npc-origin/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regclass, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` is 1; npc_keys, refit_word, ord_49, job are 0; npc_refit_waits and fleet_origin are null; head is 0321 (0320 until #516 lands).
begin transaction read only;
with h(fn, ord, old) as (values
  ('voyage.settle(uuid,timestamp with time zone)'::regprocedure, 1, $h$    v_resolved := v_resolved + 1;
  end loop;
$h$),
  ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)'::regprocedure, 1, $h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass tows her
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
  end if;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$        perform public.convoy_book('RETURNED', p_fleet, c.player_id, f.port_id, v_left, v_load);
      end if;
      update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
$h$),
  ('voyage.forced_home(uuid,integer,uuid)'::regprocedure, 1, $h$  e        record;
  s        record;
  v_lost   jsonb := '{}'::jsonb;
  v_qty    numeric;
  v_u      numeric;
$h$),
  ('voyage.forced_home(uuid,integer,uuid)'::regprocedure, 2, $h$  for e in select distinct k.key as code
             from public.ships s0 cross join lateral jsonb_each(s0.cargo) k
            where s0.fleet_id = p_fleet and (k.value)::text::numeric > 0
            order by 1 loop
    v_qty := public.fleet_cargo_qty(p_fleet, e.code);
    if v_qty > 0 then
      v_lost := v_lost || jsonb_build_object(e.code, public.fleet_unload(p_fleet, e.code, v_qty));
    end if;
  end loop;
$h$),
  ('public.tow_for(uuid,uuid)'::regprocedure, 1, $h$  select y.id, y.code, y.name, case when y.id = f.port_id then 0 else r.nm end
    into v_to, v_code, v_name, v_nm
    from public.ports y
    left join voyage.reach_from(f.port_id) r on r.port_id = y.id
   where y.kind = 'HARBOUR' and not y.is_ice_closed and public.port_has_shipyard(y.id)
     and (y.id = f.port_id or r.nm is not null)
   order by case when y.id = f.port_id then 0 else r.nm end, y.code
   limit 1;
$h$))
select (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'hunk', h.ord,
          'times', (length(d.t) - length(replace(d.t, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
          from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as t) d) as hunks,
       (select count(*) from public.world_config c where c.key in ('npc_refits_enabled', 'npc_refit_share', 'npc_refit_minutes', 'npc_refits_per_run', 'ransom_share')) as npc_keys,
       (select count(*) from public.stats_flow_words w where w.kind = 'REFIT') as refit_word,
       (select count(*) from public.stats_flow_words w where w.ord = 49) as ord_49,
       (select count(*) from cron.job j where j.jobname = 'byeharu-voyage:npc-refits' or j.schedule like '18 %') as job,
       to_regclass('public.npc_refit_waits')::text as npc_refit_waits,
       to_regprocedure('public.fleet_origin(uuid)')::text as fleet_origin,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
