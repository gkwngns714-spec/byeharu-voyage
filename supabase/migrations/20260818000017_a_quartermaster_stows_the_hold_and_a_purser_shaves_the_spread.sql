-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0017 — A QUARTERMASTER STOWS THE HOLD, AND A PURSER SHAVES THE SPREAD
--        Two of 0015's three inert specialties are wired to real rules. The SURGEON stays inert,
--        deliberately and out loud.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT 0015 PROMISED, VERBATIM, IN ITS OWN HEADER ────────────────────────────────────────────
--   NAVIGATOR     -> voyage.fleet_speed()   READ. Superseded.
--   QUARTERMASTER -> hold                   NOT READ YET. Attaches where cargo capacity is summed.
--   SURGEON       -> crew loss              NOT READ YET. Attaches in voyage.report_line (0007).
--   PURSER        -> price/haggling         NOT READ YET. Attaches in world.quote (0005).
--
-- Three quarters of a table of officers was decoration, and `world.officers()` said so on every
-- card. This file makes two of the three true and leaves the third saying so.
--
-- ── WHAT CURRENTLY SAYS THE OPPOSITE, NAMED ────────────────────────────────────────────────────
--
-- "HOW MUCH FITS IN THIS HULL?" HAD FOUR ANSWERS ON THE SERVER AND THREE MORE ON THE CLIENT. All
-- seven read `ship_classes.hold` and re-derive the same subtraction by hand:
--
--   public.fleet_free_hold          0007:127   sum(greatest(0, c.hold - cargo - water - food))
--   public.fleet_load               0007:249   c.hold - public.ship_cargo_tuns(s.id) - water - food
--   cmd.do_provision                0007:579   least(r.hold - r.cargo_t, ...)   (and again at :583,
--                                              :609, :613 — the same expression four times in one
--                                              function body)
--   world.fleets                    0009:183   'hold', c.hold                   (served to the UI)
--   src/domain/fleet/derive.ts:40              Math.max(0, ship.hold - shipHoldUsed(ship))
--   src/features/command/fleetLimits.ts:31     Σ max(0, hold − cargo_tuns − water_t − food_t)
--   src/features/market/MarketScreen.tsx:687   Σ max(0, hold − cargo_tuns)      -- ALREADY DRIFTED:
--                                              this one forgets the stores and has been wrong since
--                                              it was written.
--
-- That is spaghetti — one rule, seven hand-copies, one of them already disagreeing — and adding a
-- quartermaster term to any single copy would have made six of them lie. So the FIRST thing this
-- file does is mint ONE authority for the question and compose every SERVER-side reader onto it.
-- The three client copies are outside this migration's file domain; they are reported, not touched,
-- and the read they draw from is corrected below so that the two honest ones become right again by
-- construction (see `world.fleets()`).
--
-- ── THE ONE AUTHORITY: public.ship_hold_capacity(ship) ─────────────────────────────────────────
-- Hold is a fact about a SHIP; an officer is posted to a FLEET. The join is made in exactly one
-- place: `ship_hold_capacity` reads the ship's own `fleet_id` and asks
-- `public.fleet_officer_bonus(fleet, 'QUARTERMASTER')` — the one reading minted by 0015, which sums
-- within a specialty and clamps at `officer_bonus_cap_pct`. Nothing here sums `bonus_pct` itself.
--
-- It FLOORS: a hull holds a whole number of tuns, `ship_classes.hold` is an `int`, and flooring is
-- what makes the no-op EXACT rather than merely equal-looking — floor(60 × (1 + 0)) is the integer
-- 60, not 60.0000000000.
--
-- ── WHY fleet_free_hold AND fleet_load HAD TO MOVE TOGETHER ────────────────────────────────────
-- `cmd.do_buy` (0007:446) checks room with `fleet_free_hold`, pays for `q.units`, and then calls
-- `fleet_load` (0007:478), which places cargo using its OWN copy of the free-space arithmetic and
-- returns how much actually went aboard. do_buy charges `q.total` either way. Wire the quartermaster
-- into the check and not into the placement and the player pays for tuns that silently never land.
-- Both compose onto `ship_hold_capacity` here, in one slice, or neither would have.
--
-- ── WHAT THE QUARTERMASTER DELIBERATELY DOES *NOT* TOUCH ───────────────────────────────────────
-- `voyage.ship_speed` (0006:351) reads `c.hold` too — as the DENOMINATOR of how laden she is, not
-- as an answer to how much fits. It keeps the rated hull, on purpose:
--   * a quartermaster wins usable STOWAGE, not a bigger ship; and
--   * `least(1.0, ...)` already clamps, so an over-stowed hull is simply "fully laden" and no
--     faster for it.
-- The consequence that matters is that the quartermaster cannot move a speed figure. Speed has one
-- owner — the NAVIGATOR of 0015 — and this file does not open a second door to it.
--
-- ── PURSER: world.quote(), NOT world.spread() ──────────────────────────────────────────────────
-- REJECTED: making `world.spread(port)` player-aware. The spread is a property of the PORT — 0005
-- derives it from `dev_commerce` alone — and it is read by `world.price()` (0005:376) and served
-- into `world.market()` (0009:124) as the port's own published figure. Giving it a fleet argument
-- would change a pure world fact into a per-caller one, break both callers, and make the number the
-- market screen prints depend on who is looking at it. A house's purser does not narrow the
-- harbour's spread; he gets a better fill inside it.
--
-- CHOSEN: `world.quote()`, which is where a trade is actually priced and the only price the money
-- moves at (0013's header says so in as many words). It gains ONE trailing parameter,
-- `p_fleet uuid default null`, and the purser shaves the spread the QUOTE executes at:
--
--     v_spread := world.spread(p_port) * (1 - purser_bonus)
--
-- so the ask falls and the bid rises, symmetrically, by the stated fraction of the half-spread.
-- `world.spread()` itself is untouched and the port still publishes one number.
--
-- The parameter is APPENDED and defaulted, so every existing 4- and 5-argument call still compiles
-- and still prices exactly as before. It could not be added with `create or replace`: a different
-- arity makes an OVERLOAD, not a replacement, and the old 4-argument calls would then be ambiguous
-- against the new defaults ("function is not unique"). So the old function is DROPPED and the new
-- one created, and its grant is re-issued explicitly — a dropped function takes its ACL with it.
--
-- No caller outside this chain is affected: the client never calls `quote` (it is absent from
-- `src/lib/rpc/catalog.ts`; the composer asks `world.buy_capacity` instead), and
-- `scripts/db/proofs/05_first_voyage_balance.sql:102,109` calls it with four arguments, which the
-- defaults still satisfy.
--
-- The three callers that DO know a fleet are superseded to pass it — `public.fleet_buy_capacity`
-- (0007:198), `cmd.do_buy` (0007:462) and `cmd.do_sell` (0007:529) — because 0007's own header
-- records what happens when the number offered and the number charged are computed differently.
--
-- A client may call `world.quote` with any fleet id it likes; that discloses nothing but a price it
-- could not trade at, since every money-moving path reads the fleet from the server's own row.
--
-- ── SURGEON: STILL INERT, AND STILL SAYING SO ──────────────────────────────────────────────────
-- Crew loss lives in `voyage.report_line()` (0007), tangled with the hazard prose and the wage and
-- ration arithmetic that `scripts/db/proofs/01_offline_equivalence.sql` matches to the character. It
-- is a bigger design question than a coefficient, so nothing here pretends otherwise:
-- `world.officers()` is superseded so `specialties_read` reads exactly
-- ['NAVIGATOR','QUARTERMASTER','PURSER'] and every SURGEON card still prints "No rule reads this yet".
--
-- 0016's HAGGLING skill also attaches at `world.quote` and is ALSO still unwired; this file does not
-- quietly light it, and the self-assert checks that `world.skills()` still says so.
--
-- ── THE GRANT HOLE THIS FILE WALKED INTO (found by writing the posture assert) ─────────────────
-- The first draft asserted, as README §3 asks, that `authenticated` may NOT execute
-- `public.fleet_free_hold`. IT FAILED ON APPLY. Measured on PostgreSQL 18.3 with the chain applied
-- through 0016 and `scripts/db/supabase-preamble.sql` in place:
--
--     pg_default_acl holds THREE rows, all owned by grantor supabase_admin. There is NO row for
--     the role that applies this chain.
--
-- So 0001:239 —
--     alter default privileges in schema public, world, cmd, voyage
--       revoke execute on functions from public, anon, authenticated;
-- — recorded NOTHING, and every function created since that did not carry its own explicit
-- `revoke` was left at PostgreSQL's built-in function default, which is EXECUTE FOR PUBLIC.
-- (0001's assert (d) reads `pg_default_acl` for leaks; an entry that was never written is not a
-- leak it can see, and the tables half of the same statement is harmless because the built-in
-- default for a TABLE grants nobody anything. Only functions were exposed.)
--
-- Counted the same way: 22 SECURITY DEFINER functions that WRITE are executable by `anon` today,
-- among them `public.fleet_load`, `public.fleet_unload`, `cmd.do_buy`, `cmd.do_sail`,
-- `cmd.execute_order`, `voyage.depart` and `cmd.advance` — every one taking a fleet id and none of
-- them checking who is asking, because 0007 and 0008 rely on `cmd.issue` doing that upstream.
--
-- THAT IS NOT THIS MIGRATION'S CONCEPT AND IT IS NOT FIXED HERE WHOLESALE. Re-granting the whole
-- chain is its own slice, and a blanket revoke written blind is how a deploy takes the game
-- offline. What this file does is refuse to re-cut a function and leave it open:
--
--   * every function 0017 creates or supersedes gets an explicit `revoke ... from public, anon,
--     authenticated`, and the two the client really calls (`world.quote`, `world.fleets`) get an
--     explicit `grant ... to authenticated` back. Seven of the 22 close here, including the two
--     rawest — `public.fleet_load` and `cmd.do_buy`.
--   * the self-assert PROVES those, and then NOTICEs the count and the names of the ones still
--     open, on every apply — 0001's (d2) shape: never swallowed, never fatal, and never quietly
--     turned into an assert that would block every deploy for a condition it cannot repair.
--
-- ── THE NO-OP IS THE POINT ─────────────────────────────────────────────────────────────────────
-- With no officer posted, `fleet_officer_bonus` returns exactly 0, so the hold multiplier is exactly
-- 1 and the spread multiplier is exactly 1. Every figure 0006/0007/0009 published still holds and
-- the five proofs — which sail an UNOFFICERED captain — are unaffected. That is proven below by
-- recomputing the pre-existing definitions inline and demanding equality, not asserted in prose.
--
-- Depends ONLY on: 0001-0016 (fleet_officer_bonus + officers 0015, ships/ship_classes 0002/0004,
-- fleet_free_hold/fleet_load/do_buy/do_sell/do_provision 0007, world.quote/spread/mid_price 0005,
-- world.fleets 0009, current_player_id 0004).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE ONE ANSWER TO "HOW MANY TUNS FIT IN THIS HULL?" ────────────────────────────────────────
create or replace function public.ship_hold_capacity(p_ship uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- The rated hull, stretched by the quartermasters posted to the fleet this ship serves in.
  -- fleet_officer_bonus (0015) is the ONLY reading of what officers are worth: it sums within the
  -- specialty and clamps at officer_bonus_cap_pct. Nothing here sums bonus_pct itself.
  -- FLOOR, because a hull holds whole tuns and because floor(hold x 1) is the int back, exactly.
  select floor(c.hold * (1 + public.fleet_officer_bonus(s.fleet_id, 'QUARTERMASTER')))
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship
$$;

comment on function public.ship_hold_capacity(uuid) is
  'THE one answer to "how many tuns fit in this hull" — the rated ship_classes.hold plus the '
  'quartermasters posted to her fleet (0017). Every server-side reader of capacity composes onto '
  'this; nothing re-derives it. voyage.ship_speed deliberately keeps the RATED hull, because that '
  'one asks how laden she is, not how much fits.';

revoke all on function public.ship_hold_capacity(uuid) from public, anon, authenticated;

-- ── SUPERSEDES 0007:120. Same sum, asking the one authority instead of re-deriving it. ─────────
create or replace function public.fleet_free_hold(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(greatest(0, public.ship_hold_capacity(s.id)
                                  - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t)), 0)
    from public.ships s
   where s.fleet_id = p_fleet
$$;

comment on function public.fleet_free_hold(uuid) is
  'Room for the next parcel, across the fleet. Supersedes the 0007 definition, which re-derived the '
  'per-hull capacity inline; identical to it when no quartermaster is posted.';

revoke all on function public.fleet_free_hold(uuid) from public, anon, authenticated;

-- ── SUPERSEDES 0007:234. The placement must agree with the check, or a player pays for cargo ────
-- that never goes aboard.
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
  -- would do and what keeps the small hulls free for the next parcel. "Largest" is now the STOWED
  -- capacity rather than the rated one, so the order and the room come from the same reading.
  for r in select s.id,
                  public.ship_hold_capacity(s.id) as cap,
                  public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)
                    - s.water_t - s.food_t as free
             from public.ships s
            where s.fleet_id = p_fleet order by cap desc loop
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

comment on function public.fleet_load(uuid, text, numeric) is
  'THE cargo mover. Supersedes 0007: the per-hull room now comes from public.ship_hold_capacity, '
  'the same reading public.fleet_free_hold uses, so what was checked and what is placed cannot '
  'disagree.';

-- AND IT IS TAKEN OFF THE CLIENT. See "THE GRANT HOLE THIS FILE WALKED INTO" in the header: this
-- SECURITY DEFINER function WRITES cargo into any ship, and until this line `anon` could call it.
revoke all on function public.fleet_load(uuid, text, numeric) from public, anon, authenticated;

-- ── SUPERSEDES 0007:550. Stores live in the hold too. ──────────────────────────────────────────
-- Four copies of `r.hold - r.cargo_t` become four calls to the one authority. The rest of the body
-- is 0007's, unchanged.
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

  for r in select s.id, s.crew, s.water_t, s.food_t, s.store_ratio,
                  public.ship_hold_capacity(s.id) as hold,
                  public.ship_cargo_tuns(s.id) as cargo_t
             from public.ships s
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

  for r in select s.id, s.crew, s.water_t, s.food_t, s.store_ratio,
                  public.ship_hold_capacity(s.id) as hold,
                  public.ship_cargo_tuns(s.id) as cargo_t
             from public.ships s
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

revoke all on function cmd.do_provision(uuid, jsonb) from public, anon, authenticated;

-- ── SUPERSEDES 0005:387 — and it has to be a DROP, see the header. ─────────────────────────────
drop function if exists world.quote(uuid, uuid, numeric, text, numeric);

create or replace function world.quote(
  p_port uuid, p_good uuid, p_qty numeric, p_side text,
  p_limit numeric default null, p_fleet uuid default null
)
returns table (units numeric, total bigint, avg_price numeric, end_stock numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_stock  numeric;
  v_spread numeric;
  v_purser numeric;
  v_tax    numeric;
  v_left   numeric := p_qty;
  v_n      numeric;
  v_mid    numeric;
  v_unit   numeric;
  v_units  numeric := 0;
  v_total  numeric := 0;
begin
  if p_side not in ('buy', 'sell') then
    raise exception 'world.quote: side must be buy or sell, got %', p_side using errcode = '22023';
  end if;

  select pg.stock into v_stock from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good;
  if v_stock is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  -- 0017: the PURSER. The port still publishes ONE spread (world.spread is untouched and still
  -- takes no player); what a house's purser wins is a better fill inside it, on both sides. With no
  -- fleet named, or none posted, this is a multiplication by exactly 1 and the arithmetic below is
  -- 0005's to the digit.
  v_purser := case when p_fleet is null then 0
                   else public.fleet_officer_bonus(p_fleet, 'PURSER') end;
  v_spread := world.spread(p_port) * (1 - v_purser);
  v_tax    := world.tax_rate(p_port);

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
  -- average." The loop IS the price impact; there is no separate impact formula to drift from it.
  while v_left > 0 loop
    v_n := least(v_step, v_left);
    if p_side = 'buy' then
      if v_stock < v_n then v_n := v_stock; end if;
      exit when v_n <= 0;
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock - v_n;
    else
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);
      exit when p_limit is not null and v_unit < p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock + v_n;
    end if;
    v_units := v_units + v_n;
    v_left  := v_left - v_n;
  end loop;

  units     := v_units;
  total     := round(v_total)::bigint;
  avg_price := case when v_units > 0 then round(v_total / v_units, 2) else null end;
  end_stock := v_stock;
  return next;
end $$;

comment on function world.quote(uuid, uuid, numeric, text, numeric, uuid) is
  'THE stepped execution price, and the only price the money moves at. Supersedes the 0005 '
  'definition with one appended parameter: name the fleet and her PURSER shaves the spread this '
  'quote executes at (0017). Omit it, or post no purser, and it is 0005 exactly.';

revoke all on function world.quote(uuid, uuid, numeric, text, numeric, uuid) from public, anon;
grant execute on function world.quote(uuid, uuid, numeric, text, numeric, uuid) to authenticated;

-- ── SUPERSEDES 0007:150. The number OFFERED must be priced the way the number CHARGED is. ──────
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

  -- Then the purse, at the price she would really pay — 0017: including her own purser's, which is
  -- why p_fleet is passed. A ceiling quoted without the purser would under-offer a house that has
  -- one, and 0007's header records what happens when the offer and the charge are computed apart.
  while v_qty > 0 loop
    select * into q from world.quote(f.port_id, p_good, v_qty, 'buy', null, p_fleet);
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

-- The client asks `world.buy_capacity` (0009), which checks ownership first and then calls this.
-- This one takes any fleet id at all, so it is not the client's to call.
revoke all on function public.fleet_buy_capacity(uuid, uuid) from public, anon, authenticated;

-- ── SUPERSEDES 0007:412 and 0007:492 — the two verbs that move money at a quote. ───────────────
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

  -- 0017: priced through this fleet's own purser.
  select * into q from world.quote(f.port_id, g.id, v_qty, 'buy',
                                   nullif((p_args->>'limit'), '')::numeric, p_fleet);
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

  -- 0017: the purser lifts the bid as much as he shaves the ask.
  select * into q from world.quote(f.port_id, g.id, v_qty, 'sell',
                                   nullif((p_args->>'limit'), '')::numeric, p_fleet);
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

-- Neither verb checks who is calling — 0007 relies on `cmd.issue` doing that and then reaching them
-- as the definer. They were reachable directly by `anon`, which made "the fleet must be yours" a
-- rule with no lock on it. Both are taken off the client here.
revoke all on function cmd.do_buy(uuid, jsonb)  from public, anon, authenticated;
revoke all on function cmd.do_sell(uuid, jsonb) from public, anon, authenticated;

-- ── SUPERSEDES 0009:149. The read has to tell the truth about capacity, or the screens lie. ────
-- `hold` keeps its meaning — "how many tuns fit" — and therefore now carries the quartermaster.
-- That is deliberate rather than a new key: three client files compute free space as
-- `hold − used` (src/domain/fleet/derive.ts:40, src/features/command/fleetLimits.ts:31,
-- src/features/market/MarketScreen.tsx:687), and serving the effective figure under the name they
-- already read is what keeps their arithmetic true without touching them. The rated hull is added
-- alongside as `hold_rated` so a card can still show what the shipwright built, and `officer_pct`
-- says, per specialty, what the fleet's officers are actually worth.
create or replace function world.fleets()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  r        record;
begin
  if v_player is null then return '[]'::jsonb; end if;

  -- DESIGN D.2: the read is the catch-up. Nine hours offline resolve here, in order, before a
  -- single number is reported.
  for r in select id from public.fleets where player_id = v_player loop
    perform voyage.settle(r.id);
  end loop;

  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'name', f.name, 'status', f.status, 'version', f.version,
    'port', (select code from public.ports where id = f.port_id),
    'busy_until', f.busy_until,
    'speed_kn', voyage.fleet_speed(f.id),
    'endurance_days', round(voyage.endurance_days(f.id), 1),
    'free_hold', public.fleet_free_hold(f.id),
    'officer_pct', jsonb_build_object(
        'NAVIGATOR',     round(public.fleet_officer_bonus(f.id, 'NAVIGATOR')     * 100, 2),
        'QUARTERMASTER', round(public.fleet_officer_bonus(f.id, 'QUARTERMASTER') * 100, 2),
        'SURGEON',       round(public.fleet_officer_bonus(f.id, 'SURGEON')       * 100, 2),
        'PURSER',        round(public.fleet_officer_bonus(f.id, 'PURSER')        * 100, 2)),
    'voyage', (select jsonb_build_object(
                 'id', v.id, 'to', (select code from public.ports where id = v.dest_port_id),
                 'eta', v.eta, 'total_nm', v.total_nm,
                 'nm_done', voyage.progress_nm(v.id),
                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))
                 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'),
    'ships', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', s.id, 'name', s.name, 'class', c.name, 'is_flagship', s.is_flagship,
                 'durability', s.durability, 'max_durability', c.durability,
                 'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
                 'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
                 'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
                 'water_t', s.water_t, 'food_t', s.food_t) order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s join public.ship_classes c on c.id = s.class_id
                where s.fleet_id = f.id),
    'queue', cmd.queue(f.id)) order by f.created_at), '[]'::jsonb)
    from public.fleets f where f.player_id = v_player);
