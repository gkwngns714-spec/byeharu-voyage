-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0487 - THE LISBON READ PLANS ONCE  (no switch; the same answers: 27 small SQL readers on the trade read's path become plpgsql with
--        their SQL body word for word, so PostgreSQL 17 keeps their plans instead of planning them again at every call)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE WORK: docs/dev-log/2026-11-24-lisbon-read.md; harness scripts/ops/harness/lisbon-read/ (before-0487.sql, after-0487.sql).
--
-- WHY: world.best_sales at Lisbon takes 2.5-2.7 s on prod (its own 2.5 s budget often cuts it); the HQ board (world.hq_board ->
--   public.hq_board_for) and the standing fleet jobs wait on it, so HQ opens in about 3 s. The same call on the local PGlite takes 0.3-0.4 s.
--   0482 cached the reach matrix and read the hulls once: -20 % locally, almost nothing on prod.
--
-- WHAT PROD SHOWED (three read-only reads, 2026-11-24; numbers in the dev-log):
--   * NOT THE DISK. One Lisbon best_sales: 100,094 buffer hits, 993 reads (1 %); pg_stat_statements over 208 board calls: mean 2,271 ms,
--     33,600 hits and 525 reads a call. port_goods' dead rows cost little: every Lisbon good's 254 market rows in 1.7 ms each.
--   * THE CPU, IN SMALL CALLS. Prod pays about 7x local for each of the read's ~30,000 small function calls (wc 24 us a call; a sell
--     quote 3.95 ms; port_fee 1.25 ms; profit_tax 0.58 ms). And one piece pays 26x: world.want_left, 1.87 ms a call on prod (72 us
--     locally), asked by EVERY sell quote of a market row a want was ever drawn on (155 a Lisbon read).
--   * WHY THE 26x, AND WHY LOCAL NEVER SHOWED IT: prod runs PostgreSQL 17.6, the local PGlite 18.3. PostgreSQL 17 PLANS A SQL-LANGUAGE
--     FUNCTION'S BODY AGAIN AT EVERY CALL made from inside a query (a SECURITY DEFINER function with SET search_path is never inlined, and
--     its plan lives only as long as the calling query's run); PostgreSQL 18 keeps it in the plan cache. world.want_left is SQL and asks
--     five more SQL functions (public.wants_lit, public.want_period twice, public.event_want, and through them public.clock_count,
--     public.economy_closed, public.world_events_on): ten plannings a call. A Lisbon read makes about 9,000 such SQL calls.
--     plpgsql keeps each statement's plan for the session (PostgREST's pooled sessions live long), so the planning is paid once.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse it):
--   THE 27 READERS, each LANGUAGE sql, STABLE, SECURITY DEFINER, SET search_path = public, pg_temp, not STRICT (asserted, with the md5 of
--   its body, before anything is changed: another body refuses the whole file):
--     the switches  public.economy_closed, city_treasury_on, ship_stores_separate, regard_on, world_events_on, nation_race_on,
--                   price_impact_lit, wants_lit, pirates_on
--     a harbour's   public.port_is_free, pirate_home, world_event_toll, treasury_balance, city_bid_factor, works_factor
--     a house's     public.crown_house, running_cost_mult;  public.regard_band
--     the stores    public.stores_in_hold, voyage.stores_need_days, public.npc_leg_days, voyage.fleet_speed_of
--     the clock     public.clock_count, public.want_period, world.game_day
--     the wants     public.event_want, world.want_left
--   Chosen as every SQL reader of that kind a Lisbon read calls 15 times or more (traced on the chain with prod's switches lit).
--   EACH BECOMES plpgsql BY ONE RULE, from its own live definition (pg_get_functiondef): LANGUAGE sql -> LANGUAGE plpgsql, and the body
--     <body>  ->  #variable_conflict use_column / begin / -- 0487 line / return (<body>\n  ); / end       (a scalar)
--     <body>  ->  #variable_conflict use_column / begin / -- 0487 line / return query <body>\n  ; / end   (a set: event_want, want_left)
--   The body is kept WORD FOR WORD (asserted: the new body reverses to the old one, md5 for md5). Its name, arguments and defaults, return
--   type, STABLE, SECURITY DEFINER, SET search_path, owner and grants are untouched (CREATE OR REPLACE keeps them; asserted).
--   Why the same answers: every body is ONE select that gives one row (no FROM, an aggregate, EXISTS, or LIMIT 1) or, for the two sets,
--   the rows it gives; `return (select ...)` answers that row's value (null for none), `return query` those rows in that order.
--   `#variable_conflict use_column` is SQL's own rule (a column of the query wins over an argument of the same name). The snapshot is the
--   caller's in both (STABLE); now() is the transaction's.
--   NOTHING ELSE MOVES (asserted: every other function of public, cmd, world and voyage has the md5 it had). No table, no row, no knob,
--   no grant, no cron job, no new function (so nothing to revoke from service_role; asserted that no client role and no service_role
--   can execute any of the 27 that could not before).
--
-- THE SELF-ASSERT (one DO block; the probe rolled back by a raised sentinel):
--   THE PROBE: a house at Lisbon, her identity set; the switches the read reads lit for the probe (only where not already on: on prod they
--   are). BEFORE (SQL) and AFTER (plpgsql, converted inside the probe by the same rule), compared to the byte:
--     the 27 readers over their inputs (every harbour; houses: hers, 40, 20 merchants, crown, navy and pirate houses; regard scores
--     -1000..1000; stores and speeds; four clocks at five instants; the wants of every 16th harbour for every good Lisbon sells), with the
--     switches as they are and lit;
--     the Lisbon read's pieces, lit: world.board_legs, world.board_sell for every good Lisbon sells (the read's own context),
--     public.fleet_buy_capacity and world.daily_cap_remaining for each, world.quote of each at every 16th harbour, public.port_fee and
--     public.profit_tax at every harbour.
--   Timed both ways (the pieces, after the readers warmed every plan): the notice says it. world.best_sales itself (time-budgeted) is
--   never asked: its sameness is its pieces'.
--   Then the conversion for real, asserted equal to the one the probe tried, and the catalog checks above. Budget 60 s.
--
-- LOAD: no rows, no tables, no cron, no beat step. Every caller of the 27 (the beat, the voyages, the trade, HQ) gets the same answers.
-- ROLLBACK (forward): a migration that writes each of the 27 back as LANGUAGE sql with the body inside its 0487 wrapper (the self-assert
--   proves the wrapper reverses to it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- THE RULE, as a function of this session only (dropped at the end): wrap a SQL body
create function pg_temp.wrap_0487(p_src text, p_set boolean) returns text language sql immutable as $w$
  select E'\n#variable_conflict use_column\nbegin\n'
         || E'  -- 0487: plpgsql so its plan is kept for the session (PostgreSQL 17 plans a SQL body again at every call); the body is its SQL body, word for word\n'
         || case when p_set then '  return query' else '  return (' end
         || p_src
         || case when p_set then E'\n  ;\nend\n' else E'\n  );\nend\n' end
$w$;

-- THE CONVERSION of one reader, from its live definition; answers its new body
create function pg_temp.plan_once_0487(p_fn regprocedure) returns text language plpgsql as $c$
declare
  v_src  text;
  v_set  boolean;
  v_def  text;
  v_new  text;
  c_sql  constant text := E'\n LANGUAGE sql\n';
begin
  select p.prosrc, p.proretset into v_src, v_set from pg_proc p where p.oid = p_fn;
  v_def := pg_get_functiondef(p_fn);
  if (length(v_def) - length(replace(v_def, c_sql, ''))) / length(c_sql) <> 1
     or (length(v_def) - length(replace(v_def, v_src, ''))) / length(v_src) <> 1 then
    raise exception '0487 self-assert FAIL: % does not show LANGUAGE sql and its body once each', p_fn;
  end if;
  v_new := replace(replace(v_def, c_sql, E'\n LANGUAGE plpgsql\n'), v_src, pg_temp.wrap_0487(v_src, v_set));
  execute v_new;
  return (select p.prosrc from pg_proc p where p.oid = p_fn);
end $c$;

-- THE 27 READERS' INPUTS AND ANSWERS (for the comparison; read only)
create function pg_temp.readers_0487(p_player uuid, p_fleet uuid) returns jsonb language plpgsql as $g$
declare
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_ats   timestamptz[] := array[now(), now() - interval '3 days 7 hours', now() + interval '11 hours 13 minutes',
                                 '2026-01-01 00:00:00+00'::timestamptz, '2026-08-18 12:34:56.789+00'::timestamptz];
  v_parts jsonb := voyage.fleet_speed_parts(p_fleet);
  v_hulls jsonb := world.trip_hulls(p_fleet);
begin
  return jsonb_build_object(
    'switches', jsonb_build_array(public.economy_closed(), public.city_treasury_on(), public.ship_stores_separate(), public.regard_on(),
                                  public.world_events_on(), public.nation_race_on(), public.price_impact_lit(), public.wants_lit(),
                                  public.pirates_on()),
    'harbours', (select jsonb_agg(jsonb_build_array(p.code, public.port_is_free(p.id), public.pirate_home(p.id), public.world_event_toll(p.id),
                                                    public.treasury_balance(p.id), public.city_bid_factor(p.id),
                                                    public.works_factor(p.id, 'market', 'market_cap_per_level')) order by p.code)
                   from public.ports p where p.kind = 'HARBOUR'),
    'houses', (select jsonb_agg(jsonb_build_array(h.id, public.crown_house(h.id), public.running_cost_mult(h.id)) order by h.id nulls last)
                 from (select p_player as id
                       union select x.id from (select pl.id from public.players pl order by pl.id limit 40) x
                       union select x.id from (select pl.id from public.players pl where pl.is_npc order by pl.id limit 20) x
                       union select x.player_id from (select c.player_id from public.cargo_ships c order by c.player_id limit 5) x
                       union select x.player_id from (select n.player_id from public.navy_ships n order by n.player_id limit 5) x
                       union select x.player_id from (select s.player_id from public.pirate_ships s order by s.player_id limit 5) x
                       union select null::uuid) h),
    'bands', (select jsonb_agg(jsonb_build_array(z.s, public.regard_band(z.s)) order by z.k)
                from (select s::numeric as s, s as k from generate_series(-1000, 1000, 25) s
                      union all select -149.5, 2001 union all select 149.49, 2002 union all select null, 2003) z),
    'hold', jsonb_build_array(public.stores_in_hold(null), public.stores_in_hold(0), public.stores_in_hold(1.5), public.stores_in_hold(100)),
    'need', (select jsonb_agg(jsonb_build_array(n, s, voyage.stores_need_days(n, s), public.npc_leg_days(n, s), public.npc_leg_days(null, s),
                                                public.npc_leg_days(n, null), public.npc_leg_days(n, 0)) order by n, s)
               from unnest(array[0, 1, 120.5, 2000]::numeric[]) n cross join unnest(array[0.1, 5, 7.25, 12]::numeric[]) s),
    'speed', jsonb_build_object(
               'hers', (select jsonb_agg(jsonb_build_array(f, voyage.fleet_speed_of(v_parts, f, null), voyage.fleet_speed_of(v_parts, f, v_hulls)) order by f nulls first)
                          from unnest(array[null, 0, 0.5, 1]::numeric[]) f),
               'fleets', (select jsonb_agg(jsonb_build_array(x.id, voyage.fleet_speed_of(voyage.fleet_speed_parts(x.id), null, null)) order by x.id)
                            from (select fl.id from public.fleets fl where exists (select 1 from public.ships s where s.fleet_id = fl.id)
                                   order by fl.id limit 20) x)),
    'clock', (select jsonb_agg(jsonb_build_array(k, a.i, public.clock_count(k, a.t)) order by k, a.i)
                from unnest(array['game_day', 'drift_slot', 'want_period', 'population_slot']) k
               cross join unnest(v_ats) with ordinality a(t, i)),
    'periods', (select jsonb_agg(jsonb_build_array(a.i, public.want_period(a.t), world.game_day(a.t)) order by a.i) from unnest(v_ats) with ordinality a(t, i)),
    'game_day', world.game_day(),
    'wants', (select jsonb_agg(jsonb_build_array(h.code, gd.code,
                                                 (select jsonb_agg(to_jsonb(w)) from world.want_left(h.id, gd.id) w),
                                                 (select jsonb_agg(to_jsonb(e)) from public.event_want(h.id, gd.id) e)) order by h.code, gd.code)
                from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                       where p.k % 16 = 1) h
               cross join (select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
                            where pg.port_id = v_lis and public.port_offers(v_lis, g.id)) gd));
