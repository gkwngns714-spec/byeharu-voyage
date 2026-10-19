begin transaction read only;
select json_agg(p.oid::regprocedure::text || '=' || p.provolatile::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('client_rpc_entry_points', 'client_write_grants', 'client_executable_writers', 'caller_evaluated_functions');
rollback;
