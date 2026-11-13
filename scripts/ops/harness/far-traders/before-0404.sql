-- 0404 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/far-traders/before-0404.sql
-- Wanted, one row: head 20260818000403; applied_already false; names_taken 0; classes_as_measured 6; gear_known 4; pirate_homes_among_the_15 0;
-- harbours_found 15; every volatility s or i (if one is v, do NOT run legs-0404.sql); fleets no more than npc_fleet_max. Read and write down: economy_closed and
-- purses_lit (both true means the five capitals pay), and each capital's purse and reserve (LIS pays about 330,000, AMS 290,000, SVQ, LON and MRS up to
-- 190,000 each, tuition included; a capital that is short calls its realm, public.capital_pays).
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       exists (select 1 from public.npc_loadouts where class_code = 'taforeia') as applied_already,
       (select count(*) from public.players pl where pl.company_name in ('Kamer Ambon', 'Kamer Banda', 'Kaapse Kamer', 'Casa do Cabo', 'Casa de Timor', 'Kamer Timor', 'Casa de Gale',
          'Kamer Galle', 'Casa de las Marianas', 'Derwent Company', 'Casa de Coulão', 'Comptoir du Malabar', 'Kamer Makassar', 'Casa de Macáçar', 'Casa de Goa Velha',
          'Carreira da Índia', 'Comptoir Port-Louis', 'Somers Isles Company', 'Comptoir des Bermudes', 'Port Jackson Company', 'Kamer Nieuw-Holland', 'Casa de Ternate',
          'Casa del Maluco', 'Casa de Tidore')) as names_taken,
       (select count(*) from public.ship_classes c join public.class_profile cp on cp.class_code = c.code
         where (c.code, cp.size, c.wave) in (('taforeia', 4, 51), ('retour', 4, 51), ('nao', 4, 51), ('hourque', 4, 51), ('indiaman', 5, 63), ('naucarr', 5, 63))) as classes_as_measured,
       (select count(*) from public.item_effects e where e.stat = 'wave' and e.delta = 3 and e.item_code in ('deal-planking', 'sheet-anchor'))
         + (select count(distinct l.item_code) from public.npc_loadouts l where l.item_code in ('suit-of-sails', 'crows-nest')) as gear_known,
       (select count(*) from public.ports p where p.kind = 'HARBOUR' and p.code in ('AMB','BND','CPT','DIL','GAL','HAG','HOB','KOL','MAK','OLD','PLO','STG','SYD','TER','TID')) as harbours_found,
       (select count(*) from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id join public.ports p on p.id = a.port_id
         where a.home and g.pirate and p.code in ('AMB','BND','CPT','DIL','GAL','HAG','HOB','KOL','MAK','OLD','PLO','STG','SYD','TER','TID')) as pirate_homes_among_the_15,
       (select string_agg(pr.proname || ' ' || pr.provolatile::text, ', ' order by pr.proname) from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
         where n.nspname = 'public' and pr.proname in ('npc_known_legs', 'npc_sea_shut', 'npc_course_zones', 'sea_refusal', 'sea_judge')) as volatility,
       (select count(*) from public.npc_fleets) as fleets,
       (select value from public.world_config where key = 'npc_fleet_max') as npc_fleet_max,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as purses_lit,
       (select string_agg(p.code || ' purse ' || t.ducats || ' reserve ' || t.reserve, '; ' order by p.code)
          from public.ports p join public.port_treasury t on t.port_id = p.id where p.code in ('LIS', 'AMS', 'SVQ', 'LON', 'MRS')) as capitals;
commit;