end $$;

revoke all on function world.fleets() from public, anon;
grant execute on function world.fleets() to authenticated;

-- ── SUPERSEDES 0015:291. Two of the three inert specialties are now read; one still is not. ────
create or replace function world.officers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  -- The specialties the RULES actually read today. 0017 added QUARTERMASTER (public.
  -- ship_hold_capacity) and PURSER (world.quote). SURGEON is absent on purpose: crew loss lives in
  -- voyage.report_line and is a design question, not a coefficient.
  v_read   constant text[] := array['NAVIGATOR', 'QUARTERMASTER', 'PURSER'];
begin
  return jsonb_build_object(
    'bonus_cap_pct', public.wc_num('officer_bonus_cap_pct'),
    'specialties_read', to_jsonb(v_read),
    'officers', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', o.code, 'name', o.name, 'specialty', o.specialty,
               'bonus_pct', o.bonus_pct, 'wage', o.wage_ducats, 'blurb', o.blurb,
               'port', p.code, 'nation', n.code,
               -- Said out loud, per row: a bonus nothing reads must not look like one that works.
               'takes_effect', (o.specialty = any(v_read)),
               'hired', (po.id is not null),
               'fleet', f.name
             ) order by o.specialty, o.code), '[]'::jsonb)
        from public.officers o
        left join public.ports p on p.id = o.home_port_id
        left join public.nations n on n.id = o.nation_id
        left join public.player_officers po
               on po.officer_id = o.id and po.player_id = v_player
        left join public.fleets f on f.id = po.fleet_id));
