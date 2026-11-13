-- 0402 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). It puts the three-argument public.sea_routes back (the live body with 0402's three hunks reversed), puts the
-- board's two calls back, and drops the four-argument function. A Trade row's tag is then the plain rule's again: rows in her home waters and in the
-- rank of the sea she lies in may say Shut while the door lets her sail (the gap 0402 closed). Safe lit or dark; no table and no switch is touched.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h     record;
  v_def text;
  f     text;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.sea_routes(uuid,integer,numeric,jsonb)') is null or to_regprocedure('public.sea_routes(integer,numeric,jsonb)') is not null then
    raise exception '0402 rollback refuses: 0402 is not applied in this world';
  end if;
  create temp table hunks_back (ord int, fn text, old text, new text) on commit drop;
  insert into hunks_back values
  (1, 'public.sea_routes(uuid,integer,numeric,jsonb)', $h$FUNCTION public.sea_routes(p_title integer, p_wave numeric, p_routes jsonb)
$h$, $h$FUNCTION public.sea_routes(p_fleet uuid, p_title integer, p_wave numeric, p_routes jsonb)
$h$),
  (2, 'public.sea_routes(uuid,integer,numeric,jsonb)', $h$           case when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$, $h$           -- 0402: LIT, a leg brings what the door asks on that line (public.sea_gate): the line's zones and the zone of the harbour she makes for
           case when public.sea_conditions_on() then s.zones || hb.zone
                when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$),
  (3, 'public.sea_routes(uuid,integer,numeric,jsonb)', $h$  judged as materialized (
    select r.i, r.needs_title, r.needs_wave, r.zones, v.refusal
      from route r
      join (select d.zones, public.sea_refusal(p_title, p_wave, d.zones) as refusal
              from (select distinct zones from route) d) v on v.zones is not distinct from r.zones)
$h$, $h$  -- 0402: LIT, THE DOOR'S OWN ANSWER FOR THE FLEET IN HAND. Each DISTINCT SEA of the board is asked once of public.sea_judge with her two floors
  -- (public.sea_floor, read once a call); a route wears the answer of the first of its seas that refuses, in the judge's own order (the seas of
  -- another rank than both floors, then of the rank she lies in, then of her capital's; requirement order within each). Nothing is judged here.
  seen as materialized (
    select z.code as zone, z.ord, case when z.title_min = fl.title_min then 1 when z.title_min = fl.home_title then 2 else 0 end as lot,
           public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) as refusal
      from (select distinct o.zone from zone_of o where public.sea_conditions_on()) d
      join public.sea_zones z on z.code = d.zone
     cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl),
  -- Dark, the plain rule once per distinct set of seas, as before (the tag is then a reading).
  judged as materialized (
    select r.i, r.needs_title, r.needs_wave, r.zones,
           case when public.sea_conditions_on()
                then (select s.refusal from seen s where s.zone = any (r.zones) and s.refusal is not null order by s.lot, s.ord limit 1)
                else v.refusal end as refusal
      from route r
      left join (select d.zones, public.sea_refusal(p_title, p_wave, d.zones) as refusal
                   from (select distinct zones from route where not public.sea_conditions_on()) d) v on v.zones is not distinct from r.zones)
$h$),
  (4, 'world.good_board(uuid,uuid,uuid,numeric)', $h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when$h$, $h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when$h$),
  (5, 'world.good_board(uuid,uuid,uuid,numeric)', $h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)$h$, $h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)$h$);
  foreach f in array array['public.sea_routes(uuid,integer,numeric,jsonb)', 'world.good_board(uuid,uuid,uuid,numeric)'] loop
    v_def := replace(pg_get_functiondef(f::regprocedure), E'', '');
    for h in select * from hunks_back b where b.fn = f order by b.ord desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0402 rollback FAIL: hunk % of % is not in the live body once', h.ord, f;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    execute v_def;
  end loop;
  revoke all on function public.sea_routes(integer, numeric, jsonb) from public, anon, authenticated;
  comment on function public.sea_routes(integer, numeric, jsonb) is
    '0219: what each route''s seas ask (needs from public.sea_leg_asks, the verdict from public.sea_refusal over the route''s zones). Read by world.good_board. Server-only.';
  drop function public.sea_routes(uuid, integer, numeric, jsonb);
  if exists (select 1 from pg_proc p where p.prosrc like '%sea_routes(p_fleet%') then
    raise exception '0402 rollback FAIL: a body still passes the fleet to the tag';
  end if;
  raise notice '0402 rolled back: the tag is the plain rule''s reading again';
end $r$;
