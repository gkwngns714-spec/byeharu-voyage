-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0007 — A FLEET ARRIVES, AND THE QUEUE RUNS ITSELF
--        The order queue, the six executable V0 verbs, and voyage.settle() — the idempotent
--        catch-up that makes "the fleet sailed while you were asleep" true rather than nearly true.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THE QUEUE AND SETTLE ARE ONE MIGRATION ──────────────────────────────────────────────────
--   DESIGN §D.2 defines tick_arrivals as: "resolve all unresolved day-checkpoints, apply
--   consumption, write the after-action report, DOCK THE FLEET, ADVANCE THE ORDER QUEUE." Those
--   are not two systems that call each other; they are one rule — TIME ADVANCES A FLEET'S AFFAIRS.
--   Splitting them would have needed a stub in one file replaced by a body in the next, which is
--   two authorities for one concept wearing a temporary disguise. 0008 is the separate concern:
--   turning a line of typed WORDS into a queued order.
--
-- ── THE HALT RULE, DELIBERATE (DESIGN §F.3, §L.4) ───────────────────────────────────────────────
--   "On failure the queue HALTS at that order with status='failed' and a reason. It does not skip
--   ahead ... a queue that quietly continues past a failed BUY will sail an empty ship halfway
--   round the world." cmd.advance() exits on the first failure and leaves the fleet in port.
--
-- ── WHY SETTLE IS IDEMPOTENT AND WHY IT MATTERS ─────────────────────────────────────────────────
--   Each voyage-day is resolved into voyage_events with ON CONFLICT DO NOTHING on
--   (voyage_id, day_index), and — the part that is easy to get wrong — the row's `resolved_at` is
--   the DETERMINISTIC day boundary, not now(). If it were now(), a lazily-settled voyage and a
--   tick-by-tick one would produce rows that differ in a column, and "byte-identical" would be
--   false in exactly the place the player cannot see. Every number written per day is a function
--   of (voyage, day, world_secret) and of the days already resolved, in order. Nothing reads the
--   clock except the decision of HOW MANY days are now due.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   public.fleet_load / fleet_unload / fleet_free_hold / fleet_cargo_qty — THE cargo movers.
--   cmd.resolve_qty()    — THE reading of ALL / HALF / n%, done at EXECUTION time, not at parse time.
--   cmd.execute_order()  — THE dispatcher; every verb's failure becomes an E_ code the same way.
--   cmd.advance()        — THE queue runner. The only thing that turns pending into done.
--   voyage.settle()      — THE catch-up. Called by every read RPC (0009) and by tick_arrivals (0010).
--   voyage.report_line() — THE prose. §E.6's after-action report is generated in one place.
--
-- ── V0 SCOPE, NAMED ─────────────────────────────────────────────────────────────────────────────
--   Six executable verbs: SAIL, BUY, SELL, PROVISION, HIRE, REPAIR. CANCEL and CLEAR act on the
--   queue rather than being queued, and live in 0008 with the parser. `SPEED press` is NOT
--   accepted: §K.1's V0 command list does not include it, so it is absent rather than half-built.
--   Hazards are §K.1's four: STORM, CALM, PIRATES, SHORT_RATIONS.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * A full §K.1 first session runs end to end inside a rolled-back probe: buy salt at Lisboa,
--     sail to Cádiz, sell, sail home — and the house is RICHER, by a printed number.
--     (§K.1's script reads "BUY sal 60". A Barca holds 60 tuns and already carries 4.2 tuns of
--     stores, so 60 does not fit and the probe buys 50. The DESIGN's beat is honoured; its
--     arithmetic is not, and saying so here is cheaper than a reader finding the divergence later.)
--   * All SIX executable verbs actually execute — SAIL, BUY, SELL, PROVISION, HIRE and REPAIR —
--     because a queue runner proven on two of them proves nothing about the other four.
--   * "SELL sal ALL" queued BEFORE the salt is even aboard sells the whole parcel on arrival, so
--     cmd.resolve_qty() is shown to read the hold at execution time rather than at parse time.
--   * SETTLING IS IDEMPOTENT: settling the same voyage five times in a row produces the same
--     number of voyage_events and the same purse as settling it once.
--   * THE HALT RULE BITES: an order that cannot execute leaves status='failed' with an E_ code and
--     the orders behind it still 'pending' — not 'skipped', not 'done'.
--   * Wages and consumption actually happen: crew are paid per voyage-day and stores fall.
--
-- Depends ONLY on: 0001-0006.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('provision_water_price', to_jsonb(2),
   'DESIGN F.2 PROVISION: ducats per tun of water. V0 uses one world price; V1 prices it per port.'),
  ('provision_food_price',  to_jsonb(5),
   'DESIGN F.2 PROVISION: ducats per tun of food. V0 uses one world price; V1 prices it per port.'),
  ('crew_urgent_multiplier', to_jsonb(2.5),
   'DESIGN F.2 HIRE: hiring beyond the port crew pool costs x2.5 ("urgent recruitment").'),
  ('short_rations_threshold', to_jsonb(0.15),
   'DESIGN B.6 SHORT_RATIONS: fires when remaining endurance falls below this fraction of the voyage length.'),
  ('repair_sim_hours_per_pct', to_jsonb(0.4),
   'DESIGN F.2 REPAIR: sim-hours of yard time per percentage point of damage repaired.')
on conflict (key) do nothing;

alter table public.fleets add column if not exists busy_until timestamptz;
comment on column public.fleets.busy_until is
  'When a REPAIRING fleet becomes available again. Like a voyage ETA it is a TIME, not a countdown: '
  'nothing has to tick for it to elapse while the player is away.';

-- ── The order queue (DESIGN §F.3) ──────────────────────────────────────────────────────────────
create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  fleet_id      uuid not null references public.fleets(id) on delete cascade,
  player_id     uuid not null references public.players(id) on delete cascade,
  seq           int  not null,
  raw_text      text not null,
  verb          text not null,
  args          jsonb not null default '{}'::jsonb,
  status        text not null default 'pending'
                check (status in ('pending','active','done','failed','cancelled','skipped')),
  error_code    text,
  error_message text,
  result        jsonb,
  issued_at     timestamptz not null default now(),
  executed_at   timestamptz,
  constraint orders_seq_unique unique (fleet_id, seq)
);
create index if not exists orders_fleet_pending on public.orders (fleet_id, seq) where status = 'pending';

alter table public.orders enable row level security;
create policy orders_read_own on public.orders for select to authenticated
  using (player_id = public.current_player_id());
grant select on public.orders to authenticated;

-- ── Cargo: the ONE set of movers ───────────────────────────────────────────────────────────────
create or replace function public.ship_cargo_tuns(p_ship uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum((e.value)::text::numeric * g.bulk), 0)
    from public.ships s
   cross join lateral jsonb_each(s.cargo) e
    join public.goods g on g.code = e.key
   where s.id = p_ship
$$;

create or replace function public.fleet_free_hold(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(greatest(0, c.hold - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t)), 0)
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet
$$;

