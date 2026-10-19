begin transaction read only;
select json_object_agg(fn, replace(pg_get_functiondef(fn::regprocedure), E'\r', '')) j from (values
 ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)'),('public.npc_tend_houses(timestamp with time zone)'),
 ('public.npc_tend_sum(jsonb,jsonb)'),('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
 ('public.npc_build_for(uuid,timestamp with time zone)'),('public.npc_give_above_ceiling(timestamp with time zone,uuid)'),('public.npc_purse_ceiling(uuid)')) v(fn);
rollback;
