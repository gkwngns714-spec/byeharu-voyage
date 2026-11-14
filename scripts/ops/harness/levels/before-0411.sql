-- 0411 PROD CHECK, BEFORE the deploy, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/levels/before-0411.sql
-- One row, one jsonb column `r`.
-- BEFORE, wanted: head = the migration before 0411 in the chain as deployed; applied false; old_hunks: every count 1 (each OLD text once in the live body:
--   prod's bodies are the pre-images); new_hunks: every count 0; volatility s or i.
-- Write down beat[] (the arrivals beat by 5-minute block: beats, mean ms, p95 ms, over 1 s, errors) and lap_starts[]: the after read is held to them.
-- If an old_hunks count is not 1, a migration deployed since this file was written re-cut that line: 0411 will refuse to apply. Rebase and re-cut.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'voyage.settle(uuid,timestamp with time zone)', E'      perform public.reputation_arrival(f.player_id, v.id);\n'),
  (2, 'cmd.do_build(uuid,jsonb)', E'  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object(''class'', c.code));\n'),
  (3, 'cmd.do_repair(uuid,jsonb)', E'  return jsonb_build_object(''points'', round(v_points, 1), ''cost'', v_cost, ''sim_hours'', round(v_hours, 1))\n'),
  (4, 'cmd.run_fulfil(uuid,uuid)', E'  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object(''port'', v_port.code, ''good'', g.code));\n'),
  (5, 'cmd.do_make(uuid,jsonb)', E'    ''fleet'', f.name, ''item'', k.name, ''qty'', v_qty, ''spent'', v_spent));\n'),
  (6, 'cmd.forge_good(uuid,uuid,integer)', E'      ''product'', v_product.name, ''qty'', v_qty, ''spent'', v_spent));\n'),
  (7, 'cmd.standing_route_close_lap(uuid,timestamp with time zone)', E'  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);\n'),
  (8, 'public.invest_for(uuid,uuid,text,integer)', E'  v_after := public.pay_city(p_player, p_port, ''SHARE'', v_cost, v_event);\n'),
  (9, 'world.levels()', E'    ''bite'', public.levels_bite_on(),\n')
), hn(ord, fn, new) as (values
  (1, 'voyage.settle(uuid,timestamp with time zone)', E'      perform public.reputation_arrival(f.player_id, v.id);\n      -- 0411: and her company''s levels raised by doing: days fed, storms and rough days come through (public.level_arrival)\n      perform public.level_arrival(f.player_id, v.id);\n'),
  (2, 'cmd.do_build(uuid,jsonb)', E'  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object(''class'', c.code));\n  perform public.level_grant(f.player_id, ''hull'', 1, ''hull:'' || v_ship);   -- 0411: Shipbuilding, once a ship\n'),
  (3, 'cmd.do_repair(uuid,jsonb)', E'  perform public.level_grant(f.player_id, ''repair'', v_cost);   -- 0411: Shipbuilding, by the coin the yard was paid (a merchant leaves after one players probe)\n  return jsonb_build_object(''points'', round(v_points, 1), ''cost'', v_cost, ''sim_hours'', round(v_hours, 1))\n'),
  (4, 'cmd.run_fulfil(uuid,uuid)', E'  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object(''port'', v_port.code, ''good'', g.code));\n  perform public.level_grant(f.player_id, ''request'', v_pay);   -- 0411: Requests, by the bonus this delivery was paid\n'),
  (5, 'cmd.do_make(uuid,jsonb)', E'    ''fleet'', f.name, ''item'', k.name, ''qty'', v_qty, ''spent'', v_spent));\n  perform public.level_grant(f.player_id, ''made'', v_qty);   -- 0411: Craft, by the fittings made\n'),
  (6, 'cmd.forge_good(uuid,uuid,integer)', E'      ''product'', v_product.name, ''qty'', v_qty, ''spent'', v_spent));\n    perform public.level_grant(v_player, ''forged'', v_qty);   -- 0411: Craft, by the goods forged\n'),
  (7, 'cmd.standing_route_close_lap(uuid,timestamp with time zone)', E'  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);\n  perform public.level_grant(sr.player_id, ''lap'', case when l.net > 0 then 1 else 0 end, ''lap:'' || l.id);   -- 0411: Routes, once a lap at a gain (no gain: 0 units, and the writer leaves before any read)\n'),
  (8, 'public.invest_for(uuid,uuid,text,integer)', E'  v_after := public.pay_city(p_player, p_port, ''SHARE'', v_cost, v_event);\n  perform public.level_grant(p_player, ''share'', v_cost);   -- 0411: Investment, by the coin paid for shares (a merchant leaves after one players probe)\n'),
  (9, 'world.levels()', E'    ''bite'', public.levels_bite_on(),\n    -- 0411: every level, raised by doing: points, the curve, activities, benefits, recent grants (public.level_skills_card, on the progress read above)\n    ''level_skills'', public.level_skills_card(v_id, v_pp),\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('voyage.settle(uuid,timestamp with time zone)'), ('cmd.do_build(uuid,jsonb)'), ('cmd.do_repair(uuid,jsonb)'), ('cmd.run_fulfil(uuid,uuid)'), ('cmd.do_make(uuid,jsonb)'), ('cmd.forge_good(uuid,uuid,integer)'), ('cmd.standing_route_close_lap(uuid,timestamp with time zone)'), ('public.invest_for(uuid,uuid,text,integer)'), ('world.levels()')) f(fn)
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config where key = 'level_skills_on'),
  'old_hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'new_hunks', (select jsonb_object_agg(hn.ord, (length(b.def) - length(replace(b.def, hn.new, ''))) / length(hn.new)) from hn join body b on b.fn = hn.fn),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.def)) from body b),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('pg_catalog.pg_get_functiondef(oid)'::regprocedure, 'pg_catalog.md5(text)'::regprocedure,
                                                  'public.real_day(timestamp with time zone)'::regprocedure)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('level_skills_on', 'reputation_on', 'rep_level_per_level', 'level_points_per_step', 'fame_ducats_per_point', 'fame_per_port',
                             'fame_nm_per_point', 'fame_per_mayor_day', 'xp_evaded_points', 'xp_driven_off_points', 'fleet_room_levels', 'title_max', 'levels_bite')),
  'humans', (select count(*) from public.players p where not p.is_npc),
  'beat', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', b.at) + floor(extract(minute from b.at) / 5) * interval '5 minutes', 'HH24:MI') as block, count(*) as beats,
                   round(avg(b.ms)) as ms_mean, round(percentile_cont(0.95) within group (order by b.ms)::numeric) as ms_p95,
                   count(*) filter (where b.ms > 1000) as over_1s, count(*) filter (where b.error is not null) as errors
              from public.arrivals_beats b where b.at >= now() - interval '30 minutes' group by 1) x),
  'lap_starts', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', l.at) + floor(extract(minute from l.at) / 10) * interval '10 minutes', 'HH24:MI') as block, count(*) as runs,
                   sum((l.receipt->>'started')::int) as started, sum((l.receipt->>'late')::int) as late
              from public.lap_start_runs l where l.at >= now() - interval '30 minutes' group by 1) x)
) as r;
commit;