-- ── HOW MUCH CAN SHE ACTUALLY TAKE ON? ────────────────────────────────────────────────────────
--
-- THE one answer to that question, because there were two and they disagreed. The hold was the
-- only limit anyone checked: `BUY salt ALL` filled the hold and then the trade was refused
-- E_INSUFFICIENT_FUNDS, and the Command tab's MAX chip offered 91 tuns of pepper that cost 8,130
-- against a purse of 8,000. Both were the same mistake — a maximum computed from ROOM while the
-- price is what binds — and both are fixed by asking here.
--
-- Four things can stop her, and the answer says WHICH, so a screen can put it in words:
--   hold   — the tuns left after stores, divided by the good's bulk
--   stock  — a port cannot sell what it does not have
--   cap    — §G.7.1's per-player, per-day anti-cornering limit
--   purse  — and this is the one nobody was checking, because it needs the STEPPED price:
--            buying moves the market (§G.2), so the tenth tun costs more than the first and a
--            maximum computed off the spot price is always too high.
--
-- It walks down in trade_step_tuns steps and asks world.quote() — the same function the committed
-- trade uses — so the number offered and the number charged cannot disagree.
create or replace function public.fleet_buy_capacity(p_fleet uuid, p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  f         public.fleets%rowtype;
  v_bulk    numeric;
  v_purse   numeric;
  v_stock   numeric;
  v_cap     numeric;
  v_hold    numeric;
  v_step    numeric := greatest(1, public.wc_num('trade_step_tuns'));
  v_qty     numeric;
  v_bound   text;
  q         record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null then
    return jsonb_build_object('max_qty', 0, 'est_total', 0, 'bound_by', 'no such fleet');
  end if;
  if f.port_id is null then
    return jsonb_build_object('max_qty', 0, 'est_total', 0, 'bound_by', 'at sea');
  end if;

  select bulk into v_bulk from public.goods where id = p_good;
  if v_bulk is null then
    return jsonb_build_object('max_qty', 0, 'est_total', 0, 'bound_by', 'no such good');
  end if;

  select ducats into v_purse from public.players where id = f.player_id;
  select stock  into v_stock from public.port_goods where port_id = f.port_id and good_id = p_good;
  v_cap  := world.daily_cap_remaining(f.player_id, f.port_id, p_good);
  v_hold := floor(public.fleet_free_hold(p_fleet) / v_bulk);

  -- The structural limits first, cheapest to establish.
  v_qty := floor(least(v_hold, coalesce(v_stock, 0), coalesce(v_cap, 0)));
  v_bound := case
               when v_qty = v_hold then 'hold'
               when v_qty = floor(coalesce(v_stock, 0)) then 'stock'
               else 'daily cap'
             end;

  -- Then the purse, at the price she would really pay. Stepping DOWN rather than solving for it
  -- keeps this arithmetic-free: the quote is the authority on what a quantity costs.
  while v_qty > 0 loop
    select * into q from world.quote(f.port_id, p_good, v_qty, 'buy');
    exit when q.units > 0 and q.total <= v_purse;
    v_bound := 'purse';
    -- Down a whole step while there is more than a step left, then ONE TUN AT A TIME. A pure
    -- ten-step walk answers "0" for anything dearer than 800 ducats a tun — she could afford two
    -- diamonds and the picker would offer her none.
    if v_qty > v_step then
      v_qty := floor((v_qty - 1) / v_step) * v_step;
    else
      v_qty := v_qty - 1;
    end if;
  end loop;

  if v_qty <= 0 then
    return jsonb_build_object('max_qty', 0, 'est_total', 0,
      'bound_by', case when v_bound = 'purse' then 'purse' else v_bound end);
  end if;
  return jsonb_build_object('max_qty', v_qty, 'est_total', round(q.total, 2), 'bound_by', v_bound);
end $$;

comment on function public.fleet_buy_capacity(uuid, uuid) is
  'THE most a fleet can actually buy, and WHICH of hold / stock / daily cap / purse stops her. '
  'Priced through world.quote(), so it accounts for the market moving under a large order — a '
  'maximum computed from the spot price is always too high.';

create or replace function public.fleet_cargo_qty(p_fleet uuid, p_good_code text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(coalesce((s.cargo->>p_good_code)::numeric, 0)), 0)
    from public.ships s where s.fleet_id = p_fleet
$$;

create or replace function public.fleet_load(p_fleet uuid, p_good_code text, p_qty numeric)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bulk numeric;
  v_left numeric := p_qty;
  v_take numeric;
  r      record;
begin
  select bulk into v_bulk from public.goods where code = p_good_code;
  -- Largest hull first: a fleet fills its bulk carrier before its coaster, which is what a master
  -- would do and what keeps the small hulls free for the next parcel.
  for r in select s.id, c.hold - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t as free
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet order by c.hold desc loop
    exit when v_left <= 0;
    v_take := least(v_left, floor(greatest(0, r.free) / v_bulk));
    if v_take > 0 then
      update public.ships
         set cargo = jsonb_set(cargo, array[p_good_code],
                     to_jsonb(coalesce((cargo->>p_good_code)::numeric, 0) + v_take), true)
       where id = r.id;
      v_left := v_left - v_take;
    end if;
  end loop;
  return p_qty - v_left;   -- how much actually went aboard
end $$;

create or replace function public.fleet_unload(p_fleet uuid, p_good_code text, p_qty numeric)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_left numeric := p_qty;
  v_take numeric;
  r      record;
begin
  for r in select s.id, coalesce((s.cargo->>p_good_code)::numeric, 0) as have
             from public.ships s where s.fleet_id = p_fleet order by have desc loop
    exit when v_left <= 0;
    v_take := least(v_left, r.have);
    if v_take > 0 then
      update public.ships
         set cargo = case when r.have - v_take <= 0 then cargo - p_good_code
                          else jsonb_set(cargo, array[p_good_code], to_jsonb(r.have - v_take), true) end
       where id = r.id;
      v_left := v_left - v_take;
    end if;
  end loop;
  return p_qty - v_left;
end $$;

-- ── THE ONE reading of "how many tuns did they mean?" ─────────────────────────────
-- DESIGN F.1: qty = integer | "ALL" | "HALF" | percent. ALL and HALF are resolved HERE, at
-- EXECUTION time, and never at parse time: "SELL cloves ALL" queued in Lisboa means all the cloves
-- aboard when the fleet reaches Amsterdam, not the number that happened to be aboard when the
-- player typed it. Resolving it in the parser would freeze a stale number into the order.
create or replace function cmd.resolve_qty(p_fleet uuid, p_good_code text, p_side text, p_args jsonb)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_bulk numeric;
  v_max  numeric;
begin
  if p_args ? 'qty' and p_args->>'qty' is not null then
    return (p_args->>'qty')::numeric;
  end if;
  if p_side = 'buy' then
    -- ALL means "as much as she can actually take on" — which is the hold OR the purse OR the
    -- stock, whichever binds first. It used to mean the hold alone, so `BUY salt ALL` filled the
    -- hold and was then refused for want of money, which is not what anybody means by ALL.
    v_max := (public.fleet_buy_capacity(
                p_fleet, (select id from public.goods where code = p_good_code)
              )->>'max_qty')::numeric;
  else
    v_max := public.fleet_cargo_qty(p_fleet, p_good_code);
  end if;
  return case coalesce(p_args->>'qty_mode', 'ALL')
           when 'ALL'  then floor(v_max)
           when 'HALF' then floor(v_max / 2)
           when 'PCT'  then floor(v_max * (p_args->>'qty_pct')::numeric / 100)
           else floor(v_max)
         end;
end $$;

-- ── The verb executors ─────────────────────────────────────────────────────────────────────────
-- Each raises 'E_XXX: sentence' on refusal. cmd.execute_order() turns that into the order's
-- error_code + error_message, so every verb fails the same shape and the UI has one contract.

create or replace function cmd.do_sail(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  v_nodes  uuid[];
  v_via    uuid[];
  v_dest   uuid;
  v_nm     numeric;
  v_speed  numeric;
  v_days   numeric;
  v_end    numeric;
  v_draft  int;
  v_maxd   int;
  v_short  int;
  v_flag   numeric;
  v_voyage uuid;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to sail', f.name, f.status using errcode = 'P0001';
  end if;

  v_dest := (p_args->>'dest')::uuid;
  select coalesce(array_agg(x::uuid), '{}'::uuid[]) into v_via
    from jsonb_array_elements_text(coalesce(p_args->'via', '[]'::jsonb)) x;

  v_nodes := voyage.route(f.port_id, v_dest, v_via);
  if v_nodes is null then
    raise exception 'E_NO_ROUTE: there is no authored sea route from here to that port'
      using errcode = 'P0001';
  end if;

  -- Every ship must be able to leave and to arrive (DESIGN F.2 SAIL preconditions).
  select count(*) into v_short
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    raise exception 'E_CREW_SHORT: % ship(s) are below their required complement', v_short using errcode = 'P0001';
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    raise exception 'E_FLAGSHIP_DISABLED: the flagship cannot sail until it is repaired' using errcode = 'P0001';
  end if;

  select max(c.draft) into v_draft from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet;
  select max_draft into v_maxd from public.ports where id = v_dest;
  if v_draft > v_maxd then
    raise exception 'E_DRAFT: the deepest hull draws % and that port takes %', v_draft, v_maxd using errcode = 'P0001';
  end if;
  if (select is_ice_closed from public.ports where id = v_dest) then
    raise exception 'E_PORT_CLOSED: that port is closed' using errcode = 'P0001';
  end if;

  select sum((e->>'nm')::numeric) into v_nm
    from jsonb_array_elements(voyage.path_from_nodes(v_nodes)) e;
  v_speed := voyage.fleet_speed(p_fleet);
  v_days  := (v_nm / v_speed) / 24;
  v_end   := voyage.endurance_days(p_fleet);
  -- DESIGN C.5: "SAIL refuses to queue if endurance_days < leg_days x 1.15, and says so."
  if v_end < v_days * public.wc_num('endurance_margin') then
    raise exception 'E_ENDURANCE: % carries %.1 days of stores and that route is %.1 voyage-days; you need % — PROVISION first',
      (select name from public.fleets where id = p_fleet),
      round(v_end, 1), round(v_days, 1), round(v_days * public.wc_num('endurance_margin'), 1)
      using errcode = 'P0001';
  end if;

  v_voyage := voyage.depart(p_fleet, v_nodes);
  perform public.emit_event(f.player_id, 'DEPARTED', jsonb_build_object(
    'fleet', f.name, 'voyage_id', v_voyage, 'total_nm', v_nm,
    'legs', jsonb_array_length(voyage.path_from_nodes(v_nodes)),
    'eta', (select eta from public.voyages where id = v_voyage)));
  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm, 'voyage_days', round(v_days, 2));
end $$;

create or replace function cmd.do_buy(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  g       public.goods%rowtype;
  v_qty   numeric;
  v_cap   numeric;
  v_free  numeric;
  v_stock numeric;
  v_purse bigint;
  q       record;
  v_culture text;
  v_loaded  numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;

  select culture into v_culture from public.ports where id = f.port_id;
  if v_culture = any(g.culture_mask) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock from public.port_goods where port_id = f.port_id and good_id = g.id;
  if v_stock is null then raise exception 'E_NO_SUCH_GOOD: no market for % here', g.name using errcode = 'P0001'; end if;

  v_qty  := cmd.resolve_qty(p_fleet, g.code, 'buy', p_args);
  v_free := floor(public.fleet_free_hold(p_fleet) / g.bulk);
  if v_qty <= 0 then
    raise exception 'E_HOLD_FULL: there is no room aboard for %', g.name using errcode = 'P0001';
  end if;
  if v_qty > v_free then
    raise exception 'E_HOLD_FULL: the fleet has room for % tuns of % and you asked for %',
      v_free, g.name, v_qty using errcode = 'P0001';
  end if;
  if v_stock <= 0 then
    raise exception 'E_NO_STOCK: there is none for sale here' using errcode = 'P0001';
  end if;
  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  if v_qty > v_cap then
    raise exception 'E_DAILY_CAP: you may take % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';
  end if;

  select * into q from world.quote(f.port_id, g.id, v_qty, 'buy',
                                   nullif((p_args->>'limit'), '')::numeric);
  if q.units <= 0 then
    if p_args ? 'limit' and p_args->>'limit' is not null then
      raise exception 'E_PRICE_LIMIT: % opened above your limit of % and nothing was bought',
        g.name, (p_args->>'limit') using errcode = 'P0001';
    end if;
    raise exception 'E_NO_STOCK: nothing could be bought' using errcode = 'P0001';
  end if;

  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < q.total then
    raise exception 'E_INSUFFICIENT_FUNDS: % tuns of % cost % d. and you hold %',
      q.units, g.name, q.total, v_purse using errcode = 'P0001';
  end if;

  v_loaded := public.fleet_load(p_fleet, g.code, q.units);
  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  values (f.player_id, f.port_id, g.id, world.game_day(), q.units)
  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;

  perform public.credit(f.player_id, 'BUY', -q.total,
    public.emit_event(f.player_id, 'BOUGHT', jsonb_build_object(
      'fleet', f.name, 'good', g.name, 'qty', q.units, 'avg_price', q.avg_price, 'total', q.total)));

  return jsonb_build_object('good', g.code, 'qty', v_loaded, 'total', q.total, 'avg_price', q.avg_price);
end $$;

create or replace function cmd.do_sell(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  g       public.goods%rowtype;
  v_qty   numeric;
  v_have  numeric;
  v_cap   numeric;
  q       record;
  v_culture text;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;

  select culture into v_culture from public.ports where id = f.port_id;
  if v_culture = any(g.culture_mask) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  v_qty  := least(cmd.resolve_qty(p_fleet, g.code, 'sell', p_args), v_have);
  if v_have <= 0 or v_qty <= 0 then
    raise exception 'E_NO_CARGO: % carries no %', f.name, g.name using errcode = 'P0001';
  end if;
  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  if v_qty > v_cap then
    raise exception 'E_DAILY_CAP: you may move % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';
  end if;

  select * into q from world.quote(f.port_id, g.id, v_qty, 'sell',
                                   nullif((p_args->>'limit'), '')::numeric);
  if q.units <= 0 then
    raise exception 'E_PRICE_LIMIT: % is bid below your limit of % and nothing was sold',
      g.name, (p_args->>'limit') using errcode = 'P0001';
  end if;

  perform public.fleet_unload(p_fleet, g.code, q.units);
  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  values (f.player_id, f.port_id, g.id, world.game_day(), q.units)
  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;

  perform public.credit(f.player_id, 'SELL', q.total,
    public.emit_event(f.player_id, 'SOLD', jsonb_build_object(
      'fleet', f.name, 'good', g.name, 'qty', q.units, 'avg_price', q.avg_price, 'total', q.total)));

  return jsonb_build_object('good', g.code, 'qty', q.units, 'total', q.total, 'avg_price', q.avg_price);
end $$;

create or replace function cmd.do_provision(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  r        record;
  v_wp     numeric := public.wc_num('provision_water_price');
  v_fp     numeric := public.wc_num('provision_food_price');
  v_water  numeric := 0;
  v_food   numeric := 0;
  v_target numeric;
  v_days   numeric;
  v_cost   bigint;
  v_purse  bigint;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to take on stores', f.name, f.status using errcode = 'P0001';
  end if;

  for r in select s.id, s.crew, s.water_t, s.food_t, s.store_ratio, c.hold,
                  public.ship_cargo_tuns(s.id) as cargo_t
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet loop
    if p_args->>'mode' = 'DAYS' then
      v_days   := (p_args->>'days')::numeric;
      v_target := least(r.hold - r.cargo_t,
                        r.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * v_days);
    else
      -- FULL: fill stores to the ship's store_ratio of its hold (DESIGN F.2), never past the hold.
      v_target := least(r.hold - r.cargo_t, r.hold * r.store_ratio);
    end if;
    v_target := greatest(0, v_target - r.water_t - r.food_t);
    -- Split in the same proportion the crew drinks and eats, so a full hold lasts the same number
    -- of days on both stores rather than running dry on water with food to spare.
    v_water := v_water + round(v_target * public.wc_num('water_per_crew_day')
               / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3);
    v_food  := v_food  + round(v_target * public.wc_num('food_per_crew_day')
               / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3);
  end loop;

  if v_water + v_food <= 0 then
    raise exception 'E_HOLD_FULL: there is no room for more stores' using errcode = 'P0001';
  end if;

  v_cost := round(v_water * v_wp + v_food * v_fp)::bigint;
  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < v_cost then
    raise exception 'E_INSUFFICIENT_FUNDS: stores cost % d. and you hold %', v_cost, v_purse using errcode = 'P0001';
  end if;

  for r in select s.id, s.crew, s.water_t, s.food_t, s.store_ratio, c.hold,
                  public.ship_cargo_tuns(s.id) as cargo_t
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet loop
    if p_args->>'mode' = 'DAYS' then
      v_target := least(r.hold - r.cargo_t,
                        r.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'))
                        * (p_args->>'days')::numeric);
    else
      v_target := least(r.hold - r.cargo_t, r.hold * r.store_ratio);
    end if;
    v_target := greatest(0, v_target - r.water_t - r.food_t);
    update public.ships
       set water_t = water_t + round(v_target * public.wc_num('water_per_crew_day')
                     / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3),
           food_t  = food_t  + round(v_target * public.wc_num('food_per_crew_day')
                     / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)
     where id = r.id;
  end loop;

  perform public.credit(f.player_id, 'PROVISION', -v_cost,
    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)));

  return jsonb_build_object('water_t', v_water, 'food_t', v_food, 'cost', v_cost,
                            'endurance_days', round(voyage.endurance_days(p_fleet), 1));
end $$;

create or replace function cmd.do_hire(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  v_count int := (p_args->>'count')::int;
  v_pool  int;
  v_room  int;
  v_rate  numeric := public.wc_num('hire_crew_rate');
  v_norm  int;
  v_urg   int;
  v_cost  bigint;
  v_purse bigint;
  v_left  int;
  r       record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and cannot recruit', f.name, f.status using errcode = 'P0001';
  end if;
  if v_count <= 0 then
    raise exception 'E_PARSE: HIRE needs a positive number of crew' using errcode = 'P0001';
  end if;

  select coalesce(sum(c.crew_max - s.crew), 0) into v_room
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;
  if v_count > v_room then
    raise exception 'E_CREW_MAX: the fleet has berths for % more hands', v_room using errcode = 'P0001';
  end if;

  select crew_pool into v_pool from public.ports where id = f.port_id;
  v_norm := least(v_count, v_pool);
  v_urg  := v_count - v_norm;
  -- DESIGN F.2 HIRE: beyond the pool you may still recruit, at the x2.5 "urgent" rate. It is a
  -- price, not a refusal, so E_CREW_POOL is reserved for a port with no hands at all.
  if v_pool <= 0 and v_urg = v_count then
    raise exception 'E_CREW_POOL: there are no hands to be had in this port' using errcode = 'P0001';
  end if;
  v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;

  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < v_cost then
    raise exception 'E_INSUFFICIENT_FUNDS: % hands cost % d. and you hold %', v_count, v_cost, v_purse using errcode = 'P0001';
  end if;

  v_left := v_count;
  for r in select s.id, c.crew_max - s.crew as room
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet order by room desc loop
    exit when v_left <= 0;
    update public.ships set crew = crew + least(v_left, r.room) where id = r.id;
    v_left := v_left - least(v_left, r.room);
  end loop;

  update public.ports set crew_pool = greatest(0, crew_pool - v_norm) where id = f.port_id;
  perform public.credit(f.player_id, 'HIRE', -v_cost,
    public.emit_event(f.player_id, 'HIRED', jsonb_build_object(
      'fleet', f.name, 'count', v_count, 'urgent', v_urg, 'cost', v_cost)));

  return jsonb_build_object('hired', v_count, 'urgent', v_urg, 'cost', v_cost);
end $$;

create or replace function cmd.do_repair(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  v_to     numeric := coalesce((p_args->>'to_pct')::numeric, 100);
  v_dev    int;
  v_yard   boolean;
  v_points numeric := 0;
  v_pct    numeric := 0;
  v_cost   bigint;
  v_purse  bigint;
  v_hours  numeric;
  r        record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and cannot enter a yard', f.name, f.status using errcode = 'P0001';
  end if;
  select has_yard, dev_industry into v_yard, v_dev from public.ports where id = f.port_id;
  if not v_yard then
    raise exception 'E_NO_YARD: this port has no repair yard' using errcode = 'P0001';
  end if;

  for r in select s.id, s.durability, c.durability as maxd
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet loop
    if r.durability < r.maxd * v_to / 100 then
      v_points := v_points + (r.maxd * v_to / 100 - r.durability);
      v_pct    := greatest(v_pct, (r.maxd * v_to / 100 - r.durability) / r.maxd * 100);
    end if;
  end loop;
  if v_points <= 0 then
    raise exception 'E_UNAVAILABLE: nothing aboard needs repair' using errcode = 'P0001';
  end if;

  v_cost := round(v_points * public.wc_num('repair_rate_per_point') * (1 - v_dev * 0.01))::bigint;
  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < v_cost then
    raise exception 'E_INSUFFICIENT_FUNDS: the repair costs % d. and you hold %', v_cost, v_purse using errcode = 'P0001';
  end if;

  update public.ships s set durability = greatest(s.durability, c.durability * v_to / 100)
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = p_fleet;

  v_hours := v_pct * public.wc_num('repair_sim_hours_per_pct');
  update public.fleets
     set status = 'REPAIRING', version = version + 1,
         busy_until = now() + make_interval(secs => (v_hours * 3600 / public.wc_num('time_compression'))::double precision)
   where id = p_fleet;

  perform public.credit(f.player_id, 'REPAIR', -v_cost,
    public.emit_event(f.player_id, 'REPAIRING', jsonb_build_object(
      'fleet', f.name, 'points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))));

  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1));
end $$;

-- ── The dispatcher ─────────────────────────────────────────────────────────────────────────────
create or replace function cmd.execute_order(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  o      public.orders%rowtype;
  v_res  jsonb;
  v_code text;
  v_msg  text;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null then
    raise exception 'E_PARSE: no such order %', p_order using errcode = 'P0001';
  end if;
  if o.status not in ('pending', 'active') then
    return jsonb_build_object('ok', false, 'reason', 'not_pending');
  end if;

  update public.orders set status = 'active' where id = o.id;

  begin
    v_res := case o.verb
               when 'SAIL'      then cmd.do_sail(o.fleet_id, o.args)
               when 'BUY'       then cmd.do_buy(o.fleet_id, o.args)
               when 'SELL'      then cmd.do_sell(o.fleet_id, o.args)
               when 'PROVISION' then cmd.do_provision(o.fleet_id, o.args)
               when 'HIRE'      then cmd.do_hire(o.fleet_id, o.args)
               when 'REPAIR'    then cmd.do_repair(o.fleet_id, o.args)
               else null
             end;
    if v_res is null then
      raise exception 'E_PARSE: % is not an executable verb in V0', o.verb using errcode = 'P0001';
    end if;
  exception when others then
    -- One shape for every refusal: 'E_CODE: sentence'. §F.5 requires "a code, a sentence and a
    -- fix"; the code and the sentence are stored here and 0008 attaches the fixes.
    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    update public.orders
       set status = 'failed', error_code = v_code,
           error_message = btrim(substr(v_msg, length(v_code) + 2)), executed_at = now()
     where id = o.id;
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)));
  end;

  update public.orders set status = 'done', result = v_res, executed_at = now() where id = o.id;
  return jsonb_build_object('ok', true, 'result', v_res);
end $$;

-- ── The queue runner (DESIGN §F.3) ─────────────────────────────────────────────────────────────
create or replace function cmd.advance(p_fleet uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f      public.fleets%rowtype;
  o      public.orders%rowtype;
  v_res  jsonb;
  v_ran  int := 0;
  guard  int := 0;
begin
  loop
    guard := guard + 1;
    exit when guard > 64;   -- the queue is capped at 12; this is a runaway guard, not a policy.

    -- §F.3: "on a failure it HALTS — it never skips." The rule was only enforced INSIDE one call:
    -- the loop stopped at a failure, and then the next arrival called advance() again, found the
    -- failed order was no longer `pending`, and ran the one behind it — which is skipping, on a
    -- delay. Found by a probe whose queue read [1:failed E_HOLD_FULL 2:done 3:pending 4:pending].
    --
    -- So a failed order now blocks the fleet until the player clears it. That is the whole point
    -- of the rule: an order that could not be carried out is a decision to bring back to the
    -- captain, not a line to step over while nobody is watching. CLEAR (and CANCEL of that order)
    -- releases it, so this can never become a deadlock.
    if exists (select 1 from public.orders
                where fleet_id = p_fleet and status = 'failed') then
      exit;
    end if;

    select * into f from public.fleets where id = p_fleet for update;
    if f.status = 'REPAIRING' then
      if f.busy_until is not null and f.busy_until <= p_now then
        update public.fleets set status = 'DOCKED', busy_until = null, version = version + 1
         where id = p_fleet;
        perform public.emit_event(f.player_id, 'REPAIRED', jsonb_build_object('fleet', f.name));
        continue;
      end if;
      exit;   -- still in the yard
    end if;
    exit when f.status <> 'DOCKED';   -- SAILING / ADRIFT / UNABLE_TO_SAIL: nothing can execute

    select * into o from public.orders
     where fleet_id = p_fleet and status = 'pending' order by seq limit 1;
    exit when o.id is null;

    v_res := cmd.execute_order(o.id);
    v_ran := v_ran + 1;
    -- THE HALT RULE (§F.3): stop at the first failure. Do NOT skip to the next order.
    exit when not coalesce((v_res->>'ok')::boolean, false);
  end loop;
  return v_ran;
end $$;

-- ── The after-action prose (DESIGN §E.6) ───────────────────────────────────────────────────────
create or replace function voyage.report_line(p_day int, p_kind text, p_payload jsonb)
returns text
language sql
immutable
as $$
  select case p_kind
    when 'CLEAR'         then format('Day %s. A quiet watch; nothing to report.', p_day)
    when 'STORM'         then format('Day %s. A gale took us on the beam. We ran under bare poles and lost %s points of hull.',
                                     p_day, coalesce(p_payload->>'hull_lost', '?'))
    when 'CALM'          then format('Day %s. The wind died away. We lay becalmed and lost %s hours.',
                                     p_day, coalesce(p_payload->>'delay_hours', '?'))
    when 'PIRATES'       then format('Day %s. Sail sighted to windward. %s',
                                     p_day, coalesce(p_payload->>'prose', 'They closed with us.'))
    when 'SHORT_RATIONS' then format('Day %s. Stores are low. The hands are on short rations and their wages are up.', p_day)
    else format('Day %s. %s', p_day, p_kind)
  end
$$;

-- ── THE CATCH-UP (DESIGN §D.2) ─────────────────────────────────────────────────────────────────
create or replace function voyage.settle(p_fleet uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v         public.voyages%rowtype;
  f         public.fleets%rowtype;
  d         int;
  v_cap     int;
  v_bound   timestamptz;
  h         record;
  s         record;
  v_kind    text;
  v_payload jsonb;
  v_wages   bigint;
  v_short   boolean;
  v_delay   numeric;
  v_hull    numeric;
  v_end     numeric;
  v_resolved int := 0;
  v_escort  numeric;
  v_raider  numeric;
  v_ratio   numeric;
  v_outcome text;
  v_prose   text;
  v_lost    numeric;
begin
  select * into f from public.fleets where id = p_fleet for update;
  if f.id is null then return 0; end if;

  select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' for update;
  if v.id is null then
    perform cmd.advance(p_fleet, p_now);
    return 0;
  end if;

  loop
    d := v.last_settled_day + 1;
    v_cap := voyage.total_days(v.id);
    exit when d > v_cap;
    v_bound := voyage.day_ends_at(v.id, d);
    exit when v_bound > p_now;

    -- ── consumption (DESIGN C.5), applied first: the day's stores are drunk before the hazard.
    for s in select sh.id, sh.crew, sh.water_t, sh.food_t from public.ships sh where sh.fleet_id = p_fleet loop
      update public.ships
         set water_t = greatest(0, water_t - s.crew * public.wc_num('water_per_crew_day')),
             food_t  = greatest(0, food_t  - s.crew * public.wc_num('food_per_crew_day'))
       where id = s.id;
    end loop;

    v_end   := voyage.endurance_days(p_fleet);
    v_short := v_end < public.wc_num('short_rations_threshold') * v_cap;

    -- ── wages (DESIGN C.5), x1.5 on short rations
    select coalesce(sum(sh.crew), 0) * public.wc_num('wage_per_crew_day')
           * (case when v_short then public.wc_num('short_rations_wage_mult') else 1 end)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;
    if v_wages > 0 then
      -- A house that cannot pay does not vanish: the wages are still owed and the purse floors at
      -- zero rather than the transaction dying halfway through a settled day.
      perform public.credit(f.player_id, 'WAGES',
        -least(v_wages, (select ducats from public.players where id = f.player_id)));
    end if;

    -- ── the deterministic hazard (DESIGN B.6)
    select * into h from voyage.hazard_roll(v.id, d);
    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);

    if h.occurred and h.kind = 'STORM' then
      v_kind := 'STORM';
      v_hull := 0;
      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        v_lost := round(s.maxd * (0.08 + 0.17 * h.magnitude), 2);
        update public.ships set durability = greatest(0, s.durability - v_lost) where id = s.id;
        v_hull := v_hull + v_lost;
      end loop;
      v_delay   := 36;   -- DESIGN B.6: +1.5 voyage-days
      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull, 'delay_hours', v_delay);

    elsif h.occurred and h.kind = 'CALM' then
      v_kind    := 'CALM';
      v_delay   := round((1 + 3 * h.magnitude) * 24, 2);   -- DESIGN B.6: 1-4 voyage-days
      v_payload := v_payload || jsonb_build_object('delay_hours', v_delay);

    elsif h.occurred and h.kind = 'PIRATES' then
      v_kind := 'PIRATES';
      -- DESIGN B.6: escort_score = Σ(guns + crew×0.02 + hull_class×3). The ENTIRE combat system.
      select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) into v_escort
        from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet;
      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid;
      v_ratio := case when v_raider <= 0 then 99 else v_escort / v_raider end;
      if    v_ratio >= 2.0 then v_outcome := 'EVADED';
      elsif v_ratio >= 1.2 then v_outcome := 'DRIVEN_OFF';
      elsif v_ratio >= 0.7 then v_outcome := 'RANSOM';
      elsif v_ratio >= 0.3 then v_outcome := 'PLUNDERED';
      else                      v_outcome := 'STRIPPED';
      end if;
      v_prose := case v_outcome
        when 'EVADED'     then 'They stood off and did not close.'
        when 'DRIVEN_OFF' then 'We fired twice and they sheered away.'
        when 'RANSOM'     then 'We paid them off rather than fight.'
        when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
        else 'They took everything but the ship itself.' end;
      if v_outcome in ('DRIVEN_OFF', 'PLUNDERED', 'STRIPPED') then
        update public.ships sh
           set crew = greatest(0, floor(sh.crew * (case v_outcome when 'DRIVEN_OFF' then 0.98
                                                                  when 'PLUNDERED' then 0.90
                                                                  else 0.70 end))),
               durability = greatest(0, sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                        when 'PLUNDERED' then 0.80
                                                                        else 1.00 end))
         where sh.fleet_id = p_fleet;
      end if;
      if v_outcome in ('PLUNDERED', 'STRIPPED') then
        -- DESIGN B.6: "The flagship is never captured." The worst case is expensive, not fatal.
        update public.ships set cargo = case when v_outcome = 'STRIPPED' then '{}'::jsonb
                                             else cargo end
         where fleet_id = p_fleet;
      end if;
      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
                                                   'escort', round(v_escort, 2), 'raider', round(v_raider, 2));
    elsif v_short then
      v_kind := 'SHORT_RATIONS';
    else
      v_kind := 'CLEAR';
    end if;

    -- resolved_at is the DETERMINISTIC day boundary, never now(). This is what makes a lazily
    -- settled voyage byte-identical to a tick-by-tick one.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v.id, d, v_kind, v_payload, v_bound)
    on conflict (voyage_id, day_index) do nothing;

    update public.voyages set last_settled_day = d where id = v.id;
    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;
    select * into v from public.voyages where id = v.id;
    v_resolved := v_resolved + 1;
  end loop;

  -- ── arrival
  if p_now >= v.eta then
    update public.voyages set status = 'ARRIVED', last_settled_day = voyage.total_days(v.id) where id = v.id;
    update public.fleets
       set status = case when (select durability from public.ships where fleet_id = p_fleet and is_flagship) <= 0
                         then 'UNABLE_TO_SAIL' else 'DOCKED' end,
           port_id = v.dest_port_id, version = version + 1
     where id = p_fleet;
    perform public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
      'fleet', f.name,
      'voyage_id', v.id,
      'from', (select code from public.ports where id = v.origin_port_id),
      'to',   (select code from public.ports where id = v.dest_port_id),
      'total_nm', v.total_nm,
      'lines', (select coalesce(jsonb_agg(voyage.report_line(ve.day_index, ve.kind, ve.payload) order by ve.day_index), '[]'::jsonb)
                  from public.voyage_events ve where ve.voyage_id = v.id)));
    perform cmd.advance(p_fleet, p_now);
  end if;

  return v_resolved;
