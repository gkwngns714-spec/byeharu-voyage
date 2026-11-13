-- 0373 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-light-regard.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It sets regard_enabled back to false.
-- WHO IT TOUCHES: every company. Every factor on tax and dock fee is 1 at once; the Town Hall serves no regard line and no fine; the Levels page says "Not open yet." again;
-- public.regard_add writes nothing and cmd.pay_fine refuses E_NOT_IN_USE. Earned rows (public.house_regard) and FINE rows of the ledger stay; the rows count again if it is relit.
-- The one-line form (owner only) does the same: update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
-- Tested locally: 0373's own self-assert plays this write inside its probe, and this file was run on the local world after 0373 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'regard_enabled') is distinct from 'true'::jsonb then
    raise exception '0373 rollback refuses: regard_enabled is not true (0373 is not applied, or it was rolled back once)';
  end if;
  update public.world_config set value = 'false'::jsonb, updated_at = now(), description = description || ' Set back to false by the rollback of 0373.'
   where key = 'regard_enabled' and value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.regard_on() then
    raise exception '0373 rollback FAIL: % row(s) written, and the reader says %', v_n, public.regard_on();
  end if;
  raise notice '0373 rollback self-assert ok: regard_enabled is false again; every factor is 1, the hall serves no line and the fine door is shut. No row of any player was written.';
end
$r$;