end $g$;

-- THE LISBON READ'S PIECES (world.best_sales' own steps, none time-budgeted; read only)
create function pg_temp.pieces_0487(p_player uuid, p_fleet uuid) returns jsonb language plpgsql as $q$
declare
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
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
     where pg.port_id = v_lis and public.port_offers(v_lis, gd.id) order by gd.code
  loop
    select * into a from world.board_amount(p_fleet, g.id, null);
    v_ctx := v_o || jsonb_build_object(
               'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
               'src', jsonb_build_object('code', case when a.basis <> 'on_board' then 'LIS' end),
               'src_cut', false, 'src_name', case when a.basis <> 'on_board' then 'Lisbon' end,
               'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', null);
    if v_legs is null then
      v_legs := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
      -- board_legs answers a row a harbour in no fixed order (its readers join by id): kept by id
      v_out := v_out || jsonb_build_object('legs', (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(v_legs) e));
    end if;
    v_out := v_out || jsonb_build_object('sell:' || g.code, world.board_sell(g.id, p_fleet, v_ctx || jsonb_build_object('legs', v_legs)),
                                         'cap:' || g.code, public.fleet_buy_capacity(p_fleet, g.id),
                                         'day:' || g.code, world.daily_cap_remaining(p_player, v_lis, g.id));
  end loop;
  return v_out || jsonb_build_object(
    'quotes', (select jsonb_agg(jsonb_build_array(h.code, gd.code, to_jsonb(q)) order by h.code, gd.code)
                 from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                        where p.k % 16 = 1) h
                cross join (select g2.id, g2.code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                             where pg.port_id = v_lis and public.port_offers(v_lis, g2.id)) gd
                cross join lateral world.quote(h.id, gd.id, 20, 'sell', null, p_fleet) q
                where exists (select 1 from public.port_goods x where x.port_id = h.id and x.good_id = gd.id)),
    'fees', (select jsonb_agg(jsonb_build_array(p.code, public.port_fee(p.id, p_player, 1000), public.port_fee(p.id, p_player, 0),
                                                public.profit_tax(p.id, 1000, p_player)) order by p.code)
               from public.ports p where p.kind = 'HARBOUR'));
