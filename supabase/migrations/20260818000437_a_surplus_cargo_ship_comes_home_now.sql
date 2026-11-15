-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0437 - A SURPLUS CARGO SHIP COMES HOME NOW  (a cargo ship over her country's share drops her circuit at the next port and sails straight home
--        with what is left aboard, and lays up there; a retired ship is out of the fleet's count; a cargo ship with nothing on board says what
--        she is doing: Returning, At home, Laid up)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15 (after 0430): "there are still cargo ships that have 0 gold. if they are returning after they provided transport, instead
-- of 0 gold, say it is returning." and "you still haven't reduce the numbers right".
--
-- WHY (prod 09:03 UTC, head 0432, scripts/ops/harness/cargo-home/before.sql; docs/dev-log/2026-11-15-cargo-home.md): 377 cargo rows, 114 laid up,
--   263 in service against shares summing to 100. The 163 surplus (ord over the share): 45 at sea WITH GOLD on a lap (3.96 M aboard; 17 legs of
--   their circuit still to sail at the median, 37 at most: 41,373 nm median at 41.4 nm a real minute, ~17 hours, up to ~24); 70 sailing home empty;
--   46 empty on a leg begun before 0430 (all after a DELIVERED; they turn home at the next port by 0430); 1 docked away, 1 home on a lap. 0 idle at
--   home: the retire keeps up with every ship that reaches home.
-- ROOT CAUSE OF THE SLOW CUT:
--   (1) 0430 lets a surplus ship WITH GOLD ABOARD sail her whole circuit (public.cargo_ship_step: "With funds still aboard she sails on to the next
--       city, as before"), and the retire (public.cargo_ships_retire, 0326) takes only a ship docked at home with no lap and nothing aboard. A circuit
--       visits every city of the realm, so the last of these ships comes home about a day after the cut.
--   (2) An idle surplus ship at home could be sent to a NEW home first (public.cargo_rebase, convoy_rich_enabled is lit on prod): the job steps the
--       idle ships after the retire's 10 a run, so at 0430's deploy (~196 idle surplus) some of them sailed off empty to another harbour instead
--       of laying up (part of the 70 "sailing home").
--   (3) Rows: a laid-up ship stays a row (0326's law: her book, public.convoy_cargo, is append-only and names her; a share that rises wakes her by
--       her ord). The Stats count (public.stats_fleets_count, public.stats_fleet_list_rows) counted those rows as cargo ships: 377.
--
-- WHAT THIS FILE DOES:
--   S1. A SURPLUS SHIP COMES HOME NOW (public.cargo_ship_step, 4 hunks). v_sur: lit, and her ord is over public.convoy_ships_of (one indexed read).
--       Away (after this city's delivery, which stands: she gives what the city is short first): she drops the rest of her circuit and sails ONE
--       leg straight home, the course 0430's HOMEWARD leg takes (public.cargo_circuit_plan legs[0]), with what is left aboard: RECALLED. At home the
--       lap closes as before (HOME: what is left is RETURNED to the port it was loaded at, her home; public.tg_convoy_cargo_closes holds that), so no
--       gold is lost or made. A load taken while she was inside her share and not yet gone sails as before: its first city was short of it,
--       so she delivers there first and is then recalled. Idle at home she waits for the retire (IDLE) and is never sent to a new home first. A ship at sea keeps her leg to its port (there is no course from open water): the
--       turn is at the next port. Inside the share nothing changes.
--   S2. THE RETIRE IS UNCHANGED (0326): a surplus ship docked at home, no lap, nothing aboard, lays up, convoy_retire_per_run (10) a run, highest
--       ord first. Laying up writes laid_up_at and nothing else: no gold, no book row. THE DECOMMISSION is the lay-up: the codebase has no other
--       path that removes a cargo ship (the only delete of a ship is public.cargo_hull's refit), and her row cannot go (her book names her).
--   S3. A RETIRED SHIP IS OUT OF THE FLEET'S COUNT (public.stats_fleets_count, public.stats_fleet_list_rows, one hunk each): the Stats count
--       counts and lists the cargo ships in service only (laid_up_at null), so the Ships and Cargo faces read ~100, not 377. The navy and pirates
--       are counted as before (their lay-ups are unpaid ships that wake).
--   S4. WHAT A CARGO SHIP IS DOING, ONE WORD (new public.cargo_ship_state, stable): LAID_UP, LOADED (gold on board), HOME (docked at her home,
--       nothing on board), RETURNING (anywhere else with nothing on board: since 0430 an empty ship's next leg is home). Served as `state` on her
--       map card (world.cargo_ship_card, 3 hunks; `next` and `stops_left` only while she is loaded and inside her share, so a ship sailing home no
--       longer lists the circuit she dropped) and on her Stats page (world.stats_fleet, 1 hunk, `cargo.state`). The client prints the word where
--       it printed 0 gold.
--   KNOBS: none.
--
-- EXPECTED (from the 09:03 read): in service 263 -> 100. The 70 sailing home arrive in 64 min at the median (p90 194, max 383) and lay up the
--   minute they dock; the 46 empty on old legs reach their port in 38 min at the median, then one leg home; the 45 with gold reach their next
--   port in 26 min at the median (max 97), give what that city is short, then one leg home (before 0437: ~17 h median, ~24 h at most). About
--   half the surplus is retired within an hour, most within ~3 h, the last when the longest homeward leg ends (~6-7 h). The floor is the sea:
--   a leg already sailed is not cut.
-- budget: no job, no table, no knob. Rows: the lay-ups are 1 row each, at most convoy_retire_per_run (10) a run of byeharu-voyage:cargo-ships, ~163
--   in all over the hours above, then 0. A RECALLED leg replaces the rest of a circuit (up to 37 legs: fewer voyage, stores and arrival rows), and
--   163 fewer ships in service cut the job's steps, upkeep and voyage rows: net FEWER rows a minute than today.
-- LOCKS: CREATE OR REPLACE x5 (by hunks: 10), CREATE FUNCTION x1. TIME: the cut is milliseconds; the probe (one ship made, recalled, home, retired,
--   rolled back) under 5 s. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/cargo-home/rollback-0437.sql (a draft: the hunks reversed, the function dropped).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the re-cut functions unmoved; no other function moved;
--   the new function stable, definer, server-only. THE PROBE, rolled back, on ANY world (the CI world has no cargo ship and convoys dark: the probe
--   lights them inside itself): one cargo ship made over her country's share, loaded 5,000 and docked at a rich city of her realm on a lap ->
--   RECALLED, sailing home with the 5,000; home -> HOME, 5,000 RETURNED; idle at a home that is no origin ->
--   IDLE (before 0437 she sailed to a new home); her state at each step (LOADED, HOME, RETURNING, LAID_UP) and her card's; the retire lays her up;
--   the Stats count and list leave her out; no gold moves.
-- VERSION: 0437 (0433-0436 are queued branches: #723, #726, #730 and the battle screen; 0432 #721). None of them touches these bodies but 0432,
--   whose hunk of public.stats_fleets_count (the `attacks` line) is disjoint from this file's (the cargo `join`): each occurs once on either body.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_meta      text;
  v_h         record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_nat       uuid;
  v_cap       uuid;
  v_city      uuid;
  v_ord       int;
  v_fl        uuid;
  v_pl        uuid;
  v_load      bigint;
  v_cir       bigint;
  v_r         text;
  v_w         numeric;
  v_card      jsonb;
  v_note      text;
  v_conv      jsonb;
  c_hunked    constant text[] := array['public.cargo_ship_step(uuid,timestamp with time zone)', 'world.cargo_ship_card(uuid)', 'world.stats_fleet(uuid)',
                                       'public.stats_fleet_list_rows(text,timestamp with time zone)',
                                       'public.stats_fleets_count(timestamp with time zone,timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.cargo_ships_retire(uuid,timestamp with time zone)') is null or to_regprocedure('public.cargo_circuit_plan(uuid,uuid,uuid)') is null
     or to_regprocedure('public.convoy_ships_of(uuid)') is null or to_regprocedure('world.stats_fleet(uuid)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or not exists (select 1 from public.world_config where key = 'cargo_fleet_total') then
    raise exception '0437 refuses: 0430 (a hundred cargo ships), 0431 (the Stats fleet pages) or the news are not all in this world';
  end if;
  if to_regprocedure('public.cargo_ship_state(uuid)') is not null then
    raise exception '0437 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 2. THE ONE WORD (S4) ──
  execute $f$
create function public.cargo_ship_state(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0437 (the owner, 2026-11-15: "if they are returning after they provided transport, instead of 0 gold, say it is returning"): THE one word for
  -- what a cargo ship is doing with her gold. LAID_UP: retired (0326). LOADED: gold on board (the card shows the gold). HOME: docked at her home,
  -- nothing on board. RETURNING: anywhere else with nothing on board (since 0430 an empty ship's next leg is home; a ship over her share is sent
  -- home by 0437). Null: no such cargo ship. Read by world.cargo_ship_card and world.stats_fleet. Two reads by key and her open load.
  select case when c.laid_up_at is not null then 'LAID_UP'
              when exists (select 1 from public.cargo_ship_aboard(c.fleet_id)) then 'LOADED'
              when f.status <> 'SAILING' and f.port_id = c.home_port_id then 'HOME'
              else 'RETURNING' end
    from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
   where c.fleet_id = p_fleet
$body$
  $f$;
  revoke all on function public.cargo_ship_state(uuid) from public, anon, authenticated;
  comment on function public.cargo_ship_state(uuid) is '0437: what a cargo ship is doing with her gold, one word: LAID_UP, LOADED, HOME or RETURNING. Server-only; served on her card and Stats page.';

  -- ── 3. THE HUNKS ──
  create temp table hunks_0437 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0437 values
  -- S1. a surplus ship comes home now
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_home  jsonb;
begin
$h$,
$h$  v_home  jsonb;
  v_sur   boolean;   -- 0437: her ord is over her country's share
begin
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$  v_left := coalesce(v_left, 0);
$h$,
$h$  v_left := coalesce(v_left, 0);
  v_sur := v_lit and c.ord > public.convoy_ships_of(c.nation_id);   -- 0437: a surplus ship: she comes home now and lays up there (public.cargo_ships_retire)
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 3,
$h$      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$,
$h$      if v_sur then
        return 'IDLE';   -- 0437: a surplus ship idle at home waits for the retire; she is never sent off to a new home first
      end if;
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 4,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$,
$h$    -- 0437: A SURPLUS SHIP COMES HOME NOW (owner 2026-11-15: "you still haven't reduce the numbers right"). Her ord is over her country's share, so she
    -- takes no new load and lays up at home. Here, after this city's delivery above, she drops the rest of her circuit and sails ONE leg straight home
    -- with whatever is left aboard (before 0437 she sailed the whole circuit first, up to 37 legs). At home the lap closes as before (HOME: the rest is
    -- RETURNED to the port it was loaded at, her home), so no gold is lost. No course home: she goes on by the circuit, whose last leg is home.
    if v_sur then
      if f.ready_at is not null and f.ready_at > p_now then
        return 'IN_PORT';
      end if;
      v_home := public.cargo_circuit_plan(c.nation_id, f.port_id, c.home_port_id) #> '{legs,0}';
      if v_home is not null then
        perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: this leg too, as every leg
        perform voyage.depart(p_fleet, voyage.segments_from_course(v_home -> 'course'), f.port_id, c.home_port_id, p_now);
        return case when exists (select 1 from public.cargo_ship_aboard(p_fleet)) then 'RECALLED' else 'HOMEWARD' end;   -- 0437: RECALLED with gold aboard; empty, 0430's word
      end if;
    end if;
    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$),
  -- S4. her card says what she is doing
  ('world.cargo_ship_card(uuid)', 1,
$h$  w record;
begin
$h$,
$h$  w record;
  v_state text := public.cargo_ship_state(p_fleet);   -- 0437: LOADED, RETURNING, HOME or LAID_UP
begin
$h$),
  ('world.cargo_ship_card(uuid)', 2,
$h$    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$,
$h$    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
    'state', v_state,   -- 0437: with nothing on board the card says this word, not 0 gold
$h$),
  ('world.cargo_ship_card(uuid)', 3,
$h$                      where l.circuit_id = c.circuit_id and l.ord > c.leg order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg),
$h$,
$h$                      where l.circuit_id = c.circuit_id and l.ord > c.leg and v_state = 'LOADED' and c.ord <= public.convoy_ships_of(c.nation_id) order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg
                    and v_state = 'LOADED' and c.ord <= public.convoy_ships_of(c.nation_id)),   -- 0437: a ship going home (empty, or over her share) has no circuit ahead
$h$),
  ('world.stats_fleet(uuid)', 1,
$h$      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$,
$h$      'state', public.cargo_ship_state(p_fleet),   -- 0437: LOADED, RETURNING, HOME or LAID_UP; the page says the word when nothing is on board
      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$),
  -- S3. a retired ship is out of the fleet's count
  ('public.stats_fleet_list_rows(text,timestamp with time zone)', 1,
$h$from public.cargo_ships c where p_kind = 'CARGO'),
$h$,
$h$from public.cargo_ships c where p_kind = 'CARGO' and c.laid_up_at is null),   -- 0437: a retired (laid-up) cargo ship is out of the fleet
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id
$h$,
$h$           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id and c.laid_up_at is null   -- 0437: a retired (laid-up) cargo ship is out of the fleet's count
$h$);

  for v_h in select h.fn from hunks_0437 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0437 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0437 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0437 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0437 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0437 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid <> 'public.cargo_ship_state(uuid)'::regprocedure) <> v_fn_before then
    raise exception '0437 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta then
    raise exception '0437 self-assert FAIL: the grants, volatility, definer, search path or owner of a re-cut function moved';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.cargo_ship_state(uuid)'::regprocedure and p.provolatile = 's' and p.prosecdef
                    and p.proconfig is not null and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) then
    raise exception '0437 self-assert FAIL: public.cargo_ship_state is not stable, definer, with its search path and server-only';
  end if;

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0437', 'A cargo ship over her country''s share comes home at once and retires; a ship with nothing on board says "Returning"',
                             '나라 몫을 넘는 화물선은 곧장 귀항해 퇴역한다; 빈 화물선은 "귀환 중"이라 표시한다');

  -- ── 6. THE PROBE, rolled back by a raised sentinel. On any world: the convoys are lit for it here (the CI world has them dark and no cargo ship).
  --   Knobs are written only to existing keys and never read by a wc_* in a WHERE of this block.
  begin
    select jsonb_object_agg(w.key, w.value) into v_conv from public.world_config w where w.key in ('convoys_enabled', 'convoy_rich_enabled');
    update public.world_config set value = 'true'::jsonb where key in ('convoys_enabled', 'city_treasury_enabled');
    update public.world_config set value = 'false'::jsonb where key in ('convoy_rich_enabled', 'convoy_armed_enabled');
    update public.world_config set value = to_jsonb(1000) where key = 'convoy_commission_per_run';
    -- a crown with a share and a city of her realm with a course home (Portugal first, as proof 131)
    select g.nation_id into v_nat
      from public.great_powers g join public.nations n on n.id = g.nation_id join public.cargo_fleet_sizes s on s.nation_id = g.nation_id
     where not g.pirate and public.realm_capital(g.nation_id) is not null
     order by (n.code = 'PRT') desc, s.ships desc, n.code
     limit 1;
    if v_nat is null then
      raise exception '0437 self-assert FAIL: no crown with a share in this world';
    end if;
    v_cap := public.realm_capital(v_nat);
    for v_city in select p.id from public.ports p
                   where p.kind = 'HARBOUR' and p.id <> v_cap and public.port_nation(p.id) = v_nat
                     and exists (select 1 from public.npc_courses k where k.from_port = p.id or k.to_port = p.id)
                   order by p.code limit 6 loop
      exit when public.cargo_circuit_plan(v_nat, v_city, v_cap) #> '{legs,0}' is not null;
    end loop;
    if v_city is null or public.cargo_circuit_plan(v_nat, v_city, v_cap) #> '{legs,0}' is null then
      raise exception '0437 self-assert FAIL: no city of % has a course to her capital', (select n.code from public.nations n where n.id = v_nat);
    end if;
    -- one ship made over the share: the share is raised to her ord, she is commissioned, the share cut back under her
    v_ord := greatest(coalesce((select max(c.ord) from public.cargo_ships c where c.nation_id = v_nat), 0) + 1, 2);
    update public.cargo_fleet_sizes s set ships = v_ord, read_at = now() + interval '2 hours' where s.nation_id = v_nat;
    perform public.cargo_ships_commission(v_nat);
    select c.fleet_id, c.player_id into v_fl, v_pl from public.cargo_ships c where c.nation_id = v_nat and c.ord = v_ord and c.home_port_id = v_cap;
    if v_fl is null or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' or (select f.port_id from public.fleets f where f.id = v_fl) <> v_cap then
      raise exception '0437 self-assert FAIL: the probe ship (ord %) was not made docked at her capital', v_ord;
    end if;
    update public.cargo_fleet_sizes s set ships = v_ord - 1 where s.nation_id = v_nat;
    insert into public.port_treasury (port_id) values (v_cap), (v_city) on conflict (port_id) do nothing;
    update public.port_treasury t set ducats = 100000000, reserve = 0 where t.port_id = v_cap;
    update public.port_treasury t set ducats = 1000000000000 where t.port_id = v_city;   -- the city needs nothing: she keeps her gold
    if public.cargo_ship_state(v_fl) <> 'HOME' then
      raise exception '0437 self-assert FAIL: a new ship at home, empty, is % (not HOME)', public.cargo_ship_state(v_fl);
    end if;

    -- (a) loaded 5,000 at home, docked at the rich city on a lap: RECALLED, sailing straight home with the 5,000
    v_load := public.convoy_book('LOADED', v_fl, v_pl, v_cap, 5000);
    v_cir := public.cargo_circuit_of(v_nat, v_cap);
    update public.fleets f set port_id = v_city, ready_at = null where f.id = v_fl;
    update public.cargo_ships c set circuit_id = v_cir, leg = case when v_cir is null then 0 else 1 end, out_load = v_load where c.fleet_id = v_fl;
    v_w := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + public.funds_aboard();
    v_r := public.cargo_ship_step(v_fl, now());
    if v_r <> 'RECALLED' or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING'
       or (select o.dest_port_id from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING') is distinct from v_cap
       or (select a.aboard from public.cargo_ship_aboard(v_fl) a) is distinct from 5000::bigint then
      raise exception '0437 self-assert FAIL: a surplus ship with 5,000 aboard at a city answered % and did not sail straight home with it', v_r;
    end if;
    v_card := world.cargo_ship_card(v_fl);
    if public.cargo_ship_state(v_fl) <> 'LOADED' or v_card ->> 'state' <> 'LOADED' or (v_card ->> 'funds')::bigint <> 5000
       or jsonb_array_length(v_card -> 'next') <> 0 or (v_card ->> 'stops_left')::int <> 0 or world.stats_fleet(v_fl) #>> '{cargo,state}' <> 'LOADED' then
      raise exception '0437 self-assert FAIL: sailing home with gold, her card or page: %', v_card - 'ships';
    end if;
    -- she docks at home: HOME, the 5,000 RETURNED there
    update public.voyages o set status = 'ABORTED' where o.fleet_id = v_fl and o.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = v_cap, ready_at = null, lat = null, lon = null where f.id = v_fl;
    v_r := public.cargo_ship_step(v_fl, now());
    if v_r <> 'HOME' or exists (select 1 from public.cargo_ship_aboard(v_fl))
       or not exists (select 1 from public.convoy_cargo b where b.load_id = v_load and b.stage = 'RETURNED' and b.port_id = v_cap and b.ducats = 5000)
       or (select c.circuit_id is not null or c.out_load is not null from public.cargo_ships c where c.fleet_id = v_fl)
       or public.cargo_ship_state(v_fl) <> 'HOME' or world.cargo_ship_card(v_fl) ->> 'state' <> 'HOME' then
      raise exception '0437 self-assert FAIL: home, the recalled ship did not close her lap and return the 5,000: %', v_r;
    end if;
    if (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + public.funds_aboard() <> v_w then
      raise exception '0437 self-assert FAIL: the recall moved gold';
    end if;
    -- (b) idle at a home that is no origin: she waits (IDLE), she is not sent to a new home; elsewhere, empty, she is RETURNING
    update public.cargo_ships c set home_port_id = v_city, based_at = null where c.fleet_id = v_fl;
    update public.fleets f set port_id = v_cap where f.id = v_fl;
    if public.cargo_ship_state(v_fl) <> 'RETURNING' or world.stats_fleet(v_fl) #>> '{cargo,state}' <> 'RETURNING' then
      raise exception '0437 self-assert FAIL: empty, away from her home, she is not RETURNING: %', public.cargo_ship_state(v_fl);
    end if;
    update public.fleets f set port_id = v_city where f.id = v_fl;
    v_r := public.cargo_ship_step(v_fl, now());
    if v_r <> 'IDLE' or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
      raise exception '0437 self-assert FAIL: a surplus ship idle at a home that is no origin answered % (she must wait for the retire)', v_r;
    end if;
    -- (c) the retire lays her up; the Stats count and list leave her out
    v_n := public.cargo_ships_retire(v_nat, now());
    if v_n < 1 or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is distinct from now()
       or public.cargo_ship_state(v_fl) <> 'LAID_UP' or world.cargo_ship_card(v_fl) ->> 'state' <> 'LAID_UP' then
      raise exception '0437 self-assert FAIL: the retire did not lay her up (% laid up)', v_n;
    end if;
    if (public.stats_fleets_count(now(), now()) #>> '{cargo,fleets}')::int <> (select count(*) from public.cargo_ships c where c.laid_up_at is null)
       or exists (select 1 from jsonb_array_elements(public.stats_fleet_list_rows('CARGO', now()) -> 'list') e where e ->> 'id' = v_fl::text) then
      raise exception '0437 self-assert FAIL: the Stats count or list still counts a retired cargo ship';
    end if;
    if (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + public.funds_aboard() <> v_w then
      raise exception '0437 self-assert FAIL: the probe moved gold';
    end if;
    v_note := 'a ' || (select n.code from public.nations n where n.id = v_nat) || ' ship (ord ' || v_ord || ', share ' || (v_ord - 1) || ') at '
              || (select p.code from public.ports p where p.id = v_city) || ' with 5,000: RECALLED home to ' || (select p.code from public.ports p where p.id = v_cap)
              || ', HOME (5,000 returned), IDLE at a home that is no origin, laid up; states HOME, LOADED, RETURNING, LAID_UP';
    raise exception sqlstate 'BV437' using message = v_note;
  exception when sqlstate 'BV437' then
    get stacked diagnostics v_note = message_text;
  end;
  if public.cargo_ship_state(v_fl) is not null or (select w.value from public.world_config w where w.key = 'convoys_enabled') is distinct from (v_conv -> 'convoys_enabled') then
    raise exception '0437 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0437 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0437 self-assert ok: A SURPLUS CARGO SHIP COMES HOME NOW. % hunks once each and reversing; grants and volatility unmoved; no other function moved; public.cargo_ship_state stable and server-only. Probe: %. % ms.',
    (select count(*) from hunks_0437), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0437;
end $m$;
