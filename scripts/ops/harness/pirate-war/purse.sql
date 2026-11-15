-- 0427 PROD READ (before): what the pirates' pay costs and what pays it. Read-only, one statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirate-war/purse.sql
-- Reads the knobs, public.pirate_spend_day (one row a day), the pirate cities' purses (a handful) and pirate_ships (~140).
begin transaction read only;
select jsonb_build_object(
  'upkeep_day', public.wc_num('navy_upkeep_day'), 'slice', round(public.wc_num('navy_upkeep_day') / 24),
  'hoard', public.pirate_hoard(), 'room_pct', public.wc_num('pirate_spend_day_pct'), 'room_now', public.pirate_spend_room(now()),
  'spent', (select jsonb_object_agg(d.day, d.spent) from (select * from public.pirate_spend_day order by day desc limit 4) d),
  'cities', (select jsonb_agg(jsonb_build_array(p.code, public.treasury_balance(p.id), public.city_surplus(p.id)) order by p.code)
               from public.port_allegiance a join public.ports p on p.id = a.port_id where a.nation_id = public.pirate_nation()),
  'capital', (select p.code from public.ports p where p.id = public.pirate_capital()),
  'ships', (select jsonb_build_object('n', count(*), 'roster_built', count(*) filter (where n.ord in (select r.ord from public.pirate_roster r)),
                                      'laid_unpaid', count(*) filter (where n.laid_up_at is not null and n.unpaid_since is not null),
                                      'laid_oldest', min(n.laid_up_at), 'unpaid_oldest', min(n.unpaid_since)) from public.pirate_ships n),
  'size', public.pirate_size(), 'roster', (select count(*) from public.pirate_roster)
) as r;
commit;
