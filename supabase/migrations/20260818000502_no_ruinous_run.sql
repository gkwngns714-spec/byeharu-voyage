-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights run_guard_enabled)
-- 0502 - NO RUINOUS RUN  (dark: the owner's switch run_guard_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD, 2026-11-25: "a job does not start a run whose fees along its chain plus provisions, crew and a repair reserve exceed the
--   purse, or whose danger for the hull is over a bound; it waits with a plain reason, like 0498's prices low." The owner's company,
--   24-25 Nov: purse 8,240, a Best run Island of Mozambique - Palma - Diego Garcia - Bandar - Malacca - Macau with 899 black coral; a
--   storm's safe default took 5,000 (SEA_LOSS), one dock fee 3,233, the purse was 0 and she lay wrecked in a harbour with no yard.
--   No plan asked whether her PURSE could pay the way (docs/dev-log/2026-11-25-no-ruinous-run.md).
--
-- WHAT (lit; dark every body answers as before):
--   public.run_guard_on()     THE SWITCH, read once: world_config run_guard_enabled.
--   public.run_need(player, fleet, from, lines)   WHAT A PLAN'S LINES ASK OF HER PURSE AND HER HULL (a read; every figure an authority's):
--       buy      the BUY's cost (public.fleet_buy_capacity for ALL, world.quote for a number)
--       stores   the casks topped up before every leg (world.trip_cost, the map's quote)
--       dock     the dock fee of every harbour called at, the sale's too (public.port_fee), for the cargo aboard AND the cargo she is
--                about to buy: world.trip_cost charges the cargo aboard NOW, so a run that buys read too little
--       crew     the hands she lacks, at the Inn's price (public.fleet_crew_shortfall, public.crew_hire_cost)
--       reserve  a whole repair: every hull from nothing, at the yard's price (public.fleet_repair_cost)
--       sea      while choices at sea are lit, the coin a storm's SAFE DEFAULT takes from that cargo, once (public.sea_choice_options)
--       hull     the share of a hull the run is expected to cost: each leg's segment of her course, its days, the day's chance of an event
--                (seas.hazard_base x hazard_mult, under hazard_p_max, as voyage.hazard_roll) and the share of that sea's storms, shoals
--                and raids (voyage.sea_mix); a storm 0.165 of a hull, a shoal 0.095 (voyage.settle's means), a raid 0.05, and 0.50 where
--                the raider (danger x 40) is stronger than her escort score
--     need = stores + dock + crew + reserve + sea. A BUY that leaves less than need is CUT to the units that leave it, when those units
--     still pay; no units do (or nothing is bought and the purse is under need): {wait: purse}. hull over run_guard_hull_share of the
--     hull she has: {wait: danger}. A trip nobody can price is left to the door ({ok}).
--     Where a PROVISION DAYS line stands before a BUY ALL (0508, the stores in the hold), the ALL is what fits beside those stores.
--   public.run_cut(lines, buy)  the lines with the BUY line's text replaced, WHEREVER IT STANDS (by its verb), every other line as it was.
--   public.fleet_job_plan     (5 hunks) asked where a run STARTS: a fixed job at its buy harbour, a Best job's sale (the first of its four
--                             best that stands; none: the first one's reason), a haul leaving the land's harbour. NOT asked: a run at
--                             its sale's harbour, and a fleet sailing home or to her buy harbour (she must be able to come back).
--   public.fleet_job_note     (1 hunk) wait `purse` | `danger`: as 0498's `low` (600 s at least, not stopped, its sentence on her row).
-- NOT IN `need`: wages (owed as she sails, paid out of her next sale's profit: voyage.settle), a tow, the sail home, a second storm.
-- NOT CHANGED: any knob but the two new; any command, table, beat step; the player's own orders (a warning there is another slice).
-- ROWS: two world_config rows. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit: one world.trip_cost and one read of the courses a started run;
--   a Best job at most four.
-- LOCKS: one INSERT (world_config); CREATE FUNCTION x3; CREATE OR REPLACE x2 by hunks. TIME: about a second. BUDGET: statement_timeout
--   90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, run_guard_enabled false. FULL: reverse the six hunks and drop the three functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants and meta unmoved; the new functions STABLE
--   and server only; two knobs added, no other moved. THE PROBE (rolled back by a raised sentinel; its own company): the run is BUILT
--   (static rows choose the pair; its two market rows are written to a paying pair, as 0498's), the purse is set against the need the
--   read itself answers, and the danger is judged by moving the bound, so no step asks the live market, purse, company or dice a sign.
-- VERSION: 0502 (0499 near-round, 0500 fit-to-sail and 0501 stand below it; its anchors are in none of their hunks).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_plan(uuid)', 'public.fleet_job_note(uuid,jsonb)'];
  c_new    constant text[] := array['public.run_guard_on()', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.run_cut(jsonb,text)'];
  c_uid    constant uuid := '00000000-0502-4000-8000-000000000001';
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
  v_dest      uuid;
  v_gid       uuid;
  v_good      text;
  v_sell      text;
  v_p0        jsonb;
  v_p         jsonb;
  v_need      jsonb;
  v_dock      bigint;
  v_w         jsonb;
  v_j         public.fleet_jobs%rowtype;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'run_guard_enabled') or to_regprocedure('public.run_guard_on()') is not null then
    raise exception '0502 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.jobs_wait_on()') is null or to_regprocedure('world.trip_cost(uuid,jsonb)') is null
     or to_regprocedure('public.port_fee(uuid,uuid,numeric)') is null or to_regprocedure('public.sea_choice_options(text,bigint,numeric,numeric)') is null
     or to_regprocedure('voyage.sea_mix(uuid,numeric)') is null then
    raise exception '0502 refuses: 0498 (jobs never lose) or one of the readings it asks is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('run_guard_enabled', 'false'::jsonb,
     '0502: THE SWITCH (the owner''s). true: a standing job starts a run only when her purse, after the BUY, covers the dock fees along its way, the stores, the crew she lacks, a whole repair and (choices at sea lit) one storm''s safe default, and when the run''s expected hull loss is within run_guard_hull_share; a BUY is cut to what leaves that, and otherwise the job WAITS (asked again 10 minutes on, never stopped). false: every job as before 0502.'),
    ('run_guard_hull_share', '0.5'::jsonb,
     '0502: the largest share of the hull she HAS (her worst ship''s) that a job''s run may be expected to cost; above it the job waits (danger). Read only while run_guard_enabled.');

  -- ── 3. THE RULES ──
  execute $f$
create function public.run_guard_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0502: THE SWITCH, read once: world_config run_guard_enabled.
  select public.wc('run_guard_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.run_need(p_player uuid, p_fleet uuid, p_from uuid, p_lines jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0502: WHAT A PLAN'S LINES (BUY good n|ALL, SAIL with its path, SELL|STORE|TAKE) ASK OF HER PURSE AND HER HULL, as the fleet lies at
-- p_from. {ok, purse, buy, stores, dock, crew, reserve, sea, need, after, hull, hull_left, units} and, when the BUY was cut, {line};
-- or {wait: purse|danger, sentence, ...}. The terms: 0502's header. {ok, unpriced}: the trip cannot be priced (or the caller is not her
-- company: world.trip_cost reads the caller): nothing is judged here, the door judges it. Writes nothing.
declare
  v_w      text[];
  v_at     text := (select p.code from public.ports p where p.id = p_from);
  v_legs   jsonb := '[]'::jsonb;
  v_calls  uuid[] := '{}';
  v_good   text;
  v_gid    uuid;
  v_dest   uuid;
  v_sells  boolean := false;
  v_n      numeric := 0;
  v_n0     numeric := 0;
  v_all    boolean := false;
  v_cost   numeric := 0;
  v_net    numeric;
  v_got    numeric;
  v_prov   numeric;
  v_gross  numeric;
  v_trip   jsonb;
  v_stock  numeric;
  v_dock   numeric;
  v_crew   numeric;
  v_short  int;
  v_res    numeric;
  v_sea    numeric;
  v_need   numeric;
  v_purse  numeric := (select p.ducats from public.players p where p.id = p_player);
  v_hull   numeric := 0;
  v_left   numeric;
  v_esc    numeric;
  v_out    jsonb;
  l        jsonb;
  i        int := 0;
begin
  -- THE LINES
  for l in select e from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e loop
    v_w := regexp_split_to_array(l->>'text', ' ');
    if v_w[1] = 'PROVISION' and v_w[2] = 'DAYS' then
      v_prov := v_w[3]::numeric;
    elsif v_w[1] = 'BUY' then
      v_good := v_w[2];
      v_all := v_w[3] = 'ALL';
      v_n := case when v_all then 0 else v_w[3]::numeric end;
    elsif v_w[1] = 'SAIL' then
      v_legs := v_legs || jsonb_build_array(jsonb_build_object('from', v_at, 'to', v_w[2], 'course', l->'path'));
      v_at := v_w[2];
      v_dest := (select p.id from public.ports p where p.code = v_at and p.kind = 'HARBOUR');
      v_calls := v_calls || v_dest;
    elsif v_w[1] = 'SELL' then
      v_sells := v_w[2] = v_good;
    end if;
  end loop;
  if jsonb_array_length(v_legs) = 0 then
    return jsonb_build_object('ok', true, 'unpriced', true);
  end if;
  v_trip := world.trip_cost(p_fleet, v_legs);
  if v_trip is null or jsonb_typeof(v_trip->'total') is distinct from 'number' then
    return jsonb_build_object('ok', true, 'unpriced', true);
  end if;

  -- THE HULL (asked first: no smaller cargo makes a sea safer)
  v_esc := coalesce(voyage.escort_score(p_fleet), 0);
  select min(sh.durability / nullif(sb.durability, 0)) into v_left from public.ships sh cross join lateral public.ship_base(sh.id) sb where sh.fleet_id = p_fleet;
  -- the passage's days in each sea (a sea's mix is read once a sea, not once a segment)
  select coalesce(sum(w.days * (select coalesce(sum(m.share * case m.kind_code when 'STORM' then 0.165 when 'SHOAL_WATER' then 0.095
                                                                   when 'PIRATES' then case when w.danger * 40 > v_esc then 0.50 else 0.05 end
                                                                   else 0 end), 0)
                                  from voyage.sea_mix(w.sea, w.danger) m)), 0)
    into v_hull
    from (select s.id as sea, voyage.sea_danger(s.id, now()) as danger,
                 sum((t.leg->>'days')::numeric * (g.seg->>'nm')::numeric / greatest((t.leg->>'nm')::numeric, 1)
                     * least(public.wc_num('hazard_p_max'), greatest(0, s.hazard_base * (g.seg->>'hazard_mult')::numeric))) as days
            from jsonb_array_elements(v_legs) with ordinality e(leg, n)
            join jsonb_array_elements(v_trip->'legs') with ordinality t(leg, n) on t.n = e.n
            cross join lateral jsonb_array_elements(case when jsonb_typeof(e.leg->'course') = 'array' then voyage.segments_from_course(e.leg->'course') else '[]'::jsonb end) g(seg)
            join public.seas s on s.id = (g.seg->>'sea_id')::uuid
           group by s.id) w;
  v_hull := round(v_hull, 4);
  v_left := round(coalesce(v_left, 0), 4);
  if v_hull > public.wc_num('run_guard_hull_share') * v_left then
    return jsonb_build_object('wait', 'danger', 'sentence', 'too dangerous for her hull', 'hull', v_hull, 'hull_left', v_left);
  end if;

  -- THE BUY
  if v_good is not null then
    v_gid := (select g.id from public.goods g where g.code = v_good);
    if v_all then
      v_out := public.fleet_buy_capacity(p_fleet, v_gid);
      v_n := coalesce((v_out->>'max_qty')::numeric, 0);
      v_cost := case when v_n > 0 then (v_out->>'est_total')::numeric else 0 end;
      -- stores in the hold (0345's switch false): the PROVISION before the BUY takes its room first (cmd.do_provision's own reading)
      if v_prov > 0 and v_n > 0 and not public.ship_stores_separate() then
        v_got := floor(greatest(0, public.fleet_free_hold(p_fleet) -
                   (select coalesce(sum(t.water_t + t.food_t), 0)
                      from public.ships sh
                     cross join lateral (select public.ship_hold_capacity(sh.id) as hold, public.ship_cargo_tuns(sh.id) as cargo_t offset 0) c
                     cross join lateral public.stores_topup(sh.crew, sh.water_t, sh.food_t, public.ship_stores_room(sh.id, c.hold - c.cargo_t), v_prov,
                                                            public.ship_stores_room(sh.id, c.hold * sh.store_ratio)) t
                     where sh.fleet_id = p_fleet)) / (select g.bulk from public.goods g where g.id = v_gid));
        if v_got < v_n then
          v_n := v_got;
          v_cost := 0;
          if v_n >= 1 then
            select q.total into v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
          end if;
        end if;
      end if;
    else
      select q.units, q.total into v_got, v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
      v_n := least(v_n, coalesce(v_got, 0));   -- the quay sells no more than it has
    end if;
    v_cost := coalesce(v_cost, 0);
    v_n0 := v_n;
  end if;

  -- THE PURSE
  v_stock := public.fleet_stock_at_cost(p_fleet);
  v_short := public.fleet_crew_shortfall(p_fleet);
  v_crew := case when v_short > 0 then coalesce((public.crew_hire_cost(p_fleet, v_short)->>'cost')::numeric, 0) else 0 end;
  v_res := public.fleet_repair_cost(p_fleet, (select sum(sb.durability) from public.ships sh cross join lateral public.ship_base(sh.id) sb where sh.fleet_id = p_fleet), null);
  loop
    i := i + 1;
    v_dock := (select coalesce(sum(public.port_fee(c.p, p_player, v_stock + v_cost)), 0) from unnest(v_calls) c(p));
    v_sea := case when public.sea_choices_on() then
               (select -coalesce(min((o->>'lose')::numeric), 0)
                  from jsonb_array_elements(public.sea_choice_options('storm', least(public.wc_int('sea_choices_stake_max'),
                         greatest(public.wc_int('sea_choices_stake_min'), round((v_stock + v_cost) * public.wc_num('sea_choices_stake_pct'))::bigint))::bigint, 1, 0)) o
                 where (o->>'safe')::boolean)
             else 0 end;
    v_need := (v_trip->>'supplies')::numeric + v_dock + v_crew + v_res + v_sea;
    exit when v_purse - v_cost >= v_need or v_n < 1 or i > 12;
    -- cut: a smaller BUY never costs more a unit, so the proportion never overshoots the purse
    v_n := least(v_n - 1, floor(v_n * greatest(v_purse - v_need, 0) / greatest(v_cost, 1)));
    if v_n < 1 then
      v_n := 0;
      v_cost := 0;
    else
      select q.units, q.total into v_got, v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
      v_n := least(v_n, coalesce(v_got, 0));
      v_cost := coalesce(v_cost, 0);
    end if;
  end loop;
  v_out := jsonb_build_object('purse', v_purse, 'buy', round(v_cost), 'stores', v_trip->'supplies', 'dock', v_dock, 'crew', v_crew,
                              'reserve', v_res, 'sea', v_sea, 'need', round(v_need), 'after', round(v_purse - v_cost - v_need),
                              'hull', v_hull, 'hull_left', v_left, 'units', v_n);
  if v_purse >= v_need and v_n0 >= 1 and v_n < 1 then
    return v_out || jsonb_build_object('wait', 'purse', 'sentence', 'purse buys too little to pay its way');
  end if;
  if v_purse - v_cost < v_need then
    return v_out || jsonb_build_object('wait', 'purse', 'sentence', format('purse %s, fees and repair need %s', to_char(v_purse, 'FM999,999,999,990'), to_char(v_need, 'FM999,999,999,990')));
  end if;
  if v_n < v_n0 then
    -- the smaller load must still pay its own way (a bring-home is not a sale)
    if v_sells then
      select q.total into v_gross from world.quote(v_dest, v_gid, v_n, 'sell', null, p_fleet) q;
      v_net := coalesce(v_gross, 0) - v_cost - coalesce(public.profit_tax(v_dest, coalesce(v_gross, 0) - v_cost, p_player), 0)
               - (v_trip->>'supplies')::numeric - (v_trip->>'wages')::numeric - v_dock;
      if v_net <= 0 then
        return v_out || jsonb_build_object('wait', 'purse', 'sentence', 'purse buys too little to pay its way');
      end if;
      v_out := v_out || jsonb_build_object('net', round(v_net));
    end if;
    v_out := v_out || jsonb_build_object('line', format('BUY %s %s', v_good, trim_scale(v_n)));
  end if;
  return v_out || jsonb_build_object('ok', true);
end
$body$
  $f$;

  execute $f$
create function public.run_cut(p_lines jsonb, p_buy text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0502: a plan's lines with its BUY line's text replaced by p_buy, wherever the BUY stands; every other line, and its order, as it was.
  select coalesce(jsonb_agg(case when e.l->>'text' like 'BUY %' then e.l || jsonb_build_object('text', p_buy) else e.l end order by e.n), '[]'::jsonb)
    from jsonb_array_elements(p_lines) with ordinality e(l, n)
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0502 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0502 values
  ('public.fleet_job_plan(uuid)', 1,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
$h$,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
  v_need  jsonb;   -- 0502: what this run asks of her purse and her hull (public.run_need)
  v_ruin  jsonb;   -- 0502: why the first of her best sales is not started
  v_judged int := 0;   -- 0502: how many of them were judged
$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$,
$h$    -- 0502 (run_guard_enabled): A RUN IS STARTED (at its buy harbour) only if her purse and her hull can bear it (public.run_need): the
    -- BUY is cut to what leaves the fees, the stores and a repair; else she WAITS (public.fleet_job_note), not stopped
    if v_at = v_buy and public.run_guard_on() then
      v_need := public.run_need(j.player_id, f.id, f.port_id, v_lines);
      if v_need ? 'wait' then
        return v_need;
      end if;
      if v_need ? 'line' then
        v_lines := public.run_cut(v_lines, v_need->>'line');
      end if;
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$),
  ('public.fleet_job_plan(uuid)', 3,
$h$    return jsonb_build_object('lines', v_lines, 'version', f.version,
                              'note', jsonb_build_object('kind', 'land',$h$,
$h$    -- 0502: a haul that leaves the land's harbour, the same guard
    if v_at = v_land and public.run_guard_on() then
      v_need := public.run_need(j.player_id, f.id, f.port_id, v_lines);
      if v_need ? 'wait' then
        return v_need;
      end if;
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version,
                              'note', jsonb_build_object('kind', 'land',$h$),
  ('public.fleet_job_plan(uuid)', 4,
$h$      v_lines := v_s->'lines';
$h$,
$h$      v_lines := v_s->'lines';
      -- 0502 (run_guard_enabled): the first of her four best sales her purse and her hull can bear, its BUY cut to what leaves the fees,
      -- the stores and a repair (public.run_need)
      if public.run_guard_on() then
        exit when v_judged >= 4;
        v_judged := v_judged + 1;
        v_need := public.run_need(j.player_id, f.id, f.port_id, v_lines);
        if v_need ? 'wait' then
          v_ruin := coalesce(v_ruin, v_need);
          continue;
        end if;
        if v_need ? 'line' then
          v_lines := public.run_cut(v_lines, v_need->>'line');
          s.e := s.e || jsonb_build_object('units', v_need->'units');
          s.profit := coalesce((v_need->>'net')::numeric, s.profit);
        end if;
      end if;
$h$),
  ('public.fleet_job_plan(uuid)', 5,
$h$    end loop;
$h$,
$h$    end loop;
    -- 0502: every sale judged would ruin her: she WAITS with the best one's reason (public.fleet_job_note), not stopped
    if v_ruin is not null then
      return v_ruin;
    end if;
$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$  elsif p_plan->>'wait' = 'low' then
$h$,
$h$  elsif p_plan->>'wait' in ('purse', 'danger') then
    -- 0502: her purse or her hull cannot bear the run: she waits as 0498's `low` waits (asked again no sooner than 10 minutes on)
    update public.fleet_jobs
       set next_at = now() + make_interval(secs => greatest(600, coalesce(public.wc_num('fleet_jobs_wait_s'), 900))),
           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait', 'sentence', p_plan->>'sentence', 'purse', p_plan->'purse', 'need', p_plan->'need',
                                     'hull', p_plan->'hull', 'hull_left', p_plan->'hull_left')
     where fleet_id = p_fleet and paused_reason is null;
  elsif p_plan->>'wait' = 'low' then
$h$);

  for v_h in select h.fn from hunks_0502 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0502 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0502 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0502 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0502 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0502 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0502 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0502 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's' and p.prosecdef) <> 3
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0502 self-assert FAIL: a new function is reachable by a client or service_role, or is not a STABLE definer read';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key not in ('run_guard_enabled', 'run_guard_hull_share')) <> v_cfg_before
     or public.wc('run_guard_enabled') is distinct from 'false'::jsonb or public.run_guard_on() or public.wc_num('run_guard_hull_share') <> 0.5 then
    raise exception '0502 self-assert FAIL: a knob other than the two new moved, or the switch is not false';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel (its own company's rows; two market rows written) ──
  begin
    v_me := public.new_house(c_uid, 'Casa da Reserva 0502', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.players p set ducats = 50000000 where p.id = v_me;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'jobs_wait_enabled';   -- this probe's own question alone
    perform cmd.assume_identity(c_uid);
    -- THE RUN, BUILT as 0498's: static rows choose the pair
    select g.code, g.id, k.code, k.to_port into v_good, v_gid, v_sell, v_dest
      from public.npc_known_legs(v_lis) k
      join public.port_goods ps on ps.port_id = k.to_port
      join public.goods g on g.id = ps.good_id
      join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
     where public.port_offers(v_lis, g.id)
       and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
       and not public.culture_refuses(pd.culture, g.culture_mask)
       and public.fleet_free_hold(v_fl) >= 20 * g.bulk
     order by k.nm, g.base_value desc, g.code limit 1;
    if v_good is null then
      raise exception '0502 self-assert FAIL: the probe found no good Lisbon offers that a remembered harbour takes (static rows, not the market)';
    end if;
    update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0,
                                    glut = 0.5, glut_at = now(), haul = 1
     where pg.port_id = v_lis and pg.good_id = v_gid;
    update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0,
                                    glut = -0.5, glut_at = now()
     where pg.port_id = v_dest and pg.good_id = v_gid;
    perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));

    -- (a) DARK: the plan it was
    v_p0 := public.fleet_job_plan(v_fl);
    if (select e->>'text' from jsonb_array_elements(v_p0->'lines') e where e->>'text' like 'BUY %') is distinct from format('BUY %s ALL', v_good) then
      raise exception '0502 self-assert FAIL: dark, the fixed plan is not BUY ALL: %', left(v_p0::text, 300);
    end if;
    -- (b) LIT, A DEEP PURSE, A WIDE BOUND: the same plan to the letter; the need adds up, the dock fees are the cargo's she will carry
    update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
    update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';
    v_p := public.fleet_job_plan(v_fl);
    if v_p is distinct from v_p0 then
      raise exception '0502 self-assert FAIL: lit, with a deep purse the plan moved: % from %', left(v_p::text, 300), left(v_p0::text, 300);
    end if;
    v_need := public.run_need(v_me, v_fl, v_lis, v_p0->'lines');
    v_dock := (select coalesce(sum(public.port_fee((select p.id from public.ports p where p.code = substr(e->>'text', 6)), v_me, (v_need->>'buy')::numeric)), 0)
                 from jsonb_array_elements(v_p0->'lines') e where e->>'text' like 'SAIL %');
    if not coalesce((v_need->>'ok')::boolean, false) or v_need ? 'unpriced' or v_need ? 'line' or abs((v_need->>'dock')::numeric - v_dock) > 5
       or (v_need->>'reserve')::numeric <= 0 or (v_need->>'units')::numeric < 1
       or (v_need->>'need')::numeric <> round((v_need->>'stores')::numeric + (v_need->>'dock')::numeric + (v_need->>'crew')::numeric + (v_need->>'reserve')::numeric + (v_need->>'sea')::numeric) then
      raise exception '0502 self-assert FAIL: the need of the built run does not add up (dock %): %', v_dock, v_need;
    end if;
    -- the cut finds the BUY by its verb and leaves every other line
    if public.run_cut('[{"text": "PROVISION DAYS 8"}, {"text": "HIRE 2"}, {"text": "BUY x ALL"}, {"text": "SAIL CAD", "path": [[1, 2]]}, {"text": "SELL x ALL"}]', 'BUY x 4')
       is distinct from '[{"text": "PROVISION DAYS 8"}, {"text": "HIRE 2"}, {"text": "BUY x 4"}, {"text": "SAIL CAD", "path": [[1, 2]]}, {"text": "SELL x ALL"}]'::jsonb then
      raise exception '0502 self-assert FAIL: the cut moved a line that is not the BUY';
    end if;
    -- (c) LIT, THE PURSE COVERS THE NEED AND HALF THE BUY: the BUY is cut, and what is left covers the need; or the smaller load would
    -- not pay its way and she waits. (BUY ALL may stand: her purse buys in whole steps, and the odd coin may cover the need)
    update public.players p set ducats = ((v_need->>'need')::numeric + (v_need->>'buy')::numeric / 2)::bigint where p.id = v_me;
    v_p := public.fleet_job_plan(v_fl);
    if v_p ? 'lines' then
      v_w := public.run_need(v_me, v_fl, v_lis, v_p->'lines');
      if (select e->>'text' from jsonb_array_elements(v_p->'lines') e where e->>'text' like 'BUY %') !~ ('^BUY ' || v_good || ' ([0-9.]+|ALL)$') or coalesce((v_w->>'after')::numeric, -1) < 0 or v_w ? 'line'
         or (v_w->>'units')::numeric >= (v_need->>'units')::numeric then
        raise exception '0502 self-assert FAIL: with half the coin the BUY is not cut to what leaves the need: % need %', left(v_p::text, 200), v_w;
      end if;
      v_note := format('cut to %s of %s %s', v_w->>'units', v_need->>'units', v_good);
    elsif v_p->>'wait' is distinct from 'purse' then
      raise exception '0502 self-assert FAIL: with half the coin she neither cuts nor waits: %', left(v_p::text, 300);
    else
      v_note := 'the smaller load would not pay its way: waits';
    end if;
    -- (d) LIT, THE PURSE IS UNDER THE REPAIR ALONE: she waits, says why, is not stopped, orders nothing, is not due
    update public.players p set ducats = ((v_need->>'reserve')::numeric / 2)::bigint where p.id = v_me;
    v_p := public.fleet_job_plan(v_fl);
    if v_p->>'wait' is distinct from 'purse' or v_p ? 'lines' or coalesce(v_p->>'sentence', '') !~ '^purse ' then
      raise exception '0502 self-assert FAIL: a purse under the repair starts a run: %', left(v_p::text, 300);
    end if;
    perform public.fleet_job_note(v_fl, v_p);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fl;
    v_w := world.workers() #> '{workers,0}';
    if v_j.paused_reason is not null or v_j.runs <> 0 or v_j.next_at < now() + interval '600 seconds' or v_j.last->>'wait' <> 'purse'
       or exists (select 1 from public.orders o where o.fleet_id = v_fl) or exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl)
       or v_w #>> '{wait,code}' is distinct from 'purse' or v_w #>> '{wait,sentence}' is distinct from v_p->>'sentence' then
      raise exception '0502 self-assert FAIL: she did not wait for her purse: % / %', to_jsonb(v_j), v_w;
    end if;
    -- (e) LIT, THE DANGER, by its bound (no dice, no sea asked a sign): over it she waits; a worse hull has less left
    update public.players p set ducats = 50000000 where p.id = v_me;
    update public.fleet_jobs set next_at = null, last = null where fleet_id = v_fl;
    update public.world_config set value = '-1'::jsonb where key = 'run_guard_hull_share';
    v_p := public.fleet_job_plan(v_fl);
    if v_p->>'wait' is distinct from 'danger' or v_p->>'sentence' is distinct from 'too dangerous for her hull' then
      raise exception '0502 self-assert FAIL: over the bound the run is started: %', left(v_p::text, 300);
    end if;
    update public.ships s set durability = s.durability / 2 where s.fleet_id = v_fl;
    v_w := public.run_need(v_me, v_fl, v_lis, v_p0->'lines');
    if (v_w->>'hull_left')::numeric >= (v_p->>'hull_left')::numeric or (v_w->>'hull')::numeric < (v_p->>'hull')::numeric or (v_p->>'hull')::numeric < 0 then
      raise exception '0502 self-assert FAIL: a worse hull reads as well as a sound one: % / %', v_p, v_w;
    end if;
    v_note := v_note || format('; need %s (stores %s, dock %s, crew %s, repair %s, sea %s), hull %s of %s', v_need->>'need', v_need->>'stores', v_need->>'dock',
                               v_need->>'crew', v_need->>'reserve', v_need->>'sea', v_need->>'hull', v_need->>'hull_left');
    raise exception using errcode = 'ZX502', message = 'PROBE_ROLLBACK_0502';
  exception when sqlstate 'ZX502' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0502 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Reserva 0502' or p.auth_uid = c_uid)
     or public.wc('run_guard_enabled') is distinct from 'false'::jsonb or public.wc_num('run_guard_hull_share') <> 0.5 then
    raise exception '0502 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0502 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0502 self-assert ok: NO RUINOUS RUN (dark). Six hunks once and reversing; three new functions STABLE and server only; no other function moved; two knobs (run_guard_enabled false, run_guard_hull_share 0.5). Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
