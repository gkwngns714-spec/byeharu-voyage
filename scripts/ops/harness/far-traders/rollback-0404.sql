-- 0404 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). It takes the 24 far traders' fleets off the merchants' roster: the tender no longer sails them (a fleet at sea
-- arrives and stays), and npc_fleet_max goes back down by 24. NOTHING IS DELETED FROM THE BOOKS AND NO MONEY MOVES: the houses, their hulls, their purses
-- and the ledger stay as they are (the ledger is append-only; paying their money back to their capitals is the owner's call). The six loadouts stay too:
-- they are read only at a founding.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  update public.standing_routes sr set paused_reason = 'dark'
   where sr.id in (select nf.route_id from public.npc_fleets nf join public.ships s on s.fleet_id = nf.fleet_id join public.ship_classes c on c.id = s.class_id
                    where c.code in ('taforeia', 'retour', 'nao', 'hourque', 'indiaman', 'naucarr'));
  delete from public.npc_fleets nf
   where nf.fleet_id in (select s.fleet_id from public.ships s join public.ship_classes c on c.id = s.class_id
                          where c.code in ('taforeia', 'retour', 'nao', 'hourque', 'indiaman', 'naucarr'));
  get diagnostics v_n = row_count;
  if v_n <> 24 then
    raise exception '0404 rollback refuses: % far-trader fleets on the roster, not 24', v_n;
  end if;
  update public.world_config set value = to_jsonb((value #>> '{}')::int - 24) where key = 'npc_fleet_max';
  raise notice '0404 rollback ok: 24 far-trader fleets off the roster; npc_fleet_max %', public.wc_int('npc_fleet_max');
end
$r$;
