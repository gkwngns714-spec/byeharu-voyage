-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0425 - A NEW SHIP IS NOT BARE  (starter gear: three cheap, plain pieces sold at every harbour, bought and fitted in one press)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15, verbatim: "and in port, there should be a beginner's gear for ships."
--   docs/dev-log/2026-11-15-starter-gear.md has the reasoning, the figures and what was decided by default.
--
-- WHAT A PLAYER GETS: at any harbour (all 254; no building needed, as fitting needs none: cmd.do_fit asks only that the fleet is
--   docked), the Gear face sells one piece for each rack a hull has a place in, at a low price paid to THAT city's purse:
--     Starter Guns      High   +30 attack, +8 reach;   -30 cargo space, -3 handling    3 deck, 4 hands   800 ducats
--     Starter Sails     Mid    +0.90 knots;            -4 handling                    2 deck, 2 hands   300 ducats
--     Starter Planking  Low    +5 armour, +80 hull;    -0.69 knots, -18 cargo space   2 deck, 0 hands   150 ducats
--   Each is its kind's grade-1 piece (Broadside Guns, Suit of Sails, Deal Planking) at HALF: every effect halved (buys and spends
--   alike), Deck and Hands halved and rounded up (scripts/build-gear.mjs STARTER, the one rule; figures above are the database's,
--   cargo space x hold_scale 3 and speed x speed_scale 3 as every item's). A whole set for a barca (guns + sails) is 1,100 ducats of
--   a new company's 40,000. Refit (permanent work on a hull) and Flourish (moves no stat) get none.
--
-- WHAT THIS FILE DOES:
--   1. THE THREE PIECES, as every item is written (scripts/build-gear.mjs --sql-0425, pasted): item_kinds, item_profile, item_effects
--      (x the two scales), item_recipes (half the G1's goods: what a repair is priced from), item_use (they WEAR like their G1: guns
--      in a fight, sails by the mile, planking in a storm), item_unmade (no workshop makes one: MAKE refuses, as for a Famous piece).
--   2. public.starter_gear (NEW, 3 rows): the pieces sold at the quay and their price. No foreign key on purpose (an FK would hold
--      SHARE ROW EXCLUSIVE on item_kinds, which every MAKE and FIT reads, to this file's commit); the codes are asserted instead.
--   3. public.buy_starter_for(player, fleet, ship, item) (NEW, server only): THE one way a starter piece is had. Her fleet docked at a
--      harbour; the piece goes STRAIGHT ONTO the ship through public.mount_fitting (the one core: rack, place, Deck, Hands, and the
--      new one-a-hull rule), then she pays the city: public.pay_city, kind GEAR (a 'moved' word: nothing minted, nothing burned). A
--      merchant is refused. cmd.buy_starter(fleet, ship, item) is its door (authenticated, one registry row).
--   4. world.starter_gear(fleet) (NEW, STABLE read, authenticated, one registry row): the pieces with their price and effects in the
--      server's words, her purse, whether the fleet is at a harbour, and for each ship of the fleet each piece's state:
--      fitted / open / full (every place of its rack is taken) / no_place (the hull has no place of that rack).
--   5. THREE HUNKS, each once and reversing:
--        public.mount_fitting        a hull carries ONE of each starter piece (E_STARTER_ONE). Every other item mounts as before.
--        world.workstation           a starter piece is not listed among what a workshop makes.
--        public.client_rpc_entry_points  the door and the read.
--   6. public.stats_flow_words GEAR ('moved', 'Starter gear').
--
-- RESALE CANNOT PROFIT: no door in the game turns an item into coin (items are fitted, used in a hull's recipe or spent on a
--   promotion). A starter piece is in no hull recipe and is no promotion item (asserted). UNFIT puts it in her store at that city like
--   any piece, for nothing; it can be FITTED again, one to a hull. A merchant cannot buy one, and no merchant loadout names one.
-- A NEW COMPANY STARTS AS BEFORE (decided by default): cmd.found_house is not cut. A founding gift would be a piece made from nothing
--   in a closed economy, and the founding body is the hottest door; one press in her first harbour fits a set for 1,100 of her 40,000.
-- LOAD: nothing in any beat or job. A buy is one player's press: a handful of rows (one unit, one event, one ledger row, one city flow).
--   The read is three small catalogue rows and her fleet's ships by key.
-- LOCKS: CREATE TABLE x1 (no FK), INSERTs into the item catalogue (ROW EXCLUSIVE; nothing live writes it), CREATE FUNCTION x3,
--   CREATE OR REPLACE x3 by hunks. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- SELF-ASSERT: the catalog (hunks once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved;
--   no other knob moved); the pieces against their G1s; then a probe company in a rolled-back sub-transaction buys and fits each piece,
--   pays the city, sees the stats move and the gear wear, is refused a second of a piece, a piece with no place, a short purse and
--   at sea; UNFIT returns a piece for nothing; a merchant is refused; another item still mounts twice. CI's proof 125 holds the same.
-- ROLLBACK (forward, owner only): scripts/ops/harness/starter-gear/rollback-0425.sql, a draft (the hunks reversed, the door, the read
--   and the table dropped; the catalogue rows stay while any is fitted).
-- VERSION: 0425 (production head 0421 on 2026-11-15; 0422-0424 are reserved for other builders and touch none of these bodies).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.mount_fitting(uuid,text)', 'world.workstation(uuid,uuid)', 'public.client_rpc_entry_points()'];
  c_new constant text[] := array['public.buy_starter_for(uuid,uuid,uuid,text)', 'cmd.buy_starter(uuid,uuid,text)', 'world.starter_gear(uuid)'];
  c_codes constant text[] := array['starter-guns', 'starter-sails', 'starter-planking'];
  c_uid constant uuid := '00000000-0425-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_tp        timestamptz;
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_pl        uuid;
  v_npc       uuid;
  v_fl        uuid;
  v_sh        uuid;
  v_nau       uuid;
  v_lis       uuid;
  v_voy       uuid;
  v_r         jsonb;
  v_a         numeric;
  v_b         numeric;
  v_c         numeric;
  v_d         numeric;
  v_purse     bigint;
  v_city      bigint;
  v_ms        numeric;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.starter_gear') is not null or to_regprocedure('public.buy_starter_for(uuid,uuid,uuid,text)') is not null
     or exists (select 1 from public.item_kinds k where k.code = any(c_codes))
     or exists (select 1 from public.stats_flow_words w where w.kind = 'GEAR') then
    raise exception '0425 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null)
     or to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null or to_regprocedure('public.fitting_lock(uuid)') is null
     or to_regprocedure('world.ship_slots(uuid)') is null or to_regprocedure('public.stat_words(text,numeric,boolean)') is null
     or to_regprocedure('public.wear_units_for(uuid,uuid)') is null or to_regprocedure('cmd.refused_envelope(text,text)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regclass('public.item_unmade') is null
     or to_regclass('public.item_use') is null
     or (select count(*) from public.item_profile ip
          where ip.grade = 1 and ip.meta = 0 and ip.base_type in ('Long Guns', 'Sails', 'Planking')
            and ip.item_code in ('broadside-guns', 'suit-of-sails', 'deal-planking')) <> 3 then
    raise exception '0425 refuses: a function it cuts or calls, or a grade-1 piece it halves, is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0425 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0425
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE THREE PIECES (scripts/build-gear.mjs --sql-0425; effects at design value, x the two scales here as every item's) ──
  insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
    ('starter-guns', 'Starter Guns', 'weapon', 'Attack, Reach', 'Hold, Handling', 'A few old iron guns from the quay: enough to answer a pirate, and no more.', 6, 1),
    ('starter-sails', 'Starter Sails', 'rig', 'Speed', 'Handling', 'A plain suit of second-hand canvas: a little more speed than bare yards.', 4, 1),
    ('starter-planking', 'Starter Planking', 'hull', 'Armour, Hull', 'Speed, Cargo space', 'Thin spruce planks nailed over the worst of the hull: a little stronger, a little slower.', 4, 1);
  insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
    ('starter-guns', 'Long Guns', 'high', 1, 0, 3, 4, true),
    ('starter-sails', 'Sails', 'mid', 1, 0, 2, 2, false),
    ('starter-planking', 'Planking', 'low', 1, 0, 2, 0, false);
  insert into public.item_effects (item_code, stat, delta)
  select x.code, x.stat,
         x.delta * case x.stat
                     when 'hold'  then coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'hold_scale'), 1)
                     when 'speed' then coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'speed_scale'), 1)
                     else 1 end
    from (values
      ('starter-guns', 'attack', 30),
      ('starter-guns', 'reach', 8),
      ('starter-guns', 'hold', -10),
      ('starter-guns', 'handling', -3),
      ('starter-sails', 'speed', 0.3),
      ('starter-sails', 'handling', -4),
      ('starter-planking', 'armour', 5),
      ('starter-planking', 'durability', 80),
      ('starter-planking', 'speed', -0.23),
      ('starter-planking', 'hold', -6)
    ) x(code, stat, delta);
  insert into public.item_recipes (item_code, good_id, qty)
  select x.code, g.id, x.qty
    from (values
      ('starter-guns', 'bar-iron', 3),
      ('starter-guns', 'timber', 1),
      ('starter-guns', 'ships-nails', 1),
      ('starter-sails', 'flax', 3),
      ('starter-sails', 'cordage', 1),
      ('starter-sails', 'tar', 1),
      ('starter-planking', 'norway-spruce', 6),
      ('starter-planking', 'ships-nails', 2),
      ('starter-planking', 'oakum', 1),
      ('starter-planking', 'pine-pitch', 1)
    ) x(code, good, qty)
    join public.goods g on g.code = x.good;
  insert into public.item_use (item_code, trigger, consumes) values
    ('starter-guns', 'PIRATES', '[{"good":"shot-and-ball","qty":1},{"good":"gunpowder","qty":1}]'),
    ('starter-planking', 'STORM', '[]'),
    ('starter-sails', 'MILES', '[]');
  insert into public.item_unmade (item_code) values
    ('starter-guns'),
    ('starter-sails'),
    ('starter-planking');

  -- retention: none, bounded by construction (one row a starter piece: three rows, written by migrations alone)
  create table public.starter_gear (
    item_code text primary key,
    price     bigint not null check (price > 0)
  );
  comment on table public.starter_gear is
    '0425: the starter pieces every harbour sells, and each one''s price in ducats (paid to the city, kind GEAR). One row a piece, authored in scripts/build-gear.mjs STARTER and held to it by the world guard. Read by public.buy_starter_for, world.starter_gear, public.mount_fitting (one a hull) and world.workstation (never listed as made). No FK to item_kinds on purpose (0425 header); every code is asserted.';
  alter table public.starter_gear enable row level security;
  revoke all on table public.starter_gear from public, anon, authenticated;
  insert into public.starter_gear (item_code, price) values
    ('starter-guns', 800),
    ('starter-sails', 300),
    ('starter-planking', 150);

  insert into public.stats_flow_words (kind, side, word, ord)
  values ('GEAR', 'moved', 'Starter gear', (select max(w.ord) + 1 from public.stats_flow_words w));

  -- ── 3. THE CORE AND ITS DOOR ──
  execute $f$
