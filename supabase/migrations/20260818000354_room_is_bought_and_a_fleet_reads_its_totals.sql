-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0354 — ROOM IS BOUGHT, AND A FLEET READS ITS TOTALS: F3 + F4 of docs/FLEETS_AND_SLOTS.md, and a door to rename a fleet. DARK-SAFE
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 180 and 316: "multiple fleets, with multiple ships"; "unlock slots by purchasing with gold, and some with levels"; "Show stats of individual ship and also as a fleet".
-- docs/SUCCESS_PLAN.md section D. 0321 counted the room and let a ship change fleets, dark. This file adds what a company PAYS for room, what a fleet adds up to, and a fleet's new name.
--
-- WHAT THIS FILE ADDS
--   public.fleet_totals(fleet, ships)  F4. A fleet's totals, summed from the very ship reads world.fleets() has just built (world.ship_view): ships, attack, hull now and at most, crew aboard / needed / bunks,
--                                      the ships short of crew, the slowest ship named with her speed, and wages a day from THE wages authority (public.fleet_wage). No second formula: sums of served figures.
--   public.room_steps(...)             The rows of one ladder: each level rung and each price, open or not. Pure.
--   world.house_room()                 F4. STABLE. Fleets and ships-per-fleet: what she has now, the top, each step (level N of which track, or a price), what the next step costs, whether she can pay,
--                                      and `on`: whether fleet room is lit. Dark, the client says "not open yet" from it and draws no dead button.
--   public.buy_room_for(player, kind)  F3. THE writer of public.house_room. One step at a time, FLEET or SHIP. The price is the next unbought one of the knob (0321's fleet_room_prices, ship_room_prices).
--   cmd.buy_room(kind)                 Its door. No player id.
--   public.rename_fleet(player, fleet, name), cmd.rename_fleet(fleet, name)   A fleet of hers takes a new name. Works whatever the switch says, and wherever the fleet is.
--   ledger kind SLOT                   public.stats_flow_words, side 'removed': the first removed kind in the table. See THE GOLD below.
--   events ROOM_OPENED, FLEET_RENAMED  One each, at the press.
--
-- THE HUNKS, each occurs once in the live body and reverses to its pre-image:
--   world.fleets (2): the ships of a fleet are built ONCE in a lateral, served as `ships` as before, and handed to public.fleet_totals for the new key `totals`. Every other key is the old expression, untouched.
--   public.client_rpc_entry_points (1): the three new rows, after 0321's.
-- SUPERSEDES (re-cut): world.fleets (0009; 0321 cut it too, on another line), public.client_rpc_entry_points (0321 and others cut it too, on other lines). By hunks, not whole bodies.
-- NOT CUT: public.earned_caps, public.house_ship_max, public.fleet_room_caps, public.assert_house_caps. The caps read public.house_room since 0321, only while lit. This file only gives that table its writer.
--
-- DARK (`fleet_room_bite` false) NOTHING CHANGES FOR ANYONE, but for: the new key `totals` on world.fleets(), the new read world.house_room(), and the rename door.
--   cmd.buy_room refuses E_NOT_IN_USE and takes no gold: room bought dark would be gold paid for nothing, since the dark caps do not read it. The design's F3 row says the same ("No while dark").
--
-- THE GOLD (design section 2.3, Q6): destroyed. One ledger row, kind SLOT, through THE gold door public.credit, with a negative delta, and no purse receives it. public.mint_guard is asked only for a
--   positive delta, so a closed economy does not refuse it. It is registered 'removed', so Stats counts it as money removed (the client already draws that side as "Burned").
--   NOTE FOR THE OWNER: docs/CLOSED_ECONOMY.md section 2.3 says every ducat is always in a purse, and that doc is younger than the room design. With the economy closed, each ducat paid here lowers the
--   world's total for good; `economy_closed_total` is then above the real total by exactly the SLOT sum. To pay a city instead is one line: public.pay_city to the realm's capital, and the word 'moved'.
--
-- THE PRICE LADDER, as served: a company's Nth bought step of a kind costs the Nth figure of the knob. FLEET: 60,000 then 1,000,000. SHIP: 10,000, 20,000, 40,000, 80,000, 160,000.
--   0321 already decided that levels and bought steps ADD UP (2 + rungs reached + bought, at most 5; 2 + the higher skill + bought, at most 7), so a price belongs to a company's Nth buy, not to "the 3rd fleet".
--   Refused: at the top (E_ROOM_TOP), when every price is used and only a level opens more (E_ROOM_BY_LEVEL), short of gold (E_INSUFFICIENT_FUNDS, with what she has and what it costs). Never refunded (Q11).
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - Buying is dark with the room (one switch, as 0321 chose for the door).
--   - A fleet is renamed in any state: docked, at sea, in a battle, empty. Nothing keys on a fleet's name but public.tg_ledger_points, which reads the name at the moment an event is written.
--     The name's rules are the table's own (fleets_name_check 3 to 24 letters, fleets_player_name_unique): the constraints judge, as cmd.found_house lets them for a company. E_BAD_NAME, E_NAME_TAKEN.
--     A rename does not raise fleets.version: no order means something else under a new name.
--   - `totals` carries no berth count: that is public.earned_caps, which reads public.player_progress, and world.fleets() is asked every 30 s by every client. world.house_room() serves the berths.
--   - `attack` is the sum of the ships' attack (world.ship_stats through world.ship_view). No ship read serves a count of guns, so none is summed.
--
-- NEWS: this file posts its own UPDATE row, 'Fleet totals, rename' / '선단 합계, 이름 변경' (0347's law, tests/news.lint.spec.ts): what is live for a player at this deploy.
--   Buying room is NOT announced: it is dark, and its news belongs to the step that lights fleet_room_bite.
--
-- LIGHTING IS NOT HERE. Whether any company would stand over its lit caps is a prod read: scripts/ops/harness/fleet-room/over-caps.sql.
--
-- SELF-ASSERT: the catalog (hunks once and reversing; ACL, volatility, definer and config unmoved; no other function; no knob; the registry; the grants), then ONE probe of this file's own rows, rolled back by
--   a raised sentinel: dark parity of world.fleets() without `totals` against its pre-image, the totals against the per-ship reads, the door dark, a rename and its refusals; then, with the switch set INSIDE the
--   probe, a fleet step and two ship steps (purse, ledger kind, caps), short of gold, the top, level only. No table is counted or summed beyond the probe's own rows. The larger proof is CI's:
--   scripts/db/proofs/57_fleet_room_bought.sql.
-- COST: world.fleets() OLD against NEW on the probe's two fleets, interleaved, printed. Local figures and prod guidance in docs/dev-log/2026-11-11-fleet-room-f3-f4.md.
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): swap the three hunks' old and new, drop the seven functions, delete the SLOT word. `fleet_room_bite` false already shuts the buying door.
-- VERSION: 0354, after 0351 (world.best_sales), 0352 (world.player, voyage.settle, cmd.do_sell, cmd.run_fulfil, cmd.do_build) and 0353 (the fight log). Written against main at 0350; it cuts none of those bodies.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_h           record;
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_words_before text;
  v_fleets_old  text;
  v_lived       boolean := false;
  v_pl          uuid;
  v_other       uuid;
  v_npc         uuid;
  v_f1          uuid;
  v_f2          uuid;
  v_fo          uuid;
  v_lis         uuid;
  v_r           jsonb;
  v_x           jsonb;
  v_old         jsonb;
  v_new         jsonb;
  v_caps0       jsonb;
  v_hull0       int;
  v_purse       bigint;
  v_old_ms      numeric := 0;
  v_new_ms      numeric := 0;
  v_pairs       int := 0;
  c_uid   constant uuid := '00000000-0354-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0354-4000-8000-000000000002';
  c_new_fns constant text[] := array[
    'public.fleet_totals(uuid,jsonb)', 'public.room_steps(jsonb,integer,jsonb,jsonb,integer,boolean,bigint)', 'world.house_room()',
    'public.buy_room_for(uuid,text)', 'cmd.buy_room(text)', 'public.rename_fleet(uuid,uuid,text)', 'cmd.rename_fleet(uuid,text)'];
  c_doors constant text[] := array['world.house_room()', 'cmd.buy_room(text)', 'cmd.rename_fleet(uuid,text)'];
  c_hunked constant text[] := array['world.fleets()', 'public.client_rpc_entry_points()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.buy_room_for(uuid,text)') is not null or to_regprocedure('world.house_room()') is not null
     or exists (select 1 from public.stats_flow_words w where w.kind = 'SLOT') then
    raise exception '0354 refuses: it has been applied once';
  end if;
  if to_regclass('public.house_room') is null or to_regprocedure('public.fleet_room_caps(uuid)') is null or to_regprocedure('public.fleet_room_on()') is null
     or to_regprocedure('public.fleet_wage(uuid,boolean,integer)') is null or to_regprocedure('world.ship_view(uuid)') is null
     or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null or to_regprocedure('cmd.refused_envelope(text,text)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null
     or not exists (select 1 from public.world_config c where c.key = 'fleet_room_prices') or not exists (select 1 from public.world_config c where c.key = 'ship_room_prices') then
    raise exception '0354 refuses: 0321 (the room) or a function this file calls is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before from public.stats_flow_words w;
  v_fleets_old := replace(pg_get_functiondef('world.fleets()'::regprocedure), E'\r', '');

  -- ── 1. THE LEDGER KIND: gold paid for room leaves the world ──
  insert into public.stats_flow_words (kind, side, word, ord) values ('SLOT', 'removed', 'Fleet room', 56);

  -- ── 2. F4: THE READS ──
  execute $f$
create function public.fleet_totals(p_fleet uuid, p_ships jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0354 (docs/FLEETS_AND_SLOTS.md section 2.5): A FLEET'S TOTALS, summed from the ship reads world.fleets() has just built (world.ship_view), so a total can never disagree with the ships under it.
  -- Wages a day are public.fleet_wage's, the figure voyage.settle charges. The slowest ship is the one voyage.fleet_speed_at takes its minimum from. A fleet with no ship: zeros, slowest null.
  select jsonb_build_object(
    'ships', count(*)::int,
    'attack', coalesce(sum((v ->> 'attack')::numeric), 0),
    'hull', coalesce(sum((v ->> 'durability')::numeric), 0),
    'hull_max', coalesce(sum((v ->> 'max_durability')::numeric), 0),
    'crew', coalesce(sum((v ->> 'crew')::numeric), 0),
    'crew_required', coalesce(sum((v ->> 'crew_required')::numeric), 0),
    'crew_max', coalesce(sum((v ->> 'crew_max')::numeric), 0),
    'short_crew', coalesce(jsonb_agg(v -> 'name' order by v ->> 'name') filter (where (v ->> 'crew')::numeric < (v ->> 'crew_required')::numeric), '[]'::jsonb),
    'wages_day', public.fleet_wage(p_fleet, false, coalesce(sum((v ->> 'crew')::numeric), 0)::int),
    'slowest', (select jsonb_build_object('id', x -> 'id', 'name', x -> 'name', 'speed', x -> 'speed')
                  from jsonb_array_elements(p_ships) x order by (x ->> 'speed')::numeric, x ->> 'name' limit 1))
    from jsonb_array_elements(p_ships) v
$$
  $f$;

  execute $f$
create function public.room_steps(p_levels jsonb, p_level int, p_tracks jsonb, p_prices jsonb, p_bought int, p_full boolean, p_purse bigint)
returns jsonb
language sql
immutable
as $$
  -- 0354: THE ROWS OF ONE LADDER. Each level rung (open when her level has reached it), then each price in order (open when bought; `next` is the one a press would buy now).
  select coalesce((select jsonb_agg(jsonb_build_object('how', 'level', 'tracks', p_tracks, 'level', l.value::int, 'open', p_level >= l.value::int) order by l.ord)
                     from jsonb_array_elements_text(p_levels) with ordinality l(value, ord)), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_build_object('how', 'gold', 'price', g.value::bigint, 'open', g.ord <= p_bought,
                                                       'next', g.ord = p_bought + 1 and not p_full, 'can_pay', p_purse >= g.value::bigint) order by g.ord)
                     from jsonb_array_elements_text(p_prices) with ordinality g(value, ord)), '[]'::jsonb)
$$
  $f$;

  execute $f$
create function world.house_room()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0354 (docs/FLEETS_AND_SLOTS.md section 2.2, F4): THE ROOM A COMPANY HAS, AND HOW MORE OPENS. `have` is public.earned_caps, what the caps trigger enforces this minute. `ladder` is public.fleet_room_caps,
-- what the ladder gives (the same figure while lit). `on` is fleet_room_bite: false means nothing here can be bought yet and the rungs do not count yet. The steps add up: free + open rungs + bought, at most `top`.
-- A merchant or a signed-out caller: {company: false}.
declare
  v_id      uuid := public.current_player_id();
  v_on      boolean := public.fleet_room_on();
  v_purse   bigint;
  v_now     jsonb;
  v_lad     jsonb;
  v_fb      int;
  v_sb      int;
  v_ftop    int := public.wc_int('fleet_hard_max');
  v_stop    int := public.wc_int('fleet_ship_top');
  v_fprices jsonb := public.wc('fleet_room_prices');
  v_sprices jsonb := public.wc('ship_room_prices');
  v_ffull   boolean;
  v_sfull   boolean;
begin
  select p.ducats into v_purse from public.players p where p.id = v_id and not p.is_npc;
  if v_purse is null then
    return jsonb_build_object('company', false, 'on', v_on);
  end if;
  v_now := public.earned_caps(v_id);
  v_lad := public.fleet_room_caps(v_id);
  v_fb := coalesce((select h.steps from public.house_room h where h.player_id = v_id and h.kind = 'FLEET'), 0);
  v_sb := coalesce((select h.steps from public.house_room h where h.player_id = v_id and h.kind = 'SHIP'), 0);
  v_ffull := (v_lad ->> 'fleet_max')::int >= v_ftop;
  v_sfull := (v_lad ->> 'fleet_ship_max')::int >= v_stop;
  return jsonb_build_object(
    'company', true, 'on', v_on, 'purse', v_purse,
    'fleets', jsonb_build_object(
      'have', (v_now ->> 'fleet_max')::int, 'ladder', (v_lad ->> 'fleet_max')::int, 'top', v_ftop, 'free', public.wc_int('fleet_max'),
      'used', (select count(*)::int from public.fleets f where f.player_id = v_id),
      'bought', v_fb, 'full', v_ffull,
      'price', case when not v_ffull then (v_fprices ->> v_fb)::bigint end,
      'steps', public.room_steps(public.wc('fleet_room_levels'), (public.player_progress(v_id) -> 'trading' ->> 'level')::int, '["trading"]'::jsonb,
                                 v_fprices, v_fb, v_ffull, v_purse)),
    'ships', jsonb_build_object(
      'have', (v_now ->> 'fleet_ship_max')::int, 'ladder', (v_lad ->> 'fleet_ship_max')::int, 'top', v_stop, 'free', public.wc_int('fleet_ship_base'),
      'used', (select coalesce(max(x.n), 0)::int from (select count(*) as n from public.ships s where s.player_id = v_id group by s.fleet_id) x),
      'bought', v_sb, 'full', v_sfull,
      'price', case when not v_sfull then (v_sprices ->> v_sb)::bigint end,
      'steps', public.room_steps((select coalesce(jsonb_agg(k order by k), '[]'::jsonb)
                                    from generate_series(1, least(v_stop - public.wc_int('fleet_ship_base'), public.wc_int('skill_max_level'))) k),
                                 greatest(public.skill_level(v_id, 'SEAMANSHIP'), public.skill_level(v_id, 'COMMAND')), '["seamanship", "command"]'::jsonb,
                                 v_sprices, v_sb, v_sfull, v_purse)),
    'hulls', jsonb_build_object('have', public.house_ship_max(v_id), 'used', (select count(*)::int from public.ships s where s.player_id = v_id)));
end $$
  $f$;

  -- ── 3. F3: ROOM IS BOUGHT ──
  execute $f$
create function public.buy_room_for(p_player uuid, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0354 (docs/FLEETS_AND_SLOTS.md sections 2.2, 2.3, F3): THE one writer of public.house_room. One step of FLEET or SHIP room, at the next unbought price of the knob, paid through public.credit as kind SLOT:
-- a negative delta that no purse receives. Refuses before anything moves. The house row is locked first, so two presses cannot both buy one price. Never refunded.
declare
  v_kind   text := upper(btrim(coalesce(p_kind, '')));
  v_npc    boolean;
  v_have   bigint;
  v_now    int;
  v_top    int;
  v_bought int;
  v_prices jsonb;
  v_price  bigint;
  v_event  uuid;
  v_after  bigint;
  v_caps   jsonb;
begin
  if not public.fleet_room_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'fleet room is not in use yet');
  end if;
  if v_kind not in ('FLEET', 'SHIP') then
    perform cmd.refuse('E_PARSE', 'room is bought for FLEET or for SHIP');
  end if;
  select p.is_npc, p.ducats into v_npc, v_have from public.players p where p.id = p_player for update;
  if v_npc is null then
    perform cmd.refuse('E_NO_HOUSE', 'there is no such company');
  end if;
  if v_npc then
    perform cmd.refuse('E_NOT_IN_USE', 'a merchant keeps the flat rules and buys no room');
  end if;
  v_caps := public.fleet_room_caps(p_player);
  v_now := (v_caps ->> case v_kind when 'FLEET' then 'fleet_max' else 'fleet_ship_max' end)::int;
  v_top := public.wc_int(case v_kind when 'FLEET' then 'fleet_hard_max' else 'fleet_ship_top' end);
  if v_now >= v_top then
    perform cmd.refuse('E_ROOM_TOP', case v_kind when 'FLEET' then format('you keep room for %s fleets and %s is the most', v_now, v_top)
                                                 else format('a fleet of yours holds %s ships and %s is the most', v_now, v_top) end);
  end if;
  v_bought := coalesce((select h.steps from public.house_room h where h.player_id = p_player and h.kind = v_kind), 0);
  v_prices := public.wc(case v_kind when 'FLEET' then 'fleet_room_prices' else 'ship_room_prices' end);
  if v_bought >= jsonb_array_length(v_prices) then
    perform cmd.refuse('E_ROOM_BY_LEVEL', format('you have bought all %s steps that are sold; the next opens by level', v_bought));
  end if;
  v_price := (v_prices ->> v_bought)::bigint;
  if v_price is null or v_price <= 0 then
    raise exception 'buy_room_for: price % of % is not a positive figure', v_bought + 1, v_kind;
  end if;
  if v_have < v_price then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('This room costs %s 🪙 and you have %s 🪙.', v_price, v_have), cmd.figures(v_have, v_price, 'ducats'));
  end if;

  v_event := public.emit_event(p_player, 'ROOM_OPENED', jsonb_build_object('kind', v_kind, 'step', v_bought + 1, 'price', v_price, 'room', v_now + 1));
  v_after := public.credit(p_player, 'SLOT', -v_price, v_event);
  insert into public.house_room as h (player_id, kind, steps) values (p_player, v_kind, 1)
  on conflict (player_id, kind) do update set steps = h.steps + 1, updated_at = now();
  v_caps := public.fleet_room_caps(p_player);
  return jsonb_build_object('ok', true, 'kind', v_kind, 'step', v_bought + 1, 'price', v_price, 'purse', v_after,
                            'fleet_max', (v_caps ->> 'fleet_max')::int, 'fleet_ship_max', (v_caps ->> 'fleet_ship_max')::int);
