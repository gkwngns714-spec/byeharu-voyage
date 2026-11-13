-- 0402 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-tag/before-0402.sql
-- Wanted, five rows (the five hunks): every old_times 1, every new_times 0, every volatility s, fleet_tag_in false, plain_tag_in true,
-- tag_readers "world.good_board(uuid,uuid,uuid,numeric)" alone, floors_of_0396_in true, sea_conditions_bite true, news_rows 0, HEAD IT MEETS: 20260818000401.
-- The hunks are the migration's own, to the letter. No game function is called: the catalog and two tables are read.
begin transaction read only;
with h(ord, fn, old, new) as (values
  (1, 'public.sea_routes(integer,numeric,jsonb)'::text, $h$FUNCTION public.sea_routes(p_title integer, p_wave numeric, p_routes jsonb)
$h$, $h$FUNCTION public.sea_routes(p_fleet uuid, p_title integer, p_wave numeric, p_routes jsonb)
$h$),
  (2, 'public.sea_routes(integer,numeric,jsonb)'::text, $h$           case when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$, $h$           -- 0402: LIT, a leg brings what the door asks on that line (public.sea_gate): the line's zones and the zone of the harbour she makes for
           case when public.sea_conditions_on() then s.zones || hb.zone
                when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$),
  (3, 'public.sea_routes(integer,numeric,jsonb)'::text, $h$  judged as materialized (
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
  (4, 'world.good_board(uuid,uuid,uuid,numeric)'::text, $h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when$h$, $h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when$h$),
  (5, 'world.good_board(uuid,uuid,uuid,numeric)'::text, $h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)$h$, $h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)$h$)
), d as (
  select h.*, replace(pg_get_functiondef(to_regprocedure(h.fn)), chr(13), '') as def, (select p.provolatile from pg_proc p where p.oid = to_regprocedure(h.fn)) as volatility from h
)
select d.ord, d.fn,
       (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old) as old_times,
       (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new) as new_times,
       d.volatility,
       (to_regprocedure('public.sea_routes(uuid,integer,numeric,jsonb)') is not null) as fleet_tag_in,
       (to_regprocedure('public.sea_routes(integer,numeric,jsonb)') is not null) as plain_tag_in,
       (select string_agg(p.oid::regprocedure::text, ' ' order by 1) from pg_proc p where p.prosrc like '%public.sea_routes(%') as tag_readers,
       (to_regprocedure('public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)') is not null and to_regprocedure('public.sea_floor(uuid,jsonb)') is not null) as floors_of_0396_in,
       (select c.value from public.world_config c where c.key = 'sea_conditions_bite') as sea_conditions_bite,
       (select count(*) from public.world_news n where n.key = 'update:0402') as news_rows,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from d order by d.ord;
commit;
