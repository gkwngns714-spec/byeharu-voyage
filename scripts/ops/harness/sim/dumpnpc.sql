select string_agg('===== ' || p.oid::regprocedure::text || ' [' || p.provolatile::text || ']' || E'\n' || replace(pg_get_functiondef(p.oid), E'\r', ''), E'\n' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and (p.proname like 'npc\_%' or p.proname in ('city_bid_factor'));