create function public.buy_starter_for(p_player uuid, p_fleet uuid, p_ship uuid, p_item text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0425 (the owner, 2026-11-15: "and in port, there should be a beginner's gear for ships"): THE one way a starter piece is had.
-- Her fleet docked at a harbour; the piece goes straight onto the ship through public.mount_fitting (the one core: rack, place,
-- Deck, Hands, one starter piece of a kind a hull); then she pays THAT city its price (public.pay_city, kind GEAR: money moved,
-- nothing minted). Refuses before anything moves; a refusal raised later rolls the whole press back. A merchant is refused.
declare
  f        public.fleets%rowtype;
  v_ship   public.ships%rowtype;
  v_price  bigint;
  v_name   text;
  v_npc    boolean;
  v_have   bigint;
  v_port   text;
  v_event  uuid;
  v_after  bigint;
begin
  select sg.price, k.name into v_price, v_name
    from public.starter_gear sg join public.item_kinds k on k.code = sg.item_code
   where sg.item_code = p_item;
  if v_price is null then
    perform cmd.refuse('E_NO_SUCH_ITEM', format('no starter piece is called "%s"', coalesce(p_item, '')));
  end if;
  select p.is_npc into v_npc from public.players p where p.id = p_player;
  if v_npc is null then
    perform cmd.refuse('E_NO_HOUSE', 'there is no such company');
  end if;
  if v_npc then
    perform cmd.refuse('E_NOT_IN_USE', 'a merchant fits her own gear and buys no starter piece');
  end if;
  select x.* into f from public.fleets x where x.id = p_fleet and x.player_id = p_player;
  if f.id is null then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours');
  end if;
  -- ONE HOUSE'S FITTINGS, ONE AT A TIME (public.fitting_lock, 0132): a double tap waits here, then is refused one-a-hull.
  perform public.fitting_lock(p_player);
  select p.name into v_port from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR';
  if f.status <> 'DOCKED' or v_port is null then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is not docked at a harbour, and starter gear is sold at the quay', f.name));
  end if;
  select s.* into v_ship from public.ships s where s.id = p_ship and s.fleet_id = f.id;
  if v_ship.id is null then
    perform cmd.refuse('E_NO_SUCH_SHIP', format('%s has no such ship', f.name));
  end if;
  select p.ducats into v_have from public.players p where p.id = p_player;
  if v_have < v_price then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('%s costs %s 🪙 and you have %s 🪙.', v_name, v_price, v_have),
                       cmd.figures(v_have, v_price, 'ducats'));
  end if;

  perform public.mount_fitting(v_ship.id, p_item);
  v_event := public.emit_event(p_player, 'FITTED', jsonb_build_object(
    'fleet', f.name, 'ship', v_ship.name, 'item', v_name, 'starter', true, 'price', v_price, 'port', v_port));
  v_after := public.pay_city(p_player, f.port_id, 'GEAR', v_price, v_event);

  return jsonb_build_object('ok', true, 'ship', v_ship.name, 'item', p_item, 'name', v_name, 'price', v_price, 'purse', v_after,
                            'port', v_port, 'hold', public.ship_hold_capacity(v_ship.id), 'speed', voyage.ship_speed(v_ship.id));
