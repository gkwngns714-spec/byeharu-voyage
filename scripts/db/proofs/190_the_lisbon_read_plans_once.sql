-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 190 - THE LISBON READ PLANS ONCE  (migration 0487; docs/dev-log/2026-11-24-lisbon-read.md)
--
--   0487 turned 27 small SQL readers into plpgsql with their SQL body word for word, so PostgreSQL 17 keeps their plans. The migration's
--   self-assert compared the readers and the Lisbon read's pieces for a newcomer at Lisbon before and after. This proof turns the 27
--   BACK into SQL inside its own transaction (each body unwrapped from its 0487 wrapper: exactly the function 0487 found) and compares
--   again, at Seville and at Lisbon with a captain seated, with the switches as they are and lit.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: world.best_sales is never asked; its sameness is its pieces' (world.board_legs,
--   world.board_sell, public.fleet_buy_capacity, world.daily_cap_remaining, world.quote, public.port_fee, public.profit_tax).
--
-- @pass PO_PLPGSQL   each of the 27 readers is plpgsql, its body the 0487 wrapper around its SQL body, which has the md5 0487 found
-- @pass PO_READERS   the 27 readers answer the same as their SQL selves over their inputs, with the switches as they are and lit
-- @pass PO_PIECES    the Lisbon read's pieces answer the same with the readers in plpgsql and in SQL, at Seville and at Lisbon with a captain seated
-- @pass PO_COST      the pieces timed both ways on this server (PGlite is PostgreSQL 18, which caches a SQL body's plan: no gain is expected here)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- 0536 moved the arithmetic of voyage.stores_need_days; this proof is of the 27 as 0487 wrote them, so it goes back to 0487's text here
CREATE OR REPLACE FUNCTION voyage.stores_need_days(p_nm numeric, p_speed numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
begin
  -- 0487: plpgsql so its plan is kept for the session (PostgreSQL 17 plans a SQL body again at every call); the body is its SQL body, word for word
  return (
  -- 0203: THE DAYS OF STORES A PASSAGE OF p_nm AT p_speed ASKS — its days at sea at endurance_margin. The
  -- sail door (voyage.sail_refusal: E_ENDURANCE when her casks hold fewer), the desk (world.good_board's
  -- `sailable`) and the planner (public.npc_leg_days) read it; there is no other copy.
  select ((p_nm / p_speed) / 24) * public.wc_num('endurance_margin')

  );
end
$function$
;
create function pg_temp.p190_wrap(p_src text, p_set boolean) returns text language sql immutable as $w$
  select E'\n#variable_conflict use_column\nbegin\n'
         || E'  -- 0487: plpgsql so its plan is kept for the session (PostgreSQL 17 plans a SQL body again at every call); the body is its SQL body, word for word\n'
         || case when p_set then '  return query' else '  return (' end
         || p_src
         || case when p_set then E'\n  ;\nend\n' else E'\n  );\nend\n' end
$w$;

-- the SQL body inside a reader's 0487 wrapper (null when the body is not that wrapper)
create function pg_temp.p190_body(p_fn regprocedure) returns text language plpgsql as $b$
declare
  v_src text;
  v_set boolean;
  v_pre int;
  v_body text;
begin
  select p.prosrc, p.proretset into v_src, v_set from pg_proc p where p.oid = p_fn;
  v_pre := length(pg_temp.p190_wrap('', v_set)) - case when v_set then length(E'\n  ;\nend\n') else length(E'\n  );\nend\n') end;
  v_body := substr(v_src, v_pre + 1, length(v_src) - length(pg_temp.p190_wrap('', v_set)));
  return case when pg_temp.p190_wrap(v_body, v_set) = v_src then v_body end;
end $b$;

-- a reader back to SQL: its live definition, LANGUAGE plpgsql -> sql and the wrapper -> the body
create function pg_temp.p190_to_sql(p_fn regprocedure) returns void language plpgsql as $s$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_src text := (select p.prosrc from pg_proc p where p.oid = p_fn);
begin
  execute replace(replace(v_def, E'\n LANGUAGE plpgsql\n', E'\n LANGUAGE sql\n'), v_src, pg_temp.p190_body(p_fn));
end $s$;

create function pg_temp.p190_readers(p_player uuid, p_fleet uuid) returns jsonb language plpgsql as $g$
declare
  v_ats   timestamptz[] := array[now(), now() - interval '3 days 7 hours', now() + interval '11 hours 13 minutes', now() - interval '40 days',
                                 '2026-01-01 00:00:00+00'::timestamptz, '2026-08-18 12:34:56.789+00'::timestamptz];
  v_parts jsonb := voyage.fleet_speed_parts(p_fleet);
  v_hulls jsonb := world.trip_hulls(p_fleet);
begin
  return jsonb_build_object(
    'switches', jsonb_build_array(public.economy_closed(), public.city_treasury_on(), public.ship_stores_separate(), public.regard_on(),
                                  public.world_events_on(), public.nation_race_on(), public.price_impact_lit(), public.wants_lit(), public.pirates_on()),
    'harbours', (select jsonb_agg(jsonb_build_array(p.code, public.port_is_free(p.id), public.pirate_home(p.id), public.world_event_toll(p.id),
                                                    public.treasury_balance(p.id), public.city_bid_factor(p.id),
                                                    public.works_factor(p.id, 'market', 'market_cap_per_level')) order by p.code)
                   from public.ports p),
    'houses', (select jsonb_agg(jsonb_build_array(h.id, public.crown_house(h.id), public.running_cost_mult(h.id)) order by h.id nulls last)
                 from (select pl.id from public.players pl union select null::uuid) h),
    'bands', (select jsonb_agg(jsonb_build_array(z.s, public.regard_band(z.s)) order by z.k)
                from (select s::numeric / 2 as s, s as k from generate_series(-2400, 2400, 7) s union all select null, 999999) z),
    'hold', (select jsonb_agg(public.stores_in_hold(t) order by t nulls first) from unnest(array[null, 0, 0.25, 1.5, 100, 1e6]::numeric[]) t),
    'need', (select jsonb_agg(jsonb_build_array(n, s, voyage.stores_need_days(n, s), public.npc_leg_days(n, s), public.npc_leg_days(null, s),
                                                public.npc_leg_days(n, null), public.npc_leg_days(n, 0)) order by n, s)
               from unnest(array[0, 1, 33.3, 120.5, 999, 2000, 12000]::numeric[]) n cross join unnest(array[0.1, 1, 5, 7.25, 12, 40]::numeric[]) s),
    'speed', jsonb_build_object(
               'hers', (select jsonb_agg(jsonb_build_array(f, voyage.fleet_speed_of(v_parts, f, null), voyage.fleet_speed_of(v_parts, f, v_hulls)) order by f nulls first)
                          from unnest(array[null, 0, 0.1, 0.5, 0.9, 1]::numeric[]) f),
               'fleets', (select jsonb_agg(jsonb_build_array(x.id, voyage.fleet_speed_of(voyage.fleet_speed_parts(x.id), null, null),
                                                             voyage.fleet_speed_of(voyage.fleet_speed_parts(x.id), 1, world.trip_hulls(x.id))) order by x.id)
                            from (select fl.id from public.fleets fl where exists (select 1 from public.ships s where s.fleet_id = fl.id)) x)),
    'clock', (select jsonb_agg(jsonb_build_array(k, a.i, public.clock_count(k, a.t)) order by k, a.i)
                from unnest(array['game_day', 'drift_slot', 'want_period', 'population_slot']) k
               cross join unnest(v_ats) with ordinality a(t, i)),
    'periods', (select jsonb_agg(jsonb_build_array(a.i, public.want_period(a.t), world.game_day(a.t)) order by a.i) from unnest(v_ats) with ordinality a(t, i)),
    'game_day', world.game_day(),
    'wants', (select jsonb_agg(jsonb_build_array(h.code, gd.code,
                                                 (select jsonb_agg(to_jsonb(w)) from world.want_left(h.id, gd.id) w),
                                                 (select jsonb_agg(to_jsonb(e)) from public.event_want(h.id, gd.id) e)) order by h.code, gd.code)
                from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                       where p.k % 4 = 1) h
               cross join (select g.id, g.code from public.goods g order by g.code limit 40) gd));
end $g$;

create function pg_temp.p190_pieces(p_player uuid, p_fleet uuid) returns jsonb language plpgsql as $q$
declare
  v_at   uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_code text := (select p.code from public.ports p where p.id = v_at);
  v_o    jsonb;
  v_ctx  jsonb;
  v_legs jsonb;
  v_out  jsonb := '{}'::jsonb;
  g      record;
  a      record;
begin
  v_o := world.board_origin(p_fleet);
  v_o := v_o || jsonb_build_object('trip_fleet', p_fleet, 'trip_hulls', world.trip_hulls(p_fleet), 'speed_parts', voyage.fleet_speed_parts(p_fleet));
  for g in
    select gd.id, gd.code from public.port_goods pg join public.goods gd on gd.id = pg.good_id
     where pg.port_id = v_at and public.port_offers(v_at, gd.id) order by gd.code
  loop
    select * into a from world.board_amount(p_fleet, g.id, null);
    v_ctx := v_o || jsonb_build_object(
               'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
               'src', jsonb_build_object('code', case when a.basis <> 'on_board' then v_code end),
               'src_cut', false, 'src_name', null, 'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', null);
    if v_legs is null then
      v_legs := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
      v_out := v_out || jsonb_build_object('legs', (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(v_legs) e));
    end if;
    v_out := v_out || jsonb_build_object('sell:' || g.code, world.board_sell(g.id, p_fleet, v_ctx || jsonb_build_object('legs', v_legs)),
                                         'trips:' || g.code, (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(
                                            world.board_trips(p_fleet, v_ctx || jsonb_build_object('buy', jsonb_build_object('units', 20, 'bulk', 1.5)), v_legs)) e),
                                         'cap:' || g.code, public.fleet_buy_capacity(p_fleet, g.id),
                                         'day:' || g.code, world.daily_cap_remaining(p_player, v_at, g.id));
  end loop;
  return v_out || jsonb_build_object(
    'quotes', (select jsonb_agg(jsonb_build_array(h.code, gd.code, q1, q2) order by h.code, gd.code)
                 from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                        where p.k % 5 = 1) h
                cross join (select g2.id, g2.code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                             where pg.port_id = v_at and public.port_offers(v_at, g2.id)) gd
                cross join lateral (select to_jsonb(q) as q1 from world.quote(h.id, gd.id, 37, 'sell', null, p_fleet) q) s1
                cross join lateral (select to_jsonb(q) as q2 from world.quote(h.id, gd.id, 11, 'buy', null, p_fleet) q) s2),
    'fees', (select jsonb_agg(jsonb_build_array(p.code, public.port_fee(p.id, p_player, 1000), public.port_fee(p.id, p_player, 0),
                                                public.port_fee(p.id, p_player, 123456), public.profit_tax(p.id, 1000, p_player),
                                                public.profit_tax(p.id, -5, p_player)) order by p.code)
               from public.ports p where p.kind = 'HARBOUR'));
