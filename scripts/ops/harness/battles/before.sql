-- 0323, BEFORE: read-only, a pure SELECT of catalog and rows; it calls no volatile function. Run with: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/battles/before.sql
-- The body digests must equal the dev-log's: 0323's hunks were cut against those bodies. No row may stand at or above day_index 1,000,000, no key of 0323 may exist, and no fleet may read a status it would refuse.
begin transaction read only;
select 'body' as what, p.oid::regprocedure::text as name, md5(replace(pg_get_functiondef(p.oid), E'\r', '')) as value
  from pg_proc p
 where p.oid::regprocedure::text in ('voyage.delay_before_day(uuid,integer)', 'voyage.progress_nm(uuid,timestamp with time zone)', 'voyage.report_line(integer,text,jsonb)',
                                     'voyage.fight(uuid,integer,uuid,numeric)', 'voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', 'cmd.divert(uuid,uuid,jsonb,jsonb)',
                                     'world.voyage_view(uuid,boolean)', 'world.sea_roster(timestamp with time zone)')
union all select 'head', max(version), null from supabase_migrations.schema_migrations
union all select 'hold rows already there (want 0)', count(*)::text, null from public.voyage_events ve where ve.day_index >= 1000000
union all select 'highest day of any row', max(ve.day_index)::text, null from public.voyage_events ve
union all select 'keys already there (want 0)', count(*)::text, null from public.world_config c where c.key in ('battle_seconds', 'attack_enabled')
union all select 'sailing with busy_until (want 0)', count(*)::text, null from public.fleets f where f.status = 'SAILING' and f.busy_until is not null
union all select 'fleets', count(*)::text, null from public.fleets
order by 1, 2;
commit;
