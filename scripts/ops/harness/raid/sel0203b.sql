begin transaction read only;
select json_build_object(
  'fight_resolve_present', to_regprocedure('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)') is not null,
  'entry_points', (select count(*) from public.client_rpc_entry_points()),
  'knobs', (select jsonb_object_agg(key, value) from public.world_config where key like 'fight\_%' or key in ('combat_bite', 'armour_turns_pct')),
  'nine', (select count(*) from public.world_config where key like 'fight\_%'),
  'bands_desc', (select description from public.world_config where key = 'fight_board_bands'),
  'write_grants', (select count(*) from public.client_write_grants()),
  'exec_writers', (select count(*) from public.client_executable_writers()),
  'caller_eval', (select count(*) from public.caller_evaluated_functions()),
  'client_exec_core', (select json_agg(rl) from unnest(array['anon', 'authenticated']) rl where has_function_privilege(rl, 'voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)', 'execute')),
  'untouched_present', (select json_agg(fn || '=' || (to_regprocedure(fn) is not null)::text) from unnest(array['voyage.fight(uuid, integer, uuid, numeric)', 'voyage.settle(uuid, timestamp with time zone)',
        'public.armour_soak(numeric, numeric)', 'public.armour_turns(uuid, numeric)', 'voyage.escort_score(uuid)', 'public.raid_crew_lost(uuid, numeric, numeric)',
        'public.fight_points(text)', 'voyage.report_line(integer, text, jsonb)']) fn),
  'readers', (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
         and p.prosrc like '%voyage.fight_resolve(%' and p.proname <> 'fight_resolve'),
  'probe_ids_unused', not exists (select 1 from public.ship_classes where code = 'xebec') is false);
rollback;
