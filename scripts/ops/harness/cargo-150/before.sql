-- 0430 PROD CHECK, BEFORE the deploy (and the lead's read of the facts the PR reports). ONE statement, read-only, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-150/before.sql
-- Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One row, one jsonb column `r`.
-- Reads great_powers (11), port_allegiance (254) with ports by key, cargo_fleet_sizes (~10), cargo_ships (~372) with their fleets, each one's open
-- load (public.cargo_ship_aboard: the (fleet_id, id) index of convoy_cargo) and whether she has any book row at all (one index probe), her SAILING
-- voyage by fleet, the four bodies 0430 re-cuts (md5 only) and the beat's ring. No big table is scanned.
-- WANTED, BEFORE: head 20260818000429 (or the head 0430 is renumbered after); applied false; bodies_pre true (each of the four live bodies is the
--   text 0430 was cut from: the md5 of the local chain at 0426, none of 0427-0429 touches them); knobs convoy_ships_min/max/span/band present,
--   convoy_retire_per_run 3, no cargo_fleet_total.
-- WHAT IT ANSWERS (by country; the share is 0430's own rule computed here: 1 each to a great power with a harbour, the rest of 100 by harbours,
--   largest remainder):
--   harbours, share, number (today's cargo_fleet_sizes), built, laid_up, in_service, at_sea, at_sea_funds, at_sea_empty, roaming (sailing,
--   nothing aboard, not bound home), idle_home (docked at home, empty, no lap), retire_now (in service, ord over the share, idle at home: laid up
--   by the job at convoy_retire_per_run a minute), retire_later (in service, ord over the share, at sea / away / with funds: laid up when home and
--   empty), never_loaded (of retire_now + retire_later, no book row ever: a hull that never carried a ducat).
begin transaction read only;
with pw as (
  select g.nation_id, n.code, g.pirate,
         (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = g.nation_id)::numeric as h
    from public.great_powers g join public.nations n on n.id = g.nation_id
), t as (
  select 100::numeric as total, count(*)::numeric as k, sum(pw.h) as hs from pw where pw.h > 0
), q as (
  select pw.*, 1 + (t.total - t.k) * pw.h / t.hs as quota from pw cross join t where pw.h > 0
), r as (
  select q.*, floor(q.quota)::int as base, row_number() over (order by q.quota - floor(q.quota) desc, q.h desc, q.code) as rk from q
), share as (
  select r.nation_id, r.code, r.pirate, r.h, r.base + case when r.rk <= (select t.total from t) - (select sum(r2.base) from r r2) then 1 else 0 end as share from r
), c as (
  select x.nation_id, x.ord, x.laid_up_at, x.out_load, x.circuit_id, x.home_port_id, f.status, f.port_id,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         exists (select 1 from public.convoy_cargo b where b.fleet_id = x.fleet_id) as ever_loaded,
         (select o.dest_port_id from public.voyages o where o.fleet_id = x.fleet_id and o.status = 'SAILING' order by o.departed_at desc limit 1) as dest
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), cs as (
  select c.*, coalesce(s.share, 0) as share,
         c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null and c.out_load is null and c.circuit_id is null as idle_home
    from c left join share s on s.nation_id = c.nation_id
), per as (
  select s.nation_id, s.code, s.pirate, s.h as harbours, s.share,
         (select z.ships from public.cargo_fleet_sizes z where z.nation_id = s.nation_id) as number,
         count(cs.ord) as built, count(*) filter (where cs.laid_up_at is not null) as laid_up,
         count(*) filter (where cs.ord is not null and cs.laid_up_at is null) as in_service,
         count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING') as at_sea,
         count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING' and cs.aboard > 0) as at_sea_funds,
         count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING' and cs.aboard is null) as at_sea_empty,
         count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING' and cs.aboard is null and cs.dest is distinct from cs.home_port_id) as roaming,
         count(*) filter (where cs.idle_home) as idle_home,
         count(*) filter (where cs.idle_home and cs.ord > s.share) as retire_now,
         count(*) filter (where cs.laid_up_at is null and cs.ord > s.share and not cs.idle_home) as retire_later,
         count(*) filter (where cs.laid_up_at is null and cs.ord > s.share and not cs.ever_loaded) as never_loaded
    from share s left join cs on cs.nation_id = s.nation_id
   group by s.nation_id, s.code, s.pirate, s.h, s.share
), body as (
  select jsonb_object_agg(p::text, md5(replace(pg_get_functiondef(p), E'\r', ''))) as md5s
    from unnest(array['public.convoy_ships_wanted()'::regprocedure, 'public.convoy_ships_of(uuid)'::regprocedure,
                      'public.convoy_fleet_settle(timestamp with time zone)'::regprocedure, 'public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure]) p
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config w where w.key = 'cargo_fleet_total'),
  'bodies_pre', (select b.md5s = '{"convoy_ships_of(uuid)":"e6eba78de3925f29f5669822f4ecdccd","convoy_ships_wanted()":"85747943fdd0d007f924b29402e76340","convoy_fleet_settle(timestamp with time zone)":"940db3908b224f84a910389348c71734","cargo_ship_step(uuid,timestamp with time zone)":"2c15de138c5362f466928ef6edb9ff53"}'::jsonb from body b),
  'bodies_post', (select b.md5s = '{"convoy_ships_of(uuid)":"60d6ea0fe52e1c172bb065dfccaf1c18","convoy_ships_wanted()":"e1c9dd483b9655791c0253196de92f5a","convoy_fleet_settle(timestamp with time zone)":"47f9759fa20a9e696afa79af3afe67aa","cargo_ship_step(uuid,timestamp with time zone)":"60e7fd174260dcd1bbbf55768df743af"}'::jsonb from body b),
  'bodies', (select b.md5s from body b),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('cargo_fleet_total', 'convoy_ships_min', 'convoy_ships_max', 'convoy_ships_span', 'convoy_ships_band', 'convoy_retire_per_run',
                             'convoy_commission_per_run', 'convoy_size_read_minutes', 'convoys_enabled', 'convoy_rich_enabled', 'convoy_load_max', 'convoy_loads_per_run')),
  'countries', (select jsonb_agg(to_jsonb(per) - 'nation_id' order by per.share desc, per.code) from per),
  'world', (select jsonb_build_object('ships', count(*), 'laid_up', count(*) filter (where cs.laid_up_at is not null),
                                      'in_service', count(*) filter (where cs.laid_up_at is null),
                                      'at_sea', count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING'),
                                      'roaming', count(*) filter (where cs.laid_up_at is null and cs.status = 'SAILING' and cs.aboard is null and cs.dest is distinct from cs.home_port_id),
                                      'retire_now', count(*) filter (where cs.idle_home and cs.ord > cs.share),
                                      'retire_later', count(*) filter (where cs.laid_up_at is null and cs.ord > cs.share and not cs.idle_home),
                                      'stay', count(*) filter (where cs.laid_up_at is null and cs.ord <= cs.share),
                                      'aboard', coalesce(sum(cs.aboard), 0))
              from cs),
  'harbours_unflagged', (select count(*) from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.port_allegiance a where a.port_id = p.id)),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(a.ms))) from public.arrivals_beats a where a.at > now() - interval '30 minutes')
) as r;
commit;
