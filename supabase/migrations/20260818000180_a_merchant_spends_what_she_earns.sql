-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0180 — A MERCHANT SPENDS WHAT SHE EARNS  (her surplus buys hulls at the yard she lies at; above
--        her purse ceiling the rest goes to the cities of her loop; and a BUY line is never born
--        refused)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17 ~23:50 UTC: *"Cities are powerful … and then make the economy circulate."* After 0174 the
-- world's money grows +11.5 M an hour, and it piles up in merchant purses (39 M above 2 × capital at
-- 05:41). The owner was offered sinks (a)–(e) (docs/dev-log/2026-10-18-circulation-watch.md §9) and did
-- not answer; the coordinator chose (d) + (a) BY DEFAULT. The owner may reverse it.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE PURSE CEILING (a). public.npc_purse_ceiling(house) — THE one reading: floor(capital ×
--     npc_purse_ceiling), the knob 3. Chosen from prod (2026-10-18 06:03, read-only): in the hour
--     before, the merchants under 3 × capital, as a band, gained −0.43 M net (under 5 ×: +0.62 M, under
--     10 ×: +3.6 M), so at 3 × the merchants' money stops growing; the cost is that 90 houses' largest
--     lap of the last four hours bought more than 0.9 × 3 × capital (their next laps are trimmed; the
--     premium they mint, estimated linearly, −15 %).
--     public.npc_give_above_ceiling — each hour, after npc_invest, every house still above her ceiling
--     gives the whole excess to the harbours of her loop, in equal parts: SHARES where a work there
--     offers them (public.invest_for, the players' door), the rest as MERCHANT_SURPLUS (public.pay_city).
--     Her purse ends AT her ceiling. Nothing is destroyed: every ducat lands in a city's purse.
--     MERCHANT_SURPLUS is not a DONATION: it counts no influence (D7's 20,000-a-day cap bounds what a
--     company's gifts weigh in a city's race, and an uncapped gift would swamp every race).
-- (2) THE MERCHANT SPENDS ON HER FLEET (d). public.npc_build_for(fleet) — a house above her ceiling
--     whose fleet LIES DOCKED at a harbour with a build yard lays down ONE hull there an hour (her
--     flagship's class as her country line builds it here, public.npc_hull_for), while the fleet and
--     the house have room (public.earned_caps, public.house_ship_max — the caps' one reading; the
--     ships_respect_house_caps trigger still refuses). Through the PLAYERS' doors: cmd.do_build (the
--     yard's labour, BUILD, into this city), cmd.do_hire (HIRE) and cmd.do_provision (PROVISION) — her
--     hull's timber and fittings are endowed, as her founding hulls were (0098), and so is her gear
--     (public.npc_fit_loadout) and her level (public.npc_fix_level). She buys only from what stands
--     above her ceiling; anything refused rolls the whole purchase back. Composed by
--     public.npc_tend_route (the hourly per-merchant step), before the halt law. The 0101 rest is
--     untouched: nothing here writes standing_routes or the fleet's status.
-- (3) A BUY LINE IS NEVER BORN REFUSED (the coordinator's question, 06:10 UTC: why do 77 % of merchant
--     laps close at zero or less?). public.npc_leg_lines wrote BUY <good> <q> AT <ceiling> where the
--     ceiling (public.npc_buy_ceiling: the ask carried to the stock the maker is SUPPOSED to hold ×
--     (1 + patience)) sits BELOW the ask it had just priced the parcel at whenever the maker's stock is
--     under target — the ask scales up with depletion, the ceiling does not. Measured on prod
--     (read-only, 06:20): 1,070 of 2,306 live BUY lines are refused by their own limit at today's
--     quote; by maker stock / target 0.5–0.6: 11 of 11, 0.6–0.7: 379 of 436, 0.7–0.8: 560 of 1,071,
--     0.8–0.9: 119 of 556, ≥ 0.9: 1 of 232. As the merchants drew the makers down after 0173, more
--     lines were born dead: the lap sails in ballast and pays its stores (net −8 … −22). One hunk: a
--     parcel is kept only when its ceiling covers its own priced ask. The planner then picks the
--     next good of the ranking. The ceiling's own rule (patience) is unchanged.
-- (4) The receipt counts both (npc_tend_sum: built, ceiling, ceiling_given). The Town Hall's
--     "Yesterday" names the new kind (client: src/live/CityTownHall.tsx).
--
-- ── MONEY (stated) ──────────────────────────────────────────────────────────────────────────────
-- Neither (a) nor (d) destroys money, and the mint (IMPORT_DEMAND, 0174 — not touched here) is not
-- touched, so the WORLD's money keeps growing by roughly the premium; what changes is WHERE it lies:
-- in the cities, not in the merchants. (3) lets laps that sailed empty carry cargo again, so the
-- premium minted may rise. See the dev-log for the measured and simulated figures.
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * (d) + (a) themselves (chosen by default); the ceiling 3 × capital; equal parts to her loop's
--   harbours; MERCHANT_SURPLUS counting no influence; one hull an hour, only while docked at a yard;
--   the hull's timber, fittings and gear endowed (only the yard's labour, the hire and the stores are
--   paid); refits and gear repairs NOT bought (gear wear is dark, gear_wear_bite false, so nothing is
--   worn; a merchant's loadout carries no refit, 0158; her hull repairs are already paid at the yard
--   on her loop every lap).
-- * (3): the parcel is dropped, not bought at the higher ask.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE FUNCTION ×3, CREATE OR REPLACE FUNCTION ×4 by hunks, one world_config INSERT. The probes run
-- on their own houses inside sub-transactions rolled back whole (asserted). No LOCK TABLE, no set role,
-- no set local, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0179, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.npc_leg_lines (0129/0147
-- line), public.npc_tend_route (0152 line), public.npc_tend_houses (0145 line), public.npc_tend_sum (0145).
-- ROLLBACK: a forward slice restores the four bodies (each hunk's OLD text is here verbatim) and drops
-- the three functions and the knob. Money already given or built with stays where it went.
-- VERSION: 0180 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0179.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0180(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0180 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
               ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)'),
               ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.npc_tend_sum(jsonb,jsonb)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0180 where def is not null) <> 4 then
    raise exception '0180 self-assert FAIL: % of the 4 bodies found', (select count(*) from defs_before_0180 where def is not null);
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('npc_purse_ceiling', 'npc_give_above_ceiling', 'npc_build_for')) then
    raise exception '0180 self-assert FAIL: a function this file creates exists already';
  end if;
  if exists (select 1 from public.world_config where key = 'npc_purse_ceiling') then
    raise exception '0180 self-assert FAIL: npc_purse_ceiling exists already';
  end if;
  if exists (select 1 from public.treasury_flows where kind = 'MERCHANT_SURPLUS') then
    raise exception '0180 self-assert FAIL: a MERCHANT_SURPLUS flow exists before this file';
  end if;
