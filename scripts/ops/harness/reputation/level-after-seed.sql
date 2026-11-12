-- 0356 PROD CHECK (after-seed), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/reputation/level-after-seed.sql
-- Every human's marks beside her derived levels, and what the level gift has paid her. Wanted, just after the deploy: the marks are level-before-seed.sql's
-- rows; `unpaid` is 0, or is a level she crossed since (her next arrival or her next open page pays it); `gifts` 0 and `events` 0 for every house (NO
-- BACK-PAY) until a house crosses a level: then gifts = 10 x each level crossed since the deploy and events = that many LEVEL_UP rows. A house founded after
-- the deploy has null marks (no row counts as 1). Thirty minutes later, the same read: a gift without its event, or a mark above its level, is the finding.
begin transaction read only;
select left(p.id::text, 8) as house,
       (x.pp -> 'trading' ->> 'level')::int as trading,
       (select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading') as trading_mark,
       (x.pp -> 'exploration' ->> 'level')::int as exploration,
       (select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'exploration') as exploration_mark,
       (x.pp -> 'combat' ->> 'level')::int as combat,
       (select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'combat') as combat_mark,
       greatest((x.pp -> 'trading' ->> 'level')::int - coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading'), 1), 0)
         + greatest((x.pp -> 'exploration' ->> 'level')::int - coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'exploration'), 1), 0)
         + case when (x.pp -> 'combat' ->> 'playable')::boolean
                then greatest((x.pp -> 'combat' ->> 'level')::int - coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'combat'), 1), 0)
                else 0 end as unpaid,
       coalesce((select sum(k.delta) from public.reputation_book k where k.player_id = p.id and k.kind = 'level'), 0) as gifts,
       (select count(*) from public.events e where e.player_id = p.id and e.kind = 'LEVEL_UP') as events,
       coalesce((select sum(k.delta) from public.reputation_book k where k.player_id = p.id and k.kind = 'lap'), 0) as lap_gifts
  from public.players p
 cross join lateral (select public.player_progress(p.id) as pp) x
 where not p.is_npc
 order by p.created_at, p.id;
commit;
