-- ════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0504 - THE BEST SALES, FASTER  (a repair; no switch, no knob, no table; not one answer moves)
-- ════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD, 2026-11-25: world.best_sales is 2.7 s on prod at Lisbon (Assign, Trade, HQ and the job tick all wait on it). Profiled locally with
--   prod's switches lit (docs/dev-log/2026-11-25-best-sales-fast.md). What repeated:
--   THE PATHFINDER   voyage.reach_passage asked the seas of all 64,516 pairs of harbours, sorted them, and looked at all of them twice more to sail
--                    the few within her reach. Now only legs within her reach are asked, kept as a list, and the next harbour is looked for among
--                    those reached (10 hunks). Same legs, same order, same choice on a tie.
--   THE WALK         a leg of a trip unpacked her hulls from jsonb, read seven knobs and made nine calls. Now her hulls are arrays, the knobs are read
--                    once a trip and a leg is arithmetic (world.trip_leg_of): 0.17 -> 0.02 ms. Each rule has ONE body still, moved whole:
--                    stores_topup_of, stores_need_days_of, stores_cost_of, ship_speed_fill, trip_leg_of; the old names ask it.
--   THE LEGS         every good unpacked 254 legs of 19 columns to price 15 of them (twice, and rebuilt them in the walk). Now the columns a harbour
--                    is ranked by come as arrays (world.legs_rank, once a read), and the rest is read of the rows kept.
-- NOT CHANGED: every knob and switch, every rule, every answer, every client read's shape; world.quote_priced and all a quote reads.
-- THE HUNKS (31; each once in the live body, each reverses). NEW: 10 functions, server only (the arithmetic ones are plain and immutable, so the planner
--   folds them in).
-- ROWS: none. budget: no table, no cron job, no autovacuum or fillfactor change.
-- LOCKS: CREATE FUNCTION x10, CREATE OR REPLACE x9. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 60 s.
-- ROLLBACK (forward): a migration reversing the hunks and dropping the new functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the cut bodies' grants, volatility, definer, search path, settings and owner
--   unmoved; no knob moved. THE PROBE (rolled back; its own company's rows), with what stood before kept under the session's own schema: the top-up, the
--   days of stores and the price of stores over a grid; a leg's walk over a grid of lengths, with and without the top-up; the passages from six harbours
--   with her cap, a short cap and none; each the same text. Her whole read is compared with its clock budgets set off (the old and the new both
--   copied under the session's schema with an hour): the same text. Nothing of the market is judged.
-- news: this file posts its own UPDATE row (public.news_update('0504', ...)).
-- VERSION: 0504, a PLACEHOLDER (after 0503 `assign-fast`).
-- ════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.stores_cost(uuid,numeric,numeric)',
                                    'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)',
                                    'voyage.reach_passage(uuid,uuid,uuid,numeric)',
                                    'voyage.ship_speed_of(jsonb,numeric)',
                                    'voyage.stores_need_days(numeric,numeric)',
                                    'world.best_sales(uuid,uuid)',
                                    'world.board_sell_memo(uuid,uuid,jsonb,jsonb)',
                                    'world.board_trips(uuid,jsonb,jsonb)',
                                    'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)'];
  c_new    constant text[] := array['voyage.ship_speed_fill',
                                    'voyage.stores_need_days_of',
                                    'public.stores_topup_of',
                                    'world.trip_leg_of',
                                    'world.trip_knobs',
                                    'public.stores_cost_terms',
                                    'public.stores_cost_of',
                                    'world.trip_hulls_at',
                                    'world.trip_arrays',
                                    'world.legs_rank'];
  c_chain  constant text[] := array['public.stores_cost(uuid,numeric,numeric)',
                                    'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)',
                                    'voyage.reach_passage(uuid,uuid,uuid,numeric)',
                                    'voyage.ship_speed_of(jsonb,numeric)',
                                    'voyage.stores_need_days(numeric,numeric)',
                                    'world.best_sales(uuid,uuid)',
                                    'world.board_sell_memo(uuid,uuid,jsonb,jsonb)',
                                    'world.board_trips(uuid,jsonb,jsonb)',
                                    'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)',
                                    'voyage.fleet_speed_of(jsonb,numeric,jsonb)',
                                    'public.npc_leg_days(numeric,numeric)',
                                    'world.board_legs(uuid,jsonb)',
                                    'world.board_origin(uuid)',
                                    'world.board_passages(uuid,uuid,uuid,numeric)',
                                    'world.board_sell(uuid,uuid,jsonb)'];
  c_uid    constant uuid := '00000000-0504-4000-8000-00000000bf01';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_me        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_a         jsonb;
  v_b         jsonb;
  v_s         jsonb;
  v_hl        jsonb;
  v_ms0       numeric;
  v_ms1       numeric;
  v_c         timestamptz;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = any (c_new)) then
    raise exception '0504 refuses: it has been applied once';
  end if;
  foreach v_q in array c_hunked loop
    if to_regprocedure(v_q) is null then
      raise exception '0504 refuses: % is not in this world', v_q;
    end if;
  end loop;

  -- ── 1. THE PRE-IMAGES, and what stood before, kept for the probe under the session's schema ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  perform set_config('check_function_bodies', 'off', true);
  foreach v_q in array c_chain loop
    v_def := replace(pg_get_functiondef(v_q::regprocedure), E'\r', '');
    for x in select distinct split_part(u.q, '(', 1) as nm from unnest(c_chain) u(q) loop
      v_def := replace(v_def, x.nm || '(', 'pg_temp.was_0504_' || split_part(x.nm, '.', 2) || '(');
    end loop;
    execute replace(v_def, $q$c_budget  constant interval := interval '2.5 seconds'$q$, $q$c_budget  constant interval := interval '1 hour'$q$);
  end loop;

  -- ── 2. THE NEW PIECES ──
  execute $mk$