end $$;

-- the old npc_leg_lines under a pg_temp name, for the side-by-side probe (positive control)
do $$
declare
  v_def text := replace((select def from defs_before_0180 where fn like 'public.npc_leg_lines%'),
                        'CREATE OR REPLACE FUNCTION public.npc_leg_lines(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_leg_lines_old_0180(');
begin
  if v_def not like '%pg_temp.npc_leg_lines_old_0180(%' then
    raise exception '0180 self-assert FAIL: the old copy of public.npc_leg_lines was not renamed';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_purse_ceiling', to_jsonb(3),
   '0180 (sink (a), chosen by default 2026-10-18; the owner may reverse): a merchant house''s purse ceiling, '
   '× her capital (public.npc_purse_ceiling). Each hour, after npc_invest, whatever stands above it is given '
   'to the harbours of her loop (public.npc_give_above_ceiling), and only what stands above it buys hulls '
   '(public.npc_build_for). 3: at prod 2026-10-18 06:03 the houses under 3 × capital, as a band, gained '
   'nothing net in the hour before (−0.43 M).');

-- ── 3. THE READER ──────────────────────────────────────────────────────────────────────────────
create function public.npc_purse_ceiling(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0180: THE one reading of a merchant house's purse ceiling — floor(capital × npc_purse_ceiling).
  -- Null for a company that is not a merchant house.
  select floor(h.capital * public.wc_num('npc_purse_ceiling'))::bigint
    from public.npc_houses h where h.player_id = p_player
$$;
comment on function public.npc_purse_ceiling(uuid) is
  '0180: a merchant house''s purse ceiling (capital × npc_purse_ceiling). Server-only.';
revoke all on function public.npc_purse_ceiling(uuid) from public, anon, authenticated;

-- ── 4. (a) ABOVE THE CEILING, TO THE CITIES OF HER LOOP ─────────────────────────────────────────
create function public.npc_give_above_ceiling(p_now timestamptz default now(), p_player uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
end $$;
comment on function public.npc_give_above_ceiling(timestamptz, uuid) is
  '0180 (a): every merchant house above her purse ceiling gives the excess to the harbours of her loop '
  '(SHARES where offered, the rest MERCHANT_SURPLUS). Composed by npc_tend_houses. Server-only.';
revoke all on function public.npc_give_above_ceiling(timestamptz, uuid) from public, anon, authenticated;

-- ── 5. (d) A HULL AT THE YARD SHE LIES AT ──────────────────────────────────────────────────────
create function public.npc_build_for(p_fleet uuid, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
end $$;
comment on function public.npc_build_for(uuid, timestamptz) is
  '0180 (d): one hull for a merchant fleet docked at a build yard, from what her house holds above her purse '
  'ceiling, through cmd.do_build / do_hire / do_provision. Composed by npc_tend_route. Server-only.';
revoke all on function public.npc_build_for(uuid, timestamptz) from public, anon, authenticated;

-- ── 6. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses; ACL unchanged)
create temporary table hunks_0180 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0180 values
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 1,
$h$      continue when v_ceiling is null;
$h$,
$h$      continue when v_ceiling is null
                 -- 0180: A LINE IS NEVER BORN REFUSED. The ceiling is the ask at the stock the maker is
                 -- supposed to hold × (1 + patience); under target the ask is dearer than that, and a line
                 -- whose limit is below the parcel's own priced ask is refused E_PRICE_LIMIT on arrival.
                 -- Such a parcel is not kept; the ranking's next good is tried.
                 or v_ceiling < q_buy.avg_price;
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 1,
$h$  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
$h$,
$h$  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 2,
$h$      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
$h$,
$h$      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
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
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 3,
$h$                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'notes', v_notes);
$h$,
$h$                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'built', v_built,   -- 0180 (d)
                            'notes', v_notes);
