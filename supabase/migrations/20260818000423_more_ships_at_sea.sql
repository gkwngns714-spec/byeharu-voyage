-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0423 - MORE SHIPS AT SEA  (a merchant rests two minutes, not ten; prices more loops before she waits; is asked again within half an hour;
--        a capital loads as many cargo ships as its cities need; a navy ship watches her own sea under sail and lies four minutes, not six hours)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "why are there still ships that are laid up, or in port this much? make it so that it fixes and have as much as ships
-- available at sea possible."
--
-- WHY (prod, read-only, 2026-11-14 17:56 UTC, head 0420; docs/dev-log/2026-11-15-at-sea.md; scripts/ops/harness/at-sea/measure.sql):
--   MERCHANTS 885: sailing 625, laid up 123, resting at home 110, port time 24, mid-lap 3.
--     * RESTING 110 (12 %): route_rest_voyage_days 1.333333 was set (0116) to be 120 real seconds; 0413 made a voyage-day five times as long,
--       so the rest became 600 s. A lap is 45 min (median), 63 (mean); her rest is a seventh of her life.
--     * LAID UP 123 ("no loop of hers pays", 0181): 85 refused four times or more in a row, so asked once in 50 minutes; 8 broke; 9 pirate houses;
--       0 shut by the sea; their home harbours are NOT full (of the goods each makes, at most 2 of 4 to 10 have npc_buyers_per_good buyers).
--       22 have a stop whose city's purse is under 10,000 (0410 rightly carries nothing there); 22 lie at a harbour with under 50,000.
--       What is left is the planner's reach: she prices her own loop and the loops npc_loop_candidates offers FROM HER HOME, 5 near, 6 trade,
--       the rest three-stop among the 5 near, 16 in all. A paying loop to the 6th to 8th nearest harbour is never priced (proof 120 builds one).
--   CARGO SHIPS 372: sailing 53, at home idle with nothing aboard 306 (port time over), laid up 11 (Mongolia over its number), away 2.
--     271 have never loaded. 84 cities are under their aid target, short 17.3 M; 12.1 M is aboard. public.cargo_ships_load loads ONE ship a
--     capital a run (hourly, in public.city_day): 8 loads in the last hour, 36 in the five before. There is cargo to carry; the rule holds it.
--   NAVY 43: sailing 14, lying HUNTING 29 (mission HUNT, at a harbour until hunt_until), unpaid 0, over the number 0, laid up 0. In port: median
--     208 minutes, mean 21 hours. navy_hunt_hours 6 is REAL hours (0413 kept it so): a ship lies six hours at her hunt harbour, or at her own
--     station when her own sea is the most dangerous, and picks again (often her own sea again). navy_hunt_per_day (0, the owner's) is not moved.
--
-- WHAT THIS FILE DOES (each cause, its own knob, its old value):
--   M1. route_rest_voyage_days 1.333333 -> 0.266667: her rest at home is 120 real seconds again (0.27 voyage-days at time_compression 192).
--   M2. THE PLANNER PRICES MORE LOOPS (knobs only; public.npc_loop_candidates reads them): npc_route_neighbours 5 -> 8 (out-and-back and
--       three-stop loops to the 8 nearest harbours), npc_route_trade_candidates 6 -> 10, npc_route_candidates 16 -> 24. The guard stands: a loop
--       is sailed with a BUY only when a lap of it nets above nothing after tax, wages, stores and every dock fee (0186, 0406), and a parcel is no
--       bigger than the sink's purse can pay (0410). Nothing she would lose on is ever bought; she only sees more.
--   M3. THE BACK-OFF STOPS AT HALF AN HOUR: npc_ask_wait_max_minutes (new, 30; 0 = 0407's longest wait, 50): a merchant refused again is asked
--       10, 20, then every 30 minutes (0420 reprices every harbour every 15 minutes, so a 50-minute wait missed three new prices). A broke house
--       still waits the longest (50): an ask cannot give her a purse. One hunk in public.npc_waiting_queue.
--   C1. A CAPITAL LOADS AS MANY SHIPS AS ITS CITIES NEED, IN ONE RUN: convoy_loads_per_run (new, 10; was one) ships a capital a run, each with at
--       most convoy_load_max (new, 1,000,000; 0 = no cap) aboard, from the homes with the most room first. Each load is the old one: her row
--       held, her home's purse tried and never waited for, the need less what every ship of the realm already carries, read again for each.
--       A home gives its room ONCE A RUN however many ships load there (its room as the run first read it, less each load): no donor is called
--       past 0307's share a run. Money is closed: public.convoy_book moves every ducat from a purse to the ship (CONVOY_LOAD), as before.
--       Six hunks in public.cargo_ships_load.
--   N1. navy_hunt_hours 6 -> 0.0625: a hunter lies half a voyage-day (225 real seconds at 192) at the harbour of the sea she hunts, then sails home.
--       Judged against 0422 (PR #698): a navy ship sails 4.5 times her own speed, so a patrol leg takes under a third of what it did; a lie longer
--       than a leg or two would keep her in port most of her time.
--   N2. HER OWN SEA, UNDER SAIL: navy_own_sea_patrol (new, true; false = 0340's lie at her station): when her own sea is the most dangerous in
--       reach she sails her station's patrol (its stops are her own waters, public.navy_patrol_build) instead of lying at her station; the hunt
--       pass (public.navy_hunt_pass) fights a pirate in her sea whether she is docked or under sail. One hunk in public.navy_hunt_step.
--
-- NOT DONE (said, for the owner): a laid-up house does not move her home (a move is a ballast passage at a loss); a cargo ship with nothing to carry
--   stays home (no circuit in ballast); Mongolia's 11 surplus cargo ships stay laid up (its number follows its purse, 0326); port_prep_seconds
--   (60 s at every call, players too) is unmoved; navy_hunt_per_day is the owner's.
-- LOAD (the PR body and the dev-log have the sums): about +290 rows a minute (up to +380, the navy's legs at 0422's speed included) and about +8 s of work a minute (the asks' planning +5 s);
--   no job is added or rescheduled and no table is made. After everything (0419-0421, the full pirate roster, this) ~42 s of 120 a minute.
-- LOCKS: CREATE OR REPLACE x3 by hunks; knobs. TIME: the cut is milliseconds; the probe reads the waiting line six times for one merchant and loads
--   one capital's ships once, rolled back: expected under 5 s. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/at-sea/rollback-0423.sql, a draft. At once with no file: the six knobs back to their old values
--   (npc_ask_wait_max_minutes 0, convoy_loads_per_run 1, convoy_load_max 0 and navy_own_sea_patrol false restore the old rules exactly).
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0423 = 0422 + 1. 0422 (PR #698, the combat speed) deploys first: it changes only voyage.fleet_speed_at and adds its own knobs and
--   functions (fleet_speed_by_kind, public.fleet_speed_mult, public.fleet_speed_set); it touches none of these bodies or knobs.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.npc_waiting_queue(timestamp with time zone)', 'public.cargo_ships_load(jsonb)',
                                 'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_kept      text := '';
  v_fleet     uuid;
  v_route     uuid;
  v_player    uuid;
  v_steps     text;
  v_note      text := 'no merchant in port to probe in this world';
  v_cnote     text := 'no cargo ship lies idle at home in this world: the loads are proof 120''s';
  v_nat       uuid;
  v_cap       uuid;
  v_city      uuid;
  v_w0        numeric;
  v_w1        numeric;
  v_r         jsonb;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key in ('npc_ask_wait_max_minutes', 'convoy_loads_per_run', 'convoy_load_max', 'navy_own_sea_patrol')) then
    raise exception '0423 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.npc_waiting_queue(timestamp with time zone)') is null or to_regprocedure('public.cargo_ships_load(jsonb)') is null
     or to_regprocedure('public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null
     or not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'npc_fleets' and c.column_name = 'refused') then
    raise exception '0423 refuses: the waiting line (0407), the cargo ships'' load (0324), the hunt (0340) or the news are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0423 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0423
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE KNOBS. A knob moves only from the value this file was written against (prod's on 2026-11-14): an owner's own value is left
  --      alone and named in the receipt.
  insert into public.world_config (key, value, description) values
    ('npc_ask_wait_max_minutes', to_jsonb(30),
     '0423: the longest a laid-up merchant waits between asks (public.npc_waiting_queue): her waits double from npc_replan_every_minutes with each refusal in a row (0407) up to this, and never past npc_replan_within_minutes less npc_replan_every_minutes. A broke house (under npc_ask_broke_under) still waits that longest. 0 = 0407''s rule alone (50 minutes).'),
    ('convoy_loads_per_run', to_jsonb(10),
     '0423: the most cargo ships one capital loads in one run of public.cargo_ships_load (hourly, through public.crown_aid), each from the idle ship whose home has the most room, until its cities'' need less what its ships carry is met. 1 = 0309''s one ship a capital a run.'),
    ('convoy_load_max', to_jsonb(1000000),
     '0423: the most ducats one cargo ship is loaded with (public.cargo_ships_load). A larger need goes out on more ships, from more homes. 0 = no cap.'),
    ('navy_own_sea_patrol', 'true'::jsonb,
     '0423: when her own sea is the most dangerous in reach, a hunter sails her station''s patrol (her own waters, under sail) instead of lying at her station navy_hunt_hours (public.navy_hunt_step). false = 0340''s lie.');
  update public.world_config set value = to_jsonb(0.266667),
         description = description || ' 0423: 0.266667 (120 real seconds at time_compression 192; 0413 had stretched 1.333333 to 600 s).'
   where key = 'route_rest_voyage_days' and value = to_jsonb(1.333333);
  if not found then v_kept := v_kept || 'route_rest_voyage_days '; end if;
  update public.world_config set value = to_jsonb(8), description = description || ' 0423: 5 -> 8.' where key = 'npc_route_neighbours' and value = to_jsonb(5);
  if not found then v_kept := v_kept || 'npc_route_neighbours '; end if;
  update public.world_config set value = to_jsonb(10), description = description || ' 0423: 6 -> 10.' where key = 'npc_route_trade_candidates' and value = to_jsonb(6);
  if not found then v_kept := v_kept || 'npc_route_trade_candidates '; end if;
  update public.world_config set value = to_jsonb(24), description = description || ' 0423: 16 -> 24.' where key = 'npc_route_candidates' and value = to_jsonb(16);
  if not found then v_kept := v_kept || 'npc_route_candidates '; end if;
  update public.world_config set value = to_jsonb(0.0625),
         description = description || ' 0423: 6 -> 0.0625 (half a voyage-day, 225 s, at time_compression 192).'
   where key = 'navy_hunt_hours' and value = to_jsonb(6);
  if not found then v_kept := v_kept || 'navy_hunt_hours '; end if;

  -- ── 3. THE HUNKS ──
  create temp table hunk_0423 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0423 values
  (2, c_cut[1],
$h$                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         greatest(w.e_min, w.w_min - w.e_min)) end),
$h$,
$h$                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         -- 0423: and never past npc_ask_wait_max_minutes (0: 0407's longest wait alone)
                                                         case when w.cap > 0 then greatest(w.e_min, least(w.cap, w.w_min - w.e_min))
                                                              else greatest(w.e_min, w.w_min - w.e_min) end) end),
$h$),
  (1, c_cut[1],
$h$                      public.wc_int('npc_ask_broke_under') as broke) w   -- 0407
$h$,
$h$                      public.wc_int('npc_ask_broke_under') as broke,   -- 0407
                      public.wc_int('npc_ask_wait_max_minutes') as cap) w   -- 0423
$h$),
  (3, c_cut[2],
$h$  v_ships  int := 0;
begin
$h$,
$h$  v_ships  int := 0;
  v_i      int;   -- 0423: the ships loaded for this capital this run
  v_rooms  jsonb := '{}'::jsonb;   -- 0423: what each home may still give THIS RUN: its room as the run first found it, less what it gave
begin
$h$),
  (4, c_cut[2],
$h$    v_fleet := null;
    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat
$h$,
$h$    -- 0423: UP TO convoy_loads_per_run SHIPS FOR THIS CAPITAL (0309 loaded one), each the load below: the idle ship whose home has the most room,
    -- her row held, her home's purse tried, the need less what every ship of the realm carries read again. A loaded ship is no longer idle.
    for v_i in 1 .. greatest(1, public.wc_int('convoy_loads_per_run')) loop
    v_fleet := null;
    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat
$h$),
  (5, c_cut[2],
$h$    continue when v_fleet is null or not public.treasury_try_lock(v_home);
$h$,
$h$    exit when v_fleet is null or not public.treasury_try_lock(v_home);   -- 0423: no idle ship left, or her home's purse is busy: this capital waits for the next run
$h$),
  (6, c_cut[2],
$h$    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),
                 public.cargo_load_room(v_home, v_nat));
    continue when v_a <= 0;
