-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0426 - MORE SHIPS AT SEA, 3  (a merchant keeps a parcel that returns 2 %, not 5; a merchant no loop of her harbour pays for moves her home to a
--        healthy harbour, on a passage that pays; a cargo load is 100,000, so the same need sails on more ships)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "why are they laid up so much? and also cargoships why so many in ports?"; earlier the same day "have as much as ships
-- available at sea possible" (row 344; 0423 and 0425 were the first two parts), and before that "merchants losing money": no merchant sails at
-- a loss.
--
-- WHY (prod, read-only, 2026-11-15 ~00:00 UTC, head 0425; docs/dev-log/2026-11-15-at-sea-3.md; scripts/ops/harness/at-sea/measure-merchants.sql,
--      at-sea/after.sql and at-sea-3/measure.sql):
--   MERCHANTS: 732 sailing, 103 laid up, 32 resting, 13 port time. Laid up by refusals in a row 1:17 2:19 3:16 4+:51; since her last lap <1 h 53,
--     1-6 h 28, 6-24 h 11, >24 h 11. 21 lie at harbours whose purse is under 50,000 and 32 have a stop under 100,000 (0410 rightly sells a city
--     only what its purse pays); 68 of 254 harbours have under 100,000, 33 under 10,000. 7 are pirate houses. Of the 103, 45 are refused 4+ in a
--     row or idle 6 hours with one ship to the house and no pirate flag; 44 of those can reach a harbour within her stores whose purse is at
--     least 100,000 and that makes a good with a free buyer place (34 of her own country; median 5 such harbours). Her planner prices loops
--     only FROM WHERE SHE LIES (public.npc_loop_candidates), so a merchant at a poor harbour is asked again and again about the same loops.
--   CARGO SHIPS 372 (361 in service): 120 at sea, 236 idle at home with nothing aboard, 11 laid up (over the country's number), 5 away. Their
--     cities' need 19.56 M, aboard 13.04 M (on ~60 ships at 250,000). Ships the need would keep loaded: 82 at 250,000, 169 at 100,000, 251 at
--     50,000 (each realm: at most its ships in service). One run now: 12 / 23 / 39 (the loads a run, 20 or 40, do not bind today; Joseon's
--     4.99 M need is held by its donors' 32,680 of room, 0307's share, not by the size of a load).
--
-- WHAT THIS FILE DOES (each knob from the value this file was written against; an owner's own value is left and named in the receipt):
--   R1. npc_min_return_pct 5 -> 2. A parcel is kept when it returns 2 % on its outlay after the sink's profit tax (was 5): still strictly above
--       nothing, and the loop it rides must still leave her more than nothing after wages, stores and every dock fee (0186, 0406), and no
--       parcel is bigger than the sink's purse can pay (0410). Read by public.npc_leg_lines and cmd.standing_route_lines, as before.
--   H1. A MERCHANT MOVES HER HOME (new public.npc_rehome, one hunk in public.waiting_ask_plan, new column npc_fleets.rehomed_at). When the
--       waiting-asks job (0405) asks a laid-up merchant and nothing from her harbour pays, and she has been refused npc_rehome_after_refused
--       (4) times in a row or closed no lap for npc_rehome_after_hours (6), she is offered the npc_rehome_candidates (3) nearest harbours she
--       can sail to now (public.npc_feasible_legs with her preset's days, public.npc_legs_open), her own country's first, whose purse is at
--       least npc_rehome_purse_min (100,000) and that make a good with fewer than npc_buyers_per_good merchant buyers. Each is priced by THE
--       leg planner (public.npc_leg_lines) as the out-and-back loop H <-> her harbour, joined at her end: she moves only when THE PASSAGE
--       ITSELF pays (her harbour -> H: its parcels' profit after tax less its wages, its stores and H's dock fee, above nothing; npc_plan
--       judges a whole loop, and a leg back INTO a poor harbour is what sinks her loops), and she can pay its stores. At H she plans afresh at
--       her lap start, as every merchant does (nothing pays there: she waits at H, no loss). The first that pays is written through the save door
--       (cmd.standing_route_save_for: stops [H, her harbour], her cursor on her harbour) and her house's home becomes H; the job's open step
--       resumes her under the quay as for any paying ask. She buys here, sails to H, closes the lap there and plans from H at her lap start.
--       Never: a pirate house (0414/0418's roster stands), a house of more than one ship (one home, one ship), a merchant moved in the last
--       npc_rehome_after_hours, more than npc_rehome_per_run (4; 0 = off) a minute.
--   C3. A LOAD IS 100,000 (knobs): convoy_load_max 250,000 -> 100,000 and convoy_loads_per_run 20 -> 30 (the largest realm need, 2.9 M, in one
--       run). Nothing else about a load moves (public.cargo_ships_load, room once a run a home, money only through public.convoy_book).
--
-- NOT DONE (in the dev-log as proposals): a merchant at a poor harbour whose passage out does not pay stays (no ballast move); a city's purse
--   is not raised; Joseon's need is its donors'; a cargo ship with nothing to carry stays home; nothing is minted.
-- budget: the moves are at most npc_rehome_per_run (4) a minute, ~20 rows each (her stops and lines re-saved, her roster row, her house, one
--   NPC_REHOMED event): <= ~80 rows a minute while the ~45 eligible are moved (about a quarter of an hour), then a few an hour. Their pricing
--   (one leg set, at most six leg pricings, ~0.2-0.5 s) is spent inside the waiting-asks job's own npc_ask_job_ms. Steady: ~+30-60 merchants
--   and ~+80 cargo ships at sea, ~+100 to +150 rows a minute in all; no job is added or rescheduled, no table is made.
-- LOCKS: ALTER TABLE npc_fleets ADD COLUMN (nullable, no default: catalog only); CREATE FUNCTION x1; CREATE OR REPLACE x1 by a hunk; knobs.
-- TIME: the cut is milliseconds; the probe plans one merchant's move (one leg set, up to six leg pricings), rolled back: under 5 s.
--   BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/at-sea-3/rollback-0426.sql (a draft). At once with no file: npc_rehome_per_run 0 (no
--   merchant moves), npc_min_return_pct 5, convoy_load_max 250000, convoy_loads_per_run 20. A merchant already moved keeps her new home.
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0426 = 0425 (#702, live) + 1. 0425 touches neither this body nor these knobs but convoy_load_max and convoy_loads_per_run (its own values
--   are this file's starting values).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn        constant text := 'public.waiting_ask_plan(uuid)';
  c_new       constant text := 'public.npc_rehome(uuid)';
  v_t0        timestamptz := clock_timestamp();
  v_pre       text;
  v_meta      text;
  v_old       text;
  v_new       text;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_kept      text := '';
  v_fleet     uuid;
  v_route     uuid;
  v_player    uuid;
  v_at        uuid;
  v_r         jsonb;
  v_note      text := 'no merchant docked between laps in this world: proof 127 moves one';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)') is null
     or to_regprocedure('public.npc_feasible_legs(uuid,uuid,numeric,integer)') is null or to_regprocedure('public.npc_legs_open(jsonb,uuid)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null
     or not exists (select 1 from public.world_config where key = 'convoy_load_max') then
    raise exception '0426 refuses: the waiting asks (0405), the leg planner, 0423''s knobs or the news are not all in this world';
  end if;
  if to_regprocedure(c_new) is not null or exists (select 1 from public.world_config where key = 'npc_rehome_per_run')
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'npc_fleets' and c.column_name = 'rehomed_at') then
    raise exception '0426 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;

  -- ── 2. THE KNOBS ──
  update public.world_config set value = to_jsonb(2),
         description = description || ' 0426: 5 -> 2 (a parcel that returns 2 % after tax is kept; the loop must still pay after wages, stores and fees).'
   where key = 'npc_min_return_pct' and value = to_jsonb(5);
  if not found then v_kept := v_kept || 'npc_min_return_pct '; end if;
  update public.world_config set value = to_jsonb(100000),
         description = description || ' 0426: 250,000 -> 100,000 (the need loaded on more ships: 169 kept loaded where 82 were, prod 2026-11-15).'
   where key = 'convoy_load_max' and value = to_jsonb(250000);
  if not found then v_kept := v_kept || 'convoy_load_max '; end if;
  update public.world_config set value = to_jsonb(30),
         description = description || ' 0426: 20 -> 30 (at 100,000 a ship, the largest realm need, 2.9 M, still goes in one run).'
   where key = 'convoy_loads_per_run' and value = to_jsonb(20);
  if not found then v_kept := v_kept || 'convoy_loads_per_run '; end if;
  insert into public.world_config (key, value, description) values
    ('npc_rehome_per_run', to_jsonb(4),
     '0426: the most laid-up merchants public.npc_rehome moves to a new home in one minute (the waiting-asks job''s run). 0 = no merchant moves.'),
    ('npc_rehome_after_refused', to_jsonb(4),
     '0426: a laid-up merchant refused this many times in a row (npc_fleets.refused) may move her home (public.npc_rehome).'),
    ('npc_rehome_after_hours', to_jsonb(6),
     '0426: a laid-up merchant whose last lap closed this many real hours ago may move her home; and one moved is not moved again within it.'),
    ('npc_rehome_purse_min', to_jsonb(100000),
     '0426: a harbour a merchant moves her home to has at least this in its purse (public.treasury_balance), while the purses are lit.'),
    ('npc_rehome_candidates', to_jsonb(3),
     '0426: the most harbours public.npc_rehome prices for one merchant (nearest first, her own country first), each as a loop with two legs.');

  -- ── 3. THE COLUMN AND THE FUNCTION ──
  alter table public.npc_fleets add column rehomed_at timestamptz;
  comment on column public.npc_fleets.rehomed_at is '0426: when public.npc_rehome last moved her home (null: never). The run''s cap and her own wait read it.';

  execute $f$
create function public.npc_rehome(p_fleet uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
-- 0426: A LAID-UP MERCHANT MOVES HER HOME, on a passage that pays. Called by public.waiting_ask_plan when THE planner (public.npc_plan) has just
-- found nothing from her harbour that pays. Null = she stays (not eligible, the run's cap reached, or no harbour near whose passage and loop pay);
-- else what was written. Eligible: laid up, docked between laps, nothing aboard, no pirate flag (0414/0418's roster keeps the pirate homes), the
-- only ship of her house, refused npc_rehome_after_refused times in a row or no lap closed for npc_rehome_after_hours, and not moved within them.
-- The harbours: the legs she can sail now (public.npc_feasible_legs with her preset's days, public.npc_legs_open), open, no pirate home, a purse
-- of npc_rehome_purse_min while the purses are lit, a good made there with fewer than npc_buyers_per_good merchant buyers; her own country's
-- first, then the nearest; npc_rehome_candidates of them. Each is priced by THE leg planner (public.npc_leg_lines) both ways, as public.npc_plan
-- prices a loop (profit after tax, less public.wages_from_profit, public.stores_cost and public.port_fee at each harbour made): she moves only when
-- the passage out ALONE leaves her more than nothing, and her purse pays its stores (the loop's net is recorded, not required: at H she plans
-- afresh at her lap start). The loop [H, her harbour] is written
-- through the save door, her cursor on her harbour: the open step resumes her, she buys here, sails to H and closes her lap there.
declare
  v_per     int := public.wc_int('npc_rehome_per_run');
  v_after_r int := public.wc_int('npc_rehome_after_refused');
  v_after_h numeric := public.wc_num('npc_rehome_after_hours');
  v_purse_min bigint := public.wc_int('npc_rehome_purse_min');
  v_kmax    int := public.wc_int('npc_buyers_per_good');
  r         record;
  d         record;
  v_last    timestamptz;
  v_crew    int;
  v_hold    numeric;
  v_aboard  numeric;
  v_speed   numeric;
  v_pdays   int;
  v_purse   numeric;
  v_out     jsonb;
  v_ret     jsonb;
  v_back    jsonb;
  v_fee_h   numeric;
  v_fee_a   numeric;
  v_sea_o   numeric;
  v_sea_l   numeric;
  v_net_o   numeric;
  v_net_l   numeric;
  v_res     jsonb;
  v_tried   int := 0;
begin
  if v_per <= 0 or not public.npc_traders_on() then return null; end if;
  select nf.fleet_id, nf.route_id, nf.refused, nf.rehomed_at, sr.player_id, sr.paused_reason, sr.lap_id, sr.fleet_id as held,
         f.status, f.port_id, f.provision_preset_id, pl.nation_id, pl.ducats, p.code as here_code
    into r
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    join public.fleets f on f.id = nf.fleet_id
    join public.players pl on pl.id = sr.player_id and pl.is_npc
    join public.npc_houses h on h.player_id = sr.player_id
    join public.ports p on p.id = f.port_id
   where nf.fleet_id = p_fleet;
  if r.fleet_id is null or r.paused_reason is distinct from 'laid_up' or r.status <> 'DOCKED' or r.lap_id is not null
     or r.held is distinct from p_fleet then
    return null;
  end if;
  if exists (select 1 from public.great_powers g where g.nation_id = r.nation_id and g.pirate)
     or (select count(*) from public.npc_fleets n2 where n2.player_id = r.player_id) <> 1 then
    return null;
  end if;
  if r.rehomed_at is not null and r.rehomed_at > now() - make_interval(secs => (v_after_h * 3600)::double precision) then
    return null;
  end if;
  select max(l.closed_at) into v_last from public.standing_route_laps l where l.route_id = r.route_id and l.closed_at is not null;
  if not (r.refused >= greatest(v_after_r, 1)
          or (v_last is not null and v_last < now() - make_interval(secs => (v_after_h * 3600)::double precision))) then
    return null;
  end if;
  if (select count(*) from public.npc_fleets n3 where n3.rehomed_at >= date_trunc('minute', now())) >= v_per then
    return null;
  end if;
  -- HER MEASURES, as public.npc_plan reads them
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
    into v_crew, v_aboard
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet;
  if v_aboard > 0 then return null; end if;
  v_hold  := v_aboard + public.fleet_free_hold(p_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed_at(p_fleet, 1), 0), 0.1);
  v_purse := r.ducats + public.fleet_stock_at_cost(p_fleet);
  select pr.days into v_pdays from public.provision_presets pr where pr.id = r.provision_preset_id;
  if coalesce(v_pdays, 0) <= 0 then return null; end if;
  if (select pf.cost from public.npc_provision_for(p_fleet, v_pdays) pf) > coalesce(v_purse, 0) then return null; end if;

  for d in
    select h.id as port_id, h.code, x->'course' as course, (x->>'nm')::numeric as nm, coalesce(public.port_nation(h.id) = r.nation_id, false) as own
      from jsonb_array_elements(public.npc_legs_open(public.npc_feasible_legs(r.port_id, p_fleet, v_speed, v_pdays), r.port_id)) x
      join public.ports h on h.id = (x->>'port_id')::uuid
     where h.id <> r.port_id and h.kind = 'HARBOUR' and not h.is_ice_closed and not public.pirate_home(h.id)
       and (not public.city_treasury_on() or public.treasury_balance(h.id) >= v_purse_min)
       and exists (select 1 from public.port_goods pg
                    where pg.port_id = h.id and pg.haul_nm = 0
                      and (select count(distinct l.route_id)
                             from public.standing_route_lines l
                             join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
                             join public.standing_routes sr3 on sr3.id = l.route_id and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
                             join public.players p3 on p3.id = sr3.player_id and p3.is_npc
                            where s3.port_id = h.id and l.good_id = pg.good_id and l.kind = 'BUY' and l.route_id <> r.route_id) < v_kmax)
     order by 5 desc, 4, 2
     limit greatest(public.wc_int('npc_rehome_candidates'), 0)
  loop
    v_tried := v_tried + 1;
    v_out   := public.npc_leg_lines(r.route_id, r.port_id, d.port_id, v_hold, v_crew, v_speed);
    v_ret   := public.npc_leg_lines(r.route_id, d.port_id, r.port_id, v_hold, v_crew, v_speed);
    v_fee_h := public.port_fee(d.port_id, r.player_id, coalesce((v_out->>'cost')::numeric, 0));
    v_fee_a := public.port_fee(r.port_id, r.player_id, coalesce((v_ret->>'cost')::numeric, 0));
    v_sea_o := coalesce((v_out->>'nm')::numeric, d.nm) / (v_speed * 24);
    v_sea_l := v_sea_o + coalesce((v_ret->>'nm')::numeric, d.nm) / (v_speed * 24);
    v_net_o := coalesce((v_out->>'profit')::numeric, 0)
               - public.wages_from_profit(coalesce((v_out->>'wages')::numeric, 0), coalesce((v_out->>'profit')::numeric, 0))
               - public.stores_cost(r.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_o, v_crew * public.wc_num('food_per_crew_day') * v_sea_o)
               - v_fee_h;
    v_net_l := coalesce((v_out->>'profit')::numeric, 0) + coalesce((v_ret->>'profit')::numeric, 0)
               - public.wages_from_profit(coalesce((v_out->>'wages')::numeric, 0) + coalesce((v_ret->>'wages')::numeric, 0),
                                          coalesce((v_out->>'profit')::numeric, 0) + coalesce((v_ret->>'profit')::numeric, 0))
               - public.stores_cost(r.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_l, v_crew * public.wc_num('food_per_crew_day') * v_sea_l)
               - v_fee_h - v_fee_a;
    continue when not coalesce((v_out->>'any')::boolean, false) or v_net_o <= 0;
    v_back := (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(d.course) with ordinality t(x, i));
    begin
      v_res := cmd.standing_route_save_for(r.player_id, r.route_id, null,
                 jsonb_build_array(
                   jsonb_build_object('port', d.code, 'course', v_back, 'repair', public.port_has_shipyard(d.port_id), 'crew_up', true,
                                      'lines', v_ret->'lines'),
                   jsonb_build_object('port', r.here_code, 'course', d.course,
                                      'repair', not public.port_has_shipyard(d.port_id) and public.port_has_shipyard(r.port_id), 'crew_up', true,
                                      'lines', v_out->'lines')),
                 null, null, public.wc_int('npc_laps_per_game_day'));
      if not coalesce((v_res->>'ok')::boolean, false)
         or (select x.stop_cursor from public.standing_routes x where x.id = r.route_id) <> 1 then
        raise exception sqlstate 'BV426';   -- the save door refused, or she is not anchored at her end: nothing of this try stands
      end if;
    exception when sqlstate 'BV426' then
      continue;
    end;
    update public.npc_fleets set rehomed_at = now() where fleet_id = p_fleet;
    update public.npc_houses set home_port_id = d.port_id where player_id = r.player_id;
    v_res := jsonb_build_object('fleet_id', p_fleet, 'from', r.here_code, 'to', d.code, 'own_country', d.own, 'nm', round(d.nm),
                                'passage_net', round(v_net_o), 'loop_net', round(v_net_l), 'priced', v_tried);
    perform public.emit_event(r.player_id, 'NPC_REHOMED', v_res);
    return v_res;
  end loop;
  return null;
end $fn$
$f$;
  revoke all on function public.npc_rehome(uuid) from public, anon, authenticated;

  -- ── 4. THE HUNK ──
  v_old :=
$h$  v_res := public.npc_plan(now(), q.route_id);
  if coalesce((v_res->>'planned')::int, 0) = 0 or coalesce((v_res->>'waiting')::int, 0) > 0 then
    return 0;   -- not planned, or nothing pays: she waits on (0181)
  end if;
$h$;
  v_new :=
$h$  v_res := public.npc_plan(now(), q.route_id);
  if coalesce((v_res->>'planned')::int, 0) = 0 or coalesce((v_res->>'waiting')::int, 0) > 0 then
    -- 0426: NOTHING FROM HER HARBOUR PAYS: she may move her home (public.npc_rehome: a healthy harbour near, on a passage that pays).
    -- Moved, she is resumed by the open step like any paying ask; else she waits on.
    if coalesce((v_res->>'planned')::int, 0) > 0 and public.npc_rehome(p_fleet) is not null then
      return 1;
    end if;
    return 0;   -- not planned, or nothing pays: she waits on (0181)
  end if;
$h$;
  v_n := (length(v_pre) - length(replace(v_pre, v_old, ''))) / length(v_old);
  if v_n <> 1 then
    raise exception '0426 self-assert FAIL: the hunk occurs % time(s) in %, not once: the deployed body is not what this file was written against', v_n, c_fn;
  end if;
  execute replace(v_pre, v_old, v_new);
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception '0426 self-assert FAIL: the hunk is not in the new body once';
  end if;
  if replace(v_def, v_new, v_old) <> v_pre then
    raise exception '0426 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0426 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure
         and p.oid <> c_new::regprocedure) <> v_fn_before then
    raise exception '0426 self-assert FAIL: another function moved';
  end if;
  if has_function_privilege('anon', c_new, 'execute') or has_function_privilege('authenticated', c_new, 'execute')
     or (select p.provolatile from pg_proc p where p.oid = c_new::regprocedure) <> 'v' then
    raise exception '0426 self-assert FAIL: % is reachable by a client or not volatile', c_new;
  end if;

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0426', 'Merchants leave poor harbours; cargo ships carry smaller loads on more ships',
                             '상선은 가난한 항구를 떠나고, 화물선은 더 작게 나눠 더 많은 배로 싣는다');

  -- ── 6. THE PROBE, rolled back by a raised sentinel: ONE merchant docked between laps with nothing aboard (a laid-up one first), her rows only:
  --   (a) npc_rehome_per_run 0: she stays (null); (b) refused 0 and the hours far off: she stays; (c) refused 4: if she moves, her route is
  --   [H, her harbour] with her cursor on her harbour, H not her harbour and its purse at least the knob, her house's home H, her stamp now; a
  --   second call in the same minute with the cap at 1 does not move her again.
  select nf.fleet_id, nf.route_id, sr.player_id, f.port_id into v_fleet, v_route, v_player, v_at
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id) and sr.lap_id is null
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.players pl on pl.id = sr.player_id
   where not exists (select 1 from public.great_powers g where g.nation_id = pl.nation_id and g.pirate)
     and (select count(*) from public.npc_fleets n2 where n2.player_id = nf.player_id) = 1
     and not exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and public.ship_cargo_tuns(s.id) > 0)
   order by coalesce(sr.paused_reason = 'laid_up', false) desc, nf.refused desc, nf.roster_ord
   limit 1;
  if v_fleet is not null then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
      update public.standing_routes set fleet_id = v_fleet, paused_reason = 'laid_up' where id = v_route;
      update public.world_config set value = to_jsonb(0) where key = 'npc_rehome_per_run';
      update public.npc_fleets set refused = 9 where fleet_id = v_fleet;
      if public.npc_rehome(v_fleet) is not null then
        raise exception '0426 self-assert FAIL: with npc_rehome_per_run 0 a merchant moved';
      end if;
      update public.world_config set value = to_jsonb(4) where key = 'npc_rehome_per_run';
      update public.world_config set value = to_jsonb(1000000) where key = 'npc_rehome_after_hours';
      update public.npc_fleets set refused = 0 where fleet_id = v_fleet;
      if public.npc_rehome(v_fleet) is not null then
        raise exception '0426 self-assert FAIL: a merchant refused 0 times, her last lap in the hours, moved';
      end if;
      update public.world_config set value = to_jsonb(6) where key = 'npc_rehome_after_hours';
      update public.npc_fleets set refused = 4 where fleet_id = v_fleet;
      v_r := public.npc_rehome(v_fleet);
      if v_r is null then
        v_note := 'one merchant (refused 4) at ' || (select p.code from public.ports p where p.id = v_at) || ': no harbour near whose passage and loop pay: she stays';
      else
        if (select x.stop_cursor from public.standing_routes x where x.id = v_route) <> 1
           or (select count(*) from public.standing_route_stops s where s.route_id = v_route) <> 2
           or (select s.port_id from public.standing_route_stops s where s.route_id = v_route and s.ord = 1) <> v_at
           or (select s.port_id from public.standing_route_stops s where s.route_id = v_route and s.ord = 0) = v_at
           or (select h.home_port_id from public.npc_houses h where h.player_id = v_player)
              is distinct from (select s.port_id from public.standing_route_stops s where s.route_id = v_route and s.ord = 0)
           or (public.city_treasury_on() and public.treasury_balance((select s.port_id from public.standing_route_stops s where s.route_id = v_route and s.ord = 0))
                 < public.wc_int('npc_rehome_purse_min'))
           or (select nf.rehomed_at from public.npc_fleets nf where nf.fleet_id = v_fleet) <> now()
           or (v_r->>'passage_net')::numeric <= 0
           or not exists (select 1 from public.standing_route_lines l where l.route_id = v_route and l.stop_ord = 1 and l.kind = 'BUY') then
          raise exception '0426 self-assert FAIL: a move was not written as it says: %', v_r;
        end if;
        update public.world_config set value = to_jsonb(1) where key = 'npc_rehome_per_run';
        update public.npc_fleets set rehomed_at = null where fleet_id = v_fleet;
        update public.npc_fleets set rehomed_at = now() where fleet_id = (select n4.fleet_id from public.npc_fleets n4 where n4.fleet_id <> v_fleet limit 1);
        update public.standing_routes set paused_reason = 'laid_up' where id = v_route;
        if public.npc_rehome(v_fleet) is not null then
          raise exception '0426 self-assert FAIL: the minute''s cap of 1 was passed';
        end if;
        v_note := 'one merchant (refused 4) moved: ' || (v_r->>'from') || ' -> ' || (v_r->>'to') || ', passage net ' || (v_r->>'passage_net')
                  || ', loop net ' || (v_r->>'loop_net') || '; the cap held';
      end if;
      raise exception sqlstate 'BV426';
    exception when sqlstate 'BV426' then null;
    end;
    if v_note not like 'one merchant%' then
      raise exception '0426 self-assert FAIL: the probe did not run to its end';
    end if;
  end if;
  if public.wc_int('npc_rehome_per_run') <> 4 or public.wc_int('npc_rehome_after_hours') <> 6
     or (v_kept = '' and (public.wc_int('npc_min_return_pct') <> 2 or public.wc_int('convoy_load_max') <> 100000 or public.wc_int('convoy_loads_per_run') <> 30)) then
    raise exception '0426 self-assert FAIL: the knobs are not this file''s (or the probe was not rolled back)';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0426 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0426 self-assert ok: MORE SHIPS AT SEA, 3. One hunk in public.waiting_ask_plan, once and reversing; grants and volatility unmoved; no other function moved; public.npc_rehome (server-only), npc_fleets.rehomed_at. Knobs: npc_min_return_pct %, convoy_load_max %, convoy_loads_per_run %, npc_rehome_per_run 4.% Probe: %; % ms.',
    public.wc_int('npc_min_return_pct'), public.wc_int('convoy_load_max'), public.wc_int('convoy_loads_per_run'),
    case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
