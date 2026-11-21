-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0465 - THE YARD TAKES AN ORDER  (slice C of docs/design/content-plan-2026-11.md: 5.3 item 3, 5.4 row C, 3.4, 3.5. DARK.)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- docs/dev-log/2026-11-22-yard-order.md has what was measured and every "decided by default".
--
-- WHY. The second ship is an 85-minute errand that is easy to get wrong (3.4), and coin buys nothing a company needs (3.5: "A ship:
--   not for sale"). The owner, 2026-11-22: "make this game a proper game", which settles the plan's open decision (5.6: a ship for
--   coin and time, at half again the price and with a real wait; the materials stay cheaper and instant).
--
-- WHAT SAYS THE OPPOSITE, NAMED. docs/SECOND_SHIP.md (d) "a used hull for coin: no, makes the yard a shop". This is not a shelf:
--   the yard BUILDS the hull, in real time, for the whole price and a fee; the materials route (cmd.do_build, 0072) is untouched and
--   stays the thrifty, instant way. Merchants already get hulls with no materials (public.commission_ship), so no rule of the world
--   breaks.
--
-- WHAT THIS FILE MAKES
--   THE SWITCH     world_config yard_order_enabled (FALSE here). While false nothing a player sees moves: world.building_yard serves
--                  exactly what it served (the new key `order` is added only while lit), world.hull_quote answers {on: false}, and
--                  cmd.order_hull refuses E_NOT_IN_USE before it writes. Lighting it is the owner's; false again is the rollback
--                  (an order already paid still launches: cmd.launch_hull is not behind the switch).
--   TWO KNOBS      yard_order_fee_pct (50: the fee on labour + materials) and yard_order_minutes_per_hour (1.25: the wait is
--                  ship_classes.build_hours x this, so a Barca's 24 h is 30 real minutes and the biggest hulls' 360 h is 7.5 hours).
--   THE TABLE      public.hull_orders: an order a company keeps at a yard (at most one open a yard: a partial unique index).
--   THE PRICE      public.hull_order_price(player, port, class): the yard's labour (public.yard_labour, the one reading) + every good
--                  the hull and her parts take at what the nearest seller asks now (world.yard_sources, the sheet's own sellers and
--                  prices: the "Total" the sheet prints, counted whole) + the fee. The wait from build_hours. One reading: the quote,
--                  the door and the self-assert all call it.
--   THE DOORS      cmd.order_hull(port, class): the gates cmd.do_build applies (the yard's tier, the country, the skills, a part no
--                  workshop makes, one famous ship to a house; each the same function do_build calls), one open order a yard, the
--                  purse; then the whole price is paid to that city (public.pay_city, kind BUILD) and the order stands until its
--                  ready_at. cmd.launch_hull(fleet, name): a fleet of yours DOCKED at that yard takes the hull once it is ready,
--                  named as cmd.do_build names one, through the one ship insert (public.commission_ship: empty and uncrewed, the
--                  ship cap's trigger bites there), with do_build's Reputation and Shipbuilding. Cores public.hull_order_for and
--                  public.hull_launch_for (server only); a refusal is the envelope, as every cmd door's.
--   THE READS      world.building_yard gains `order` while lit: {on, fee_pct, open (this yard: class, price, ordered_at, ready_at,
--                  ready), elsewhere (your open orders at other yards)} (public.hull_order_card). world.hull_quote(port, class): the
--                  price and the wait for this company, or {on: false} dark.
--   CUT            Cancel (two doors, as the plan says: an order is paid and built). "The planned trip stops sailing past its
--                  materials" (5.3): not in this file (the dev-log says why).
-- NO COIN IS MADE. The order's price leaves the company's purse into that city's treasury (pay_city), as a hull's labour does.
-- budget: no job, no cron, no trigger; 0 rows a minute while nobody presses (0 while dark: the order door refuses before it writes).
--   Lit: an order writes 1 hull_orders row + 1 event + 2 ledger/treasury rows; a launch 1 ship + 1 event + 1 order update (+ the
--   Reputation and level rows cmd.do_build writes for a hull).
-- retention: public.hull_orders keeps a launched order 7 days: the company's next order deletes its own launched rows older than
--   that (public.hull_order_for). Bounded by one open order a company a yard, so at most a few rows a company.
-- LOCKS: CREATE TABLE (new), CREATE FUNCTION x7, CREATE OR REPLACE x2 by hunks (world.building_yard, public.client_rpc_entry_points).
-- news: none (dark; the News is told when the owner lights it)
-- SELF-ASSERT: hunks once and reversing, metadata unmoved, no other function moved, no knob moved but the three new ones (the switch
--   false); the cores server only (service_role too), the doors and the quote authenticated only; the table not reachable by a
--   client and under RLS; then probes, rolled back: (a) dark, a new Lisbon company's yard read is the same text as before the hunk,
--   the quote is {on: false}, the order door refuses E_NOT_IN_USE and writes nothing; (b) lit: the Barca's price is labour +
--   materials + half again, her wait 30 minutes; ordered, the purse pays exactly that to Lisbon; a second order there is refused; the
--   launch before ready refuses E_NOT_READY; at ready it puts her in the fleet, uncrewed, the order closed. Proof 168 holds the rest.
-- ROLLBACK: yard_order_enabled false (the knob; nothing to undo). An order paid before keeps its row and still launches.
-- VERSION: 0465 (production head 0462 on 2026-11-22; 0463 and 0464 are ahead of it in the queue and touch nothing here).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['world.building_yard(uuid)', 'public.client_rpc_entry_points()'];
  c_new constant text[] := array[
    'public.hull_order_price(uuid,uuid,text)', 'public.hull_order_card(uuid,uuid)',
    'public.hull_order_for(uuid,uuid,text,timestamp with time zone)', 'public.hull_launch_for(uuid,uuid,text,timestamp with time zone)',
    'world.hull_quote(uuid,text)', 'cmd.order_hull(uuid,text)', 'cmd.launch_hull(uuid,text)'];
  c_knobs constant text[] := array['yard_order_enabled', 'yard_order_fee_pct', 'yard_order_minutes_per_hour'];
  c_uid  constant uuid := '00000000-0465-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_pl        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_r         jsonb;
  v_q         jsonb;
  v_purse     bigint;
  v_order     uuid;
  v_ready     timestamptz;
  v_pre_yard  jsonb;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.hull_orders') is not null
     or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null)
     or exists (select 1 from public.world_config c where c.key = any(c_knobs)) then
    raise exception '0465 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null)
     or to_regprocedure('world.yard_sources(uuid,text)') is null or to_regprocedure('public.yard_labour(uuid,text)') is null
     or to_regprocedure('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)') is null
     or to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null or to_regprocedure('public.hull_unmade(text)') is null
     or to_regprocedure('public.yard_wrong_country(uuid,text)') is null or to_regprocedure('public.requirements_met(uuid,text,text)') is null
     or to_regprocedure('public.requirements_refusal(uuid,text,text)') is null or to_regprocedure('public.famous_held(uuid,text)') is null
     or to_regprocedure('public.reputation_built(uuid,uuid,jsonb)') is null or to_regprocedure('public.level_grant(uuid,text,numeric,text)') is null
     or to_regprocedure('cmd.refused_envelope(text,text)') is null or to_regprocedure('cmd.figures(numeric,numeric,text)') is null
     or not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'ship_classes' and c.column_name = 'build_hours') then
    raise exception '0465 refuses: the yard of 0072, 0349 and 0358 is not in this world as this file was written against';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0465 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0465
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

  -- (a, before) what a new Lisbon company's yard read says BEFORE anything here moves; rolled back, only the value is kept
  begin
    v_pl := public.new_house(c_uid, 'Estaleiro 0465', 'PRT');
    perform cmd.assume_identity(c_uid);
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pre_yard := world.building_yard(v_lis);
    raise exception using errcode = 'ZX465', message = 'PRE_ROLLBACK_0465';
  exception when sqlstate 'ZX465' then
    null;
  end;
  if v_pre_yard is null or jsonb_array_length(v_pre_yard -> 'hulls') < 3 or public.current_player_id() is not null then
    raise exception '0465 self-assert FAIL: the reading before the hunk did not run: %', left(v_pre_yard::text, 200);
  end if;

  -- ── 2. THE DATA ──
  insert into public.world_config (key, value, description) values
    ('yard_order_enabled', 'false'::jsonb, '0465: THE YARD TAKES AN ORDER (content plan slice C). False: world.building_yard serves no `order`, world.hull_quote answers {on: false} and cmd.order_hull refuses E_NOT_IN_USE; nothing a player sees moves. The owner lights it; false again is the rollback (an order already paid still launches).'),
    ('yard_order_fee_pct', '50'::jsonb, '0465: the yard''s fee on an order, per cent of its labour + materials (public.hull_order_price). The plan''s default: half again.'),
    ('yard_order_minutes_per_hour', '1.25'::jsonb, '0465: an order''s wait in real minutes for each ship_classes.build_hours (public.hull_order_price): a Barca''s 24 h is 30 minutes, the biggest hulls'' 360 h 7.5 hours.');

  -- retention: a launched order is deleted 7 days on by the company's next order (public.hull_order_for); none open beyond one a yard
  create table public.hull_orders (
    id          uuid primary key default gen_random_uuid(),
    player_id   uuid not null references public.players(id) on delete cascade,
    port_id     uuid not null references public.ports(id),
    class_code  text not null references public.hull_recipes(class_code),
    labour      bigint not null check (labour >= 0),
    materials   bigint not null check (materials >= 0),
    fee         bigint not null check (fee >= 0),
    price       bigint not null check (price > 0 and price = labour + materials + fee),
    ordered_at  timestamptz not null,
    ready_at    timestamptz not null check (ready_at >= ordered_at),
    launched_at timestamptz,
    ship_id     uuid,
    check ((launched_at is null) = (ship_id is null))
  );
  create unique index hull_orders_one_open on public.hull_orders (player_id, port_id) where launched_at is null;
  create index hull_orders_player on public.hull_orders (player_id);
  comment on table public.hull_orders is '0465: a hull a company ordered at a yard for coin (cmd.order_hull): paid whole when ordered, ready at ready_at, launched into a fleet docked there (cmd.launch_hull). At most one open a company a yard. Retention: a launched row goes 7 days on, at the company''s next order.';
  alter table public.hull_orders enable row level security;
  revoke all on table public.hull_orders from public, anon, authenticated;

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.hull_order_price(p_player uuid, p_port uuid, p_class text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0465: THE ONE READING of what an order of a hull costs a company at a yard, and how long she takes. Labour: public.yard_labour (the
-- one reading of the yard's work). Materials: every good the hull and her parts take, at what the nearest seller asks now
-- (world.yard_sources: the sheet's own sellers and prices), counted whole. Fee: yard_order_fee_pct of the two. Minutes:
-- ship_classes.build_hours x yard_order_minutes_per_hour. `short`: the goods no harbour sells (then there is no price). Null for a
-- class no yard builds.
declare
  v_lab   bigint := public.yard_labour(p_player, p_class);
  v_src   jsonb;
  v_mat   numeric;
  v_short text;
  v_fee   bigint;
  v_min   int;
begin
  if v_lab is null then
    return null;
  end if;
  v_src := world.yard_sources(p_port, p_class);
  select sum((x.e ->> 'qty')::numeric * (x.e ->> 'ask')::numeric),
         string_agg(case when x.e ->> 'ask' is null then g.name end, ', ' order by g.name)
    into v_mat, v_short
    from (select e from jsonb_array_elements(v_src -> 'goods') e
          union all
          select i from jsonb_array_elements(v_src -> 'items') it cross join lateral jsonb_array_elements(it -> 'inputs') i) x
    left join public.goods g on g.code = x.e ->> 'code';
  v_mat := ceil(coalesce(v_mat, 0));
  v_fee := round((v_lab + v_mat) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint;
  select round(c.build_hours * public.wc_num('yard_order_minutes_per_hour'))::int into v_min from public.ship_classes c where c.code = p_class;
  return jsonb_build_object('class', p_class, 'labour', v_lab, 'materials', v_mat::bigint, 'fee', v_fee,
                            'price', v_lab + v_mat::bigint + v_fee, 'minutes', greatest(coalesce(v_min, 0), 1), 'short', v_short);
end
$body$
  $f$;

  execute $f$
create function public.hull_order_card(p_player uuid, p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0465: what world.building_yard adds while the yard takes orders: {order: {on, fee_pct, open, elsewhere}}. `open`: this company's
-- order at THIS yard (null: none), with `ready` read at now(). `elsewhere`: its open orders at other yards. Dark: {} (the read is as
-- it was). Server only.
begin
  if public.wc('yard_order_enabled') is distinct from 'true'::jsonb then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('order', jsonb_build_object(
    'on', true,
    'fee_pct', public.wc_num('yard_order_fee_pct'),
    'open', (select jsonb_build_object('id', o.id, 'class', o.class_code, 'name', c.name, 'price', o.price,
                                       'ordered_at', o.ordered_at, 'ready_at', o.ready_at, 'ready', o.ready_at <= now())
               from public.hull_orders o join public.ship_classes c on c.code = o.class_code
              where o.player_id = p_player and o.port_id = p_port and o.launched_at is null),
    'elsewhere', (select coalesce(jsonb_agg(jsonb_build_object('port', p.code, 'port_name', p.name, 'class', o.class_code, 'name', c.name,
                                                               'ready_at', o.ready_at, 'ready', o.ready_at <= now()) order by o.ready_at), '[]'::jsonb)
                    from public.hull_orders o join public.ship_classes c on c.code = o.class_code join public.ports p on p.id = o.port_id
                   where o.player_id = p_player and o.port_id <> p_port and o.launched_at is null)));
end
$body$
  $f$;

  execute $f$
create function public.hull_order_for(p_player uuid, p_port uuid, p_class text, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0465: THE ONE WAY a hull is ordered for coin. The gates are cmd.do_build's, each the same function it calls; then one open order a
-- yard, a price for every good, the purse; then the whole price is paid to this city (public.pay_city, kind BUILD) and the order
-- stands until ready_at. Refuses before anything moves. Server only: cmd.order_hull is its door.
declare
  c       public.ship_classes%rowtype;
  h       public.hull_recipes%rowtype;
  v_npc   boolean;
  v_tier  int;
  v_wrong text;
  v_q     jsonb;
  v_purse bigint;
  v_id    uuid;
  v_after bigint;
begin
  if public.wc('yard_order_enabled') is distinct from 'true'::jsonb then
    perform cmd.refuse('E_NOT_IN_USE', 'the yard takes no orders yet', null);
  end if;
  select p.is_npc into v_npc from public.players p where p.id = p_player for update;   -- one company's orders one at a time
  if v_npc is null then
    perform cmd.refuse('E_NO_HOUSE', 'there is no such company', null);
  end if;
  if v_npc then
    perform cmd.refuse('E_NOT_IN_USE', 'a merchant orders no hull', null);
  end if;
  select * into c from public.ship_classes where code = p_class;
  select * into h from public.hull_recipes where class_code = p_class;
  if c.code is null or h.class_code is null then
    perform cmd.refuse('E_NOT_BUILDABLE', format('no yard lays down a hull called "%s"', coalesce(p_class, '')), null);
  end if;
  if public.hull_unmade(c.code) is not null then
    perform cmd.refuse('E_NOT_BUILDABLE', public.hull_unmade(c.code), null);
  end if;
  select b.tier into v_tier from public.port_buildings b where b.port_id = p_port and b.kind = 'building_yard';
  if v_tier is null then
    perform cmd.refuse('E_NO_BUILDING_YARD', 'this city lays down no hulls', null);
  end if;
  if v_tier < h.yard_tier then
    perform cmd.refuse('E_YARD_TOO_SMALL', format('a %s wants a tier %s yard and this one is tier %s', c.name, h.yard_tier, v_tier), null);
  end if;
  v_wrong := public.yard_wrong_country(p_port, c.code);
  if v_wrong is not null then
    perform cmd.refuse('E_WRONG_YARD', v_wrong, null);
  end if;
  if not public.requirements_met(p_player, 'hull', c.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(p_player, 'hull', c.code), null);
  end if;
  -- one famous ship to a house: one kept, or one on order anywhere
  if exists (select 1 from public.class_profile cp where cp.class_code = c.code and cp.tech = 'F') then
    if public.famous_held(p_player, c.code) is not null then
      perform cmd.refuse('E_FAMOUS_HELD', public.famous_held(p_player, c.code), null);
    end if;
    if exists (select 1 from public.hull_orders o where o.player_id = p_player and o.class_code = c.code and o.launched_at is null) then
      perform cmd.refuse('E_FAMOUS_HELD', format('%s is a famous ship, and yours is already on order', c.name), null);
    end if;
  end if;
  if exists (select 1 from public.hull_orders o where o.player_id = p_player and o.port_id = p_port and o.launched_at is null) then
    perform cmd.refuse('E_YARD_BUSY', 'this yard is already building a hull for you; launch her first', null);
  end if;
  v_q := public.hull_order_price(p_player, p_port, c.code);
  if v_q ->> 'short' is not null then
    perform cmd.refuse('E_NOT_BUILDABLE', format('no harbour sells %s, so the yard cannot price her', v_q ->> 'short'), null);
  end if;
  select p.ducats into v_purse from public.players p where p.id = p_player;
  if v_purse < (v_q ->> 'price')::bigint then
    perform cmd.refuse('E_NO_FUNDS', format('the yard asks %s for the %s and you hold %s', v_q ->> 'price', c.name, v_purse),
                       cmd.figures(v_purse, (v_q ->> 'price')::numeric, 'ducats'));
  end if;

  -- retention: this company's launched orders older than 7 days go now
  delete from public.hull_orders o where o.player_id = p_player and o.launched_at < p_at - interval '7 days';
  insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
  values (p_player, p_port, c.code, (v_q ->> 'labour')::bigint, (v_q ->> 'materials')::bigint, (v_q ->> 'fee')::bigint, (v_q ->> 'price')::bigint,
          p_at, p_at + make_interval(mins => (v_q ->> 'minutes')::int))
  returning id into v_id;
  v_after := public.pay_city(p_player, p_port, 'BUILD', (v_q ->> 'price')::bigint,
    public.emit_event(p_player, 'HULL_ORDERED', jsonb_build_object('order', v_id, 'class', c.name, 'ducats', (v_q ->> 'price')::bigint,
                                                                  'minutes', (v_q ->> 'minutes')::int)));
  return jsonb_build_object('ok', true, 'order', v_id, 'class', c.code, 'name', c.name, 'price', (v_q ->> 'price')::bigint,
                            'minutes', (v_q ->> 'minutes')::int, 'ready_at', p_at + make_interval(mins => (v_q ->> 'minutes')::int), 'purse', v_after);
end
$body$
  $f$;

  execute $f$
create function public.hull_launch_for(p_player uuid, p_fleet uuid, p_name text, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0465: THE ONE WAY an ordered hull is launched: a fleet of the company DOCKED at the yard takes her once ready_at has passed, named as
-- cmd.do_build names a hull, through the one ship insert (public.commission_ship: empty and uncrewed; the ship cap's trigger bites
-- there), with do_build's Reputation and Shipbuilding. Not behind the switch: an order paid launches. Server only.
declare
  f      public.fleets%rowtype;
  o      public.hull_orders%rowtype;
  c      public.ship_classes%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_ship uuid;
begin
  select x.* into f from public.fleets x where x.id = p_fleet and x.player_id = p_player;
  if f.id is null then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours', null);
  end if;
  if f.status <> 'DOCKED' or f.port_id is null then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is not in harbour, and a hull is launched to a fleet lying at the yard', f.name), null);
  end if;
  select x.* into o from public.hull_orders x where x.player_id = p_player and x.port_id = f.port_id and x.launched_at is null for update;
  if o.id is null then
    perform cmd.refuse('E_NO_ORDER', 'the yard here is building nothing for you', null);
  end if;
  select * into c from public.ship_classes where code = o.class_code;
  if p_at < o.ready_at then
    perform cmd.refuse('E_NOT_READY', format('the %s is ready in %s min', c.name, ceil(extract(epoch from o.ready_at - p_at) / 60)), null);
  end if;
  if exists (select 1 from public.class_profile cp where cp.class_code = c.code and cp.tech = 'F') and public.famous_held(p_player, c.code) is not null then
    perform cmd.refuse('E_FAMOUS_HELD', public.famous_held(p_player, c.code), null);
  end if;
  if length(v_name) < 3 or length(v_name) > 24 then
    perform cmd.refuse('E_PARSE', 'a ship is named in 3 to 24 letters', null);
  end if;
  if exists (select 1 from public.ships s where s.player_id = p_player and lower(s.name) = lower(v_name)) then
    perform cmd.refuse('E_NAME_TAKEN', format('you already keep a ship called %s', v_name), null);
  end if;
  v_ship := public.commission_ship(p_player, p_fleet, c.code, v_name, false, false);
  perform public.reputation_built(p_player, v_ship, jsonb_build_object('class', c.code));
  perform public.level_grant(p_player, 'hull', 1, 'hull:' || v_ship);
  update public.hull_orders set launched_at = p_at, ship_id = v_ship where id = o.id;
  perform public.emit_event(p_player, 'HULL_LAUNCHED', jsonb_build_object('order', o.id, 'fleet', f.name, 'ship', v_name, 'class', c.name));
  return jsonb_build_object('ok', true, 'ship', v_ship, 'name', v_name, 'class', c.code, 'fleet', f.name);
end
$body$
  $f$;

  execute $f$
create function world.hull_quote(p_port uuid, p_class text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0465: what an order of this hull at this yard costs the caller now, and how long she takes (public.hull_order_price, the one
-- reading): {on, class, labour, materials, fee, price, minutes, short}. Dark: {on: false}. Whether the yard takes the order is the
-- door's to say.
declare
  v_q jsonb;
begin
  if public.wc('yard_order_enabled') is distinct from 'true'::jsonb then
    return '{"on": false}'::jsonb;
  end if;
  v_q := public.hull_order_price(public.current_player_id(), p_port, p_class);
  return jsonb_build_object('on', true) || coalesce(v_q, jsonb_build_object('class', p_class, 'price', null));
end
$body$
  $f$;

  execute $f$
create function cmd.order_hull(p_port uuid, p_class text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0465: order a hull at a yard for coin (public.hull_order_for). A refusal is the envelope.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.hull_order_for(v_player, p_port, p_class, now());
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  execute $f$
create function cmd.launch_hull(p_fleet uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0465: launch the hull the yard here built for you into this fleet (public.hull_launch_for). A refusal is the envelope.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.hull_launch_for(v_player, p_fleet, p_name, now());
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  -- grants: the two doors and the quote to authenticated alone; the cores and readings server only (service_role too: the platform
  -- grants it execute on a new public function by default, 0459's first push)
  foreach v_def in array c_new loop
    if v_def like 'cmd.%' or v_def like 'world.%' then
      execute format('revoke all on function %s from public, anon', v_def::regprocedure);
      execute format('grant execute on function %s to authenticated', v_def::regprocedure);
    else
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
    end if;
  end loop;

  -- ── 4. THE HUNKS ──
  create temp table hunk_0465 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0465 values
  -- world.building_yard: the order's card, served only while the yard takes orders (dark it is {} and the read is as it was)
  (1, c_cut[1],
$h$public.hull_unmade(c.code) as unmade) yw));$h$,
$h$public.hull_unmade(c.code) as unmade) yw)) || public.hull_order_card(v_player, p_port);$h$),
  -- public.client_rpc_entry_points: the quote and the two doors
  (2, c_cut[2],
$h$      ('world',       'crew_cost',           'uuid, int'),
$h$,
$h$      ('world',       'crew_cost',           'uuid, int'),
      -- 0465: the yard takes an order: the quote, the order and the launch. Dark: {on: false}, E_NOT_IN_USE.
      ('world',       'hull_quote',          'uuid, text'),
      ('cmd',         'order_hull',          'uuid, text'),
      ('cmd',         'launch_hull',         'uuid, text'),
$h$);
  for h in select * from hunk_0465 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0465 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0465 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0465 p where p.fn = h.fn) then
      raise exception '0465 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  for h in select p.fn, p.def from pre_0465 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0465 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0465 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0465 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all(c_knobs)) <> v_cfg_before
     or public.wc('yard_order_enabled') <> 'false'::jsonb
     or public.wc_num('yard_order_fee_pct') <> 50 or public.wc_num('yard_order_minutes_per_hour') <> 1.25 then
    raise exception '0465 self-assert FAIL: a world_config row moved, or the yard''s order is not dark at 50 %% and 1.25 min an hour';
  end if;
  -- grants: the cores server only (service_role too); the doors and the quote authenticated alone and registered; the table no client's
  if exists (select 1 from unnest(c_new) f
              where f like 'public.%' and (has_function_privilege('authenticated', f::regprocedure, 'execute') or has_function_privilege('anon', f::regprocedure, 'execute')
                                           or has_function_privilege('service_role', f::regprocedure, 'execute')))
     or (select count(*) from public.client_rpc_entry_points() e
          where (e.schema_name, e.function_name, e.arg_types) in (('world', 'hull_quote', 'uuid, text'), ('cmd', 'order_hull', 'uuid, text'), ('cmd', 'launch_hull', 'uuid, text'))
            and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 3
     or has_table_privilege('authenticated', 'public.hull_orders', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.hull_orders', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.hull_orders'::regclass)
     or (select p.provolatile from pg_proc p where p.oid = 'world.building_yard(uuid)'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'world.hull_quote(uuid,text)'::regprocedure) <> 's'
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0465 self-assert FAIL: a core is reachable by a client or service_role, a door is not registered to authenticated alone, the table is reachable, or a read is no longer stable';
  end if;

  -- ── 6. THE PROBE, rolled back ──
  begin
    v_pl := public.new_house(c_uid, 'Estaleiro 0465', 'PRT');
    perform cmd.assume_identity(c_uid);
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select f.id into v_fl from public.fleets f where f.player_id = v_pl;

    -- (a) DARK: the yard read is the same text as before the hunk; the quote is {on: false}; the order door refuses and writes nothing
    if world.building_yard(v_lis) <> v_pre_yard or world.hull_quote(v_lis, 'barca') <> '{"on": false}'::jsonb then
      raise exception '0465 self-assert FAIL: dark, the yard read or the quote moved';
    end if;
    v_r := cmd.order_hull(v_lis, 'barca');
    if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or exists (select 1 from public.hull_orders o where o.player_id = v_pl) then
      raise exception '0465 self-assert FAIL: dark, the order door opened: %', v_r;
    end if;

    -- (b) LIT: the Barca's price and wait; the order paid exactly; one a yard; not ready; launched at ready
    update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';
    v_q := world.hull_quote(v_lis, 'barca');
    if (v_q ->> 'labour')::bigint <> public.yard_labour(v_pl, 'barca') or (v_q ->> 'materials')::bigint <= 0
       or (v_q ->> 'fee')::bigint <> round(((v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint) * 0.5)
       or (v_q ->> 'price')::bigint <> (v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint + (v_q ->> 'fee')::bigint
       or (v_q ->> 'minutes')::int <> 30 or v_q ->> 'short' is not null then
      raise exception '0465 self-assert FAIL: the Barca''s quote is not labour + materials + half again, in 30 minutes: %', v_q;
    end if;
    update public.players set ducats = (v_q ->> 'price')::bigint + 1000 where id = v_pl;
    v_r := cmd.order_hull(v_lis, 'barca');
    select o.id, o.ready_at into v_order, v_ready from public.hull_orders o where o.player_id = v_pl and o.launched_at is null;
    if not coalesce((v_r ->> 'ok')::boolean, false) or v_order is null or v_ready <> now() + interval '30 minutes'
       or (select p.ducats from public.players p where p.id = v_pl) <> 1000
       or (world.building_yard(v_lis) -> 'order' -> 'open' ->> 'class') is distinct from 'barca'
       or (world.building_yard(v_lis) -> 'order' -> 'open' ->> 'ready')::boolean is distinct from false then
      raise exception '0465 self-assert FAIL: the order was not paid whole and served open, not ready: % / %', v_r, world.building_yard(v_lis) -> 'order';
    end if;
    v_r := cmd.order_hull(v_lis, 'barca');
    if v_r ->> 'error_code' is distinct from 'E_YARD_BUSY' then
      raise exception '0465 self-assert FAIL: a second order at the same yard was not refused: %', v_r;
    end if;
    v_r := cmd.launch_hull(v_fl, 'Encomenda');
    if v_r ->> 'error_code' is distinct from 'E_NOT_READY' then
      raise exception '0465 self-assert FAIL: she launched before she was ready: %', v_r;
    end if;
    v_r := public.hull_launch_for(v_pl, v_fl, 'Encomenda', v_ready + interval '1 second');
    if not coalesce((v_r ->> 'ok')::boolean, false)
       or (select count(*) from public.ships s where s.fleet_id = v_fl) <> 2
       or (select s.crew from public.ships s where s.player_id = v_pl and s.name = 'Encomenda') <> 0
       or (select o.ship_id from public.hull_orders o where o.id = v_order) is distinct from (v_r ->> 'ship')::uuid then
      raise exception '0465 self-assert FAIL: at ready she did not join the fleet, uncrewed, the order closed: %', v_r;
    end if;
    v_note := format('the Barca at Lisbon: labour %s + materials %s + fee %s = %s, ready in %s min; ordered, paid, launched into her fleet',
      v_q ->> 'labour', v_q ->> 'materials', v_q ->> 'fee', v_q ->> 'price', v_q ->> 'minutes');
    raise exception using errcode = 'ZX465', message = 'PROBE_ROLLBACK_0465';
  exception when sqlstate 'ZX465' then
    v_lived := true;
  end;
  if not v_lived or v_note not like 'the Barca%' then
    raise exception '0465 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) or exists (select 1 from public.hull_orders)
     or public.wc('yard_order_enabled') <> 'false'::jsonb or public.current_player_id() is not null then
    raise exception '0465 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0465 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0465 self-assert ok: THE YARD TAKES AN ORDER, DARK. hull_orders (retention 7 days a launched row), three knobs (yard_order_enabled false), seven functions (cores server only; the quote and two doors authenticated), two hunks each once and reversing; dark the yard read is as before. Probe (rolled back): %. In all % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
