-- 0369 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-light-ship-stores.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It sets ship_stores_separate back to false: the world before 0345 at once.
-- WHO IT TOUCHES: every company and merchant. Supplies share the cargo hold again. Nothing aboard is taken: a hold that then holds more than its space keeps it and cannot load more
-- until some is sold or eaten. The one-line form (owner only) does the same: update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
-- Tested locally: 0369's own self-assert plays this write inside its probe, and this file was run on the local world after 0369 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'ship_stores_separate') is distinct from 'true'::jsonb then
    raise exception '0369 rollback refuses: ship_stores_separate is not true (0369 is not applied, or it was rolled back once)';
  end if;
  update public.world_config set value = 'false'::jsonb, updated_at = now(), description = description || ' Set back to false by the rollback of 0369.'
   where key = 'ship_stores_separate' and value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.ship_stores_separate() then
    raise exception '0369 rollback FAIL: % row(s) written, and the reader says %', v_n, public.ship_stores_separate();
  end if;
  raise notice '0369 rollback self-assert ok: ship_stores_separate is false again; supplies share the cargo hold as before 0345. No row of any player was written.';
end
$r$;
