-- 0435 PROD CHECK, BEFORE and AFTER the deploy (the same read; its header says what each side wants).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/tick-combat/check.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One statement, read only.
-- Reads public.battles of the last hour (RAID rows are kept 48 h; the hour is ~120 at the ceiling), the knobs and the beat's ring. No big table is scanned.
-- BEFORE, wanted: applied false; raids_1h and their mean span (~600 s) as 0427-0432 left them; round_rows_1h ~7 a battle.
-- AFTER (30 minutes), wanted: applied true; tick_1h = every battle opened since the deploy; span_s mean 15-75 (max <= 75); stuck 0 (no FIGHTING battle
--   past its end by more than 2 minutes); round_rows_since 0 for tick battles; outcomes spread as before (PLUNDERED / EVADED / DRIVEN_OFF / RANSOM);
--   ticks_kb mean 1-6; beat < 1,000 ms and no worse than BEFORE.
begin transaction read only;
with b as (
  select x.id, x.kind, x.status, x.started_at, x.resolves_at, x.result,
         to_jsonb(x) -> 'ticks' as ticks   -- absent before 0435: null
    from public.battles x where x.started_at > now() - interval '1 hour'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', exists (select 1 from public.world_config k where k.key = 'tick_ms'),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k where k.key in ('tick_ms', 'tick_window', 'tick_fight_kinds', 'battle_join_nm', 'battle_seconds', 'battle_round_seconds')),
  'battles_1h', (select coalesce(jsonb_object_agg(z.kind, z.n), '{}'::jsonb) from (select b.kind, count(*) as n from b group by 1) z),
  'tick_1h', (select count(*) from b where b.ticks is not null and b.ticks <> 'null'::jsonb),
  'span_s', (select jsonb_build_object('round', round(avg(extract(epoch from b.resolves_at - b.started_at)) filter (where b.ticks is null or b.ticks = 'null'::jsonb)),
                                       'tick_mean', round(avg(extract(epoch from b.resolves_at - b.started_at)) filter (where b.ticks is not null and b.ticks <> 'null'::jsonb)),
                                       'tick_max', round(max(extract(epoch from b.resolves_at - b.started_at)) filter (where b.ticks is not null and b.ticks <> 'null'::jsonb))) from b),
  'outcomes_1h', (select coalesce(jsonb_object_agg(z.o, z.n), '{}'::jsonb) from (select coalesce(b.result ->> 'outcome', 'FIGHTING') as o, count(*) as n from b group by 1) z),
  'round_rows_1h', (select count(*) from public.battle_rounds r join b on b.id = r.battle_id),
  'round_rows_tick', (select count(*) from public.battle_rounds r join b on b.id = r.battle_id where b.ticks is not null and b.ticks <> 'null'::jsonb),
  'ticks_kb', (select round(avg(length(b.ticks::text)) / 1024.0, 2) from b where b.ticks is not null and b.ticks <> 'null'::jsonb),
  'stuck', (select count(*) from b where b.status = 'FIGHTING' and b.resolves_at < now() - interval '2 minutes'),
  'beat', (select jsonb_build_object('mean_ms', round(avg(a.ms)), 'n', count(*)) from public.arrivals_beats a where a.at > now() - interval '5 minutes')
) as r;
commit;
