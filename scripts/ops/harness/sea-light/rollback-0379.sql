-- ROLLBACK DRAFT for 0379 (the step that lights sea_conditions_bite_npc). NOT a migration and NOT a prod check.
-- THE ROLLBACK OF THE LIGHT IS THE SWITCH, at once (owner only):
--   update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc' returning key, value;
-- Every plan after it is the old planner's (proof 70 SM_OFF, proof 72 NL_BACK). A merchant already moved to another loop keeps it until the planner moves her
-- again; nothing is undone by hand. The news row update:0379 stays. This draft is the FORWARD removal of 0379's two functions, for the owner to turn into a new
-- migration if the step itself must go. It does not touch the switch. A real migration must not carry the guard line below.
-- LOCAL PGlite WORLD ONLY while it carries this guard (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  drop function public.sea_conditions_npc_light();
  drop function public.sea_conditions_npc_ready();
  raise notice 'rollback-0379 draft ok: the merchants'' step and its read are gone; sea_conditions_bite_npc is %', (select value from public.world_config where key = 'sea_conditions_bite_npc');
end
$r$;
