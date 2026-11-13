-- 0362 PROD CHECK (before the deploy, and whenever news_big_trade is retuned), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news-kinds/trade-sizes.sql
-- HOW THE KNOB SITS AGAINST TODAY'S TRADES: the last 24 hours of sales and buys, a merchant's and a player's apart: how many, what they came to (p50, p90, p99, p99.9, the
-- largest) and how many reached 250,000 (the knob as shipped), 500,000, 1,000,000 and 2,000,000.
-- READ IT LIKE THIS: the design chose 250,000 as the 99.9th per cent of a sale (2026-10-26: about 30 a day). If `at_250k` of the merchants is far above 48 a day, the cap
-- (news_merchant_hour 2 a kind an hour) is what bounds the feed and the headlines are the first two of each hour, not the largest: raise news_big_trade to about today's p99.9
-- (the owner's knob). Nothing depends on this read: whatever it says, the merchants cannot tell more than the cap.
-- One range scan of the trades' own index (events_trades_window: created_at, SOLD and BOUGHT only, the payload included).
begin transaction read only;
select e.kind, p.is_npc as merchant, count(*) as trades,
       round(percentile_cont(0.5) within group (order by (e.payload->>'total')::numeric)) as p50,
       round(percentile_cont(0.9) within group (order by (e.payload->>'total')::numeric)) as p90,
       round(percentile_cont(0.99) within group (order by (e.payload->>'total')::numeric)) as p99,
       round(percentile_cont(0.999) within group (order by (e.payload->>'total')::numeric)) as p999,
       round(max((e.payload->>'total')::numeric)) as largest,
       count(*) filter (where (e.payload->>'total')::numeric >= 250000) as at_250k,
       count(*) filter (where (e.payload->>'total')::numeric >= 500000) as at_500k,
       count(*) filter (where (e.payload->>'total')::numeric >= 1000000) as at_1m,
       count(*) filter (where (e.payload->>'total')::numeric >= 2000000) as at_2m
  from public.events e join public.players p on p.id = e.player_id
 where e.kind in ('SOLD', 'BOUGHT') and e.created_at > now() - interval '24 hours'
 group by e.kind, p.is_npc
 order by e.kind, p.is_npc;
commit;