$h$),
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$  v_inv      jsonb := '{}'::jsonb;
$h$,
$h$  v_inv      jsonb := '{}'::jsonb;
  v_ceil     jsonb := '{}'::jsonb;   -- 0180 (a): the purse ceiling's pass
$h$),
('public.npc_tend_houses(timestamp with time zone)', 2,
$h$    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;
$h$,
$h$    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- 0180 (a): ABOVE HER PURSE CEILING, the rest goes to the cities of her loop (public.npc_give_above_ceiling).
  if v_on then
    v_ceil := public.npc_give_above_ceiling(p_now);
    v_deferred := v_deferred + coalesce((v_ceil->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_ceil->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_ceil->'notes', '[]'::jsonb);
  end if;
$h$),
('public.npc_tend_houses(timestamp with time zone)', 3,
$h$                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
$h$,
$h$                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
                            'ceiling', coalesce((v_ceil->>'ceiling')::int, 0),   -- 0180 (a)
                            'ceiling_given', coalesce((v_ceil->>'given')::bigint, 0) + coalesce((v_ceil->>'shares')::bigint, 0),
$h$),
('public.npc_tend_sum(jsonb,jsonb)', 1,
$h$                             'invested', 'donated', 'busy', 'failed', 'deferred'] loop   -- 0145: donated
$h$,
$h$                             'invested', 'donated', 'busy', 'failed', 'deferred',
                             'built', 'ceiling', 'ceiling_given'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0180 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0180 where fn = d.fn order by n loop
      if pg_temp.occurs_0180(v_def, h.old) <> 1 then
        raise exception '0180 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0180(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0180 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0180 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0180(v_rev, h.new) <> 1 then
        raise exception '0180 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0180 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0180 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 7. THE PROBES (own state, every one rolled back whole) ─────────────────────────────────────
create temp table probe_0180 (k text primary key, j jsonb) on commit drop;

-- (i) A LINE IS NEVER BORN REFUSED: 40 merchant legs (stop 0 → stop 1, roster order), their makers'
-- stock drawn to 65 % of target; every BUY line the new body writes has a limit that covers its own
-- ask; the old body (the positive control) writes at least one that does not.
do $$
declare
  r       record;
  v_new   jsonb;
  v_old   jsonb;
  v_hold  numeric;
  v_crew  int;
  v_speed numeric;
  e       jsonb;
  v_ask   numeric;
  v_t0    timestamptz;
  v_out   jsonb := jsonb_build_object('legs', 0, 'new_lines', 0, 'new_dead', 0, 'old_lines', 0, 'old_dead', 0,
                                      'new_ms', 0, 'old_ms', 0);
begin
  begin
    update public.port_goods pg set stock = round(pg.stock_target * 0.65, 3)
     where pg.stock_target > 0
       and pg.port_id in (select s.port_id from public.standing_route_stops s
                           where s.ord = 0 and s.route_id in (select nf.route_id from public.npc_fleets nf order by nf.roster_ord limit 40));
    for r in select nf.route_id, nf.fleet_id,
                    (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 0) as p_from,
                    (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 1) as p_to
               from public.npc_fleets nf order by nf.roster_ord limit 40 loop
      continue when r.p_from is null or r.p_to is null;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = r.fleet_id;
      v_hold := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);
      v_t0 := clock_timestamp();
      v_new := public.npc_leg_lines(r.route_id, r.p_from, r.p_to, v_hold, v_crew, v_speed);
      v_out := jsonb_set(v_out, '{new_ms}', to_jsonb((v_out->>'new_ms')::numeric + extract(epoch from clock_timestamp() - v_t0) * 1000));
      v_t0 := clock_timestamp();
      v_old := pg_temp.npc_leg_lines_old_0180(r.route_id, r.p_from, r.p_to, v_hold, v_crew, v_speed);
      v_out := jsonb_set(v_out, '{old_ms}', to_jsonb((v_out->>'old_ms')::numeric + extract(epoch from clock_timestamp() - v_t0) * 1000));
      v_out := jsonb_set(v_out, '{legs}', to_jsonb((v_out->>'legs')::int + 1));
      for e in select x from jsonb_array_elements(v_new->'lines') x where x->>'kind' = 'BUY' loop
        select q.avg_price into v_ask from world.quote(r.p_from, (select g.id from public.goods g where g.code = e->>'good'),
                                                      (e->>'qty')::numeric, 'buy', null, null) q;
        v_out := jsonb_set(v_out, '{new_lines}', to_jsonb((v_out->>'new_lines')::int + 1));
        if (e->>'price_limit')::numeric < v_ask then
          v_out := jsonb_set(v_out, '{new_dead}', to_jsonb((v_out->>'new_dead')::int + 1));
        end if;
      end loop;
      for e in select x from jsonb_array_elements(v_old->'lines') x where x->>'kind' = 'BUY' loop
        select q.avg_price into v_ask from world.quote(r.p_from, (select g.id from public.goods g where g.code = e->>'good'),
                                                      (e->>'qty')::numeric, 'buy', null, null) q;
        v_out := jsonb_set(v_out, '{old_lines}', to_jsonb((v_out->>'old_lines')::int + 1));
        if (e->>'price_limit')::numeric < v_ask then
          v_out := jsonb_set(v_out, '{old_dead}', to_jsonb((v_out->>'old_dead')::int + 1));
        end if;
      end loop;
    end loop;
    raise exception 'PROBE_ROLLBACK_0180:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0180:%' then raise; end if;
    insert into probe_0180 values ('lines', substr(sqlerrm, length('PROBE_ROLLBACK_0180:') + 1)::jsonb);
  end;
