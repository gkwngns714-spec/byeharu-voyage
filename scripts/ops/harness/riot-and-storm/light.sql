-- LIGHT (the lead, on the owner's word): update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'happenings_bite';
-- ROLLBACK: the same with 'false'. Voyages that left lit finish under the figures they left with.
-- To use it on production (the lead, on the owner's word): strip the guard line below.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'happenings_bite';