end $q$;

do $p$
declare
  c_b     constant uuid := '00000000-0190-4000-8000-0000000001b1';
  c_c     constant uuid := '00000000-0190-4000-8000-0000000001c1';
  c_lit   constant text[] := array['economy_closed', 'city_treasury_enabled', 'city_wants', 'world_events_enabled', 'regard_enabled',
                                   'nation_race_enabled', 'price_impact', 'pirates_bite', 'pirate_ports_free', 'ship_stores_separate',
                                   'influence_enabled', 'logbook_enabled', 'goods_mastery_enabled', 'first_hour_enabled',
                                   'near_choice_enabled', 'levels_bite'];
  v_b     uuid;
  v_c     uuid;
  v_fb    uuid;
  v_fc    uuid;
  v_bad   text;
  v_k     text;
  v_was   jsonb := '{}'::jsonb;
  v_rd    jsonb;  v_rl jsonb;  v_pb jsonb;  v_pc jsonb;
  v_t     timestamptz;
  v_ms_pl numeric;
  v_ms_sq numeric;
  v_n     int;
  x       record;
begin
  -- PO_PLPGSQL
  create temp table p190_readers (ord int primary key, fn text not null, md5 text not null) on commit drop;
  insert into p190_readers (ord, fn, md5) values
    ( 1, 'public.economy_closed()', 'f78659ae4bc972be757c25e547999998'),
    ( 2, 'public.city_treasury_on()', 'edd922cbf5b7607570875c75d5e397d7'),
    ( 3, 'public.ship_stores_separate()', '072701313c80ebe489aa48f33c9ac796'),
    ( 4, 'public.regard_on()', 'f9cf5e1d0a4829bed73d03bf6c33fdf6'),
    ( 5, 'public.world_events_on()', '50d4f15eb8420cb18fa0143b308441b7'),
    ( 6, 'public.nation_race_on()', '195db19c46e348717cc068b5baee4fc1'),
    ( 7, 'public.price_impact_lit()', '9bdfe0755be06ae0656721dfb0557b17'),
    ( 8, 'public.wants_lit()', '893a420aa27485b9e57d9158fd618d88'),
    ( 9, 'public.pirates_on()', '0f8e3252470d2a95c5ffd53d49b41360'),
    (10, 'public.port_is_free(uuid)', '689788fa761e94f4ffeb6830dcdc8d02'),
    (11, 'public.pirate_home(uuid)', '8436e15a58f06b6901ddee450af0d970'),
    (12, 'public.crown_house(uuid)', '16a77f26c77c1f3e9b555b5fec0baf46'),
    (13, 'public.running_cost_mult(uuid)', '15dbe5b056ace091e5df3f9019d039fc'),
    (14, 'public.world_event_toll(uuid)', 'fcff32019e25dd77566bd46cb0af8567'),
    (15, 'public.treasury_balance(uuid)', '707eeee39e6223a034e3ac608bee6a98'),
    (16, 'public.city_bid_factor(uuid)', '37200d1406b2aebfdcdf1c6fac30d895'),
    (17, 'public.works_factor(uuid,text,text)', '7909a61c0169eb81a8ff37155d4fb335'),
    (18, 'public.regard_band(numeric)', '9f6fce83cdddf59b13599cac020216b0'),
    (19, 'public.stores_in_hold(numeric)', '5c520d9a77929ddbeb8a864f9ee29783'),
    (20, 'voyage.stores_need_days(numeric,numeric)', 'cc09a0b1ae180130219ccd6d32a52372'),
    (21, 'public.npc_leg_days(numeric,numeric)', '3fdfe3d1c09b7d1145fddbfdd2a2de41'),
    (22, 'voyage.fleet_speed_of(jsonb,numeric,jsonb)', '0a9afd9784bdb8078fbeb2fe9a2d94ad'),
    (23, 'public.clock_count(text,timestamp with time zone)', 'a558fe09fcec00c3b572c83fb19c0d15'),
    (24, 'public.want_period(timestamp with time zone)', '1c09bbed1321d26e6702aa8e059895f7'),
    (25, 'world.game_day(timestamp with time zone)', '4e02e28f964ad51a6019ee83d44d64fe'),
    (26, 'public.event_want(uuid,uuid)', '4eb6272ceb04bac48be6769877c25e0d'),
    (27, 'world.want_left(uuid,uuid)', '008e3f6bdb30d75c745bdee667714a4c');
  select string_agg(r.fn, ', ' order by r.ord) into v_bad
    from p190_readers r join pg_proc p on p.oid = to_regprocedure(r.fn) join pg_language l on l.oid = p.prolang
   where l.lanname <> 'plpgsql' or not p.prosecdef or p.proconfig is distinct from array['search_path=public, pg_temp'] or p.provolatile <> 's'
      or md5(replace(pg_temp.p190_body(p.oid::regprocedure), E'\r', '')) is distinct from r.md5;
  if v_bad is not null or (select count(*) from p190_readers r where to_regprocedure(r.fn) is not null) <> 27 then
    raise exception 'PO_PLPGSQL: not plpgsql, or not the 0487 wrapper around the SQL body 0487 found: %', v_bad;
  end if;
  raise notice 'PASS: PO_PLPGSQL — 27 readers in plpgsql, each the 0487 wrapper around the SQL body 0487 found (md5 for md5), definer, search path and STABLE kept';

  -- the companies: B at Seville, C at Lisbon with a captain seated (proof 185's)
  v_b := public.new_house(c_b, 'Casa de Sevilla 190', 'ESP', 'SVQ');
  v_c := public.new_house(c_c, 'Casa do Piloto 190', 'PRT');
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.id into v_fc from public.fleets f where f.player_id = v_c;
  update public.players p set ducats = 60000 where p.id in (v_b, v_c);
  declare
    v_po uuid;
    o record;
  begin
    for o in select ox.id from public.officers ox join public.captain_profile cp on cp.officer_id = ox.id order by ox.code limit 1 loop
      insert into public.player_officers (player_id, officer_id) values (v_c, o.id) returning id into v_po;
      insert into public.captain_active (player_officer_id, trait) select v_po, ct.trait from public.captain_traits ct where ct.officer_id = o.id on conflict do nothing;
      perform public.captain_seat_put(v_po, (select s.id from public.ships s where s.fleet_id = v_fc order by s.is_flagship desc, s.id limit 1), 1);
    end loop;
  end;

  -- plpgsql (as 0487 left them): the readers as the switches are, then lit; the pieces lit, timed
  perform cmd.assume_identity(c_c);
  v_rd := pg_temp.p190_readers(v_c, v_fc);
  foreach v_k in array c_lit loop
    if exists (select 1 from public.world_config c where c.key = v_k and c.value is distinct from 'true'::jsonb) then
      v_was := v_was || jsonb_build_object(v_k, (select c.value from public.world_config c where c.key = v_k));
      update public.world_config c set value = 'true'::jsonb where c.key = v_k;
    end if;
  end loop;
  v_rl := pg_temp.p190_readers(v_c, v_fc);
  perform cmd.assume_identity(c_b);
  v_pb := pg_temp.p190_pieces(v_b, v_fb);
  perform cmd.assume_identity(c_c);
  v_t := clock_timestamp();
  v_pc := pg_temp.p190_pieces(v_c, v_fc);
  v_ms_pl := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);

  -- the 27 back to SQL (the functions 0487 found), then everything again
  for x in select r.fn from p190_readers r order by r.ord loop
    perform pg_temp.p190_to_sql(x.fn::regprocedure);
  end loop;
  if exists (select 1 from p190_readers r join pg_proc p on p.oid = to_regprocedure(r.fn) join pg_language l on l.oid = p.prolang
              where l.lanname <> 'sql' or md5(replace(p.prosrc, E'\r', '')) <> r.md5) then
    raise exception 'PO_READERS: a reader did not go back to the SQL body 0487 found';
  end if;

  perform cmd.assume_identity(c_c);
  if pg_temp.p190_readers(v_c, v_fc) is distinct from v_rl then
    raise exception 'PO_READERS: a reader answers differently lit: %',
      (select string_agg(k, ', ') from jsonb_object_keys(v_rl) k where v_rl->k is distinct from pg_temp.p190_readers(v_c, v_fc)->k);
  end if;
  v_t := clock_timestamp();
  if pg_temp.p190_pieces(v_c, v_fc) is distinct from v_pc then
    raise exception 'PO_PIECES: a piece answers differently at Lisbon with a captain';
  end if;
  v_ms_sq := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
  perform cmd.assume_identity(c_b);
  if pg_temp.p190_pieces(v_b, v_fb) is distinct from v_pb then
    raise exception 'PO_PIECES: a piece answers differently at Seville';
  end if;
  update public.world_config c set value = v_was->c.key where v_was ? c.key;
  perform cmd.assume_identity(c_c);
  if pg_temp.p190_readers(v_c, v_fc) is distinct from v_rd then
    raise exception 'PO_READERS: a reader answers differently with the switches as they are';
  end if;
  if jsonb_array_length(v_rl->'wants') = 0 or jsonb_array_length(v_rl->'houses') < 10 or jsonb_array_length(v_pc->'quotes') = 0 then
    raise exception 'PO_READERS: the inputs were empty';
  end if;
  raise notice 'PASS: PO_READERS — the 27 answer as their SQL selves: % harbours, % houses, % regard scores, % stores and speeds, % fleets, % clock readings, % wants; the switches as they are and lit',
    jsonb_array_length(v_rl->'harbours'), jsonb_array_length(v_rl->'houses'), jsonb_array_length(v_rl->'bands'), jsonb_array_length(v_rl->'need'),
    jsonb_array_length(v_rl->'speed'->'fleets'), jsonb_array_length(v_rl->'clock'), jsonb_array_length(v_rl->'wants');

  select count(*) into v_n from (select jsonb_object_keys(v_pb) union all select jsonb_object_keys(v_pc)) k(k) where k.k like 'sell:%';
  if v_n < 4 then
    raise exception 'PO_PIECES: only % goods compared', v_n;
  end if;
  raise notice 'PASS: PO_PIECES — board_legs, and board_sell, board_trips, buy capacity and day cap for % goods; % quotes both ways; the dock fee and profit tax at % harbours: the same in plpgsql and in SQL (Seville; Lisbon with a captain seated; lit)',
    v_n, jsonb_array_length(v_pb->'quotes') + jsonb_array_length(v_pc->'quotes'), jsonb_array_length(v_pc->'fees');
  raise notice 'PASS: PO_COST — the pieces at Lisbon with a captain: % ms with the readers in plpgsql, % ms in SQL (server %)', v_ms_pl, v_ms_sq, current_setting('server_version');
end $p$;
