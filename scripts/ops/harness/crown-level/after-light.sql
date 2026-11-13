-- 0372 PROD CHECK (the light of npc_ship_level_enabled), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/crown-level/after-light.sql
-- The dev-log's after-light block of 0344 (docs/dev-log/2026-11-10-crown-hulls-have-a-level.md), as a file. Run it BEFORE the deploy, right after it, and at +30 minutes.
--   Wanted before: switch false, level 5, job 1, crown_rows 0 (the migration refuses on any), news_rows 0. `crown_hulls` is how many rows the file will write.
--   Wanted after:  switch true, level 5, job 1, news_rows 1, and crown_at_level = crown_hulls with crown_other_level 0. A hull laid or refitted in the last ten minutes may still be
--                  waiting for the job (crown_no_row above 0): read again after the next run; it must not stay.
--   by_kind is for the eye: cargo, navy and pirate hulls, and how many of each hold the level.
-- Every function called is STABLE or IMMUTABLE (public.wc, public.wc_num, public.crown_house, public.level_from_points). Never call public.crown_hull_level_fix from a check: it writes.
begin transaction read only;
with h as (
  select s.id,
         case when exists (select 1 from public.cargo_ships c where c.player_id = s.player_id) then 'cargo'
              when exists (select 1 from public.pirate_ships p where p.player_id = s.player_id) then 'pirate'
              else 'navy' end as kind,
         (select x.xp from public.ship_xp x where x.ship_id = s.id) as xp
    from public.ships s
   where public.crown_house(s.player_id)
)
select public.wc('npc_ship_level_enabled') as switch,
       public.wc('npc_ship_level') as level,
       (select count(*) from cron.job j where j.jobname = 'byeharu-voyage:crown-hull-level' and j.active) as job,
       (select count(*) from public.world_news w where w.key = 'update:0372') as news_rows,
       (select count(*) from h) as crown_hulls,
       (select count(*) from h where h.xp is not null) as crown_rows,
       (select count(*) from h where h.xp is not null and public.level_from_points(h.xp) = public.wc_num('npc_ship_level')) as crown_at_level,
       (select count(*) from h where h.xp is not null and public.level_from_points(h.xp) <> public.wc_num('npc_ship_level')) as crown_other_level,
       (select count(*) from h where h.xp is null) as crown_no_row,
       (select jsonb_object_agg(k.kind, jsonb_build_object('hulls', k.n, 'with_row', k.r)) from (select h.kind, count(*) as n, count(h.xp) as r from h group by h.kind) k) as by_kind;
commit;
