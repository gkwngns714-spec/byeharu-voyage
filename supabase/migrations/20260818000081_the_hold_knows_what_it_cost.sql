-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0081 — THE HOLD KNOWS WHAT IT COST  (and a sale says what it made)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-09-09, docs/OWNER_REQUESTS.md row 74) ────────────────────────────
--   "when trading i would like to know how much i bought the item, and by selling them i would
--    like to see the profits of this trade"
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- Nothing in the chain records what the cargo aboard COST. `public.ships.cargo` (0004:93) is a map
-- of goods.code -> tuns and nothing else; `src/lib/db/README.md` §4.9 says of the price paid
-- *"not served. The Fleets tab's average-cost column has no source. Purchase prices are in the
-- ledger's BOUGHT events"*, and `src/domain/fleet/derive.ts:207-210` repeats it: *"there is no
-- per-lot purchase price to fold and no average cost to report."* The ledger is a DIARY, not a
-- ledger of the hold: a BOUGHT event names a fleet by its NAME and never says which tuns it still
-- has, so nothing can be reconstructed from it after one sale, one STORE, or one raid.
--
-- ── COST BASIS IS A SERVER FACT, NOT A CLIENT MEMORY ────────────────────────────────────────────
-- What a hold cost is a property of the cargo aboard. It must survive a reload, a second device
-- and a voyage that settles with the tab shut, so it is written WHERE THE CARGO IS WRITTEN — in the
-- one cargo mover — and SERVED. A client that remembered its own purchases would be a second
-- ledger, and it would disagree with the game the first time a voyage settled offline.
--
-- THE UNIT IS THE AVERAGE PAID PER TUN, because a hold does not keep its parcels apart: a buy
-- BLENDS into the average, a sale LEAVES IT UNCHANGED, and the profit of a sale is realised HERE,
-- at the moment of sale, against that basis — `proceeds - round(basis x tuns)`. The client
-- never subtracts two served numbers; it asks `cmd.preview` for the real SELL and reads the
-- profit the verb itself computed.
--
-- ── WHERE IT LIVES, AND WHY THERE ───────────────────────────────────────────────────────────────
--   * `public.ships.cargo_basis`  jsonb, goods.code -> ducats per tun (a JSON null = UNKNOWN).
--     Beside `cargo`, per ship, because that is where the tuns are. The average is kept EQUAL
--     across every ship of the fleet that carries the good — `fleet_load` writes the fleet's new
--     average onto all of them — so the fleet is ONE hold for the arithmetic (the owner's fleet
--     is one actor), a partial sale from any hull realises exactly average x tuns, and the books
--     stay exact: 10 t at 100 + 10 t at 200 is 20 t at 150, sell 10 for a cost of 1,500, and the
--     10 that remain still cost 1,500. A per-ship average that was NOT equalised would put the
--     same fleet's cost at 3,500 after the same sale.
--   * `public.player_storage.basis`  numeric per tun — the shed keeps the cost with the goods, so
--     STORE then TAKE then SELL still knows what it paid. Blended on STORE, unchanged on TAKE.
--   * UNKNOWN is a value, not a zero. Tuns that arrive without a price — everything aboard TODAY,
--     because nothing recorded it; a parcel hand-loaded by a probe — carry no key, and a blend
--     that touches an unknown IS unknown. It clears the moment that good is out of the hold:
--     `fleet_unload` drops the key with the cargo key, and the next load starts fresh. No number
--     the game will not honour is ever served: the map omits the good, the sale's profit is null.
--
-- ── THE FOUR NEW OBJECTS ────────────────────────────────────────────────────────────────────────
--   public.blend_basis(q0, b0, q1, b1)           THE one weighted average, null-propagating.
--   public.fleet_cargo_basis(fleet, code)        THE one reading: tun-weighted over the hulls
--                                                that carry the good; null when none do or when
--                                                any of them does not know.
--   public.fleet_cargo_basis_map(fleet)          the reading for every good aboard, served on
--                                                world.fleets() as `cargo_basis` — only the goods
--                                                whose cost is known appear.
--   public.fleet_load(fleet, code, qty, unit_cost default null)
--                                                the mover, with the price the tuns came aboard at.
--
-- ── SUPERSEDE ───────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed bodies of `public.fleet_load` (0017 — DROPPED and re-created
-- with a fourth, defaulted argument, because a 3-arg twin beside a 4-arg default would make every
-- existing 3-arg call ambiguous), `public.fleet_unload` (0007), `cmd.do_buy` (last cut by 0080),
-- `cmd.do_sell` (0080), `cmd.do_store` (0070), `cmd.do_take` (0070) and `world.fleets()` (last cut
-- by 0077), by SLICING them: `pg_temp.recut` replaces hunks that must occur exactly once and
-- refuses otherwise, and assert (j) rebuilds each body from its captured pre-image with only the
-- declared hunks swapped in and compares byte for byte. No ACL is re-declared for the sliced
-- bodies (0080 §3 says what that habit cost): assert (l) proves each ACL byte-identical to the one
-- this file found. `fleet_load` is the one drop, so its posture is DECLARED and then checked.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   * What a trade CHARGES. `world.quote` is untouched; the purse moves by the same `q.total`.
--   * Which tuns go on which hull, and which come off first. The loops in the movers are the
--     0017/0007 loops; only a second column is written beside `cargo`.
--   * Cargo lost at sea (0027's STRIPPED writes `cargo = '{}'` directly). It leaves stale keys in
--     `cargo_basis`, and that is harmless BY CONSTRUCTION: every reading weights by the tuns in
--     `cargo`, so a key with no tuns behind it is never read, and the next load starts from a
--     fleet quantity of zero. Asserted in (c).
--   * `world.market`, `world.snapshot`, the ledger's BOUGHT/SOLD sentences, prices, stock, drift.
--
-- Depends on: 0004 (ships.cargo), 0007 (fleet_unload, fleet_cargo_qty, cmd.do_sell's shape),
-- 0017 (fleet_load's stowed-capacity loop, ship_hold_capacity), 0022 (world.quote's `total`,
-- the money the purse moves by), 0070 (player_storage, do_store, do_take), 0077 (the deployed
-- world.fleets body), 0080 (the deployed do_buy / do_sell bodies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0050:120) ──────
-- Its own copy, by necessity: a pg_temp function lives in this connection's temporary schema and
-- cannot be seen from any other transaction (tests/duplication.spec.ts:365-380 says why).
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0081 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0081 as
select p.oid::regprocedure::text as fn,
       pg_get_functiondef(p.oid)  as def,
       coalesce(p.proacl::text, '') as acl
  from pg_proc p
 where p.oid in ('public.fleet_load(uuid,text,numeric)'::regprocedure,
                 'public.fleet_unload(uuid,text,numeric)'::regprocedure,
                 'cmd.do_buy(uuid,jsonb)'::regprocedure,
                 'cmd.do_sell(uuid,jsonb)'::regprocedure,
                 'cmd.do_store(uuid,jsonb)'::regprocedure,
                 'cmd.do_take(uuid,jsonb)'::regprocedure,
                 'world.fleets()'::regprocedure,
                 'world.quote(uuid,uuid,numeric,text,numeric,uuid)'::regprocedure,
                 'world.market(uuid)'::regprocedure,
                 'world.snapshot()'::regprocedure);

create temporary table world_before_0081 as
select (select count(*) from public.goods)        as goods,
       (select count(*) from public.port_goods)   as market_rows,
       (select count(*) from public.ports)        as ports,
       (select count(*) from public.ships)        as ships,
       (select count(*) from public.players)      as players;

-- ── 1. THE COLUMNS ─────────────────────────────────────────────────────────────────────────────
alter table public.ships add column if not exists cargo_basis jsonb not null default '{}'::jsonb;
comment on column public.ships.cargo_basis is
  '0081 — jsonb map of goods.code -> the AVERAGE ducats paid per tun of that good aboard, or a '
  'JSON null when some of it came aboard without a price (UNKNOWN). Written ONLY by '
  'public.fleet_load (blend on load) and public.fleet_unload (the key leaves with the last tun); '
  'read ONLY through public.fleet_cargo_basis, which weights by the tuns in `cargo`, so a key '
  'with no tuns behind it (a raid that emptied the hold) is never read. Kept EQUAL across every '
  'hull of the fleet that carries the good, so the fleet is one hold for the arithmetic and a '
  'sale from any hull realises exactly average x tuns.';

alter table public.player_storage add column if not exists basis numeric;
comment on column public.player_storage.basis is
  '0081 — the average ducats paid per tun of what this house keeps of this good in this city, '
  'or null when any of it arrived without a price. Blended on STORE through public.blend_basis; '
  'unchanged on TAKE, which loads the ship at this figure. The row leaves with its last tun (0070).';

-- ── 2. THE AUTHORITIES ─────────────────────────────────────────────────────────────────────────
-- `create`, not `create or replace`: this file claims the three are NEW (0051:252's convention).

-- THE ONE weighted average. Null-propagating on purpose: a blend that touches an unknown parcel
-- is unknown, and an unknown is a fact the screen prints as nothing, never as zero.
create function public.blend_basis(p_qty0 numeric, p_basis0 numeric, p_qty1 numeric, p_basis1 numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  select case
           when coalesce(p_qty1, 0) <= 0 then p_basis0
           when coalesce(p_qty0, 0) <= 0 then p_basis1
           when p_basis0 is null or p_basis1 is null then null
           else (p_qty0 * p_basis0 + p_qty1 * p_basis1) / (p_qty0 + p_qty1)
         end
$$;
comment on function public.blend_basis(numeric, numeric, numeric, numeric) is
  '0081 — THE one weighted average behind every cost basis: q0 tuns at b0 joined by q1 tuns at '
  'b1. Nothing added returns b0; nothing there before returns b1 (which may be null); a null on '
  'either side with tuns behind it returns null, because a hold that mixed a priced parcel with '
  'an unpriced one no longer knows what it paid. IMMUTABLE and free of SECURITY DEFINER so it '
  'inlines; it is arithmetic over four values the caller already holds, never a lookup.';
revoke all on function public.blend_basis(numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- THE ONE reading. Tun-weighted over the hulls that carry the good; null when no hull does, or
-- when any of them carries it without a price. A hull with the good in `cargo` but no key in
-- `cargo_basis` — every hull on the day this file lands — is an unknown, not a zero.
create function public.fleet_cargo_basis(p_fleet uuid, p_good_code text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when count(*) = 0 then null
           when count(*) filter (where s.cargo_basis->p_good_code is null
                                    or jsonb_typeof(s.cargo_basis->p_good_code) <> 'number') > 0 then null
           else sum((s.cargo->>p_good_code)::numeric * (s.cargo_basis->>p_good_code)::numeric)
                / sum((s.cargo->>p_good_code)::numeric)
         end
    from public.ships s
   where s.fleet_id = p_fleet
     and coalesce((s.cargo->>p_good_code)::numeric, 0) > 0
$$;
comment on function public.fleet_cargo_basis(uuid, text) is
  '0081 — THE one answer to "what did the tuns of this good aboard this fleet cost, per tun?": '
  'the tun-weighted average over the hulls carrying it, or null when none do or when any hull '
  'does not know. cmd.do_sell realises profit against it, cmd.do_store carries it ashore, '
  'public.fleet_load blends onto it, and world.fleets() serves it. Nothing else reads the column.';
revoke all on function public.fleet_cargo_basis(uuid, text) from public, anon, authenticated;

-- The same reading for every good aboard, as the wire wants it: only the goods whose cost is
-- KNOWN appear, rounded to the hundredth of a ducat the quote itself keeps (world.quote rounds
-- its avg_price to 2). A screen reads `cargo_basis[code]` and prints nothing for a missing key.
create function public.fleet_cargo_basis_map(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(g.code, round(b.basis, 2)), '{}'::jsonb)
    from (select distinct e.key as code
            from public.ships s cross join lateral jsonb_each(s.cargo) e
           where s.fleet_id = p_fleet and (e.value)::text::numeric > 0) g
   cross join lateral (select public.fleet_cargo_basis(p_fleet, g.code) as basis) b
   where b.basis is not null
$$;
comment on function public.fleet_cargo_basis_map(uuid) is
  '0081 — goods.code -> average ducats per tun, for every good aboard whose cost is known. '
  'Composes public.fleet_cargo_basis once per good; it is the wire shape of that one reading '
  'and decides nothing itself. Served as `cargo_basis` on world.fleets().';
revoke all on function public.fleet_cargo_basis_map(uuid) from public, anon, authenticated;

-- ── 3. THE MOVERS, SLICED ──────────────────────────────────────────────────────────────────────
-- fleet_load: DROPPED and re-created with the price as a fourth, defaulted argument. Every
-- existing 3-argument call (the probes in 0061/0068/0070, the proofs) keeps meaning "no price".
-- The loop that chooses the hull is untouched; the blend is one UPDATE after it, over every hull
-- of the fleet that now carries the good, so the average is equal across them.
select pg_temp.recut('public.fleet_load(uuid,text,numeric)'::regprocedure, true,
  $h$CREATE OR REPLACE FUNCTION public.fleet_load(p_fleet uuid, p_good_code text, p_qty numeric)$h$,
  $h$CREATE OR REPLACE FUNCTION public.fleet_load(p_fleet uuid, p_good_code text, p_qty numeric, p_unit_cost numeric DEFAULT NULL::numeric)$h$,
  $h$  r      record;
begin
  select bulk into v_bulk from public.goods where code = p_good_code;$h$,
  $h$  r      record;
  v_qty0   numeric;
  v_basis0 numeric;
  v_loaded numeric;
begin
  select bulk into v_bulk from public.goods where code = p_good_code;
  -- 0081: what the fleet already holds of this good, and what it paid for it, read BEFORE the
  -- tuns move so the blend below is q0 at b0 joined by what actually went aboard at p_unit_cost.
  v_qty0   := public.fleet_cargo_qty(p_fleet, p_good_code);
  v_basis0 := public.fleet_cargo_basis(p_fleet, p_good_code);$h$,
  $h$  return p_qty - v_left;   -- how much actually went aboard
end$h$,
  $h$  v_loaded := p_qty - v_left;   -- how much actually went aboard
  -- 0081: the cost basis is written where the cargo was written, once, onto EVERY hull of the
  -- fleet that now carries the good — one average for one hold. A null (no price came with the
  -- tuns, or the hold already held an unpriced parcel) is stored as a JSON null, never dropped:
  -- a missing key would read as "nothing aboard" and a zero would be a lie.
  if v_loaded > 0 then
    update public.ships
       set cargo_basis = jsonb_set(cargo_basis, array[p_good_code],
             coalesce(to_jsonb(public.blend_basis(v_qty0, v_basis0, v_loaded, p_unit_cost)), 'null'::jsonb), true)
     where fleet_id = p_fleet
       and coalesce((cargo->>p_good_code)::numeric, 0) > 0;
  end if;
  return v_loaded;
end$h$);

comment on function public.fleet_load(uuid, text, numeric, numeric) is
  'THE one way cargo goes aboard (0007), by stowed capacity largest hull first (0017). 0081: the '
  'fourth argument is the ducats per tun the parcel came aboard at — cmd.do_buy passes what the '
  'purse moved by over the tuns, cmd.do_take passes the shed''s figure, and a probe that passes '
  'nothing loads an UNKNOWN. After the loop it writes the fleet''s new average onto every hull '
  'carrying the good, so the whole fleet is one hold for the cost arithmetic. Returns how many '
  'tuns actually went aboard.';
revoke all on function public.fleet_load(uuid, text, numeric, numeric) from public, anon, authenticated;

-- fleet_unload: the key leaves with the last tun, exactly as `cargo`'s does. A partial unload
-- leaves the average alone — that is the owner's rule, "a sale leaves it unchanged".
select pg_temp.recut('public.fleet_unload(uuid,text,numeric)'::regprocedure, false,
  $h$         set cargo = case when r.have - v_take <= 0 then cargo - p_good_code
                          else jsonb_set(cargo, array[p_good_code], to_jsonb(r.have - v_take), true) end
       where id = r.id;$h$,
  $h$         set cargo = case when r.have - v_take <= 0 then cargo - p_good_code
                          else jsonb_set(cargo, array[p_good_code], to_jsonb(r.have - v_take), true) end,
             -- 0081: the cost leaves with the last tun; a partial unload leaves the average alone.
             cargo_basis = case when r.have - v_take <= 0 then cargo_basis - p_good_code
                                else cargo_basis end
       where id = r.id;$h$);

-- ── 4. THE VERBS, SLICED ───────────────────────────────────────────────────────────────────────
-- BUY: the tuns come aboard at what the purse moves by, over the tuns — q.total is the exact
-- figure public.credit takes two statements later, so what was paid IS what is recorded.
select pg_temp.recut('cmd.do_buy(uuid,jsonb)'::regprocedure, false,
  $h$  v_loaded := public.fleet_load(p_fleet, g.code, q.units);$h$,
  $h$  v_loaded := public.fleet_load(p_fleet, g.code, q.units, q.total::numeric / q.units);$h$);

-- SELL: the basis is read BEFORE the tuns leave, the profit is realised against it, and both go
-- out on the event and on the result — which is what cmd.preview hands the tray, and what the
-- committed order writes to `orders.result`. Nothing on the client subtracts anything.
select pg_temp.recut('cmd.do_sell(uuid,jsonb)'::regprocedure, false,
  $h$  v_conc    numeric;
begin$h$,
  $h$  v_conc    numeric;
  v_basis   numeric;
  v_cost    bigint;
  v_profit  bigint;
begin$h$,
  $h$  perform public.fleet_unload(p_fleet, g.code, q.units);$h$,
  $h$  -- 0081: what these tuns COST is read before they leave — the average paid per tun, through
  -- the one reader — and the profit is realised HERE, at the moment of sale, against it. All
  -- three are null when the hold does not know, and a null is served as a null.
  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);
  v_cost   := round(v_basis * q.units)::bigint;
  v_profit := q.total - v_cost;
  perform public.fleet_unload(p_fleet, g.code, q.units);$h$,
  $h$      'haggled', v_conc > 0, 'concession', v_conc)));$h$,
  $h$      'haggled', v_conc > 0, 'concession', v_conc,
      'basis', v_basis, 'cost', v_cost, 'profit', v_profit)));$h$,
  $h$                            'avg_price', q.avg_price, 'concession_spent', v_conc);$h$,
  $h$                            'avg_price', q.avg_price, 'concession_spent', v_conc,
                            'basis', v_basis, 'cost', v_cost, 'profit', v_profit);$h$);

