-- 0363 PROD CHECK (the 30-minute window), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/second-ship/window.sql
-- A recipe is a rule of play, so the deploy gets a measured window: run this once before the deploy and again 30 minutes after it.
-- Hulls laid down by human companies, by class, in the last 30 minutes, the last day and ever (the event cmd.do_build writes), and how many human companies hold one ship and two or more.
-- Wanted: nothing asserted. A Barca laid down after the deploy by a company that kept no part is the change at work; a jump far beyond the rate of the day is a reason to look.
begin transaction read only;
select coalesce(e.payload ->> 'class', '(none yet)') as class,
       count(e.id) filter (where e.created_at > now() - interval '30 minutes') as last_30_minutes,
       count(e.id) filter (where e.created_at > now() - interval '1 day') as last_day,
       count(e.id) as ever,
       max(e.created_at) as newest,
       (select count(*) from public.players pl where not pl.is_npc and (select count(*) from public.ships s where s.player_id = pl.id) = 1) as companies_with_one_ship,
       (select count(*) from public.players pl where not pl.is_npc and (select count(*) from public.ships s where s.player_id = pl.id) >= 2) as companies_with_two_or_more
  from (select 1) one
  left join public.events e on e.kind = 'HULL_LAID_DOWN' and exists (select 1 from public.players pl where pl.id = e.player_id and not pl.is_npc)
 group by 1
 order by 4 desc, 1;
commit;
