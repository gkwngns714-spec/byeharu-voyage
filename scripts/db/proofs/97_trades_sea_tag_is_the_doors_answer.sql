-- ═════════════════════════════════════════════════════════════════════════════════════
-- PROOF 97 - TRADE'S SEA TAG IS THE DOOR'S OWN ANSWER  (migration 0402; docs/SEA_CONDITIONS_AND_REGIONS.md 10.6, row S7)
--
--   Two real companies founded here and rolled back, each a title-1 barca: one of Portugal moved to lie at Acapulco (a far sea: the way home), one of
--   Japan at her capital (a far power at home: home waters). For each, the real world.good_board of three goods, dark and then lit. Every buy row and
--   every sell row is taken apart into its legs (where she sails from, its stops, the city) and each leg is asked of the door's own judge
--   (public.sea_judge with her floors from public.sea_floor, what public.sea_gate asks) over the seas of the leg's pair row and its destination's sea.
--   Since 0403 a pair row holds the seas of the course a fleet really sails, not of the straight line: that the row is the plotted course's seas, and
--   that public.sea_gate on that very course answers as the tag does, is proof 98's. Nothing here depends on which goods the market
--   favours or on the world's secret: the goods are three her harbour's roster sells (world data), first by code, and every row served is checked.
--
-- @pass TAG_FAR_FLEET   lit, lying at Acapulco: every board row is shut exactly when the door refuses one of its legs; a row of one leg wears the door's refusal to the letter; rows the plain rule would shut are open (the way home) and seas of another rank are shut still
-- @pass TAG_FAR_POWER   lit, a company of Japan at her capital: the same, row for row (home waters)
-- @pass TAG_DARK        dark, for both companies every row's tag is the plain rule's reading, recomputed here from public.sea_leg_asks and public.sea_refusal without public.sea_routes: the text it was before 0402
-- ═════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_a constant uuid := '00000000-0402-4000-8000-0000000000a1';
  c_j constant uuid := '00000000-0402-4000-8000-0000000000b1';
  v_pl    uuid;
  v_fl    uuid;
  v_port  uuid;
  v_ocode text;
  v_title int;
  v_wave  numeric;
  v_b     jsonb;
  v_r     jsonb;
  v_co    text;
  v_lit   boolean;
  v_off   boolean;
  gd      record;
  v_rows  int;
  v_one   int;
  v_bad   text;
  v_open  int;
  v_shut  int;
  v_dark  int := 0;
