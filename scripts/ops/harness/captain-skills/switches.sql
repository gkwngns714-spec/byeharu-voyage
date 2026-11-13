-- 0355 PROD CHECK (switches), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-skills/switches.sql
-- Read BEFORE the deploy (docs/REPUTATION.md risk 2). What each answer means for a captain's skill:
--   crew_bite     true: the LIT arm of public.crew_terms: every skill she uses can be raised. false: the DARK arm: only her job can (E_TRAIT_IDLE otherwise).
--   levels_bite   true: her level multiplies beside her steps (value x level x step). false: the level factor is 1.
--   combat_bite   true: a Gunner's or a Boarder's skill is read by the fight and can be raised. false: it is refused E_TRAIT_IDLE.
--   reputation_on false: nothing can be spent (E_NOT_IN_USE).
-- Wanted: 4 rows, each value a jsonb true or false. 0355 changes none of them.
begin transaction read only;
select c.key, c.value, c.updated_at
  from public.world_config c
 where c.key in ('crew_bite', 'levels_bite', 'combat_bite', 'reputation_on')
 order by c.key;
commit;
