-- 0356 PROD CHECK (before-seed), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/reputation/level-before-seed.sql
-- Every human's three levels as public.player_progress (STABLE) derives them now: the marks 0356 will seed (no back-pay). One row a human (19 expected), no
-- name: the first 8 characters of her id. It is the same read the migration makes (one player_progress a human), so running it just before the deploy also
-- warms those pages. A read here that takes many seconds is the warning that the migration's own seed read will too (that read holds no lock; its bound is
-- the file's statement_timeout of 60 s). Keep the rows: level-after-seed.sql is read against them.
begin transaction read only;
select left(p.id::text, 8) as house,
       (x.pp -> 'trading' ->> 'level')::int as trading,
       (x.pp -> 'exploration' ->> 'level')::int as exploration,
       (x.pp -> 'combat' ->> 'level')::int as combat,
       (x.pp -> 'combat' ->> 'playable')::boolean as combat_playable
  from public.players p
 cross join lateral (select public.player_progress(p.id) as pp) x
 where not p.is_npc
 order by p.created_at, p.id;
commit;