-- STORE: the cost goes ashore with the goods and blends into what the shed already holds.
select pg_temp.recut('cmd.do_store(uuid,jsonb)'::regprocedure, false,
  $h$  v_room numeric;
begin$h$,
  $h$  v_room numeric;
  v_basis numeric;
begin$h$,
  $h$  perform public.fleet_unload(p_fleet, g.code, v_qty);
  insert into public.player_storage (player_id, port_id, good_id, qty)
  values (f.player_id, f.port_id, g.id, v_qty)
  on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;$h$,
  $h$  -- 0081: the cost goes ashore with the goods, blended into what the shed already holds.
  v_basis := public.fleet_cargo_basis(p_fleet, g.code);
  perform public.fleet_unload(p_fleet, g.code, v_qty);
  insert into public.player_storage (player_id, port_id, good_id, qty, basis)
  values (f.player_id, f.port_id, g.id, v_qty, v_basis)
  on conflict (player_id, port_id, good_id) do update
    set qty   = public.player_storage.qty + excluded.qty,
        basis = public.blend_basis(public.player_storage.qty, public.player_storage.basis,
                                   excluded.qty, excluded.basis);$h$);

-- TAKE: the tuns come back aboard at the shed's figure, and the shed's figure does not move.
select pg_temp.recut('cmd.do_take(uuid,jsonb)'::regprocedure, false,
  $h$  v_took numeric;
begin$h$,
  $h$  v_took numeric;
  v_basis numeric;
begin$h$,
  $h$  select ps.qty into v_have from public.player_storage ps$h$,
  $h$  select ps.qty, ps.basis into v_have, v_basis from public.player_storage ps$h$,
  $h$  v_took := public.fleet_load(p_fleet, g.code, v_qty);$h$,
  $h$  v_took := public.fleet_load(p_fleet, g.code, v_qty, v_basis);$h$);

