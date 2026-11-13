-- cost.sql: WHAT A BOARD COSTS, run before and after 0403 (a plotted course crosses more seas than a straight line with the land left out, so a row holds more).
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-conditions/run.mjs --apply=0400,0401,0402[,0403] scripts/ops/harness/pair-table/cost.sql
-- Lit, a title-1 barca of Portugal at Lisbon and lying at Acapulco: the tag alone on the 249 direct routes (mean of 30), a whole board of four goods (mean of 20). Notices only.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_uid constant uuid := '00000000-0403-4000-8000-0000000000c1';
  v_pl uuid; v_fl uuid; v_lis uuid; v_aca uuid := (select id from public.ports where code = 'ACA');
  v_routes jsonb; v_x jsonb; v_t timestamptz; gd record; i int; v_place text; b numeric; d numeric;
begin
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  v_pl := public.new_house(c_uid, 'Casa do Custo 0403', 'PRT', 'LIS', 'Custo', 'barca', 'Custo', null, false);
  select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  foreach v_place in array array['LIS', 'ACA'] loop
    update public.fleets set port_id = (select x.id from (values ('LIS', v_lis), ('ACA', v_aca)) x(k, id) where x.k = v_place) where id = v_fl;
    v_routes := (select jsonb_agg(jsonb_build_array(v_place, p.code) order by p.code) from public.ports p where p.kind = 'HARBOUR');
    b := 0; d := 0;
    for i in 1 .. 30 loop
      v_t := clock_timestamp(); v_x := public.sea_routes(v_fl, 1, 12, v_routes); b := b + extract(epoch from clock_timestamp() - v_t) * 1000;
    end loop;
    for i in 1 .. 5 loop
      for gd in select g.id from public.goods g order by g.code limit 4 loop
        v_t := clock_timestamp(); v_x := world.good_board(gd.id, v_fl, null, null); d := d + extract(epoch from clock_timestamp() - v_t) * 1000;
      end loop;
    end loop;
    raise notice 'at %: the tag on 249 direct routes % ms (mean of 30); a board % ms (mean of 20); mean seas a row: %',
      v_place, round(b / 30, 2), round(d / 20, 1), (select round(avg(cardinality(zones)), 2) from public.sea_leg_asks);
  end loop;
end $$;
