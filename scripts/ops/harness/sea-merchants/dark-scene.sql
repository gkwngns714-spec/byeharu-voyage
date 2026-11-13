-- 0392 PARITY SCENE: run by proof-0392.mjs on the world BEFORE the file and AFTER it, rolled back each time, with sea_conditions_bite_npc FALSE (as shipped).
-- It names only what existed before 0392 and reads what the merchants' sea rule must NOT change while dark: the loops offered to every fourth merchant of the
-- roster (public.npc_loop_candidates, the one caller of the re-cut public.npc_feasible_legs), and a REAL plan pass (public.npc_plan, each merchant alone at her
-- lap start) over 60 merchants spread over the roster: every stop, course and line it wrote and its counters. Every SCENE line must be equal before and after.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  v_txt text;
  r     record;
  v_p   jsonb;
  v_sum jsonb := '{}'::jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  select md5(string_agg(x.line, ';' order by x.line)) into v_txt
    from (select nf.roster_ord || ':' || coalesce((select string_agg(c.kind || '=' || md5(c.stops::text), ',' order by c.kind, c.stops::text)
                                                    from public.npc_loop_candidates(nf.route_id, nf.fleet_id, h.home_port_id, public.fleet_free_hold(nf.fleet_id),
                                                                                    greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1)) c), '-') as line
            from public.npc_houses h join public.npc_fleets nf on nf.player_id = h.player_id
           where nf.route_id is not null and nf.roster_ord % 4 = 0) x;
  raise notice 'SCENE: LOOPS %', v_txt;
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null from public.npc_fleets nf where nf.route_id = sr.id;
  for r in select nf.route_id from public.npc_fleets nf where nf.route_id is not null and nf.roster_ord % 14 = 3 order by nf.roster_ord limit 60 loop
    v_p := public.npc_plan(now(), r.route_id);
    v_sum := jsonb_build_object('planned', coalesce((v_sum->>'planned')::int, 0) + (v_p->>'planned')::int, 'ballast', coalesce((v_sum->>'ballast')::int, 0) + (v_p->>'ballast')::int,
                                'chosen', coalesce((v_sum->>'chosen')::int, 0) + (v_p->>'chosen')::int, 'candidates', coalesce((v_sum->>'candidates')::int, 0) + (v_p->>'candidates')::int,
                                'waiting', coalesce((v_sum->>'waiting')::int, 0) + (v_p->>'waiting')::int, 'failed', coalesce((v_sum->>'failed')::int, 0) + (v_p->>'failed')::int);
  end loop;
  raise notice 'SCENE: PLAN COUNTERS %', v_sum;
  raise notice 'SCENE: PLAN STOPS %', (select md5(string_agg(st.route_id::text || ':' || st.ord || ':' || st.port_id::text || ':' || md5(st.course::text) || ':' || coalesce(st.course_nm::text, '-') || ':' || st.repair || ':' || st.crew_up, ';'
                                                              order by st.route_id, st.ord))
                                         from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id where nf.roster_ord % 14 = 3);
  raise notice 'SCENE: PLAN LINES %', (select md5(string_agg(l.route_id::text || ':' || l.stop_ord || ':' || l.ord || ':' || l.kind || ':' || coalesce(l.good_id::text, '-') || ':' || coalesce(l.qty::text, '-') || ':' || coalesce(l.price_limit::text, '-') || ':' || coalesce(l.at_profit::text, '-'), ';'
                                                              order by l.route_id, l.stop_ord, l.ord))
                                         from public.standing_route_lines l join public.npc_fleets nf on nf.route_id = l.route_id where nf.roster_ord % 14 = 3);
  raise notice 'SCENE: ROUTES %', (select md5(string_agg(sr.id::text || ':' || coalesce(sr.paused_reason, '-') || ':' || coalesce(sr.laps_per_game_day::text, '-'), ';' order by sr.id))
                                     from public.standing_routes sr join public.npc_fleets nf on nf.route_id = sr.id where nf.roster_ord % 14 = 3);
  raise notice 'SCENE: PRESETS %', (select md5(string_agg(f.id::text || ':' || coalesce(pr.days::text, '-'), ';' order by f.id))
                                      from public.fleets f join public.npc_fleets nf on nf.fleet_id = f.id left join public.provision_presets pr on pr.id = f.provision_preset_id where nf.roster_ord % 14 = 3);
end $$;
