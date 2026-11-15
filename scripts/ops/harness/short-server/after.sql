-- 0433 PROD CHECK, AFTER the deploy: the same read as before.sql under its own name (before.sql's header says what each side wants).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/short-server/after.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). Pure reads: four function bodies by name, two small
-- word tables (news_kinds 8 rows, voyage_event_kinds 14), six world_news rows by their unique key, and two IMMUTABLE / STABLE calls (cmd.refusal,
-- public.sea_refusal) that read no table but sea_zones. No big table is scanned, no volatile function is called.
-- BEFORE, wanted: head 20260818000432; applied false; refusal "a long sentence"; sea "... asks title 2 and wave resistance 10 — you are title 1 and
--   your fleet holds 12"; news UPDATE 'Update: {title}'; prose STORM 'A gale took us on the beam...'; titles_long 6; hunks *_old 1, *_new 0.
-- AFTER, wanted: head 20260818000433; applied true; refusal 'Money 5,000 / 9,000'; sea '<Sea> closed. Title 1 / 2.'; news UPDATE '{title}';
--   prose STORM 'Gale: hull −%s.'; titles_long 0; hunks *_old 0, *_new 1; append_only_on true; the gate green.
begin transaction read only;
with b as (
  select replace(pg_get_functiondef('cmd.refusal(text,text,jsonb)'::regprocedure), E'\r', '') as refusal,
         replace(pg_get_functiondef('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)'::regprocedure), E'\r', '') as raid,
         replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', '') as best,
         replace(pg_get_functiondef('world.house_room()'::regprocedure), E'\r', '') as room
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regprocedure('cmd.refusal_line(text,jsonb)') is not null,
  'refusal', cmd.refusal('E_INSUFFICIENT_FUNDS', 'a long sentence', cmd.figures(5000, 9000, 'ducats'))->>'sentence',
  'sea', public.sea_refusal(1, 12, array[(select z.code from public.sea_zones z where z.title_min = 2 and z.wave_min <= 12 order by z.ord limit 1)])->>'sentence',
  'hunks', (select jsonb_build_object(
      'refusal_old', (position($q$'sentence', btrim(p_sentence),$q$ in b.refusal) > 0)::int, 'refusal_new', (position('cmd.refusal_line' in b.refusal) > 0)::int,
      'raid_old', (position('Your lookout saw them first.' in b.raid) > 0)::int, 'raid_new', (position('We saw them first.' in b.raid) > 0)::int,
      'best_new', (position('-- 0433' in b.best) > 0)::int, 'room_new', (position('-- 0433' in b.room) > 0)::int) from b),
  'news', (select jsonb_object_agg(k.kind, k.en) from public.news_kinds k),
  'prose', (select jsonb_object_agg(k.code, k.prose) from public.voyage_event_kinds k),
  'titles_long', (select count(*) from public.world_news w
                   where w.key in ('update:0375', 'update:0413', 'update:0422', 'update:0423', 'update:0425', 'update:0426')
                     and length(w.detail->'words'->'title'->>'en') > 40),
  'append_only_on', (select t.tgenabled = 'O' from pg_trigger t where t.tgrelid = 'public.world_news'::regclass and t.tgname = 'world_news_append_only')
) as r;
commit;
