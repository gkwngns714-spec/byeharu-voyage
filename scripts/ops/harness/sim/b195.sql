begin transaction read only;
select json_build_object('head', (select max(version) from supabase_migrations.schema_migrations),
 'plan', replace(pg_get_functiondef('public.npc_plan(timestamp with time zone,uuid)'::regprocedure), E'\r', ''),
 'cand', replace(pg_get_functiondef('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)'::regprocedure), E'\r', ''),
 'legl', replace(pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure), E'\r', '')) j;
rollback;