-- ── 5. THE WIRE ────────────────────────────────────────────────────────────────────────────────
-- One key on the fleet, beside the one answer to "how much room": goods.code -> ducats per tun,
-- known goods only. The client reads it; it never folds one.
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $h$    'free_hold', public.fleet_free_hold(f.id),$h$,
  $h$    'free_hold', public.fleet_free_hold(f.id),
    'cargo_basis', public.fleet_cargo_basis_map(f.id),$h$);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe     uuid := gen_random_uuid();
  v_player    uuid;
  v_fleet     uuid;
  v_port      uuid;
  v_port_code text;
  v_flag      uuid;
  v_second    uuid;
  v_class     public.ship_classes%rowtype;
  v_good      uuid;
  v_code      text;
  v_bulk      numeric;
  v_max       numeric;
  v_qty       numeric;
  v_r1        jsonb;
  v_r2        jsonb;
  v_r3        jsonb;
  v_r4        jsonb;
  v_pv        jsonb;
  v_basis     numeric;
  v_basis_b   numeric;
  v_want      numeric;
  v_purse0    bigint;
  v_purse1    bigint;
  v_fleets    jsonb;
  v_served    numeric;
  v_n         bigint;
  v_r         record;
  v_def       text;
  v_expect    text;
  v_off       uuid;
  v_off_code  text;
  v_ctrl      numeric;
  v_fn        text;
  v_u1        jsonb;
  v_u2        jsonb;
  v_u3        jsonb;
  v_shed      boolean := false;