end $$;

comment on function voyage.settle(uuid, timestamptz) is
  'THE idempotent catch-up of DESIGN D.2. Safe to call any number of times: each voyage-day is one '
  'row keyed (voyage_id, day_index) and every number written is a pure function of the voyage, the '
  'day and the days already resolved. Called by every read RPC and by tick_arrivals.';

grant execute on function cmd.advance(uuid, timestamptz) to service_role;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe constant uuid := '00000000-0007-4000-8000-000000000001';
  v_player uuid; v_fleet uuid; v_lis uuid; v_cad uuid; v_sal uuid;
  v_start bigint; v_final bigint;
  v_bad uuid; v_next uuid;
  v_events1 int; v_events2 int; v_purse1 bigint; v_purse2 bigint;
  v_water0 numeric; v_water1 numeric; v_wages int;
  v_grants int; n int; k int;
  v_prov jsonb; v_hire jsonb; v_rep jsonb;
  v_end_status text; v_end_port text; v_orders text; v_room numeric;
  v_probe2 constant uuid := '00000000-0000-0000-0000-0000000007bb';
  r_try record; q_try_buy record; q_try_sell record; v_try_qty numeric; v_best_gain numeric;
  v_player2 uuid; v_fleet2 uuid;
  f_session boolean := false; f_idem boolean := false; f_halt boolean := false;
  f_burn boolean := false; f_verbs boolean := false; f_cap boolean := false;
  v_cap jsonb; v_cap_good uuid; v_cap_total numeric; v_cap_over numeric; v_cap_purse numeric;
  o public.orders%rowtype;