end $q$;

do $m$
declare
  c_ua    constant uuid := '00000000-0487-4000-8000-0000000004a1';
  v_t0    timestamptz := clock_timestamp();
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_fn_before text;
  v_meta  text;
  v_priv  text;
  v_a     uuid;
  v_fa    uuid;
  v_lit   text[] := '{}';
  v_was   jsonb := '{}'::jsonb;
  v_k     text;
  v_rc0   jsonb;  v_rl0 jsonb;  v_pc0 jsonb;
  v_rc1   jsonb;  v_rl1 jsonb;  v_pc1 jsonb;
  v_ms0   numeric;
  v_ms1   numeric;
  v_rms0  numeric;
  v_rms1  numeric;
  v_t     timestamptz;
  v_tried jsonb := '{}'::jsonb;
  v_src   text;
  v_lived boolean := false;
  v_bad   text;
  x       record;
  c_lit   constant text[] := array['economy_closed', 'city_treasury_enabled', 'city_wants', 'world_events_enabled', 'regard_enabled',
                                   'nation_race_enabled', 'price_impact', 'pirates_bite', 'pirate_ports_free', 'ship_stores_separate',
                                   'influence_enabled', 'logbook_enabled', 'goods_mastery_enabled', 'first_hour_enabled',
                                   'near_choice_enabled', 'levels_bite'];
