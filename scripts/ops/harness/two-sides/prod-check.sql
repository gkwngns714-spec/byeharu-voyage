-- prod-check.sql: READ-ONLY on prod, one pure SELECT: the bodies 0320 was cut against, the names it adds, the knobs it reads.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select jsonb_object_agg(f, md5(replace(pg_get_functiondef(f::regprocedure), E'\r', ''))) from unnest(array['voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', 'voyage.fight(uuid,integer,uuid,numeric)', 'voyage.escort_score(uuid)', 'public.armour_soak(numeric,numeric)', 'voyage.rng(uuid,integer,text)']) f) as bodies,
       (select count(*) from pg_proc p where p.proname in ('fight_sides', 'fight_volley', 'raider_hulls')) as new_names,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'fight%' or c.key in ('armour_turns_pct', 'combat_bite')) as knobs;
commit;