end $$;

-- (ii) (d) and (a) on a lit world: a merchant whose fleet lies at a yard that builds her line, made
-- rich, lays down one hull through the doors; one at her ceiling does not; then (a) gives a rich
-- house's excess to her loop and leaves her at her ceiling, the world's money unchanged.
do $$
declare
  v_f      record;
  v_g      record;
  v_cls    text;
  v_ceil   bigint;
  v_r      jsonb;
  v_n0     int;
  v_crew0  int;
  v_hold0  timestamptz;
  v_flow0  bigint;
  v_world0 numeric;
  v_world1 numeric;
  v_inf0   numeric;   -- her influence day_given before the pass (a real house may have given today)
  v_ports  int;
  v_t0     timestamptz;
  v_out    jsonb := '{}'::jsonb;
begin
  begin
    if not public.city_treasury_on() then
      perform public.city_treasury_switch(true);
    end if;
    -- her house: one hull in one fleet, and a HOME with a yard of the tier her line hull's recipe asks, in a
    -- country that builds it. Chosen by the roster, never by where her fleet happens to lie now: the probe
    -- then lays her fleet at her home quay itself (its own precondition, rolled back with the rest).
    select nf.fleet_id, nf.player_id, nf.route_id, h.home_port_id as port_id, h.capital into v_f
      from public.npc_fleets nf
      join public.npc_houses h on h.player_id = nf.player_id
      join public.port_buildings b on b.port_id = h.home_port_id and b.kind = 'building_yard'
      join lateral (select public.npc_hull_for(coalesce((select lh.live_class from public.npc_line_hulls lh where lh.class_code = c.code), c.code), h.home_port_id) as cls
                      from public.ships s join public.ship_classes c on c.id = s.class_id
                     where s.fleet_id = nf.fleet_id order by s.is_flagship desc, s.name limit 1) k on true
      join public.hull_recipes hr on hr.class_code = k.cls and hr.yard_tier <= b.tier
     where (select count(*) from public.ships s where s.fleet_id = nf.fleet_id) = 1
       and (select count(*) from public.ships s where s.player_id = nf.player_id) = 1
       and public.yard_wrong_country(h.home_port_id, k.cls) is null
       and public.requirements_met(nf.player_id, 'hull', k.cls)
       and not exists (select 1 from public.class_profile cp where cp.class_code = k.cls and cp.tech = 'F')
     order by nf.roster_ord limit 1;
    if v_f.fleet_id is null then
      raise exception '0180 self-assert FAIL: no one-hull merchant house homes at a yard that builds her line hull — the roster moved, not this file';
    end if;
    -- THE PRECONDITION: her fleet lies docked at her home quay (a passage she is on is set aside)
    update public.voyages set status = 'ABORTED' where fleet_id = v_f.fleet_id and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_f.port_id, lat = null, lon = null where id = v_f.fleet_id;
    v_ceil := public.npc_purse_ceiling(v_f.player_id);
    -- AT her ceiling: nothing is tried
    perform public.credit(v_f.player_id, 'PROBE_0180', v_ceil - (select ducats from public.players where id = v_f.player_id));
    v_out := v_out || jsonb_build_object('at_ceiling', public.npc_build_for(v_f.fleet_id, now()));
    -- ABOVE it by 2 M
    perform public.credit(v_f.player_id, 'PROBE_0180', 2000000);
    select count(*), sum(s.crew) into v_n0, v_crew0 from public.ships s where s.fleet_id = v_f.fleet_id;
    select sr.hold_until into v_hold0 from public.standing_routes sr where sr.id = v_f.route_id;
    select coalesce(max(id), 0) into v_flow0 from public.treasury_flows;
    select ducats into v_world0 from public.players where id = v_f.player_id;
    v_t0 := clock_timestamp();
    v_r := public.npc_build_for(v_f.fleet_id, now());
    v_out := v_out || jsonb_build_object('build_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    select pl.ducats + coalesce((select sum(t.ducats) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_f.player_id), 0)
      into v_world1 from public.players pl where pl.id = v_f.player_id;
    select c.code into v_cls from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_f.fleet_id and not s.is_flagship order by s.name limit 1;
    v_out := v_out || jsonb_build_object('r', v_r, 'cls', v_cls, 'ceil', v_ceil,
      'hulls', (select count(*) from public.ships s where s.fleet_id = v_f.fleet_id), 'hulls0', v_n0,
      'crew_added', (select sum(s.crew) from public.ships s where s.fleet_id = v_f.fleet_id) - v_crew0,
      'crew_req', (select c.crew_required from public.ship_classes c where c.code = v_cls),
      'fit_new', (select count(*) from public.fitted_units u join public.ships s on s.id = u.ship_id
                   where s.fleet_id = v_f.fleet_id and not s.is_flagship),
      'fit_flag', (select count(*) from public.fitted_units u join public.ships s on s.id = u.ship_id
                    where s.fleet_id = v_f.fleet_id and s.is_flagship),
      'build_paid', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t
                      where t.id > v_flow0 and t.kind = 'BUILD' and t.port_id = v_f.port_id and t.player_id = v_f.player_id),
      'labour', public.yard_labour(v_f.player_id, v_cls),
      'hire_paid', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.id > v_flow0 and t.kind = 'HIRE' and t.port_id = v_f.port_id and t.player_id = v_f.player_id),
      'prov_paid', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.id > v_flow0 and t.kind = 'PROVISION' and t.port_id = v_f.port_id and t.player_id = v_f.player_id),
      'other_ports', (select count(*) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_f.player_id and t.port_id <> v_f.port_id),
      'purse', (select ducats from public.players where id = v_f.player_id),
      'status', (select status from public.fleets where id = v_f.fleet_id),
      'hold_same', (select sr.hold_until is not distinct from v_hold0 from public.standing_routes sr where sr.id = v_f.route_id),
      'shed_left', (select count(*) from public.player_storage ps where ps.player_id = v_f.player_id and ps.qty > 0)
                 + (select count(*) from public.player_items pi where pi.player_id = v_f.player_id and pi.qty > 0),
      'world_moved', v_world1 - v_world0);
    perform public.assert_ledger_reconciles(v_f.player_id);   -- raises on a mismatch
    v_out := v_out || jsonb_build_object('ledger_ok', true);

    -- (a): another house, 1,234,567 above her ceiling
    select h.player_id into v_g from public.npc_houses h
     where h.player_id <> v_f.player_id order by h.roster_ord limit 1;
    perform public.credit(v_g.player_id, 'PROBE_0180',
                          public.npc_purse_ceiling(v_g.player_id) + 1234567 - (select ducats from public.players where id = v_g.player_id));
    -- the first house back at her ceiling, so the pass meets only this one
    perform public.credit(v_f.player_id, 'PROBE_0180', v_ceil - (select ducats from public.players where id = v_f.player_id));
    select count(distinct s.port_id) into v_ports
      from public.npc_fleets nf join public.standing_route_stops s on s.route_id = nf.route_id
      join public.ports po on po.id = s.port_id and po.kind = 'HARBOUR'
     where nf.player_id = v_g.player_id;
    select coalesce(max(id), 0) into v_flow0 from public.treasury_flows;
    select ducats into v_world0 from public.players where id = v_g.player_id;
    select coalesce(sum(i.day_given), 0) into v_inf0 from public.port_influence i where i.player_id = v_g.player_id;
    v_t0 := clock_timestamp();
    v_r := public.npc_give_above_ceiling(now(), v_g.player_id);   -- her house only (own state)
    v_out := v_out || jsonb_build_object('give_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    select pl.ducats + coalesce((select sum(t.ducats) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_g.player_id), 0)
      into v_world1 from public.players pl where pl.id = v_g.player_id;
    v_out := v_out || jsonb_build_object('give', v_r - 'notes', 'give_notes', v_r->'notes', 'loop_ports', v_ports,
      'g_purse', (select ducats from public.players where id = v_g.player_id), 'g_ceil', public.npc_purse_ceiling(v_g.player_id),
      'g_flows', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_g.player_id and t.kind in ('SHARE', 'MERCHANT_SURPLUS')),
      'g_ports', (select count(distinct t.port_id) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_g.player_id and t.kind in ('SHARE', 'MERCHANT_SURPLUS')),
      'g_others', (select count(*) from public.treasury_flows t where t.id > v_flow0 and t.player_id = v_g.player_id and t.kind not in ('SHARE', 'MERCHANT_SURPLUS')),
      'g_world_moved', v_world1 - v_world0,
      'g_influence', (select coalesce(sum(i.day_given), 0) from public.port_influence i where i.player_id = v_g.player_id) - v_inf0,
      'sum', public.npc_tend_sum(jsonb_build_object('built', 1, 'ceiling', 2, 'ceiling_given', 5), jsonb_build_object('built', 1)));
    raise exception 'PROBE_ROLLBACK_0180:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0180:%' then raise; end if;
    insert into probe_0180 values ('spend', substr(sqlerrm, length('PROBE_ROLLBACK_0180:') + 1)::jsonb);
  end;
