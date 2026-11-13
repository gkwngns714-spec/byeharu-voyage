-- 0372 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-light-npc-levels.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It sets npc_ship_level_enabled back to false and runs the one writer
-- of 0344 once, so every crown and pirate hull is level 1 at once (the job would do the same within ten minutes).
-- WHO IT TOUCHES: crown cargo ships, navy ships and pirate ships only: their ship_xp rows go. No row of any merchant or company is written.
-- The one-line form (owner only) leaves the rows to the job: update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';
-- Tested locally: 0372's own self-assert plays this inside its probe, and this file was run on the local world after 0372 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
  v_d int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'npc_ship_level_enabled') is distinct from 'true'::jsonb then
    raise exception '0372 rollback refuses: npc_ship_level_enabled is not true (0372 is not applied, or it was rolled back once)';
  end if;
  update public.world_config set value = 'false'::jsonb, updated_at = now(), description = description || ' Set back to false by the rollback of 0372.'
   where key = 'npc_ship_level_enabled' and value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0372 rollback FAIL: % row(s) written', v_n;
  end if;
  v_d := public.crown_hull_level_fix();
  raise notice '0372 rollback self-assert ok: npc_ship_level_enabled is false again and the writer took % level row(s) away: crown and pirate hulls are level 1. No row of any merchant or company was written.', v_d;
end
$r$;
