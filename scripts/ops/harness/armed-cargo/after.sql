-- 0328 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/armed-cargo/after.sql
-- Every function read here is STABLE: public.cargo_armed_on, public.cargo_class, public.cargo_armed. No game function is called.
-- Wanted: armed_on false; class qpinnace; armed_keys as shipped; armed_hulls 0; crewed 0; upkeep_flows 0.
select public.cargo_armed_on() as armed_on,
       public.cargo_class() as class,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('convoy_armed_enabled', 'convoy_armed_class', 'convoy_upkeep_per_leg', 'convoy_store_days')) as armed_keys,
       (select count(*) from public.cargo_ships c where public.cargo_armed(c.fleet_id)) as armed_hulls,
       (select count(*) from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id where s.crew > 0) as crewed,
       (select count(*) from public.treasury_flows f where f.kind = 'CONVOY_UPKEEP') as upkeep_flows,
       (select count(*) from public.cargo_ships) as ships,
       (select max(version) from supabase_migrations.schema_migrations) as head;
