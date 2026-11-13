-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0370 — A COMPANY BUYS ROOM AND STARTS A SECOND FLEET: world_config `fleet_room_bite` false -> true, and `fleet_hard_max` 5 -> 6. Two knob rows and one news row. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. Owner rows 180 and 316: "multiple fleets, with multiple ships"; "unlock slots by purchasing with gold, and some with levels". 0321 built the ladders and the move door, 0354 the
--   buying door and the room read, #617 the Fleets page (New fleet, Buy room, Move a ship): all dark behind `fleet_room_bite`. Owner row 323 asks for an armada of up to SIX fleets (0367),
--   and the one thing holding a company at five is the knob `fleet_hard_max` (public.fleet_room_caps: least(fleet_hard_max, 2 free + 2 Trading rungs + 2 bought steps)).
--   Owner, 2026-11-13 (row 324): "do all, make everything work. open them if everything is built and is workable." This file is that one light (the form of 0178 and 0179).
-- WHAT THE SWITCH TURNS ON (every reader is live already; none is touched here):
--   * a company's caps are the ladders: fleets = 2 + Trading rungs reached (3, 6) + steps bought (60,000 then 1,000,000 d.), at most 6;
--     ships in a fleet = 2 + the higher of Seamanship and Command + steps bought (10,000 to 160,000 d.), at most 7;
--   * cmd.buy_room sells a step (ledger kind SLOT); cmd.move_ship moves a ship to another fleet of hers, or into a NEW fleet at her port; world.ship_moves and world.house_room say `on`;
--   * the Fleets page stops saying "Not open yet": New fleet is a real flow, the room rows carry Buy, a ship's sheet carries Move.
--   * EVERY OTHER HOUSE (merchants, crown cargo ships, navy, pirates): two fleets as today; ships in a fleet at most 7 where it was 8 (fleet_ship_top). The guard below reads that none is over.
-- THE GOLD (decided by default, as built in 0354; the owner may reverse): gold paid for room is DESTROYED. It reaches no purse and no city (ledger kind SLOT, Stats side "removed").
--   With the economy closed, `economy_closed_total` then stands above the real total by the SLOT sum. The other way, paying the realm's capital (public.pay_city in public.buy_room_for,
--   the word "moved"), is one small forward migration.
-- GUARD (the file refuses, and nothing is written, when any of these is not so):
--   * 0321's and 0354's functions and 0347's news exist;
--   * `fleet_room_bite` reads exactly false and `fleet_hard_max` exactly 5; nobody holds bought room yet (public.house_room is empty: buying was dark);
--   * the ladder can reach the new top: fleet_max + the Trading rungs + the fleet prices >= 6; and 0367's `armada_fleet_max`, where it exists, is not below 6;
--   * THE PRECONDITION READ (scripts/ops/harness/fleet-room/over-caps.sql, written here as an assert): with the top at 6, no house of any kind stands over its lit caps
--     (over_fleets, over_ships_a_fleet, over_hulls all 0). A house over a cap would be refused her next new ship, new fleet or moved ship.
-- SELF-ASSERT, on a probe company of this file's own, rolled back: the room read says on and top 6; she buys both fleet steps at the knob prices (one SLOT row each, the gold in no
--   purse); the third press is refused E_ROOM_BY_LEVEL; with both Trading rungs reached she keeps room for SIX fleets and the next press is refused E_ROOM_TOP; she moves her second ship
--   into a new fleet; THE ROLLBACK PLAYED inside the probe (the switch set false) refuses a buy E_NOT_IN_USE and gives the flat caps back. The catalog: no function moved; exactly two
--   world_config rows moved; the news row is one row.
-- ALTERS LIVE PLAY: its own window, a 30-minute after-check (scripts/ops/harness/fleet-room/after-light.sql every few minutes: unbalanced 0, past_top 0, merchant_rows 0, room_events = steps_held).
-- ROLLBACK (forward; a draft is scripts/ops/harness/fleet-room/rollback-0370.sql): `fleet_room_bite` false. The caps return to the flat ones at once. Gold already paid stays paid and its
--   house_room rows stay (they count again if it is relit); a second fleet already formed stays a fleet. `fleet_hard_max` may stay 6: nothing reads it while dark.
--   The one-line form (owner only): update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0370', 'Fleets: buy room, start a second fleet', '선단: 자리 구매, 두 번째 선단 시작') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0370 - deploys after 0369 (ship_stores_separate), in its own window. It names no function of 0364, 0366 or 0367; it reads 0367's knob only where it exists.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_houses      int;
  v_over        int;
  v_names       text;
  v_reach       int;
  v_fn_before   text;
  v_cfg_before  text;
  v_lived       boolean := false;
  v_lis         uuid;
  v_pl          uuid;
  v_f1          uuid;
  v_s2          uuid;
  v_room        jsonb;
  v_r           jsonb;
  v_p1          bigint;
  v_p2          bigint;
  v_others      bigint;
  v_ms_over     numeric;
  v_ms_probe    numeric;
  c_uid         constant uuid := '00000000-0370-4000-8000-000000000001';
  c_purse       constant bigint := 2000000;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.fleet_room_on()', 'public.fleet_room_caps(uuid)', 'public.earned_caps(uuid)', 'public.house_ship_max(uuid)', 'public.buy_room_for(uuid,text)',
                                        'cmd.buy_room(text)', 'world.house_room()', 'public.move_ship(uuid,uuid,uuid,text)', 'public.form_fleet(uuid,text,uuid)', 'cmd.assume_identity(uuid)',
                                        'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.house_room') is null then
    raise exception '0370 refuses: fleet room (0321, 0354) or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = 'fleet_room_bite') is distinct from 'false'::jsonb or public.fleet_room_on() then
    raise exception '0370 refuses: fleet_room_bite is not false in this world (it reads %): this file lights it once, from dark', (select c.value from public.world_config c where c.key = 'fleet_room_bite');
  end if;
  if (select c.value from public.world_config c where c.key = 'fleet_hard_max') is distinct from '5'::jsonb then
    raise exception '0370 refuses: fleet_hard_max is not 5 in this world (it reads %): this file was written to raise it from 5 to 6', (select c.value from public.world_config c where c.key = 'fleet_hard_max');
  end if;
  if exists (select 1 from public.house_room) then
    raise exception '0370 refuses: % row(s) of bought room exist while buying was dark; read scripts/ops/harness/fleet-room/after-light.sql first', (select count(*) from public.house_room);
  end if;
  v_reach := public.wc_int('fleet_max') + jsonb_array_length(public.wc('fleet_room_levels')) + jsonb_array_length(public.wc('fleet_room_prices'));
  if v_reach < 6 then
    raise exception '0370 refuses: the fleet ladder adds up to % (free + level rungs + prices), so a top of 6 could not be reached', v_reach;
  end if;
  if exists (select 1 from public.world_config c where c.key = 'armada_fleet_max' and (c.value #>> '{}')::int < 6) then
    raise exception '0370 refuses: armada_fleet_max is below 6, so six fleets could not sail as one';
  end if;

  -- ── 1. BEFORE: the catalog and every OTHER knob ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key not in ('fleet_room_bite', 'fleet_hard_max');

  -- ── 2. THE TOP: five fleets -> six (owner row 323). Nothing reads it while the switch is dark. ──
  update public.world_config
     set value = '6'::jsonb, updated_at = now(), description = description || ' RAISED 5 -> 6 by 0370 (owner row 323: an armada of up to six fleets).'
   where key = 'fleet_hard_max' and value = '5'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or public.wc_int('fleet_hard_max') <> 6 then
    raise exception '0370 self-assert FAIL: % row(s) of fleet_hard_max written, and it reads %', v_n, public.wc_int('fleet_hard_max');
  end if;

  -- ── 3. THE PRECONDITION READ (over-caps.sql as an assert): no house of any kind stands over its lit caps. public.fleet_room_caps does not read the switch. ──
  v_t := clock_timestamp();
  with h as (
    select p.id, p.company_name, p.is_npc, public.fleet_room_caps(p.id) as lit,
           (select count(*) from public.fleets f where f.player_id = p.id) as fleets,
           (select count(*) from public.ships s where s.player_id = p.id) as ships,
           (select coalesce(max(x.n), 0) from (select count(*) as n from public.ships s where s.player_id = p.id group by s.fleet_id) x) as most
      from public.players p
  ), j as (
    select h.*, (h.lit ->> 'fleet_max')::int as lit_fleets, (h.lit ->> 'fleet_ship_max')::int as lit_ships,
           case when h.is_npc then public.house_ship_max(h.id) else (h.lit ->> 'fleet_max')::int * (h.lit ->> 'fleet_ship_max')::int end as lit_hulls
      from h
  )
  select count(*), count(*) filter (where j.fleets > j.lit_fleets or j.most > j.lit_ships or j.ships > j.lit_hulls),
         string_agg(j.company_name, ', ' order by j.company_name) filter (where j.fleets > j.lit_fleets or j.most > j.lit_ships or j.ships > j.lit_hulls)
    into v_houses, v_over, v_names from j;
  if v_over > 0 then
    raise exception '0370 refuses: % house(s) would stand over the lit caps (over_fleets, over_ships_a_fleet or over_hulls is not 0): %; run scripts/ops/harness/fleet-room/over-caps.sql', v_over, left(v_names, 400);
  end if;
  v_ms_over := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. THE LIGHT ──
  update public.world_config
     set value = 'true'::jsonb, updated_at = now(), description = description || ' LIT by 0370 (owner row 324, 2026-11-13).'
   where key = 'fleet_room_bite' and value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or not public.fleet_room_on() then
    raise exception '0370 self-assert FAIL: % row(s) of fleet_room_bite written, and the reader says %', v_n, public.fleet_room_on();
  end if;

  -- ── 5. THE SELF-ASSERT: a probe company of this file's own, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select coalesce(sum(p.ducats), 0) into v_others from public.players p;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Prova 0370', (select n.id from public.nations n where n.code = 'PRT'), c_purse, false) returning id into v_pl;
    v_f1 := public.form_fleet(v_pl, 'Prova 0370', v_lis);
    perform public.commission_ship(v_pl, v_f1, 'barca', 'Primeira 0370', true, true);
    perform public.commission_ship(v_pl, v_f1, 'barca', 'Segunda 0370', false, true);
    select s.id into v_s2 from public.ships s where s.fleet_id = v_f1 and not s.is_flagship;
    perform cmd.assume_identity(c_uid);

    -- the room read: lit, the top is six, two level rungs and two prices
    v_room := world.house_room();
    if (v_room ->> 'on')::boolean is not true or (v_room -> 'fleets' ->> 'top')::int <> 6 or (v_room -> 'fleets' ->> 'have')::int <> public.wc_int('fleet_max')
       or (v_room -> 'fleets' ->> 'price')::bigint is distinct from (public.wc('fleet_room_prices') ->> 0)::bigint
       or jsonb_array_length(v_room -> 'fleets' -> 'steps') <> jsonb_array_length(public.wc('fleet_room_levels')) + jsonb_array_length(public.wc('fleet_room_prices')) then
      raise exception '0370 self-assert FAIL: lit, the room read is not on, top 6, the free fleets and the first price: %', v_room -> 'fleets';
    end if;
    -- both fleet steps, at the knob prices; the gold reaches no purse
    v_p1 := (public.wc('fleet_room_prices') ->> 0)::bigint;
    v_p2 := (public.wc('fleet_room_prices') ->> 1)::bigint;
    v_r := cmd.buy_room('FLEET');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'price')::bigint <> v_p1 or (v_r ->> 'fleet_max')::int <> public.wc_int('fleet_max') + 1 then
      raise exception '0370 self-assert FAIL: the first fleet step was not bought at %: %', v_p1, v_r;
    end if;
    v_r := cmd.buy_room('FLEET');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'price')::bigint <> v_p2 or (v_r ->> 'fleet_max')::int <> public.wc_int('fleet_max') + 2 then
      raise exception '0370 self-assert FAIL: the second fleet step was not bought at %: %', v_p2, v_r;
    end if;
    if (select pl.ducats from public.players pl where pl.id = v_pl) <> c_purse - v_p1 - v_p2
       or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'SLOT') <> 2
       or (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_pl and l.kind = 'SLOT') <> v_p1 + v_p2
       or (select coalesce(sum(p.ducats), 0) from public.players p where p.id <> v_pl) <> v_others
       or (select h.steps from public.house_room h where h.player_id = v_pl and h.kind = 'FLEET') <> 2 then
      raise exception '0370 self-assert FAIL: the two steps did not take exactly % from her purse as two SLOT rows, or the gold reached another purse', v_p1 + v_p2;
    end if;
    -- every price used and room still to open: by level
    v_r := cmd.buy_room('FLEET');
    if v_r ->> 'error_code' is distinct from 'E_ROOM_BY_LEVEL' then
      raise exception '0370 self-assert FAIL: every fleet price used, and the next press answered: %', v_r;
    end if;
    -- SIX: both Trading rungs reached (the knob moved inside this probe only) and both steps bought
    update public.world_config set value = '[1, 1]'::jsonb where key = 'fleet_room_levels';
    v_r := cmd.buy_room('FLEET');
    if (public.earned_caps(v_pl) ->> 'fleet_max')::int <> 6 or v_r ->> 'error_code' is distinct from 'E_ROOM_TOP' or v_r ->> 'error_message' not like '%6 fleets%' then
      raise exception '0370 self-assert FAIL: both rungs and both steps do not give six fleets, or the press at the top answered: % (caps %)', v_r, public.earned_caps(v_pl);
    end if;
    -- a second fleet, by the move door
    v_r := public.move_ship(v_pl, v_s2, null, 'Segunda Frota 0370');
    if (select count(*) from public.fleets f where f.player_id = v_pl) <> 2
       or (select count(*) from public.ships s where s.id = v_s2 and s.fleet_id <> v_f1) <> 1 then
      raise exception '0370 self-assert FAIL: lit, her second ship did not start a second fleet: %', v_r;
    end if;
    -- THE ROLLBACK, PLAYED: the switch set back refuses a buy and gives the flat caps back; what she bought and formed stays
    update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
    v_r := cmd.buy_room('SHIP');
    if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (public.earned_caps(v_pl) ->> 'fleet_max')::int <> public.wc_int('fleet_max')
       or (select count(*) from public.fleets f where f.player_id = v_pl) <> 2 or (select h.steps from public.house_room h where h.player_id = v_pl and h.kind = 'FLEET') <> 2 then
      raise exception '0370 self-assert FAIL: with the switch set back a buy answered %, or the flat caps did not return, or what she holds was taken', v_r;
    end if;
    raise exception using errcode = 'ZX370', message = 'PROBE_ROLLBACK_0370';
  exception when sqlstate 'ZX370' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0370 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid = c_uid) or exists (select 1 from public.house_room) then
    raise exception '0370 self-assert FAIL: the probe company or her bought room outlived the probe';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 6. AFTER: lit, six, and nothing else moved ──
  if not public.fleet_room_on() or public.wc_int('fleet_hard_max') <> 6 then
    raise exception '0370 self-assert FAIL: after the probe the switch is not lit or the top is not 6';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0370 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('fleet_room_bite', 'fleet_hard_max')) <> v_cfg_before then
    raise exception '0370 self-assert FAIL: another world_config row moved: this file writes two';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0370', 'Fleets: buy room, start a second fleet', '선단: 자리 구매, 두 번째 선단 시작');
  if (select count(*) from public.world_news w where w.key = 'update:0370') <> 1 then
    raise exception '0370 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0370 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0370 timings: the over-caps read (% house(s)) % ms; the probe % ms', v_houses, v_ms_over, v_ms_probe;
  raise notice '0370 self-assert ok: A COMPANY BUYS ROOM AND STARTS A SECOND FLEET. fleet_room_bite was false and is true; fleet_hard_max was 5 and is 6. None of % house(s) stands over its lit caps. A probe company: the room read is on with a top of 6; she bought both fleet steps for % and % (two SLOT rows, the gold in no purse); the third press is refused E_ROOM_BY_LEVEL; with both Trading rungs reached she keeps room for six fleets and the next press is refused E_ROOM_TOP; her second ship started a second fleet; with the switch set back (the rollback, played and rolled back) a buy is refused E_NOT_IN_USE and the flat caps return. No function moved, no other knob moved, its UPDATE row is one row. % ms.',
    v_houses, v_p1, v_p2, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