begin
  if to_regprocedure('public.sea_routes(uuid,integer,numeric,jsonb)') is null or to_regprocedure('public.sea_routes(integer,numeric,jsonb)') is not null then
    raise exception 'PROOF 97 FAIL: 0402 is not in this world';
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('sea_conditions_bite', 'economy_closed');
  create temp table r97 (id int generated always as identity primary key, co text, lit boolean, good text, side text, port text, route jsonb, tag jsonb) on commit drop;
  create temp table x97 (id int primary key, legs int, shut boolean, gate jsonb, plain jsonb) on commit drop;

  foreach v_co in array array['FAR_FLEET', 'FAR_POWER'] loop
    if v_co = 'FAR_FLEET' then
      v_pl := public.new_house(c_a, 'Casa Etiqueta 97', 'PRT', 'LIS', 'Etiqueta', 'barca', 'Etiqueta', null, false);
      update public.fleets set port_id = (select id from public.ports where code = 'ACA') where player_id = v_pl;
      perform cmd.assume_identity(c_a);
    else
      perform cmd.assume_identity(c_j);
      v_r := cmd.found_house('Casa Etiqueta Longe 97', 'JPN');
      v_pl := (v_r ->> 'player_id')::uuid;
    end if;
    select f.id, f.port_id, p.code into v_fl, v_port, v_ocode from public.fleets f join public.ports p on p.id = f.port_id where f.player_id = v_pl;
    v_title := public.title_level(v_pl);
    v_wave := public.fleet_wave(v_fl);
    if v_fl is null or v_title <> 1 or v_wave <> 12
       or (select z.title_min from public.sea_zones z where z.code = public.harbour_zone(v_port)) <= 1 then
      raise exception 'PROOF 97 FAIL: % is not a title-1 barca lying in a sea that asks a title (she lies at %, title %, wave %)', v_co, v_ocode, v_title, v_wave;
    end if;

    -- the boards, dark and then lit: every row with the route it serves
    foreach v_lit in array array[false, true] loop
      update public.world_config set value = to_jsonb(v_lit) where key = 'sea_conditions_bite';
      for gd in select g.id, g.code from public.goods g order by public.port_offers(v_port, g.id) desc, g.code limit 3 loop
        v_off := public.port_offers(v_port, gd.id);   -- bought where she lies, a sell row's route is its own stops; else only the buy rows are read
        v_b := world.good_board(gd.id, v_fl, case when v_off then v_port end, null);
        insert into r97 (co, lit, good, side, port, route, tag)
        select v_co, v_lit, gd.code, s.side, e ->> 'port',
               public.sea_route_stops(v_ocode, case when jsonb_typeof(e -> 'miles') = 'number' then e -> 'stops' end, e ->> 'port'), e -> 'sea'
          from (values ('buy'), ('sell')) s(side)
         cross join lateral jsonb_array_elements(v_b -> s.side) e
         where s.side = 'buy' or v_off;
      end loop;
    end loop;

    -- every leg of every row, asked ONCE of the door's judge (lit) for this fleet over the seas of its pair row; and the plain rule's reading, recomputed
    with leg as (
      select q.id, q.a, q.b from (select r.id, x.code as a, lead(x.code) over (partition by r.id order by x.k) as b
                                    from r97 r cross join lateral jsonb_array_elements_text(r.route) with ordinality x(code, k) where r.co = v_co) q
       where q.b is not null and q.a <> q.b),
    door as materialized (
      select d.a, d.b, public.sea_judge(v_title, v_wave, s.zones || public.harbour_zone(rb.port_id), fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) as gate
        from (select distinct l.a, l.b from leg l) d join public.sea_reaches ra on ra.code = d.a join public.sea_reaches rb on rb.code = d.b
        join public.sea_leg_asks s on s.from_port = ra.port_id and s.to_port = rb.port_id
       cross join (select * from public.sea_floor(v_fl, null) offset 0) fl),
    asks as (
      select l.id, s.title_min, s.wave_min,
             case when s.title_min > greatest(za.title_min, zb.title_min) or s.wave_min > greatest(za.wave_min, zb.wave_min) then s.zones else array[za.code, zb.code] end as zones
        from leg l join public.sea_reaches ra on ra.code = l.a join public.sea_reaches rb on rb.code = l.b
        join public.sea_leg_asks s on s.from_port = ra.port_id and s.to_port = rb.port_id
        join public.sea_zones za on za.code = public.harbour_zone(ra.port_id) join public.sea_zones zb on zb.code = public.harbour_zone(rb.port_id)),
    plain as (
      select p.id, p.needs_title, p.needs_wave, p.zones, public.sea_refusal(v_title, v_wave, p.zones) as refusal
        from (select a.id, max(a.title_min) as needs_title, max(a.wave_min) as needs_wave, (select array_agg(distinct z) from asks a2 cross join unnest(a2.zones) z where a2.id = a.id) as zones
                from asks a group by a.id) p)
    insert into x97 (id, legs, shut, gate, plain)
    select r.id, (select count(*) from leg l where l.id = r.id),
           coalesce((select bool_or(d.gate is not null) from leg l join door d on d.a = l.a and d.b = l.b where l.id = r.id), false),
           (select min(d.gate::text)::jsonb from leg l join door d on d.a = l.a and d.b = l.b where l.id = r.id),
           (select jsonb_build_object('zone', coalesce(p.refusal -> 'figures' ->> 'zone', t.code), 'zone_name', coalesce(p.refusal -> 'figures' ->> 'zone_name', t.name),
                                      'needs_title', p.needs_title, 'needs_wave', p.needs_wave, 'refusal', p.refusal)
              from plain p cross join lateral (select z.code, z.name from public.sea_zones z where z.code = any (p.zones) order by z.title_min desc, z.wave_min desc, z.ord limit 1) t
             where p.id = r.id)
      from r97 r where r.co = v_co;

    -- LIT: the tag is the door's answer
    select count(*), count(*) filter (where x.legs = 1),
           string_agg(r.good || ' ' || r.side || ' ' || r.port, ', ') filter (where
             case when x.legs = 0 then r.tag <> 'null'::jsonb
                  when x.legs = 1 then nullif(r.tag -> 'refusal', 'null'::jsonb) is distinct from x.gate
                  else (nullif(r.tag -> 'refusal', 'null'::jsonb) is not null) <> x.shut end),
           count(*) filter (where x.legs > 0 and not x.shut and nullif(x.plain -> 'refusal', 'null'::jsonb) is not null),
           count(*) filter (where x.shut)
      into v_rows, v_one, v_bad, v_open, v_shut
      from r97 r join x97 x on x.id = r.id where r.co = v_co and r.lit;
    if v_rows < 100 or v_one < 20 or v_bad is not null or v_open < 1 or v_shut < 1 then
      raise exception 'PROOF 97 FAIL: % lit, at %: of % rows (% of one leg) these wear a tag that is not the door''s answer: %; opened % (want 1 or more), shut % (want 1 or more)',
        v_co, v_ocode, v_rows, v_one, left(coalesce(v_bad, 'none'), 600), v_open, v_shut;
    end if;
    raise notice 'PASS: TAG_% — lit, at %: all % board rows (% of one leg, to the letter) wear the door''s own answer; % that the plain rule shuts are open to her, % are shut still',
      v_co, v_ocode, v_rows, v_one, v_open, v_shut;

    -- DARK: the tag is the plain rule's reading, the text it was
    select string_agg(r.good || ' ' || r.side || ' ' || r.port, ', ') into v_bad
      from r97 r join x97 x on x.id = r.id
     where r.co = v_co and not r.lit and r.tag is distinct from case when x.legs = 0 then 'null'::jsonb else x.plain end;
    if v_bad is not null then
      raise exception 'PROOF 97 FAIL: % dark, at %: these rows'' tags are not the plain rule''s reading: %', v_co, v_ocode, left(v_bad, 600);
    end if;
    v_dark := v_dark + (select count(*) from r97 r where r.co = v_co and not r.lit);
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    perform cmd.assume_identity(null);
  end loop;
  raise notice 'PASS: TAG_DARK — dark, all % rows of both companies wear the plain rule''s reading, recomputed without public.sea_routes', v_dark;
end $$;
