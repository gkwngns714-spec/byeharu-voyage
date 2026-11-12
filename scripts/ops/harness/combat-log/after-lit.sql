-- 0353 PROD CHECK (after-lit), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-log/after-lit.sql
-- The 30 minutes before now: run it 30 minutes after the deploy (the log is live at once), and again 30 minutes after raid_orders_enabled is lit.
--   fought / with_log      every company raid day fought in rounds keeps a log: wanted equal. world_with_log: wanted 0 (no ship of the world keeps one).
--   by_order, by_end       the company days by the order they were fought under (FIGHT is no order) and by how they ended. Before the switch is lit: FIGHT only.
--   pay_refused            Pay days that were refused, by reason (EMPTY, NO_PAYEE).
--   ransom_paid_sum        what the Pay days say they paid; named_ransom_sum what a boarding paid a named raider (0339); ransom_ledger the RANSOM rows of the ledger in the window.
--   Wanted: ransom_ledger = ransom_paid_sum + named_ransom_sum, give or take a day that resolved on one side of the window and was written on the other.
-- A bounded window on voyage_events and ledger; no table is summed whole.
begin transaction read only;
with w as (select now() - interval '30 minutes' as a, now() as b),
d as (
  select ve.payload p, pl.is_npc
    from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id join public.players pl on pl.id = v.player_id, w
   where ve.kind = 'PIRATES' and ve.resolved_at >= w.a and ve.resolved_at < w.b)
select (select count(*) from d where not is_npc and p ? 'rounds') as fought,
       (select count(*) from d where not is_npc and p -> 'fight' ? 'log') as with_log,
       (select count(*) from d where is_npc and p -> 'fight' ? 'log') as world_with_log,
       (select jsonb_object_agg(k, n) from (select coalesce(p -> 'fight' -> 'log' ->> 'order', 'FIGHT') k, count(*) n from d where not is_npc and p -> 'fight' ? 'log' group by 1) x) as by_order,
       (select jsonb_object_agg(k, n) from (select p -> 'fight' -> 'log' ->> 'end' k, count(*) n from d where not is_npc and p -> 'fight' ? 'log' group by 1) x) as by_end,
       (select jsonb_object_agg(k, n) from (select p -> 'fight' -> 'log' ->> 'no_pay' k, count(*) n from d where p -> 'fight' -> 'log' ? 'no_pay' group by 1) x) as pay_refused,
       (select count(*) from d where p ? 'ransom_paid') as ransom_paid_days,
       (select coalesce(sum((p ->> 'ransom_paid')::bigint), 0) from d where p ? 'ransom_paid') as ransom_paid_sum,
       (select coalesce(sum((p -> 'pirate' ->> 'ransom')::bigint), 0) from d where not p ? 'ransom_paid' and p ? 'pirate') as named_ransom_sum,
       (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l, w where l.kind = 'RANSOM' and l.created_at >= w.a and l.created_at < w.b) as ransom_ledger,
       public.raid_orders_on() as switch,
       (select jsonb_object_agg(o.raid_order, o.n) from (select r.raid_order, count(*) n from public.fleet_raid_orders r group by 1) o) as order_rows;
commit;
