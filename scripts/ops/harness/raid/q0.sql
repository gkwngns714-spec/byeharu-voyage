begin transaction read only;
select json_build_object(
 've', (select json_agg(column_name||':'||data_type order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='voyage_events'),
 'v', (select json_agg(column_name||':'||data_type order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='voyages'),
 'xebec', (select row_to_json(c) from public.ship_classes c where code='xebec'),
 'fk', (select json_agg(key||'='||value::text) from public.world_config where key like 'fight\_%' or key in ('combat_bite','armour_turns_pct')),
 'head', (select max(version) from supabase_migrations.schema_migrations));
rollback;
