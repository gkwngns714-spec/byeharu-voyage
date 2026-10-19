begin transaction read only;
select json_build_object('n', (select count(*) from public.treasury_flows where kind='MERCHANT_SURPLUS'),
 'ledger', (select count(*) from public.ledger where kind='MERCHANT_SURPLUS'),
 'min_flow', (select min(created_at) from public.treasury_flows),
 'ev', (select count(*) from public.events where kind='SURPLUS_GIVEN'),
 'cols', (select json_agg(column_name) from information_schema.columns where table_schema='public' and table_name='treasury_flows')) j;
rollback;