end
$body$
  $f$;
  revoke all on function public.buy_starter_for(uuid, uuid, uuid, text) from public, anon, authenticated;
  comment on function public.buy_starter_for(uuid, uuid, uuid, text) is
    '0425: THE one way a starter piece is had: bought at a harbour and fitted straight onto a ship of the fleet (public.mount_fitting), its price paid to that city (public.pay_city, kind GEAR). Server only; its door is cmd.buy_starter.';

  execute $f$
create function cmd.buy_starter(p_fleet uuid, p_ship uuid, p_item text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0425: the caller's company buys a starter piece and fits it on a ship of a fleet of hers. The core is public.buy_starter_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.buy_starter_for(v_player, p_fleet, p_ship, p_item);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;
  revoke all on function cmd.buy_starter(uuid, uuid, text) from public, anon;
  grant execute on function cmd.buy_starter(uuid, uuid, text) to authenticated;
  comment on function cmd.buy_starter(uuid, uuid, text) is
    '0425: the door of public.buy_starter_for for the signed-in company (a refusal is the envelope, as every cmd door).';

  -- ── 4. THE READ ──
  execute $f$
create function world.starter_gear(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0425: THE GEAR FACE. The starter pieces (public.starter_gear) with their rack, words, price and effects in the server's words
-- (public.stat_words); the caller's purse; whether the fleet (hers, or none) is docked at a harbour; and for each of its ships each
-- piece's state: fitted (she carries it), no_place (her hull has no place of its rack), full (every place of its rack is taken),
-- open. Deck and Hands are judged at the press (public.mount_fitting). Three catalogue rows and the fleet's ships by key.
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_port   text;
begin
  if p_fleet is not null and v_player is not null then
    select x.* into f from public.fleets x where x.id = p_fleet and x.player_id = v_player;
  end if;
  if f.id is not null and f.status = 'DOCKED' then
    select p.name into v_port from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR';
  end if;
  return jsonb_build_object(
    'purse', (select p.ducats from public.players p where p.id = v_player and not p.is_npc),
    'here', v_port is not null,
    'port', v_port,
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'code', k.code, 'name', k.name, 'rack', ip.rack, 'word', gr.word, 'buys', k.buys, 'spends', k.spends, 'note', k.note,
                'price', sg.price, 'deck', ip.deck, 'hands', ip.hands,
                'effects', (select coalesce(jsonb_agg(public.stat_words(e.stat, e.delta, false) order by e.delta < 0, e.stat), '[]'::jsonb)
                              from public.item_effects e where e.item_code = k.code))
                order by gr.ord, k.code), '[]'::jsonb)
                from public.starter_gear sg
                join public.item_kinds k on k.code = sg.item_code
                join public.item_profile ip on ip.item_code = sg.item_code
                join public.gear_racks gr on gr.code = ip.rack),
    'ships', case when f.id is null then '[]'::jsonb else (
              select coalesce(jsonb_agg(jsonb_build_object(
                       'id', s.id, 'name', s.name, 'class', c.name,
                       'pieces', (select jsonb_object_agg(sg.item_code,
                                    case when exists (select 1 from public.fitted_units u where u.ship_id = s.id and u.item_code = sg.item_code) then 'fitted'
                                         when coalesce((sl.v -> 'open' ->> ip.rack)::int, 0) < 1 then 'no_place'
                                         when (select count(*) from public.fitted_units u join public.item_profile up on up.item_code = u.item_code
                                                where u.ship_id = s.id and up.rack = ip.rack) >= (sl.v -> 'open' ->> ip.rack)::int then 'full'
                                         else 'open' end)
                                    from public.starter_gear sg join public.item_profile ip on ip.item_code = sg.item_code))
                       order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s
                join public.ship_classes c on c.id = s.class_id
               cross join lateral (select world.ship_slots(s.id) as v) sl
               where s.fleet_id = f.id) end);
end
$body$
  $f$;
  revoke all on function world.starter_gear(uuid) from public, anon;
  grant execute on function world.starter_gear(uuid) to authenticated;
  comment on function world.starter_gear(uuid) is
    '0425: the Gear face: the starter pieces, their price and effects, the purse, whether the fleet is at a harbour, and each ship''s state for each piece. A read.';

  -- ── 5. THE HUNKS ──
  create temp table hunk_0425 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0425 values
  (1, c_cut[1],
$h$  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$,
$h$  -- 0425: A STARTER PIECE IS ONE OF ITS KIND TO A HULL (public.starter_gear): a cheap piece cannot be stacked. Every other item as before.
  if exists (select 1 from public.starter_gear sg where sg.item_code = k.code)
     and exists (select 1 from public.fitted_units u where u.ship_id = v_ship.id and u.item_code = k.code) then
    perform cmd.refuse('E_STARTER_ONE', format('%s already carries %s; a ship takes one', v_ship.name, k.name));
  end if;

  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$),
  (2, c_cut[2],
$h$     where k.kind = 'fitting'));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made)
$h$,
$h$     where k.kind = 'fitting'
       and not exists (select 1 from public.starter_gear sg where sg.item_code = k.code)));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made); 0425: a starter piece is bought at the quay, never made
