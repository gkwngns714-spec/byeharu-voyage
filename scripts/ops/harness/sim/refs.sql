begin transaction read only;
select json_build_object(
 'head', (select max(version) from supabase_migrations.schema_migrations),
 'refs', (select json_agg(json_build_array(n.nspname||'.'||p.proname, pg_get_function_identity_arguments(p.oid), p.provolatile) order by 1)
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname in ('public','cmd','voyage','world')
             and (p.prosrc ~ 'npc_build_for|npc_give_above_ceiling|npc_purse_ceiling|MERCHANT_SURPLUS|ceiling_given' )),
 'knob', (select json_agg(key) from public.world_config where key like 'npc_purse%'),
 'flows', (select count(*) from public.treasury_flows where kind='MERCHANT_SURPLUS'),
 'flows_sum', (select sum(ducats) from public.treasury_flows where kind='MERCHANT_SURPLUS'),
 'ledger', (select count(*) from public.ledger where kind='MERCHANT_SURPLUS'),
 'events', (select count(*) from public.events where kind='SURPLUS_GIVEN')
) j;
rollback;
