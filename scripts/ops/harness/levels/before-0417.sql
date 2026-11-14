-- 0417 PROD CHECK, BEFORE the deploy, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/levels/before-0417.sql
-- One row, one jsonb column `r`. It reads the catalog, a few knobs, the last 30 minutes of two small run logs, and (after) a 35-row table: no scan of a large table.
-- BEFORE, wanted: head 20260818000416 (0411, the levels, and every file up to 0416 deployed); applied false; levels_there true; old_hunks: every count 1;
--   new_hunks: every count 0; volatility s or i. Write down beat[] and lap_starts[].
-- If an old_hunks count is not 1, a migration deployed since this file was written re-cut that line: 0417 will refuse to apply.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.stores_cost(uuid,numeric,numeric)', E'               * public.running_cost_mult(p_player)\n               * public.wc_num(''running_cost_level''))::bigint;   -- 0210: running costs keep pace with the goods\n'),
  (2, 'public.fleet_repair_cost(uuid,numeric,jsonb)', E'               * public.running_cost_mult(f.player_id)\n               * public.wc_num(''running_cost_level''))::bigint\n'),
  (3, 'public.wear_units_for(uuid,uuid)', E'  v_n      int;\nbegin\n'),
  (4, 'public.wear_units_for(uuid,uuid)', E'    from public.voyage_events ve where ve.voyage_id = p_voyage;\n'),
  (5, 'public.wear_units_for(uuid,uuid)', E'                   when ''MILES''   then v_nm / 1000 * public.wc_num(''gear_wear_per_1000nm'')\n                   when ''PIRATES'' then v_fights * public.wc_num(''gear_wear_per_fight'')\n                   when ''STORM''   then v_storms * public.wc_num(''gear_wear_per_storm'')\n'),
  (6, 'public.reputation_request(uuid,bigint,uuid,jsonb)', E'    least(greatest(floor(p_premium / v_per), public.wc_int(''rep_request_min'')), public.wc_int(''rep_request_max''))::int,\n'),
  (7, 'public.reputation_lap(uuid,uuid,bigint,text,integer)', E'  return public.reputation_credit(p_player, ''lap'', public.wc_int(''rep_lap''), ''lap:'' || p_lap,\n'),
  (8, 'public.standing_route_max_for(uuid)', E'  if p_player is null or not public.skills_bite_on() then\n    return v_max;\n  end if;\n'),
  (9, 'public.invest_for(uuid,uuid,text,integer)', E'  perform public.regard_gift(p_player, p_port, v_cost, ''SHARE'');   -- 0319: dark, nothing\n'),
  (10, 'public.level_benefits(text,integer)', E'       where p_skill in (''trading'', ''exploration'') and t.level between 2 and public.wc_int(''title_max'')\n    ) b\n')
), hn(ord, fn, new) as (values
  (1, 'public.stores_cost(uuid,numeric,numeric)', E'               * public.running_cost_mult(p_player)\n               * (1 - public.level_perk(p_player, ''supplies_price'') / 100)   -- 0417: her Supplies level (a merchant: 0)\n               * public.wc_num(''running_cost_level''))::bigint;   -- 0210: running costs keep pace with the goods\n'),
  (2, 'public.fleet_repair_cost(uuid,numeric,jsonb)', E'               * public.running_cost_mult(f.player_id)\n               * (1 - public.level_perk(f.player_id, ''repair_price'') / 100)   -- 0417: her Shipbuilding level, on the hull''s price (a merchant: 0)\n               * public.wc_num(''running_cost_level''))::bigint\n'),
  (3, 'public.wear_units_for(uuid,uuid)', E'  v_n      int;\n  v_storm_x numeric := 1;   -- 0417: what her Weather level leaves of a storm day''s wear\n  v_gear_x  numeric := 1;   -- 0417: what her Craft level leaves of the wear of miles and fights\nbegin\n'),
  (4, 'public.wear_units_for(uuid,uuid)', E'    from public.voyage_events ve where ve.voyage_id = p_voyage;\n  -- 0417: her company''s levels, read once a passage (public.level_perk). This function runs for a player''s fleet only.\n  select 1 - public.level_perk(f.player_id, ''storm_wear'') / 100, 1 - public.level_perk(f.player_id, ''gear_wear'') / 100\n    into v_storm_x, v_gear_x from public.fleets f where f.id = p_fleet;\n'),
  (5, 'public.wear_units_for(uuid,uuid)', E'                   when ''MILES''   then v_nm / 1000 * public.wc_num(''gear_wear_per_1000nm'') * v_gear_x\n                   when ''PIRATES'' then v_fights * public.wc_num(''gear_wear_per_fight'') * v_gear_x\n                   when ''STORM''   then v_storms * public.wc_num(''gear_wear_per_storm'') * v_storm_x\n'),
  (6, 'public.reputation_request(uuid,bigint,uuid,jsonb)', E'    -- 0417: and her Requests level''s share more (public.level_perk)\n    floor(least(greatest(floor(p_premium / v_per), public.wc_int(''rep_request_min'')), public.wc_int(''rep_request_max''))\n          * (1 + public.level_perk(p_player, ''request_reputation'') / 100))::int,\n'),
  (7, 'public.reputation_lap(uuid,uuid,bigint,text,integer)', E'  -- 0417: and her Routes level''s share more (public.level_perk)\n  return public.reputation_credit(p_player, ''lap'', floor(public.wc_int(''rep_lap'') * (1 + public.level_perk(p_player, ''lap_reputation'') / 100))::int, ''lap:'' || p_lap,\n'),
  (8, 'public.standing_route_max_for(uuid)', E'  if p_player is null then\n    return v_max;\n  end if;\n  v_max := v_max + public.level_perk(p_player, ''route_room'')::int;   -- 0417: and the routes her Routes level gives\n  if not public.skills_bite_on() then\n    return v_max;\n  end if;\n'),
  (9, 'public.invest_for(uuid,uuid,text,integer)', E'  -- 0417: her Investment level makes the stake count for more regard (public.level_perk; a merchant: 0, and public.regard_add turns her away)\n  perform public.regard_gift(p_player, p_port, round(v_cost * (1 + public.level_perk(p_player, ''share_regard'') / 100))::bigint, ''SHARE'');   -- 0319: dark, nothing\n'),
  (10, 'public.level_benefits(text,integer)', E'       where p_skill in (''trading'', ''exploration'') and t.level between 2 and public.wc_int(''title_max'')\n      union all\n      -- 0417: perk: a step of public.level_perks at this level: its amount, and `total`, what the benefit is worth from this level on\n      select k.level, 5, jsonb_build_object(''level'', k.level, ''kind'', ''perk'', ''perk'', k.perk, ''unit'', k.unit, ''word'', k.word, ''amount'', k.amount,\n               ''total'', (select sum(k2.amount) from public.level_perks k2 where k2.perk = k.perk and k2.level <= k.level))\n        from public.level_perks k\n       where k.skill = p_skill and public.wc(''level_perks_on'') = ''true''::jsonb\n    ) b\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.stores_cost(uuid,numeric,numeric)'), ('public.fleet_repair_cost(uuid,numeric,jsonb)'), ('public.wear_units_for(uuid,uuid)'), ('public.reputation_request(uuid,bigint,uuid,jsonb)'), ('public.reputation_lap(uuid,uuid,bigint,text,integer)'), ('public.standing_route_max_for(uuid)'), ('public.invest_for(uuid,uuid,text,integer)'), ('public.level_benefits(text,integer)')) f(fn) where to_regprocedure(f.fn) is not null
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config where key = 'level_perks_on'),
  'levels_there', to_regclass('public.level_xp') is not null,
  'old_hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'new_hunks', (select jsonb_object_agg(hn.ord, (length(b.def) - length(replace(b.def, hn.new, ''))) / length(hn.new)) from hn join body b on b.fn = hn.fn),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.def)) from body b),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('pg_catalog.pg_get_functiondef(oid)'::regprocedure, 'pg_catalog.md5(text)'::regprocedure)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('level_perks_on', 'level_skills_on', 'reputation_on', 'provision_water_price', 'provision_food_price', 'repair_rate_per_point',
                             'gear_wear_per_storm', 'gear_wear_per_1000nm', 'gear_wear_per_fight', 'gear_wear_bite', 'rep_request_per_point', 'rep_request_min',
                             'rep_request_max', 'rep_lap', 'standing_route_max', 'regard_per_100k', 'regard_enabled', 'running_cost_level', 'npc_cost_mult', 'skills_bite')),
  'beat', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', b.at) + floor(extract(minute from b.at) / 5) * interval '5 minutes', 'HH24:MI') as block, count(*) as beats,
                   round(avg(b.ms)) as ms_mean, round(percentile_cont(0.95) within group (order by b.ms)::numeric) as ms_p95,
                   count(*) filter (where b.ms > 1000) as over_1s, count(*) filter (where b.error is not null) as errors
              from public.arrivals_beats b where b.at >= now() - interval '30 minutes' group by 1) x),
  'lap_starts', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', l.at) + floor(extract(minute from l.at) / 10) * interval '10 minutes', 'HH24:MI') as block, count(*) as runs,
                   sum((l.receipt->>'started')::int) as started, sum((l.receipt->>'late')::int) as late,
                   round(sum((l.receipt->>'plan_ms')::numeric) / nullif(sum((l.receipt->>'started')::numeric + (l.receipt->>'settled')::numeric), 0)) as plan_ms_a_start
              from public.lap_start_runs l where l.at >= now() - interval '30 minutes' group by 1) x)
) as r;
commit;
