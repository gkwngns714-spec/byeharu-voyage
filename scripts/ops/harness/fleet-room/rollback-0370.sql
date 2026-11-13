-- 0370 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-light-fleet-room.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It sets fleet_room_bite back to false.
-- WHO IT TOUCHES: every company. The caps are the flat ones again at once (two fleets; ships in a fleet by Seamanship). Buy, Move and New fleet refuse E_NOT_IN_USE and the Fleets page
-- says "Not open yet". Gold already paid stays paid and its house_room rows stay (they count again if it is relit). A second fleet already formed stays a fleet; a company holding more
-- than the flat caps allow keeps what she has and is refused her next new ship or fleet. fleet_hard_max stays 6: nothing reads it while dark.
-- The one-line form (owner only) does the same: update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
-- Tested locally: 0370's own self-assert plays this write inside its probe, and this file was run on the local world after 0370 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select c.value from public.world_config c where c.key = 'fleet_room_bite') is distinct from 'true'::jsonb then
    raise exception '0370 rollback refuses: fleet_room_bite is not true (0370 is not applied, or it was rolled back once)';
  end if;
  update public.world_config set value = 'false'::jsonb, updated_at = now(), description = description || ' Set back to false by the rollback of 0370.'
   where key = 'fleet_room_bite' and value = 'true'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.fleet_room_on() then
    raise exception '0370 rollback FAIL: % row(s) written, and the reader says %', v_n, public.fleet_room_on();
  end if;
  raise notice '0370 rollback self-assert ok: fleet_room_bite is false again; the flat caps are back and the buying and moving doors are shut. No row of any player was written.';
end
$r$;
