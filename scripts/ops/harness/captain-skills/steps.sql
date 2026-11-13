-- 0355 PROD CHECK (steps), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-skills/steps.sql
-- The 30-minute after-check, and any day after: every step a player has bought, newest first (at most 50). Each row is one CAPTAIN_SKILL event
-- beside the row it left and the book row that paid for it. Wanted on every row: held >= rank (a later step may stand above it); paid = -cost;
-- merchant false. No row at all right after the deploy is right too: nothing moves until a player spends.
begin transaction read only;
select e.created_at as at,
       pl.company_name as company,
       e.payload ->> 'name' as captain,
       e.payload ->> 'trait' as skill,
       (e.payload ->> 'rank')::int as rank,
       (e.payload ->> 'cost')::int as cost,
       (select r.rank from public.captain_trait_rank r
          join public.player_officers po on po.id = r.player_officer_id join public.officers o on o.id = po.officer_id
         where po.player_id = e.player_id and o.code = e.payload ->> 'officer' and r.trait = e.payload ->> 'trait') as held,
       (select k.delta from public.reputation_book k
         where k.player_id = e.player_id and k.kind = 'skill' and k.note ->> 'officer' = e.payload ->> 'officer'
           and k.note ->> 'trait' = e.payload ->> 'trait' and (k.note ->> 'rank')::int = (e.payload ->> 'rank')::int) as paid,
       pl.is_npc as merchant
  from public.events e join public.players pl on pl.id = e.player_id
 where e.kind = 'CAPTAIN_SKILL'
 order by e.created_at desc
 limit 50;
commit;
