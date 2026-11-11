-- 0353 PROD CHECK (raids-rate), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-log/raids-rate.sql
-- What the log will cost: the PIRATES days of the last 24 hours by who was raided (a company, or a ship of the world), how many were fought in rounds, and the size of a day's
-- payload. docs/COMBAT_LOG.md 1.2 reasons from a guess (one company raid an hour: about 36 kB a day of log); this is the measured rate. Run it before the PR and keep the rows.
-- After the deploy with_log must equal fought for a company and be 0 for the world. A bounded window on voyage_events by resolved_at; nothing is asserted on a growing table.
begin transaction read only;
select case when p.is_npc then 'world' else 'company' end as who,
       count(*) as pirates_days,
       count(*) filter (where ve.payload ? 'rounds') as fought,
       count(*) filter (where ve.payload -> 'fight' ? 'log') as with_log,
       round(avg(pg_column_size(ve.payload))) as payload_bytes_avg,
       max(pg_column_size(ve.payload)) as payload_bytes_max,
       round(count(*) / 24.0, 2) as per_hour
  from public.voyage_events ve
  join public.voyages v on v.id = ve.voyage_id
  join public.players p on p.id = v.player_id
 where ve.kind = 'PIRATES' and ve.resolved_at >= now() - interval '24 hours'
 group by 1 order by 1;
commit;