create function voyage.ship_speed_fill(p_k numeric, p_fill numeric, p_penalty numeric) returns numeric language sql immutable parallel safe as
$f$ select round(p_k * (1 - p_penalty * p_fill), 4) $f$
  $mk$;

  execute $mk$
create function voyage.stores_need_days_of(p_nm numeric, p_speed numeric, p_margin numeric) returns numeric language sql immutable parallel safe as
$f$ select ((p_nm / p_speed) / 24) * p_margin $f$
  $mk$;

  execute $mk$
create function public.stores_topup_of(p_crew numeric, p_water numeric, p_food numeric, p_room numeric, p_days numeric, p_full numeric, v_w numeric, v_f numeric,
                                                  out water_t numeric, out food_t numeric, out days numeric)
language plpgsql immutable parallel safe as
$body$
declare
  v_cw   numeric;
  v_cf   numeric;
  v_free numeric := greatest(0, coalesce(p_room, 0) - coalesce(p_water, 0) - coalesce(p_food, 0));
  v_dw   numeric;
  v_df   numeric;
  v_max  numeric;
  v_d    numeric;
  v_t    numeric;
begin
  if coalesce(p_crew, 0) <= 0 then
    v_t := greatest(0, least(coalesce(p_room, 0), case when p_days is null then coalesce(p_full, 0) else 0 end)
                       - coalesce(p_water, 0) - coalesce(p_food, 0));
    water_t := round(v_t * v_w / (v_w + v_f), 3);
    food_t  := round(v_t * v_f / (v_w + v_f), 3);
    days    := 9999;
    return;
  end if;
  v_cw := p_crew * v_w;
  v_cf := p_crew * v_f;
  v_dw := coalesce(p_water, 0) / v_cw;
  v_df := coalesce(p_food, 0) / v_cf;
  if v_dw <= v_df then
    v_max := case when v_cw * (v_df - v_dw) >= v_free then v_dw + v_free / v_cw
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  else
    v_max := case when v_cf * (v_dw - v_df) >= v_free then v_df + v_free / v_cf
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  end if;
  v_d := least(coalesce(p_days, least(coalesce(p_room, 0), coalesce(p_full, 0)) / (v_cw + v_cf)), v_max);
  water_t := round(greatest(0, v_cw * v_d - coalesce(p_water, 0)), 3);
  food_t  := round(greatest(0, v_cf * v_d - coalesce(p_food, 0)), 3);
  days    := least((coalesce(p_water, 0) + water_t) / v_cw, (coalesce(p_food, 0) + food_t) / v_cf);
end $body$
  $mk$;

  execute $mk$
create function world.trip_leg_of(p_kn numeric[], p_k numeric[], p_hold numeric[], p_crew numeric[], p_cargo numeric[], p_room numeric[], p_full numeric[],
    p_f numeric, p_min0 numeric, p_mult numeric, p_least numeric, p_water numeric[], p_food numeric[], p_nm numeric, p_top boolean, p_sea numeric,
    out o_water numeric[], out o_food numeric[], out water_t numeric, out food_t numeric, out sea_days numeric, out sail_days numeric)
language plpgsql immutable parallel safe as
$body$
-- p_kn: load_speed_penalty, endurance_margin, water_per_crew_day, food_per_crew_day
declare
  n   int := coalesce(cardinality(p_crew), 0);
  i   int;
  v_s numeric;
  v_x numeric;
  v_top numeric;
  t   record;
begin
  o_water := p_water;
  o_food := p_food;
  water_t := 0;
  food_t := 0;
  if p_top then
    v_s := p_min0;
    for i in 1 .. n loop
      if p_k[i] is not null then
        v_s := least(v_s, voyage.ship_speed_fill(p_k[i], least(1.0, (p_cargo[i] + o_water[i] + o_food[i]) / p_hold[i]), p_kn[1]));
      end if;
    end loop;
    v_s := round(v_s * p_f, 4);
    v_s := case when p_least is not null then least(v_s, p_least) when p_mult is not null then v_s * p_mult else v_s end;
    v_top := ceil(voyage.stores_need_days_of(coalesce(p_nm, 0), greatest(greatest(v_s, 0.1), 0.1), p_kn[2]))::int + 1;
    for i in 1 .. n loop
      select * into t from public.stores_topup_of(p_crew[i], o_water[i], o_food[i], p_room[i], v_top, p_full[i], p_kn[3], p_kn[4]);
      water_t := water_t + coalesce(t.water_t, 0);
      food_t := food_t + coalesce(t.food_t, 0);
      o_water[i] := coalesce(o_water[i], 0) + coalesce(t.water_t, 0);
      o_food[i] := coalesce(o_food[i], 0) + coalesce(t.food_t, 0);
    end loop;
  end if;
  if p_sea is null then
    v_s := p_min0;
    for i in 1 .. n loop
      if p_k[i] is not null then
        v_s := least(v_s, voyage.ship_speed_fill(p_k[i], least(1.0, (p_cargo[i] + o_water[i] + o_food[i]) / p_hold[i]), p_kn[1]));
      end if;
    end loop;
    v_s := round(v_s * p_f, 4);
    v_s := case when p_least is not null then least(v_s, p_least) when p_mult is not null then v_s * p_mult else v_s end;
    sail_days := p_nm / greatest(v_s, 0.1) / 24;
  end if;
  sea_days := coalesce(p_sea, greatest(1, ceil(sail_days)));
  for i in 1 .. n loop
    v_x := coalesce(p_crew[i], 0);
    o_water[i] := greatest(0, o_water[i] - v_x * p_kn[3] * sea_days);
    o_food[i] := greatest(0, o_food[i] - v_x * p_kn[4] * sea_days);
  end loop;
end $body$
  $mk$;

  execute $mk$
create function world.trip_knobs() returns numeric[] language plpgsql stable security definer set search_path = public, pg_temp as $body$
begin
  return array[public.wc_num('load_speed_penalty'), public.wc_num('endurance_margin'), public.wc_num('water_per_crew_day'), public.wc_num('food_per_crew_day')];