$h$,
$h$    -- 0423: A HOME GIVES ITS ROOM ONCE A RUN, however many ships load there: its room (public.cargo_load_room: a share of what it holds above
    -- its target, 0307) is read the first time and what each ship takes comes off it, so a run never calls a donor past what 0324 allowed.
    if not v_rooms ? v_home::text then
      v_rooms := v_rooms || jsonb_build_object(v_home::text, public.cargo_load_room(v_home, v_nat));
    end if;
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),
                 (v_rooms ->> v_home::text)::bigint,
                 nullif(public.wc_int('convoy_load_max'), 0));   -- 0423: one ship's share at most (0: no cap; least() passes over a null)
    exit when v_a <= 0;   -- 0423: the need is met, or the home with the most room has none
    v_rooms := v_rooms || jsonb_build_object(v_home::text, (v_rooms ->> v_home::text)::bigint - v_a);
$h$),
  (7, c_cut[2],
$h$    v_ships := v_ships + 1;
  end loop;
$h$,
$h$    v_ships := v_ships + 1;
    end loop;   -- 0423
  end loop;
$h$),
  (9, c_cut[2],
$h$       and c.ord <= public.convoy_ships_of(c.nation_id)
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
$h$,
$h$       and c.ord <= public.convoy_ships_of(c.nation_id)
       and coalesce((v_rooms ->> c.home_port_id::text)::bigint, 1) > 0   -- 0423: a home that has given its room this run is passed over
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
$h$),
  (8, c_cut[3],
$h$    if t.port_id = p_home then
      perform public.fleet_mend(p_fleet);
$h$,
$h$    if t.port_id = p_home then
      -- 0423: HER OWN SEA, UNDER SAIL. She watches it on her station's patrol (its stops are her own waters) instead of lying at her station: the
      -- hunt's fields go and the step goes on to her patrol (public.navy_ship_step). navy_own_sea_patrol false: 0340's lie, below.
      if public.wc('navy_own_sea_patrol') = 'true'::jsonb then
        update public.navy_ships x set mission = case when x.mission = 'HUNT' then 'PATROL' else x.mission end, hunt_port = null, hunt_until = null
         where x.fleet_id = p_fleet and (x.mission = 'HUNT' or x.hunt_port is not null or x.hunt_until is not null);
        return null;
      end if;
      perform public.fleet_mend(p_fleet);
$h$);
  -- each body's hunks are cut together and the body is written once (a loop opened by one hunk is closed by another)
  for h in select p.fn, p.def from pre_0423 p loop
    v_def := h.def;
    for v_z in select x.ord, x.old, x.new from hunk_0423 x where x.fn = h.fn order by x.ord loop
      v_n := (length(h.def) - length(replace(h.def, v_z.old, ''))) / length(v_z.old);
      if v_n <> 1 then
        raise exception '0423 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_z.ord, h.fn, v_n;
      end if;
      v_def := replace(v_def, v_z.old, v_z.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.ord, x.new from hunk_0423 x where x.fn = h.fn order by x.ord loop
      if (length(v_def) - length(replace(v_def, v_z.new, ''))) / length(v_z.new) <> 1 then
        raise exception '0423 self-assert FAIL: hunk % of % is not in the new body once', v_z.ord, h.fn;
      end if;
    end loop;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0423 p where p.fn = h.fn) then
      raise exception '0423 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0423 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0423 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0423 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0423 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE NEWS (0347's law) ──
  perform public.news_update('0423', 'Busier seas: merchants rest less, more cargo ships sail, the navy patrols',
                             '더 붐비는 바다: 상선은 덜 쉬고, 화물선은 더 많이, 해군은 순찰한다');

  -- ── 5. THE PROBE, rolled back by a raised sentinel. It reads and writes only the rows it names.
  --   (a) ONE MERCHANT'S DUE RULE (no plan): refused 1 to 5 her asks are due 10 20 30 30 30 minutes after the last; broke, 50; the cap at 0, 0407's.
  select nf.fleet_id, nf.route_id, sr.player_id into v_fleet, v_route, v_player
    from public.npc_tend_roster() ro
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
   order by ro.k
   limit 1;
  if v_fleet is not null then
    begin
      update public.world_config set value = to_jsonb(10) where key = 'npc_replan_every_minutes';
      update public.world_config set value = to_jsonb(60) where key = 'npc_replan_within_minutes';
      update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
      update public.standing_routes set paused_reason = 'laid_up', updated_at = now() - interval '3 hours' where id = v_route;
      update public.players set ducats = 5000 where id = v_player;
      v_steps := '';
      foreach v_n in array array[1, 2, 3, 4, 5] loop
        update public.npc_fleets set refused = v_n, asked_at = null where fleet_id = v_fleet;
        v_steps := v_steps || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet) || ' ';
      end loop;
      update public.players set ducats = 99 where id = v_player;
      v_steps := v_steps || '/ broke ' || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet);
      update public.players set ducats = 5000 where id = v_player;
      update public.world_config set value = to_jsonb(0) where key = 'npc_ask_wait_max_minutes';
      v_steps := v_steps || ' / cap off';
      foreach v_n in array array[1, 2, 3, 4, 5] loop
        update public.npc_fleets set refused = v_n where fleet_id = v_fleet;
        v_steps := v_steps || ' ' || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet);
      end loop;
      if v_steps is distinct from '10 20 30 30 30 / broke 50 / cap off 10 20 40 50 50' then
        raise exception '0423 self-assert FAIL: the due rule''s steps are "%", not "10 20 30 30 30 / broke 50 / cap off 10 20 40 50 50"', v_steps;
      end if;
      v_note := 'one merchant''s due rule: ' || v_steps;
      raise exception sqlstate 'BV423';
    exception when sqlstate 'BV423' then null;
    end;
    if v_note not like 'one merchant%' then
      raise exception '0423 self-assert FAIL: the merchant probe did not run to its end';
    end if;
  end if;
  --   (b) ONE CAPITAL'S LOADS: the realm with the most idle ships at home on a circuit; one of its cities short by five ships' worth, every purse of
  --       the realm rich; public.cargo_ships_load with that one line loads more than one ship, none above convoy_load_max, and the world's money
  --       (its purses plus what is aboard) does not move.
  select c.nation_id into v_nat
    from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id
   where f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null and c.ord <= public.convoy_ships_of(c.nation_id)
     and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
     and exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(c.nation_id, c.home_port_id))
   group by c.nation_id
  having count(*) >= 2
   order by count(*) desc, c.nation_id
   limit 1;
  if v_nat is not null then
    v_cap := public.realm_capital(v_nat);
    select p.id into v_city from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1;
  end if;
  if v_nat is not null and v_city is not null then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('convoys_enabled', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
      update public.port_treasury t set ducats = 1000000000, reserve = 0 where public.port_nation(t.port_id) = v_nat;
      update public.port_treasury t set ducats = 0 where t.port_id = v_city;
      v_w0 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t where public.port_nation(t.port_id) = v_nat) + public.funds_aboard();
      v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_city, 'cap', v_cap,
                                                                          'target', 5 * public.wc_int('convoy_load_max'))));
      v_w1 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t where public.port_nation(t.port_id) = v_nat) + public.funds_aboard();
      if coalesce((v_r->>'ships')::int, 0) < 2 or (v_r->>'loaded')::bigint > (v_r->>'ships')::bigint * public.wc_int('convoy_load_max') or v_w1 <> v_w0 then
        raise exception '0423 self-assert FAIL: one capital''s run loaded % (money before %, after %)', v_r, v_w0, v_w1;
      end if;
      v_cnote := 'one capital''s run loaded ' || (v_r->>'ships') || ' ships, ' || (v_r->>'loaded') || ' d., the realm''s money unmoved';
      raise exception sqlstate 'BV423';
    exception when sqlstate 'BV423' then null;
    end;
    if v_cnote not like 'one capital%' then
      raise exception '0423 self-assert FAIL: the cargo probe did not run to its end';
    end if;
  end if;
  if public.wc_int('npc_ask_wait_max_minutes') <> 30 or public.wc_int('convoy_loads_per_run') <> 10 or public.wc_int('convoy_load_max') <> 1000000
     or public.wc('navy_own_sea_patrol') <> 'true'::jsonb then
    raise exception '0423 self-assert FAIL: the new knobs are not this file''s (or the probe was not rolled back)';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0423 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0423 self-assert ok: MORE SHIPS AT SEA. Nine hunks over three bodies, each once and reversing; grants and volatility unmoved; no other function moved. Knobs: rest % voyage-days, neighbours %, trade %, candidates %, hunt % h; new npc_ask_wait_max_minutes 30, convoy_loads_per_run 10, convoy_load_max 1,000,000, navy_own_sea_patrol true.% Probe: %; %; % ms.',
    public.wc_num('route_rest_voyage_days'), public.wc_int('npc_route_neighbours'), public.wc_int('npc_route_trade_candidates'), public.wc_int('npc_route_candidates'),
    public.wc_num('navy_hunt_hours'), case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note, v_cnote,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
