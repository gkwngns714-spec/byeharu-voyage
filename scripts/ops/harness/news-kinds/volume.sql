-- 0362 PROD CHECK (the 30-minute after-check, and again after a day), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news-kinds/volume.sql
-- WHAT THE NEW KINDS TOLD: one row a kind: rows in the last hour and the last 24 hours, how many of them a ship of the world's (npc), and the newest instant.
-- Wanted: for BIG_SALE, BIG_BUY, PIRATES and CAPITAL_GIFT the npc rows of ANY one hour never above news_merchant_hour (2): last_hour_npc at most 2 (3 where two sessions told at the same instant), last_day_npc at most about 48;
-- PRICE_SPIKE last_hour at most news_spike_top (5), last_day at most 120. A kind with no row yet is not listed. One range scan of world_news by its (scope, at) index.
begin transaction read only;
select w.kind,
       count(*) filter (where w.at > now() - interval '1 hour') as last_hour,
       count(*) filter (where w.at > now() - interval '1 hour' and (w.detail->>'npc')::boolean) as last_hour_npc,
       count(*) as last_day,
       count(*) filter (where (w.detail->>'npc')::boolean) as last_day_npc,
       max(w.at) as newest
  from public.world_news w
 where w.scope in ('port', 'company') and w.at > now() - interval '24 hours' and w.kind = any (array['BIG_SALE', 'BIG_BUY', 'PRICE_SPIKE', 'PIRATES', 'CAPITAL_GIFT'])
 group by w.kind order by w.kind;
commit;
