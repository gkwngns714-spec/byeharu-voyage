-- 0514 ROLLBACK of the light, at once (owner, or the lead on a red after-check): every passage is judged as before the light. The news row stays (it is history).
-- To use it on production (owner, or the lead): strip the guard line below. With no file: the same update, by hand.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
update public.world_config set value = 'false'::jsonb, updated_at = now() where key = 'sea_conditions_bite' returning key, value;
