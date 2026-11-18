-- 0455 AFTER-CHECK (the land, L1), read-only, ONE statement. Run after the deploy, and again at +10 and +30 minutes after the owner
-- lights land_enabled:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/after-l1.sql
-- After the deploy, wanted: head 20260818000455; land_enabled false; parties 0; mining_xp_rows 0; land_ledger 0; sea_levels: the
--   eleven sea skills, side sea, curve short, top 20 (as before); mining: land, long, top 100.
-- Lit: parties and working (sent), xp rows and level_book rows of mining (written), LAND ledger rows (picks bought). No scan of a large
-- table: level_book and ledger are read by an indexed key (skill / kind) over the last hour only.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'parties', (select count(*) from public.land_parties),
  'working', (select count(*) from public.land_parties lp where lp.action is not null),
  'mining_xp_rows', (select count(*) from public.level_xp x where x.skill = 'mining'),
  'mining_book_last_hour', (select count(*) from public.level_book b where b.skill = 'mining' and b.created_at > now() - interval '1 hour'),
  'land_ledger_last_hour', (select count(*) from public.ledger l where l.kind = 'LAND' and l.created_at > now() - interval '1 hour'),
  'sea_levels', (select jsonb_agg(jsonb_build_object('code', s.code, 'side', s.side, 'curve', s.curve, 'top', public.level_top(s.code)) order by s.ord)
                   from public.level_skills s),
  'curve_top', (select max(c.xp) from public.level_curves c)) as r;