begin
  select id into v_lis from public.ports where code = 'LIS';

  begin
    v_player := public.new_house(v_probe, 'Casa Fila', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    -- Water the ship before sailing. The starter Barca carries 2.4 tuns, which is a coastal hop's
    -- worth; §F.2's endurance rule refuses a real voyage on it, and refusing IS the game working.
    -- So the probe does what a captain does — fills the casks at the quay — and only then asks
    -- whether the QUEUE runs itself, which is what this migration is about.
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    -- AND SIGN A FULL COMPLEMENT. A Barca sails with the eight hands she needs and no more, so a
    -- single desertion or fever at sea (§B.6 rolls them) leaves her below her minimum and the
    -- homeward SAIL is refused E_CREW_SHORT — which is the game working, and which made this probe
    -- fail on some runs and not others depending on the day's hazard rolls. A captain about to
    -- cross five hundred miles hires to full at the quay; so does this.
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id
        where sh.fleet_id = v_fleet)));
    select water_t into v_water0 from public.ships where fleet_id = v_fleet;
    -- The purse is read AFTER watering, so "came home richer" is a judgement on the trade rather
    -- than on the stores, which are a cost the voyage was always going to pay.
    select ducats into v_start from public.players where id = v_player;

    -- THE SUBJECT OF THIS PROBE IS FOUND, NOT NAMED, AND CHOSEN BY WHAT IT PAYS.
    --
    -- §K.1's script reads "buy sal at Lisboa, sell it at Cádiz" — true of the twelve-port world it
    -- was written against, and an assertion about a SEED rather than about the game. So the probe
    -- asks the world instead.
    --
    -- It used to ask for the widest AFFINITY GAP, which is a proxy for profit and not profit: the
    -- gap ignores the spread, the tax, and the market moving under the order. With the economy
    -- tuned down to a median 8.8% (D10) that proxy picked a cargo whose whole margin was thinner
    -- than the voyage's wages, and the round trip came home 23 ducats POORER — on CI, where the
    -- hazard rolls differ from this machine, while passing here. A coin flip in a self-assert.
    --
    -- So it quotes BOTH ENDS through world.quote() — the same stepped pricing a real trade walks —
    -- and takes the best actual gain. That is also what a player does with the MARKET tab open.
    for r_try in
      select g.id as good_id, l_dest.id as dest_id
        from public.legs l
        join public.ports l_dest
          on l_dest.id = case when l.from_port_id = v_lis then l.to_port_id else l.from_port_id end
        join public.port_goods pg_home on pg_home.port_id = v_lis
        join public.port_goods pg_away
          on pg_away.port_id = l_dest.id and pg_away.good_id = pg_home.good_id
        join public.goods g on g.id = pg_home.good_id
       where (l.from_port_id = v_lis or l.to_port_id = v_lis)
         and l.distance_nm < 700                                  -- a first voyage, not an ocean crossing
         and not (l_dest.culture = any(g.culture_mask))           -- they will trade it at the far end
         and g.bulk <= 1.0                                        -- and it fits a Barca's hold
       order by pg_away.affinity - pg_home.affinity desc, l.distance_nm asc, g.code asc
       limit 8
    loop
      v_try_qty := (public.fleet_buy_capacity(v_fleet, r_try.good_id)->>'max_qty')::numeric;
      if v_try_qty < 1 then continue; end if;
      select * into q_try_buy  from world.quote(v_lis, r_try.good_id, v_try_qty, 'buy');
      select * into q_try_sell from world.quote(r_try.dest_id, r_try.good_id, q_try_buy.units, 'sell');
      if v_best_gain is null or (q_try_sell.total - q_try_buy.total) > v_best_gain then
        v_best_gain := q_try_sell.total - q_try_buy.total;
        v_sal  := r_try.good_id;
        v_cad  := r_try.dest_id;
        v_room := q_try_buy.units;
      end if;
    end loop;

    if v_sal is null then
      raise exception '0007 self-assert FAIL: no one-leg trade out of Lisboa is open to a starter at all';
    end if;
    -- The voyage has to clear its own wages and stores, or "came home richer" is a coin flip. If
    -- the best trade in reach cannot, that is a BALANCE failure and it should say so in those
    -- words — scripts/db/proofs/05_first_voyage_balance.sql is where that band is set.
    if v_best_gain < 400 then
      raise exception '0007 self-assert FAIL: the best one-leg trade out of Lisboa gains only % d. gross, which will not cover a voyage''s wages and stores. Run scripts/db/tune-balance.mjs.',
        round(v_best_gain, 0);
    end if;

    -- The §K.1 script, entered as a QUEUE the fleet runs by itself while nobody watches.
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values
      (v_fleet, v_player, 1, 'BUY',         'BUY',  jsonb_build_object('good', v_sal, 'qty', v_room)),
      (v_fleet, v_player, 2, 'SAIL OUT',    'SAIL', jsonb_build_object('dest', v_cad)),
      (v_fleet, v_player, 3, 'SELL ALL',    'SELL', jsonb_build_object('good', v_sal, 'qty_mode', 'ALL')),
      (v_fleet, v_player, 4, 'SAIL HOME',   'SAIL', jsonb_build_object('dest', v_lis));

    perform cmd.advance(v_fleet);   -- BUY executes, SAIL departs, the rest waits for landfall.

    -- Backdate whatever voyage is running until its ETA is in the past, then settle: this is the
    -- offline player, for whom no tick ran while the fleet was at sea. Arrival runs the queue on,
    -- which departs the homeward leg, so the loop follows the fleet home rather than assuming a
    -- fixed duration — a real voyage in this world is however long its water turned out to be.
    -- settle() advances one voyage-day at a time, so a long leg takes several rounds; the loop is
    -- bounded only so a bug cannot spin forever.
    for k in 1 .. 24 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute',
             eta         = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet);
    end loop;

    select count(*) into v_events1 from public.voyage_events ve
      join public.voyages vv on vv.id = ve.voyage_id where vv.fleet_id = v_fleet;
    select ducats into v_purse1 from public.players where id = v_player;
    select water_t into v_water1 from public.ships where fleet_id = v_fleet;

    -- IDEMPOTENCE: settle four more times. Nothing may change.
    perform voyage.settle(v_fleet); perform voyage.settle(v_fleet);
    perform voyage.settle(v_fleet); perform voyage.settle(v_fleet);
    select count(*) into v_events2 from public.voyage_events ve
      join public.voyages vv on vv.id = ve.voyage_id where vv.fleet_id = v_fleet;
    select ducats into v_purse2 from public.players where id = v_player;
    if v_events1 = v_events2 and v_purse1 = v_purse2 and v_events1 >= 2 then f_idem := true; end if;

    select count(*) into v_wages from public.ledger where player_id = v_player and kind = 'WAGES';
    if v_water1 < v_water0 and v_wages >= 2 then f_burn := true; end if;

    select ducats into v_final from public.players where id = v_player;
    select f.status, p.code into v_end_status, v_end_port
      from public.fleets f left join public.ports p on p.id = f.port_id where f.id = v_fleet;
    select string_agg(o2.seq || ':' || o2.status || coalesce(' ' || o2.error_code, ''), ' ' order by o2.seq)
      into v_orders from public.orders o2 where o2.fleet_id = v_fleet;
    if v_final > v_start and v_end_status = 'DOCKED' and v_end_port = 'LIS' then
      f_session := true;
    end if;

    -- The other three verbs, so "the queue runs" is not proven on SAIL and BUY alone. They need a
    -- docked fleet, so say plainly when it is not one: an E_NOT_DOCKED from three lines down would
    -- report the verb's complaint instead of the reason the voyage never ended.
    if v_end_status is distinct from 'DOCKED' then
      raise exception '0007 self-assert FAIL: after the queue ran, the fleet is % at %, queue [%] — it should have come home and docked',
        coalesce(v_end_status, 'gone'), coalesce(v_end_port, 'sea'), coalesce(v_orders, 'none');
    end if;
    -- ON A FRESH HOUSE, DELIBERATELY. Run against the fleet that just came home, this probe was
    -- INTERMITTENT — red on two runs in four — because what that fleet has left after a voyage
    -- depends on the hazards it rolled, and hazard rolls move with the game-day. PROVISION and
    -- HIRE cost money, so a probe standing on a purse of unknown size is a probe that sometimes
    -- proves nothing and sometimes fails for a reason that is not a defect.
    --
    -- A second house is a KNOWN precondition: a Barca docked at Lisboa with 8,000 ducats, exactly
    -- as new_house() founds it. The rule from the previous project applies here too — a test must
    -- set its own precondition or follow the game, never assume the state something else left.
    v_player2 := public.new_house(v_probe2, 'Casa Verbos', 'PRT');
    select id into v_fleet2 from public.fleets where player_id = v_player2;

    v_prov := cmd.do_provision(v_fleet2, jsonb_build_object('mode', 'FULL'));
    v_hire := cmd.do_hire(v_fleet2, jsonb_build_object('count', 4));
    update public.ships set durability = 200 where fleet_id = v_fleet2;   -- give the yard something to do
    v_rep  := cmd.do_repair(v_fleet2, jsonb_build_object('to_pct', 100));
    if (v_prov->>'cost')::bigint > 0 and (v_hire->>'hired')::int = 4 and (v_rep->>'cost')::bigint > 0
       and (select crew from public.ships where fleet_id = v_fleet2) = 12
       and (select durability from public.ships where fleet_id = v_fleet2) = 400
       and (select status from public.fleets where id = v_fleet2) = 'REPAIRING' then
      f_verbs := true;
    end if;
    -- The yard releases the fleet on its own, without a tick, once busy_until has elapsed.
    update public.fleets set busy_until = now() - interval '1 second' where id = v_fleet2;
    perform cmd.advance(v_fleet2);

    -- ── HOW MUCH CAN SHE ACTUALLY BUY? Proven by BOTH edges, on a good dear enough for the purse
    --    to be what binds. One edge alone would pass on a function that always answered "one tun".
    select g.id into v_cap_good
      from public.goods g
      join public.port_goods pg on pg.good_id = g.id and pg.port_id = v_lis
     where g.bulk <= 1.0
     order by (select ask from world.price(v_lis, g.id)) desc
     limit 1;
    v_cap := public.fleet_buy_capacity(v_fleet2, v_cap_good);
    select ducats into v_cap_purse from public.players where id = v_player2;
    if (v_cap->>'bound_by') = 'purse' and (v_cap->>'max_qty')::numeric > 0 then
      select total into v_cap_total
        from world.quote(v_lis, v_cap_good, (v_cap->>'max_qty')::numeric, 'buy');
      select total into v_cap_over
        from world.quote(v_lis, v_cap_good, (v_cap->>'max_qty')::numeric + 1, 'buy');
      -- Affordable at the number offered, and NOT affordable one tun above it: that is what makes
      -- it a maximum rather than a guess. The old client-side answer failed the second half —
      -- it offered 91 tuns of pepper for a purse that could carry 50.
      if v_cap_total <= v_cap_purse and v_cap_over > v_cap_purse then
        f_cap := true;
      end if;
    end if;

    -- THE HALT RULE: an impossible order fails and the one behind it stays pending.
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values
      (v_fleet, v_player, 6, 'BUY 99999', 'BUY',
       jsonb_build_object('good', v_sal, 'qty', 99999))
      returning id into v_bad;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values
      (v_fleet, v_player, 7, 'BUY 5', 'BUY', jsonb_build_object('good', v_sal, 'qty', 5))
      returning id into v_next;
    perform cmd.advance(v_fleet);
    perform cmd.advance(v_fleet);   -- and AGAIN: a halt that only lasts one call is not a halt
    select * into o from public.orders where id = v_bad;
    if o.status = 'failed' and o.error_code = 'E_HOLD_FULL'
       and (select status from public.orders where id = v_next) = 'pending' then
      f_halt := true;
    end if;
    -- The RELEASE from that halt is CLEAR, which lives in 0008 and is proven there — a fleet that
    -- could halt but never resume would be the deadlock shape that cost the previous game a live
    -- incident, so the two halves are asserted in the two files that own them.

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_session then
    raise exception '0007 self-assert FAIL: the round trip did not end docked at Lisboa and richer — start % d., end % d., fleet % at %, queue [%]',
      v_start, v_final, v_end_status, coalesce(v_end_port, 'sea'), v_orders;
  end if;
  if not f_idem then
    raise exception '0007 self-assert FAIL: settle() is NOT idempotent — after the voyage: % events / % d.; after 4 more calls: % events / % d.',
      v_events1, v_purse1, v_events2, v_purse2;
  end if;
  if not f_burn then
    raise exception '0007 self-assert FAIL: the voyage burned no stores (water % -> %) or paid wages only % time(s)', v_water0, v_water1, v_wages;
  end if;
  if not f_cap then
    raise exception '0007 self-assert FAIL: fleet_buy_capacity is not a real maximum — % (purse % d.); % at the max and % one tun over',
      v_cap, v_cap_purse, v_cap_total, v_cap_over;
  end if;
  if not f_verbs then
    raise exception '0007 self-assert FAIL: PROVISION / HIRE / REPAIR did not all take effect (provision %, hire %, repair %)', v_prov, v_hire, v_rep;
  end if;
  if not f_halt then
    raise exception '0007 self-assert FAIL: an impossible order did not HALT the queue (status %, code %)', o.status, o.error_code;
  end if;

  select count(*) into n from public.orders;
  if n <> 0 then raise exception '0007 self-assert FAIL: % order row(s) survived the probe subtransaction', n; end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0007 self-assert FAIL: the queue minted % client write grant(s)', v_grants; end if;

  raise notice '0007 self-assert ok: a full session ran as a 4-order queue with NO tick — bought 50 tuns of % at Lisboa, sailed to % and back (% nm each way), settled % voyage-day checkpoint(s) lazily, and docked at Lisboa with % d. against a start of % d. (+% d.); 4 more settle() calls changed nothing (% events, % d.); stores fell % -> % t and % wage payment(s) landed; on a second, freshly founded house PROVISION cost % d., HIRE took 4 hands and REPAIR restored the hull to 400 and put her in the yard; the most she can buy of the dearest good is % tun(s) (bound by the purse: affordable at that, too dear one tun over); an impossible order failed E_HOLD_FULL and left the next order pending across TWO advances; 0 client write grants',
    (select name from public.goods where id = v_sal),
    (select name from public.ports where id = v_cad),
    (select round(min(l.distance_nm), 1) from public.legs l
      where (l.from_port_id = v_lis and l.to_port_id = v_cad) or (l.from_port_id = v_cad and l.to_port_id = v_lis)),
    v_events1, v_final, v_start, v_final - v_start, v_events2, v_purse2, v_water0, v_water1, v_wages,
    (v_cap->>'max_qty'), (v_prov->>'cost');
end $$;
