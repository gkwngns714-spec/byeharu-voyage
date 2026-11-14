-- 0412 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). FIRST, WITH NO FILE: level_skills_on false stops every grant at once (the page then shows the seven levels as
-- not counted; what was earned is kept).
-- This draft takes the hooks out: the nine bodies go back to their text before 0412 (each hunk's NEW text must occur once, else it refuses: a later file
-- re-cut that line and the draft is stale). The four tables, the six functions and the knob are LEFT in place and unread: experience already earned is
-- not taken back, and Reputation already given for a level stays given. world.levels() stops serving level_skills, so the CLIENT must go back first (the
-- Levels page reads it): revert the client commit, let it publish, then deploy this.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0412 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0412 values
  (1, 'voyage.settle(uuid,timestamp with time zone)',
$h$      perform public.reputation_arrival(f.player_id, v.id);
      -- 0412: and her company's levels raised by doing: days fed, storms and rough days come through (public.level_arrival)
      perform public.level_arrival(f.player_id, v.id);
$h$,
$h$      perform public.reputation_arrival(f.player_id, v.id);
$h$),
  (2, 'cmd.do_build(uuid,jsonb)',
$h$  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object('class', c.code));
  perform public.level_grant(f.player_id, 'hull', 1, 'hull:' || v_ship);   -- 0412: Shipbuilding, once a ship
$h$,
$h$  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object('class', c.code));
$h$),
  (3, 'cmd.do_repair(uuid,jsonb)',
$h$  perform public.level_grant(f.player_id, 'repair', v_cost);   -- 0412: Shipbuilding, by the coin the yard was paid (a merchant leaves after one players probe)
  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
$h$,
$h$  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
$h$),
  (4, 'cmd.run_fulfil(uuid,uuid)',
$h$  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object('port', v_port.code, 'good', g.code));
  perform public.level_grant(f.player_id, 'request', v_pay);   -- 0412: Requests, by the bonus this delivery was paid
$h$,
$h$  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object('port', v_port.code, 'good', g.code));
$h$),
  (5, 'cmd.do_make(uuid,jsonb)',
$h$    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));
  perform public.level_grant(f.player_id, 'made', v_qty);   -- 0412: Craft, by the fittings made
$h$,
$h$    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));
$h$),
  (6, 'cmd.forge_good(uuid,uuid,integer)',
$h$      'product', v_product.name, 'qty', v_qty, 'spent', v_spent));
    perform public.level_grant(v_player, 'forged', v_qty);   -- 0412: Craft, by the goods forged
$h$,
$h$      'product', v_product.name, 'qty', v_qty, 'spent', v_spent));
$h$),
  (7, 'cmd.standing_route_close_lap(uuid,timestamp with time zone)',
$h$  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);
  perform public.level_grant(sr.player_id, 'lap', case when l.net > 0 then 1 else 0 end, 'lap:' || l.id);   -- 0412: Routes, once a lap at a gain (no gain: 0 units, and the writer leaves before any read)
$h$,
$h$  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);
$h$),
  (8, 'public.invest_for(uuid,uuid,text,integer)',
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
  perform public.level_grant(p_player, 'share', v_cost);   -- 0412: Investment, by the coin paid for shares (a merchant leaves after one players probe)
$h$,
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
$h$),
  (9, 'world.levels()',
$h$    'bite', public.levels_bite_on(),
    -- 0412: every level, raised by doing: points, the curve, activities, benefits, recent grants (public.level_skills_card, on the progress read above)
    'level_skills', public.level_skills_card(v_id, v_pp),
$h$,
$h$    'bite', public.levels_bite_on(),
$h$);
  for h in select * from back_0412 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0412 rollback: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('cmd', 'voyage', 'world') and (p.prosrc like '%level\_grant(%' or p.prosrc like '%level\_arrival(%' or p.prosrc like '%level\_skills\_card(%')) then
    raise exception '0412 rollback: a door still names the levels';
  end if;
  raise notice '0412 rollback ok: nine hooks out, level_skills_on false; the tables, the functions and what was earned are left in place.';
end $r$;
