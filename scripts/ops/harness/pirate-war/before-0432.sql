-- 0432 PROD CHECK, BEFORE the deploy: the same read as after-0432.sql under its own name (its header says what each side wants).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirate-war/after-0432.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads public.battles of the last hour (raids are kept 48 h: at most ~6,000 rows, the hour ~120) with each one's defender by key, the knobs and the
-- beat's ring. No big table is scanned.
-- BEFORE, wanted: applied false; raids_1h as 0427/0429 left them; by_defender_1h has COMPANY among the first.
-- AFTER, wanted: applied true; knobs peace 5, floor 0.10, cap 0.80; within 30 minutes raids_1h steady; npc_first: most raids on MERCHANT / CARGO_SHIP;
--   flee_opened_1h > 0 (the world's outgunned merchants run); fled_1h > 0 with taken_when_fled 0; every rolled flee chance within 0.10..0.80
--   (flee_out_of_range 0); peace_broken 0 (no raid opened on a ship inside 5 minutes of a battle she was set upon in ending); stuck 0; beat < 1,000 ms.
begin transaction read only;
with b as (
  select x.id, x.kind, x.status, x.started_at, x.resolves_at, x.result, x.sheet,
         (select bs.fleet_id from public.battle_sides bs where bs.battle_id = x.id and bs.side = 'DEFENDER' and bs.how = 'OPENED') as d
    from public.battles x where x.kind = 'RAID' and x.started_at > now() - interval '1 hour'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', exists (select 1 from public.world_config k where k.key = 'peace_after_flee_minutes'),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key in ('peace_after_flee_minutes', 'raid_flee_ratio', 'raid_flee_floor', 'raid_flee_max', 'raid_flee_per_speed', 'raid_flee_per_handling', 'attack_ship_minutes')),
  'raids_1h', (select count(*) from b),
  'by_defender_1h', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select public.fleet_kind(b.d) as k, count(*) as n from b group by 1) z),
  'flee_opened_1h', (select count(*) from b where exists (select 1 from public.battle_stances s where s.battle_id = b.id and s.fleet_id = b.d and s.stance = 'FLEE')),
  'fled_1h', (select count(*) from b where coalesce((b.result ->> 'fled')::boolean, false)),
  'taken_when_fled', (select count(*) from b where coalesce((b.result ->> 'fled')::boolean, false) and coalesce((b.result #>> '{raid,taken}')::bigint, 0) > 0),
  'flee_out_of_range', (select count(*) from b cross join lateral jsonb_array_elements(coalesce(b.result -> 'rounds', '[]'::jsonb)) r
                         where b.sheet ? 'a_flee' and r ? 'flee' and ((r ->> 'flee')::numeric < 0.10 or (r ->> 'flee')::numeric > 0.80)),
  'a_flee', (select jsonb_build_object('min', min((b.sheet ->> 'a_flee')::numeric), 'max', max((b.sheet ->> 'a_flee')::numeric)) from b where b.sheet ? 'a_flee'),
  'peace_broken', (select count(*) from b join public.battle_sides ps on ps.fleet_id = b.d and ps.side = 'DEFENDER' join public.battles p on p.id = ps.battle_id
                    where p.id <> b.id and p.status <> 'FIGHTING' and b.started_at > p.resolves_at and b.started_at < p.resolves_at + interval '5 minutes'),
  'stuck', (select count(*) from b where b.status = 'FIGHTING' and b.resolves_at < now() - interval '2 minutes'),
  'beat', (select jsonb_build_object('mean_ms', round(avg(a.ms)), 'n', count(*)) from public.arrivals_beats a where a.at > now() - interval '5 minutes')
) as r;
commit;