$h$),
  (3, c_cut[3],
$h$      ('world',       'stats_fleets',          ''),
$h$,
$h$      ('world',       'stats_fleets',          ''),
      -- 0425: the Gear face (the starter pieces) and its press: buy one and fit it.
      ('world',       'starter_gear',          'uuid'),
      ('cmd',         'buy_starter',           'uuid, uuid, text'),
$h$);
  for h in select * from hunk_0425 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0425 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0425 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0425 p where p.fn = h.fn) then
      raise exception '0425 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  for h in select p.fn, p.def from pre_0425 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0425 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0425 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0425 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0425 self-assert FAIL: a world_config row moved';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'starter_gear' and e.arg_types = 'uuid' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'cmd' and e.function_name = 'buy_starter' and e.arg_types = 'uuid, uuid, text' and e.fn is not null)
     or not has_function_privilege('authenticated', 'world.starter_gear(uuid)', 'execute') or has_function_privilege('anon', 'world.starter_gear(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.buy_starter(uuid,uuid,text)', 'execute') or has_function_privilege('anon', 'cmd.buy_starter(uuid,uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.buy_starter_for(uuid,uuid,uuid,text)', 'execute')
     or has_table_privilege('authenticated', 'public.starter_gear', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.starter_gear'::regclass)
     or (select p.provolatile from pg_proc p where p.oid = 'world.starter_gear(uuid)'::regprocedure) <> 's'
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0425 self-assert FAIL: the door and the read are not registered and granted to authenticated alone, or a client reaches the core or the table';
  end if;
  -- THE PIECES: every code whole in every catalogue table; one a rack; each effect of its G1's sign and at most 55 % of it; each
  -- price under half of what its G1's goods are worth; made nowhere; in no hull recipe and no promotion
  if (select count(*) from public.starter_gear sg
        join public.item_kinds k on k.code = sg.item_code and k.kind = 'fitting'
        join public.item_profile ip on ip.item_code = sg.item_code
        join public.item_use iu on iu.item_code = sg.item_code
        join public.item_unmade un on un.item_code = sg.item_code
       where public.item_recipe_value(sg.item_code) > 0 and public.made_only_in(sg.item_code, null) is not null) <> 3
     or (select count(distinct ip.rack) from public.starter_gear sg join public.item_profile ip on ip.item_code = sg.item_code) <> 3
     or exists (select 1 from public.hull_recipe_items hi where hi.item_code = any(c_codes))
     or exists (select 1 from public.promotion_items pi where pi.item_code = any(c_codes))
     or exists (select 1 from public.skill_requirements sr where sr.subject_kind = 'item' and sr.subject_code = any(c_codes)) then
    raise exception '0425 self-assert FAIL: a starter piece is not whole in the catalogue, or is made, a hull''s part or a promotion';
  end if;
  for v_z in select sg.item_code as code, sg.price, ip.base_type, ip.deck, ip.hands,
                    (select g.item_code from public.item_profile g
                      where g.base_type = ip.base_type and g.grade = 1 and g.meta = 0 and g.item_code <> all(c_codes)) as g1
               from public.starter_gear sg join public.item_profile ip on ip.item_code = sg.item_code loop
    if v_z.g1 is null
       or exists (select 1
                    from (select e.stat, e.delta from public.item_effects e where e.item_code = v_z.g1 and e.stat <> 'wave') g
                    full join (select e.stat, e.delta from public.item_effects e where e.item_code = v_z.code) s using (stat)
                   where s.delta is null or g.delta is null or sign(s.delta) <> sign(g.delta) or abs(s.delta) > abs(g.delta) * 0.55)
       or v_z.deck > (select g.deck from public.item_profile g where g.item_code = v_z.g1)
       or v_z.hands > (select g.hands from public.item_profile g where g.item_code = v_z.g1)
       or v_z.price * 2 >= public.item_recipe_value(v_z.g1) then
      raise exception '0425 self-assert FAIL: % is not clearly below its grade-1 piece % (effects, deck, hands or price)', v_z.code, v_z.g1;
    end if;
  end loop;

  -- ── 7. THE PROBE: a new company buys and fits, rolled back ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    -- the purses lit and the wear biting INSIDE the probe, whatever the world's switches say (rolled back with it)
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'gear_wear_bite') and value is distinct from 'true'::jsonb;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa Inicial 0425', (select n.id from public.nations n where n.code = 'PRT'), 2000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0425', (select n.id from public.nations n where n.code = 'PRT'), 5000, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Inicial', v_lis);
    v_sh := public.commission_ship(v_pl, v_fl, 'barca', 'Primeira', true, true);
    v_nau := public.commission_ship(v_pl, v_fl, 'nau', 'Grande', false, true);
    perform cmd.assume_identity(c_uid);

    -- (a) THE FACE: three pieces, prices as the table's, the barca has no Low place, everything else open
    v_tp := clock_timestamp();
    v_r := world.starter_gear(v_fl);
    v_ms := round(extract(epoch from clock_timestamp() - v_tp) * 1000, 1);
    if jsonb_array_length(v_r -> 'items') <> 3 or (v_r ->> 'here')::boolean is not true or (v_r ->> 'purse')::bigint <> 2000
       or (select sum((i ->> 'price')::bigint) from jsonb_array_elements(v_r -> 'items') i) <> (select sum(price) from public.starter_gear)
       or exists (select 1 from jsonb_array_elements(v_r -> 'items') i where jsonb_array_length(i -> 'effects') < 2)
       or (select s -> 'pieces' from jsonb_array_elements(v_r -> 'ships') s where s ->> 'name' = 'Primeira')
          <> '{"starter-guns": "open", "starter-sails": "open", "starter-planking": "no_place"}'::jsonb
       or (select s -> 'pieces' ->> 'starter-planking' from jsonb_array_elements(v_r -> 'ships') s where s ->> 'name' = 'Grande') <> 'open' then
      raise exception '0425 self-assert FAIL: the Gear face is not what the catalogue and the hulls say: %', v_r;
    end if;
    if (world.starter_gear(null) -> 'ships') <> '[]'::jsonb or (world.starter_gear(null) ->> 'here')::boolean then
      raise exception '0425 self-assert FAIL: the face with no fleet serves ships or a harbour';
    end if;

    -- (b) BUY AND FIT: the guns go on the barca, she pays 800, the city of Lisbon gets 800, attack and reach move by the piece
    v_a := world.ship_stat(v_sh, 'attack');
    v_b := world.ship_stat(v_sh, 'reach');
    v_city := coalesce((select sum(t.ducats) from public.treasury_flows t where t.player_id = v_pl and t.kind = 'GEAR'), 0);
    v_r := cmd.buy_starter(v_fl, v_sh, 'starter-guns');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'purse')::bigint <> 1200
       or (select p.ducats from public.players p where p.id = v_pl) <> 1200
       or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'GEAR' and l.ducats_delta = -800) <> 1
       or (select count(*) from public.treasury_flows t where t.player_id = v_pl and t.kind = 'GEAR' and t.port_id = v_lis and t.ducats = 800) <> 1
       or (select count(*) from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-guns') <> 1
       or world.ship_stat(v_sh, 'attack') - v_a <> (select e.delta from public.item_effects e where e.item_code = 'starter-guns' and e.stat = 'attack')
       or world.ship_stat(v_sh, 'reach') - v_b <> (select e.delta from public.item_effects e where e.item_code = 'starter-guns' and e.stat = 'reach') then
      raise exception '0425 self-assert FAIL: a buy did not fit the guns, take 800 and pay the city: % (attack % -> %)', v_r, v_a, world.ship_stat(v_sh, 'attack');
    end if;

    -- (c) THE REFUSALS, each moving nothing: a second gun with no free High place, a piece with no place, an unknown piece, no such
    --     ship, a short purse (a second of a piece where there IS room is (d)'s; at sea is (h)'s)
    v_r := jsonb_build_array(cmd.buy_starter(v_fl, v_sh, 'starter-guns') ->> 'error_code',
                             cmd.buy_starter(v_fl, v_sh, 'starter-planking') ->> 'error_code',
                             cmd.buy_starter(v_fl, v_sh, 'suit-of-sails') ->> 'error_code',
                             cmd.buy_starter(v_fl, gen_random_uuid(), 'starter-sails') ->> 'error_code');
    if v_r <> '["E_SLOTS_FULL", "E_NO_SLOT", "E_NO_SUCH_ITEM", "E_NO_SUCH_SHIP"]'::jsonb
       or (select p.ducats from public.players p where p.id = v_pl) <> 1200
       or (select count(*) from public.fitted_units u where u.ship_id in (v_sh, v_nau)) <> 1 then
      raise exception '0425 self-assert FAIL: a refused buy moved something, or was not refused with its code: %', v_r;
    end if;
    update public.players set ducats = 100 where id = v_pl;
    v_r := cmd.buy_starter(v_fl, v_nau, 'starter-planking');
    if v_r ->> 'error_code' <> 'E_INSUFFICIENT_FUNDS' or (select p.ducats from public.players p where p.id = v_pl) <> 100
       or exists (select 1 from public.fitted_units u where u.ship_id = v_nau) then
      raise exception '0425 self-assert FAIL: a short purse bought a piece: %', v_r;
    end if;
    update public.players set ducats = 1200 where id = v_pl;

    -- (d) THE OTHER PIECES: sails on the barca (speed by the piece), planking on the nau (armour by the piece); each pays its city
    v_a := world.ship_stat(v_sh, 'speed');
    v_b := world.ship_stat(v_nau, 'armour');
    -- (each press is its own statement: a condition's operands may be evaluated in any order, so no press sits inside one)
    v_r := jsonb_build_array(cmd.buy_starter(v_fl, v_sh, 'starter-sails') ->> 'ok');
    v_r := v_r || jsonb_build_array(cmd.buy_starter(v_fl, v_nau, 'starter-planking') ->> 'ok');
    v_r := v_r || jsonb_build_array(cmd.buy_starter(v_fl, v_nau, 'starter-sails') ->> 'ok');
    v_r := v_r || jsonb_build_array(cmd.buy_starter(v_fl, v_sh, 'starter-sails') ->> 'error_code');   -- the barca's second Mid place is free: one a hull refuses
    if v_r <> '["true", "true", "true", "E_STARTER_ONE"]'::jsonb
       or (select p.ducats from public.players p where p.id = v_pl) <> 1200 - 300 - 150 - 300
       or (select sum(t.ducats) from public.treasury_flows t where t.player_id = v_pl and t.kind = 'GEAR') - v_city <> 800 + 300 + 150 + 300
       or abs(world.ship_stat(v_sh, 'speed') - v_a - (select e.delta from public.item_effects e where e.item_code = 'starter-sails' and e.stat = 'speed')) > 0.001
       or world.ship_stat(v_nau, 'armour') - v_b <> (select e.delta from public.item_effects e where e.item_code = 'starter-planking' and e.stat = 'armour') then
      raise exception '0425 self-assert FAIL: the sails or the planking did not fit, pay or move their stat (presses %, purse %, speed % -> %, armour % -> %)',
        v_r, (select p.ducats from public.players p where p.id = v_pl), v_a, world.ship_stat(v_sh, 'speed'), v_b, world.ship_stat(v_nau, 'armour');
    end if;
    v_purse := (select p.ducats from public.players p where p.id = v_pl);

    -- (e) RESALE CANNOT PROFIT: UNFIT puts the sails in her store at Lisbon for nothing; FIT puts them back (one a hull still holds);
    --     a second bought while one waits in the store cannot be stacked through FIT
    v_r := cmd.do_unfit(v_fl, jsonb_build_object('item', 'starter-sails', 'ship', 'Primeira'));
    if (select p.ducats from public.players p where p.id = v_pl) <> v_purse
       or (select pi.qty from public.player_items pi where pi.player_id = v_pl and pi.port_id = v_lis and pi.item_code = 'starter-sails') <> 1 then
      raise exception '0425 self-assert FAIL: UNFIT of a starter piece moved her purse or did not store the piece';
    end if;
    v_r := cmd.buy_starter(v_fl, v_sh, 'starter-sails');
    v_purse := v_purse - 300;
    begin
      perform cmd.do_fit(v_fl, jsonb_build_object('item', 'starter-sails', 'ship', 'Primeira'));
      v_note := 'stacked';
    exception when others then
      v_note := split_part(sqlerrm, ':', 1);
    end;
    if v_note <> 'E_STARTER_ONE' or (v_r ->> 'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_pl) <> v_purse
       or (select count(*) from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-sails') <> 1 then
      raise exception '0425 self-assert FAIL: FIT stacked a second starter piece on a hull (%), or a buy after UNFIT did not fit', v_note;
    end if;

    -- (f) ANOTHER ITEM IS NOT TOUCHED BY THE RULE: two suits of sails go on one hull as before (the nau's Mid has room)
    perform public.mount_fitting(v_nau, 'suit-of-sails');
    perform public.mount_fitting(v_nau, 'suit-of-sails');
    if (select count(*) from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'suit-of-sails') <> 2 then
      raise exception '0425 self-assert FAIL: a grade-1 piece could not be mounted twice';
    end if;

    -- (g) IT WEARS like its G1: 2,000 miles wear the sails, two storm days the planking, no fight the guns
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl, '[]', 2000, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload) values (v_voy, 1, 'STORM', '{}'), (v_voy, 2, 'STORM', '{}');
    perform public.wear_units_for(v_fl, v_voy);
    v_c := (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-sails');
    v_d := (select u.wear from public.fitted_units u where u.ship_id = v_nau and u.item_code = 'starter-planking');
    if v_c <> round(2 * public.wc_num('gear_wear_per_1000nm'), 2) or v_d <> round(2 * public.wc_num('gear_wear_per_storm'), 2)
       or (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-guns') <> 0 then
      raise exception '0425 self-assert FAIL: the starter pieces did not wear as their kind: sails %, planking %', v_c, v_d;
    end if;

    -- (h) A MERCHANT IS REFUSED; AT SEA IS REFUSED; THE WORKSHOP LISTS NONE; MAKE IS REFUSED
    begin
      perform public.buy_starter_for(v_npc, v_fl, v_sh, 'starter-guns');
      v_note := 'sold';
    exception when others then
      v_note := split_part(sqlerrm, ':', 1);
    end;
    if v_note <> 'E_NOT_IN_USE' then
      raise exception '0425 self-assert FAIL: a merchant was not refused (%)', v_note;
    end if;
    if exists (select 1 from jsonb_array_elements(world.workstation(v_lis, v_fl) -> 'items') i where i ->> 'code' = any(c_codes))
       or public.made_only_in('starter-sails', v_lis) is null then
      raise exception '0425 self-assert FAIL: a workshop lists or makes a starter piece';
    end if;
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.5 where id = v_fl;
    if cmd.buy_starter(v_fl, v_nau, 'starter-guns') ->> 'error_code' <> 'E_NOT_DOCKED' or (world.starter_gear(v_fl) ->> 'here')::boolean then
      raise exception '0425 self-assert FAIL: a fleet at sea was sold a piece, or the face says she is at a harbour';
    end if;
    v_note := format('the face read in %s ms; five buys (the three pieces, sails twice) fitted for %s ducats paid to Lisbon; refusals E_STARTER_ONE, E_SLOTS_FULL, E_NO_SLOT, E_NO_SUCH_ITEM, E_NO_SUCH_SHIP, E_INSUFFICIENT_FUNDS, E_NOT_DOCKED, E_NOT_IN_USE; sails wore %s by the mile, planking %s by the storm',
                     v_ms, 800 + 300 + 150 + 300 + 300, v_c, v_d);
    raise exception using errcode = 'ZX425', message = 'PROBE_ROLLBACK_0425';
  exception when sqlstate 'ZX425' then
    v_lived := true;
  end;
  if not v_lived or v_note not like 'the face%' then
    raise exception '0425 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0425' or p.auth_uid = c_uid)
     or exists (select 1 from public.fitted_units u where u.item_code = any(c_codes))
     or public.current_player_id() is not null then
    raise exception '0425 self-assert FAIL: the probe left something behind';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law)
  perform public.news_update('0425', 'Starter gear at every harbour', '모든 항구에서 초보 장비 판매');
  if (select count(*) from public.world_news w where w.key = 'update:0425') <> 1 then
    raise exception '0425 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0425 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0425 self-assert ok: A NEW SHIP IS NOT BARE. Three starter pieces (guns, sails, planking: one a rack, every effect half its grade-1 piece''s, each under half its goods'' worth, made nowhere, in no hull recipe), public.starter_gear, a core and its door, a read; three hunks over three bodies, each once and reversing; grants, volatility, definer and search path unmoved; no other function and no knob moved. Probe (rolled back): %. In all % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
