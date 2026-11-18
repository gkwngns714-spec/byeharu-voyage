-- 0455 PROD CHECK, BEFORE the deploy, read-only, one SELECT inside `begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/before-0455.sql
-- One row, one jsonb column `r`. It reads the catalog, a few knobs and small static tables (regions, ports, goods, sea_reaches by key):
-- no scan of a large table, no volatile function.
-- BEFORE, wanted: head 20260818000454; applied false; old_hunks: every count 1; new_hunks: every
--   count 0; constraints both true; goods 57; regions 25; lis_ply 760.2 (the far trip's passage: 950 s); harbours LIS and PLY true;
--   secret_ok true. If an old_hunks count is not 1, a migration deployed since this file was written re-cut that line: 0455 refuses.
-- Generated from the migration's own hunks (the same text, so the check cannot drift from the file).
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.level_grant(uuid,text,numeric,text)', E'  v_l0 := public.level_from_points(x.xp);\n  v_l1 := public.level_from_points(x.xp + v_amount);\n  if v_l1 > v_l0 then\n    v_per := case when public.wc(\'reputation_on\') = \'true\'::jsonb then coalesce(public.wc_int(\'rep_level_per_level\'), 0) else 0 end;\n    for v_l in v_l0 + 1 .. v_l1 loop\n      v_got := 0;\n      if v_per > 0 then\n        v_got := public.reputation_credit(p_player, \'level\', v_per * v_l, \'level:\' || a.skill || \':\' || v_l,\n'),
  (2, 'public.level_perk(uuid,text)', E'public.level_perk_at(p_perk, public.level_from_points(v_xp));'),
  (3, 'public.level_skills_card(uuid,jsonb)', E'                 public.level_line(z.points) || jsonb_build_object(\n                   \'code\', s.code, \'word\', s.word, \'kept\', s.kept,'),
  (4, 'public.level_skills_card(uuid,jsonb)', E' end as points) z))'),
  (5, 'world.snapshot()', E'        \'neighbour_radius_nm\', public.wc_num(\'neighbour_radius_nm\')),'),
  (6, 'public.client_rpc_entry_points()', E'      (\'world\',       \'stats_now\',             \'\'),\n')
), hn(ord, fn, new) as (values
  (1, 'public.level_grant(uuid,text,numeric,text)', E'  -- 0455: the level on the skill\'s own curve (public.level_of: a short skill\'s is public.level_from_points, as before); a long skill\n  -- pays its gift every gift_every levels, what the matching sea level pays (level 50 of a land skill pays what level 10 pays)\n  v_l0 := public.level_of(a.skill, x.xp);\n  v_l1 := public.level_of(a.skill, x.xp + v_amount);\n  if v_l1 > v_l0 then\n    v_per := case when public.wc(\'reputation_on\') = \'true\'::jsonb then coalesce(public.wc_int(\'rep_level_per_level\'), 0) else 0 end;\n    for v_l in v_l0 + 1 .. v_l1 loop\n      v_got := 0;\n      if v_per > 0 and v_l % (select s.gift_every from public.level_skills s where s.code = a.skill) = 0 then\n        v_got := public.reputation_credit(p_player, \'level\', v_per * (v_l / (select s.gift_every from public.level_skills s where s.code = a.skill)), \'level:\' || a.skill || \':\' || v_l,\n'),
  (2, 'public.level_perk(uuid,text)', E'public.level_perk_at(p_perk, public.level_of(v_skill, v_xp));   -- 0455: on the skill\'s own curve'),
  (3, 'public.level_skills_card(uuid,jsonb)', E'                 public.level_line_of(s.code, z.points) || jsonb_build_object(\n                   -- 0455: each skill\'s own line, top, side and gift (public.level_line_of, public.level_top); a long skill\'s own curve\n                   \'side\', s.side, \'top\', public.level_top(s.code), \'gift_every\', s.gift_every,\n                   \'curve\', case when s.curve = \'short\' then null else (select jsonb_agg(c.xp order by c.level) from public.level_curves c where c.curve = s.curve) end,\n                   \'code\', s.code, \'word\', s.word, \'kept\', s.kept,'),
  (4, 'public.level_skills_card(uuid,jsonb)', E' end as points) z\n                where s.side = \'sea\' or public.land_on()))   -- 0455: a land skill only while land_enabled'),
  (5, 'world.snapshot()', E'        \'neighbour_radius_nm\', public.wc_num(\'neighbour_radius_nm\'),\n        -- 0455: the land\'s switch, for the bar (the Land tab is shown only while it is true)\n        \'land_enabled\', public.land_on()),'),
  (6, 'public.client_rpc_entry_points()', E'      (\'world\',       \'stats_now\',             \'\'),\n      -- 0455: the Land tab: its read, and the four doors (send, collect, call home, buy a tool). Dark: {enabled: false}, E_NOT_IN_USE.\n      (\'world\',       \'land\',                  \'text\'),\n      (\'cmd\',         \'land_send\',             \'text\'),\n      (\'cmd\',         \'land_collect\',          \'\'),\n      (\'cmd\',         \'land_home\',             \'\'),\n      (\'cmd\',         \'land_tool\',             \'text\'),\n')
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regclass('public.land_parties') is not null or exists (select 1 from public.world_config c where c.key = 'land_enabled'),
  'old_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old))
                  from hk h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'new_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new))
                  from hn h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'constraints', jsonb_build_object(
      'level_skills_check', exists (select 1 from pg_constraint c where c.conrelid = 'public.level_skills'::regclass and c.conname = 'level_skills_check'),
      'level_perks_level_check', exists (select 1 from pg_constraint c where c.conrelid = 'public.level_perks'::regclass and c.conname = 'level_perks_level_check')),
  'goods', (select count(*) from public.goods g where g.code in ('coal', 'iron', 'clay', 'stone', 'sand', 'copper', 'salt', 'tin', 'lead', 'lime', 'gypsum', 'sulphur', 'alum', 'saltpetre', 'zinc-spelter', 'ochre', 'feldspar', 'quartz', 'silver', 'marble', 'antimony', 'cobalt', 'quicksilver', 'cinnabar', 'alum-shale', 'swedish-iron', 'osmund-iron', 'bar-iron', 'japan-copper', 'chilean-copper', 'tin-ingots', 'gold', 'gold-dust', 'amber', 'baltic-amber', 'lodestone', 'potosi-silver', 'zacatecas-silver', 'turquoise', 'carnelian', 'malachite', 'onyx', 'lapis-lazuli', 'opals', 'peridot', 'jade', 'nephrite', 'pounamu', 'emeralds', 'emerald-muzo', 'rubies', 'burma-rubies', 'ceylon-sapphires', 'diamonds', 'golconda-diamonds', 'platinum', 'andacollo-gold') and g.is_raw and coalesce(array_length(g.origin_regions, 1), 0) > 0),
  'regions', (select count(*) from public.regions),
  'lis_ply', (select (sr.reaches ->> 'PLY')::numeric from public.sea_reaches sr where sr.code = 'LIS'),
  'harbours', (select jsonb_object_agg(p.code, p.kind = 'HARBOUR') from public.ports p where p.code in ('LIS', 'PLY')),
  'land_word', exists (select 1 from public.stats_flow_words w where w.kind = 'LAND'),
  'mining', exists (select 1 from public.level_skills s where s.code = 'mining'),
  'secret_ok', (select length(c.value #>> '{}') >= 64 from public.world_config c where c.key = 'world_secret'),
  'level_skills', (select count(*) from public.level_skills)) as r;
commit;