end $body$
  $mk$;

  execute $mk$
create function public.stores_cost_terms(p_player uuid) returns numeric[] language plpgsql stable security definer set search_path = public, pg_temp as $body$
begin
  return array[public.wc_num('provision_water_price'), public.wc_num('provision_food_price'), public.running_cost_mult(p_player),
               public.level_perk(p_player, 'supplies_price'), public.wc_num('running_cost_level')];
end $body$
  $mk$;

  execute $mk$
create function public.stores_cost_of(p_water_t numeric, p_food_t numeric, p_t numeric[]) returns bigint language sql immutable parallel safe as
$f$ select round((coalesce(p_water_t, 0) * p_t[1] + coalesce(p_food_t, 0) * p_t[2]) * p_t[3] * (1 - p_t[4] / 100) * p_t[5])::bigint $f$
  $mk$;

  execute $mk$
create function world.trip_hulls_at(p_hulls jsonb, p_water numeric[], p_food numeric[]) returns jsonb language sql immutable parallel safe as
$f$ select coalesce(jsonb_agg(h.e || jsonb_build_object('water', p_water[h.i], 'food', p_food[h.i]) order by h.i), '[]'::jsonb) from jsonb_array_elements(p_hulls) with ordinality h(e, i) $f$
  $mk$;

  execute $mk$
create function world.trip_arrays(p_speed jsonb, p_hulls jsonb, out o_k numeric[], out o_hold numeric[], out o_crew numeric[], out o_cargo numeric[], out o_room numeric[],
   out o_full numeric[], out o_water numeric[], out o_food numeric[], out o_f numeric, out o_min0 numeric, out o_mult numeric, out o_least numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $body$
begin
  select array_agg((s.e->>'k')::numeric order by h.i), array_agg((s.e->>'hold')::numeric order by h.i), array_agg((h.e->>'crew')::numeric order by h.i),
         array_agg((coalesce(h.e->>'cargo', s.e->>'cargo'))::numeric order by h.i), array_agg((h.e->>'room')::numeric order by h.i), array_agg((h.e->>'full')::numeric order by h.i),
         array_agg((h.e->>'water')::numeric order by h.i), array_agg((h.e->>'food')::numeric order by h.i)
    into o_k, o_hold, o_crew, o_cargo, o_room, o_full, o_water, o_food
    from jsonb_array_elements(p_hulls) with ordinality h(e, i)
    left join jsonb_array_elements(p_speed->'hulls') s(e) on s.e->>'ship' = h.e->>'ship';
  o_f := (p_speed->>'f')::numeric;
  -- a hull of her speed's parts that is not among the walked: at her own casks; one whose hold is not known refuses as the speed does
  select min(voyage.ship_speed_of(s.e, null)) into o_min0 from jsonb_array_elements(p_speed->'hulls') s(e)
   where (s.e->>'hold') is null or not exists (select 1 from jsonb_array_elements(p_hulls) h(e) where h.e->>'ship' = s.e->>'ship');
  if p_speed ? 'members' then
    select min(voyage.fleet_speed_of(m, null, null)) into o_least from jsonb_array_elements(p_speed->'members') m;
  elsif p_speed ? 'mult' then
    o_mult := (p_speed->>'mult')::numeric;
  end if;
end $body$
  $mk$;

  execute $mk$
create function world.legs_rank(p_legs jsonb) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $body$
-- 0504: WHAT A HARBOUR IS RANKED AND FITTED BY, of world.board_legs' rows, each column one array as its text (`k`: the row's place in them),
-- so world.board_sell_memo reads them whole and takes the rest of a row only for the rows it keeps. Nothing is worked out. Server only.
begin
  return (select jsonb_build_object('id', array_agg(l.id order by l.k)::text, 'nm', array_agg(l.nm order by l.k)::text, 'max_leg', array_agg(l.max_leg order by l.k)::text,
                                    'shut_leg', array_agg(l.shut_leg order by l.k)::text, 'sn_fits', array_agg(l.sn_fits order by l.k)::text,
                                    'sn_hold', array_agg(l.sn_hold order by l.k)::text, 'k', array_agg(l.k::int order by l.k)::text)
            from rows from (jsonb_to_recordset(p_legs) as (id uuid, nm numeric, max_leg numeric, shut_leg numeric, sn_fits boolean, sn_hold numeric)) with ordinality l(id, nm, max_leg, shut_leg, sn_fits, sn_hold, k));
