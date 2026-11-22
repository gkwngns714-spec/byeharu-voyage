-- EACH LEVEL OPENS SOMETHING (0468), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/level-unlocks/before-0468.sql
-- Expect: head 0467; switch null (absent); trading_steps 0; each of the five hunks' OLD text once (old 1) and its NEW text absent
-- (new 0) in the live body; fleet_room_levels [3, 6]; fleet_ship_top 7; yard_order_fee_pct 50; level_perks_on true.
-- Reads: the catalog (pg_get_functiondef of five functions: stable), world_config by key, level_perks (about 55 rows), and the human
-- companies' Trading marks (house_level_marks by key for about 19 rows). No game function is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('public.level_perk(uuid,text)',               'select k.skill into v_skill from public.level_perks k where k.perk = p_perk limit 1;', '0468: a step of a level counted from the record'),
  ('public.level_benefits(text,integer)',        'where k.skill = p_skill and public.wc(''level_perks_on'') = ''true''::jsonb', '0468: a step of a level counted from the record'),
  ('public.standing_route_max_for(uuid)',        'v_max := v_max + public.level_perk(p_player, ''route_room'')::int;', '0468: and the routes her Trading level opens'),
  ('public.fleet_room_caps(uuid)',               '+ greatest(public.skill_level(p_player, ''SEAMANSHIP''), public.skill_level(p_player, ''COMMAND''))', '0468: and the ships a fleet'),
  ('public.hull_order_price(uuid,uuid,text)',    'v_fee := round((v_lab + v_mat) * public.wc_num(''yard_order_fee_pct'') / 100.0)::bigint;', '0468: less the share her Trading level')
), d as (
  select h.fn, h.old, h.new, case when to_regprocedure(h.fn) is null then null else replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') end as def from h
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select value from public.world_config where key = 'level_unlocks_enabled'),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('fleet_room_levels', 'fleet_ship_top', 'fleet_ship_base', 'yard_order_fee_pct', 'level_perks_on', 'standing_route_max', 'reputation_on')),
  'trading_steps', (select count(*) from public.level_perks k where k.skill = 'trading'),
  'hunks', (select jsonb_agg(jsonb_build_object('fn', d.fn,
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new)) order by d.fn) from d),
  'trading_marks', (select jsonb_object_agg(x.level, x.n) from (
                      select m.level, count(*) as n from public.house_level_marks m join public.players p on p.id = m.player_id
                       where not p.is_npc and m.track = 'trading' group by 1) x));
rollback;
