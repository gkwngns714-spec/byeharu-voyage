-- ATTACKS, PROD CHECK (after-battles), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/after-battles.sql
-- Lines 1 and 4 of the after-check of lighting attack_enabled (docs/COMBAT_LOG.md 3.6). The 30 minutes before now; run it at +5, +15 and +30 minutes after the light.
--   opened, closed     battles a company opened (kind ATTACK) and battles that ended, in the window. by_status and by_outcome: how they stand and how they ended.
--   late               WANTED 0: battles still FIGHTING more than 2 minutes past their clock (resolves_at). The minute job (byeharu-voyage:battles) or a watching card closes each at its clock.
--   late_list          those battles: id, started, clock, rounds logged (at most 20).
--   fleets_in_battle   fleets with status IN_BATTLE now; stuck_in_battle WANTED 0: such a fleet with no FIGHTING battle of her own.
--   stuck_busy         WANTED 0: a fleet that was a side of a battle that has ended and still carries its busy_until (public.battle_resolve clears it for every side).
--   stuck_navy         WANTED 0: a navy ship still tied (battle_id) to a battle that has ended (public.navy_close frees them).
--   held_now           voyages held at sea for a battle now (a FIGHTING battle's sailing sides): for reading, not bounded.
-- Reads public.battles (small: no battle existed before the light), its sides, and the fleets by status. No growing table is read whole.
begin transaction read only;
with w as (select now() - interval '30 minutes' as a, now() as b),
ended as (select b.id from public.battles b where b.status <> 'FIGHTING' and b.resolves_at > now() - interval '7 days')
select (select w.a from w) as window_from, (select w.b from w) as window_to,
       (select count(*) from public.battles b, w where b.kind = 'ATTACK' and b.started_at >= w.a and b.started_at < w.b) as opened,
       (select count(*) from public.battles b, w where b.kind = 'ATTACK' and b.status <> 'FIGHTING' and b.resolves_at >= w.a and b.resolves_at < w.b) as closed,
       (select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb) from (select b.status, count(*) as n from public.battles b, w where b.started_at >= w.a group by b.status) x) as by_status,
       (select coalesce(jsonb_object_agg(x.o, x.n), '{}'::jsonb)
          from (select coalesce(b.result ->> 'outcome', 'none') as o, count(*) as n from public.battles b, w where b.status <> 'FIGHTING' and b.resolves_at >= w.a group by 1) x) as by_outcome,
       (select count(*) from public.battles b where b.status = 'FIGHTING' and b.resolves_at < now() - interval '2 minutes') as late,
       (select coalesce(jsonb_agg(jsonb_build_object('battle', x.id, 'started', x.started_at, 'clock', x.resolves_at, 'rounds_done', x.rounds_done) order by x.resolves_at), '[]'::jsonb)
          from (select b.id, b.started_at, b.resolves_at, b.rounds_done from public.battles b
                 where b.status = 'FIGHTING' and b.resolves_at < now() - interval '2 minutes' order by b.resolves_at limit 20) x) as late_list,
       (select count(*) from public.fleets f where f.status = 'IN_BATTLE') as fleets_in_battle,
       (select count(*) from public.fleets f where f.status = 'IN_BATTLE'
           and not exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id where bs.fleet_id = f.id and b.status = 'FIGHTING')) as stuck_in_battle,
       (select count(distinct f.id) from ended e join public.battle_sides bs on bs.battle_id = e.id join public.fleets f on f.id = bs.fleet_id
         where f.busy_until is not null
           and not exists (select 1 from public.battle_sides b2 join public.battles b on b.id = b2.battle_id where b2.fleet_id = f.id and b.status = 'FIGHTING')) as stuck_busy,
       (select count(*) from public.navy_ships n join public.battles b on b.id = n.battle_id where b.status <> 'FIGHTING') as stuck_navy,
       (select count(*) from public.battles b join public.battle_sides bs on bs.battle_id = b.id join public.fleets f on f.id = bs.fleet_id
         where b.status = 'FIGHTING' and f.status = 'SAILING') as held_now,
       public.attack_on() as attack_enabled,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
