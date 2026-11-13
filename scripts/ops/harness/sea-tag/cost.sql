-- cost.sql: WHAT THE TAG COSTS A BOARD, before and after 0402. LOCAL ONLY (the cached world; it founds a probe company and turns the switch, so it never
-- runs on prod).   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-conditions/run.mjs --apply=0400,0401,0402 scripts/ops/harness/sea-tag/cost.sql
-- It keeps the pre-image by reversing 0402's hunks under pg_temp names, then times, lit, turn about: the tag alone on the 249 direct routes of a board,
-- and the whole board of four goods, for a title-1 barca of Portugal at Lisbon and lying at Acapulco. Notices only.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_uid constant uuid := '00000000-0402-4000-8000-0000000000c1';
  v_pl uuid; v_fl uuid; v_lis uuid; v_aca uuid := (select id from public.ports where code = 'ACA');
  v_def text; v_routes jsonb; v_x jsonb; v_t timestamptz; gd record; i int; v_place text;
  a numeric; b numeric; c numeric; d numeric; v_sets_old int; v_sets_new int;
begin
  v_def := replace(pg_get_functiondef('public.sea_routes(uuid,integer,numeric,jsonb)'::regprocedure), E'\r', '');
  v_def := replace(v_def, 'FUNCTION public.sea_routes(p_fleet uuid, ', 'FUNCTION pg_temp.sea_routes_old(');
  v_def := replace(v_def, 'public.sea_conditions_on()', 'false');   -- the dark branches are the pre-image's reading
  v_def := replace(v_def, 'public.sea_floor(p_fleet, null)', 'public.sea_floor(null, null)');
  execute v_def;
  execute replace(replace(replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), E'\r', ''), 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_old('),
                  'public.sea_routes(p_fleet, ', 'pg_temp.sea_routes_old(');
  v_pl := public.new_house(c_uid, 'Casa do Custo 0402', 'PRT', 'LIS', 'Custo', 'barca', 'Custo', null, false);
  select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  foreach v_place in array array['LIS', 'ACA'] loop
    update public.fleets set port_id = case v_place when 'LIS' then v_lis else v_aca end where id = v_fl;
    v_routes := (select jsonb_agg(jsonb_build_array(v_place, p.code) order by p.code) from public.ports p where p.kind = 'HARBOUR');
    a := 0; b := 0; c := 0; d := 0;
    for i in 1 .. 30 loop
      v_t := clock_timestamp(); v_x := pg_temp.sea_routes_old(1, 12, v_routes); a := a + extract(epoch from clock_timestamp() - v_t) * 1000;
      v_t := clock_timestamp(); v_x := public.sea_routes(v_fl, 1, 12, v_routes); b := b + extract(epoch from clock_timestamp() - v_t) * 1000;
    end loop;
    for i in 1 .. 5 loop
      for gd in select g.id from public.goods g order by g.code limit 4 loop
        v_t := clock_timestamp(); v_x := pg_temp.good_board_old(gd.id, v_fl, null, null); c := c + extract(epoch from clock_timestamp() - v_t) * 1000;
        v_t := clock_timestamp(); v_x := world.good_board(gd.id, v_fl, null, null); d := d + extract(epoch from clock_timestamp() - v_t) * 1000;
      end loop;
    end loop;
    raise notice 'at %: the tag on 249 direct routes % ms before, % ms after (mean of 30); a board % ms before, % ms after (mean of 20): % %%',
      v_place, round(a / 30, 2), round(b / 30, 2), round(c / 20, 1), round(d / 20, 1), round((d - c) * 100 / c, 1);
  end loop;
end $$;
