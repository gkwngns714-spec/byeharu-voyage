-- 0381 PROD CHECK (BEFORE lighting pirates_joinable), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/before-light.sql
-- Wanted, or do not light:
--   snapshot_names_pirates true (0380 is live: 0381 refuses without it); knob false; joinable 10; update_rows 0;
--   capital 'POR', capital_held_by_pirates true, pirate_homes 4;
--   closed and purses as production runs them; capital_can_pay true (closed, Port Royal's purse must hold starting_ducats: it pays every founding under the skull
--     and every gift to a broke pirate company; if false a founding under the skull is refused, and 0381's own probe stops the file);
--   companies_of_pirates 0 (no human company sails for them yet: any other figure means the knob was lit before);
--   switches: regard_enabled as the lead means it (lit, it puts the Wary band's factor on her war factor), attack_enabled false, the rest for the record;
--   war_factor x wary_factor is what a crown port asks of her on its tax and dock fee; war_regard_base is where her regard with every crown starts.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select p.prosrc like '%0380: THE PIRATE POWER%' from pg_proc p where p.oid = 'world.snapshot()'::regprocedure) as snapshot_names_pirates,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob,
       (select count(*) from public.nations n where public.nation_joinable(n.id)) as joinable,
       (select n.capital_port_code from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital,
       (select public.port_nation(p.id) = g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital_held_by_pirates,
       (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_is_free(p.id)) as pirate_homes,
       public.economy_closed() as closed,
       public.city_treasury_on() as purses,
       (select public.treasury_balance(p.id) from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital_purse,
       (select public.treasury_balance(p.id) >= (select (c.value)::text::bigint from public.world_config c where c.key = 'starting_ducats') from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital_can_pay,
       (select count(*) from public.players pl where not pl.is_npc and public.pirate_power(pl.nation_id)) as companies_of_pirates,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c
         where c.key in ('regard_enabled', 'attack_enabled', 'pirates_bite', 'pirate_ports_free', 'navy_enabled', 'navy_hunt_per_day', 'starting_ducats', 'nation_change_cooldown_days')) as switches,
       (select (c.value ->> 'war')::numeric from public.world_config c where c.key = 'country_tax_factor') as war_factor,
       (select (b.value ->> 'factor')::numeric from public.world_config c cross join lateral jsonb_array_elements(c.value) b where c.key = 'regard_bands' and b.value ->> 'band' = 'wary') as wary_factor,
       (select (c.value ->> 'war')::numeric from public.world_config c where c.key = 'regard_stance_base') as war_regard_base,
       (select count(*) from public.world_news w where w.key = 'update:0381') as update_rows;
commit;
