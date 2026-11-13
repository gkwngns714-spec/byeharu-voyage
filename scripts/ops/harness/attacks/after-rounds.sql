-- ATTACKS, PROD CHECK (after-rounds), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/after-rounds.sql
-- Line 2 of the after-check of lighting attack_enabled (docs/COMBAT_LOG.md 3.1, 3.6): EVERY BATTLE'S LOGGED ROUNDS ARE A RE-RUN OF ITS SHEET.
-- For each battle fought round by round that began in the last 24 hours (the newest 200): the rows of public.battle_rounds, in order, against the rounds of public.battle_fight(battle, null)
-- (STABLE: the frozen sheet fought again to its end under the stances kept; no engine state is kept between rounds, so the log must be its first rows, as text).
--   battles            how many were read; fighting of them; rounds_logged in all.
--   rounds_differ      WANTED 0: battles whose logged rows are not the first rows of the re-run.
--   count_differs      WANTED 0: ended battles whose number of logged rows is not the re-run's rounds_fought.
--   result_differs     WANTED 0: ended battles whose kept result (outcome, rounds, hull) is not the re-run's.
--   differing          the ids of any of those (at most 20), for the dev-log.
-- Cost: one re-run a battle (about 0.5 ms each on PGlite, measured for 0357); 200 at most.
begin transaction read only;
with b as (
  select bt.id, bt.status, bt.result, public.battle_fight(bt.id, null) as rerun,
         (select coalesce(jsonb_agg(r."row" order by r.g), '[]'::jsonb) from public.battle_rounds r where r.battle_id = bt.id) as logged
    from (select x.id, x.status, x.result from public.battles x
           where x.sheet is not null and x.started_at > now() - interval '24 hours' order by x.started_at desc, x.id limit 200) bt),
c as (
  select b.*, jsonb_array_length(b.logged) as n,
         (select coalesce(jsonb_agg(e.v order by e.o), '[]'::jsonb) from jsonb_array_elements(b.rerun -> 'rounds') with ordinality e(v, o) where e.o <= jsonb_array_length(b.logged)) as first_rows
    from b)
select count(*) as battles,
       count(*) filter (where c.status = 'FIGHTING') as fighting,
       coalesce(sum(c.n), 0) as rounds_logged,
       count(*) filter (where c.logged is distinct from c.first_rows) as rounds_differ,
       count(*) filter (where c.status <> 'FIGHTING' and c.n is distinct from (c.rerun ->> 'rounds_fought')::int) as count_differs,
       count(*) filter (where c.status <> 'FIGHTING' and (c.result ->> 'outcome' is distinct from c.rerun ->> 'outcome' or c.result -> 'rounds' is distinct from c.rerun -> 'rounds'
                                                          or c.result -> 'hull' is distinct from c.rerun -> 'hull')) as result_differs,
       (select coalesce(jsonb_agg(d.id), '[]'::jsonb)
          from (select c2.id from c c2
                 where c2.logged is distinct from c2.first_rows
                    or (c2.status <> 'FIGHTING' and (c2.n is distinct from (c2.rerun ->> 'rounds_fought')::int or c2.result ->> 'outcome' is distinct from c2.rerun ->> 'outcome'
                                                     or c2.result -> 'rounds' is distinct from c2.rerun -> 'rounds' or c2.result -> 'hull' is distinct from c2.rerun -> 'hull'))
                 order by c2.id limit 20) d) as differing,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from c;
commit;
