===== city_bid_factor(uuid) [s]
CREATE OR REPLACE FUNCTION public.city_bid_factor(p_port uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0122: THE soft half of the empty-purse rule. 1 dark, 1 at or above the reserve (or with no
  -- reserve yet), falling linearly to city_bid_floor at an empty purse. 0174: the LIVE purse
  -- (public.treasury_balance — rolled + this hour's flows) against the rolled reserve.
  select case when not public.city_treasury_on() then 1::numeric
              else coalesce((select case when t.reserve <= 0 then 1::numeric
                                         else public.wc_num('city_bid_floor')
                                              + (1 - public.wc_num('city_bid_floor'))
                                                * least(1::numeric, greatest(0, public.treasury_balance(p_port))::numeric
                                                                    / t.reserve) end
                               from public.port_treasury t where t.port_id = p_port), 1::numeric) end
$function$

===== npc_affordable(uuid,uuid,numeric,numeric) [s]
CREATE OR REPLACE FUNCTION public.npc_affordable(p_port uuid, p_good uuid, p_qty numeric, p_budget numeric)
 RETURNS TABLE(units numeric, total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0129: THE BOUND. The most units, at most p_qty, whose buy quote at p_port (world.quote, the one
-- price authority, no purser: never cheaper than she will pay) costs no more than p_budget. Buying
-- raises the price, so a smaller parcel never costs more a unit: the walk goes down by budget ÷
-- quote, and always by at least one, at most 12 quotes. A quote the port cannot fill at p_qty is
-- answered as asked (units p_qty) — the caller's own stock test refuses it, as before.
declare
  v_q numeric := floor(coalesce(p_qty, 0));
  v_b numeric := greatest(coalesce(p_budget, 0), 0);
  q   record;
  i   int := 0;
begin
  while v_q >= 1 and i < 12 loop
    i := i + 1;
    select * into q from world.quote(p_port, p_good, v_q, 'buy', null, null);
    if q.units is null or q.total is null or q.units < v_q then
      units := v_q; total := q.total; return next; return;
    end if;
    if q.total <= v_b then
      units := v_q; total := q.total; return next; return;
    end if;
    v_q := least(v_q - 1, floor(v_q * v_b / q.total));
  end loop;
  units := 0; total := 0; return next;
end $function$

===== npc_build_for(uuid,timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION public.npc_build_for(p_fleet uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0180 (d): ONE hull for a merchant fleet that lies DOCKED at a harbour with a build yard, while her
-- house stands above her purse ceiling and the fleet and the house have room (public.earned_caps,
-- public.house_ship_max). The class: her flagship's class as her country's line builds it here
-- (public.npc_hull_for). Through the players' doors — cmd.do_build (the yard's labour, BUILD, into
-- this city; every rule of the yard: tier, country, skills, famous, name), cmd.do_hire (HIRE, her
-- hull's crew) and cmd.do_provision (PROVISION, her standing order's days) — with the hull's timber
-- and fittings endowed into this city's shed first, as her founding hulls were, then her gear
-- (public.npc_fit_loadout) and her level (public.npc_fix_level). She pays only from what stands above
-- her ceiling: a purchase that would take her under it, or any refusal (E_…), rolls the whole of it
-- back and is answered {built: 0, refused}. Null when there is nothing to try. Writes nothing on
-- standing_routes and leaves the fleet DOCKED (the 0101 rest is the route's). Lit only.
declare
  f        public.fleets%rowtype;
  v_purse  bigint;
  v_ceil   bigint;
  v_class  text;
  v_n      int;
  v_k      int;
  v_name   text;
  v_res    jsonb;
  v_ship   uuid;
  v_crew   int;
  v_days   int;
  v_after  bigint;
begin
  if not public.city_treasury_on() then
    return null;
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.status <> 'DOCKED' or f.port_id is null then
    return null;
  end if;
  v_ceil := public.npc_purse_ceiling(f.player_id);
  select pl.ducats into v_purse from public.players pl where pl.id = f.player_id and pl.is_npc;
  if v_ceil is null or v_purse is null or v_purse <= v_ceil then
    return null;
  end if;
  if not exists (select 1 from public.port_buildings b where b.port_id = f.port_id and b.kind = 'building_yard') then
    return null;
  end if;
  select count(*) into v_n from public.ships where fleet_id = p_fleet;
  if v_n < 1
     or v_n >= (public.earned_caps(f.player_id)->>'fleet_ship_max')::int
     or (select count(*) from public.ships where player_id = f.player_id) >= public.house_ship_max(f.player_id) then
    return null;
  end if;
  select c.code into v_class
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet order by s.is_flagship desc, s.name limit 1;
  v_class := public.npc_hull_for(coalesce((select h.live_class from public.npc_line_hulls h where h.class_code = v_class), v_class),
                                 f.port_id);
  v_k := v_n + 1;
  loop
    v_name := left(btrim(f.name), 20) || ' ' || v_k;
    exit when not exists (select 1 from public.ships s where s.player_id = f.player_id and lower(s.name) = lower(v_name));
    v_k := v_k + 1;
  end loop;

  begin
    insert into public.player_storage (player_id, port_id, good_id, qty, basis)
    select f.player_id, f.port_id, hg.good_id, hg.qty, 0 from public.hull_recipe_goods hg where hg.class_code = v_class
    on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;
    insert into public.player_items (player_id, port_id, item_code, qty)
    select f.player_id, f.port_id, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = v_class
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;
    v_res := cmd.do_build(p_fleet, jsonb_build_object('class', v_class, 'name', v_name));
    v_ship := (v_res->>'ship')::uuid;
    perform public.npc_fit_loadout(v_ship);
    perform public.npc_fix_level(f.player_id);
    select c.crew_required into v_crew from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_ship;
    if coalesce(v_crew, 0) > 0 then
      perform cmd.do_hire(p_fleet, jsonb_build_object('count', v_crew));
    end if;
    select pr.days into v_days from public.provision_presets pr where pr.id = f.provision_preset_id;
    if v_days is not null then
      perform cmd.do_provision(p_fleet, jsonb_build_object('mode', 'DAYS', 'days', v_days));
    end if;
    select pl.ducats into v_after from public.players pl where pl.id = f.player_id;
    if v_after < v_ceil then
      perform cmd.refuse('E_UNDER_CEILING', format('the hull would take %s under her purse ceiling of %s', f.name, v_ceil),
                         cmd.figures(v_purse - v_ceil, v_purse - v_after, 'ducats'));
    end if;
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then
      raise;
    end if;
    return jsonb_build_object('built', 0, 'fleet', f.name, 'class', v_class,
                              'port', (select p.code from public.ports p where p.id = f.port_id),
                              'refused', split_part(sqlerrm, ':', 1));
  end;
  return jsonb_build_object('built', 1, 'fleet', f.name, 'ship', v_name, 'class', v_class,
                            'port', (select p.code from public.ports p where p.id = f.port_id),
                            'paid', v_purse - v_after);
end $function$

===== npc_buy_budget(uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_buy_budget(p_fleet uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0129: what a merchant's parcels at one stop may cost — her working capital (purse + cargo aboard
  -- at cost: her SELLs run first and never below cost) less the npc_buy_purse_pct keep-back that
  -- pays the stop's stores and repairs. 0 for no such fleet.
  select coalesce((select greatest(0, floor((pl.ducats + public.fleet_stock_at_cost(f.id))
                                             * public.wc_num('npc_buy_purse_pct') / 100))
                     from public.fleets f join public.players pl on pl.id = f.player_id
                    where f.id = p_fleet), 0)
$function$

===== npc_buy_ceiling(uuid,uuid,numeric) [s]
CREATE OR REPLACE FUNCTION public.npc_buy_ceiling(p_port uuid, p_good uuid, p_patience numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0181: THE ASK NOW, times (1 + patience) — the most a merchant pays a unit at this quay: the quote
-- authority's own answer for one unit (world.quote, its spread and tax), nothing restated. Read by
-- the planner (public.npc_leg_lines: a parcel whose own priced ask is above it is not kept) and, live
-- as she arrives, by the route's renderer (cmd.standing_route_lines), under what her next stop's bid
-- lets her pay. Null = nothing to quote, and the planner does not buy that good. (0097–0180 carried
-- the ask to the stock the port is SUPPOSED to hold; under target that sat below the ask itself, and
-- as rivals drew a maker down a line written at plan time died before she arrived.)
declare
  q        record;
begin
  select * into q from world.quote(p_port, p_good, 1, 'buy', null, null);
  if q.units is null or q.units <= 0 or q.avg_price is null then
    return null;
  end if;
  return round(q.avg_price * (1 + coalesce(p_patience, 0)), 2);
end $function$

===== npc_casks_blocked(uuid,uuid,numeric,numeric) [s]
CREATE OR REPLACE FUNCTION public.npc_casks_blocked(p_fleet uuid, p_from uuid, p_nm numeric, p_speed numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0150: SHE CANNOT STOW HER CASKS FOR THIS LEG BESIDE HER CARGO. She lies docked at p_from, her
-- SAIL from there was refused E_ENDURANCE (public.sail_refused_days), and a hull of hers that
-- carries cargo cannot reach the leg's days — the larger of that refusal's and the planner's
-- (p_nm / p_speed through endurance_margin, + 1) — through public.stores_topup. Read by
-- public.npc_leg_lines (the cut-loss for room).
declare
  v_d     int;
  v_reach numeric;
  s       record;
begin
  if p_fleet is null
     or not exists (select 1 from public.fleets f where f.id = p_fleet and f.status = 'DOCKED' and f.port_id = p_from) then
    return false;
  end if;
  v_d := public.sail_refused_days(p_fleet);
  if v_d = 0 then
    return false;
  end if;
  v_d := greatest(v_d, ceil(coalesce(p_nm, 0) / (greatest(coalesce(p_speed, 0), 0.1) * 24)
                            * public.wc_num('endurance_margin'))::int + 1);
  for s in select sh.crew, sh.water_t, sh.food_t,
                  public.ship_hold_capacity(sh.id) as hold, public.ship_cargo_tuns(sh.id) as cargo_t
             from public.ships sh where sh.fleet_id = p_fleet loop
    continue when s.cargo_t <= 0 or coalesce(s.crew, 0) <= 0;
    select t.days into v_reach from public.stores_topup(s.crew, s.water_t, s.food_t, s.hold - s.cargo_t, v_d, null) t;
    if v_reach < v_d then
      return true;
    end if;
  end loop;
  return false;
end $function$

===== npc_closest_race(uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_closest_race(p_player uuid)
 RETURNS TABLE(port_id uuid, gap numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0145 (D12): the contestable stop of this company's loop where its country is in the CLOSEST race
-- — the smallest distance, in its own influence there, to flipping a city (attack:
-- influence_flip_lead × holder / hers − 1, not yet won), to claiming a free one
-- (influence_claim_min / hers − 1, not yet claimed), or to being flipped (defend:
-- influence_flip_lead × hers / best rival − 1, never below 0). A stop where its country has given
-- nothing (attack, claim) or nobody challenges it (defend) is no race. Shares are
-- public.influence_shares' (the one reader). No race: no row. Ties: the port code.
declare
  v_nation uuid := (select pl.nation_id from public.players pl where pl.id = p_player);
  v_lead   numeric := public.wc_num('influence_flip_lead');
  v_claim  numeric := public.wc_num('influence_claim_min');
begin
  return query
    with stops as (
      select distinct st.port_id from public.npc_fleets nf
        join public.standing_route_stops st on st.route_id = nf.route_id
        join public.port_allegiance a on a.port_id = st.port_id and not a.home
       where nf.player_id = p_player
    ), race as (
      select s.port_id, public.port_nation(s.port_id) as holder,
             coalesce((select x.points from public.influence_shares(s.port_id) x where x.nation_id = v_nation), 0) as hers,
             coalesce((select x.points from public.influence_shares(s.port_id) x where x.nation_id = public.port_nation(s.port_id)), 0) as held,
             coalesce((select max(x.points) from public.influence_shares(s.port_id) x where x.nation_id <> v_nation), 0) as rival
        from stops s
    ), gaps as (
      select r.port_id,
             case when r.holder = v_nation then
                    case when r.rival > 0 then greatest(0, v_lead * r.hers / r.rival - 1) end
                  when r.holder is null then
                    case when r.hers > 0 and v_claim / r.hers - 1 >= 0 then v_claim / r.hers - 1 end
                  else
                    case when r.hers > 0 and v_lead * r.held / r.hers - 1 >= 0 then v_lead * r.held / r.hers - 1 end
             end as gap
        from race r
    )
    select g.port_id, g.gap from gaps g join public.ports p on p.id = g.port_id
     where g.gap is not null
     order by g.gap, p.code
     limit 1;
end $function$

===== npc_compact(timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION public.npc_compact(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Players' books stay append-only for ever. A merchant's are compacted to a rolling window:
--   voyages (not SAILING, ended before the window, not read by the fleet's OPEN lap; their
--   voyage_events cascade), ledger (rolled into ONE `NPC_CARRIED` row per company — THE ONE PLACE
--   a ledger row is written other than public.credit; assert_ledger_reconciles runs right after,
--   so a wrong roll-up raises and rolls back), events (not of a kept kind, not referenced by a
--   remaining ledger row), trade_daily (past game-days), orders (done/skipped, past the window).
-- The append-only trigger lets the deletes through ONLY with byeharu.npc_compact = 'on'
-- (transaction-local, set here and nowhere else) AND only for a merchant's row (0097's
-- forbid_mutation hunk).
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  hh        record;
  v_n       int;
  v_sum     bigint;
  v_bal     bigint;
  v_at      timestamptz;
  v_voy     int := 0;
  v_led     int := 0;
  v_ev      int := 0;
  v_td      int := 0;
  v_ord     int := 0;
begin
  -- OFF IS INERT (§9 "Off: nothing moves"), AND THE COMPACTOR IS NOT AN EXCEPTION. It is gated
  -- exactly like npc_plan and npc_tend. Without this gate tick_reconcile called it every hour from
  -- the moment 0098 landed, so six hours after the deploy — while npc_traders_enabled was still
  -- false — it would have rolled the 23 seeded companies' FOUNDING / OFFICER_WAGE / TUITION rows
  -- into one NPC_CARRIED row each, exercising the append-only ledger's DELETE exemption on
  -- production before the owner had flipped anything (found by the 2026-10-08 review). Residual
  -- un-compacted rows after a switch-off are bounded: off means nothing moves, so nothing is
  -- written to compact, and the next ON resumes the rolling window.
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  perform set_config('byeharu.npc_compact', 'on', true);

  delete from public.voyages v
   using public.fleets f, public.players p
   where v.fleet_id = f.id and f.player_id = p.id and p.is_npc
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.orders o
   using public.players p
   where o.player_id = p.id and p.is_npc
     and o.status in ('done', 'skipped', 'cancelled') and coalesce(o.executed_at, o.issued_at) < v_cut
     and not exists (select 1 from public.standing_routes sr where sr.lap_id = o.route_lap_id);
  get diagnostics v_ord = row_count;

  delete from public.trade_daily td
   using public.players p
   where td.player_id = p.id and p.is_npc and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  for hh in select p.id from public.players p where p.is_npc order by p.id loop
    select count(*), coalesce(sum(l.ducats_delta), 0), max(l.created_at)
      into v_n, v_sum, v_at
      from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
    if v_n >= 2 then
      -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED. Every row written inside one
      -- tick shares created_at (= the transaction's now()), so `order by created_at desc` has no
      -- tie-break that means "last": picking the highest balance_after among the last tick's rows
      -- returned the wrong running balance (+500 then -700 in one transaction carried 104,500 on a
      -- purse of 103,800), and assert_ledger_reconciles checks only Σ delta, so nothing raised
      -- (found by the 2026-10-08 review). The balance after the LAST collapsed row is the purse
      -- now, less every delta booked after the cut — exact by construction, whatever the order
      -- inside a tick.
      select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                   where l2.player_id = hh.id and l2.created_at >= v_cut), 0)
        into v_bal from public.players p where p.id = hh.id;
      delete from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
      values (hh.id, 'NPC_CARRIED', v_sum, v_bal, null, v_at);
      perform public.assert_ledger_reconciles(hh.id);
      v_led := v_led + v_n;
    end if;
    delete from public.events ev
     where ev.player_id = hh.id and ev.created_at < v_cut
       and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
       and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
    get diagnostics v_n = row_count;
    v_ev := v_ev + v_n;
  end loop;

  perform set_config('byeharu.npc_compact', 'off', true);
  return jsonb_build_object('voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev,
                            'trade_daily', v_td, 'orders', v_ord, 'before', v_cut);
end $function$

===== npc_feasible_legs(uuid,numeric,integer) [s]
CREATE OR REPLACE FUNCTION public.npc_feasible_legs(p_port uuid, p_speed numeric, p_days integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of speed p_speed may sail
  -- with p_days of stores: an open harbour (the berth fact voyage.sail_refusal reads; 0139 removed
  -- the draft gate — any hull enters any harbour), and a passage her stores cover at
  -- endurance_margin, one day spare — the stores gate as the sail gate judges it. Nearest first,
  -- then the port id.
  select coalesce(jsonb_agg(jsonb_build_object('port_id', l.to_port, 'code', l.code, 'course', l.course, 'nm', l.nm)
                            order by l.nm, l.to_port), '[]'::jsonb)
    from public.npc_known_legs(p_port) l
    join public.ports p on p.id = l.to_port
   where p.kind = 'HARBOUR' and not p.is_ice_closed
     and ceil(l.nm / (greatest(p_speed, 0.1) * 24) * public.wc_num('endurance_margin'))::int + 1 <= p_days
$function$

===== npc_fit_loadout(uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_fit_loadout(p_ship uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class text;
  v_fleet uuid;
  v_n     int;
  v_pat   int;
  r       record;
  v_fit   int := 0;
begin
  -- 0126: HER GEAR IS ENDOWED, AS HER HULL IS, AND FIXED. A hull that carries anything already is
  -- left exactly as she is: this never adds to, swaps or upgrades a fitting.
  select c.code, s.fleet_id into v_class, v_fleet
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship;
  if v_class is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
  -- 0132: one house's fittings one at a time, and "already fitted" is read off the mounted units.
  perform public.fitting_lock((select s.player_id from public.ships s where s.id = p_ship));
  if exists (select 1 from public.fitted_units where ship_id = p_ship) then
    return 0;
  end if;

  -- 0167 (S18): a line hull a merchant sails in place of a live class wears THAT class's patterns
  -- (public.npc_line_hulls) — one authored set per live class, data/npc-loadouts.json, never a copy.
  v_class := coalesce((select h.live_class from public.npc_line_hulls h where h.class_code = v_class), v_class);
  select count(distinct pattern) into v_n from public.npc_loadouts where class_code = v_class;
  if v_n = 0 then
    raise exception 'E_NO_LOADOUT: no merchant loadout is authored for a % (data/npc-loadouts.json)', v_class
      using errcode = 'P0001';
  end if;
  -- ONE PATTERN PER FLEET: every hull of a fleet wears the same one, and a re-run picks it again.
  v_pat := mod(mod(('x' || left(md5(v_fleet::text), 8))::bit(32)::int, v_n) + v_n, v_n);

  for r in select l.item_code, l.qty from public.npc_loadouts l
            where l.class_code = v_class and l.pattern = v_pat order by l.item_code loop
    for i in 1 .. r.qty loop
      perform public.mount_fitting(p_ship, r.item_code);
      v_fit := v_fit + 1;
    end loop;
  end loop;
  return v_fit;
end $function$

===== npc_fix_hull_skills(uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_fix_hull_skills(p_player uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_home  text;
  r       record;
  v_lvl   int;
  v_res   jsonb;
  v_cost  bigint;
  v_n     bigint := 0;
begin
  -- 0167 (S18): A MERCHANT'S HULL SKILLS, FIXED ONCE — every level the hulls she sails ask for
  -- (skill_requirements, kind 'hull'), raised through the academy's core at her home harbour, each level
  -- endowed first as npc_found endows its founding tuition, so her purse ends where it began. Levels she
  -- holds already are not raised again (run twice, it raises nothing). Answers the ducats endowed (and
  -- paid). Merchants only.
  if not exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    raise exception 'E_NOT_A_MERCHANT: npc_fix_hull_skills fixes a merchant company''s hull skills, and % is not one', p_player
      using errcode = 'P0001';
  end if;
  select p.code into v_home from public.npc_houses h join public.ports p on p.id = h.home_port_id where h.player_id = p_player;
  for r in
    select sr.skill_code, max(sr.level) as need,
           coalesce((select ps.level from public.player_skills ps join public.skills sk on sk.id = ps.skill_id
                      where ps.player_id = p_player and sk.code = sr.skill_code), 0) as have
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      join public.skill_requirements sr on sr.subject_kind = 'hull' and sr.subject_code = c.code
     where s.player_id = p_player
     group by sr.skill_code
     order by sr.skill_code
  loop
    for v_lvl in r.have + 1 .. r.need loop
      v_cost := public.wc_int('skill_study_base_cost') * v_lvl;   -- raise_skill's own price of level v_lvl
      perform public.credit(p_player, 'FOUNDING', v_cost);
      v_res := public.raise_skill(p_player, r.skill_code, v_home);
      if not coalesce((v_res->>'ok')::boolean, false) or (v_res->>'paid')::bigint <> v_cost then
        raise exception 'npc_fix_hull_skills: % could not study % for %: %', p_player, r.skill_code, v_cost, v_res;
      end if;
      v_n := v_n + v_cost;
    end loop;
  end loop;
  return v_n;
end $function$

===== npc_fix_level(uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_fix_level(p_player uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sum int;
  v_lvl int;
begin
  -- 0127: A MERCHANT'S HULLS CARRY A FIXED LEVEL (owner, 2026-10-15): 1 + floor(the company's four
  -- skill levels added / 3) — the number the city list already prints as her level. Written once,
  -- at founding; nothing raises a merchant's skills, so it never moves.
  if not exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    raise exception 'E_NOT_A_MERCHANT: npc_fix_level fixes a merchant company''s level, and % is not one', p_player
      using errcode = 'P0001';
  end if;
  select coalesce(sum(ps.level), 0) into v_sum from public.player_skills ps where ps.player_id = p_player;
  v_lvl := public.level_from_points(public.level_points(1 + v_sum / 3));
  insert into public.ship_xp (ship_id, xp)
  select s.id, public.level_points(v_lvl) from public.ships s where s.player_id = p_player
  on conflict (ship_id) do update set xp = excluded.xp;
  return v_lvl;
end $function$

===== npc_found(jsonb) [v]
CREATE OR REPLACE FUNCTION public.npc_found(p_spec jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- ONE merchant company, founded through the authorities a player's company is made by. The spec
-- (0098's generated literal) names: company (+ alt_company), nation, ink, master, blurb, capital,
-- patience, wares, skills {code: level}, roster_ord, and fleets [{name, roster_ord, home, days,
-- ships [{class, name}] (the first is her flagship), officers [codes], stops [{port, course}],
-- alt_stops}]. Purse after founding = capital: the house is founded with capital + every officer's
-- wage + every level's tuition, and those are then PAID through the same credit calls the player
-- verbs make. The ships are endowed, as every player's Gaivota is (0004:308). The route is saved
-- with its stops, courses, crew_up, repair at stop 0 and the merchant pace — and NO lines, and is
-- NOT assigned (assigning sails): npc_tend assigns it when the switch is on.
-- This body inserts into no table but npc_houses and npc_fleets (asserted).
declare
  v_name    text;
  v_player  uuid;
  v_fleet   uuid;
  v_route   uuid;
  v_preset  uuid;
  v_fl      jsonb;
  v_sh      jsonb;
  v_off     text;
  v_stops   jsonb;
  v_st      jsonb;
  v_res     jsonb;
  v_wages   bigint := 0;
  v_tuition bigint := 0;
  v_skill   record;
  v_lvl     int;
  v_k       int;
  v_i       int;
  v_home    text;
begin
  -- THE NAME: the first spelling that is free, said which; both taken is a raise, never silence.
  v_name := p_spec->>'company';
  if exists (select 1 from public.players where company_name = v_name) then
    v_name := p_spec->>'alt_company';
    if v_name is null or exists (select 1 from public.players where company_name = v_name) then
      raise exception 'E_NAME_TAKEN: both spellings of "%" are taken', p_spec->>'company' using errcode = 'P0001';
    end if;
    raise notice 'npc_found: "%" is taken; founded as "%"', p_spec->>'company', v_name;
  end if;

  select coalesce(sum(o.wage_ducats), 0) into v_wages
    from public.officers o
   where o.code in (select jsonb_array_elements_text(f->'officers') from jsonb_array_elements(p_spec->'fleets') f);
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    v_tuition := v_tuition + public.wc_int('skill_study_base_cost') * (v_skill.level * (v_skill.level + 1) / 2);
  end loop;

  v_fl := p_spec->'fleets'->0;
  v_home := v_fl->'stops'->0->>'port';
  -- 0167 (S18): every hull she is founded with is her country's line hull for the roster's class
  -- (public.npc_hull_for at her house's home — the one rule).
  v_player := public.new_house(null, v_name, p_spec->>'nation', v_home, v_fl->>'name',
                               public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),
                               v_fl->'ships'->0->>'name',
                               (p_spec->>'capital')::bigint + v_wages + v_tuition, true);

  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
  values (v_player, (p_spec->>'roster_ord')::int, p_spec->>'ink', p_spec->>'blurb', p_spec->>'master',
          (select id from public.ports where code = v_home), (p_spec->>'capital')::bigint,
          (p_spec->>'patience')::numeric,
          coalesce((select array_agg(x) from jsonb_array_elements_text(p_spec->'wares') x), '{}'));

  -- SKILLS: the company's levels, paid level by level through the academy's core.
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    for v_lvl in 1 .. v_skill.level loop
      v_res := public.raise_skill(v_player, v_skill.code, v_home);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not study %: %', v_name, v_skill.code, v_res;
      end if;
    end loop;
  end loop;

  for v_k in 0 .. jsonb_array_length(p_spec->'fleets') - 1 loop
    v_fl := p_spec->'fleets'->v_k;
    if v_k = 0 then
      select id into v_fleet from public.fleets where player_id = v_player;
    else
      v_fleet := public.form_fleet(v_player, v_fl->>'name',
                                   (select id from public.ports where code = v_fl->'stops'->0->>'port'));
      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_fl->'ships'->0->>'name', true, true);
    end if;
    for v_i in 1 .. jsonb_array_length(v_fl->'ships') - 1 loop
      v_sh := v_fl->'ships'->v_i;
      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_sh->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_sh->>'name', false, true);
    end loop;
    -- 0126: HER GEAR, endowed as her hulls are — the pattern for this fleet, through the one core.
    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
    -- 0127: HER HULLS' LEVEL, FIXED ONCE from the company's skills (public.npc_fix_level); never moved.
    perform public.npc_fix_level(v_player);

    -- OFFICERS: signed and posted to this fleet, paid through the one mover.
    for v_off in select jsonb_array_elements_text(coalesce(v_fl->'officers', '[]'::jsonb)) loop
      v_res := public.sign_officer(v_player, v_off, v_fleet);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not sign %: %', v_name, v_off, v_res;
      end if;
    end loop;

    -- SUPPLIES: the fleet's standing order, through the preset cores.
    v_res := cmd.provision_preset_save_for(v_player, null, left(v_fl->>'name', 24), (v_fl->>'days')::int);
    v_preset := (v_res->>'id')::uuid;
    if v_preset is null then
      raise exception 'npc_found: % could not keep supplies: %', v_fl->>'name', v_res;
    end if;
    perform cmd.provision_preset_apply_for(v_player, v_fleet, v_preset);

    -- THE ROUTE: stops and courses, crew_up everywhere, repair at home, the merchant pace, no lines.
    v_stops := '[]'::jsonb;
    for v_i in 0 .. jsonb_array_length(v_fl->'stops') - 1 loop
      v_st := v_fl->'stops'->v_i;
      v_stops := v_stops || jsonb_build_object('port', v_st->>'port', 'course', v_st->'course',
                                               'repair', v_i = 0, 'crew_up', true, 'lines', '[]'::jsonb);
    end loop;
    v_res := cmd.standing_route_save_for(v_player, null, left(v_fl->>'name', 24), v_stops, 0, null,
                                         public.wc_int('npc_laps_per_game_day'));
    v_route := (v_res->>'id')::uuid;
    if v_route is null then
      raise exception 'npc_found: the route of % was refused: %', v_fl->>'name', v_res;
    end if;

    insert into public.npc_fleets (fleet_id, player_id, route_id, roster_ord, alt_loop)
    values (v_fleet, v_player, v_route, (v_fl->>'roster_ord')::int, v_fl->'alt_stops');
  end loop;

  -- 0167 (S18): HER HULL SKILLS, FIXED ONCE from the hulls she sails — endowed and paid, so the purse
  -- check below still reads her capital. After npc_fix_level, so her hulls' level is the live skills'.
  perform public.npc_fix_hull_skills(v_player);

  if (select ducats from public.players where id = v_player) <> (p_spec->>'capital')::bigint then
    raise exception 'npc_found: % ends with % in its purse, not its capital %', v_name,
      (select ducats from public.players where id = v_player), p_spec->>'capital';
  end if;
  return v_player;
end $function$

===== npc_give_above_ceiling(timestamp with time zone,uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_give_above_ceiling(p_now timestamp with time zone DEFAULT now(), p_player uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0180 (a): every merchant house above her purse ceiling (public.npc_purse_ceiling) gives the whole
-- excess to the harbours of her loop — every distinct harbour her routes call at, by code, in equal
-- parts (the remainder rounded down the list); none, her home. At each: SHARES first, as many as a
-- work there offers and the part covers (public.invest_for, the players' door; most offered first),
-- the rest as MERCHANT_SURPLUS (public.pay_city — no influence). Her purse ends AT her ceiling. Lit
-- only (dark, a payment to a city writes nothing, so nothing is given). Composed by
-- public.npc_tend_houses after public.npc_invest, while the merchants are on. Budgeted by 0114's
-- deadline (public.npc_upkeep_spent): a house not reached is deferred to the next hour. p_player, when
-- given, limits the pass to that one house (the hourly caller gives none: every house).
declare
  hh        record;
  w         record;
  v_ports   uuid[];
  v_over    bigint;
  v_n       int;
  i         int;
  v_cum     bigint;
  v_prev    bigint;
  v_part    bigint;
  v_buy     int;
  v_houses  int := 0;
  v_shares  bigint := 0;
  v_given   bigint := 0;
  v_deferred int := 0;
  v_failed  int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.city_treasury_on() then
    return jsonb_build_object('ceiling', 0, 'given', 0, 'shares', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
  for hh in select h.player_id, h.home_port_id, pl.company_name
              from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
             where pl.ducats > public.npc_purse_ceiling(h.player_id)
               and (p_player is null or h.player_id = p_player)
             order by h.roster_ord loop
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- 0122's ONE LOCK ORDER: the house's row first (then each city's, inside the doors).
      select pl.ducats - public.npc_purse_ceiling(pl.id) into v_over
        from public.players pl where pl.id = hh.player_id for update;
      continue when v_over is null or v_over <= 0;
      v_ports := array(select st.port_id
                         from (select distinct s.port_id from public.npc_fleets nf
                                 join public.standing_route_stops s on s.route_id = nf.route_id
                                where nf.player_id = hh.player_id) st
                         join public.ports po on po.id = st.port_id and po.kind = 'HARBOUR'
                        order by po.code);
      if cardinality(v_ports) = 0 then
        v_ports := array[hh.home_port_id];
      end if;
      v_n := cardinality(v_ports);
      v_prev := 0;
      for i in 1 .. v_n loop
        v_cum := floor(v_over::numeric * i / v_n)::bigint;
        v_part := v_cum - v_prev;
        v_prev := v_cum;
        continue when v_part <= 0;
        for w in select cw.kind, public.city_offered(cw.port_id, cw.kind) as offered,
                        public.works_share_price(cw.level) as price
                   from public.city_works cw
                  where cw.port_id = v_ports[i] and public.city_offered(cw.port_id, cw.kind) > 0
                  order by 2 desc, array_position(array['docks', 'market', 'production', 'inn'], cw.kind) loop
          v_buy := least(w.offered, floor(v_part / w.price))::int;
          continue when v_buy < 1 or v_buy * w.price < public.wc_int('invest_min_ducats');
          perform public.invest_for(hh.player_id, v_ports[i], w.kind, v_buy);
          v_part := v_part - v_buy * w.price;
          v_shares := v_shares + v_buy * w.price;
        end loop;
        if v_part > 0 then
          perform public.pay_city(hh.player_id, v_ports[i], 'MERCHANT_SURPLUS', v_part,
            public.emit_event(hh.player_id, 'SURPLUS_GIVEN', jsonb_build_object(
              'company', hh.company_name, 'amount', v_part,
              'port', (select p.code from public.ports p where p.id = v_ports[i]))));
          v_given := v_given + v_part;
        end if;
      end loop;
      v_houses := v_houses + 1;
    exception when others then
      v_failed := v_failed + 1;
      v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'ceiling_error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('ceiling', v_houses, 'given', v_given, 'shares', v_shares,
                            'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$

===== npc_hull_for(text,uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_hull_for(p_class text, p_port uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0167 (S18): THE HULL A MERCHANT SAILS for a roster class, at a house whose home is p_port: the line
  -- hull of the country that holds the port today (public.port_nation, 0143), or the class itself where
  -- that country builds no such hull (public.npc_line_hulls, the one rule's rows).
  select coalesce((select h.class_code
                     from public.npc_line_hulls h
                     join public.ship_lines sl on sl.code = h.line_code
                     join public.nations n on n.id = public.port_nation(p_port)
                    where h.live_class = p_class and n.code = any(sl.builder_nations)
                    order by sl.code limit 1), p_class)
$function$

===== npc_invest(timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION public.npc_invest(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0123: lit and with the merchants on, at most npc_invest_max_per_hour companies above
-- npc_invest_above × capital, longest-uninvested first, each buy ONE stake at the stop of her loop
-- that offers the most shares (ties: kind order, then port code), toward npc_invest_keep × capital,
-- through public.invest_for — the players' door. Budgeted by 0114's deadline. Called by npc_tend.
declare
  hi         record;
  v_pick     record;
  v_buy      int;
  v_invested int := 0;
  v_deferred int := 0;
  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
  -- 0145 (D12): where she gives, lit
  v_race     uuid;
  v_stake    record;
  v_left     numeric;
  v_room     bigint;
  v_donated  int := 0;
  v_gave     boolean;
begin
  if not public.city_treasury_on() or not public.npc_traders_on() then
    return jsonb_build_object('invested', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
  for hi in select h.player_id, h.capital, pl.ducats, pl.company_name
              from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
             where pl.ducats > h.capital * public.wc_num('npc_invest_above')
             order by h.invested_at nulls first, h.roster_ord
             limit public.wc_int('npc_invest_max_per_hour') loop
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop
      -- (public.npc_closest_race) — shares there if offered, the rest as a gift under D7's cap. No race
      -- on her loop: 0123's rule below, as it was.
      v_race := null;
      if public.influence_on() then
        select r.port_id into v_race from public.npc_closest_race(hi.player_id) r;
      end if;
      if v_race is not null then
        v_left := hi.ducats - public.wc_num('npc_invest_keep') * hi.capital;
        v_gave := false;
        select w.kind, public.city_offered(w.port_id, w.kind) as offered, public.works_share_price(w.level) as price
          into v_stake
          from public.city_works w
         where w.port_id = v_race and public.city_offered(w.port_id, w.kind) > 0
         order by 2 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind)
         limit 1;
        if v_stake.kind is not null then
          v_buy := least(v_stake.offered, floor(v_left / v_stake.price))::int;
          if v_buy >= 1 and v_buy * v_stake.price >= public.wc_int('invest_min_ducats') then
            perform public.invest_for(hi.player_id, v_race, v_stake.kind, v_buy);
            v_left := v_left - v_buy * v_stake.price;
            v_invested := v_invested + 1;
            v_gave := true;
          end if;
        end if;
        select public.wc_int('influence_day_cap') - coalesce(sum(i.day_given), 0) into v_room
          from public.port_influence i where i.port_id = v_race and i.player_id = hi.player_id;
        if floor(least(v_left, v_room)) >= public.wc_int('donate_min_ducats') then
          perform public.donate_for(hi.player_id, v_race, floor(least(v_left, v_room))::bigint);
          v_donated := v_donated + 1;
          v_gave := true;
        end if;
        if v_gave then
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
        end if;
        continue;
      end if;
      select w.port_id, w.kind, public.city_offered(w.port_id, w.kind) as offered,
             public.works_share_price(w.level) as price
        into v_pick
        from (select distinct s.port_id from public.npc_fleets nf
                join public.standing_route_stops s on s.route_id = nf.route_id
               where nf.player_id = hi.player_id) st
        join public.ports po on po.id = st.port_id and po.kind = 'HARBOUR'
        join public.city_works w on w.port_id = st.port_id
       where public.city_offered(w.port_id, w.kind) > 0
       order by 3 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind), po.code
       limit 1;
      if v_pick.port_id is not null then
        v_buy := least(v_pick.offered,
                       floor((hi.ducats - public.wc_num('npc_invest_keep') * hi.capital) / v_pick.price))::int;
        if v_buy >= 1 and v_buy * v_pick.price >= public.wc_int('invest_min_ducats') then
          perform public.invest_for(hi.player_id, v_pick.port_id, v_pick.kind, v_buy);
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
          v_invested := v_invested + 1;
        end if;
      end if;
    exception when others then
      v_failed := v_failed + 1;
      v_notes := v_notes || jsonb_build_object('company', hi.company_name, 'invest_error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('invested', v_invested, 'donated', v_donated, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$

===== npc_known_legs(uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_known_legs(p_from uuid)
 RETURNS TABLE(to_port uuid, code text, course jsonb, nm numeric, reversed boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
begin
  -- 0120: THE COURSES THE WORLD HOLDS out of one harbour: every merchant route's leg from it, and
  -- every merchant route's leg INTO it sailed backwards (the same polyline, the same water; the
  -- roadsteads are its two ends either way, and cmd.do_sail judges it again at every departure).
  -- One per destination — an authored (forward) course before a reversed one, then the fewer
  -- points — with THE sailed distance (voyage.reach_from, the reach table).
  return query
  with ms as (
    select s.route_id, s.ord, s.port_id, s.course,
           lead(s.port_id)        over (partition by s.route_id order by s.ord) as nxt,
           first_value(s.port_id) over (partition by s.route_id order by s.ord) as first_port
      from public.standing_route_stops s
      join public.standing_routes sr on sr.id = s.route_id
      join public.players p on p.id = sr.player_id and p.is_npc
     -- 0134: ONLY THE ROUTES THAT CALL AT p_from — a leg from or to it lies on such a route, and a
     -- route's lead / first_value are its own (was: every merchant route's stops, 12 ms a harbour).
     where s.route_id in (select t.route_id from public.standing_route_stops t where t.port_id = p_from)),
  legs as (
    select m.port_id as a, coalesce(m.nxt, m.first_port) as b, m.course from ms m),
  both_ways as (
    select l.b as to_port, l.course, false as reversed from legs l where l.a = p_from
    union all
    select l.a, (select jsonb_agg(t.x order by t.i desc)
                   from jsonb_array_elements(l.course) with ordinality t(x, i)), true
      from legs l where l.b = p_from)
  select distinct on (w.to_port) w.to_port, p.code, w.course, r.nm, w.reversed
    from both_ways w
    join public.ports p on p.id = w.to_port
    join voyage.reach_from(p_from) r on r.port_id = w.to_port
   where w.to_port <> p_from
   order by w.to_port, w.reversed, jsonb_array_length(w.course);
end
$function$

===== npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric) [v]
CREATE OR REPLACE FUNCTION public.npc_leg_lines(p_route uuid, p_from uuid, p_to uuid, p_hold numeric, p_crew integer, p_speed numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- The lines a merchant route writes at p_from bound for p_to, and what they pay. 0114:246-293
-- moved here whole so a loop can be priced without being written (npc_plan prices every candidate
-- loop through this and writes only the winner):
--   1. RANK with THE ranking (world.trade_routes, p_from to p_to, twelve rows), priced end to end
--      through world.quote.
--   2. FILTER: the house's authored wares first (all rows only when no listed good passes), and at
--      most npc_buyers_per_good OTHER merchant routes buying that good here (a laid-up or failed
--      route holds no place) — the count taken ONCE per port, as a good -> buyers map.
--   3. SIZE each kept good with the quote authority's own answer: the units the SINK takes above
--      the probe's cost x (1 + npc_sell_margin), capped by the daily cap at both ends, (0129) what
--      her working capital still covers at the source (public.npc_affordable) and the hold
--      left. KEEP only if the two quotes at that size pay after the profit tax (0128: the leg's
--      wages, running_cost_mult, come out of its profit — public.wages_from_profit) and
--      return >= npc_min_return_pct on the outlay. The first npc_lines_per_stop.
--   4. LINES: SELL everything above cost (paid + npc_sell_margin); for a good refused E_PRICE_LIMIT
--      on a SELL here in BOTH of the last two closed laps, the cut-loss: SELL <good> ALL at the
--      quay's bid, no floor (0142: the at-cost floor 0120 put here was never asked for — removed);
--      BUY <good> <q> AT <ceiling>.
-- Answers {lines, profit, wages, nm, any}: `profit` is the sum of (sink quote - source quote) less
-- the sink's profit tax over the kept goods; `wages` what the leg's sea-days owe (0142: npc_plan
-- takes them out of the LOOP's profit, once — a ballast leg's days are owed too); `nm` the sailed
-- distance from the reach table (the figure the ranking's rows carry); `any` whether anything was kept.
declare
  v_k       int     := public.wc_int('npc_lines_per_stop');
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_minret  numeric := public.wc_num('npc_min_return_pct');
  v_kmax    int     := public.wc_int('npc_buyers_per_good');
  sr        public.standing_routes%rowtype;
  h         public.npc_houses%rowtype;
  v_code    text;
  v_nm      numeric;
  v_lines   jsonb := jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true));
  v_cut     text;
  v_rows    jsonb;
  v_buyers  jsonb;
  e         jsonb;
  v_good    uuid;
  v_bulk    numeric;
  v_cap     numeric;
  v_q       numeric;
  v_ceiling numeric;
  v_left    numeric;
  v_wages   numeric;
  v_kept    int := 0;
  v_pass    int;
  v_profit  numeric := 0;
  v_net     numeric;   -- 0122: a parcel's margin after the sink's profit tax
  v_budget  numeric;   -- 0129: her working capital left for this leg's parcels
  v_any     boolean := false;
  q_size    record;
  q_sell    record;
  q_buy     record;
begin
  select * into sr from public.standing_routes where id = p_route;
  select * into h from public.npc_houses where player_id = sr.player_id;
  select p.code into v_code from public.ports p where p.id = p_from;
  select r.nm into v_nm from voyage.reach_from(p_from) r where r.port_id = p_to;

  -- THE CUT-LOSS: refused E_PRICE_LIMIT on a SELL here in BOTH of the last two closed laps.
  for v_cut in
    select z.g from (
      select split_part(x.e->>'line', ' ', 2) as g, count(distinct x.lap_no) as laps
        from (select l.lap_no, jsonb_array_elements(l.skipped) as e
                from (select lp.lap_no, lp.skipped from public.standing_route_laps lp
                       where lp.route_id = sr.id and lp.closed_at is not null
                       order by lp.lap_no desc limit 2) l) x
       where x.e->>'port' = v_code and x.e->>'verb' = 'SELL' and x.e->>'code' = 'E_PRICE_LIMIT'
       group by 1) z
     where z.laps = 2 and exists (select 1 from public.goods g where g.code = z.g)
     order by z.g limit 2 loop
    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);   -- 0142: at the quay's bid
  end loop;
  -- 0150: THE CUT-LOSS FOR ROOM. Her SAIL from here was refused E_ENDURANCE and a hull of hers
  -- cannot stow this leg's casks beside the cargo the at-profit SELL could not move
  -- (public.npc_casks_blocked): every good aboard goes at the quay's bid, so the PROVISION after
  -- it has room and her lap can close — the two-closed-laps cut-loss above never comes to a lap
  -- that cannot close.
  if public.npc_casks_blocked(sr.fleet_id, p_from, v_nm, p_speed) then
    for v_cut in select distinct e.key from public.ships s cross join lateral jsonb_each(s.cargo) e
                  where s.fleet_id = sr.fleet_id and (e.value)::text::numeric > 0
                  order by 1 loop
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'SELL', 'good', v_cut));
      v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);
    end loop;
  end if;

  -- THE OTHER MERCHANT BUYERS HERE, per good, once (0114 counted them once per candidate good).
  select coalesce(jsonb_object_agg(z.g, z.n), '{}'::jsonb) into v_buyers from (
    select l.good_id::text as g, count(distinct l.route_id) as n
      from public.standing_route_lines l
      join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
      join public.standing_routes sr3 on sr3.id = l.route_id
                                     and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
      join public.players p3 on p3.id = sr3.player_id and p3.is_npc
     where l.route_id <> sr.id and l.kind = 'BUY' and s3.port_id = p_from
     group by 1) z;

  -- RANK, FILTER, SIZE, KEEP.
  v_rows  := coalesce(world.trade_routes(p_from, null, null, 12, p_to)->'routes', '[]'::jsonb);
  v_left  := p_hold;
  -- 0129: her fleet's working capital — the route's fleet, or (before the switch assigns it) the
  -- merchant fleet the roster keeps for this route.
  v_budget := public.npc_buy_budget(coalesce(sr.fleet_id,
                (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)));
  v_wages := public.crew_wages(p_crew, false) * public.running_cost_mult(sr.player_id)
             * coalesce(v_nm, 0) / (greatest(p_speed, 0.1) * 24);
  for v_pass in 1 .. 2 loop
    exit when v_pass = 2 and v_kept > 0;
    for e in select x from jsonb_array_elements(v_rows) x loop
      exit when v_kept >= v_k;
      v_good := (e->>'good_id')::uuid;
      continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', e->>'code'));
      continue when coalesce((v_buyers->>(v_good::text))::int, 0) >= v_kmax;
      select g.bulk into v_bulk from public.goods g where g.id = v_good;
      v_cap := floor(least(world.daily_cap_remaining(sr.player_id, p_from, v_good),
                           world.daily_cap_remaining(sr.player_id, p_to, v_good),
                           v_left / greatest(v_bulk, 0.001)));
      continue when v_cap is null or v_cap < 1;
      -- THE SIZE is the sink's own answer: units it takes above the probe's cost plus the margin.
      select * into q_size from world.quote(p_to, v_good, v_cap, 'sell',
                                            round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
      v_q := floor(coalesce(q_size.units, 0));
      continue when v_q < 1;
      -- 0129: and no more than her working capital covers at the source — the quay refuses a parcel
      -- she cannot pay for WHOLE (E_INSUFFICIENT_FUNDS), and she sails in ballast.
      select a.units into v_q from public.npc_affordable(p_from, v_good, v_q, v_budget) a;
      continue when v_q < 1;
      select * into q_buy from world.quote(p_from, v_good, v_q, 'buy', null, null);
      continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0;
      select * into q_sell from world.quote(p_to, v_good, v_q, 'sell', null, null);
      -- 0122: the parcel's cost IS q_buy.total, so this is exactly the profit do_sell will tax.
      v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total,
                 (select r_0147.player_id from public.standing_routes r_0147 where r_0147.id = p_route));   -- 0147: her rate
      -- 0128: wages are paid out of the profit and never past it, so a parcel that pays is kept.
      continue when v_net <= 0
                 or v_net * 100 < v_minret * q_buy.total;
      v_ceiling := public.npc_buy_ceiling(p_from, v_good, h.patience);
      continue when v_ceiling is null
                 -- 0180: A LINE IS NEVER BORN REFUSED. A line whose limit is below the parcel's own priced
                 -- ask is refused E_PRICE_LIMIT on arrival; such a parcel is not kept, and the ranking's
                 -- next good is tried. 0181: the ceiling is the quay's ask now × (1 + patience), so this
                 -- drops only a parcel whose own size walks the price past her patience.
                 or v_ceiling < q_buy.avg_price;
      v_lines  := v_lines || jsonb_build_object('kind', 'BUY', 'good', e->>'code', 'qty', v_q,
                                                'price_limit', v_ceiling);
      v_left   := v_left - v_q * v_bulk;
      v_budget := v_budget - q_buy.total;   -- 0129
      v_kept   := v_kept + 1;
      v_profit := v_profit + v_net;   -- 0122: after tax
      v_any    := true;
    end loop;
  end loop;

  -- 0142: the leg's profit after tax, and apart from it the wages its sea-days owe — npc_plan takes
  -- the wages out of the LOOP's profit by the rule the sale pays by (public.wages_from_profit).
  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any);
end $function$

===== npc_loop_beats(integer,numeric,integer,numeric) [i]
CREATE OR REPLACE FUNCTION public.npc_loop_beats(p_tier integer, p_score numeric, p_best_tier integer, p_best_score numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  -- 0152: a loop beats the best so far by its tier first, then by its score (ducats per real hour).
  return p_tier > p_best_tier or (p_tier = p_best_tier and p_score > p_best_score);
end $function$

===== npc_loop_candidates(uuid,uuid,uuid,numeric,numeric) [s]
CREATE OR REPLACE FUNCTION public.npc_loop_candidates(p_route uuid, p_fleet uuid, p_home uuid, p_hold numeric, p_speed numeric)
 RETURNS TABLE(stops jsonb, kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- The loops a merchant may price at a lap start, each a jsonb array of stops
-- [{port_id, code, course, nm}, …] whose stop i's course is the leg to stop i + 1 (the last leg
-- returns home). Bounded by the knobs; every destination must be an open harbour (0139: any hull
-- enters any harbour) within the days of stores she can carry. Deterministic (ties fall to the port id).
--   near  : out-and-back to each of the npc_route_neighbours nearest known harbours;
--   near3 : home -> B -> C -> home where B and C are neighbours and the roster knows B -> C,
--           the shortest first, filling what npc_route_candidates leaves;
--   far   : (hold >= npc_route_far_hold_tuns) out-and-back on the npc_route_far_candidates
--           farthest known legs of npc_route_far_nm or more; her harbour having none, via each
--           neighbour's farthest such leg (home -> X -> F -> X -> home).
declare
  v_near    int     := public.wc_int('npc_route_neighbours');
  v_farn    int     := public.wc_int('npc_route_far_candidates');
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_far_hld numeric := public.wc_num('npc_route_far_hold_tuns');
  v_max     int     := public.wc_int('npc_route_candidates');
  v_days_cap int;
  v_capacity numeric;
  v_crew    int;
  v_preset  int;
  v_stores  numeric;
  v_home    jsonb;
  v_legs    jsonb;
  v_nearset jsonb;
  v_farset  jsonb;
  v_cache   jsonb := '{}'::jsonb;
  v_out     int := 0;
  v_room    int;
  b         jsonb;
  c         jsonb;
  v_ret     jsonb;
  v_bc      jsonb;
  v_three   jsonb := '[]'::jsonb;
  t         jsonb;
  v_xf      jsonb;
  v_fx      jsonb;
begin
  select coalesce(sum(public.ship_hold_capacity(s.id)), 0), coalesce(sum(s.crew), 0)
    into v_capacity, v_crew
    from public.ships s join public.ship_classes cl on cl.id = s.class_id where s.fleet_id = p_fleet;
  select pr.days into v_preset
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = p_fleet;
  v_stores   := v_crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'));
  -- THE DAYS SHE CAN CARRY: her preset as it stands, or what the planner may raise it to — the knob,
  -- and never more than half her hold in stores.
  v_days_cap := greatest(coalesce(v_preset, 0),
                         least(public.wc_int('npc_preset_days_max'),
                               coalesce(floor(0.5 * v_capacity / nullif(v_stores, 0))::int, 0)));
  select jsonb_build_object('port_id', p.id, 'code', p.code) into v_home from public.ports p where p.id = p_home;

  -- the feasible known legs out of a harbour, read once per harbour this call touches
  v_legs := public.npc_feasible_legs(p_home, p_speed, v_days_cap);
  v_cache := jsonb_build_object(p_home::text, v_legs);

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_nearset
    from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric < v_far_nm
           order by (x->>'nm')::numeric, x->>'port_id' limit v_near) z;
  if p_hold >= v_far_hld then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_farset
      from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric >= v_far_nm
             order by (x->>'nm')::numeric desc, x->>'port_id' limit v_farn) z;
  else
    v_farset := '[]'::jsonb;
  end if;

  -- OUT AND BACK, near then far. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset || v_farset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := case when (b->>'nm')::numeric >= v_far_nm then 'far' else 'near' end;
    v_out := v_out + 1;
    return next;
  end loop;

  -- FAR VIA A NEIGHBOUR, when her own harbour has no long haul: home -> X -> F -> X -> home.
  if p_hold >= v_far_hld and jsonb_array_length(v_farset) = 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      exit when v_out >= v_max - 1 or v_farn <= 0;
      select x into v_xf from jsonb_array_elements(v_cache->(b->>'port_id')) x
       where (x->>'nm')::numeric >= v_far_nm order by (x->>'nm')::numeric desc, x->>'port_id' limit 1;
      continue when v_xf is null;
      if not v_cache ? (v_xf->>'port_id') then
        v_cache := v_cache || jsonb_build_object(v_xf->>'port_id',
                     public.npc_feasible_legs((v_xf->>'port_id')::uuid, p_speed, v_days_cap));
      end if;
      select x into v_fx from jsonb_array_elements(v_cache->(v_xf->>'port_id')) x where x->>'port_id' = b->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_xf->'course', 'nm', v_xf->'nm'),
        jsonb_build_object('port_id', v_xf->'port_id', 'code', v_xf->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
      kind := 'far';
      v_out := v_out + 1;
      v_farn := v_farn - 1;
      return next;
    end loop;
  end if;

  -- THREE STOPS among the neighbours, the shortest first, into the room that is left.
  v_room := v_max - 1 - v_out;
  if v_room > 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      for c in select x from jsonb_array_elements(v_nearset) x loop
        continue when c->>'port_id' = b->>'port_id';
        select x into v_bc from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = c->>'port_id';
        continue when v_bc is null;
        select x into v_ret from jsonb_array_elements(v_cache->(c->>'port_id')) x where x->>'port_id' = p_home::text;
        continue when v_ret is null;
        v_three := v_three || jsonb_build_object(
          'nm', (b->>'nm')::numeric + (v_bc->>'nm')::numeric + (v_ret->>'nm')::numeric,
          'loop', jsonb_build_array(
            v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
            jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_bc->'course', 'nm', v_bc->'nm'),
            jsonb_build_object('port_id', c->'port_id', 'code', c->'code', 'course', v_ret->'course', 'nm', v_ret->'nm')));
      end loop;
    end loop;
    for t in select x from jsonb_array_elements(v_three) x
              order by (x->>'nm')::numeric, x->'loop'->1->>'port_id', x->'loop'->2->>'port_id' limit v_room loop
      stops := t->'loop';
      kind := 'near3';
      return next;
    end loop;
  end if;
  return;
end $function$

===== npc_loop_switches(integer,numeric,integer,numeric,numeric) [i]
CREATE OR REPLACE FUNCTION public.npc_loop_switches(p_best_tier integer, p_best_score numeric, p_cur_tier integer, p_cur_score numeric, p_switch_pct numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  -- 0152: she leaves her present loop for the best when it is of a HIGHER tier (outright), or, in
  -- the same tier, when it pays something and npc_route_switch_pct more per hour (0120's rule).
  return p_best_tier > p_cur_tier
      or (p_best_tier = p_cur_tier and p_best_score > 0 and p_best_score >= p_cur_score * (1 + p_switch_pct / 100));
end $function$

===== npc_loop_tier(boolean,numeric,boolean) [i]
CREATE OR REPLACE FUNCTION public.npc_loop_tier(p_yard boolean, p_net numeric, p_unsailable boolean)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  -- 0152: 1 = the loop has a shipyard AND pays (what a lap leaves her > 0); 0 otherwise; -1 = her
  -- present loop while she lies off it (it cannot be sailed from there). Read by npc_plan alone.
  if coalesce(p_unsailable, false) then return -1; end if;
  if coalesce(p_yard, false) and coalesce(p_net, 0) > 0 then return 1; end if;
  return 0;
end $function$

===== npc_plan(timestamp with time zone,uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_plan(p_now timestamp with time zone DEFAULT now(), p_route uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Writes each merchant route's STOPS and LINES from the market through cmd.standing_route_save_for.
-- Every leg's lines come from THE leg planner (public.npc_leg_lines: 0114's rank, filter, size,
-- keep); this function decides WHICH LOOP and writes it.
--   * A PASS (p_route null — the switch) or a route not at a lap start: her present loop, re-lined.
--   * A LAP START (p_route named, her fleet docked at her stop 0 with no open lap): her present
--     loop and up to npc_route_candidates others (public.npc_loop_candidates), each priced through
--     the leg planner with every distinct leg priced once, scored in ducats per REAL hour of the
--     lap — sea time at her speed through time_compression, plus her rest (route_rest_voyage_days).
--     0142: the ducats are what the lap LEAVES her — the parcels' profit after tax, less the wages
--     every sea-day of the loop owes and the stores it eats — and the loop she sails, chosen or
--     kept, has her preset raised to cover its longest leg. She repairs at its first shipyard.
--     0152: a loop with a shipyard that pays (TIER 1) outranks every loop without one — a yardless
--     loop is chosen only when no loop with a yard pays — and a higher tier switches outright.
--   * DOCKED OFF HER LOOP (0152: towed to a shipyard her loop does not call at; p_route named): the
--     same choice from where she lies, her present loop never kept (it cannot be sailed from there).
--     The best wins when it beats her present loop by npc_route_switch_pct; a longer leg than her
--     stores cover raises her preset through cmd.provision_preset_save_for first (the candidates
--     already stop at npc_preset_days_max and half her hold), and a refused raise keeps her loop.
--     Counted `chosen`; the loops priced, `candidates`.
--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY. Counted `ballast`. Mid-lap, off her loop, on the switch's pass or with
--     cargo aboard she sails it in ballast (0115). 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE
--     WAITS IN PORT — laid up ('laid_up', written once) and counted `waiting`; public.npc_tend_route
--     re-plans her at every tend and resumes her on the first loop that pays.
-- The pass takes the route planned LONGEST AGO first (updated_at) and defers past the upkeep
-- budget (public.npc_upkeep_spent); a route not reached is counted `deferred`, never half-planned.
-- Routes paused 'error' or 'laid_up' are skipped by the pass; npc_tend re-plans one alone.
-- Locks fleet then route, NOWAIT: a busy route is skipped, never waited for.
declare
  v_pace    int     := public.wc_int('npc_laps_per_game_day');
  v_cand    int     := public.wc_int('npc_route_candidates');
  v_switch  numeric := public.wc_num('npc_route_switch_pct');
  v_emargin numeric := public.wc_num('endurance_margin');
  v_comp    numeric := public.wc_num('time_compression');
  v_rest_h  numeric := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression') / 3600;
  v_day_h   numeric := public.wc_num('game_day_seconds') / 3600;   -- the daily cap's period, in real hours
  r         record;
  lp        record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  v_n       int;
  v_hold    numeric;
  v_crew    int;
  v_speed   numeric;
  v_choose  boolean;
  v_loops   jsonb;
  v_loop    jsonb;
  v_len     int;
  v_memo    jsonb;
  v_key     text;
  v_leg     jsonb;
  v_from    uuid;
  v_to      uuid;
  v_stops   jsonb;
  v_profit  numeric;
  v_nm      numeric;
  v_maxnm   numeric;
  v_any     boolean;
  v_score   numeric;
  v_cur_stops jsonb;
  v_cur_score numeric;
  v_cur_any boolean;
  v_best_i  int;
  v_best_stops jsonb;
  v_best_score numeric;
  v_best_any boolean;
  v_best_maxnm numeric;
  v_cur_maxnm numeric;   -- 0142: her present loop's longest leg
  v_wages   numeric;     -- 0142: what every sea-day of a loop owes
  v_net     numeric;     -- 0142: what a lap of the loop leaves her
  v_cur_net numeric;     -- 0142
  v_best_net numeric;    -- 0142
  v_rep     boolean;     -- 0142: a REPAIR is written on this loop already
  v_yard    boolean;     -- 0142: this stop has a shipyard (public.port_has_shipyard)
  v_sea_d   numeric;     -- 0142: the loop's days at sea
  v_try     int;         -- 0142
  v_off     boolean;     -- 0152: she lies docked at a port her loop does not call at
  v_tier    int;         -- 0152: 1 = a shipyard on the loop and it pays; 0 otherwise; -1 = unsailable
  v_cur_tier int;        -- 0152
  v_best_tier int;       -- 0152
  v_days    int;
  v_preset  int;
  v_res     jsonb;
  i         int;
  j         int;
  v_planned int := 0;
  v_laid    int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_chosen  int := 0;
  v_cands   int := 0;
  v_waiting int := 0;      -- 0181: laid up at her lap start, nothing paying on any loop
  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  for r in
    select nf.fleet_id, nf.route_id
      from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr0 on sr0.id = nf.route_id
     where (p_route is null and coalesce(sr0.paused_reason, '') not in ('error', 'laid_up'))
        or nf.route_id = p_route
     order by sr0.updated_at, nf.roster_ord
  loop
    -- THE BUDGET (0114). Past the upkeep's deadline a route is not begun.
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- FLEET BEFORE ROUTE, and never wait (§4.5).
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = r.fleet_id;
      v_aboard := v_hold;   -- 0181: what she carries, before her free hold is added
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);

      -- LOOP 0 IS HER PRESENT LOOP.
      select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
        into v_loop
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id;
      v_loops := jsonb_build_array(v_loop);

      -- THE CHOICE, at her lap start only: planned alone, her fleet lying at her stop 0 between
      -- laps. The switch's pass (p_route null) and a route mid-lap keep their loop.
      -- 0152: OR SHE LIES DOCKED OFF HER LOOP — the candidates start where she lies.
      v_off := p_route is not null and sr.fleet_id = r.fleet_id and f.status = 'DOCKED'
               and not exists (select 1 from public.standing_route_stops s0
                                where s0.route_id = sr.id and s0.port_id = f.port_id);
      v_choose := (p_route is not null and v_cand > 0 and sr.fleet_id = r.fleet_id and sr.lap_id is null
                  and f.status = 'DOCKED' and f.port_id = (v_loop->0->>'port_id')::uuid)
                  or (v_off and v_cand > 0);
      if v_choose then
        for lp in select * from public.npc_loop_candidates(sr.id, r.fleet_id, f.port_id, v_hold, v_speed) loop
          exit when jsonb_array_length(v_loops) >= v_cand;
          v_loops := v_loops || jsonb_build_array(lp.stops);
        end loop;
      end if;

      -- PRICE EVERY LOOP through the leg planner, each distinct leg once.
      v_memo := '{}'::jsonb;
      v_best_i := 0;
      for i in 0 .. jsonb_array_length(v_loops) - 1 loop
        v_loop   := v_loops->i;
        v_len    := jsonb_array_length(v_loop);
        v_stops  := '[]'::jsonb;
        v_profit := 0;
        v_nm     := 0;
        v_maxnm  := 0;
        v_any    := false;
        v_wages  := 0;       -- 0142
        v_rep    := false;   -- 0142
        for j in 0 .. v_len - 1 loop
          v_from := (v_loop->j->>'port_id')::uuid;
          v_to   := (v_loop->((j + 1) % v_len)->>'port_id')::uuid;
          v_key  := v_from::text || '>' || v_to::text;
          if v_memo ? v_key then
            v_leg := v_memo->v_key;
          else
            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
          end if;
          -- 0142: SHE REPAIRS AT THE FIRST STOP OF THE LOOP THAT HAS A SHIPYARD (public.port_has_shipyard,
          -- the reading cmd.do_repair refuses E_NO_YARD by) — never where no yard is.
          v_yard   := not v_rep and public.port_has_shipyard(v_from);
          v_rep    := v_rep or v_yard;
          v_stops  := v_stops || jsonb_build_object('port', v_loop->j->>'code', 'course', v_loop->j->'course',
                                                   'repair', v_yard, 'crew_up', true, 'lines', v_leg->'lines');
          v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
          v_nm     := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
          v_maxnm  := greatest(v_maxnm, coalesce((v_leg->>'nm')::numeric, 0));
          v_any    := v_any or coalesce((v_leg->>'any')::boolean, false);
        end loop;
        -- DUCATS PER REAL HOUR of the lap: nm / kn is voyage-hours; through the compression, real;
        -- plus her rest; and never less than a game-day, because the daily cap lets her buy a
        -- parcel once a game-day — a five-minute hop does not sell its parcel eleven times an hour.
        -- 0142: WHAT THE LAP LEAVES HER — the parcels' profit after tax, less the wages every sea-day
        -- of the loop owes (paid from that profit and never past it: public.wages_from_profit, once
        -- for the loop, so a ballast leg's days count), less the stores the loop eats
        -- (public.stores_cost, the price cmd.do_provision charges, for her crew over nm / kn days).
        v_sea_d := v_nm / (v_speed * 24);
        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
        v_score := v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        -- 0152: THE TIER (owner default, 2026-10-17): a shipyard on the loop (v_rep — the REPAIR
        -- written above) AND it pays is tier 1, else 0; her present loop, when she lies off it, -1.
        -- The best is the highest tier, then the best per real hour.
        v_tier := public.npc_loop_tier(v_rep, v_net, i = 0 and v_off);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any; v_cur_maxnm := v_maxnm; v_cur_net := v_net;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
          v_cur_tier := v_tier; v_best_tier := v_tier;   -- 0152
        elsif public.npc_loop_beats(v_tier, v_score, v_best_tier, v_best_score) then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
          v_best_tier := v_tier;   -- 0152
        end if;
      end loop;
      v_cands := v_cands + jsonb_array_length(v_loops);

      -- SHE CHANGES LOOP only when the best pays npc_route_switch_pct more per hour than her own.
      -- 0152: a HIGHER TIER switches outright (a paying loop with a shipyard over one without; any
      -- loop over the one she lies off); within a tier, npc_route_switch_pct as before.
      if v_best_i <> 0 and not public.npc_loop_switches(v_best_tier, v_best_score, v_cur_tier, v_cur_score, v_switch) then
        v_best_i := 0;
      end if;
      -- A LONGER LEG THAN HER STORES COVER raises her preset through the preset core. 0142: FOR THE
      -- LOOP SHE WILL SAIL, chosen or kept — a kept loop was never measured again, her speed moved
      -- under it, and her SAIL was refused E_ENDURANCE for ever. A chosen loop whose raise is
      -- refused is not chosen, and her present loop is measured in turn.
      for v_try in 1 .. 2 loop
        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
        -- 0150: AND, FOR THE LOOP SHE KEEPS, NEVER LESS THAN THE PASSAGE HER SAIL WAS REFUSED FOR
        -- (public.sail_refused_days — the SAIL's own measure of the course, 2-7 % past the reach
        -- table's nm on a long leg).
        if v_best_i = 0 then
          v_days := greatest(v_days, public.sail_refused_days(f.id));
        end if;
        select pr.days into v_preset from public.provision_presets pr where pr.id = f.provision_preset_id;
        exit when v_preset is null or v_days <= v_preset;
        v_res := cmd.provision_preset_save_for(sr.player_id, f.provision_preset_id, null, v_days);
        exit when coalesce((v_res->>'ok')::boolean, false);
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'preset_refused', v_res->>'error_code');
        exit when v_best_i = 0;
        v_best_i := 0;
      end loop;
      if v_best_i <> 0 then
        v_stops := v_best_stops; v_any := v_best_any;
        v_chosen := v_chosen + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'chosen',
                     (select string_agg(x->>'port', '-' order by k) from jsonb_array_elements(v_best_stops) with ordinality t(x, k)),
                     'per_hour', round(v_best_score), 'was', round(v_cur_score),
                     'net', round(v_best_net), 'was_net', round(v_cur_net),   -- 0142
                     'yard', v_best_tier = 1, 'off_loop', v_off);               -- 0152
      else
        v_stops := v_cur_stops; v_any := v_cur_any;
      end if;

      -- 0115: Nothing pays: the loop is written as it stands — SELL at a profit at every stop and no
      -- BUY. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
      -- 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE WAITS IN PORT instead of sailing a lap that
      -- pays only its stores (the owner, 2026-10-18: "redesign the routes ... that gives negative
      -- cash"). Every loop on offer was priced above and none carries a paying parcel: she is laid
      -- up where she lies, once (a lay-up already standing is not written again), and counted
      -- `waiting`. cmd.run_standing_route does not open a lap its plan paused (0114), and
      -- public.npc_tend_route re-plans her at every tend. With cargo aboard she sails (her SELLs and
      -- 0142's cut-loss clear it); mid-lap, off her loop or on the switch's pass, as before.
      if not v_any and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
        if sr.paused_reason is distinct from 'laid_up' then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
                     'No cargo pays on any leg of her loops at present; she waits in port.');
          if not coalesce((v_res->>'ok')::boolean, false) then
            raise exception 'npc_plan: the pause door refused % — %', sr.name, v_res->>'error_message';
          end if;
        end if;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('enabled', true, 'planned', v_planned, 'ballast', v_laid,
                            'chosen', v_chosen, 'candidates', v_cands, 'waiting', v_waiting,   -- 0181
                            'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $function$

===== npc_purse_ceiling(uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_purse_ceiling(p_player uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0180: THE one reading of a merchant house's purse ceiling — floor(capital × npc_purse_ceiling).
  -- Null for a company that is not a merchant house.
  select floor(h.capital * public.wc_num('npc_purse_ceiling'))::bigint
    from public.npc_houses h where h.player_id = p_player
$function$

===== npc_step_failed(jsonb,text) [i]
CREATE OR REPLACE FUNCTION public.npc_step_failed(p_where jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE receipt of an hourly-upkeep step that raised and was rolled back alone (its error, or
-- the purse it broke — public.tick_reconcile checks the ledger inside the step, before its COMMIT):
-- failed 1, and one note, p_where || {error}. Added up by public.npc_tend_sum like any count.
begin
  return jsonb_build_object('failed', 1, 'notes', jsonb_build_array(p_where || jsonb_build_object('error', p_error)));
end $function$

===== npc_tend(timestamp with time zone,uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_tend(p_now timestamp with time zone DEFAULT now(), p_route uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> counted and left (0115: never parked; there is no RECALL or salvage
--     verb for anybody, so the executor waits for her).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once — 0181: unless the
--     plan lays her up again (nothing on her loops pays: she waits); whether THIS call re-planned her is read off the
--     plan's receipt, not off updated_at (the save bumps it). error -> the same after 6 h (the
--     pause is dated by updated_at). off_route -> re-assigned if she lies at a stop; otherwise
--     reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between re-plans her lines first (0115).
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- 0137: the steps live in their own functions — public.npc_tend_roster (the walk),
-- public.npc_tend_route (one merchant), public.npc_tend_houses (the companies), public.npc_tend_sum (the
-- receipt). This is their one-transaction composition; the hourly public.tick_reconcile composes the
-- same steps one transaction each.
declare
  v_on  boolean := public.npc_traders_on();
  r     record;
  v_acc jsonb := '{}'::jsonb;
begin
  for r in select * from public.npc_tend_roster() loop
    continue when p_route is not null and r.route_id <> p_route;
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
  end loop;
  if p_route is null then
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_houses(p_now));
  end if;
  return jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_acc, '{}'::jsonb);
end $function$

===== npc_tend_houses(timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION public.npc_tend_houses(p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE companies' upkeep — public.npc_tend's investment (public.npc_invest) and refound passes,
-- moved verbatim. npc_tend runs it after the routes when no single route was asked for; the hourly
-- public.tick_reconcile runs it in its own transaction after the routes.
declare
  v_on      boolean := public.npc_traders_on();
  hh        record;
  v_last    timestamptz;
  v_week    int;
  v_refound int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_can      bigint;
  v_unfunded int := 0;
  v_inv      jsonb := '{}'::jsonb;
  v_ceil     jsonb := '{}'::jsonb;   -- 0180 (a): the purse ceiling's pass
  v_notes   jsonb := '[]'::jsonb;
begin
  -- 0123: INVESTMENT — merchants put their surplus into the cities of their loop (public.npc_invest).
  if v_on then
    v_inv := public.npc_invest(p_now);
    v_deferred := v_deferred + coalesce((v_inv->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_inv->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- 0180 (a): ABOVE HER PURSE CEILING, the rest goes to the cities of her loop (public.npc_give_above_ceiling).
  if v_on then
    v_ceil := public.npc_give_above_ceiling(p_now);
    v_deferred := v_deferred + coalesce((v_ceil->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_ceil->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_ceil->'notes', '[]'::jsonb);
  end if;

  -- REFOUNDS, per company, only while the switch is on.
  if v_on then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('refounded', v_refound, 'refound_unfunded', v_unfunded,
                            'invested', coalesce((v_inv->>'invested')::int, 0),
                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
                            'ceiling', coalesce((v_ceil->>'ceiling')::int, 0),   -- 0180 (a)
                            'ceiling_given', coalesce((v_ceil->>'given')::bigint, 0) + coalesce((v_ceil->>'shares')::bigint, 0),
                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $function$

===== npc_tend_roster() [s]
CREATE OR REPLACE FUNCTION public.npc_tend_roster()
 RETURNS TABLE(fleet_id uuid, route_id uuid, player_id uuid, alt_loop jsonb, k bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE merchant upkeep's walk, moved verbatim out of public.npc_tend — the route written
-- longest ago first, k = the roster rank. Read by npc_tend and by the hourly public.tick_reconcile.
#variable_conflict use_column
begin
  return query select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,
                  row_number() over (order by nf.roster_ord) as k
             from public.npc_fleets nf
             join public.players p on p.id = nf.player_id and p.is_npc
             join public.standing_routes sr0 on sr0.id = nf.route_id
            where nf.route_id is not null
            order by sr0.updated_at, nf.roster_ord;
end $function$

===== npc_tend_route(timestamp with time zone,uuid,uuid,bigint) [v]
CREATE OR REPLACE FUNCTION public.npc_tend_route(p_now timestamp with time zone, p_fleet uuid, p_route uuid, p_k bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: ONE merchant's upkeep — public.npc_tend's per-route body, moved verbatim (fleet then route
-- locked NOWAIT in its own subtransaction; a busy route is skipped and counted). Returns this
-- merchant's counts; public.npc_tend_sum adds them up. Called by npc_tend (one transaction) and by
-- the hourly public.tick_reconcile (one transaction PER MERCHANT, so the locks she takes are held
-- for her step and no longer).
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  r         record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      -- 0152: A WRECK IN PORT IS TOWED (owner default, 2026-10-17) through public.tow_for — THE tow,
      -- the one a player presses — to the nearest harbour with a shipyard, and her REPAIR is queued
      -- there the way a player queues it (cmd.parse, cmd.enqueue, cmd.advance). Repaired off her
      -- loop, the off_route branch below chooses her loop afresh. A tow her fortune will not pay
      -- (E_TOW_FUNDS) is noted and she is counted below, as before.
      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        begin
          v_res := public.tow_for(sr.player_id, r.fleet_id);
          v_res := v_res || jsonb_build_object('repair_queued', cmd.enqueue(sr.player_id,
                     jsonb_set(cmd.parse(sr.player_id, r.fleet_id, 'REPAIR'), '{fleet_id}', to_jsonb(r.fleet_id::text)),
                     'REPAIR', null, null)->'ok');
          perform cmd.advance(r.fleet_id, p_now);
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'towed', v_res->>'to',
                                                   'nm', v_res->'nm', 'fee', v_res->'fee',
                                                   'repair_queued', v_res->'repair_queued');
          continue;
        exception when others then
          if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'tow_refused', split_part(sqlerrm, ':', 1));
        end;
      end if;
      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        -- 0152: a wreck in port is towed above; what reaches here is ADRIFT, a wreck at sea, or a
        -- tow refused.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
        -- chosen afresh from where she lies (public.npc_plan), and she is assigned there below.
        if f.status = 'DOCKED'
           and not exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          perform public.npc_plan(p_now, sr.id);
        end if;
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- 0114: THE BUDGET gates the dear work only — a plan and a start or a resume, and the halt
      -- law's release below. The dark and cannot-sail lay-ups above stay unconditional.
      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        -- 0181: SHE WAITS IN PORT. The plan priced every loop on offer from where she lies and none
        -- pays, so it laid her up (or kept her laid up): she is not resumed; the next tend asks again.
        if coalesce((v_res->>'waiting')::int, 0) > 0 then
          v_waiting := v_waiting + 1;
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
      -- stands above her purse ceiling, one hull (public.npc_build_for: the players' doors, paid into
      -- this city). Budgeted like the dear work above.
      if f.status = 'DOCKED' and not public.npc_upkeep_spent() then
        v_res := public.npc_build_for(r.fleet_id, p_now);
        if v_res is not null then
          v_built := v_built + coalesce((v_res->>'built')::int, 0);
          v_notes := v_notes || (jsonb_build_object('route', sr.name) || v_res);
        end if;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        -- 0150: A SAIL REFUSED E_ENDURANCE IS RE-PLANNED ON THIS CLEAR. Only a plan answers it (her
        -- preset, room for her casks, her cursor back on her stop so the stop renders whole); a
        -- clear alone re-sends the SAIL and nothing else. The count of three was read off events
        -- the compactor deletes after npc_retention_hours, and the hour's pass reached a stuck
        -- merchant every two or three hours: for 251 of 270 it never came.
        if v_clears >= 3 or (fo.verb = 'SAIL' and fo.error_code = 'E_ENDURANCE') then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dark', v_dark, 'started', v_started, 'resumed', v_resumed, 'cleared', v_cleared,
                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
                            'notes', v_notes);
end $function$

===== npc_tend_sum(jsonb,jsonb) [i]
CREATE OR REPLACE FUNCTION public.npc_tend_sum(p_a jsonb, p_b jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE one place npc_tend's receipt is added up — the counts of two steps summed (a missing
-- count is 0), their notes concatenated in order. npc_tend_sum(x, '{}') is x with every count present.
declare
  v_k text;
  v   jsonb := jsonb_build_object('notes', coalesce(p_a->'notes', '[]'::jsonb) || coalesce(p_b->'notes', '[]'::jsonb));
begin
  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'donated', 'busy', 'failed', 'deferred',
                             'built', 'ceiling', 'ceiling_given', 'waiting'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given; 0181: waiting
    v := v || jsonb_build_object(v_k, coalesce((p_a->>v_k)::int, 0) + coalesce((p_b->>v_k)::int, 0));
  end loop;
  return v;
end $function$

===== npc_traders_on() [s]
CREATE OR REPLACE FUNCTION public.npc_traders_on()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.wc('npc_traders_enabled') = 'true'::jsonb and public.standing_routes_on()
$function$

===== npc_traders_switch(boolean) [v]
CREATE OR REPLACE FUNCTION public.npc_traders_switch(p_on boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- THE switch: writes the flag, then plans and tends at once, so merchants put to sea within the
-- minute (the arrivals job takes them from there). false is the reverse, and is how an incident is
-- stopped: one statement. Server-only — the owner runs it in the SQL editor.
declare
  v_plan jsonb;
begin
  update public.world_config set value = to_jsonb(coalesce(p_on, false)) where key = 'npc_traders_enabled';
  if public.npc_traders_on() then
    v_plan := public.npc_plan(now());
  end if;
  return jsonb_build_object('enabled', public.npc_traders_on(), 'plan', v_plan, 'tend', public.npc_tend(now()));
end $function$

===== npc_upkeep_scope(timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION public.npc_upkeep_scope(p_deadline timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE scope of one transaction of the hourly merchant upkeep: never wait on a lock longer than
-- 2 s (0097), and stop the dear work at the hour's deadline (0114; read by public.npc_upkeep_spent).
-- Both transaction-local. Called by public.tick_reconcile alone.
begin
  perform set_config('lock_timeout', '2s', true);
  perform set_config('byeharu.npc_upkeep_deadline', p_deadline::text, true);
end $function$

===== npc_upkeep_spent() [v]
CREATE OR REPLACE FUNCTION public.npc_upkeep_spent()
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0114: true once the hourly upkeep's deadline has passed. The deadline is transaction-local
  -- and set by tick_reconcile ALONE; unset or empty means no budget, so a switch, a proof or a
  -- one-route tend is never cut short.
  select coalesce(nullif(current_setting('byeharu.npc_upkeep_deadline', true), '')::timestamptz
                  < clock_timestamp(), false)
$function$

