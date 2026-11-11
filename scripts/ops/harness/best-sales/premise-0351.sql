-- 0351 PROD CHECK (before, and again after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/premise-0351.sql
-- THE PREMISE on the live world. stores_on_credit: true means a sale is within her purse when the BUY is (her stores may be owed; the trip tray judges the same); false means the
-- buy and the stores together. real_seconds_a_game_day: what the card's time is counted in. Wanted: one row; nothing is asserted, the two figures are read into the dev-log.
-- STABLE functions only; nothing is written.
begin transaction read only;
select p.code, public.credit_on(p.id) as stores_on_credit, round(86400 / public.wc_num('time_compression'), 1) as real_seconds_a_game_day
  from public.ports p
 where p.code = 'LIS';
commit;
