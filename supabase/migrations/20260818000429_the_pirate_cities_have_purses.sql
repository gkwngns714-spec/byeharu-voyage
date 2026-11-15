-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0429 - THE PIRATE CITIES HAVE PURSES  (a pirate is never laid up while the hoard can pay; every pirate city and hub is given 10 M from Port
--        Royal; five pirate cargo ships carry Port Royal's gold to the poorer pirate cities; Port Royal is the pirates' capital)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "raise the cap more, pirates should never be laid up. allocate gold to pirate cities and hub, 10m each, port royal 30m.
--   they should also have like 5 cargo ship (pirates) to move gold to poorer pirate cities. port royal will be capital for pirates."
--
-- WHY (prod, read-only, 2026-11-15, head 0426/0427; docs/dev-log/2026-11-15-pirate-purses.md): the hoard 949,719,366 is Port Royal's purse
--   (949,568,351); the other eight pirate harbours hold 648 to 95,327. 93 pirate ships, 68 LAID UP UNPAID: every payment of the hoard
--   (public.pirate_pay: an hour's pay, a wake, a wreck's refit, a 0339 hull) went through the DAY'S ROOM (pirate_spend_day_pct of the hoard a UTC
--   day), and a ship an hour's pay could not reach was laid up until 00:00 UTC. Today 1.99 M of a 2.28 M room was spent by mid-morning.
--
-- WHAT THIS FILE DOES:
--   P1. NEVER LAID UP FOR PAY (public.pirate_pay, one hunk; public.pirate_add, one hunk): an hour's pay (NAVY_PAY) and a wreck's refit (REFIT) -- a
--       0339 hull stays in the room (proof 106's rule) -- are paid while the hoard stays above pirate_hoard_floor (100 M) after the payment. A
--       wake waits on the same floor. The room (pirate_spend_day_pct 0.006 -> 0.01, "raise the cap more") still bounds the rest: the gifts and the
--       pirate merchants' foundings. Every payment is still written to the day. Who pays a refit is unchanged (own purse, home, another pirate
--       city, then the hoard).
--   P2. EVERY LAID-UP PIRATE IS WOKEN (public.pirate_purse_step, from public.tick_pirates, one hunk): each minute, up to pirate_wakes_per_run (20)
--       laid-up fleets the pirates keep (public.pirate_ord_wanted) are put back to work while the hoard is above the floor: 68 in four minutes.
--   P3. THE PURSES (public.pirate_purses_allot, run ONCE here): every harbour of the pirates but the capital (DGA DJE FLO GOT LGA MWY PTC TDC on
--       prod) is topped up to pirate_city_purse (10,000,000) from Port Royal: two rows of treasury_flows a city, kind PIRATE_ALLOT (moved: never
--       made). ~79.8 M moves. PORT ROYAL IS THE HOARD: its purse and the hoard are one balance (public.pirate_hoard = the pirate harbours' purses,
--       of which Port Royal holds ~95 %). Its 30 M is kept as a FLOOR it never goes under (pirate_capital_purse: no cargo load takes it below; and
--       pay stops at the 100 M hoard floor first), not a second purse. ~870 M stays in it.
--   P4. FIVE PIRATE CARGO SHIPS (public.pirate_purse_step): pirate_cargo_ships (5) cargo ships of the pirates' country, home Port Royal, made one a
--       minute by the hands every cargo ship is made by. THE CARGO SHIPS' OWN MACHINERY CARRIES THEM (one authority): public.cargo_ship_step sails
--       the circuit (public.cargo_circuit_build for the pirates from Port Royal, rebuilt when a harbour changes flag; public.cargo_circuit_plan, two
--       hunks, takes the pirates' own harbours as its stops, since the pirates keep no aiding capital), public.convoy_book moves
--       the gold (LOADED at Port Royal, DELIVERED, RETURNED), public.cargo_ship_aboard reads it. Each minute one idle ship at Port Royal loads what
--       the pirate cities lack of 10 M (less what is already aboard), at most 10 M a ship, never taking Port Royal under pirate_capital_purse nor the
--       hoard under its floor; at each pirate city she tops it up to 10 M (public.cargo_ship_step, one hunk), and the rest comes home.
--       A pirate cargo ship never takes a new home (one hunk). Raidable as any cargo ship by a player (attack_for: a CARGO_SHIP), NEVER BY PIRATES:
--       public.raid_target already passes over the pirates' own country; voyage.freeze_raiders names no raider for her (one hunk); and
--       voyage.hazard_roll's PIRATES day passes her by (one hunk, read only on a PIRATES day).
--   P5. PORT ROYAL IS THE CAPITAL: public.pirate_capital() reads nations.capital_port_code of the pirates ('POR'); this file asserts it and the
--       self-assert refuses any other.
-- NOT DONE: the gifts' own rule (public.pirate_gift_pay keeps its room) and the pirate merchants' refits (public.npc_refit_payer) are unchanged.
-- LOAD: -- budget: the wake ~20 rows a minute for four minutes, then 0; a cargo load at most 1 a minute (2-3 rows); 5 ships on circuits of the
--   eight pirate harbours (~10 legs, a delivery 3 rows a stop) ~+5 rows a minute; the hour's pay ~+90 rows an hour no longer lost to lay-ups.
--   About +10 rows a minute steady. One-time: 16 treasury_flows rows. No job added or rescheduled; no table made.
-- LOCKS: CREATE OR REPLACE x7 by nine hunks; CREATE FUNCTION x2; Port Royal's purse lock for the allotment. BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pirate-war/rollback-0429.sql (a draft): the hunks reversed, the two functions dropped, the
--   knobs back. Quick: pirate_cargo_ships 0 (no new ship, none loaded; those at sea come home and return what they carry), pirate_wakes_per_run 0,
--   pirate_hoard_floor 2000000000 (every payment back under the room). The allotment is not taken back (moved gold; the cities spend it).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the new functions
--   server-only; the capital is Port Royal; the knobs; the allotment (lit purses: every pirate city at 10 M or more, Port Royal at 30 M or more,
--   the purses' sum unmoved); THE PROBE, rolled back: one tick of public.pirate_purse_step.
-- VERSION: 0429 = 0428 (db-room, #707) + 1, after 0427 (#706). 0427 hunked tick_pirates' return line: this file's hunk is cut from 0427's text.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)', 'public.pirate_add(timestamp with time zone)',
    'public.tick_pirates(timestamp with time zone)', 'public.cargo_ship_step(uuid,timestamp with time zone)',
    'voyage.freeze_raiders(jsonb,uuid)', 'voyage.hazard_roll(uuid,integer)', 'public.cargo_circuit_plan(uuid,uuid,uuid)'];
  c_new constant text[] := array['public.pirate_purses_allot(timestamp with time zone)', 'public.pirate_purse_step(timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_kept      text := '';
  v_sum0      numeric;
  v_allot     jsonb;
  v_probe     jsonb;
  v_note      text;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'pirate_city_purse') then
    raise exception '0429 refuses: it has been applied once';
  end if;
  if not exists (select 1 from public.world_config where key = 'pirate_strike_minutes') or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regprocedure('public.cargo_circuit_build(uuid,uuid)') is null or to_regprocedure('public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)') is null then
    raise exception '0429 refuses: 0427 (the pirates strike), the cargo ships'' circuit or the hoard''s payer is not in this world';
  end if;
  if (select n.capital_port_code from public.nations n where n.id = public.pirate_nation()) is distinct from 'POR'
     or public.pirate_capital() is distinct from (select p.id from public.ports p where p.code = 'POR') then
    raise exception '0429 refuses: the pirates'' capital is not Port Royal (POR) in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS AND THE WORD ──
  insert into public.world_config (key, value, description) values
    ('pirate_hoard_floor', to_jsonb(100000000), '0429: an hour''s pay, a wake and a wreck''s refit are paid by the hoard while it stays at or above this after the payment, whatever the day''s room says (the owner, 2026-11-15: "pirates should never be laid up"). The room bounds the rest.'),
    ('pirate_city_purse', to_jsonb(10000000), '0429: what every pirate harbour but the capital is topped up to: once by public.pirate_purses_allot, then by the pirate cargo ships (the owner: "10m each").'),
    ('pirate_capital_purse', to_jsonb(30000000), '0429: Port Royal''s purse is the hoard; no pirate cargo load ever takes it under this (the owner: "port royal 30m").'),
    ('pirate_cargo_ships', to_jsonb(5), '0429: the pirate cargo ships, home Port Royal, carrying its gold to the poorer pirate cities (the owner: "like 5 cargo ship"), while the cargo fleet sizes carry no row for the pirates; once they do (0430), their share (public.convoy_ships_of). 0: none is made or loaded; those out come home.'),
    ('pirate_wakes_per_run', to_jsonb(20), '0429: laid-up pirate fleets put back to work a minute by public.pirate_purse_step while the hoard is above its floor.');
  insert into public.stats_flow_words (kind, side, word, ord)
  select 'PIRATE_ALLOT', 'moved', 'Pirate purses', coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w;
  update public.world_config set value = to_jsonb(0.01),
         description = description || ' 0429: 0.006 -> 0.01 ("raise the cap more"); pay, wakes and refits no longer wait on it (pirate_hoard_floor).'
   where key = 'pirate_spend_day_pct' and value = to_jsonb(0.006);
  if not found then v_kept := v_kept || 'pirate_spend_day_pct '; end if;

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.pirate_purses_allot(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0429: EVERY PIRATE HARBOUR BUT THE CAPITAL TOPPED UP TO pirate_city_purse FROM PORT ROYAL, whole cities first by code, as far as Port Royal holds
-- above pirate_capital_purse. Two rows a city (public.treasury_post, kind PIRATE_ALLOT, moved): never made. Port Royal's purse is locked first
-- (public.treasury_lock). Purses dark: nothing. Run once by migration 0429; the pirate cargo ships keep the purses after. Answers {code: ducats}.
declare
  v_cap    uuid := public.pirate_capital();
  v_target bigint := public.wc_num('pirate_city_purse')::bigint;
  v_keep   bigint := public.wc_num('pirate_capital_purse')::bigint;
  v_give   bigint;
  v_out    jsonb := '{}'::jsonb;
  r        record;
begin
  if v_cap is null or not public.city_treasury_on() then
    return v_out;
  end if;
  perform public.treasury_lock(v_cap);
  for r in select p.id, p.code from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
            where a.nation_id = public.pirate_nation() and p.id <> v_cap order by p.code loop
    v_give := least(greatest(0, v_target - public.treasury_balance(r.id)), greatest(0, public.city_surplus(v_cap) - v_keep));
    continue when v_give <= 0;
    perform public.treasury_post(v_cap, 'PIRATE_ALLOT', -v_give, null, null);
    perform public.treasury_post(r.id, 'PIRATE_ALLOT', v_give, null, null);
    v_out := v_out || jsonb_build_object(r.code, v_give);
  end loop;
  return v_out;
end
$body$;
$f$;

  execute $f$
create function public.pirate_purse_step(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0429: ONCE A MINUTE, from public.tick_pirates (lit, after its steps, add and pay; never behind a trade's locks). Never raises. Answers {woke, made, circuit, loaded}.
--   WAKE: up to pirate_wakes_per_run laid-up fleets the pirates keep (public.pirate_ord_wanted) back to work while the hoard is above
--     pirate_hoard_floor; their next hour is paid by public.pirate_pay_hour under the same floor.
--   THE CARGO SHIPS (lit cargo ships and purses): the first missing of pirate_cargo_ships is made at Port Royal (one a run) by the hands every
--     cargo ship is made by; the pirates' circuit from Port Royal is built when there is none or a harbour changed flag since; then ONE idle ship at
--     Port Royal loads (public.convoy_book LOADED) what the pirate harbours lack of pirate_city_purse, less what is aboard, at most pirate_city_purse,
--     never taking Port Royal under pirate_capital_purse nor the hoard under its floor. public.cargo_ship_step sails, delivers and brings home.
declare
  v_cap    uuid := public.pirate_capital();
  v_nat    uuid := public.pirate_nation();
  v_floor  bigint := public.wc_num('pirate_hoard_floor')::bigint;
  v_slice  bigint := round(public.wc_num('navy_upkeep_day') / 24);
  -- how many: the pirates' share of the cargo ships once the fleet sizes carry a row for them (0430: public.convoy_ships_of, about 7 of 100),
  -- else pirate_cargo_ships (5). pirate_cargo_ships 0 stops them either way.
  v_ships  int := case when coalesce(public.wc_int('pirate_cargo_ships'), 0) <= 0 then 0
                       when exists (select 1 from public.cargo_fleet_sizes s where s.nation_id = public.pirate_nation()) then public.convoy_ships_of(public.pirate_nation())
                       else public.wc_int('pirate_cargo_ships') end;
  v_target bigint := public.wc_num('pirate_city_purse')::bigint;
  v_woke   int := 0;
  v_made   int := 0;
  v_built  bigint;
  v_load   bigint := 0;
  v_need   bigint;
  v_aboard bigint;
  v_player uuid;
  v_fleet  uuid;
  v_n      int;
begin
  begin
    -- THE WAKE
    if public.pirate_hoard() - v_slice >= v_floor then
      update public.pirate_ships x set laid_up_at = null, unpaid_since = null
       where x.fleet_id in (select n.fleet_id from public.pirate_ships n
                             where n.laid_up_at is not null and public.pirate_ord_wanted(n.ord)
                             order by n.ord limit greatest(0, coalesce(public.wc_int('pirate_wakes_per_run'), 0)));
      get diagnostics v_woke = row_count;
    end if;

    -- THE CARGO SHIPS
    if v_cap is not null and v_ships > 0 and public.convoys_on() and public.city_treasury_on() then
      for v_n in 1 .. v_ships loop
        exit when v_made > 0;
        update public.cargo_ships c set laid_up_at = null where c.nation_id = v_nat and c.ord = v_n and c.laid_up_at is not null;
        continue when found or exists (select 1 from public.cargo_ships c where c.nation_id = v_nat and c.ord = v_n);
        insert into public.players (company_name, nation_id, ducats, is_npc)
        values (format('Brethren Cargo %s', v_n), v_nat, 0, true)
        returning id into v_player;
        v_fleet := public.form_fleet(v_player, format('Brethren cargo ship %s', v_n), v_cap);
        perform public.commission_ship(v_player, v_fleet, public.cargo_class(), format('Brethren cargo ship %s', v_n), true, false);
        insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord) values (v_fleet, v_player, v_nat, v_cap, v_n);
        v_made := v_made + 1;
      end loop;
      if exists (select 1 from public.cargo_ships c where c.nation_id = v_nat)
         and not exists (select 1 from public.cargo_circuits k where k.id = public.cargo_circuit_of(v_nat, v_cap)
                          and k.built_at >= coalesce((select max(a.since) from public.port_allegiance a), k.built_at)) then
        v_built := public.cargo_circuit_build(v_nat, v_cap);
      end if;
      select coalesce(sum(greatest(0, v_target - public.treasury_balance(p.id))), 0)::bigint into v_need
        from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
       where a.nation_id = v_nat and p.id <> v_cap;
      select coalesce(sum(b.aboard), 0)::bigint into v_aboard
        from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) b where c.nation_id = v_nat;
      v_load := least(v_need - v_aboard, v_target,
                      public.city_surplus(v_cap) - public.wc_num('pirate_capital_purse')::bigint,
                      public.pirate_hoard() - v_floor);
      if v_load > 0 then
        select c.fleet_id, c.player_id into v_fleet, v_player
          from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id
         where c.nation_id = v_nat and c.ord <= v_ships and f.status = 'DOCKED' and f.port_id = v_cap and c.home_port_id = v_cap and c.out_load is null
           and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
           and exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(v_nat, v_cap))
         order by c.ord limit 1
           for update of c skip locked;
        if v_fleet is not null and public.treasury_try_lock(v_cap) then
          perform public.convoy_book('LOADED', v_fleet, v_player, v_cap, v_load);
        else
          v_load := 0;
        end if;
      else
        v_load := 0;
      end if;
    end if;
  exception when others then
    raise warning 'pirate_purse_step: the run stopped (SQLSTATE %: %)', sqlstate, sqlerrm;
    return jsonb_build_object('error', sqlerrm);
  end;
  return jsonb_build_object('woke', v_woke, 'made', v_made, 'circuit', v_built, 'loaded', v_load);
end
$body$;
$f$;

  revoke all on function public.pirate_purses_allot(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_purse_step(timestamptz) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0429 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0429 values
  ('public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)', 1,
$h$  if public.pirate_spend_room(p_now) < p_amount or public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;$h$,
$h$  -- 0429 (the owner, 2026-11-15: "pirates should never be laid up"): an hour's pay and a wreck's refit are paid while the hoard stays at or
  -- above pirate_hoard_floor after the payment, whatever the day's room says; the room bounds every other kind. Every payment is still written to the day.
  if (case when p_kind in ('NAVY_PAY', 'REFIT') then public.pirate_hoard() - p_amount < public.wc_num('pirate_hoard_floor')::bigint
           else public.pirate_spend_room(p_now) < p_amount end)
     or public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;$h$),
  ('public.pirate_add(timestamp with time zone)', 1,
$h$    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then$h$,
$h$    if public.pirate_hoard() - v_slice < public.wc_num('pirate_hoard_floor')::bigint or public.city_surplus(v_cap) < v_slice then   -- 0429: a wake waits on the hoard's floor, not the day's room$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end;$h$,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end
         -- 0429: the wake and the pirate cargo ships (public.pirate_purse_step, which never raises), as the strikes
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end;$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);$h$,
$h$      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
      if public.pirate_power(c.nation_id) then
        return 'IDLE';   -- 0429: a pirate cargo ship's home is Port Royal, always: she never takes a new one
      end if;
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$      v_give := least(public.city_aid_target(f.port_id) - public.treasury_balance(f.port_id), v_left);$h$,
$h$      v_give := least(case when public.pirate_power(c.nation_id) then public.wc_num('pirate_city_purse')::bigint   -- 0429: a pirate city is topped up to pirate_city_purse
                           else public.city_aid_target(f.port_id) end - public.treasury_balance(f.port_id), v_left);$h$),
  ('public.cargo_circuit_plan(uuid,uuid,uuid)', 1,
$h$          union select p.id from public.ports p where p.kind = 'HARBOUR' and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap))) x;$h$,
$h$          union select p.id from public.ports p where p.kind = 'HARBOUR' and (p.id = p_to or (p_to is null and (public.city_capital(p.id) = v_cap
                                                                                                           -- 0429: the pirates keep no capital that aids (public.city_capital): their stops are their harbours
                                                                                                           or (public.pirate_power(p_nation) and public.port_nation(p.id) = p_nation))))) x;$h$),
  ('public.cargo_circuit_plan(uuid,uuid,uuid)', 2,
$h$                   where p.kind = 'HARBOUR' and p.id <> v_start and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap)) order by p.code);$h$,
$h$                   where p.kind = 'HARBOUR' and p.id <> v_start and (p.id = p_to or (p_to is null and (public.city_capital(p.id) = v_cap
                                                                                         or (public.pirate_power(p_nation) and public.port_nation(p.id) = p_nation)))) order by p.code);   -- 0429$h$),
  ('voyage.freeze_raiders(jsonb,uuid)', 1,
$h$  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments$h$,
$h$  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet)
                   or coalesce(public.crown_nation(p_fleet) = public.pirate_nation(), false) then p_segments   -- 0429: nor a ship of the pirates' own country (their cargo ships)$h$),
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$      v_sea, r_kind using errcode = 'P0001';
  end if;