end $body$
  $mk$;

  for x in select p.oid::regprocedure::text as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = any (c_new) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', x.fn);
  end loop;

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0504 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0504 values
  ('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)', 1,
$h$
-- 0150: THE top-up of one hull's stores. p_room = her hold less her cargo (what water and food may
-- fill); p_days = the days asked (PROVISION DAYS n), or null for FULL, which asks the days that
-- p_full tons (hold x store_ratio) last. Each store is raised to the days asked — the shorter
-- first, then both in step — never past p_room. Answers the tons to ADD and the days she then holds
-- (the shorter store's; before the ENDURANCE skill). A crewless hull keeps the old split: FULL
-- fills it to p_full, DAYS adds nothing. Read by cmd.do_provision (both passes) and by
-- public.npc_casks_blocked.
declare
  v_w    numeric := public.wc_num('water_per_crew_day');
  v_f    numeric := public.wc_num('food_per_crew_day');
  v_cw   numeric;
  v_cf   numeric;
  v_free numeric := greatest(0, coalesce(p_room, 0) - coalesce(p_water, 0) - coalesce(p_food, 0));
  v_dw   numeric;
  v_df   numeric;
  v_max  numeric;
  v_d    numeric;
  v_t    numeric;
begin
  if coalesce(p_crew, 0) <= 0 then
    v_t := greatest(0, least(coalesce(p_room, 0), case when p_days is null then coalesce(p_full, 0) else 0 end)
                       - coalesce(p_water, 0) - coalesce(p_food, 0));
    water_t := round(v_t * v_w / (v_w + v_f), 3);
    food_t  := round(v_t * v_f / (v_w + v_f), 3);
    days    := 9999;
    return next;
    return;
  end if;
  v_cw := p_crew * v_w;
  v_cf := p_crew * v_f;
  v_dw := coalesce(p_water, 0) / v_cw;
  v_df := coalesce(p_food, 0) / v_cf;
  -- THE MOST DAYS THE FREE ROOM REACHES: the shorter store raised toward the other first; if the
  -- room outlasts that, both in step until the room beside her cargo is full.
  if v_dw <= v_df then
    v_max := case when v_cw * (v_df - v_dw) >= v_free then v_dw + v_free / v_cw
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  else
    v_max := case when v_cf * (v_dw - v_df) >= v_free then v_df + v_free / v_cf
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  end if;
  v_d := least(coalesce(p_days, least(coalesce(p_room, 0), coalesce(p_full, 0)) / (v_cw + v_cf)), v_max);
  water_t := round(greatest(0, v_cw * v_d - coalesce(p_water, 0)), 3);
  food_t  := round(greatest(0, v_cf * v_d - coalesce(p_food, 0)), 3);
  days    := least((coalesce(p_water, 0) + water_t) / v_cw, (coalesce(p_food, 0) + food_t) / v_cf);
  return next;
end $h$,
$h$
-- 0150: THE top-up of one hull's stores (0504: its arithmetic is public.stores_topup_of, moved there whole; the two knobs are read here)
begin
  select t.water_t, t.food_t, t.days into water_t, food_t, days
    from public.stores_topup_of(p_crew, p_water, p_food, p_room, p_days, p_full, public.wc_num('water_per_crew_day'), public.wc_num('food_per_crew_day')) t;
  return next;
end $h$),
  ('voyage.stores_need_days(numeric,numeric)', 1,
$h$
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
$h$,
$h$
begin
  -- 0203: THE DAYS OF STORES A PASSAGE OF p_nm AT p_speed ASKS (0504: its arithmetic is voyage.stores_need_days_of, moved there whole)
  return voyage.stores_need_days_of(p_nm, p_speed, public.wc_num('endurance_margin'));
end
$h$),
  ('public.stores_cost(uuid,numeric,numeric)', 1,
$h$
begin
  -- 0142: THE price of stores — tons of water and food at provision_water_price /
  -- provision_food_price through the house's running_cost_mult — lifted from cmd.do_provision
  -- (0114). Read by cmd.do_provision (what she pays) and by public.npc_plan (what a loop will eat).
  return round((coalesce(p_water_t, 0) * public.wc_num('provision_water_price')
                + coalesce(p_food_t, 0) * public.wc_num('provision_food_price'))
               * public.running_cost_mult(p_player)
               * (1 - public.level_perk(p_player, 'supplies_price') / 100)   -- 0417: her Supplies level (a merchant: 0)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
end $h$,
$h$
begin
  -- 0142: THE price of stores (0504: its reads are public.stores_cost_terms, its arithmetic public.stores_cost_of, moved there whole)
  return public.stores_cost_of(p_water_t, p_food_t, public.stores_cost_terms(p_player));
end $h$),
  ('world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)', 1,
$h$
-- 0361: ONE LEG OF A TRIP, WALKED (world.trip_cost and world.board_trips ask it). Every hull of p_hulls (world.trip_hulls) is topped up for a leg
-- of p_nm as cmd.do_sail tops her (public.stores_topup to public.npc_leg_days), then the leg's settled days are eaten at water_per_crew_day and
-- food_per_crew_day a crew, as voyage.settle eats them: every day begun is a day settled (voyage.total_days: the hours over 24, rounded up, never
-- under one). Answers her hulls as she arrives, the tuns of water and food the top-up took on (public.stores_cost prices them), and the days
-- settled (public.fleet_wage is owed for each).
-- 0454: AT HER SPEED AT EACH DEPARTURE, as cmd.do_sail reads it. p_speed is her voyage.fleet_speed_parts, read once by the caller: the top-up's
-- days at voyage.fleet_speed_of with the casks she carries INTO this departure (public.supply_need's reading), the settled days at
-- voyage.fleet_speed_of with the casks topped up (voyage.depart's: the speed frozen for the leg).
-- 0459: + sail_days, THE LEG'S TIME: p_nm at that frozen speed, in voyage-days with their fraction (voyage.depart's eta; sea_days is it rounded up).
-- A hull's other keys (cap, cargo: world.trip_hulls, world.trip_stow) ride through; her cargo is in her speed (voyage.fleet_speed_of).
--   p_top false  nothing is bought (a voyage already under way; or from an anchorage, where cmd.do_sail buys nothing): the leg on the casks she has
--   p_sea        the days to settle, when the caller knows them (a voyage under way: what is left of it); then no speed is read and sail_days is null
declare
  v_wpd    numeric := public.wc_num('water_per_crew_day');
  v_fpd    numeric := public.wc_num('food_per_crew_day');
  v_top    numeric;
  v_w      numeric;
  v_f      numeric;
  v_topped jsonb := '[]'::jsonb;
  h        jsonb;
begin
  if p_top then
    v_top := public.npc_leg_days(p_nm, greatest(voyage.fleet_speed_of(p_speed, null, p_hulls), 0.1));
  end if;
  water_t := 0;
  food_t := 0;
  for h in select e from jsonb_array_elements(p_hulls) e loop
    v_w := 0;
    v_f := 0;
    if p_top then
      select tu.water_t, tu.food_t into v_w, v_f
        from public.stores_topup((h->>'crew')::numeric, (h->>'water')::numeric, (h->>'food')::numeric, (h->>'room')::numeric, v_top, (h->>'full')::numeric) tu;
    end if;
    water_t := water_t + coalesce(v_w, 0);
    food_t := food_t + coalesce(v_f, 0);
    v_topped := v_topped || jsonb_build_array(h || jsonb_build_object(
      'water', coalesce((h->>'water')::numeric, 0) + coalesce(v_w, 0), 'food', coalesce((h->>'food')::numeric, 0) + coalesce(v_f, 0)));
  end loop;
  if p_sea is null then
    sail_days := p_nm / greatest(voyage.fleet_speed_of(p_speed, null, v_topped), 0.1) / 24;   -- voyage.depart: the miles at the speed frozen for the leg
  end if;
  sea_days := coalesce(p_sea, greatest(1, ceil(sail_days)));   -- voyage.total_days: every day begun is settled, never under one
  hulls := '[]'::jsonb;
  for h in select e from jsonb_array_elements(v_topped) e loop
    hulls := hulls || jsonb_build_array(h || jsonb_build_object(
      'water', greatest(0, (h->>'water')::numeric - coalesce((h->>'crew')::numeric, 0) * v_wpd * sea_days),
      'food',  greatest(0, (h->>'food')::numeric - coalesce((h->>'crew')::numeric, 0) * v_fpd * sea_days)));
  end loop;
  return next;
end
$h$,
$h$
-- 0361 / 0454 / 0459: ONE LEG OF A TRIP, AS THE GAME SAILS IT: topped up before it as cmd.do_sail tops her (p_top), her speed as she leaves, the
-- days settled. 0504: the walk is world.trip_leg_of, moved there whole, on her hulls in arrays (world.trip_arrays); here they are unpacked and put back.
declare
  a record;
  x record;
begin
  select * into a from world.trip_arrays(p_speed, p_hulls);
  select * into x from world.trip_leg_of(world.trip_knobs(), a.o_k, a.o_hold, a.o_crew, a.o_cargo, a.o_room, a.o_full, a.o_f, a.o_min0, a.o_mult, a.o_least,
                                         a.o_water, a.o_food, p_nm, p_top, p_sea);
  hulls := world.trip_hulls_at(p_hulls, x.o_water, x.o_food);
  water_t := x.water_t;
  food_t := x.food_t;
  sea_days := x.sea_days;
  sail_days := x.sail_days;
  return next;
end
$h$),
  ('voyage.ship_speed_of(jsonb,numeric)', 1,
$h$  return round((p_parts ->> 'k')::numeric * (1 - public.wc_num('load_speed_penalty') * v_fill), 4);$h$,
$h$  return voyage.ship_speed_fill((p_parts ->> 'k')::numeric, v_fill, public.wc_num('load_speed_penalty'));   -- 0504: its arithmetic, moved there$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 1,
$h$  m_h       jsonb[] := '{}';
$h$,
$h$  m_w       numeric[] := '{}';       -- 0504: her hulls' casks there, one element a hull (v_hn a way)
  m_f       numeric[] := '{}';
$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 2,
$h$  v_h       jsonb;
$h$,
$h$  -- 0504 (2): the old walk kept its state here
$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 3,
$h$  ti        int;
$h$,
$h$  ti        int;
  -- 0504: her hulls in arrays, the knobs and her house's price of stores read once, so a leg is arithmetic alone (world.trip_leg_of)
  v_kn      numeric[] := world.trip_knobs();
  v_sc      numeric[] := public.stores_cost_terms(v_player);
  a         record;                  -- world.trip_arrays of her hulls as she sails from v_origin
  ab        record;                  -- and with the buy aboard
  x0        record;
  v_hn      int;
  v_cw      numeric[];
  v_cf      numeric[];
$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 4,
$h$  for tr in
$h$,
$h$  select * into a from world.trip_arrays(v_speed, v_h0);
  v_hn := coalesce(cardinality(a.o_crew), 0);
  for tr in
$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 5,
$h$v_h := v_h0; v_sup$h$,
$h$v_cw := a.o_water; v_cf := a.o_food; v_sup$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 6,
$h$v_h := m_h[v_pos]; $h$,
$h$v_cw := m_w[(v_pos - 1) * v_hn + 1 : v_pos * v_hn]; v_cf := m_f[(v_pos - 1) * v_hn + 1 : v_pos * v_hn]; $h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 7,
$h$          v_hb := coalesce(v_hb, world.trip_stow(v_h, v_units, v_bulk));   -- the buy, aboard as she leaves the buy city
          v_h := v_hb;
        end if;
        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days, tl.sail_days into v_h, v_w, v_f, v_sea, v_sail from world.trip_leg(v_speed, v_h, v_nm) tl;
        v_sup := v_sup + public.stores_cost(v_player, v_w, v_f);
$h$,
$h$          if v_hb is null then   -- the buy, aboard as she leaves the buy city
            v_hb := world.trip_stow(world.trip_hulls_at(v_h0, v_cw, v_cf), v_units, v_bulk);
            select * into ab from world.trip_arrays(v_speed, v_hb);
          end if;
          v_cw := ab.o_water; v_cf := ab.o_food;
        end if;
        if ti - 1 >= v_nb then
          select * into x0 from world.trip_leg_of(v_kn, ab.o_k, ab.o_hold, ab.o_crew, ab.o_cargo, ab.o_room, ab.o_full, ab.o_f, ab.o_min0, ab.o_mult, ab.o_least, v_cw, v_cf, v_nm, true, null);
        else
          select * into x0 from world.trip_leg_of(v_kn, a.o_k, a.o_hold, a.o_crew, a.o_cargo, a.o_room, a.o_full, a.o_f, a.o_min0, a.o_mult, a.o_least, v_cw, v_cf, v_nm, true, null);
        end if;
        v_cw := x0.o_water; v_cf := x0.o_food; v_sea := x0.sea_days; v_sail := x0.sail_days;
        v_sup := v_sup + public.stores_cost_of(x0.water_t, x0.food_t, v_sc);
$h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 8,
$h$m_h := m_h || v_h; $h$,
$h$m_w := m_w || v_cw; m_f := m_f || v_cf; $h$),
  ('world.board_trips(uuid,jsonb,jsonb)', 9,
$h$  v_w       numeric;
  v_f       numeric;
$h$,
$h$  -- 0504 (9): the old walk kept its state here
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 1,
$h$  v_shut  boolean := false;   -- 0231: the cap left a harbour unreached
$h$,
$h$  v_shut  boolean := false;   -- 0231: the cap left a harbour unreached
  -- 0504: THE OPEN LEGS, KEPT AS A LIST: only a leg no longer than the search's limit is asked of the seas and looked at again (v_at: their
  -- places in the matrix, row by row; e_j, e_w: the open ones' ends and miles; e_s: where a harbour's begin), and the next harbour is looked
  -- for among those reached and not yet settled (v_f). The same legs in the same order, the same choice on a tie: the same passages
  v_lim   float8;
  v_at    int[];
  v_aw    float8[];
  e_j     int[];
  e_w     float8[];
  e_s     int[];
  v_f     int[];
  v_fn    int;
  v_fp    int;
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 2,
$h$  -- 0216: THE SEA, ONCE A CALL.$h$,
$h$  v_lim := v_reach;
  loop   -- 0504: twice at most: within her cap, and (0231) within her navigation when the cap left a harbour unreached
  if v_lim is null then
    select array_agg(x.o::int order by x.o), array_agg(x.w order by x.o) into v_at, v_aw from unnest(d) with ordinality x(w, o) where x.w is not null;
  else
    select array_agg(x.o::int order by x.o), array_agg(x.w order by x.o) into v_at, v_aw from unnest(d) with ordinality x(w, o) where x.w <= v_lim;
  end if;
  v_at := coalesce(v_at, '{}');
  -- 0216: THE SEA, ONCE A CALL.$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 3,
$h$      from unnest(v_ids) with ordinality a(id, i)
     cross join unnest(v_ids) with ordinality b(id, j)
$h$,
$h$      from unnest(v_at) q(o)
     cross join lateral (select v_ids[(q.o - 1) / v_n + 1] as id, (q.o - 1) / v_n + 1 as i offset 0) a
     cross join lateral (select v_ids[(q.o - 1) % v_n + 1] as id, (q.o - 1) % v_n + 1 as j offset 0) b
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 4,
$h$  dist := array_fill(null::float8, array[v_n]);
  hops$h$,
$h$  select array_agg((q.o - 1) % v_n + 1 order by q.o), array_agg(q.w order by q.o) into e_j, e_w
    from unnest(v_at, v_aw, ok) q(o, w, k) where ok is null or q.k;
  -- e_s[i]: how many of them leave the harbours before i, and one; e_s[v_n + 1]: one past the last
  select array_agg(y.n order by y.i) into e_s
    from (select g.i, 1 + coalesce(sum(c.n) over (order by g.i rows between unbounded preceding and 1 preceding), 0)::int as n
            from generate_series(1, v_n + 1) g(i)
            left join (select (q.o - 1) / v_n + 1 as i, count(*) as n from unnest(v_at, ok) q(o, k) where ok is null or q.k group by 1) c on c.i = g.i) y;
  if v_shut then
    exit;
  end if;
  dist := array_fill(null::float8, array[v_n]);
  hops$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 5,
$h$  dist[v_s] := 0;
  loop
    u := 0;
    best := null;
    for i in 1 .. v_n loop
      if not done[i] and dist[i] is not null and (best is null or dist[i] < best) then
        u := i;
        best := dist[i];
      end if;
    end loop;
    exit when u = 0;
    done[u] := true;
    for j in 1 .. v_n loop
      if not done[j] and v_open[j] and (ok is null or ok[(u - 1) * v_n + j]) then   -- 0216
        w := d[(u - 1) * v_n + j];
        if w is not null and w <= v_reach then
          nd := best + w;
          if dist[j] is null or nd < dist[j] or (nd = dist[j] and hops[u] + 1 < hops[j]) then
            dist[j] := nd;
            hops[j] := hops[u] + 1;
            maxl[j] := greatest(maxl[u], w);
            prev[j] := u;
          end if;
        end if;
      end if;
    end loop;
  end loop;
$h$,
$h$  dist[v_s] := 0;
  v_f := array_fill(0, array[v_n]);
  v_f[1] := v_s;
  v_fn := 1;
  while v_fn > 0 loop
    u := 0;
    best := null;
    for i in 1 .. v_fn loop
      k := v_f[i];
      w := dist[k];
      if best is null or w < best or (w = best and k < u) then
        u := k;
        best := w;
        v_fp := i;
      end if;
    end loop;
    v_f[v_fp] := v_f[v_fn];
    v_fn := v_fn - 1;
    done[u] := true;
    for i in e_s[u] .. e_s[u + 1] - 1 loop
      k := e_j[i];
      if not done[k] and v_open[k] then   -- 0216: the leg is open (e_j)
        w := e_w[i];
        nd := best + w;
        if dist[k] is null or nd < dist[k] or (nd = dist[k] and hops[u] + 1 < hops[k]) then
          if dist[k] is null then
            v_fn := v_fn + 1;
            v_f[v_fn] := k;
          end if;
          dist[k] := nd;
          hops[k] := hops[u] + 1;
          maxl[k] := greatest(maxl[u], w);
          prev[k] := u;
        end if;
      end if;
    end loop;
  end loop;
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 6,
$h$        v_shut := true;
        exit;
      end if;
    end loop;
  end if;
$h$,
$h$        v_shut := true;
        exit;
      end if;
    end loop;
  end if;
  exit when not v_shut;
  v_lim := v_nav;   -- 0504: once more, the legs within her navigation
  ok := null;
  end loop;
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 7,
$h$    bn[v_s] := 0;
    loop
      u := 0;
      best := null;
      for i in 1 .. v_n loop
        if not done[i] and bn[i] is not null and (best is null or bn[i] < best) then
          u := i;
          best := bn[i];
        end if;
      end loop;
      exit when u = 0;
      done[u] := true;
      for j in 1 .. v_n loop
        if not done[j] and v_open[j] and (ok is null or ok[(u - 1) * v_n + j]) then
          w := d[(u - 1) * v_n + j];
          if w is not null and (v_nav is null or w <= v_nav) then
            nd := greatest(best, w);
            if bn[j] is null or nd < bn[j] then
              bn[j] := nd;
            end if;
          end if;
        end if;
      end loop;
    end loop;
$h$,
$h$    bn[v_s] := 0;
    v_f := array_fill(0, array[v_n]);
    v_f[1] := v_s;
    v_fn := 1;
    while v_fn > 0 loop
      best := null;
      for i in 1 .. v_fn loop
        k := v_f[i];
        w := bn[k];
        if best is null or w < best or (w = best and k < u) then
          u := k;
          best := w;
          v_fp := i;
        end if;
      end loop;
      v_f[v_fp] := v_f[v_fn];
      v_fn := v_fn - 1;
      done[u] := true;
      for i in e_s[u] .. e_s[u + 1] - 1 loop
        k := e_j[i];
        if not done[k] and v_open[k] then
          nd := greatest(best, e_w[i]);
          if bn[k] is null or nd < bn[k] then
            if bn[k] is null then
              v_fn := v_fn + 1;
              v_f[v_fn] := k;
            end if;
            bn[k] := nd;
          end if;
        end if;
      end loop;
    end loop;
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 1,
$h$  v_taxon   boolean := public.city_treasury_on();
begin
$h$,
$h$  v_taxon   boolean := public.city_treasury_on();
  v_rank    jsonb := p_ctx->'rank';   -- 0504: the legs' figures a harbour is ranked by (world.legs_rank), when the caller has them
begin
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 2,
$h$  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
$h$,
$h$  if v_rank is null or jsonb_typeof(v_rank) <> 'object' then
    v_rank := world.legs_rank(v_legs);
  end if;

  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 3,
$h$           l.nm, l.stops, l.direct_nm, l.max_leg, l.shut_leg,
           l.sn_days, l.sn_tons, l.sn_cost, l.sn_fits, l.sn_hold,   -- 0225; sn_hold: the room those stores take in her hold (public.stores_in_hold), read once a leg
           l.t_sea, l.t_sup, l.t_stop, l.t_pre, l.t_post,   -- 0361: the trip there, as the game will charge it (world.board_legs)
           l.t_sail, l.t_days, l.t_arrive   -- 0459: and its time as walked (world.board_trips)
$h$,
$h$           l.nm, l.max_leg, l.shut_leg, l.sn_fits, l.sn_hold, l.k   -- 0504: what a harbour is ranked and fitted by; `ranked` reads the rest of its leg
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 4,
$h$      join jsonb_to_recordset(v_legs) l(id uuid, nm numeric, stops text[], direct_nm numeric, max_leg numeric, shut_leg numeric,
                                        sn_days numeric, sn_tons numeric, sn_cost bigint, sn_fits boolean, sn_hold numeric,
                                        t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[],
                                        t_sail numeric, t_days numeric, t_arrive timestamptz) on l.id = p.id   -- 0361; 0459: + t_sail, t_days, t_arrive
$h$,
$h$      join unnest((v_rank->>'id')::uuid[], (v_rank->>'nm')::numeric[], (v_rank->>'max_leg')::numeric[], (v_rank->>'shut_leg')::numeric[],
                  (v_rank->>'sn_fits')::boolean[], (v_rank->>'sn_hold')::numeric[], (v_rank->>'k')::int[]) l(id, nm, max_leg, shut_leg, sn_fits, sn_hold, k) on l.id = p.id
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 5,
$h$  ), ranked as materialized (
$h$,
$h$  ), ranked0 as materialized (
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 6,
$h$      from cand c
  ), units as (
$h$,
$h$      from cand c
  ), ranked as materialized (
    -- 0504: the rest of a harbour's leg, read of the rows kept (lean: the priced ones): 0225; 0361: the trip there as the game will charge it
    -- (world.board_legs); 0459: and its time as walked (world.board_trips)
    select r0.*, l.*
      from ranked0 r0
     cross join lateral jsonb_to_record(v_legs->(r0.k - 1)) l(stops text[], direct_nm numeric, sn_days numeric, sn_tons numeric, sn_cost bigint,
                                                             t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[],
                                                             t_sail numeric, t_days numeric, t_arrive timestamptz)
     where not v_lean or r0.rk <= v_quoted or r0.nk <= v_near
  ), units as (
$h$),
  ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 7,
$h$                                                                                                  'only', d.ids), v_legs)) x(e)
$h$,
$h$                                                                                                  'only', d.ids),
                                                      (select jsonb_agg(v_legs->(r0.k - 1)) from ranked0 r0 where d.ids @> jsonb_build_array(r0.id)))) x(e)