begin
  -- (a) THE COLUMNS, AND NOTHING ABOARD KNOWS ITS COST YET. Every hull in the world carries an
  --     empty map, because no price was ever recorded before this file: the day it lands, what is
  --     aboard is UNKNOWN and is served as nothing, never as zero.
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'ships' and column_name = 'cargo_basis') <> 1
     or (select count(*) from information_schema.columns
          where table_schema = 'public' and table_name = 'player_storage' and column_name = 'basis') <> 1 then
    raise exception '0081 self-assert FAIL: a column this file declares is missing';
  end if;
  select count(*) into v_n from public.ships where cargo_basis <> '{}'::jsonb;
  if v_n <> 0 then
    raise exception '0081 self-assert FAIL: % hull(s) already carry a cost basis — this file invents nothing about cargo it did not see bought', v_n;
  end if;
  select count(*) into v_n from public.ships s
   where exists (select 1 from jsonb_each(s.cargo) e where (e.value)::text::numeric > 0)
     and public.fleet_cargo_basis_map(s.fleet_id) <> '{}'::jsonb;
  if v_n <> 0 then
    raise exception '0081 self-assert FAIL: % hull(s) with cargo aboard are served a cost for it, and nothing ever recorded one', v_n;
  end if;

  -- (b) THE BLEND IS THE BLEND, on the four cases the column comment names, and its NULL is a
  --     null in both directions. Written as values, not as a fixture, because it is arithmetic.
  if public.blend_basis(0, null, 10, 5) is distinct from 5
     or public.blend_basis(10, 100, 10, 200) is distinct from 150
     or public.blend_basis(30, 10, 10, 50) is distinct from 20
     or public.blend_basis(10, 7, 0, 99) is distinct from 7
     or public.blend_basis(10, null, 10, 5) is not null
     or public.blend_basis(10, 5, 10, null) is not null
     or public.blend_basis(0, null, 10, null) is not null then
    raise exception '0081 self-assert FAIL: public.blend_basis is not the weighted average the header describes — (0,-,10,5)=%, (10,100,10,200)=%, (30,10,10,50)=%, (10,7,0,99)=%, unknown-in=%/%',
      public.blend_basis(0, null, 10, 5), public.blend_basis(10, 100, 10, 200), public.blend_basis(30, 10, 10, 50),
      public.blend_basis(10, 7, 0, 99), public.blend_basis(10, null, 10, 5), public.blend_basis(10, 5, 10, null);
  end if;

  -- ── THE WORKED EXAMPLE, ON A REAL HOUSE WITH A REAL FLEET, TWO HULLS AND A REAL QUAY ────────
  v_player := public.new_house(v_probe, 'Casa da Conta', 'PRT');
  select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
  select code into v_port_code from public.ports where id = v_port;
  select id into v_flag from public.ships where fleet_id = v_fleet and is_flagship;
  perform cmd.assume_identity(v_probe);

  -- The subject: the good this quay offers that this house can take MOST of, by the authority the
  -- picker asks (0061's own rule), and it must afford the whole example — two buys and two sales
  -- run through the daily cap and the purse — or the probe has no subject and says so.
  select g.id, g.code, g.bulk into v_good, v_code, v_bulk
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     -- the example trades 83 tuns of it today, buys and sales alike, and the daily cap counts both
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code
   limit 1;
  v_max := (public.fleet_buy_capacity(v_fleet, v_good)->>'max_qty')::numeric;
  if v_good is null or v_max < 20 then
    raise exception '0081 self-assert FAIL: at % the most this house can take of any offered good with 90 tuns of daily cap is % tun(s) of % — the worked example needs 20', v_port_code, v_max, coalesce(v_code, '-');
  end if;
  v_qty := 10;

  -- A SECOND HULL, with room for exactly 4 tuns of the subject, so the first buy of 10 must split
  -- across two ships (the mover fills the larger hull first, and a caravela out-holds a barca).
  -- That is what makes (c) a proof of the EQUALISED average rather than of one hull's.
  select * into v_class from public.ship_classes where code = 'carlat';
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, water_t, food_t, is_flagship)
  values (v_player, v_fleet, v_class.id, 'Segunda', v_class.durability, v_class.crew_required, 0, 0, false)
  returning id into v_second;
  update public.ships set water_t = public.ship_hold_capacity(v_second) - 4 * v_bulk where id = v_second;

  -- (c) BUY TWICE: THE BASIS IS THE MONEY THE PURSE MOVED BY, OVER THE TUNS, BLENDED.
  select ducats into v_purse0 from public.players where id = v_player;
  v_r1 := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', v_qty));
  v_basis := public.fleet_cargo_basis(v_fleet, v_code);
  v_want  := (v_r1->>'total')::numeric / (v_r1->>'qty')::numeric;
  if v_basis is null or abs(v_basis - v_want) > 0.000001 then
    raise exception '0081 self-assert FAIL: after buying % t of % for % d. the basis reads % — expected % per tun (total over tuns)',
      v_r1->>'qty', v_code, v_r1->>'total', v_basis, v_want;
  end if;
  --     ... and it split across the two hulls, and BOTH read the fleet's figure.
  if coalesce((select (cargo->>v_code)::numeric from public.ships where id = v_second), 0) <> 4
     or coalesce((select (cargo->>v_code)::numeric from public.ships where id = v_flag), 0) <> v_qty - 4 then
    raise exception '0081 self-assert FAIL: the 10-tun parcel did not split 4 / 6 across the two hulls (Segunda %, flagship %) — the fixture no longer proves the equalised average',
      (select cargo->>v_code from public.ships where id = v_second), (select cargo->>v_code from public.ships where id = v_flag);
  end if;
  v_r2 := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', v_qty));
  v_basis := public.fleet_cargo_basis(v_fleet, v_code);
  v_want  := ((v_r1->>'total')::numeric + (v_r2->>'total')::numeric) / ((v_r1->>'qty')::numeric + (v_r2->>'qty')::numeric);
  if abs(v_basis - v_want) > 0.000001 then
    raise exception '0081 self-assert FAIL: after a second buy of % t for % d. the basis reads %, expected the blend % (% + % over % + %)',
      v_r2->>'qty', v_r2->>'total', v_basis, v_want, v_r1->>'total', v_r2->>'total', v_r1->>'qty', v_r2->>'qty';
  end if;
  --     NOT VACUOUS: the two buys were priced differently — the book stepped — or the blend above
  --     would be the same number as either buy and would prove nothing about blending.
  if (v_r1->>'avg_price')::numeric = (v_r2->>'avg_price')::numeric then
    raise exception '0081 self-assert FAIL: both buys of % priced at % per tun, so the blend was never exercised', v_code, v_r1->>'avg_price';
  end if;
  select (cargo_basis->>v_code)::numeric into v_basis_b from public.ships where id = v_second;
  if v_basis_b is distinct from (select (cargo_basis->>v_code)::numeric from public.ships where id = v_flag)
     or abs(v_basis_b - v_basis) > 0.000001 then
    raise exception '0081 self-assert FAIL: the two hulls carry different averages (% and %) for one fleet''s % — the hold is not one hold',
      v_basis_b, (select cargo_basis->>v_code from public.ships where id = v_flag), v_code;
  end if;
  --     THE POSITIVE CONTROL: the reader CAN see a hull that disagrees. One hull's figure is bent
  --     by a ducat inside a subtransaction the block throws away, and the fleet reading must move.
  begin
    update public.ships set cargo_basis = jsonb_set(cargo_basis, array[v_code], to_jsonb(v_basis_b + 1)) where id = v_second;
    v_ctrl := public.fleet_cargo_basis(v_fleet, v_code);
    raise exception '__0081_CONTROL__';
  exception when others then
    if sqlerrm <> '__0081_CONTROL__' then raise; end if;
  end;
  if v_ctrl is null or abs(v_ctrl - v_basis) < 0.000001 then
    raise exception '0081 self-assert FAIL: a hull carrying a bent basis left the fleet reading at % (was %) — the reader is not reading the hulls', v_ctrl, v_basis;
  end if;
  --     ... and a stale key with no tuns behind it is never read (the STRIPPED case, 0027): empty
  --     the second hull's cargo of the good directly, leave its key, and the reading must equal
  --     the flagship's alone.
  begin
    update public.ships set cargo = cargo - v_code where id = v_second;
    v_ctrl := public.fleet_cargo_basis(v_fleet, v_code);
    raise exception '__0081_CONTROL__';
  exception when others then
    if sqlerrm <> '__0081_CONTROL__' then raise; end if;
  end;
  if v_ctrl is null or abs(v_ctrl - v_basis) > 0.000001 then
    raise exception '0081 self-assert FAIL: a stale basis key on an emptied hull changed the reading to % (was %)', v_ctrl, v_basis;
  end if;

  -- (d) THE WIRE SERVES IT, to the hundredth, under the fleet, and only for a good that knows.
  v_fleets := world.fleets();
  select (e->'cargo_basis'->>v_code)::numeric into v_served
    from jsonb_array_elements(v_fleets) e where e->>'id' = v_fleet::text;
  if v_served is null or v_served <> round(v_basis, 2) then
    raise exception '0081 self-assert FAIL: world.fleets() serves cargo_basis.% = %, expected % (the reading, rounded to 2)', v_code, v_served, round(v_basis, 2);
  end if;

  -- (e) A PREVIEW OF THE SALE IS THE SALE'S OWN ARITHMETIC, AND MOVES NOTHING. This is the seam
  --     the tray reads: cmd.preview runs the real verb and rolls it back, so the profit it hands
  --     the screen is the one the committed sale will realise, and the client subtracts nothing.
  select ducats into v_purse0 from public.players where id = v_player;
  v_pv := cmd.preview(v_fleet, 'SELL ' || v_code || ' 5', null::jsonb);
  if coalesce((v_pv->>'ok')::boolean, false) is not true or v_pv->'estimate' is null then
    raise exception '0081 self-assert FAIL: cmd.preview refused the sale the example is about: %', v_pv;
  end if;
  if (v_pv->'estimate'->>'basis')::numeric is distinct from v_basis
     or (v_pv->'estimate'->>'cost')::bigint is distinct from round(v_basis * 5)::bigint
     or (v_pv->'estimate'->>'profit')::bigint is distinct from (v_pv->'estimate'->>'total')::bigint - round(v_basis * 5)::bigint then
    raise exception '0081 self-assert FAIL: the previewed sale of 5 t reads basis % / cost % / profit % against total % — expected % / % / %',
      v_pv->'estimate'->>'basis', v_pv->'estimate'->>'cost', v_pv->'estimate'->>'profit', v_pv->'estimate'->>'total',
      v_basis, round(v_basis * 5)::bigint, (v_pv->'estimate'->>'total')::bigint - round(v_basis * 5)::bigint;
  end if;
  select ducats into v_purse1 from public.players where id = v_player;
  if v_purse1 <> v_purse0 or public.fleet_cargo_qty(v_fleet, v_code) <> 2 * v_qty
     or public.fleet_cargo_basis(v_fleet, v_code) is distinct from v_basis then
    raise exception '0081 self-assert FAIL: the preview moved something — purse % -> %, % t aboard, basis %', v_purse0, v_purse1, public.fleet_cargo_qty(v_fleet, v_code), public.fleet_cargo_basis(v_fleet, v_code);
  end if;

  -- (f) SELL FIVE: THE PROFIT IS REALISED AGAINST THE BASIS, THE PURSE MOVES BY THE PROCEEDS,
  --     AND THE FIFTEEN THAT REMAIN STILL COST WHAT THEY COST. Then the previewed figure and the
  --     committed one are the same figure.
  v_r3 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 5));
  select ducats into v_purse1 from public.players where id = v_player;
  if (v_r3->>'qty')::numeric <> 5
     or (v_r3->>'basis')::numeric is distinct from v_basis
     or (v_r3->>'cost')::bigint is distinct from round(v_basis * 5)::bigint
     or (v_r3->>'profit')::bigint is distinct from (v_r3->>'total')::bigint - round(v_basis * 5)::bigint then
    raise exception '0081 self-assert FAIL: selling 5 t of % answered % — expected basis %, cost %, profit total - cost', v_code, v_r3, v_basis, round(v_basis * 5);
  end if;
  if v_purse1 <> v_purse0 + (v_r3->>'total')::bigint then
    raise exception '0081 self-assert FAIL: the sale said % d. and the purse moved % -> %', v_r3->>'total', v_purse0, v_purse1;
  end if;
  if (v_r3->>'profit')::bigint is distinct from (v_pv->'estimate'->>'profit')::bigint then
    raise exception '0081 self-assert FAIL: the preview promised a profit of % and the sale realised % — the two are one code path and must agree', v_pv->'estimate'->>'profit', v_r3->>'profit';
  end if;
  if public.fleet_cargo_basis(v_fleet, v_code) is distinct from v_basis then
    raise exception '0081 self-assert FAIL: a sale of 5 t moved the basis of the 15 that remain from % to % — a sale leaves it unchanged', v_basis, public.fleet_cargo_basis(v_fleet, v_code);
  end if;
  --     ... and the event carries the same three figures, for whatever reads the ledger later.
  select count(*) into v_n from public.events ev
   where ev.player_id = v_player and ev.kind = 'SOLD'
     and (ev.payload->>'profit')::bigint = (v_r3->>'profit')::bigint
     and (ev.payload->>'cost')::bigint = (v_r3->>'cost')::bigint
     and (ev.payload->>'basis')::numeric = v_basis;
  if v_n <> 1 then
    raise exception '0081 self-assert FAIL: the SOLD event does not carry basis / cost / profit as the sale reported them (% matching event(s))', v_n;
  end if;

  -- (g) STORE FOUR, TAKE FOUR: THE COST GOES ASHORE AND COMES BACK, and the fleet's figure is
  --     the same figure on both sides of the shed. The city must keep a warehouse for this; if
  --     the starting port does not, one is raised for the probe (the fixture owns its precondition).
  if not exists (select 1 from public.port_buildings b where b.port_id = v_port and b.kind = 'warehouse') then
    insert into public.port_buildings (port_id, kind, tier) values (v_port, 'warehouse', 1);
    v_shed := true;
  end if;
  perform cmd.do_store(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 4));
  if (select ps.basis from public.player_storage ps where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_good)
     is distinct from v_basis then
    raise exception '0081 self-assert FAIL: 4 t stored ashore carry a basis of %, expected the fleet''s %',
      (select ps.basis from public.player_storage ps where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_good), v_basis;
  end if;
  if public.fleet_cargo_basis(v_fleet, v_code) is distinct from v_basis then
    raise exception '0081 self-assert FAIL: storing 4 t moved the basis of the 11 that remain aboard';
  end if;
  perform cmd.do_take(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 4));
  if public.fleet_cargo_qty(v_fleet, v_code) <> 15 or abs(public.fleet_cargo_basis(v_fleet, v_code) - v_basis) > 0.000001 then
    raise exception '0081 self-assert FAIL: after STORE 4 / TAKE 4 the fleet holds % t at % — expected 15 t at %',
      public.fleet_cargo_qty(v_fleet, v_code), public.fleet_cargo_basis(v_fleet, v_code), v_basis;
  end if;
  if exists (select 1 from public.player_storage ps where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_good) then
    raise exception '0081 self-assert FAIL: the shed still holds a row for % after all of it was taken back', v_code;
  end if;

  -- (h) SELL THE REST: THE KEY LEAVES WITH THE LAST TUN, on every hull, and the wire stops
  --     serving the good.
  v_r4 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 15));
  if public.fleet_cargo_qty(v_fleet, v_code) <> 0
     or public.fleet_cargo_basis(v_fleet, v_code) is not null
     or exists (select 1 from public.ships where fleet_id = v_fleet and cargo_basis ? v_code)
     or (public.fleet_cargo_basis_map(v_fleet) ? v_code) then
    raise exception '0081 self-assert FAIL: after selling every tun of % a basis key survives (fleet reading %, hulls with key %)',
      v_code, public.fleet_cargo_basis(v_fleet, v_code), (select count(*) from public.ships where fleet_id = v_fleet and cargo_basis ? v_code);
  end if;

  -- (i) UNKNOWN IS UNKNOWN, NOT ZERO. A parcel that comes aboard without a price — the shape of
  --     every hold on the day this file lands — is served as nothing, sells at a null profit,
  --     poisons a priced buy that joins it, and clears the moment the good is out of the hold.
  perform public.fleet_load(v_fleet, v_code, 3);
  if public.fleet_cargo_basis(v_fleet, v_code) is not null or (public.fleet_cargo_basis_map(v_fleet) ? v_code) then
    raise exception '0081 self-assert FAIL: 3 t loaded with no price read a basis of %', public.fleet_cargo_basis(v_fleet, v_code);
  end if;
  v_u1 := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', v_qty));
  if public.fleet_cargo_basis(v_fleet, v_code) is not null then
    raise exception '0081 self-assert FAIL: buying 10 t on top of 3 unpriced tuns produced a basis of % — an average over tuns of unknown cost is a made-up number', public.fleet_cargo_basis(v_fleet, v_code);
  end if;
  v_u2 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 13));
  if v_u2->'basis' is distinct from 'null'::jsonb or v_u2->'cost' is distinct from 'null'::jsonb or v_u2->'profit' is distinct from 'null'::jsonb
     or (v_u2->>'total')::bigint <= 0 then
    raise exception '0081 self-assert FAIL: selling an unpriced parcel answered % — basis, cost and profit must be null and the sale must still pay', v_u2;
  end if;
  v_u3 := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', v_qty));
  if abs(public.fleet_cargo_basis(v_fleet, v_code) - (v_u3->>'total')::numeric / (v_u3->>'qty')::numeric) > 0.000001 then
    raise exception '0081 self-assert FAIL: once the unpriced parcel was gone a fresh buy read % rather than its own % per tun',
      public.fleet_cargo_basis(v_fleet, v_code), (v_u3->>'total')::numeric / (v_u3->>'qty')::numeric;
  end if;

  -- The example ends with an empty hold. The house itself STAYS, as 0061's probe house does:
  -- public.events is append-only by 0004's trigger (a DELETE of the player cascades into it and
  -- is refused — measured, "events is append-only: DELETE is not permitted"), and the ledger
  -- being immutable is a rule of the game, not an obstacle to route around. What it leaves is one
  -- house with two hulls, nothing aboard and nothing ashore; the world tables are untouched.
  perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_good::text, 'qty', v_qty));
  if v_shed then
    delete from public.port_buildings where port_id = v_port and kind = 'warehouse';
  end if;
  if public.fleet_cargo_qty(v_fleet, v_code) <> 0
     or exists (select 1 from public.ships where fleet_id = v_fleet and cargo_basis <> '{}'::jsonb)
     or exists (select 1 from public.player_storage where player_id = v_player)
     or (select count(*) from public.players) <> (select players from world_before_0081) + 1 then
    raise exception '0081 self-assert FAIL: the probe house did not end empty (% t aboard, % hull(s) with a basis, % shed row(s))',
      public.fleet_cargo_qty(v_fleet, v_code),
      (select count(*) from public.ships where fleet_id = v_fleet and cargo_basis <> '{}'::jsonb),
      (select count(*) from public.player_storage where player_id = v_player);
  end if;

  -- (j) EACH SLICED BODY IS ITS OWN PRE-IMAGE WITH EXACTLY THE DECLARED HUNKS SWAPPED IN. What
  --     makes "nothing else moved" a fact: the whole definition is rebuilt from the captured one
  --     and compared byte for byte. fleet_load's rebuilt signature must read the way PostgreSQL
  --     prints a defaulted argument, which is also why the hunk above is spelt that way.
  for v_r in select fn, def from defs_before_0081
              where fn not in ('world.quote(uuid,uuid,numeric,text,numeric,uuid)', 'world.market(uuid)', 'world.snapshot()') loop
    v_expect := v_r.def;
    if v_r.fn like '%fleet_load(uuid,text,numeric)' then  -- regprocedure::text drops a schema on the search_path
      v_expect := replace(v_expect,
        'CREATE OR REPLACE FUNCTION public.fleet_load(p_fleet uuid, p_good_code text, p_qty numeric)',
        'CREATE OR REPLACE FUNCTION public.fleet_load(p_fleet uuid, p_good_code text, p_qty numeric, p_unit_cost numeric DEFAULT NULL::numeric)');
      v_expect := replace(v_expect,
        E'  r      record;\nbegin\n  select bulk into v_bulk from public.goods where code = p_good_code;',
        E'  r      record;\n  v_qty0   numeric;\n  v_basis0 numeric;\n  v_loaded numeric;\nbegin\n  select bulk into v_bulk from public.goods where code = p_good_code;\n'
        || E'  -- 0081: what the fleet already holds of this good, and what it paid for it, read BEFORE the\n'
        || E'  -- tuns move so the blend below is q0 at b0 joined by what actually went aboard at p_unit_cost.\n'
        || E'  v_qty0   := public.fleet_cargo_qty(p_fleet, p_good_code);\n'
        || E'  v_basis0 := public.fleet_cargo_basis(p_fleet, p_good_code);');
      v_expect := replace(v_expect,
        E'  return p_qty - v_left;   -- how much actually went aboard\nend',
        E'  v_loaded := p_qty - v_left;   -- how much actually went aboard\n'
        || E'  -- 0081: the cost basis is written where the cargo was written, once, onto EVERY hull of the\n'
        || E'  -- fleet that now carries the good — one average for one hold. A null (no price came with the\n'
        || E'  -- tuns, or the hold already held an unpriced parcel) is stored as a JSON null, never dropped:\n'
        || E'  -- a missing key would read as "nothing aboard" and a zero would be a lie.\n'
        || E'  if v_loaded > 0 then\n'
        || E'    update public.ships\n'
        || E'       set cargo_basis = jsonb_set(cargo_basis, array[p_good_code],\n'
        || E'             coalesce(to_jsonb(public.blend_basis(v_qty0, v_basis0, v_loaded, p_unit_cost)), \'null\'::jsonb), true)\n'
        || E'     where fleet_id = p_fleet\n'
        || E'       and coalesce((cargo->>p_good_code)::numeric, 0) > 0;\n'
        || E'  end if;\n'
        || E'  return v_loaded;\nend');
      select pg_get_functiondef('public.fleet_load(uuid,text,numeric,numeric)'::regprocedure) into v_def;
    else
      v_expect := replace(v_expect,
        E'         set cargo = case when r.have - v_take <= 0 then cargo - p_good_code\n                          else jsonb_set(cargo, array[p_good_code], to_jsonb(r.have - v_take), true) end\n       where id = r.id;',
        E'         set cargo = case when r.have - v_take <= 0 then cargo - p_good_code\n                          else jsonb_set(cargo, array[p_good_code], to_jsonb(r.have - v_take), true) end,\n'
        || E'             -- 0081: the cost leaves with the last tun; a partial unload leaves the average alone.\n'
        || E'             cargo_basis = case when r.have - v_take <= 0 then cargo_basis - p_good_code\n'
        || E'                                else cargo_basis end\n       where id = r.id;');
      v_expect := replace(v_expect,
        '  v_loaded := public.fleet_load(p_fleet, g.code, q.units);',
        '  v_loaded := public.fleet_load(p_fleet, g.code, q.units, q.total::numeric / q.units);');
      if v_r.fn = 'cmd.do_sell(uuid,jsonb)' then
        v_expect := replace(v_expect, E'  v_conc    numeric;\nbegin', E'  v_conc    numeric;\n  v_basis   numeric;\n  v_cost    bigint;\n  v_profit  bigint;\nbegin');
        v_expect := replace(v_expect,
          '  perform public.fleet_unload(p_fleet, g.code, q.units);',
          E'  -- 0081: what these tuns COST is read before they leave — the average paid per tun, through\n'
          || E'  -- the one reader — and the profit is realised HERE, at the moment of sale, against it. All\n'
          || E'  -- three are null when the hold does not know, and a null is served as a null.\n'
          || E'  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);\n'
          || E'  v_cost   := round(v_basis * q.units)::bigint;\n'
          || E'  v_profit := q.total - v_cost;\n'
          || E'  perform public.fleet_unload(p_fleet, g.code, q.units);');
        v_expect := replace(v_expect,
          E'      \'haggled\', v_conc > 0, \'concession\', v_conc)));',
          E'      \'haggled\', v_conc > 0, \'concession\', v_conc,\n      \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit)));');
        v_expect := replace(v_expect,
          E'                            \'avg_price\', q.avg_price, \'concession_spent\', v_conc);',
          E'                            \'avg_price\', q.avg_price, \'concession_spent\', v_conc,\n                            \'basis\', v_basis, \'cost\', v_cost, \'profit\', v_profit);');
      end if;
      if v_r.fn = 'cmd.do_store(uuid,jsonb)' then
        v_expect := replace(v_expect, E'  v_room numeric;\nbegin', E'  v_room numeric;\n  v_basis numeric;\nbegin');
        v_expect := replace(v_expect,
          E'  perform public.fleet_unload(p_fleet, g.code, v_qty);\n  insert into public.player_storage (player_id, port_id, good_id, qty)\n  values (f.player_id, f.port_id, g.id, v_qty)\n  on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;',
          E'  -- 0081: the cost goes ashore with the goods, blended into what the shed already holds.\n'
          || E'  v_basis := public.fleet_cargo_basis(p_fleet, g.code);\n'
          || E'  perform public.fleet_unload(p_fleet, g.code, v_qty);\n'
          || E'  insert into public.player_storage (player_id, port_id, good_id, qty, basis)\n'
          || E'  values (f.player_id, f.port_id, g.id, v_qty, v_basis)\n'
          || E'  on conflict (player_id, port_id, good_id) do update\n'
          || E'    set qty   = public.player_storage.qty + excluded.qty,\n'
          || E'        basis = public.blend_basis(public.player_storage.qty, public.player_storage.basis,\n'
          || E'                                   excluded.qty, excluded.basis);');
      end if;
      if v_r.fn = 'cmd.do_take(uuid,jsonb)' then
        v_expect := replace(v_expect, E'  v_took numeric;\nbegin', E'  v_took numeric;\n  v_basis numeric;\nbegin');
        v_expect := replace(v_expect, '  select ps.qty into v_have from public.player_storage ps', '  select ps.qty, ps.basis into v_have, v_basis from public.player_storage ps');
        v_expect := replace(v_expect, '  v_took := public.fleet_load(p_fleet, g.code, v_qty);', '  v_took := public.fleet_load(p_fleet, g.code, v_qty, v_basis);');
      end if;
      v_expect := replace(v_expect,
        E'    \'free_hold\', public.fleet_free_hold(f.id),',
        E'    \'free_hold\', public.fleet_free_hold(f.id),\n    \'cargo_basis\', public.fleet_cargo_basis_map(f.id),');
      select pg_get_functiondef(v_r.fn::regprocedure) into v_def;
    end if;
    if v_def <> v_expect then
      raise exception '0081 self-assert FAIL: % is not its pre-image with only the declared hunks swapped in (% chars before, % after, % expected)',
        v_r.fn, length(v_r.def), length(v_def), length(v_expect);
    end if;
  end loop;
  --     ... and the three bodies this file only READ are byte-identical.
  for v_r in select fn, def from defs_before_0081
              where fn in ('world.quote(uuid,uuid,numeric,text,numeric,uuid)', 'world.market(uuid)', 'world.snapshot()') loop
    if pg_get_functiondef(v_r.fn::regprocedure) <> v_r.def then
      raise exception '0081 self-assert FAIL: % moved, and this file declared it would not', v_r.fn;
    end if;
  end loop;
  --     ... and the old 3-argument fleet_load is GONE, not sitting beside the new one as an
  --     overload that would make every 3-argument call ambiguous.
  if to_regprocedure('public.fleet_load(uuid,text,numeric)') is not null then
    raise exception '0081 self-assert FAIL: public.fleet_load(uuid,text,numeric) still exists beside the 4-argument one';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'fleet_load') <> 1 then
    raise exception '0081 self-assert FAIL: % public.fleet_load overloads, expected exactly 1',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fleet_load');
  end if;

  -- (k) THE COLUMN HAS ONE WRITER-PAIR AND ONE READER. Any other body that names it is a second
  --     authority, and this is the guard that finds it the day it is written.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc ~ '(^|[^_a-z])cargo_basis'   -- the COLUMN (and the wire key), not the reader's name
     and n.nspname || '.' || p.proname not in ('public.fleet_load', 'public.fleet_unload',
                                               'public.fleet_cargo_basis', 'public.fleet_cargo_basis_map',
                                               'world.fleets');
  if v_n <> 0 then
    raise exception '0081 self-assert FAIL: % function body(ies) besides the declared writers, readers and the wire name cargo_basis', v_n;
  end if;
  if (select count(*) from pg_proc p where p.prosrc like '%fleet_cargo_basis(%' and p.proname <> 'fleet_cargo_basis') <> 4 then
    raise exception '0081 self-assert FAIL: public.fleet_cargo_basis has % caller(s), expected exactly 4 (fleet_load, fleet_cargo_basis_map, do_sell, do_store)',
      (select count(*) from pg_proc p where p.prosrc like '%fleet_cargo_basis(%' and p.proname <> 'fleet_cargo_basis');
  end if;

  -- (l) THE POSTURE: every sliced ACL byte-identical to the one this file found; the dropped and
  --     re-created mover, and the three new functions, off every client role; both halves of the
  --     grant discipline (0001 / 0018) still read zero.
  for v_r in select fn, acl from defs_before_0081 where fn not like '%fleet_load(uuid,text,numeric)' loop
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '')
       is distinct from v_r.acl then
      raise exception '0081 self-assert FAIL: the ACL of % moved — was [%], is now [%]', v_r.fn, v_r.acl,
        coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '');
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'world.fleets()', 'execute') then
    raise exception '0081 self-assert FAIL: world.fleets() lost its grant when it was re-cut — every screen would go dark';
  end if;
  if has_function_privilege('anon', 'world.fleets()', 'execute') then
    raise exception '0081 self-assert FAIL: anon may execute world.fleets()';
  end if;
  foreach v_fn in array array[
      'public.fleet_load(uuid, text, numeric, numeric)',
      'public.fleet_unload(uuid, text, numeric)',
      'public.blend_basis(numeric, numeric, numeric, numeric)',
      'public.fleet_cargo_basis(uuid, text)',
      'public.fleet_cargo_basis_map(uuid)',
      'cmd.do_buy(uuid, jsonb)', 'cmd.do_sell(uuid, jsonb)', 'cmd.do_store(uuid, jsonb)', 'cmd.do_take(uuid, jsonb)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0081 self-assert FAIL: a client role may execute %', v_fn;
    end if;
  end loop;
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception '0081 self-assert FAIL: % client write grant(s) after this migration', v_n;
  end if;
  select count(*) into v_n from public.client_executable_writers();
  if v_n <> 0 then
    raise exception '0081 self-assert FAIL: % client-executable writer(s) after this migration', v_n;
  end if;

  -- (m) THE WORLD IS THE SAME WORLD. Mechanism, not content.
  if (select goods from world_before_0081) <> (select count(*) from public.goods)
     or (select market_rows from world_before_0081) <> (select count(*) from public.port_goods)
     or (select ports from world_before_0081) <> (select count(*) from public.ports) then
    raise exception '0081 self-assert FAIL: this file wrote content; it is only allowed to move mechanism';
  end if;

  raise notice '0081 self-assert ok: THE HOLD KNOWS WHAT IT COST. public.ships.cargo_basis (goods.code -> average ducats per tun, JSON null = unknown) beside cargo, written only by the one mover pair — fleet_load blends what came aboard at what it cost onto EVERY hull of the fleet carrying the good, fleet_unload drops the key with the last tun — read only through public.fleet_cargo_basis, served as cargo_basis on world.fleets(). WORKED EXAMPLE at % on a fresh house with two hulls: bought 10 t of % for % d. (% d./t) — split 4/6 across the hulls, both reading one figure — then 10 t more for % d. (% d./t), so the hold reads % d./t, the blend of the two; a previewed SELL 5 answered basis % / cost % d. / profit % d. on % d. of proceeds and moved nothing; the committed sale of 5 realised the SAME % d. profit, the purse rose by exactly its % d., and the 15 that remained still read % d./t; STORE 4 put % d./t ashore and TAKE 4 brought it back unchanged; selling the last 15 for % d. dropped the key on every hull and off the wire. UNKNOWN IS UNKNOWN: 3 t loaded with no price read nothing, a 10 t buy (% d.) on top of them read nothing, their sale of 13 t paid % d. with a null profit, and the next buy started fresh at its own % d./t. Every sliced body is its pre-image with only the declared hunks swapped in; world.quote, world.market and world.snapshot are byte-identical; the 3-argument fleet_load is gone and only the 4-argument one stands; cargo_basis is named by exactly five bodies and fleet_cargo_basis has exactly four callers; every ACL this file found is where it found it, world.fleets() still executes for authenticated and nothing else does, 0 client write grants, 0 client-executable writers; no good, price row or port was written. Nothing aboard TODAY has a recorded cost — what a hull carries when this file lands is served as nothing, and clears once that parcel is out of the hold.',
    v_port_code,
    v_code, v_r1->>'total', v_r1->>'avg_price',
    v_r2->>'total', v_r2->>'avg_price', round(v_basis, 2),
    round((v_pv->'estimate'->>'basis')::numeric, 2), v_pv->'estimate'->>'cost', v_pv->'estimate'->>'profit', v_pv->'estimate'->>'total',
    v_r3->>'profit', v_r3->>'total', round(v_basis, 2),
    round(v_basis, 2),
    v_r4->>'total',
    v_u1->>'total', v_u2->>'total', round((v_u3->>'total')::numeric / (v_u3->>'qty')::numeric, 2);
end $$;
