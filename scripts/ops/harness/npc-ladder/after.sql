-- 0451 PROD CHECK, AFTER the deploy (it names 0451's own tables, so it cannot run before): the re-rating as it goes.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/npc-ladder/after.sql
-- One row, one jsonb column `r`. One statement, read only: the ladder's small tables, the rung rows (one a fleet, ~550 at most), the three ship
-- tables, the hoard's last days and the beat's ring. Stable functions only (public.npc_hulls_sig, public.pirate_hoard).
-- WANTED: knobs {true, 2, 40}; `rated_10m` at most 20 a kind (2 a minute); `rated` rising run on run until `due` (at work, her hulls not her
--   rung's) is 0 for the navy and the pirates and falling for the cargo ships (each waits for her own idle minute at home); by_rung with
--   every rung of every kind; `unpaid` and `laid_up` as before the deploy (the pay is by the fleet: 0451 moves none of it); the hoard above
--   100 M and its day's spend in line with the days before; beat < 1,000 ms.
begin transaction read only;
with npc as (
  select 'PIRATE' as kind, n.fleet_id, n.laid_up_at is not null as laid, n.unpaid_since is not null as unpaid from public.pirate_ships n
  union all select 'NAVY', n.fleet_id, n.laid_up_at is not null, n.unpaid_since is not null from public.navy_ships n
  union all select 'CARGO', c.fleet_id, c.laid_up_at is not null, false from public.cargo_ships c
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k where k.key in ('npc_ladder_enabled', 'npc_ladder_per_minute', 'npc_ladder_looks_per_run')),
  'clock', (select jsonb_agg(to_jsonb(c) order by c.kind) from public.npc_ladder_clock c),
  'rated', (select jsonb_object_agg(z.kind, z.n) from (select g.kind, count(*) as n from public.npc_fleet_rungs g group by 1) z),
  'rated_10m', (select jsonb_object_agg(z.kind, z.n) from (select g.kind, count(*) as n from public.npc_fleet_rungs g where g.rated_at > now() - interval '10 minutes' group by 1) z),
  'by_rung', (select jsonb_agg(to_jsonb(z) order by z.kind, z.rung, z.hulls)
                from (select g.kind, g.rung, (select l.name from public.npc_ladder l where l.kind = g.kind and l.rung = g.rung) as name, g.hulls, count(*) as fleets
                        from public.npc_fleet_rungs g group by 1, 2, 4) z),
  'due', (select jsonb_object_agg(z.kind, z.n)
            from (select npc.kind, count(*) as n from npc
                   where not npc.laid and not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = npc.fleet_id and g.hulls = public.npc_hulls_sig(npc.fleet_id))
                   group by 1) z),
  'unpaid', (select jsonb_object_agg(z.kind, z.n) from (select npc.kind, count(*) filter (where npc.unpaid) as n from npc group by 1) z),
  'laid_up', (select jsonb_object_agg(z.kind, z.n) from (select npc.kind, count(*) filter (where npc.laid) as n from npc group by 1) z),
  'hoard', public.pirate_hoard(),
  'spend', (select jsonb_agg(to_jsonb(d) order by d.day desc) from (select * from public.pirate_spend_day order by day desc limit 3) d),
  'beat', (select jsonb_build_object('mean_ms', round(avg(a.ms)), 'n', count(*)) from public.arrivals_beats a where a.at > now() - interval '5 minutes')
) as r;
commit;
