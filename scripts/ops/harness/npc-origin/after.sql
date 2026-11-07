-- 0322 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/npc-origin/after.sql
-- Every function read here is STABLE: pg_get_functiondef, to_regprocedure, and public.fleet_origin, public.npc_refits_on, public.npc_refit_cost, public.city_surplus, public.fleet_kind.
-- Wanted: refits_on false, refit_rows 0, respawned 0, waits 0, job_active true, no_origin 0, no_refit_cost 0. wrecks and cannot_pay are for reading: what the switch would meet.
begin transaction read only;
select public.npc_refits_on() as refits_on,
       (select count(*) from public.treasury_flows f where f.kind = 'REFIT') as refit_rows,
       (select count(*) from public.events e where e.kind in ('RESPAWNED', 'REFIT_WAITING', 'REFITTED')) as respawned,
       (select count(*) from public.npc_refit_waits) as waits,
       (select j.active from cron.job j where j.jobname = 'byeharu-voyage:npc-refits') as job_active,
       (select count(*) from public.fleets f join public.players p on p.id = f.player_id where p.is_npc and public.fleet_origin(f.id) is null) as no_origin,
       (select count(*) from public.fleets f join public.players p on p.id = f.player_id where p.is_npc and public.npc_refit_cost(f.id) <= 0) as no_refit_cost,
       (select count(*) from public.fleets f where public.fleet_kind(f.id) <> 'COMPANY' and f.status <> 'SAILING'
           and exists (select 1 from public.ships s where s.fleet_id = f.id) and not exists (select 1 from public.ships s where s.fleet_id = f.id and s.durability > 0)) as wrecks,
       (select count(*) from public.fleets f join public.players p on p.id = f.player_id where p.is_npc and public.city_surplus(public.fleet_origin(f.id)) < public.npc_refit_cost(f.id)) as cannot_pay,
       (select count(*) from public.fleets f join public.players p on p.id = f.player_id where p.is_npc) as npc_fleets;
commit;
