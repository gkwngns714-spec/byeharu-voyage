-- 0526 THE CHART IS BLACK UNTIL SHE SAILS, AFTER (and again after the backfill, and after the light). A PROD CHECK: read-only, ONE statement.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/chart-fog/after-0526.sql
-- Expect after the deploy: head 20260818000526; switch false; sight 150; charts 0; left = companies (none backfilled yet).
-- THE BACKFILL (the lead's, off the beat, the gate read first; it WRITES one row a company, so it is not in this file):
--   select public.chart_backfill_next(5, 500);     -- repeat until its `left` is 0
-- Expect after it: charts = companies, left 0, no merchant row, every row 8,100 bytes; `squares` the fewest and the most any company has.
-- THE LIGHT (the owner's): update public.world_config set value = 'true'::jsonb where key = 'chart_fog_enabled';
-- Expect after it, over the 30-minute check: the beat as it was; `written_30m` about the companies' arrivals in that time, never more.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, players (not merchants), company_chart (one row a company).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'chart_fog_enabled'),
  'sight', (select c.value from public.world_config c where c.key = 'chart_sight_nm'),
  'companies', (select count(*) from public.players pl where not pl.is_npc),
  'charts', (select count(*) from public.company_chart),
  'left', (select count(*) from public.players pl where not pl.is_npc
            and not exists (select 1 from public.company_chart c where c.player_id = pl.id and c.backfilled_at is not null)),
  'merchant_rows', (select count(*) from public.company_chart c join public.players pl on pl.id = c.player_id where pl.is_npc),
  'wrong_size', (select count(*) from public.company_chart c where length(c.cells) <> 8100),
  'squares', (select json_build_object('fewest', min(bit_count(c.cells)), 'most', max(bit_count(c.cells))) from public.company_chart c),
  'written_30m', (select count(*) from public.company_chart c where c.updated_at > now() - interval '30 minutes'),
  'table_kb', (select pg_total_relation_size('public.company_chart') / 1024));
rollback;
