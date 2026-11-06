-- 0333 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/navy-comes/after.sql
-- Every function read here is STABLE (public.attack_on, public.navy_on). No game function is called.
-- Wanted: attack_on false; navy_on false; keys 4; how_other 0; ships 0; called 0; head 0333.
select public.attack_on() as attack_on,
       public.navy_on() as navy_on,
       (select count(*) from public.world_config c where c.key in ('navy_call_ships', 'navy_escorts', 'regard_attack_navy', 'attack_ship_minutes')) as keys,
       (select count(*) from public.battle_sides bs where bs.how <> 'OPENED') as how_other,
       (select count(*) from public.navy_ships) as ships,
       (select count(*) from public.navy_ships n where n.battle_id is not null or n.escort_of is not null) as called,
       (select max(version) from supabase_migrations.schema_migrations) as head;
