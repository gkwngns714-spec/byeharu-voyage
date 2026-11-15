-- 0445 PROD CHECK, BEFORE and AFTER the deploy (+10 min, +30 min, +60 min), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirates-at-sea/before.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads public.pirate_ships (one row a pirate fleet, ~121) with each one's fleet by key, her ended voyages of the last 2 hours through
-- voyages_fleet_ended_0249 (fleet_id, eta), the raids of the last hour (public.battles, kept 48 h) and the beat's ring. No big table is scanned.
-- BEFORE, wanted: applied false; `where` shows most working pirates DOCKED at their haunt, lying pirate_haunt_hours.
-- AFTER, wanted: applied true; at_sea_share >= 0.70 of the working pirates within ~30 minutes; lying_min p50 under 5; raids_1h steady;
--   raids_from_port_10m 0; stuck 0; beat mean under 1,000 ms.
begin transaction read only;
with p as (
  select n.fleet_id, n.ord, n.home_port, n.sea_id, n.mission, n.haunt_port, n.haunt_since, n.unpaid_since, n.laid_up_at, n.wrecked_at,
         f.status, f.port_id, f.ready_at, f.busy_until,
         (select coalesce(bool_or(x.durability > 0), false) from public.ships x where x.fleet_id = n.fleet_id) as alive
    from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
), w as (
  select p.*, case when p.laid_up_at is not null then 'laid_up' when p.wrecked_at is not null or not p.alive then 'wrecked' else 'work' end as st,
         case when p.status = 'SAILING' then 'sea' when p.port_id = p.home_port then 'home' when p.port_id = p.haunt_port then 'haunt' else 'other' end as at
    from p
), v as (
  select v.fleet_id, extract(epoch from v.eta - v.departed_at) / 60 as mins, v.total_nm
    from w join public.voyages v on v.fleet_id = w.fleet_id and v.status <> 'SAILING' and v.eta > now() - interval '2 hours'
), b as (
  select x.id, x.started_at, x.status, x.resolves_at,
         (select bs.fleet_id from public.battle_sides bs where bs.battle_id = x.id and bs.side = 'ATTACKER' and bs.how = 'OPENED') as a
    from public.battles x where x.kind = 'RAID' and x.started_at > now() - interval '1 hour'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', exists (select 1 from public.world_config k where k.key = 'pirate_port_minutes'),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key in ('pirate_haunt_hours', 'navy_steps_per_run', 'navy_reach_nm', 'attack_reach_nm', 'pirate_strike_minutes', 'pirate_strikes_per_run',
                             'pirate_strike_tries_per_run', 'fleet_speed_by_kind', 'game_day_seconds', 'navy_store_days', 'pirate_port_minutes', 'pirate_cruise_minutes',
                             'pirate_refit_below', 'pirates_bite', 'attack_enabled')),
  'fleets', (select count(*) from w),
  'state', (select jsonb_object_agg(z.st, z.n) from (select w.st, count(*) as n from w group by 1) z),
  'working', (select count(*) from w where w.st = 'work'),
  'at_sea', (select count(*) from w where w.st = 'work' and w.status = 'SAILING'),
  'at_sea_share', (select round(count(*) filter (where w.status = 'SAILING')::numeric / greatest(count(*), 1), 2) from w where w.st = 'work'),
  'where', (select jsonb_agg(jsonb_build_object('status', z.status, 'at', z.at, 'mission', z.mission, 'sea_set', z.sea_set, 'waits_ready', z.waits, 'held', z.held,
                                                'unpaid', z.unpaid, 'n', z.n) order by z.n desc)
              from (select w.status, w.at, w.mission, w.sea_id is not null as sea_set, coalesce(w.ready_at > now(), false) as waits, w.busy_until is not null as held,
                           w.unpaid_since is not null as unpaid, count(*) as n
                      from w where w.st = 'work' group by 1, 2, 3, 4, 5, 6, 7) z),
  'lying_min', (select jsonb_build_object('n', count(*), 'not_started', count(*) filter (where w.haunt_since is null),
                                          'p50', round((percentile_cont(0.5) within group (order by extract(epoch from now() - w.haunt_since) / 60))::numeric),
                                          'max', round(max(extract(epoch from now() - w.haunt_since) / 60)::numeric))
                  from w where w.st = 'work' and w.status = 'DOCKED' and w.at = 'haunt'),
  'haunts', (select jsonb_build_object('distinct', count(distinct w.haunt_port), 'homes', count(distinct w.home_port)) from w where w.st = 'work'),
  'legs_2h', (select jsonb_build_object('n', count(*), 'fleets', count(distinct v.fleet_id), 'min_p50', round((percentile_cont(0.5) within group (order by v.mins))::numeric, 1),
                                        'min_max', round(max(v.mins)::numeric, 1), 'nm_p50', round((percentile_cont(0.5) within group (order by v.total_nm))::numeric),
                                        'nm_max', round(max(v.total_nm)::numeric),
                                        'nm_a_min_p50', round((percentile_cont(0.5) within group (order by v.total_nm / nullif(v.mins, 0)))::numeric, 1))
                from v),
  'raids_1h', (select count(*) from b),
  'raiders_1h', (select count(distinct b.a) from b),
  'raids_10m', (select count(*) from b where b.started_at > now() - interval '10 minutes'),
  'raids_from_port_10m', (select count(*) from b join w on w.fleet_id = b.a where b.status = 'FIGHTING' and w.port_id is not null),
  'raids_fighting', (select jsonb_build_object('n', count(*), 'attacker_in_port', count(*) filter (where w.port_id is not null))
                       from b join w on w.fleet_id = b.a where b.status = 'FIGHTING'),
  'stuck', (select count(*) from b where b.status = 'FIGHTING' and b.resolves_at < now() - interval '2 minutes'),
  'beat', (select jsonb_build_object('mean_ms', round(avg(a.ms)), 'n', count(*)) from public.arrivals_beats a where a.at > now() - interval '5 minutes')
) as r;
commit;
