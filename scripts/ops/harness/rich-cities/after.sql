-- 0324 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/rich-cities/after.sql
-- Every function read here is STABLE: public.rich_cities_on, public.cargo_origins, public.realm_capital, public.cargo_circuit_of. No game function is called.
-- Wanted: rich_on false; rich_keys as shipped; off_capital 0; away_from_capital 0; based 0; no_circuit 0; call_flows above 0 (the call still runs off) only after a :37 run with a short realm.
select public.rich_cities_on() as rich_on,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('convoy_rich_enabled', 'convoy_rich_ports', 'convoy_rebase_idle_days')) as rich_keys,
       (select count(*) from public.great_powers g where public.cargo_origins(g.nation_id) is distinct from array[public.realm_capital(g.nation_id)]) as off_capital,
       (select count(*) from public.cargo_ships c where c.home_port_id <> public.realm_capital(c.nation_id)) as away_from_capital,
       (select count(*) from public.cargo_ships c where c.based_at is not null) as based,
       (select count(*) from public.cargo_ships c where public.cargo_circuit_of(c.nation_id, c.home_port_id) is null) as no_circuit,
       (select count(*) from public.treasury_flows f where f.kind = 'CROWN_CALL') as call_flows,
       (select count(*) from public.cargo_ships) as ships,
       (select max(version) from supabase_migrations.schema_migrations) as head
