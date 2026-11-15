-- 0429 PROD CHECK, BEFORE the deploy: the same read as after-0429.sql under its own name (its header says what each side wants).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirate-war/after-0429.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads the nine pirate harbours' purses, pirate_ships (~95) and the pirates' cargo ships (0 before, 5 after) by key, the day's spend row, the
-- PIRATE_ALLOT flows of the last day through treasury_flows' created_at index, and the beat's ring. No big table is scanned.
-- BEFORE, wanted: applied false; cities each under 10 M; laid_up ~68 (unpaid); cargo.ships 0; allot_rows 0.
-- AFTER, wanted: applied true; every pirate city at >= 10,000,000 (allot_rows 16 = two a city); por >= 30 M (~870 M); within 5 minutes
--   laid_up 0 for the fleets the pirates keep (laid_wanted) and unpaid 0 at the next :47 pay; cargo.ships rising one a minute to 5, all home POR,
--   none raided by a pirate (cargo.raided_by_pirates 0); beat mean under 1,000 ms. A pirate city under 10 M again is topped up by the next load.
begin transaction read only;
with c as (
  select p.code, public.treasury_balance(p.id) as purse, p.id = public.pirate_capital() as cap
    from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
   where a.nation_id = public.pirate_nation()
), cg as (
  select x.fleet_id, x.home_port_id, f.status, (select b.aboard from public.cargo_ship_aboard(x.fleet_id) b) as aboard
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id where x.nation_id = public.pirate_nation()
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', exists (select 1 from public.world_config k where k.key = 'pirate_city_purse'),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key in ('pirate_hoard_floor', 'pirate_city_purse', 'pirate_capital_purse', 'pirate_cargo_ships', 'pirate_wakes_per_run', 'pirate_spend_day_pct')),
  'capital', (select p.code from public.ports p where p.id = public.pirate_capital()),
  'hoard', public.pirate_hoard(),
  'cities', (select jsonb_object_agg(c.code, c.purse) from c),
  'cities_under_10m', (select count(*) from c where not c.cap and c.purse < 10000000),
  'ships', (select jsonb_build_object('all', count(*), 'laid_up', count(*) filter (where n.laid_up_at is not null),
                                      'laid_wanted', count(*) filter (where n.laid_up_at is not null and public.pirate_ord_wanted(n.ord)),
                                      'unpaid', count(*) filter (where n.unpaid_since is not null)) from public.pirate_ships n),
  'cargo', (select jsonb_build_object('ships', count(*), 'sailing', count(*) filter (where cg.status = 'SAILING'),
                                      'home_por', count(*) filter (where cg.home_port_id = public.pirate_capital()), 'aboard', coalesce(sum(cg.aboard), 0),
                                      'raided_by_pirates', (select count(*) from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                                             where b.kind = 'RAID' and bs.side = 'DEFENDER' and bs.fleet_id in (select cg2.fleet_id from cg cg2))) from cg),
  'room', public.pirate_spend_room(now()),
  'spent_today', (select d.spent from public.pirate_spend_day d where d.day = (now() at time zone 'UTC')::date),
  'allot_rows', (select count(*) from public.treasury_flows f where f.kind = 'PIRATE_ALLOT' and f.created_at > now() - interval '1 day'),
  'beat', (select jsonb_build_object('mean_ms', round(avg(b.ms)), 'n', count(*)) from public.arrivals_beats b where b.at > now() - interval '5 minutes')
) as r;
commit;
