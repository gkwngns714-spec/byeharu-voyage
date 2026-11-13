-- ATTACKS, PROD CHECK (after-loot), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/after-loot.sql
-- Line 3 of the after-check of lighting attack_enabled (docs/COMBAT_LOG.md 3.6): THE GOLD. Loot is MOVED, never minted (public.loot_take: the ship's book down, the company's purse up, kind LOOT).
-- Read per company that opened an attack in the 7 days before now (public.battle_sides, small), so no ledger row of anyone else is read (the ledger by player_id, created_at):
--   companies          companies that opened an attack in those days.            battles_ended  their battles that are over.
--   loot_battles       the sum of `loot` in the ended battles' results.          loot_reports   the sum of `loot` in their BATTLE_REPORT events.
--   loot_ledger        the sum of their LOOT rows in the ledger.
--   WANTED: the three equal (give or take a battle whose close is being written as this reads).
--   over_day_cap       WANTED 0: companies whose loot of any 24 hours (the 24 hours to each of their LOOT rows, public.loot_today's own window) is over loot_per_company_day.
--   most_in_24h        the most any company took in any such 24 hours; day_cap the knob.
--   over_ship_cap      WANTED 0: battles whose loot is over loot_per_ship.
--   by_company         each company: battles ended, won (boarded or paid off), loot, hands lost (at most 30 rows).
begin transaction read only;
with a as (
  select distinct f.player_id
    from public.battles b join public.battle_sides bs on bs.battle_id = b.id and bs.side = 'ATTACKER' and bs.how = 'OPENED' join public.fleets f on f.id = bs.fleet_id
   where b.kind = 'ATTACK' and b.started_at > now() - interval '7 days'),
done as (
  select b.id, f.player_id, b.result
    from public.battles b join public.battle_sides bs on bs.battle_id = b.id and bs.side = 'ATTACKER' and bs.how = 'OPENED' join public.fleets f on f.id = bs.fleet_id
   where b.kind = 'ATTACK' and b.status <> 'FIGHTING' and b.started_at > now() - interval '7 days'),
l as (
  select l.player_id, l.created_at, l.ducats_delta,
         sum(l.ducats_delta) over (partition by l.player_id order by l.created_at range between interval '24 hours' preceding and current row) as in_24h
    from a join public.ledger l on l.player_id = a.player_id and l.created_at > now() - interval '7 days'
   where l.kind = 'LOOT')
select (select count(*) from a) as companies,
       (select count(*) from done) as battles_ended,
       (select coalesce(sum((d.result ->> 'loot')::bigint), 0) from done d) as loot_battles,
       (select coalesce(sum((e.payload ->> 'loot')::bigint), 0) from a join public.events e on e.player_id = a.player_id and e.created_at > now() - interval '7 days'
         where e.kind = 'BATTLE_REPORT' and e.payload ? 'loot') as loot_reports,
       (select coalesce(sum(l.ducats_delta), 0) from l) as loot_ledger,
       (select count(distinct l.player_id) from l where l.in_24h > public.wc_num('loot_per_company_day')) as over_day_cap,
       (select coalesce(max(l.in_24h), 0) from l) as most_in_24h,
       public.wc_num('loot_per_company_day') as day_cap,
       (select count(*) from done d where (d.result ->> 'loot')::bigint > public.wc_num('loot_per_ship')) as over_ship_cap,
       (select coalesce(jsonb_agg(jsonb_build_object('company', p.company_name, 'battles', x.n, 'won', x.won, 'loot', x.loot, 'crew_lost', x.crew) order by x.loot desc, p.company_name), '[]'::jsonb)
          from (select d.player_id, count(*) as n, count(*) filter (where d.result ->> 'outcome' in ('PLUNDERED', 'RANSOM')) as won,
                       coalesce(sum((d.result ->> 'loot')::bigint), 0) as loot, coalesce(sum((d.result ->> 'crew_lost')::bigint), 0) as crew
                  from done d group by d.player_id order by 4 desc limit 30) x join public.players p on p.id = x.player_id) as by_company,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
