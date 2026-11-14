-- 0425 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- Gives public.navy_hunt_step back its 0423 body (the hunk reversed, checked once) and the two knobs their 0423 values.
-- The knobs alone are the quick way back for the cargo half: convoy_load_max 1000000, convoy_loads_per_run 10. The navy hunk only ever cuts a
-- lie down to the knob's own length; reversing it brings back nothing but lies longer than the knob.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  c_fn  constant text := 'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)';
  v_def text := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  v_old text :=
$h$  if n.mission = 'HUNT' and n.hunt_port = p_port then
    if n.hunt_until is not null and n.hunt_until > p_now then
      return 'HUNTING';
$h$;
  v_new text :=
$h$  if n.mission = 'HUNT' and n.hunt_port = p_port then
    -- 0425: A LIE IS NEVER LONGER THAN THE KNOB SAYS NOW. One written under an older, longer navy_hunt_hours (0423 moved 6 h to 225 s and left
    -- the rows) is cut to now + navy_hunt_hours; at her own station with navy_own_sea_patrol on it ends now, and she picks again below (her own
    -- sea: her patrol, under sail). A lie written under the live knob is never shortened.
    if n.hunt_until is not null and n.hunt_until > p_now
       and ((p_port = p_home and public.wc('navy_own_sea_patrol') = 'true'::jsonb)
            or n.hunt_until > p_now + make_interval(secs => (v_hours * 3600)::double precision)) then
      n.hunt_until := case when p_port = p_home and public.wc('navy_own_sea_patrol') = 'true'::jsonb then p_now
                           else p_now + make_interval(secs => (v_hours * 3600)::double precision) end;
      update public.navy_ships x set hunt_until = n.hunt_until where x.fleet_id = p_fleet;
    end if;
    if n.hunt_until is not null and n.hunt_until > p_now then
      return 'HUNTING';
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception 'rollback-0425 refuses: 0425''s hunk is not in the live body once';
  end if;
  execute replace(v_def, v_new, v_old);
  update public.world_config set value = to_jsonb(1000000) where key = 'convoy_load_max' and value = to_jsonb(250000);
  update public.world_config set value = to_jsonb(10) where key = 'convoy_loads_per_run' and value = to_jsonb(20);
  raise notice 'rollback-0425 ok: navy_hunt_step is 0423''s again; convoy_load_max %, convoy_loads_per_run %',
    public.wc_int('convoy_load_max'), public.wc_int('convoy_loads_per_run');
end $r$;
