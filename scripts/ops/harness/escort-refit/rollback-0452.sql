-- 0452 ROLLBACK (forward, OWNER ONLY, a DRAFT). NOT a prod check and NOT a migration yet: to use it, strip the guard line below, give the file the
-- next number and deploy it as any migration. It swaps 0452's two hunks of public.npc_ladder_refit back, so the refit refuses an escort again
-- (escort_of set). The escorts already re-rated keep their hulls: they are their rung's, and nothing re-rates them back. The quick stop for the
-- whole ladder stays 0451's switch (npc_ladder_enabled), one row.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_def text := replace(pg_get_functiondef('public.npc_ladder_refit(uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  v_n   int;
  x     record;
begin
  for x in select * from (values
    (1,
$h$-- fight, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). An escort in harbour is re-rated as any other
-- (0452): her duty is her row of public.navy_ships (mission, escort_of), which this never writes. Her old hulls go and
$h$,
$h$-- fight or escorting, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). Her old hulls go and
$h$),
    (2,
$h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null)) then   -- 0452: not escort_of, which is set while any cargo ship of hers sails with funds, so always
$h$,
$h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null or n.escort_of is not null)) then
$h$)) h(ord, new, old) order by 1 loop
    v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
    if v_n <> 1 then
      raise exception 'rollback-0452 refuses: hunk % occurs % time(s), not once', x.ord, v_n;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  execute v_def;
  raise notice 'rollback-0452: public.npc_ladder_refit refuses an escort again';
end $r$;