end $$
  $f$;

  execute $f$
create function cmd.buy_room(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0354: the caller's company buys one step of room. The core is public.buy_room_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.buy_room_for(v_player, p_kind);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  -- ── 4. A FLEET TAKES A NEW NAME ──
  execute $f$
create function public.rename_fleet(p_player uuid, p_fleet uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0354: THE one way a fleet's name changes. Paper: no ship, gold or order moves, and she may be anywhere. The name's rules are the table's (fleets_name_check, fleets_player_name_unique): they judge,
-- and this says what they meant. The same name again changes nothing and writes nothing.
declare
  v_name text := btrim(coalesce(p_name, ''));
  f      public.fleets%rowtype;
begin
  select x.* into f from public.fleets x where x.id = p_fleet and x.player_id = p_player for update;
  if f.id is null then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours');
  end if;
  if v_name = f.name then
    return jsonb_build_object('ok', true, 'fleet_id', f.id, 'from', f.name, 'to', f.name, 'changed', false);
  end if;
  begin
    update public.fleets set name = v_name where id = f.id;
  exception
    when check_violation then
      perform cmd.refuse('E_BAD_NAME', 'a fleet is named in 3 to 24 letters');
    when unique_violation then
      perform cmd.refuse('E_NAME_TAKEN', format('you already keep a fleet called %s', v_name));
  end;
  perform public.emit_event(p_player, 'FLEET_RENAMED', jsonb_build_object('from', f.name, 'to', v_name));
  return jsonb_build_object('ok', true, 'fleet_id', f.id, 'from', f.name, 'to', v_name, 'changed', true);
end $$
  $f$;

  execute $f$
create function cmd.rename_fleet(p_fleet uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0354: the caller's company renames a fleet of hers. The core is public.rename_fleet.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.rename_fleet(v_player, p_fleet, p_name);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  revoke all on function public.fleet_totals(uuid, jsonb) from public, anon, authenticated;
  revoke all on function public.room_steps(jsonb, int, jsonb, jsonb, int, boolean, bigint) from public, anon, authenticated;
  revoke all on function public.buy_room_for(uuid, text) from public, anon, authenticated;
  revoke all on function public.rename_fleet(uuid, uuid, text) from public, anon, authenticated;
  revoke all on function world.house_room() from public, anon;
  grant execute on function world.house_room() to authenticated;
  revoke all on function cmd.buy_room(text) from public, anon;
  grant execute on function cmd.buy_room(text) to authenticated;
  revoke all on function cmd.rename_fleet(uuid, text) from public, anon;
  grant execute on function cmd.rename_fleet(uuid, text) to authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0354 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0354 values
  ('world.fleets()', 1,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id)   -- 0124: one ship, one builder
                 order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s
                where s.fleet_id = f.id),
$h$,
$h$    'ships', sv.ships,   -- 0354: built once, in the lateral below, so the totals are sums of these very reads
    'totals', public.fleet_totals(f.id, sv.ships),   -- 0354: what the fleet adds up to (docs/FLEETS_AND_SLOTS.md section 2.5)
$h$),
  ('world.fleets()', 2,
$h$    from public.fleets f where f.player_id = v_player);
$h$,
$h$    from public.fleets f
   cross join lateral (select coalesce(jsonb_agg(world.ship_view(s.id)   -- 0124: one ship, one builder
                 order by s.is_flagship desc, s.name), '[]'::jsonb) as ships
                 from public.ships s
                where s.fleet_id = f.id offset 0) sv   -- 0354: OFFSET 0 keeps it one evaluation a fleet
   where f.player_id = v_player);
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'ship_moves',            'uuid'),
$h$,
$h$      ('world',       'ship_moves',            'uuid'),
      -- 0354: the room a company has and how more opens; one step of room bought (dark until fleet_room_bite); a fleet renamed.
      ('world',       'house_room',            ''),
      ('cmd',         'buy_room',              'text'),
      ('cmd',         'rename_fleet',          'uuid, text'),