begin
  -- ── 0. THE PRE-IMAGE: the 27 readers as this file was written against them ──
  create temp table readers_0487 (ord int primary key, fn text not null, md5 text not null) on commit drop;
  insert into readers_0487 (ord, fn, md5) values
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
    from readers_0487 r
    left join pg_proc p on p.oid = to_regprocedure(r.fn)
    left join pg_language l on l.oid = p.prolang
   where p.oid is null or l.lanname <> 'sql' or not p.prosecdef or p.proconfig is distinct from array['search_path=public, pg_temp']
      or p.provolatile <> 's' or p.proisstrict or p.prokind <> 'f' or md5(replace(p.prosrc, E'\r', '')) <> r.md5;
  if v_bad is not null then
    raise exception '0487 self-assert FAIL: not the SQL reader this file was written against: %', v_bad;
  end if;
  -- every other function of the four schemas, and the 27's grants, owner, definer, search path, volatility, strictness, arguments and type
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select to_regprocedure(r.fn)::oid from readers_0487 r));
  select md5(string_agg(r.fn || ':' || coalesce(p.proacl::text, '') || ':' || p.proowner::text || ':' || p.prosecdef::text || ':' || coalesce(p.proconfig::text, '')
                        || ':' || p.provolatile::text || p.proisstrict::text || p.proparallel::text || p.proleakproof::text || ':' || p.procost::text || ':' || p.prorows::text
                        || ':' || p.proretset::text || ':' || p.prorettype::text || ':' || p.proargtypes::text || ':' || coalesce(p.proargnames::text, '')
                        || ':' || coalesce(p.proallargtypes::text, '') || ':' || coalesce(p.proargmodes::text, '') || ':' || coalesce(pg_get_expr(p.proargdefaults, 0), ''),
                        ',' order by r.ord))
    into v_meta
    from readers_0487 r join pg_proc p on p.oid = to_regprocedure(r.fn);
  select string_agg(r.fn || ':' || has_function_privilege('anon', r.fn, 'execute')::text || has_function_privilege('authenticated', r.fn, 'execute')::text
                    || has_function_privilege('service_role', r.fn, 'execute')::text, ',' order by r.ord)
    into v_priv from readers_0487 r;

  -- ── 1. THE PROBE, rolled back by a raised sentinel: the readers and the read's pieces before and after, compared and timed ──
  begin
    v_a := public.new_house(c_ua, 'Casa do Plano 0487', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    update public.players p set ducats = 2000000 where p.id = v_a;
    perform cmd.assume_identity(c_ua);
    if (select f.port_id from public.fleets f where f.id = v_fa) is distinct from v_lis then
      raise exception '0487 self-assert FAIL: a Portuguese house does not start at Lisbon';
    end if;

    -- BEFORE (SQL): the readers as the switches are, then lit (only those not already on), then the pieces, timed
    v_rc0 := pg_temp.readers_0487(v_a, v_fa);
    foreach v_k in array c_lit loop
      if exists (select 1 from public.world_config c where c.key = v_k and c.value is distinct from 'true'::jsonb) then
        v_was := v_was || jsonb_build_object(v_k, (select c.value from public.world_config c where c.key = v_k));
        update public.world_config c set value = 'true'::jsonb where c.key = v_k;
        v_lit := v_lit || v_k;
      end if;
    end loop;
    v_t := clock_timestamp();
    v_rl0 := pg_temp.readers_0487(v_a, v_fa);
    v_rms0 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    v_t := clock_timestamp();
    v_pc0 := pg_temp.pieces_0487(v_a, v_fa);
    v_ms0 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);

    -- THE CONVERSION, tried here (rolled back with the probe)
    for x in select r.ord, r.fn from readers_0487 r order by r.ord loop
      v_tried := v_tried || jsonb_build_object(x.fn, md5(pg_temp.plan_once_0487(x.fn::regprocedure)));
    end loop;

    -- AFTER (plpgsql): the readers lit, the pieces timed, then the switches as they were and the readers again; all compared to the byte
    v_t := clock_timestamp();
    v_rl1 := pg_temp.readers_0487(v_a, v_fa);
    v_rms1 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    v_t := clock_timestamp();
    v_pc1 := pg_temp.pieces_0487(v_a, v_fa);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    update public.world_config c set value = v_was->c.key where c.key = any (v_lit);
    v_rc1 := pg_temp.readers_0487(v_a, v_fa);

    if v_rc1 is distinct from v_rc0 then
      raise exception '0487 self-assert FAIL: a reader answers differently (switches as they are): %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_rc0) k where v_rc0->k is distinct from v_rc1->k);
    end if;
    if v_rl1 is distinct from v_rl0 then
      raise exception '0487 self-assert FAIL: a reader answers differently (lit): %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_rl0) k where v_rl0->k is distinct from v_rl1->k);
    end if;
    if v_pc1 is distinct from v_pc0 then
      raise exception '0487 self-assert FAIL: a piece of the Lisbon read answers differently: %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_pc0) k where v_pc0->k is distinct from v_pc1->k);
    end if;
    if (select count(*) from jsonb_object_keys(v_pc0) k where k like 'sell:%') = 0
       or jsonb_array_length(v_rl0->'wants') = 0 or jsonb_array_length(v_pc0->'quotes') = 0 then
      raise exception '0487 self-assert FAIL: the probe compared nothing (Lisbon sells nothing, or no want or quote was asked)';
    end if;
    raise exception using errcode = 'ZX487', message = 'PROBE_ROLLBACK_0487';
  exception when sqlstate 'ZX487' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0487 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0487' or p.auth_uid = c_ua)
     or public.current_player_id() is not null
     or exists (select 1 from readers_0487 r join pg_proc p on p.oid = to_regprocedure(r.fn) join pg_language l on l.oid = p.prolang where l.lanname <> 'sql') then
    raise exception '0487 self-assert FAIL: the probe left something behind';
  end if;

  -- ── 2. THE CONVERSION, for real: the same rule, the same new bodies as the probe tried ──
  for x in select r.ord, r.fn, r.md5 from readers_0487 r order by r.ord loop
    v_src := pg_temp.plan_once_0487(x.fn::regprocedure);
    if md5(v_src) is distinct from v_tried->>x.fn then
      raise exception '0487 self-assert FAIL: % is not the body the probe tried', x.fn;
    end if;
  end loop;

  -- ── 3. SELF-ASSERT: the catalog ──
  -- each reader is plpgsql, and its body reverses to the SQL body it had (md5 for md5)
  select string_agg(r.fn, ', ' order by r.ord) into v_bad
    from readers_0487 r
    join pg_proc p on p.oid = to_regprocedure(r.fn)
    join pg_language l on l.oid = p.prolang
   where l.lanname <> 'plpgsql'
      or left(p.prosrc, length(pg_temp.wrap_0487('', p.proretset)) - case when p.proretset then length(E'\n  ;\nend\n') else length(E'\n  );\nend\n') end)
           <> left(pg_temp.wrap_0487('', p.proretset), length(pg_temp.wrap_0487('', p.proretset)) - case when p.proretset then length(E'\n  ;\nend\n') else length(E'\n  );\nend\n') end)
      or md5(replace(substr(p.prosrc,
                            length(pg_temp.wrap_0487('', p.proretset)) - case when p.proretset then length(E'\n  ;\nend\n') else length(E'\n  );\nend\n') end + 1,
                            length(p.prosrc) - length(pg_temp.wrap_0487('', p.proretset))), E'\r', '')) <> r.md5
      or pg_temp.wrap_0487(substr(p.prosrc,
                                  length(pg_temp.wrap_0487('', p.proretset)) - case when p.proretset then length(E'\n  ;\nend\n') else length(E'\n  );\nend\n') end + 1,
                                  length(p.prosrc) - length(pg_temp.wrap_0487('', p.proretset))), p.proretset) <> p.prosrc;
  if v_bad is not null then
    raise exception '0487 self-assert FAIL: not plpgsql, or the body does not reverse to its SQL body: %', v_bad;
  end if;
  if (select md5(string_agg(r.fn || ':' || coalesce(p.proacl::text, '') || ':' || p.proowner::text || ':' || p.prosecdef::text || ':' || coalesce(p.proconfig::text, '')
                        || ':' || p.provolatile::text || p.proisstrict::text || p.proparallel::text || p.proleakproof::text || ':' || p.procost::text || ':' || p.prorows::text
                        || ':' || p.proretset::text || ':' || p.prorettype::text || ':' || p.proargtypes::text || ':' || coalesce(p.proargnames::text, '')
                        || ':' || coalesce(p.proallargtypes::text, '') || ':' || coalesce(p.proargmodes::text, '') || ':' || coalesce(pg_get_expr(p.proargdefaults, 0), ''),
                        ',' order by r.ord))
        from readers_0487 r join pg_proc p on p.oid = to_regprocedure(r.fn)) is distinct from v_meta then
    raise exception '0487 self-assert FAIL: the grants, owner, definer, search path, volatility, strictness, arguments or type of a reader moved';
  end if;
  -- no client role and no service_role (prod's default ACL grants it EXECUTE on a NEW function; none is new here) can execute what it could not
  if (select string_agg(r.fn || ':' || has_function_privilege('anon', r.fn, 'execute')::text || has_function_privilege('authenticated', r.fn, 'execute')::text
                        || has_function_privilege('service_role', r.fn, 'execute')::text, ',' order by r.ord) from readers_0487 r) is distinct from v_priv then
    raise exception '0487 self-assert FAIL: a role''s right to execute a reader moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select to_regprocedure(r.fn)::oid from readers_0487 r))) is distinct from v_fn_before then
    raise exception '0487 self-assert FAIL: another function moved, or a function was added';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0487 self-assert FAIL: a client write grant appeared';
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0487 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0487 self-assert ok: THE LISBON READ PLANS ONCE. 27 SQL readers are plpgsql, each body its SQL body word for word (reversed md5 for md5); grants, owner, definer, search path, volatility and types unmoved; no other function moved, none added. Probe (rolled back; lit for it: %): the 27 readers over their inputs, as the switches are and lit, and the Lisbon read''s pieces lit (board_legs; board_sell, buy capacity and day cap for % goods; % sell quotes; the dock fee and profit tax at % harbours) the same to the byte before and after. TIMED on this server (%): the pieces % ms before, % ms after; the readers lit % ms before, % ms after. % ms.',
    case when cardinality(v_lit) = 0 then 'none, all on' else array_to_string(v_lit, ' ') end,
    (select count(*) from jsonb_object_keys(v_pc0) k where k like 'sell:%'), jsonb_array_length(v_pc0->'quotes'), jsonb_array_length(v_pc0->'fees'),
    current_setting('server_version'), v_ms0, v_ms1, v_rms0, v_rms1,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

drop function pg_temp.pieces_0487(uuid, uuid);
drop function pg_temp.readers_0487(uuid, uuid);
drop function pg_temp.plan_once_0487(regprocedure);
drop function pg_temp.wrap_0487(text, boolean);
