-- 0397 SIM SCENE (run by sim.mjs, once dark and once lit, rolled back each time): every merchant started on her route where she lies and planned ALONE at her
-- lap start through the real planner, public.npc_plan(now(), route); then what the plan wrote is read. "Closed" is public.npc_loop_sea_shut, the planner's own
-- reading of the one rule, asked whatever the switch says, so the dark arm counts the same loops.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
create temp table sim_0397 (fleet_id uuid primary key, route_id uuid, size int, wave numeric, closed_before boolean, loop_before text,
                            plan jsonb, ms numeric, closed_after boolean, loop_after text, buys int, paused text) on commit drop;
do $$
declare
  r   record;
  v_t timestamptz;
  v_p jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  for r in
    select nf.fleet_id, nf.route_id,
           (select max(cp.size) from public.ships s join public.ship_classes c on c.id = s.class_id join public.class_profile cp on cp.class_code = c.code where s.fleet_id = nf.fleet_id) as size,
           (select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course, 'nm', s.course_nm) order by s.ord)
              from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = nf.route_id) as lp
      from public.npc_fleets nf where nf.route_id is not null order by nf.roster_ord /*LIMIT*/
  loop
    insert into sim_0397 (fleet_id, route_id, size, wave, closed_before, loop_before)
    values (r.fleet_id, r.route_id, r.size, public.fleet_wave(r.fleet_id), public.npc_loop_sea_shut(r.fleet_id, r.lp),
            (select string_agg(x->>'code', '-' order by o) from jsonb_array_elements(r.lp) with ordinality t(x, o)));
    v_t := clock_timestamp();
    v_p := public.npc_plan(now(), r.route_id);
    update sim_0397 s set plan = v_p, ms = round(extract(epoch from clock_timestamp() - v_t) * 1000),
           closed_after = public.npc_loop_sea_shut(r.fleet_id,
             (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord) from public.standing_route_stops st where st.route_id = r.route_id)),
           loop_after = (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = r.route_id),
           buys = (select count(*) from public.standing_route_lines l where l.route_id = r.route_id and l.kind = 'BUY'),
           paused = (select sr.paused_reason from public.standing_routes sr where sr.id = r.route_id)
     where s.fleet_id = r.fleet_id;
  end loop;
  raise notice 'first failure, if any: %', (select s.plan->'notes' from sim_0397 s where (s.plan->>'failed')::int > 0 limit 1);
  raise notice 'harbours called at before % after %',
    (select count(distinct c) from sim_0397 q cross join lateral unnest(string_to_array(q.loop_before, '-')) c),
    (select count(distinct c) from sim_0397 q cross join lateral unnest(string_to_array(q.loop_after, '-')) c);
  raise notice 'harbours that lose every caller: %',
    (select string_agg(b.c, ' ' order by b.c) from (select distinct c from sim_0397 q cross join lateral unnest(string_to_array(q.loop_before, '-')) c) b
      where b.c not in (select c from sim_0397 q cross join lateral unnest(string_to_array(q.loop_after, '-')) c));
  raise notice 'stops before % after %; stops at the harbours that lose every caller %',
    (select count(*) from sim_0397 q cross join lateral unnest(string_to_array(q.loop_before, '-')) c),
    (select count(*) from sim_0397 q cross join lateral unnest(string_to_array(q.loop_after, '-')) c),
    (select count(*) from sim_0397 q cross join lateral unnest(string_to_array(q.loop_before, '-')) c
      where c not in (select c2 from sim_0397 q2 cross join lateral unnest(string_to_array(q2.loop_after, '-')) c2));
end $$;
select coalesce(s.size::text, 'all') as hull_size, count(*) as fleets,
       count(*) filter (where closed_before) as closed_before,
       count(*) filter (where loop_after is distinct from loop_before) as moved,
       count(*) filter (where closed_before and loop_after is distinct from loop_before) as closed_and_moved,
       count(*) filter (where closed_after) as closed_after,
       count(*) filter (where buys = 0) as no_buy,
       count(*) filter (where closed_before and buys = 0) as closed_and_no_buy,
       count(*) filter (where paused = 'laid_up') as laid_up,
       count(*) filter (where closed_before and paused = 'laid_up') as closed_and_laid_up,
       count(*) filter (where (plan->>'failed')::int > 0) as failed,
       round(avg(ms)) as plan_ms_avg, max(ms) as plan_ms_max,
       round(avg(ms) filter (where closed_before)) as plan_ms_avg_closed
  from sim_0397 s group by rollup (s.size) order by 1;
