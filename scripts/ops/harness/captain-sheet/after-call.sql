-- 0337 AFTER DEPLOY, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-sheet/after-call.sql
-- world.captain_stats is STABLE. Called once, as the database owner with no identity (a caller with no company): it must answer null, never an error. Wanted: answers_null_for_nobody true.
begin transaction read only;
select world.captain_stats('NOBODY') is null as answers_null_for_nobody;
commit;
