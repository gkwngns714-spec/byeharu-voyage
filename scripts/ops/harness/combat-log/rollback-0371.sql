-- 0371 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-light-raid-orders.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It sets raid_orders_enabled back to false.
-- WHO IT TOUCHES: every company. voyage.leg_order answers null, so every order frozen on a voyage under way is ignored at once and each raid is fought as Fight; the door refuses
-- E_NOT_IN_USE and the picker is not drawn. The rows of public.fleet_raid_orders and every fight log stay. A ransom already paid stays paid.
-- The one-line form (owner only) does the same: update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
-- Tested locally: 0371's own self-assert plays this write inside its probe, and this file was run on the local world after 0371 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'raid_orders_enabled') is distinct from 'true'::jsonb then
    raise exception '0371 rollback refuses: raid_orders_enabled is not true (0371 is not applied, or it was rolled back once)';
  end if;
  update public.world_config set value = 'false'::jsonb, updated_at = now(), description = description || ' Set back to false by the rollback of 0371.'
   where key = 'raid_orders_enabled' and value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.raid_orders_on() then
    raise exception '0371 rollback FAIL: % row(s) written, and the reader says %', v_n, public.raid_orders_on();
  end if;
  raise notice '0371 rollback self-assert ok: raid_orders_enabled is false again; every frozen order is ignored and the door is shut. No row of any player was written.';
end
$r$;