$h$);

  for v_h in select h.fn from hunks_0354 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0354 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0354 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0354 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0354 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0354 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0354 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0354 self-assert FAIL: a world_config row moved or was added: this file writes no knob';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0354 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> 'SLOT') <> v_words_before
     or not exists (select 1 from public.stats_flow_words w where w.kind = 'SLOT' and w.side = 'removed') then
    raise exception '0354 self-assert FAIL: another flow word moved, or SLOT is not a removed kind';
  end if;
  if public.fleet_room_on() then
    raise exception '0354 self-assert FAIL: the room is not dark';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute')
                 or (has_function_privilege('authenticated', f::regprocedure, 'execute') <> (f = any (c_doors)))) then
    raise exception '0354 self-assert FAIL: the grants are not the contract: only the read and the two doors, only to authenticated';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('house_room', 'buy_room', 'rename_fleet') and e.fn is not null) <> 3 then
    raise exception '0354 self-assert FAIL: the read or a door is not in the client registry';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0354 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(array['world.house_room()', 'public.fleet_totals(uuid,jsonb)', 'public.room_steps(jsonb,integer,jsonb,jsonb,integer,boolean,bigint)']) x))) <> 'sis' then
    raise exception '0354 self-assert FAIL: a read is not STABLE (or the pure rows not IMMUTABLE)';
  end if;

  -- ── 7. SELF-ASSERT: one probe of this file's own rows, rolled back by the sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Sala 0354', (select n.id from public.nations n where n.code = 'PRT'), 300000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa Vizinha 0354', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_other;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0354', (select n.id from public.nations n where n.code = 'PRT'), 300000, true) returning id into v_npc;
    v_f1 := public.form_fleet(v_pl, 'Sala Um 0354', v_lis);
    v_f2 := public.form_fleet(v_pl, 'Sala Dois 0354', v_lis);
    v_fo := public.form_fleet(v_other, 'Vizinha 0354', v_lis);
    perform public.commission_ship(v_pl, v_f1, 'barca', 'Um 0354', true, true);
    perform public.commission_ship(v_pl, v_f1, 'barca', 'Dois 0354', false, false);   -- laid down with no hands: she is short of crew
    perform public.commission_ship(v_pl, v_f2, 'barca', 'Tres 0354', true, true);
    create function pg_temp.fleets_old_0354() returns jsonb language plpgsql as 'begin return null; end';
    execute replace(replace(v_fleets_old, 'CREATE OR REPLACE FUNCTION world.fleets()', 'CREATE OR REPLACE FUNCTION pg_temp.fleets_old_0354()'), 'SECURITY DEFINER', '');
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_uid)::text, true);
    if public.current_player_id() is distinct from v_pl then
      raise exception '0354 self-assert FAIL: the probe is not signed in as its house';
    end if;

    -- (a) DARK: world.fleets() without the new key is its pre-image, to the byte
    v_old := pg_temp.fleets_old_0354();
    v_new := world.fleets();
    if jsonb_array_length(v_new) <> 2
       or (select jsonb_agg(e.value - 'totals' order by e.ord) from jsonb_array_elements(v_new) with ordinality e(value, ord)) is distinct from v_old
       or exists (select 1 from jsonb_array_elements(v_new) e where not (e ? 'totals')) then
      raise exception '0354 self-assert FAIL: dark, world.fleets() without `totals` is not its pre-image';
    end if;
    -- (b) THE TOTALS are the sums of the per-ship reads, taken here from the authorities themselves, not from the list
    for v_h in select f.id, e.value -> 'totals' as t
                 from public.fleets f join jsonb_array_elements(v_new) e on (e.value ->> 'id')::uuid = f.id where f.player_id = v_pl loop
      select jsonb_build_object(
               'ships', count(*)::int,
               'attack', coalesce(sum(world.ship_stat(s.id, 'attack')), 0),
               'hull', coalesce(sum(s.durability), 0),
               'hull_max', coalesce(sum((world.ship_view(s.id) ->> 'max_durability')::numeric), 0),
               'crew', coalesce(sum(s.crew), 0),
               'crew_required', coalesce(sum(c.crew_required), 0),
               'crew_max', coalesce(sum((world.ship_view(s.id) ->> 'crew_max')::numeric), 0),
               'short_crew', coalesce(jsonb_agg(s.name order by s.name) filter (where s.crew < c.crew_required), '[]'::jsonb),
               'wages_day', public.fleet_wage(v_h.id, false),
               'slowest', (select jsonb_build_object('id', y.id, 'name', y.name, 'speed', voyage.ship_speed(y.id))
                             from public.ships y where y.fleet_id = v_h.id order by voyage.ship_speed(y.id), y.name limit 1))
        into v_x
        from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_h.id;
      if v_h.t is distinct from v_x then
        raise exception '0354 self-assert FAIL: a fleet''s totals are not the sums of her ships: % against %', v_h.t, v_x;
      end if;
    end loop;
    if (select count(*) from jsonb_array_elements(v_new) e where e.value -> 'totals' -> 'short_crew' = '["Dois 0354"]'::jsonb) <> 1 then
      raise exception '0354 self-assert FAIL: the ship laid down with no hands is not named short of crew';
    end if;

    -- (c) DARK: the door refuses and takes nothing; the read says it is not lit; rows in house_room move no cap
    v_caps0 := public.earned_caps(v_pl);
    v_hull0 := public.house_ship_max(v_pl);
    v_r := cmd.buy_room('FLEET');
    if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (select p.ducats from public.players p where p.id = v_pl) <> 300000
       or exists (select 1 from public.house_room h where h.player_id = v_pl) or exists (select 1 from public.ledger l where l.player_id = v_pl) then
      raise exception '0354 self-assert FAIL: dark, the buying door is not shut: %', v_r;
    end if;
    v_r := world.house_room();
    if (v_r ->> 'on')::boolean or not (v_r ->> 'company')::boolean or (v_r -> 'fleets' ->> 'have')::int <> (v_caps0 ->> 'fleet_max')::int
       or (v_r -> 'ships' ->> 'have')::int <> (v_caps0 ->> 'fleet_ship_max')::int or (v_r -> 'fleets' ->> 'used')::int <> 2 or (v_r -> 'ships' ->> 'used')::int <> 2
       or (v_r -> 'hulls' ->> 'have')::int <> v_hull0 or (v_r -> 'hulls' ->> 'used')::int <> 3
       or jsonb_array_length(v_r -> 'fleets' -> 'steps') <> jsonb_array_length(public.wc('fleet_room_levels')) + jsonb_array_length(public.wc('fleet_room_prices')) then
      raise exception '0354 self-assert FAIL: dark, the room read is wrong: %', v_r;
    end if;
    insert into public.house_room (player_id, kind, steps) values (v_pl, 'FLEET', 2), (v_pl, 'SHIP', 3);
    if public.earned_caps(v_pl) is distinct from v_caps0 or public.house_ship_max(v_pl) <> v_hull0 then
      raise exception '0354 self-assert FAIL: dark, bought rows moved a cap';
    end if;
    delete from public.house_room where player_id = v_pl;

    -- (d) A NEW NAME, dark: accepted, trimmed, one event; and every refusal
    v_r := cmd.rename_fleet(v_f1, '  Nova Sala 0354 ');
    if not (v_r ->> 'ok')::boolean or (select f.name from public.fleets f where f.id = v_f1) <> 'Nova Sala 0354' or v_r ->> 'from' <> 'Sala Um 0354'
       or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'FLEET_RENAMED') <> 1 then
      raise exception '0354 self-assert FAIL: the fleet did not take her new name: %', v_r;
    end if;
    v_r := cmd.rename_fleet(v_f1, 'Nova Sala 0354');
    if not (v_r ->> 'ok')::boolean or (v_r ->> 'changed')::boolean or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'FLEET_RENAMED') <> 1 then
      raise exception '0354 self-assert FAIL: the same name again wrote something: %', v_r;
    end if;
    for v_h in select * from (values (v_f1, 'ab', 'E_BAD_NAME'), (v_f1, '   ', 'E_BAD_NAME'), (v_f1, repeat('x', 25), 'E_BAD_NAME'), (v_f1, null, 'E_BAD_NAME'),
                                     (v_f1, 'SALA DOIS 0354', 'E_NAME_TAKEN'), (v_fo, 'Roubada 0354', 'E_NO_SUCH_FLEET'), (null::uuid, 'Nenhuma 0354', 'E_NO_SUCH_FLEET')) t(fl, nm, want) loop
      v_r := cmd.rename_fleet(v_h.fl, v_h.nm);
      if v_r ->> 'error_code' is distinct from v_h.want then
        raise exception '0354 self-assert FAIL: renaming to "%" answered % and not %', v_h.nm, v_r, v_h.want;
      end if;
    end loop;
    if (select f.name from public.fleets f where f.id = v_f1) <> 'Nova Sala 0354' or (select f.name from public.fleets f where f.id = v_fo) <> 'Vizinha 0354' then
      raise exception '0354 self-assert FAIL: a refused rename left a mark';
    end if;

    -- (e) THE COST of the 30-second read, OLD against NEW, interleaved on the probe's two fleets, 40 pairs
    v_old := pg_temp.fleets_old_0354(); v_new := world.fleets();
    while v_pairs < 40 and clock_timestamp() - v_t0 < interval '8 seconds' loop
      v_t := clock_timestamp(); v_old := pg_temp.fleets_old_0354(); v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - v_t) * 1000;
      v_t := clock_timestamp(); v_new := world.fleets();            v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - v_t) * 1000;
      v_pairs := v_pairs + 1;
    end loop;

    -- (f) LIT, inside the probe only: a fleet step, two ship steps, short of gold, level only, the top
    update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
    v_caps0 := public.earned_caps(v_pl);
    v_r := world.house_room();
    if not (v_r ->> 'on')::boolean or (v_caps0 ->> 'fleet_max')::int <> 2 or (v_caps0 ->> 'fleet_ship_max')::int <> 2
       or (v_r -> 'fleets' ->> 'price')::bigint is distinct from (public.wc('fleet_room_prices') ->> 0)::bigint
       or (v_r -> 'ships' ->> 'price')::bigint is distinct from (public.wc('ship_room_prices') ->> 0)::bigint
       or (v_r -> 'fleets' ->> 'have')::int <> (v_r -> 'fleets' ->> 'ladder')::int then
      raise exception '0354 self-assert FAIL: lit, a new company does not read 2 fleets of 2 with the first prices: % %', v_caps0, v_r;
    end if;
    v_purse := 300000;
    for v_h in select * from (values ('FLEET', 'fleet_room_prices', 0, 'fleet_max', 3), ('ship', 'ship_room_prices', 0, 'fleet_ship_max', 3),
                                     (' Ship ', 'ship_room_prices', 1, 'fleet_ship_max', 4)) t(kind, knob, step, cap, want) loop
      v_r := cmd.buy_room(v_h.kind);
      v_purse := v_purse - (public.wc(v_h.knob) ->> v_h.step)::bigint;
      if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'price')::bigint <> (public.wc(v_h.knob) ->> v_h.step)::bigint or (v_r ->> 'purse')::bigint <> v_purse
         or (select p.ducats from public.players p where p.id = v_pl) <> v_purse
         or (public.earned_caps(v_pl) ->> v_h.cap)::int <> v_h.want
         or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'SLOT' and l.ducats_delta = -(public.wc(v_h.knob) ->> v_h.step)::bigint and l.balance_after = v_purse) <> 1
         or exists (select 1 from public.ledger l where l.player_id = v_pl and l.kind <> 'SLOT') then
        raise exception '0354 self-assert FAIL: lit, buying % step % did not cost the knob price, book SLOT and raise % to %: %', v_h.kind, v_h.step + 1, v_h.cap, v_h.want, v_r;
      end if;
    end loop;
    if public.house_ship_max(v_pl) <> 12 or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'ROOM_OPENED') <> 3
       or (select string_agg(h.kind || h.steps, ',' order by h.kind) from public.house_room h where h.player_id = v_pl) <> 'FLEET1,SHIP2' then
      raise exception '0354 self-assert FAIL: lit, three steps did not leave 3 fleets of 4, three events and the two rows';
    end if;
    -- short of gold: the second fleet price is above what is left, and the refusal carries both figures
    v_r := cmd.buy_room('FLEET');
    if v_r ->> 'error_code' is distinct from 'E_INSUFFICIENT_FUNDS' or (v_r -> 'figures' ->> 'have')::numeric <> v_purse
       or (v_r -> 'figures' ->> 'need')::numeric <> (public.wc('fleet_room_prices') ->> 1)::numeric
       or (select p.ducats from public.players p where p.id = v_pl) <> v_purse or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'ROOM_OPENED') <> 3
       or (select h.steps from public.house_room h where h.player_id = v_pl and h.kind = 'FLEET') <> 1 then
      raise exception '0354 self-assert FAIL: lit, short of gold is not refused whole with its figures: %', v_r;
    end if;
    -- every price used and room left: only a level opens more
    update public.house_room set steps = jsonb_array_length(public.wc('fleet_room_prices')) where player_id = v_pl and kind = 'FLEET';
    v_r := cmd.buy_room('FLEET');
    if (public.earned_caps(v_pl) ->> 'fleet_max')::int < public.wc_int('fleet_hard_max') and v_r ->> 'error_code' is distinct from 'E_ROOM_BY_LEVEL' then
      raise exception '0354 self-assert FAIL: lit, with every price used the door did not say by level: %', v_r;
    end if;
    -- the top, both kinds
    update public.house_room set steps = 9 where player_id = v_pl;
    if (public.earned_caps(v_pl) ->> 'fleet_max')::int <> public.wc_int('fleet_hard_max') or (public.earned_caps(v_pl) ->> 'fleet_ship_max')::int <> public.wc_int('fleet_ship_top')
       or cmd.buy_room('FLEET') ->> 'error_code' is distinct from 'E_ROOM_TOP' or cmd.buy_room('SHIP') ->> 'error_code' is distinct from 'E_ROOM_TOP'
       or cmd.buy_room('CABIN') ->> 'error_code' is distinct from 'E_PARSE'
       or (select p.ducats from public.players p where p.id = v_pl) <> v_purse then
      raise exception '0354 self-assert FAIL: lit, the top or an unknown kind is not refused, or a refusal took gold';
    end if;
    v_r := world.house_room();
    if not (v_r -> 'fleets' ->> 'full')::boolean or (v_r -> 'fleets' -> 'price') <> 'null'::jsonb or (v_r -> 'ships' -> 'price') <> 'null'::jsonb
       or exists (select 1 from jsonb_array_elements(v_r -> 'ships' -> 'steps') s where (s.value ->> 'next')::boolean) then
      raise exception '0354 self-assert FAIL: lit, at the top the read still offers a price: %', v_r;
    end if;
    -- a merchant buys nothing
    begin
      perform public.buy_room_for(v_npc, 'FLEET');
      raise exception '0354 self-assert FAIL: a merchant bought room';
    exception when others then
      if sqlerrm not like 'E_NOT_IN_USE%' then raise; end if;
    end;
    raise exception using errcode = 'ZX354', message = 'PROBE_ROLLBACK_0354';
  exception when sqlstate 'ZX354' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0354 self-assert FAIL: the probe did not run to its end';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0354' or p.auth_uid in (c_uid, c_uid2))
     or public.fleet_room_on() or exists (select 1 from public.house_room h where h.updated_at >= v_t0)
     or to_regprocedure('pg_temp.fleets_old_0354()') is not null
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0354 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0354 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  -- THE NEWS (0347's law): one UPDATE row, outside the probe, idempotent by its number. What is live at this deploy; buying room is dark and is not announced.
  perform public.news_update('0354', 'Fleet totals, rename', '선단 합계, 이름 변경');
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0354 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0354 cost: world.fleets() on a probe house of 2 fleets and 3 ships, OLD and NEW interleaved, % pairs: OLD % ms a read, NEW % ms a read.',
    v_pairs, case when v_pairs > 0 then round(v_old_ms / v_pairs, 3) end, case when v_pairs > 0 then round(v_new_ms / v_pairs, 3) end;
  raise notice '0354 self-assert ok: ROOM IS BOUGHT, AND A FLEET READS ITS TOTALS, dark. 7 functions (1 read and 2 doors for a client), 1 removed ledger kind, no knob; % hunks once each and reversing; no other function moved; the probe rolled back. % ms.',
    (select count(*) from hunks_0354), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0354;
end
$m$;