end $$;

-- ── 8. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  l jsonb := (select j from probe_0180 where k = 'lines');
  s jsonb := (select j from probe_0180 where k = 'spend');
begin
  if exists (select 1 from public.ledger where kind = 'PROBE_0180') or exists (select 1 from public.treasury_flows where kind = 'MERCHANT_SURPLUS') then
    raise exception '0180 self-assert FAIL: a probe''s money survived its rolled-back block';
  end if;
  if public.wc_num('npc_purse_ceiling') <> 3 then
    raise exception '0180 self-assert FAIL: npc_purse_ceiling is %, not 3', public.wc_num('npc_purse_ceiling');
  end if;
  -- (i)
  if (l->>'legs')::int < 20 then
    raise exception '0180 self-assert FAIL: the line probe priced only % merchant legs', l->>'legs';
  end if;
  if (l->>'new_dead')::int <> 0 then
    raise exception '0180 self-assert FAIL: % of % BUY lines the new planner wrote are refused by their own limit (%)', l->>'new_dead', l->>'new_lines', l;
  end if;
  if (l->>'old_dead')::int < 1 then
    raise exception '0180 self-assert FAIL: the positive control saw no dead line in the old planner at 65 %% stock — the probe cannot see the bug (%)', l;
  end if;
  -- (ii) (d)
  if s->'at_ceiling' <> 'null'::jsonb then
    raise exception '0180 self-assert FAIL: a house AT her ceiling was offered a hull: %', s->'at_ceiling';
  end if;
  if (s->'r'->>'built')::int is distinct from 1 or (s->>'hulls')::int <> (s->>'hulls0')::int + 1 then
    raise exception '0180 self-assert FAIL: the rich merchant at a yard did not lay down one hull: % (% → % hulls)', s->'r', s->>'hulls0', s->>'hulls';
  end if;
  if (s->>'build_paid')::bigint <> (s->>'labour')::bigint or (s->>'build_paid')::bigint <= 0 then
    raise exception '0180 self-assert FAIL: the yard was paid % for a % whose labour is %', s->>'build_paid', s->>'cls', s->>'labour';
  end if;
  if (s->>'crew_added')::int <> (s->>'crew_req')::int or (s->>'hire_paid')::bigint <= 0 then
    raise exception '0180 self-assert FAIL: the new % took % hands (wants %), HIRE paid %', s->>'cls', s->>'crew_added', s->>'crew_req', s->>'hire_paid';
  end if;
  if (s->>'fit_new')::int <> (s->>'fit_flag')::int then
    raise exception '0180 self-assert FAIL: the new hull carries % fittings, her flagship % (one pattern per fleet)', s->>'fit_new', s->>'fit_flag';
  end if;
  if (s->>'other_ports')::int <> 0 or (s->>'world_moved')::numeric <> 0 or (s->>'shed_left')::int <> 0
     or not (s->>'ledger_ok')::boolean then
    raise exception '0180 self-assert FAIL: the hull''s money left this city or her money moved (% of her flows elsewhere, her purse + flows %, shed %, ledger %)',
      s->>'other_ports', s->>'world_moved', s->>'shed_left', s->>'ledger_ok';
  end if;
  if (s->>'purse')::bigint < (s->>'ceil')::bigint or s->>'status' <> 'DOCKED' or not (s->>'hold_same')::boolean then
    raise exception '0180 self-assert FAIL: after the hull her purse % (ceiling %), her fleet %, her rest moved %', s->>'purse', s->>'ceil', s->>'status', not (s->>'hold_same')::boolean;
  end if;
  -- (ii) (a)
  -- the pass was given HER house only (p_player), so it gives for exactly one
  if (s->'give'->>'ceiling')::int <> 1 or (s->'give'->>'failed')::int <> 0 then
    raise exception '0180 self-assert FAIL: the ceiling pass gave for % house(s) (want 1), failed % — %', s->'give'->>'ceiling', s->'give'->>'failed', s->'give_notes';
  end if;
  if (s->>'g_purse')::bigint <> (s->>'g_ceil')::bigint or (s->>'g_flows')::bigint <> 1234567
     or (s->'give'->>'given')::bigint + (s->'give'->>'shares')::bigint <> 1234567 then
    raise exception '0180 self-assert FAIL: her purse % against her ceiling %; the cities took % of 1234567 (%)', s->>'g_purse', s->>'g_ceil', s->>'g_flows', s->'give';
  end if;
  if (s->>'g_ports')::int <> greatest((s->>'loop_ports')::int, 1) or (s->>'g_others')::int <> 0 or (s->>'g_world_moved')::numeric <> 0
     or (s->>'g_influence')::numeric <> 0 then
    raise exception '0180 self-assert FAIL: given to % harbours of her % loop harbours; % other flows of hers; her money moved %; influence day_given moved %',
      s->>'g_ports', s->>'loop_ports', s->>'g_others', s->>'g_world_moved', s->>'g_influence';
  end if;
  if (s->'sum'->>'built')::int <> 2 or (s->'sum'->>'ceiling')::int <> 2 or (s->'sum'->>'ceiling_given')::int <> 5 then
    raise exception '0180 self-assert FAIL: npc_tend_sum does not add the new counts: %', s->'sum';
  end if;

  raise notice '0180 self-assert ok: A MERCHANT SPENDS WHAT SHE EARNS. (3) LINES: % merchant legs at 65 %% maker stock — the new planner wrote % BUY lines, 0 refused by their own limit; the old one % lines, % refused (positive control); priced in % ms new / % ms old. (d) A HULL: a house AT her ceiling is offered none; % d. above it, her fleet at % laid down a % (% → % hulls) through cmd.do_build: BUILD % = the yard''s labour, HIRE % for % hands, PROVISION %, her gear % = her flagship''s, her purse % ≥ her ceiling %, still DOCKED, her rest untouched, no flow of hers outside the city, her purse + her flows unchanged (% ms). (a) THE CEILING (3 × capital): a house 1234567 above it gave % in shares + % as MERCHANT_SURPLUS to % harbours of her loop and stands at her ceiling %; no influence, her purse + her flows unchanged (% ms). Bodies reverse, ACLs unchanged.',
    l->>'legs', l->>'new_lines', l->>'old_lines', l->>'old_dead', round((l->>'new_ms')::numeric), round((l->>'old_ms')::numeric),
    2000000, s->'r'->>'port', s->>'cls', s->>'hulls0', s->>'hulls', s->>'build_paid', s->>'hire_paid', s->>'crew_added', s->>'prov_paid',
    s->>'fit_new', s->>'purse', s->>'ceil', s->>'build_ms',
    s->'give'->>'shares', s->'give'->>'given', s->>'g_ports', s->>'g_purse', s->>'give_ms';
end $$;