end $$;

comment on function world.officers() is
  'The roster, and which of them this house has signed. Carries `takes_effect` per officer. After '
  '0017 three of the four specialties are read by a rule; SURGEON is still not, and still says so.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe    constant uuid := '00000000-0017-4000-8000-000000000001';
  -- posture
  v_fn       text;
  v_open     int;
  v_names    text;
  v_grants   int;
  v_players  int;
  v_left     int;
  v_cap_now  numeric;
  v_cap_end  numeric;
  -- the probe world
  v_player   uuid;
  v_fleet    uuid;
  v_ship     uuid;
  v_port     uuid;
  v_good     uuid;
  v_code     text;
  v_bulk     numeric;
  v_stock    numeric;
  v_qty      numeric;
  v_step     numeric;
  -- QUARTERMASTER
  v_rated    int;
  v_hold0    numeric;
  v_hold1    numeric;
  v_hold2    numeric;
  v_free0    numeric;
  v_free1    numeric;
  v_inline0  numeric;
  v_qm       numeric;
  v_qm2      numeric;
  v_placed   numeric;
  v_overflow numeric;
  v_qm_txt   text;
  v_qm2_txt  text;
  -- PURSER
  v_mid      numeric;
  v_tax      numeric;
  v_spread   numeric;
  v_pu       numeric;
  v_pu2      numeric;
  v_pu_txt   text;
  v_ask0     numeric;
  v_ask1     numeric;
  v_bid0     numeric;
  v_bid1     numeric;
  v_ask2     numeric;
  q_plain    record;
  q_fleet0   record;
  q_buy      record;
  q_sell0    record;
  q_sell1    record;
  q_cap      record;
  -- reads
  v_fl       jsonb;
  v_shipjson jsonb;
  v_roster   jsonb;
  v_skills   jsonb;
  v_hire     jsonb;
