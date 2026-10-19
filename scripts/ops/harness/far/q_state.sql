begin transaction read only;
select json_build_object(
 'at', now(), 'game_day', world.game_day(),
 'rows', (select json_agg(json_build_array(p.code, g.code, pg.stock, pg.stock_target, pg.drift, pg.season_mod, pg.glut, pg.last_regen_day, pg.production_rate, pg.haul, pg.demand, pg.affinity))
            from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id),
 'treasury', (select json_agg(json_build_array(p.code, public.treasury_balance(p.id))) from public.port_treasury t join public.ports p on p.id = t.port_id),
 'dev', (select json_agg(json_build_array(p.code, p.dev_commerce)) from public.ports p),
 'wc', (select json_object_agg(key, value) from public.world_config)
) j;