$h$),
  ('world.best_sales(uuid,uuid)', 1,
$h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
$h$,
$h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
  v_rank_buy jsonb;                 -- 0504: world.legs_rank of the two, asked once
  v_rank_own jsonb;
$h$),
  ('world.best_sales(uuid,uuid)', 2,
$h$        v_legs_own := world.board_legs(p_fleet, v_ctx);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_own);
$h$,
$h$        v_legs_own := world.board_legs(p_fleet, v_ctx);
        v_rank_own := world.legs_rank(v_legs_own);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_own, 'rank', v_rank_own);
$h$),
  ('world.best_sales(uuid,uuid)', 3,
$h$        v_legs_buy := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_buy);
$h$,
$h$        v_legs_buy := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
        v_rank_buy := world.legs_rank(v_legs_buy);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_buy, 'rank', v_rank_buy);
$h$);

  for v_h in select h.fn from hunks_0504 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0504 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0504 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0504 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0504 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0504 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  perform public.news_update('0504', 'Trade, HQ and Assign open sooner', 'Trade, HQ and Assign open sooner');

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and n.nspname || '.' || p.proname <> all (c_new)
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_fn_before then
    raise exception '0504 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0504 self-assert FAIL: the grants, volatility, definer, settings or owner of a cut body moved';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname || '.' || p.proname = any (c_new)
                and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = any (c_new)) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0504 self-assert FAIL: a new function is reachable by a client or service_role, or is there twice';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (its own company's rows alone) ──
  begin
    v_me := public.new_house(c_uid, 'Casa Depressa 0504', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
    perform cmd.assume_identity(c_uid);
    v_s := voyage.fleet_speed_parts(v_fl);
    v_hl := world.trip_hulls(v_fl);

    -- the arithmetic, over a grid
    if exists (select 1 from unnest(array[0, 0.5, 3, 8, 40]::numeric[]) c(v) cross join unnest(array[0, 1.25, 7.5, 30]::numeric[]) w(v) cross join unnest(array[0, 2.5, 9]::numeric[]) f(v)
                cross join unnest(array[0, 5, 26, 120]::numeric[]) m(v) cross join unnest(array[null, 0, 3, 40]::numeric[]) d(v)
                cross join lateral public.stores_topup(c.v, w.v, f.v, m.v, d.v, m.v * 0.8) n
                cross join lateral pg_temp.was_0504_stores_topup(c.v, w.v, f.v, m.v, d.v, m.v * 0.8) o
                where (n.water_t::text, n.food_t::text, n.days::text) is distinct from (o.water_t::text, o.food_t::text, o.days::text))
       or exists (select 1 from unnest(array[0, 1, 137.4, 1630, 9000]::numeric[]) a(v) cross join unnest(array[0.1, 4.25, 11]::numeric[]) b(v)
                   where voyage.stores_need_days(a.v, b.v)::text is distinct from pg_temp.was_0504_stores_need_days(a.v, b.v)::text
                      or public.stores_cost(v_me, a.v / 100, b.v)::text is distinct from pg_temp.was_0504_stores_cost(v_me, a.v / 100, b.v)::text
                      or public.stores_cost(null, a.v / 100, null)::text is distinct from pg_temp.was_0504_stores_cost(null, a.v / 100, null)::text)
       or exists (select 1 from jsonb_array_elements(v_s->'hulls') h(e) cross join unnest(array[null, 0, 0.5, 1, 2]::numeric[]) q(v)
                   where voyage.ship_speed_of(h.e, q.v)::text is distinct from pg_temp.was_0504_ship_speed_of(h.e, q.v)::text) then
      raise exception '0504 self-assert FAIL: the top-up, the days of stores, their price or a hull''s speed is not what it was';
    end if;
    if exists (select 1 from unnest(array[0, 60, 731.2, 1630, 5200]::numeric[]) a(v) cross join (values (true, null::numeric), (false, null), (false, 3), (true, 2)) m(t, s)
                cross join lateral world.trip_leg(v_s, v_hl, a.v, m.t, m.s) n cross join lateral pg_temp.was_0504_trip_leg(v_s, v_hl, a.v, m.t, m.s) o
                where to_jsonb(n)::text is distinct from to_jsonb(o)::text) then
      raise exception '0504 self-assert FAIL: a leg is not walked as it was';
    end if;
    -- the passages
    for x in select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as i from public.ports p0 where p0.kind = 'HARBOUR') p where p.i % 50 = 9 or p.id = v_lis loop
      foreach v_q in array array['700', '1900', ''] loop
        select jsonb_agg(to_jsonb(r) order by r.code) into v_a from voyage.reach_passage(v_me, v_fl, x.id, nullif(v_q, '')::numeric) r;
        select jsonb_agg(to_jsonb(r) order by r.code) into v_b from pg_temp.was_0504_reach_passage(v_me, v_fl, x.id, nullif(v_q, '')::numeric) r;
        if v_a::text is distinct from v_b::text then
          raise exception '0504 self-assert FAIL: the passages from % (cap %) are not what they were', x.code, v_q;
        end if;
      end loop;
    end loop;
    -- her whole read, its clock budget an hour on both sides
    v_def := replace(replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', ''), 'world.best_sales(', 'pg_temp.now_0504_best_sales(');
    execute replace(v_def, $q$c_budget  constant interval := interval '2.5 seconds'$q$, $q$c_budget  constant interval := interval '1 hour'$q$);
    v_c := clock_timestamp();
    v_a := pg_temp.was_0504_best_sales(v_fl, v_lis);
    v_ms0 := round(extract(epoch from clock_timestamp() - v_c) * 1000);
    v_c := clock_timestamp();
    v_b := pg_temp.now_0504_best_sales(v_fl, v_lis);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_c) * 1000);
    if v_a::text is distinct from v_b::text then
      raise exception '0504 self-assert FAIL: her best sales are not what they were: % / %', left(v_b::text, 900), left(v_a::text, 900);
    end if;
    v_note := format('the arithmetic, the walk, the passages and her read (%s cards) the same to the letter; best_sales %s ms before, %s ms now', jsonb_array_length(v_b->'goods'), v_ms0, v_ms1);
    raise exception using errcode = 'ZX504', message = 'PROBE_ROLLBACK_0504';
  exception when sqlstate 'ZX504' then
    v_lived := true;
  end;
  -- what stood before, kept for the probe, goes
  for x in select p.oid::regprocedure::text as fn from pg_proc p where p.pronamespace = pg_my_temp_schema() and (p.proname like 'was\_0504\_%' or p.proname like 'now\_0504\_%') loop
    execute 'drop function ' || x.fn;
  end loop;
  if not v_lived then
    raise exception '0504 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa Depressa 0504' or p.auth_uid = c_uid)
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0504 self-assert FAIL: the probe left something behind, or a knob moved';
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0504 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0504 self-assert ok: THE BEST SALES, FASTER. % hunks once and reversing; % new functions server only; no other function moved; no knob moved. Probe (rolled back): %. % ms.',
    (select count(*) from hunks_0504), cardinality(c_new), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
