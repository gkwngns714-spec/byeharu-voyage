-- 0335 AFTER DEPLOY, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/realm-pays/after.sql
-- Every function called here is STABLE. Wanted: head 0335; navy_on false; navy_rows 0; navy_flows 0; crown_call_cut true; realms: what each realm could lay at its capital this minute, for the dev-log's table.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'navy_on', (select c.value from public.world_config c where c.key = 'navy_enabled'),
  'navy_rows', (select count(*) from public.navy_ships),
  'navy_flows', (select count(*) from public.treasury_flows f where f.kind in ('BUILD_NAVY', 'NAVY_PAY')),
  'fns', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile) from pg_proc p
           where p.oid in ('public.crown_donors(uuid)'::regprocedure, 'public.capital_can_draw(uuid,bigint)'::regprocedure, 'public.capital_draw(uuid,bigint,boolean)'::regprocedure)),
  'crown_call_cut', position('public.crown_donors(k.cap)' in pg_get_functiondef('public.crown_call(jsonb)'::regprocedure)) > 0,
  'realms', (select jsonb_agg(jsonb_build_object('nation', n.code, 'surplus', public.city_surplus(c.cap), 'hull', public.capital_can_draw(c.cap, k.build_cost::bigint),
                     'rooms', (select sum(d.room) from public.crown_donors(c.cap) d)) order by n.code)
               from public.great_powers g join public.nations n on n.id = g.nation_id
              cross join lateral (select public.realm_capital(g.nation_id) as cap) c
              cross join (select s.build_cost from public.ship_classes s where s.code = (select x.value #>> '{}' from public.world_config x where x.key = 'navy_ship_class')) k)
) as checks;
commit;