$h$,
$h$      v_sea, r_kind using errcode = 'P0001';
  end if;

  -- 0429: a cargo ship of the pirates' own country is never raided by pirates: her PIRATES day passes her by (read only on such a day)
  if kind = 'PIRATES' and exists (select 1 from public.voyages v join public.cargo_ships c on c.fleet_id = v.fleet_id
                                   where v.id = p_voyage and public.pirate_power(c.nation_id)) then
    occurred := false;
    kind := null;
  end if;
$h$);

  for v_h in select h.fn from hunks_0429 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0429 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0429 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0429 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0429 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0429 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0429 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0429 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_new) f join public.client_rpc_entry_points() e on e.fn = f::regprocedure) then
    raise exception '0429 self-assert FAIL: a function of this file is open to clients';
  end if;
  if public.wc_int('pirate_hoard_floor') <> 100000000 or public.wc_int('pirate_city_purse') <> 10000000 or public.wc_int('pirate_capital_purse') <> 30000000
     or public.wc_int('pirate_cargo_ships') <> 5 or public.wc_int('pirate_wakes_per_run') <> 20
     or (v_kept = '' and public.wc_num('pirate_spend_day_pct') <> 0.01) then
    raise exception '0429 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 6. THE ALLOTMENT, ONCE (lit purses: real rows, moved) ──
  v_sum0 := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t);
  v_allot := public.pirate_purses_allot(now());
  if (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) <> v_sum0 then
    raise exception '0429 self-assert FAIL: the allotment changed the purses'' sum (it must only move)';
  end if;
  if public.city_treasury_on() and public.city_surplus(public.pirate_capital()) >= public.wc_num('pirate_capital_purse') + 8 * public.wc_num('pirate_city_purse') then
    if exists (select 1 from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
                where a.nation_id = public.pirate_nation() and p.id <> public.pirate_capital() and public.treasury_balance(p.id) < public.wc_num('pirate_city_purse')) then
      raise exception '0429 self-assert FAIL: a pirate city is under pirate_city_purse after the allotment: %', v_allot;
    end if;
  end if;
  if public.city_treasury_on() and public.city_surplus(public.pirate_capital()) < public.wc_num('pirate_capital_purse')
     and v_allot <> '{}'::jsonb then
    raise exception '0429 self-assert FAIL: the allotment took Port Royal under pirate_capital_purse';
  end if;

  -- ── 7. THE NEWS (0347's law) ──
  perform public.news_update('0429', 'The pirate cities are funded; pirate cargo ships carry Port Royal''s gold',
                             '해적 도시에 자금이 배정되고, 해적 화물선이 포트로열의 금을 나른다');

  -- ── 8. THE PROBE, rolled back by a raised sentinel: one tick of public.pirate_purse_step, lit as prod is (it answers, it never raises) ──
  v_n := (select count(*) from public.cargo_ships c where c.nation_id = public.pirate_nation());
  begin
    update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'convoys_enabled') and value is distinct from 'true'::jsonb;
    v_probe := public.pirate_purse_step(now());
    if v_probe ? 'error' then
      raise exception '0429 self-assert FAIL: public.pirate_purse_step raised inside: %', v_probe ->> 'error';
    end if;
    v_note := v_probe::text;
    raise exception sqlstate 'BV429';
  exception when sqlstate 'BV429' then null;
  end;
  if (select count(*) from public.cargo_ships c where c.nation_id = public.pirate_nation()) <> v_n then
    raise exception '0429 self-assert FAIL: the probe left a pirate cargo ship standing';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0429 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0429 self-assert ok: THE PIRATE CITIES HAVE PURSES. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 2 new functions, server-only; the capital is POR. Allotted %. Knobs: floor %, city purse %, Port Royal keeps %, % cargo ships, % wakes a run, room %.% Probe (rolled back): %; % ms.',
    (select count(*) from hunks_0429), v_allot, public.wc_int('pirate_hoard_floor'), public.wc_int('pirate_city_purse'), public.wc_int('pirate_capital_purse'),
    public.wc_int('pirate_cargo_ships'), public.wc_int('pirate_wakes_per_run'), public.wc_num('pirate_spend_day_pct'),
    case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0429;
end $m$;
