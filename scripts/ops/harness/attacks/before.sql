-- 0327, BEFORE: read-only, a pure SELECT of catalog and rows. It calls pg_get_functiondef and count only, no volatile game function. Run with: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/before.sql
-- Wanted: every hunk `times` 1; keys, words, column and rows of 0327 all 0; `attack_enabled` false; no battle of kind ATTACK. Re-run at the head before 0327: 0325 and 0326 may cut these bodies.
with bodies as (
  select n.name, replace(pg_get_functiondef(n.name::regprocedure), E'\r', '') as def
    from (values ('public.battle_open(text,uuid,uuid,timestamp with time zone)'), ('public.battle_resolve(uuid,timestamp with time zone)'),
                 ('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)'), ('world.cargo_ship_card(uuid)'), ('public.client_rpc_entry_points()')) n(name)
), hunks (name, old) as (values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', $h$  if p_kind is distinct from 'PROBE' then$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', $h$  v_rep   jsonb;
begin$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', $h$  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', $h$'outcome', v_f->>'outcome') || v_rep);$h$),
  ('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)', $h$  perform public.treasury_post(p_port,
    case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
    case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');$h$),
  ('world.cargo_ship_card(uuid)', $h$                from public.ships s where s.fleet_id = p_fleet));$h$),
  ('public.client_rpc_entry_points()', $h$      ('cmd',         'preview_tow',           'uuid'),$h$)
)
select 'hunk' as what, h.name, ((length(b.def) - length(replace(b.def, h.old, ''))) / length(h.old))::text as value from hunks h join bodies b on b.name = h.name
union all select 'head', max(version), null from supabase_migrations.schema_migrations
union all select 'keys already there (want 0)', count(*)::text, null from public.world_config c
 where c.key in ('loot_share', 'loot_per_ship', 'loot_per_company_day', 'attack_reach_nm', 'attack_cooldown_minutes', 'attack_crew_lost', 'attack_word_bands', 'regard_attack_cargo', 'regard_sink')
union all select 'LOOT word already there (want 0)', count(*)::text, null from public.stats_flow_words w where w.kind = 'LOOT'
union all select 'last_attacked_lap already there (want 0)', count(*)::text, null from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'cargo_ships' and c.column_name = 'last_attacked_lap'
union all select 'attack_enabled (want false)', c.value::text, null from public.world_config c where c.key = 'attack_enabled'
union all select 'battles of kind ATTACK (want 0)', count(*)::text, null from public.battles b where b.kind <> 'PROBE'
union all select 'book rows', count(*)::text, null from public.convoy_cargo
union all select 'cargo ships', count(*)::text, null from public.cargo_ships
order by 1, 2
