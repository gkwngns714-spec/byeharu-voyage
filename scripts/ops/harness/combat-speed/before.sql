-- COMBAT SPEED (0422): THE BEFORE CHECK. Read-only, ONE statement, static (no function called). Run after db-health/gate.sql is ok, just before
-- ~/bin/bv-deploy.sh, from the linked clone:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-speed/before.sql
-- WANTED: prod head 0421 (renumbered to 0422 by the lead: it deploys before the at-sea work, now 0423+);
-- no fleet_speed_by_kind knob yet; voyage.fleet_speed_at still 0367's body (no "0422"); the navy and pirate voyages at sea that the switch
-- will re-time (each kind's median departure knots, for the after check to compare with).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knob_absent', not exists (select 1 from public.world_config where key = 'fleet_speed_by_kind'),
  'speed_body_0367', (select p.prosrc not like '%0422%' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'voyage' and p.proname = 'fleet_speed_at'),
  'at_sea', (select jsonb_object_agg(k, jsonb_build_object('n', n, 'kn_median', kn)) from (
               select case when exists (select 1 from public.npc_fleets x where x.fleet_id = v.fleet_id) then 'MERCHANT'
                           when exists (select 1 from public.navy_ships x where x.fleet_id = v.fleet_id) then 'NAVY'
                           when exists (select 1 from public.pirate_ships x where x.fleet_id = v.fleet_id) then 'PIRATE' else 'OTHER' end as k,
                      count(*) as n,
                      round((percentile_cont(0.5) within group (order by (v.speed_profile ->> 0)::numeric))::numeric, 2) as kn
                 from public.voyages v where v.status = 'SAILING' group by 1) x)
) as before;
commit;
