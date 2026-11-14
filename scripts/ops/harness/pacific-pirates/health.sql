-- health.sql: READ-ONLY. THE GUARD (the owner, 2026-11-14: "make it so that this problem does not occur again"): NPC ships unable to sail for more than 3 hours. Every figure should read 0.
-- A pirate fleet is counted from the hour she was brought home (pirate_ships.wrecked_at); any other ship from the day her city was first told (npc_refit_waits.told_at).
-- On 2026-11-14, before 0414, it would have read: pirates 7 (five waiting on a refit their home could not pay), and no merchant, cargo ship or navy ship.
-- `pirates_waiting_on_a_purse` above 0 means every pirate purse is short: they wait at home, loudly (a REFIT_WAITING event a day), until money comes in. Nothing is minted for them.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pacific-pirates/health.sql
begin transaction read only;
select jsonb_build_object('at', now(),
  'pirates_stuck', (select count(*) from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
                     where f.status = 'UNABLE_TO_SAIL' and n.laid_up_at is null and coalesce(n.wrecked_at, n.fought_at, n.created_at) < now() - interval '3 hours'),
  'pirates_waiting_on_a_purse', (select count(*) from public.npc_refit_waits w join public.pirate_ships n on n.fleet_id = w.fleet_id),
  'others_waiting_over_3h', (select coalesce(jsonb_object_agg(x.kind, x.n), '{}'::jsonb) from (
       select public.fleet_kind(w.fleet_id) as kind, count(*) as n from public.npc_refit_waits w
        where not exists (select 1 from public.pirate_ships n where n.fleet_id = w.fleet_id) and w.told_at < now() - interval '3 hours' group by 1) x)
) as health;
commit;
