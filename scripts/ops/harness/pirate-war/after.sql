-- 0427 PROD CHECK, BEFORE and AFTER the deploy (+30 min and +3 h), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirate-war/after.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads pirate_ships (~140) with their fleets by key, the sailing voyages once (~1,500, two trig sums a pirate), public.battles (0 before;
-- at most ~6,000 rows after, kept 48 hours) and the knobs. No big table is scanned.
-- BEFORE, wanted: applied false; battles.all_time 0; knobs pirate_add_minutes 5, pirate_respawn_minutes 60; pirates.hunting = the pirates
--   that may strike once 0427 is live; targets_near = merchants roughly within attack_reach_nm of each hunting pirate (the rate's ceiling).
-- AFTER, wanted: applied true; knobs pirate_add_minutes 1, pirate_respawn_minutes 5, pirate_strike_minutes 5, pirate_strikes_per_run 2;
--   within 10 minutes battles.raid_1h > 0 and battles.fighting > 0; by +30 min raid_1h between ~20 and 60 (at most 2 a minute); every
--   raid's defender a merchant (by_defender has no NAVY or PIRATE); pirates.wrecked lying under 10 minutes each (respawn 5);
--   beat.mean_ms under 1,000. A raid stuck FIGHTING past its resolves_at by more than 2 minutes (stuck) is a fault: 0.
begin transaction read only;
with k as (
  select jsonb_object_agg(c.key, c.value) as knobs from public.world_config c
   where c.key in ('pirate_add_minutes', 'pirate_respawn_minutes', 'pirate_strike_minutes', 'pirate_strikes_per_run', 'pirate_strike_tries_per_run',
                   'raid_keep_hours', 'attack_enabled', 'pirates_bite', 'attack_reach_nm', 'attack_ship_minutes', 'pirate_spend_day_pct')
), pr as (
  select n.fleet_id, n.sea_id, n.mission, n.haunt_port, n.laid_up_at, n.wrecked_at, n.unpaid_since, f.status, f.busy_until, f.port_id
    from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
), hunt as (
  select c.fleet_id, pt.lat::float8 as lat, pt.lon::float8 as lon
    from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id
    cross join lateral voyage.fleet_point(c.fleet_id, now()) pt
   where f.busy_until is null
), sv as (
  select v.fleet_id,
         a.lat + (b.lat - a.lat) * least(1, greatest(0, extract(epoch from now() - v.departed_at) / nullif(extract(epoch from v.eta - v.departed_at), 0))) as lat,
         a.lon + (b.lon - a.lon) * least(1, greatest(0, extract(epoch from now() - v.departed_at) / nullif(extract(epoch from v.eta - v.departed_at), 0))) as lon
    from public.voyages v
    join public.ports a on a.id = v.origin_port_id
    join public.ports b on b.id = v.dest_port_id
   where v.status = 'SAILING'
     and not exists (select 1 from public.pirate_ships x where x.fleet_id = v.fleet_id)
     and not exists (select 1 from public.navy_ships x where x.fleet_id = v.fleet_id)
), near as (
  select h.fleet_id, count(s.fleet_id) as n
    from hunt h left join sv s on voyage.gc_distance_nm(h.lat, h.lon, s.lat::float8, s.lon::float8) <= public.wc_num('attack_reach_nm') + 120
   group by h.fleet_id
), bt as (
  select b.kind, b.status, b.started_at, b.resolves_at, b.result ->> 'outcome' as outcome, (b.result #>> '{navy,came}')::int as came,
         (select public.fleet_kind(bs.fleet_id) from public.battle_sides bs where bs.battle_id = b.id and bs.side = 'DEFENDER' and bs.how = 'OPENED') as d_kind
    from public.battles b
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', exists (select 1 from public.world_config c where c.key = 'pirate_strike_minutes'),
  'knobs', (select k.knobs from k),
  'pirates', (select jsonb_build_object(
                'all', count(*), 'laid_up', count(*) filter (where pr.laid_up_at is not null),
                'unpaid', count(*) filter (where pr.unpaid_since is not null),
                'wrecked', count(*) filter (where pr.wrecked_at is not null),
                'wrecked_oldest_min', round(extract(epoch from now() - min(pr.wrecked_at)) / 60),
                'cruise', count(*) filter (where pr.mission = 'CRUISE' and pr.laid_up_at is null),
                'sailing', count(*) filter (where pr.status = 'SAILING' and pr.laid_up_at is null),
                'in_battle', count(*) filter (where pr.busy_until is not null),
                'hunting', (select count(*) from hunt)) from pr),
  'targets_near', (select jsonb_build_object('pirates_with_one', count(*) filter (where near.n > 0), 'sum', coalesce(sum(near.n), 0)) from near),
  'merchants_sailing', (select count(*) from sv),
  'clock', (select jsonb_build_object('added_at', c.added_at, 'paid_at', c.paid_at) from public.pirate_clock c),
  'room', public.pirate_spend_room(now()),
  'battles', (select jsonb_build_object(
                'all_time', count(*),
                'by_kind', coalesce((select jsonb_object_agg(z.kind, z.n) from (select bt.kind, count(*) as n from bt group by bt.kind) z), '{}'::jsonb),
                'raid_1h', count(*) filter (where bt.kind = 'RAID' and bt.started_at > now() - interval '1 hour'),
                'raid_24h', count(*) filter (where bt.kind = 'RAID' and bt.started_at > now() - interval '24 hours'),
                'fighting', count(*) filter (where bt.status = 'FIGHTING'),
                'stuck', count(*) filter (where bt.status = 'FIGHTING' and bt.resolves_at < now() - interval '2 minutes'),
                'outcomes_1h', coalesce((select jsonb_object_agg(z.o, z.n) from (select coalesce(bt2.outcome, '?') as o, count(*) as n from bt bt2
                                          where bt2.kind = 'RAID' and bt2.status <> 'FIGHTING' and bt2.resolves_at > now() - interval '1 hour' group by 1) z), '{}'::jsonb),
                'navy_came_1h', count(*) filter (where bt.kind = 'RAID' and bt.came > 0 and bt.resolves_at > now() - interval '1 hour'),
                'by_defender', coalesce((select jsonb_object_agg(z.d, z.n) from (select coalesce(bt3.d_kind, '?') as d, count(*) as n from bt bt3 where bt3.kind = 'RAID' group by 1) z), '{}'::jsonb))
              from bt),
  'stats_latest', (select x.figures -> 'win' from public.stats_fleets x order by x.slot desc limit 1),
  'beat', (select jsonb_build_object('mean_ms', round(avg(b.ms)), 'n', count(*)) from public.arrivals_beats b where b.at > now() - interval '5 minutes')
) as r;
commit;
