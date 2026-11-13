-- ROLLBACK DRAFT for 0378 (the step that lights sea_conditions_bite). NOT a migration and NOT a prod check.
-- THE ROLLBACK OF THE LIGHT IS THE SWITCH, at once (owner only):
--   update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite' returning key, value;
-- Every passage is then judged as before the light (proof 71, SL_BACK). The news row update:0378 stays: it is history, and a later light does not post it twice.
-- This draft is the FORWARD removal of 0378's two functions, for the owner to turn into a new migration (the next free number) if the step itself must go.
-- It does not touch the switch. A real migration must not carry the guard line below.
-- LOCAL PGlite WORLD ONLY while it carries this guard (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  drop function public.sea_conditions_light();
  drop function public.sea_conditions_ready();
  raise notice 'rollback-0378 draft ok: the step and its read are gone; sea_conditions_bite is %', (select value from public.world_config where key = 'sea_conditions_bite');
end
$r$;