begin
  -- ── POSTURE, outside anything that rolls back ────────────────────────────────────────────────
  -- world.quote was DROPPED and recreated, so its ACL was rebuilt from scratch; check both ends.
  if has_function_privilege('anon', 'world.quote(uuid, uuid, numeric, text, numeric, uuid)', 'execute') then
    raise exception '0017 self-assert FAIL: anon may execute world.quote()';
  end if;
  if not has_function_privilege('authenticated', 'world.quote(uuid, uuid, numeric, text, numeric, uuid)', 'execute') then
    raise exception '0017 self-assert FAIL: authenticated may NOT execute world.quote() — the drop took its grant and it was not re-issued';
  end if;
  if not has_function_privilege('authenticated', 'world.fleets()', 'execute') then
    raise exception '0017 self-assert FAIL: authenticated may NOT execute world.fleets() — the revoke took the grant with it';
  end if;
  if has_function_privilege('anon', 'world.fleets()', 'execute') then
    raise exception '0017 self-assert FAIL: anon may execute world.fleets()';
  end if;
  -- Every function this file creates or supersedes is off the client. See "THE GRANT HOLE THIS
  -- FILE WALKED INTO": before 0017 all seven of these were executable by anon, and two of them
  -- write. Named one at a time rather than counted, so the message says WHICH.
  foreach v_fn in array array[
      'public.ship_hold_capacity(uuid)',
      'public.fleet_free_hold(uuid)',
      'public.fleet_load(uuid, text, numeric)',
      'public.fleet_buy_capacity(uuid, uuid)',
      'cmd.do_buy(uuid, jsonb)',
      'cmd.do_sell(uuid, jsonb)',
      'cmd.do_provision(uuid, jsonb)'] loop
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0017 self-assert FAIL: a client role may still execute %, which 0017 re-cut and was supposed to take off the client', v_fn;
    end if;
  end loop;
  -- the old 5-argument quote must be GONE, not sitting beside the new one as an overload
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'world' and p.proname = 'quote') <> 1 then
    raise exception '0017 self-assert FAIL: world.quote has % overload(s); the 0005 definition was not dropped',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'world' and p.proname = 'quote');
  end if;
  -- world.spread was NOT made player-aware: it still takes exactly one argument.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'world' and p.proname = 'spread' and p.pronargs = 1) <> 1 then
    raise exception '0017 self-assert FAIL: world.spread(port) is no longer the one-argument port fact it was';
  end if;

  select public.wc_num('officer_bonus_cap_pct') into v_cap_now;
  select public.wc_num('trade_step_tuns') into v_step;

  -- ── THE ROLLED-BACK PROBE ────────────────────────────────────────────────────────────────────
  begin
    perform cmd.assume_identity(v_probe);
    v_player := public.new_house(v_probe, 'Casa da Estiva', 'PRT');
    select f.id, f.port_id into v_fleet, v_port
      from public.fleets f where f.player_id = v_player limit 1;
    select s.id, c.hold into v_ship, v_rated
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_fleet limit 1;
    if v_ship is null or v_port is null then
      raise exception '0017 self-assert FAIL: the probe house opened with no ship or no port';
    end if;

    -- Find the subject by QUERY, never by literal: the dearest good actually traded at this port
    -- with enough stock for a single 10-tun step. A dear good is chosen so that shaving 6 per cent
    -- off the half-spread moves the rounded unit price by more than a cent — otherwise the purser
    -- assert below could pass while doing nothing.
    select g.id, g.code, g.bulk, pg.stock
      into v_good, v_code, v_bulk, v_stock
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     where pg.port_id = v_port
       and p.culture <> all(g.culture_mask)
       and pg.stock >= v_step
     order by world.mid_price(pg.port_id, pg.good_id, pg.stock) desc
     limit 1;
    if v_good is null then
      raise exception '0017 self-assert FAIL: the probe port offers no good with % tuns in stock, so nothing below could be checked', v_step;
    end if;
    v_qty := v_step;   -- exactly one price step, so avg_price IS the unit price

    -- ══ (a) QUARTERMASTER, THE NO-OP ═════════════════════════════════════════════════════════
    v_qm := public.fleet_officer_bonus(v_fleet, 'QUARTERMASTER');
    if v_qm <> 0 then
      raise exception '0017 self-assert FAIL: an unofficered fleet reported a quartermaster bonus of %', v_qm;
    end if;
    v_hold0 := public.ship_hold_capacity(v_ship);
    if v_hold0::text <> v_rated::text then
      raise exception '0017 self-assert FAIL: with no quartermaster the capacity reads % and the rated hull is % — the supersede is not a no-op', v_hold0, v_rated;
    end if;
    -- 0007's own definition, recomputed inline. Equality here is what makes "identical without
    -- officers" a measurement rather than a claim.
    select coalesce(sum(greatest(0, c.hold - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t)), 0)
      into v_inline0
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_fleet;
    v_free0 := public.fleet_free_hold(v_fleet);
    if v_free0 <> v_inline0 then
      raise exception '0017 self-assert FAIL: free hold reads % where 0007''s definition gives %', v_free0, v_inline0;
    end if;
    if v_free0 <= 0 then
      raise exception '0017 self-assert FAIL: the probe fleet has no free hold, so every capacity check below would be vacuous';
    end if;

    -- ══ (b) PURSER, THE NO-OP ════════════════════════════════════════════════════════════════
    v_mid    := world.mid_price(v_port, v_good, v_stock);
    v_tax    := world.tax_rate(v_port);
    v_spread := world.spread(v_port);
    v_ask0   := round(v_mid * (1 + v_tax + v_spread / 2), 2);
    v_bid0   := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);

    select * into q_plain  from world.quote(v_port, v_good, v_qty, 'buy');
    select * into q_fleet0 from world.quote(v_port, v_good, v_qty, 'buy', null, v_fleet);
    if q_plain.avg_price <> v_ask0 then
      raise exception '0017 self-assert FAIL: an unnamed quote priced % where 0005''s ask is %', q_plain.avg_price, v_ask0;
    end if;
    if q_fleet0.units <> q_plain.units or q_fleet0.total <> q_plain.total
       or q_fleet0.avg_price <> q_plain.avg_price or q_fleet0.end_stock <> q_plain.end_stock then
      raise exception '0017 self-assert FAIL: naming an unpursered fleet changed the quote (% / % vs % / %)',
        q_fleet0.units, q_fleet0.total, q_plain.units, q_plain.total;
    end if;
    select * into q_sell0 from world.quote(v_port, v_good, v_qty, 'sell', null, v_fleet);
    if q_sell0.avg_price <> v_bid0 then
      raise exception '0017 self-assert FAIL: an unpursered sell bid % where 0005''s bid is %', q_sell0.avg_price, v_bid0;
    end if;

    -- and the READ is a no-op too: world.fleets serves the rated hull under `hold` when nobody
    -- has been signed on.
    v_fl := world.fleets();
    v_shipjson := (select e from jsonb_array_elements(v_fl->0->'ships') e
                    where (e->>'id')::uuid = v_ship);
    if (v_shipjson->>'hold') <> v_rated::text or (v_shipjson->>'hold_rated') <> v_rated::text then
      raise exception '0017 self-assert FAIL: world.fleets served hold=% hold_rated=% for a rated hull of %',
        v_shipjson->>'hold', v_shipjson->>'hold_rated', v_rated;
    end if;

    -- ══ (c) QUARTERMASTER, BY THE STATED AMOUNT ══════════════════════════════════════════════
    v_hire := cmd.hire_officer('ALCANT', v_fleet);        -- Inês de Alcântara, QUARTERMASTER 6.00
    if not (v_hire->>'ok')::boolean then
      raise exception '0017 self-assert FAIL: hiring the quartermaster was refused: %', v_hire;
    end if;
    v_qm     := public.fleet_officer_bonus(v_fleet, 'QUARTERMASTER');
    v_qm_txt := round(v_qm * 100, 2)::text || '%';
    if v_qm <> (select bonus_pct from public.officers where code = 'ALCANT') / 100.0 then
      raise exception '0017 self-assert FAIL: one quartermaster is worth % and her card says %',
        v_qm, (select bonus_pct from public.officers where code = 'ALCANT');
    end if;

    v_hold1 := public.ship_hold_capacity(v_ship);
    if v_hold1 <> floor(v_rated * (1 + v_qm)) then
      raise exception '0017 self-assert FAIL: a +% quartermaster took a % tun hull to % and floor(% x (1+%)) is %',
        v_qm_txt, v_rated, v_hold1, v_rated, v_qm, floor(v_rated * (1 + v_qm));
    end if;
    if v_hold1 <= v_hold0 then
      raise exception '0017 self-assert FAIL: a quartermaster added no stowage (% -> %)', v_hold0, v_hold1;
    end if;

    v_free1 := public.fleet_free_hold(v_fleet);
    if v_free1 <> v_free0 + (v_hold1 - v_hold0) then
      raise exception '0017 self-assert FAIL: free hold went % -> % for a capacity gain of %',
        v_free0, v_free1, v_hold1 - v_hold0;
    end if;

    -- THE SEAM. fleet_load must place exactly what fleet_free_hold says fits; do_buy pays for the
    -- quote either way, so a disagreement here is a player paying for cargo that never lands.
    v_placed   := public.fleet_load(v_fleet, v_code, floor(v_free1 / v_bulk));
    v_overflow := public.fleet_load(v_fleet, v_code, 1);
    if v_placed <> floor(v_free1 / v_bulk) then
      raise exception '0017 self-assert FAIL: free hold offered % tuns of % and fleet_load placed %',
        floor(v_free1 / v_bulk), v_code, v_placed;
    end if;
    if v_overflow <> 0 then
      raise exception '0017 self-assert FAIL: one tun past a full hold still went aboard (% placed), so the placement check is not real', v_overflow;
    end if;
    if public.fleet_free_hold(v_fleet) >= v_bulk then
      raise exception '0017 self-assert FAIL: after loading to capacity there are still % tuns free', public.fleet_free_hold(v_fleet);
    end if;

    -- and the read follows the rule
    v_fl := world.fleets();
    v_shipjson := (select e from jsonb_array_elements(v_fl->0->'ships') e
                    where (e->>'id')::uuid = v_ship);
    if (v_shipjson->>'hold')::numeric <> v_hold1 or (v_shipjson->>'hold_rated') <> v_rated::text then
      raise exception '0017 self-assert FAIL: world.fleets served hold=% for a stowed capacity of % (rated %)',
        v_shipjson->>'hold', v_hold1, v_rated;
    end if;
    if (v_fl->0->'officer_pct'->>'QUARTERMASTER')::numeric <> round(v_qm * 100, 2) then
      raise exception '0017 self-assert FAIL: world.fleets reports a quartermaster worth % and the rule reads %',
        v_fl->0->'officer_pct'->>'QUARTERMASTER', round(v_qm * 100, 2);
    end if;

    -- ══ (d) PURSER, BY THE STATED AMOUNT ═════════════════════════════════════════════════════
    v_hire := cmd.hire_officer('FUGGER', v_fleet);        -- Matthias Fugger, PURSER 6.00
    if not (v_hire->>'ok')::boolean then
      raise exception '0017 self-assert FAIL: hiring the purser was refused: %', v_hire;
    end if;
    v_pu     := public.fleet_officer_bonus(v_fleet, 'PURSER');
    v_pu_txt := round(v_pu * 100, 2)::text || '%';
    v_ask1   := round(v_mid * (1 + v_tax + v_spread * (1 - v_pu) / 2), 2);
    v_bid1   := round(v_mid * (1 - v_spread * (1 - v_pu) / 2) * (1 - v_tax), 2);
    -- The precondition, stated so this cannot pass while doing nothing: the shave must be worth at
    -- least a whole ducat-cent on the good the probe picked.
    if v_ask1 >= v_ask0 or v_bid1 <= v_bid0 then
      raise exception '0017 self-assert FAIL: on % the purser''s shave is below the rounding floor (ask % -> %, bid % -> %), so nothing below could bite',
        v_code, v_ask0, v_ask1, v_bid0, v_bid1;
    end if;

    select * into q_buy  from world.quote(v_port, v_good, v_qty, 'buy',  null, v_fleet);
    select * into q_sell1 from world.quote(v_port, v_good, v_qty, 'sell', null, v_fleet);
    if q_buy.avg_price <> v_ask1 then
      raise exception '0017 self-assert FAIL: with a +% purser the ask is % and the rule gives %', v_pu_txt, q_buy.avg_price, v_ask1;
    end if;
    if q_sell1.avg_price <> v_bid1 then
      raise exception '0017 self-assert FAIL: with a +% purser the bid is % and the rule gives %', v_pu_txt, q_sell1.avg_price, v_bid1;
    end if;
    if q_buy.total >= q_plain.total then
      raise exception '0017 self-assert FAIL: a purser did not make % tuns of % cheaper (% -> %)', v_qty, v_code, q_plain.total, q_buy.total;
    end if;
    if q_sell1.total <= q_sell0.total then
      raise exception '0017 self-assert FAIL: a purser did not lift the proceeds (% -> %)', q_sell0.total, q_sell1.total;
    end if;
    -- the market is still a market: narrowing the spread must never make the bid meet the ask.
    if v_bid1 >= v_ask1 then
      raise exception '0017 self-assert FAIL: with a purser aboard the bid % meets the ask % — a same-port round trip would print money', v_bid1, v_ask1;
    end if;
    -- and the OFFER is priced the same way the CHARGE is (0007's own lesson).
    q_cap := null;
    if (public.fleet_buy_capacity(v_fleet, v_good)->>'max_qty')::numeric > 0 then
      select * into q_cap from world.quote(v_port, v_good,
        (public.fleet_buy_capacity(v_fleet, v_good)->>'max_qty')::numeric, 'buy', null, v_fleet);
      if q_cap.total > (select ducats from public.players where id = v_player) then
        raise exception '0017 self-assert FAIL: buy_capacity offered a parcel costing % against a purse of %',
          q_cap.total, (select ducats from public.players where id = v_player);
      end if;
    end if;

    -- ══ (e) THE WORLD CAP CLAMPS BOTH OF THEM, AND IT BITES ══════════════════════════════════
    -- Two officers of a specialty sum to 10, which is under the seeded cap of 25, so the seeded cap
    -- can never be observed clamping anything. The probe sets its own precondition instead: drop the
    -- knob to 5 (rolled back with everything else) and require the sum to be held at exactly that.
    update public.world_config set value = to_jsonb(5) where key = 'officer_bonus_cap_pct';
    perform cmd.hire_officer('HOLBEK', v_fleet);          -- QUARTERMASTER 4.00 -> sum 10.00
    perform cmd.hire_officer('BARROS', v_fleet);          -- PURSER        4.00 -> sum 10.00
    v_qm2     := public.fleet_officer_bonus(v_fleet, 'QUARTERMASTER');
    v_pu2     := public.fleet_officer_bonus(v_fleet, 'PURSER');
    v_qm2_txt := round(v_qm2 * 100, 2)::text || '%';
    if v_qm2 <> 0.05 or v_pu2 <> 0.05 then
      raise exception '0017 self-assert FAIL: with the cap at 5 the sums read % and % rather than 0.05', v_qm2, v_pu2;
    end if;
    if v_qm2 >= (select sum(o.bonus_pct) from public.player_officers po
                   join public.officers o on o.id = po.officer_id
                  where po.fleet_id = v_fleet and o.specialty = 'QUARTERMASTER') / 100.0 then
      raise exception '0017 self-assert FAIL: the cap did not clamp — two quartermasters summing % were read as %',
        (select sum(o.bonus_pct) from public.player_officers po join public.officers o on o.id = po.officer_id
          where po.fleet_id = v_fleet and o.specialty = 'QUARTERMASTER'), v_qm2;
    end if;
    -- and the clamped figure is what the RULES see, not just what the reading returns
    v_hold2 := public.ship_hold_capacity(v_ship);
    if v_hold2 <> floor(v_rated * (1 + v_qm2)) then
      raise exception '0017 self-assert FAIL: the clamped quartermaster bonus % gave a capacity of % rather than %',
        v_qm2, v_hold2, floor(v_rated * (1 + v_qm2));
    end if;
    v_ask2 := round(v_mid * (1 + v_tax + v_spread * (1 - v_pu2) / 2), 2);
    select * into q_buy from world.quote(v_port, v_good, v_qty, 'buy', null, v_fleet);
    if q_buy.avg_price <> v_ask2 then
      raise exception '0017 self-assert FAIL: the clamped purser bonus % priced % rather than %', v_pu2, q_buy.avg_price, v_ask2;
    end if;

    -- ══ (f) THE SURGEON IS STILL INERT, AND STILL SAYS SO ════════════════════════════════════
    v_roster := world.officers();
    if not (v_roster->'specialties_read' @> '["NAVIGATOR","QUARTERMASTER","PURSER"]'::jsonb)
       or jsonb_array_length(v_roster->'specialties_read') <> 3 then
      raise exception '0017 self-assert FAIL: specialties_read is % and should name exactly the three specialties a rule reads', v_roster->'specialties_read';
    end if;
    if (select count(*) from jsonb_array_elements(v_roster->'officers') e
         where (e->>'specialty') = 'SURGEON' and (e->>'takes_effect')::boolean) > 0 then
      raise exception '0017 self-assert FAIL: a SURGEON is reported as taking effect, but no rule reads one';
    end if;
    if (select count(*) from jsonb_array_elements(v_roster->'officers') e
         where (e->>'specialty') <> 'SURGEON' and not (e->>'takes_effect')::boolean) > 0 then
      raise exception '0017 self-assert FAIL: a navigator, quartermaster or purser is reported as taking no effect, but the rules read all three';
    end if;
    if (select count(*) from jsonb_array_elements(v_roster->'officers') e
         where (e->>'specialty') = 'SURGEON') = 0 then
      raise exception '0017 self-assert FAIL: no SURGEON is on the roster, so the inertness check above was vacuous';
    end if;
    -- 0016's HAGGLING skill attaches at the same function and was NOT lit here.
    v_skills := world.skills();
    if v_skills->'effects_read' @> '["SPREAD"]'::jsonb then
      raise exception '0017 self-assert FAIL: world.skills() claims SPREAD is read, but 0017 wired the officer and not the skill';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- ── THE PROBE LEFT NOTHING BEHIND ────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_players from public.players;
  select count(*) into v_left    from public.player_officers;
  if v_players <> 0 or v_left <> 0 then
    raise exception '0017 self-assert FAIL: the probe left % player(s) and % posting(s) behind', v_players, v_left;
  end if;
  select public.wc_num('officer_bonus_cap_pct') into v_cap_end;
  if v_cap_end <> v_cap_now then
    raise exception '0017 self-assert FAIL: the probe left officer_bonus_cap_pct at % rather than %', v_cap_end, v_cap_now;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0017 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  -- ── THE PART 0017 COULD NOT REPAIR, PRINTED RATHER THAN HIDDEN ───────────────────────────────
  -- 0001's (d2) shape: a condition this migration cannot fix is a permanent NOTICE on every apply,
  -- naming names. Never swallowed, never fatal — an assert that can never pass is pressure to
  -- delete the check (CHAIN.md, 2026-08-18). `client_write_grants()` above reads TABLE grants and
  -- is blind to this by design, which is why it says zero one line up.
  select count(*), string_agg(fn, ', ' order by fn)
    into v_open, v_names
    from (select n.nspname || '.' || p.proname as fn
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'world', 'cmd', 'voyage')
             and p.prosecdef and p.provolatile = 'v'
             and has_function_privilege('anon', p.oid, 'execute')
           group by 1) s;
  if v_open > 0 then
    raise notice '0017 NOTE: % SECURITY DEFINER function(s) that WRITE are still executable by anon, inherited from PostgreSQL''s built-in EXECUTE-for-PUBLIC default because 0001:239''s ALTER DEFAULT PRIVILEGES recorded no pg_default_acl row for the role applying this chain. 0017 closed the seven it re-cut; these remain and want their own migration: %',
      v_open, v_names;
  else
    raise notice '0017 NOTE: no SECURITY DEFINER writer in public/world/cmd/voyage is executable by anon.';
  end if;

  raise notice '0017 self-assert ok: ONE authority for capacity — public.ship_hold_capacity — and fleet_free_hold, fleet_load, do_provision and world.fleets all compose onto it; with no officer aboard a % tun hull reads % and the fleet''s free hold % matches 0007''s own definition exactly, so the supersede is a no-op; a +% quartermaster took the hull to % tuns (floor(% x 1+%)) and the free hold rose by exactly % — and fleet_load then placed all % tuns of % that fleet_free_hold offered, with one tun more REFUSED, so the check and the placement agree; world.quote gained p_fleet and nothing else — naming an unpursered fleet reproduced the 0005 quote to the digit (ask %, bid %), and a +% purser moved the ask to % and the bid to % — the stated amounts, not merely better — with the bid still under the ask; the world cap BIT at a deliberately lowered 5%% (two officers summing 10.00 read as %, capacity %, ask %); SURGEON is still inert and world.officers() says so, and world.skills() still reports HAGGLING/SPREAD unread; all 7 functions this file re-cut are now off the client (they were anon-executable before it, fleet_load and do_buy among them) with % SECURITY DEFINER writer(s) still open chain-wide and NOTICEd by name above; probe rolled back leaving 0 players, 0 postings and the cap back at %; 0 client write grants',
    v_rated, v_hold0, v_free0, v_qm_txt, v_hold1, v_rated, v_qm_txt, v_hold1 - v_hold0,
    v_placed, v_code, v_ask0, v_bid0, v_pu_txt, v_ask1, v_bid1, v_qm2_txt, v_hold2, v_ask2,
    v_open, v_cap_end;
end $$;
