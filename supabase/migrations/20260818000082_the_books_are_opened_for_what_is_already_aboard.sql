-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0082 — THE BOOKS ARE OPENED FOR WHAT IS ALREADY ABOARD
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-09-09, after driving the game on production) ──────────────────────
--   The cargo already in their hold shows NO cost at all. "fix both of those" — this is the first.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- 0081 records a basis only from the next purchase onward. Its own header says so: *"Tuns that
-- arrive without a price — everything aboard TODAY, because nothing recorded it — carry no key"*,
-- and its assert (a) requires every hull to carry an empty map on the day it lands. So the olive
-- oil the owner bought before 0081 is served as nothing, and stays nothing until it is sold out.
--
-- ── THE INSIGHT THAT MAKES THIS A RECONSTRUCTION, NOT A GUESS ──────────────────────────────────
-- A SALE NEVER MOVES THE AVERAGE (0081: "a buy blends, a sale leaves the average unchanged"). So
-- the average cost of what REMAINS in a hold is the weighted average of everything ever BOUGHT
-- into it — provided every acquisition was priced and the ledger is complete. `public.events` is
-- append-only (0004's trigger) and carries what is needed: BOUGHT has fleet, good, qty, total;
-- SOLD, STORED and TAKEN have fleet, good, qty. Replaying them per (house, fleet, good) with the
-- SAME blend 0081 uses — `public.blend_basis`, never a second one — yields the figure 0081 would
-- have written had it been there. Where the replay cannot be proven right, it REFUSES: 0081 prints
-- an unknown as nothing, never as zero, so a refusal is safe and a wrong number is not.
--
-- ── §7B — THE FOUR QUESTIONS, ANSWERED BEFORE THE CODE ──────────────────────────────────────────
--   1. CONCEPT, one noun phrase: the opening of the books for cargo bought before 0081 recorded it.
--   2. WHERE IT LIVES: in this migration ONLY, as a one-shot `pg_temp` replay that writes the
--      column 0081 owns (`ships.cargo_basis`) exactly as 0081's mover would — the fleet's average
--      onto every hull carrying the good — and then ceases to exist. It is not a function in the
--      catalogue, because a standing "recompute the basis from the ledger" would be a SECOND
--      authority beside `fleet_load`/`fleet_unload` (0081 assert (k) counts the bodies that name
--      the column, and this file re-asserts that count unchanged).
--   3. THE SECOND CALLER: none, by design. A hold that is opened here is on the books; from then on
--      `fleet_load` blends and `fleet_unload` drops the key, and nothing ever needs the ledger
--      replayed again. If a second caller appears, the ledger has become a second source of truth
--      for the hold, and that is the defect, not a feature to serve.
--   4. WHAT WOULD MAKE IT WRONG, and how anyone finds out: a written figure that disagrees with what
--      was paid. The self-assert below constructs holds whose ledger and cargo DISAGREE and proves
--      each guard refuses them, and holds that agree and proves the exact figure is written and
--      read back through 0081's one reader — including a hold shaped like the owner's own, with
--      the owner's own production figures, so the production receipt is predicted here.
--
-- ── THE METHOD ─────────────────────────────────────────────────────────────────────────────────
-- Per (house, fleet NAME, good), the house's events in `created_at` order, carrying (qty, basis):
--   BOUGHT  blend in `qty` tuns at `total / qty` through public.blend_basis (0081's cmd.do_buy
--           passes exactly `q.total / q.units`);
--   SOLD    qty falls; the basis is unchanged; at zero the basis is unknown again (fleet_unload
--           drops the key with the last tun, and a re-buy starts fresh);
--   STORED  qty falls; the tuns join a per-(house, CITY, good) shed bucket blended at the fleet's
--           basis of that moment (cmd.do_store reads it BEFORE the unload);
--   TAKEN   qty rises, blended at the shed bucket's basis; the bucket's basis does not move and the
--           bucket leaves with its last tun (0070 deletes the row).
-- The CITY of a STORE or TAKE is not on the event (0070 writes only fleet, good, qty). It is the
-- fleet's harbour at that instant, read from the ledger the way the game moves a fleet: the
-- latest VOYAGE_REPORT with a `to` at or before the event, else — for the founding fleet only —
-- the FOUNDED event's `port`. A fleet only ever docks by arriving (voyage.settle is the one writer
-- of a DOCKED port for a real house; the direct `update fleets set port_id` sites in the chain are
-- all inside self-assert probes).
--
-- ── THE GUARDS — REFUSING IS THE FEATURE ───────────────────────────────────────────────────────
--   1. The replayed quantity must EQUAL the tuns in the hold. Otherwise the ledger is incomplete
--      for that good (cargo hand-loaded by a probe, a raid, a transfer) — refuse.
--   2. Any unpriced acquisition poisons it: blend_basis propagates null, and null is never written.
--   3. A shed that cannot be placed in one city — no arrival on record for a fleet that is not the
--      founding one, or two arrivals sharing the instant — refuses the good; a TAKE from a bucket
--      the ledger never filled refuses; and the replayed sheds must EQUAL `public.player_storage`
--      city for city, or the placement is not trusted.
--   4. Within ONE instant the order of events is unrecoverable (`created_at` is the transaction's
--      now(), `id` is random): a purchase and a sale of one good sharing an instant refuse. Two
--      purchases, or two sales, commute and are allowed.
--   5. Written onto EVERY hull that carries the good — the fleet is one hold — and ONLY where no
--      hull carrying it has an entry already. A key 0081 wrote, a JSON null included, is never
--      overwritten: the pair is KEPT, not opened.
--   6. Every refusal is REPORTED with its reason; the receipt names each pair it opened, kept and
--      refused.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
-- No function body, no ACL, no shed basis (`player_storage.basis` stays as 0081 left it — the ask
-- is the HOLD), no price, no stock, no world row. The ten bodies 0081 named are proven byte-identical.
--
-- Depends on: 0004 (events, FOUNDED), 0007 (BOUGHT/SOLD shape, fleet_cargo_qty), 0047 (the deployed
-- VOYAGE_REPORT's `to`), 0070 (STORED/TAKEN shape, player_storage keyed by city), 0081
-- (ships.cargo_basis, blend_basis, fleet_cargo_basis, the one writer pair).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. PRE-IMAGES ──────────────────────────────────────────────────────────────────────────────
create temporary table defs_before_0082 as
select p.oid::regprocedure::text as fn, pg_get_functiondef(p.oid) as def, coalesce(p.proacl::text, '') as acl
  from pg_proc p
 where p.oid in ('public.fleet_load(uuid,text,numeric,numeric)'::regprocedure,
                 'public.fleet_unload(uuid,text,numeric)'::regprocedure,
                 'public.blend_basis(numeric,numeric,numeric,numeric)'::regprocedure,
                 'public.fleet_cargo_basis(uuid,text)'::regprocedure,
                 'public.fleet_cargo_basis_map(uuid)'::regprocedure,
                 'cmd.do_buy(uuid,jsonb)'::regprocedure,
                 'cmd.do_sell(uuid,jsonb)'::regprocedure,
                 'cmd.do_store(uuid,jsonb)'::regprocedure,
                 'cmd.do_take(uuid,jsonb)'::regprocedure,
                 'world.fleets()'::regprocedure);

create temporary table world_before_0082 as
select (select count(*) from public.goods)          as goods,
       (select count(*) from public.port_goods)     as market_rows,
       (select count(*) from public.ports)          as ports,
       (select count(*) from public.players)        as players,
       (select count(*) from public.events)         as events,
       (select count(*) from public.player_storage) as sheds;

-- ── 1. THE REPLAY — one temporary function, gone with this connection ──────────────────────────
-- (a number printed without trailing zeros, for the receipt and the refusal sentences)
create or replace function pg_temp.n82(p numeric) returns text language sql immutable
as $$ select regexp_replace(round(p, 2)::text, '\.?0+$', '') $$;

-- It READS a ledger (a relation shaped like public.events — the real one, or a fixture) and fills
-- `books_0082` with a verdict per (fleet, good) that has tuns aboard. It writes NOTHING to the
-- world; the one write is step 3, over the verdicts, and is asserted separately.
create or replace function pg_temp.replay_0082(p_events regclass, p_player uuid default null)
returns void
language plpgsql
as $$
declare
  e      record;
  v_hq   numeric;   -- the fleet's replayed tuns of the good, before this event
  v_hb   numeric;   -- ... and their basis
  v_sq   numeric;   -- the shed bucket's tuns
  v_sb   numeric;   -- ... and their basis
  v_unit numeric;
  v_t    text;
begin
  -- a second call (the real ledger after the fixture one) starts clean
  foreach v_t in array array['ev_0082', 'hold_0082', 'shed_0082', 'refuse_0082', 'books_0082'] loop
    if to_regclass('pg_temp.' || v_t) is not null then execute 'drop table ' || v_t; end if;
  end loop;

  -- (a) every trade event of the ledger, its good resolved by NAME through public.goods — the one
  --     table that says what a good is called — exactly one hit or unresolved. An unresolved
  --     name can never open anything: the hold it belongs to then replays short and guard 1 refuses.
  execute format($q$
    create temporary table ev_0082 as
    select e.id, e.player_id, e.created_at, e.kind,
           e.payload->>'fleet' as fleet_name,
           case when g.n = 1 then g.code end as code,
           (e.payload->>'qty')::numeric   as qty,
           (e.payload->>'total')::numeric as total,
           null::text as port_code, false as port_ambiguous
      from %s e
      left join lateral (select count(*) as n, min(code) as code
                           from public.goods where name = e.payload->>'good') g on true
     where e.kind in ('BOUGHT', 'SOLD', 'STORED', 'TAKEN')
       and (%L::uuid is null or e.player_id = %L::uuid)$q$, p_events, p_player, p_player);

  -- (b) the CITY of every STORE and TAKE: the fleet's latest arrival at or before the instant, else
  --     the founding port for the founding fleet. Two arrivals sharing that latest instant with
  --     different harbours cannot be told apart, and say so.
  execute format($q$
    with arrivals as (
      select r.player_id, r.payload->>'fleet' as fleet_name, r.created_at, r.payload->>'to' as to_code
        from %s r where r.kind = 'VOYAGE_REPORT' and r.payload->>'to' is not null),
    founded as (
      select f.player_id, f.payload->>'port' as port_code from %s f where f.kind = 'FOUNDED'),
    placed as (
      select e2.id,
             coalesce(a.to_code, case when fl.first_name = e2.fleet_name then fo.port_code end) as port_code,
             coalesce(a.n_distinct, 0) > 1 as ambiguous
        from ev_0082 e2
        left join lateral (
          select count(distinct a1.to_code) as n_distinct, min(a1.to_code) as to_code
            from arrivals a1
           where a1.player_id = e2.player_id and a1.fleet_name = e2.fleet_name
             and a1.created_at = (select max(a2.created_at) from arrivals a2
                                   where a2.player_id = e2.player_id and a2.fleet_name = e2.fleet_name
                                     and a2.created_at <= e2.created_at)) a on true
        left join lateral (select f1.name as first_name from public.fleets f1
                            where f1.player_id = e2.player_id order by f1.created_at, f1.id limit 1) fl on true
        left join founded fo on fo.player_id = e2.player_id
       where e2.kind in ('STORED', 'TAKEN'))
    update ev_0082 e set port_code = p.port_code, port_ambiguous = p.ambiguous
      from placed p where p.id = e.id$q$, p_events, p_events);

  create temporary table hold_0082 (player_id uuid, fleet_name text, code text, qty numeric, basis numeric,
                                    primary key (player_id, fleet_name, code));
  create temporary table shed_0082 (player_id uuid, port_code text, code text, qty numeric, basis numeric,
                                    primary key (player_id, port_code, code));
  create temporary table refuse_0082 (player_id uuid, code text, reason text);

  -- (c) guard 4: an instant that both raises and lowers one good cannot be ordered.
  insert into refuse_0082
  select player_id, code, 'a purchase and a sale of it share one instant, and the ledger cannot say which came first'
    from ev_0082 where code is not null
   group by player_id, code, created_at
  having bool_or(kind in ('BOUGHT', 'TAKEN')) and bool_or(kind in ('SOLD', 'STORED'));

  -- (d) THE REPLAY, in ledger order. Inside one instant only same-direction events remain, and
  --     those commute, so the order among them does not matter.
  for e in select * from ev_0082 where code is not null
             and not exists (select 1 from refuse_0082 r where r.player_id = ev_0082.player_id and r.code = ev_0082.code)
            order by player_id, created_at, id loop
    if exists (select 1 from refuse_0082 r where r.player_id = e.player_id and r.code = e.code) then
      continue;   -- refused earlier in this same replay
    end if;
    select h.qty, h.basis into v_hq, v_hb from hold_0082 h
     where h.player_id = e.player_id and h.fleet_name = e.fleet_name and h.code = e.code;
    v_hq := coalesce(v_hq, 0);

    if e.kind = 'BOUGHT' then
      if e.total is null or coalesce(e.qty, 0) <= 0 then
        insert into refuse_0082 values (e.player_id, e.code, 'an acquisition in its history carried no price');
        continue;
      end if;
      v_unit := e.total / e.qty;
      insert into hold_0082 values (e.player_id, e.fleet_name, e.code, v_hq + e.qty, public.blend_basis(v_hq, v_hb, e.qty, v_unit))
      on conflict (player_id, fleet_name, code) do update set qty = excluded.qty, basis = excluded.basis;

    elsif e.kind = 'SOLD' then
      if coalesce(e.qty, 0) <= 0 or e.qty > v_hq then
        insert into refuse_0082 values (e.player_id, e.code, 'the ledger records more sold or stored than it ever bought');
        continue;
      end if;
      update hold_0082 set qty = v_hq - e.qty, basis = case when v_hq - e.qty <= 0 then null else basis end
       where player_id = e.player_id and fleet_name = e.fleet_name and code = e.code;

    elsif e.kind = 'STORED' then
      if e.port_ambiguous then
        insert into refuse_0082 values (e.player_id, e.code, 'two harbours claim the same instant, so the shed cannot be placed');
        continue;
      elsif e.port_code is null then
        insert into refuse_0082 values (e.player_id, e.code, 'a STORE or TAKE of it cannot be placed in a city');
        continue;
      elsif coalesce(e.qty, 0) <= 0 or e.qty > v_hq then
        insert into refuse_0082 values (e.player_id, e.code, 'the ledger records more sold or stored than it ever bought');
        continue;
      end if;
      update hold_0082 set qty = v_hq - e.qty, basis = case when v_hq - e.qty <= 0 then null else basis end
       where player_id = e.player_id and fleet_name = e.fleet_name and code = e.code;
      insert into shed_0082 values (e.player_id, e.port_code, e.code, e.qty, v_hb)
      on conflict (player_id, port_code, code) do update
        set qty   = shed_0082.qty + excluded.qty,
            basis = public.blend_basis(shed_0082.qty, shed_0082.basis, excluded.qty, excluded.basis);

    elsif e.kind = 'TAKEN' then
      if e.port_ambiguous then
        insert into refuse_0082 values (e.player_id, e.code, 'two harbours claim the same instant, so the shed cannot be placed');
        continue;
      elsif e.port_code is null then
        insert into refuse_0082 values (e.player_id, e.code, 'a STORE or TAKE of it cannot be placed in a city');
        continue;
      end if;
      select s.qty, s.basis into v_sq, v_sb from shed_0082 s
       where s.player_id = e.player_id and s.port_code = e.port_code and s.code = e.code;
      if coalesce(e.qty, 0) <= 0 or e.qty > coalesce(v_sq, 0) then
        insert into refuse_0082 values (e.player_id, e.code, 'the ledger takes more from a shed than it ever put there');
        continue;
      end if;
      update shed_0082 set qty = v_sq - e.qty
       where player_id = e.player_id and port_code = e.port_code and code = e.code;
      delete from shed_0082 where player_id = e.player_id and port_code = e.port_code and code = e.code and qty <= 0;
      insert into hold_0082 values (e.player_id, e.fleet_name, e.code, v_hq + e.qty, public.blend_basis(v_hq, v_hb, e.qty, v_sb))
      on conflict (player_id, fleet_name, code) do update set qty = excluded.qty, basis = excluded.basis;
    end if;
  end loop;

  -- (e) guard 3's last half: the replayed sheds must equal the sheds in the cities, city for city,
  --     for every good whose history went through a shed at all.
  insert into refuse_0082
  select distinct x.player_id, x.code, 'the sheds on the books disagree with the sheds in the cities'
    from (select player_id, code from ev_0082 where kind in ('STORED', 'TAKEN') and code is not null) x
   where exists (
     select 1 from (
       select s.player_id, p.code as port_code, s.code, s.qty from shed_0082 s join public.ports p on p.code = s.port_code
       union all
       select ps.player_id, p.code, g.code, -ps.qty
         from public.player_storage ps join public.ports p on p.id = ps.port_id join public.goods g on g.id = ps.good_id
     ) u
     where u.player_id = x.player_id and u.code = x.code
     group by u.player_id, u.port_code, u.code having sum(u.qty) <> 0);

  -- (f) THE VERDICTS: one per (fleet, good) with tuns aboard.
  create temporary table books_0082 as
  select c.fleet_id, c.player_id, c.fleet_name, c.code, c.hold_qty, h.qty as book_qty, h.basis,
         case when c.any_key then 'KEPT'
              when r.reasons is not null then 'REFUSED'
              when h.qty is null or h.qty <> c.hold_qty then 'REFUSED'
              when h.basis is null then 'REFUSED'
              else 'OPENED' end as verdict,
         case when c.any_key then 'already on the books, or unknown by 0081''s own rule'
              when r.reasons is not null then r.reasons
              when h.qty is null or h.qty <> c.hold_qty then
                format('the ledger accounts for %s t and the hold carries %s t', pg_temp.n82(coalesce(h.qty, 0)), pg_temp.n82(c.hold_qty))
              when h.basis is null then 'an acquisition in its history carried no price'
              else null end as reason
    from (select s.fleet_id, f.player_id, f.name as fleet_name, je.key as code,
                 sum((je.value)::text::numeric) as hold_qty, bool_or(s.cargo_basis ? je.key) as any_key
            from public.ships s join public.fleets f on f.id = s.fleet_id
           cross join lateral jsonb_each(s.cargo) je
           where (je.value)::text::numeric > 0 and (p_player is null or f.player_id = p_player)
           group by 1, 2, 3, 4) c
    left join hold_0082 h on h.player_id = c.player_id and h.fleet_name = c.fleet_name and h.code = c.code
    left join (select player_id, code, string_agg(distinct reason, '; ') as reasons from refuse_0082 group by 1, 2) r
           on r.player_id = c.player_id and r.code = c.code;
end $$;

-- ── 2. THE FIXTURES: two houses whose ledgers are KNOWN, so the replay's verdicts can be predicted ─
create temporary table fx_0082 (k text primary key, v text);

do $$
declare
  v_probe1   uuid := gen_random_uuid();
  v_probe2   uuid := gen_random_uuid();
  v_p1       uuid;
  v_p2       uuid;
  v_fleet1   uuid;
  v_fleet2   uuid;
  v_port     uuid;
  v_port_code text;
  v_flag     uuid;
  v_second   uuid;
  v_class    public.ship_classes%rowtype;
  v_good     uuid;
  v_code     text;
  v_bulk     numeric;
  v_max      numeric;
  v_good2    uuid;
  v_code2    text;
  v_r1       jsonb;
  v_r2       jsonb;
  v_r3       jsonb;
  v_r5       jsonb;
  v_good3    uuid;
  v_code3    text;
  v_basis3   numeric;
  v_basis81  numeric;
  v_g        text[];
  v_n        text[];
  v_ship2    uuid;
  v_city     uuid;
  v_city_c   text;
  v_city2_c  text;
  v_t        timestamptz := now();
begin
  -- ── HOUSE 1, through the REAL verbs on a REAL quay: the same worked example 0081 ran, then its
  --    keys are struck out, so its hold is exactly the shape of the owner's — tuns aboard, bought
  --    and paid for, with no cost on record. Two buys share this transaction's instant, and two
  --    purchases commute, so guard 4 lets them through. 0081 wrote the figure before it was struck;
  --    the replay must find the SAME figure.
  v_p1 := public.new_house(v_probe1, 'Casa dos Livros', 'PRT');
  select id, port_id into v_fleet1, v_port from public.fleets where player_id = v_p1;
  select code into v_port_code from public.ports where id = v_port;
  select id into v_flag from public.ships where fleet_id = v_fleet1 and is_flagship;
  perform cmd.assume_identity(v_probe1);
  select g.id, g.code, g.bulk into v_good, v_code, v_bulk
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_p1, v_port, g.id) >= 60
   order by (public.fleet_buy_capacity(v_fleet1, g.id)->>'max_qty')::numeric desc, g.code
   limit 1;
  v_max := (public.fleet_buy_capacity(v_fleet1, v_good)->>'max_qty')::numeric;
  if v_good is null or v_max < 20 then
    raise exception '0082 self-assert FAIL: at % the most this house can take of any offered good with 60 tuns of daily cap is % tun(s) of % — the fixture needs 20', v_port_code, v_max, coalesce(v_code, '-');
  end if;
  -- a second hull with room for exactly 4 tuns, so the parcel splits and BOTH hulls must be opened
  select * into v_class from public.ship_classes where code = 'carlat';
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, water_t, food_t, is_flagship)
  values (v_p1, v_fleet1, v_class.id, 'Segunda', v_class.durability, v_class.crew_required, 0, 0, false)
  returning id into v_second;
  update public.ships set water_t = public.ship_hold_capacity(v_second) - 4 * v_bulk where id = v_second;

  v_r1 := cmd.do_buy(v_fleet1, jsonb_build_object('good', v_good::text, 'qty', 10));
  v_r2 := cmd.do_buy(v_fleet1, jsonb_build_object('good', v_good::text, 'qty', 10));
  if (v_r1->>'avg_price')::numeric = (v_r2->>'avg_price')::numeric then
    raise exception '0082 self-assert FAIL: both fixture buys of % priced at % per tun, so the replayed blend would prove nothing', v_code, v_r1->>'avg_price';
  end if;
  if coalesce((select (cargo->>v_code)::numeric from public.ships where id = v_second), 0) <> 4 then
    raise exception '0082 self-assert FAIL: the first 10-tun parcel did not put 4 t on the second hull (it holds %)', (select cargo->>v_code from public.ships where id = v_second);
  end if;
  v_basis81 := public.fleet_cargo_basis(v_fleet1, v_code);
  if v_basis81 is null then
    raise exception '0082 self-assert FAIL: 0081 recorded no basis for the fixture''s two buys';
  end if;

  -- a SECOND good on the same house whose hold DISAGREES with its ledger: 5 t bought, 3 t
  -- hand-loaded with no price and no event — the 0070-probe shape — so guard 1 must refuse it
  select g.id, g.code into v_good2, v_code2
    from public.goods g
   where g.id <> v_good
     and public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_p1, v_port, g.id) >= 20
     and (public.fleet_buy_capacity(v_fleet1, g.id)->>'max_qty')::numeric >= 8
   order by g.code limit 1;
  if v_good2 is null then
    raise exception '0082 self-assert FAIL: at % no second offered good with room for 8 t and 20 t of daily cap — the disagreeing fixture has no subject', v_port_code;
  end if;
  v_r3 := cmd.do_buy(v_fleet1, jsonb_build_object('good', v_good2::text, 'qty', 5));
  perform public.fleet_load(v_fleet1, v_code2, 3);
  if public.fleet_cargo_qty(v_fleet1, v_code2) <> 8 then
    raise exception '0082 self-assert FAIL: the disagreeing fixture holds % t of %, expected 8', public.fleet_cargo_qty(v_fleet1, v_code2), v_code2;
  end if;

  -- a THIRD good, 5 t bought and nothing else, so that ONE hull carries TWO goods to be opened
  -- beside one to be refused: the write must land every opened key of a hull, not one of them
  select g.id, g.code into v_good3, v_code3
    from public.goods g
   where g.id not in (v_good, v_good2)
     and public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_p1, v_port, g.id) >= 10
     and (public.fleet_buy_capacity(v_fleet1, g.id)->>'max_qty')::numeric >= 5
   order by g.code limit 1;
  if v_good3 is null then
    raise exception '0082 self-assert FAIL: at % no third offered good with room for 5 t — the two-goods-on-one-hull fixture has no subject', v_port_code;
  end if;
  v_r5 := cmd.do_buy(v_fleet1, jsonb_build_object('good', v_good3::text, 'qty', 5));
  v_basis3 := public.fleet_cargo_basis(v_fleet1, v_code3);
  if v_basis3 is null or coalesce((select (cargo->>v_code3)::numeric from public.ships where id = v_flag), 0) <> 5
     or coalesce((select (cargo->>v_code)::numeric from public.ships where id = v_flag), 0) <> 16 then
    raise exception '0082 self-assert FAIL: the flagship should carry 16 t of % and 5 t of % (it carries % and %)',
      v_code, v_code3, (select cargo->>v_code from public.ships where id = v_flag), (select cargo->>v_code3 from public.ships where id = v_flag);
  end if;

  -- STRIKE THE KEYS: what 0081 wrote is struck from every hull of house 1, so the house is in the
  -- pre-0081 state the owner is in — cargo aboard, nothing on the books.
  update public.ships set cargo_basis = '{}'::jsonb where fleet_id = v_fleet1;

  insert into fx_0082 values ('p1', v_p1::text), ('fleet1', v_fleet1::text), ('flag1', v_flag::text), ('second1', v_second::text),
    ('good1', v_good::text), ('code1', v_code), ('basis81', v_basis81::text), ('port1', v_port_code),
    ('t1', v_r1->>'total'), ('q1', v_r1->>'qty'), ('t2', v_r2->>'total'), ('q2', v_r2->>'qty'),
    ('a1', v_r1->>'avg_price'), ('a2', v_r2->>'avg_price'),
    ('good2', v_good2::text), ('code2', v_code2), ('t3', v_r3->>'total'),
    ('good3', v_good3::text), ('code3', v_code3), ('basis3', v_basis3::text), ('t5', v_r5->>'total');

  -- ── HOUSE 2, a ledger written into a FIXTURE relation (never into public.events — the ledger of
  --    the game is not a place for invented rows), at DISTINCT instants, with cargo set to match or
  --    to disagree. Nine goods, nine predicted verdicts. The first two carry the OWNER'S OWN figures
  --    from production (BOUGHT 55 for 4,447; SOLD 20; BOUGHT 3 for 3,817), so the production
  --    receipt is predicted by this file rather than hoped for.
  v_p2 := public.new_house(v_probe2, 'Casa do Azeite', 'PRT');
  select id into v_fleet2 from public.fleets where player_id = v_p2;
  select id into v_ship2 from public.ships where fleet_id = v_fleet2 and is_flagship;
  -- twelve goods with unique names, chosen by code order; a second harbour with a shed, by code order
  select array_agg(code order by code), array_agg(name order by code) into v_g, v_n
    from (select g.code, g.name from public.goods g
           where (select count(*) from public.goods g2 where g2.name = g.name) = 1
           order by g.code limit 12) s;
  if array_length(v_g, 1) <> 12 then
    raise exception '0082 self-assert FAIL: fewer than 12 uniquely named goods in the catalogue';
  end if;
  select p.id, p.code into v_city, v_city_c from public.ports p
   where p.kind = 'HARBOUR' and p.code <> 'LIS' and exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'warehouse')
   order by p.code limit 1;
  select p.code into v_city2_c from public.ports p where p.kind = 'HARBOUR' and p.code not in ('LIS', v_city_c) order by p.code limit 1;
  if v_city is null or v_city2_c is null then
    raise exception '0082 self-assert FAIL: no second and third harbour to place the fixture''s sheds';
  end if;

  create temporary table fx_events_0082 as select * from public.events where player_id = v_p2;  -- its FOUNDED
  insert into fx_events_0082 (id, player_id, kind, payload, created_at) values
    -- [1] the owner's olive oil: 55 for 4,447, then 20 sold → 35 t at 4447/55
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[1], 'qty', 55, 'total', 4447), v_t - interval '3 hours'),
    (gen_random_uuid(), v_p2, 'SOLD',   jsonb_build_object('fleet', 'Gaivota', 'good', v_n[1], 'qty', 20, 'total', 1933), v_t - interval '2 hours'),
    -- [2] the owner's clocks: 3 for 3,817
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[2], 'qty', 3, 'total', 3817), v_t - interval '1 hour'),
    -- [3] through a shed in another city: 20 @100 at LIS; arrive at the city; STORE 10; BUY 10 @160;
    --     TAKE 5 back at the shed's 100 → fleet 20 @130 + 5 @100 = 25 t at 124; shed keeps 5 @100
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[3], 'qty', 20, 'total', 2000), v_t - interval '55 minutes'),
    (gen_random_uuid(), v_p2, 'VOYAGE_REPORT', jsonb_build_object('fleet', 'Gaivota', 'from', 'LIS', 'to', v_city_c), v_t - interval '50 minutes'),
    (gen_random_uuid(), v_p2, 'STORED', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[3], 'qty', 10), v_t - interval '40 minutes'),
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[3], 'qty', 10, 'total', 1600), v_t - interval '35 minutes'),
    (gen_random_uuid(), v_p2, 'TAKEN',  jsonb_build_object('fleet', 'Gaivota', 'good', v_n[3], 'qty', 5), v_t - interval '30 minutes'),
    -- [4] a purchase and a sale in ONE instant → refused (guard 4), though the quantities agree
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[4], 'qty', 10, 'total', 1000), v_t - interval '20 minutes'),
    (gen_random_uuid(), v_p2, 'SOLD',   jsonb_build_object('fleet', 'Gaivota', 'good', v_n[4], 'qty', 4, 'total', 500), v_t - interval '20 minutes'),
    -- [5] a TAKE from a shed the ledger never filled → refused (guard 3)
    (gen_random_uuid(), v_p2, 'TAKEN',  jsonb_build_object('fleet', 'Gaivota', 'good', v_n[5], 'qty', 5), v_t - interval '10 minutes'),
    -- [6] two arrivals in one instant, then a STORE → the shed cannot be placed (guard 3)
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[6], 'qty', 10, 'total', 500), v_t - interval '12 minutes'),
    (gen_random_uuid(), v_p2, 'VOYAGE_REPORT', jsonb_build_object('fleet', 'Gaivota', 'from', v_city_c, 'to', v_city2_c), v_t - interval '9 minutes'),
    (gen_random_uuid(), v_p2, 'VOYAGE_REPORT', jsonb_build_object('fleet', 'Gaivota', 'from', v_city2_c, 'to', v_city_c), v_t - interval '9 minutes'),
    (gen_random_uuid(), v_p2, 'STORED', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[6], 'qty', 4), v_t - interval '8 minutes'),
    -- [7] a purchase with no price on it → refused (guard 2)
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[7], 'qty', 10), v_t - interval '7 minutes'),
    -- [8] a STORE from a fleet with no arrival on record that is not the founding one → cannot be placed
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[8], 'qty', 10, 'total', 300), v_t - interval '6 minutes'),
    (gen_random_uuid(), v_p2, 'STORED', jsonb_build_object('fleet', 'Ghost', 'good', v_n[8], 'qty', 3), v_t - interval '5 minutes'),
    -- [9] the ledger says 10, the hold carries 12 → refused (guard 1)
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[9], 'qty', 10, 'total', 700), v_t - interval '4 minutes'),
    -- [10] a key 0081 already wrote (12.5) beside a ledger that would say 100 → KEPT, never overwritten (guard 5)
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[10], 'qty', 5, 'total', 500), v_t - interval '3 minutes'),
    -- [11] sold OUT and bought again: 10 @100, all 10 sold, 5 @150 → the old figure is gone, 5 t at 150
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[11], 'qty', 10, 'total', 1000), v_t - interval '90 minutes'),
    (gen_random_uuid(), v_p2, 'SOLD',   jsonb_build_object('fleet', 'Gaivota', 'good', v_n[11], 'qty', 10, 'total', 900),  v_t - interval '80 minutes'),
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[11], 'qty', 5, 'total', 750),   v_t - interval '70 minutes'),
    -- [12] a STORE the city does not remember: 4 t on the books ashore, no shed row → refused (guard 3)
    (gen_random_uuid(), v_p2, 'BOUGHT', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[12], 'qty', 10, 'total', 1000), v_t - interval '65 minutes'),
    (gen_random_uuid(), v_p2, 'STORED', jsonb_build_object('fleet', 'Gaivota', 'good', v_n[12], 'qty', 4), v_t - interval '45 minutes');
  -- the hold, set directly (a fixture owns its precondition); [3]'s shed row in the city, as 0070 keeps it
  update public.ships
     set cargo = jsonb_build_object(v_g[1], 35, v_g[2], 3, v_g[3], 25, v_g[4], 6, v_g[5], 5, v_g[6], 6, v_g[7], 10, v_g[8], 10, v_g[9], 12, v_g[10], 5)
                 || jsonb_build_object(v_g[11], 5, v_g[12], 6),
         cargo_basis = jsonb_build_object(v_g[10], 12.5)
   where id = v_ship2;
  insert into public.player_storage (player_id, port_id, good_id, qty)
  values (v_p2, v_city, (select id from public.goods where code = v_g[3]), 5);

  insert into fx_0082 values ('p2', v_p2::text), ('fleet2', v_fleet2::text), ('ship2', v_ship2::text), ('city', v_city_c),
    ('g1', v_g[1]), ('g2', v_g[2]), ('g3', v_g[3]), ('g4', v_g[4]), ('g5', v_g[5]), ('g6', v_g[6]), ('g7', v_g[7]), ('g8', v_g[8]), ('g9', v_g[9]), ('g10', v_g[10]), ('g11', v_g[11]), ('g12', v_g[12]);
end $$;

-- ── 2b. THE ENGINE ON THE FIXTURE LEDGER: twelve predicted verdicts, watched ─────────────────────
select pg_temp.replay_0082('pg_temp.fx_events_0082'::regclass, (select v::uuid from fx_0082 where k = 'p2'));

do $$
declare
  v_fleet2 uuid := (select v::uuid from fx_0082 where k = 'fleet2');
  v_ship2  uuid := (select v::uuid from fx_0082 where k = 'ship2');
  g        text[] := array[(select v from fx_0082 where k = 'g1'), (select v from fx_0082 where k = 'g2'),
                           (select v from fx_0082 where k = 'g3'), (select v from fx_0082 where k = 'g4'),
                           (select v from fx_0082 where k = 'g5'), (select v from fx_0082 where k = 'g6'),
                           (select v from fx_0082 where k = 'g7'), (select v from fx_0082 where k = 'g8'),
                           (select v from fx_0082 where k = 'g9'), (select v from fx_0082 where k = 'g10'),
                           (select v from fx_0082 where k = 'g11'), (select v from fx_0082 where k = 'g12')];
  b        record;
  v_n      int;
begin
  select count(*) into v_n from books_0082;
  if v_n <> 12 then
    raise exception '0082 self-assert FAIL: the fixture ledger produced % verdict(s), expected 12', v_n;
  end if;
  -- [1] the owner's olive oil: 35 t at 4447/55 = 80.8545…
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[1];
  if b.verdict <> 'OPENED' or b.hold_qty <> 35 or abs(b.basis - 4447.0 / 55) > 1e-9 then
    raise exception '0082 self-assert FAIL: [1] 55 bought for 4,447 then 20 sold should OPEN 35 t at % — got % % t at % (%)', 4447.0 / 55, b.verdict, b.hold_qty, b.basis, b.reason;
  end if;
  -- [2] the owner's clocks: 3 t at 3817/3 = 1272.333…
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[2];
  if b.verdict <> 'OPENED' or b.hold_qty <> 3 or abs(b.basis - 3817.0 / 3) > 1e-9 then
    raise exception '0082 self-assert FAIL: [2] 3 bought for 3,817 should OPEN 3 t at % — got % % t at % (%)', 3817.0 / 3, b.verdict, b.hold_qty, b.basis, b.reason;
  end if;
  -- [3] through the shed: 20@100, store 10, buy 10@160 (fleet 20@130), take 5@100 → 25 t at 124
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[3];
  if b.verdict <> 'OPENED' or b.hold_qty <> 25 or abs(b.basis - 124) > 1e-9 then
    raise exception '0082 self-assert FAIL: [3] the shed round trip should OPEN 25 t at 124 — got % % t at % (%)', b.verdict, b.hold_qty, b.basis, b.reason;
  end if;
  if (select qty from shed_0082 where player_id = (select v::uuid from fx_0082 where k = 'p2') and code = g[3]) is distinct from 5
     or (select basis from shed_0082 where player_id = (select v::uuid from fx_0082 where k = 'p2') and code = g[3]) is distinct from 100 then
    raise exception '0082 self-assert FAIL: [3] the replayed shed should keep 5 t at 100';
  end if;
  -- [4]..[9]: refused, each for its own stated reason
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[4];
  if b.verdict <> 'REFUSED' or b.reason not like '%share one instant%' then
    raise exception '0082 self-assert FAIL: [4] a purchase and a sale in one instant should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[5];
  if b.verdict <> 'REFUSED' or b.reason not like '%takes more from a shed%' then
    raise exception '0082 self-assert FAIL: [5] a TAKE from an unfilled shed should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[6];
  if b.verdict <> 'REFUSED' or b.reason not like '%two harbours claim the same instant%' then
    raise exception '0082 self-assert FAIL: [6] a STORE after two arrivals in one instant should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[7];
  if b.verdict <> 'REFUSED' or b.reason not like '%carried no price%' then
    raise exception '0082 self-assert FAIL: [7] an unpriced purchase should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[8];
  if b.verdict <> 'REFUSED' or b.reason not like '%cannot be placed in a city%' then
    raise exception '0082 self-assert FAIL: [8] a STORE from a fleet with no arrival should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[9];
  if b.verdict <> 'REFUSED' or b.reason not like 'the ledger accounts for 10 t and the hold carries 12 t' then
    raise exception '0082 self-assert FAIL: [9] a hold of 12 against a ledger of 10 should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[10];
  if b.verdict <> 'KEPT' or (select (cargo_basis->>g[10])::numeric from public.ships where id = v_ship2) <> 12.5 then
    raise exception '0082 self-assert FAIL: [10] a key already on the books should be KEPT — got % (%)', b.verdict, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[11];
  if b.verdict <> 'OPENED' or b.hold_qty <> 5 or abs(b.basis - 150) > 1e-9 then
    raise exception '0082 self-assert FAIL: [11] sold out and bought again should OPEN 5 t at 150 — got % % t at % (%)', b.verdict, b.hold_qty, b.basis, b.reason;
  end if;
  select * into b from books_0082 where fleet_id = v_fleet2 and code = g[12];
  if b.verdict <> 'REFUSED' or b.reason not like '%sheds on the books disagree%' then
    raise exception '0082 self-assert FAIL: [12] a STORE the city does not remember should REFUSE — got % (%)', b.verdict, b.reason;
  end if;
  -- the fixture ledger was never written into the game's ledger
  if (select count(*) from public.events where player_id = (select v::uuid from fx_0082 where k = 'p2')) <> 1 then
    raise exception '0082 self-assert FAIL: the fixture house has % event(s) in public.events, expected only its FOUNDED', (select count(*) from public.events where player_id = (select v::uuid from fx_0082 where k = 'p2'));
  end if;
  -- the engine wrote nothing: the fixture hull still carries only the key it was given
  if (select cargo_basis from public.ships where id = v_ship2) <> jsonb_build_object(g[10], 12.5) then
    raise exception '0082 self-assert FAIL: the replay itself wrote a basis; only step 3 may';
  end if;
  raise notice '0082 fixture ledger ok: 12 predicted verdicts held — the owner''s shape opens 35 t at % and 3 t at %, the shed round trip opens 25 t at 124, a good sold out and bought again opens at its new price alone, seven disagreeing ledgers refuse for seven stated reasons, and a key already on the books is kept',
    round(4447.0 / 55, 4), round(3817.0 / 3, 4);
end $$;

-- the fixture hold is cleared before the real ledger is replayed: house 2 has no real trades
update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
 where id = (select v::uuid from fx_0082 where k = 'ship2');
delete from public.player_storage where player_id = (select v::uuid from fx_0082 where k = 'p2');

-- ── 3. THE REAL LEDGER, AND THE ONE WRITE ──────────────────────────────────────────────────────
create temporary table ships_before_0082 as select id, cargo_basis from public.ships;

select pg_temp.replay_0082('public.events'::regclass);

-- One statement, every opened key of a hull at once: UPDATE ... FROM uses ONE join row per target
-- row, so a hull carrying two opened goods (the owner's flagship carries olive oil AND clocks)
-- would otherwise be opened for only one of them. Found by the break-test, not by reasoning.
update public.ships s
   set cargo_basis = s.cargo_basis || k.keys
  from (select s2.id, jsonb_object_agg(b.code, b.basis) as keys
          from public.ships s2
          join books_0082 b on b.fleet_id = s2.fleet_id and b.verdict = 'OPENED'
         where coalesce((s2.cargo->>b.code)::numeric, 0) > 0
           and not (s2.cargo_basis ? b.code)
         group by s2.id) k
 where k.id = s.id;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_p1      uuid := (select v::uuid from fx_0082 where k = 'p1');
  v_fleet1  uuid := (select v::uuid from fx_0082 where k = 'fleet1');
  v_flag    uuid := (select v::uuid from fx_0082 where k = 'flag1');
  v_second  uuid := (select v::uuid from fx_0082 where k = 'second1');
  v_good    uuid := (select v::uuid from fx_0082 where k = 'good1');
  v_code    text := (select v from fx_0082 where k = 'code1');
  v_good2   uuid := (select v::uuid from fx_0082 where k = 'good2');
  v_code2   text := (select v from fx_0082 where k = 'code2');
  v_good3   uuid := (select v::uuid from fx_0082 where k = 'good3');
  v_code3   text := (select v from fx_0082 where k = 'code3');
  v_basis3  numeric := (select v::numeric from fx_0082 where k = 'basis3');
  v_t5      numeric := (select v::numeric from fx_0082 where k = 't5');
  v_basis81 numeric := (select v::numeric from fx_0082 where k = 'basis81');
  v_t1      numeric := (select v::numeric from fx_0082 where k = 't1');
  v_q1      numeric := (select v::numeric from fx_0082 where k = 'q1');
  v_t2      numeric := (select v::numeric from fx_0082 where k = 't2');
  v_q2      numeric := (select v::numeric from fx_0082 where k = 'q2');
  v_probe1  uuid;
  b         record;
  r         record;
  v_n       bigint;
  v_opened  int;
  v_refused int;
  v_kept    int;
  v_pv      jsonb;
  v_r4      jsonb;
  v_lines   text := '';
  v_reasons text := '';
  v_fn      text;
  v_served  numeric;
begin
  -- (a) HOUSE 1 THROUGH THE REAL LEDGER: the figure 0081 wrote and then had struck is FOUND AGAIN,
  --     to the digit, and it is total over tuns of the two real buys.
  select * into b from books_0082 where fleet_id = v_fleet1 and code = v_code;
  if b.verdict is distinct from 'OPENED' or abs(b.basis - v_basis81) > 1e-9 then
    raise exception '0082 self-assert FAIL: house 1''s % — 0081 had recorded % d./t; the replay says % (%: %)', v_code, v_basis81, b.basis, b.verdict, b.reason;
  end if;
  if abs(b.basis - (v_t1 + v_t2) / (v_q1 + v_q2)) > 1e-9 then
    raise exception '0082 self-assert FAIL: house 1''s replayed basis % is not (% + %) / (% + %)', b.basis, v_t1, v_t2, v_q1, v_q2;
  end if;
  --     ... written onto BOTH hulls, equal, and read back through 0081's one reader
  if (select (cargo_basis->>v_code)::numeric from public.ships where id = v_second) is distinct from
     (select (cargo_basis->>v_code)::numeric from public.ships where id = v_flag)
     or (select cargo_basis ? v_code from public.ships where id = v_second) is not true then
    raise exception '0082 self-assert FAIL: the two hulls of house 1 do not both carry the opened figure (% / %)',
      (select cargo_basis->>v_code from public.ships where id = v_flag), (select cargo_basis->>v_code from public.ships where id = v_second);
  end if;
  if abs(public.fleet_cargo_basis(v_fleet1, v_code) - v_basis81) > 1e-9 then
    raise exception '0082 self-assert FAIL: the reader answers % for house 1''s %, expected %', public.fleet_cargo_basis(v_fleet1, v_code), v_code, v_basis81;
  end if;
  --     ... the THIRD good opened on the SAME hull as the first — two opened keys on one hull
  select * into b from books_0082 where fleet_id = v_fleet1 and code = v_code3;
  if b.verdict is distinct from 'OPENED' or abs(b.basis - v_basis3) > 1e-9 or abs(b.basis - v_t5 / 5) > 1e-9 then
    raise exception '0082 self-assert FAIL: house 1''s third good % — 0081 had recorded % d./t; the replay says % (%: %)', v_code3, v_basis3, b.basis, b.verdict, b.reason;
  end if;
  if (select cargo_basis ? v_code and cargo_basis ? v_code3 from public.ships where id = v_flag) is not true
     or abs((select (cargo_basis->>v_code3)::numeric from public.ships where id = v_flag) - v_basis3) > 1e-9
     or abs(public.fleet_cargo_basis(v_fleet1, v_code3) - v_basis3) > 1e-9 then
    raise exception '0082 self-assert FAIL: the flagship carries % and % but was opened for only one of them (%)',
      v_code, v_code3, (select cargo_basis from public.ships where id = v_flag);
  end if;
  --     ... the disagreeing good REFUSED, guard 1, and its hull still carries no key
  select * into b from books_0082 where fleet_id = v_fleet1 and code = v_code2;
  if b.verdict is distinct from 'REFUSED' or b.reason not like 'the ledger accounts for 5 t and the hold carries 8 t' then
    raise exception '0082 self-assert FAIL: house 1''s % (5 bought, 8 aboard) should REFUSE by quantity — got % (%)', v_code2, b.verdict, b.reason;
  end if;
  if exists (select 1 from public.ships where fleet_id = v_fleet1 and cargo_basis ? v_code2)
     or public.fleet_cargo_basis(v_fleet1, v_code2) is not null then
    raise exception '0082 self-assert FAIL: a refused good was written';
  end if;

  -- (b) THE SEAM THE OWNER SEES: a previewed sale of the opened cargo now realises a profit against
  --     the opened figure, through cmd.do_sell's own arithmetic, and the committed sale agrees.
  select auth_uid into v_probe1 from public.players where id = v_p1;
  perform cmd.assume_identity(v_probe1);
  select (e->'cargo_basis'->>v_code)::numeric into v_served
    from jsonb_array_elements(world.fleets()) e where e->>'id' = v_fleet1::text;
  if v_served is null or v_served <> round(v_basis81, 2) then
    raise exception '0082 self-assert FAIL: world.fleets() serves cargo_basis.% = % for the opened hold, expected %', v_code, v_served, round(v_basis81, 2);
  end if;
  v_pv := cmd.preview(v_fleet1, 'SELL ' || v_code || ' 5', null::jsonb);
  if coalesce((v_pv->>'ok')::boolean, false) is not true
     or (v_pv->'estimate'->>'basis')::numeric is distinct from public.fleet_cargo_basis(v_fleet1, v_code)
     or (v_pv->'estimate'->>'profit')::bigint is distinct from (v_pv->'estimate'->>'total')::bigint - round(v_basis81 * 5)::bigint then
    raise exception '0082 self-assert FAIL: a previewed SELL of 5 t of the opened cargo answered % — expected basis % and profit total - %', v_pv, v_basis81, round(v_basis81 * 5);
  end if;
  v_r4 := cmd.do_sell(v_fleet1, jsonb_build_object('good', v_good::text, 'qty', 20));
  if (v_r4->>'profit')::bigint is distinct from (v_r4->>'total')::bigint - round(v_basis81 * 20)::bigint
     or exists (select 1 from public.ships where fleet_id = v_fleet1 and cargo_basis ? v_code) then
    raise exception '0082 self-assert FAIL: selling all 20 t of the opened cargo answered % and left a key behind', v_r4;
  end if;
  perform cmd.do_sell(v_fleet1, jsonb_build_object('good', v_good2::text, 'qty', 8));
  v_r4 := cmd.do_sell(v_fleet1, jsonb_build_object('good', v_good3::text, 'qty', 5));
  if (v_r4->>'profit')::bigint is distinct from (v_r4->>'total')::bigint - round(v_basis3 * 5)::bigint then
    raise exception '0082 self-assert FAIL: selling the third good realised % against an opened basis of %', v_r4, v_basis3;
  end if;
  if public.fleet_cargo_qty(v_fleet1, v_code) <> 0 or public.fleet_cargo_qty(v_fleet1, v_code2) <> 0 or public.fleet_cargo_qty(v_fleet1, v_code3) <> 0
     or exists (select 1 from public.ships where fleet_id = v_fleet1 and cargo_basis <> '{}'::jsonb) then
    raise exception '0082 self-assert FAIL: house 1 did not end empty';
  end if;

  -- (c) THE ONE WRITE TOUCHED EXACTLY THE OPENED PAIRS, on every hull carrying them, and nothing else.
  select count(*) into v_n
    from public.ships s join ships_before_0082 o on o.id = s.id
   where s.fleet_id <> v_fleet1   -- house 1 sold out above, by design
     and s.cargo_basis - coalesce((select array_agg(b2.code) from books_0082 b2 where b2.verdict = 'OPENED' and b2.fleet_id = s.fleet_id), array[]::text[])
         <> o.cargo_basis;
  if v_n <> 0 then
    raise exception '0082 self-assert FAIL: % hull(s) carry a change that is not an opened key', v_n;
  end if;
  select count(*) into v_n
    from books_0082 b2 join public.ships s on s.fleet_id = b2.fleet_id
   where b2.verdict = 'OPENED' and b2.fleet_id <> v_fleet1
     and coalesce((s.cargo->>b2.code)::numeric, 0) > 0
     and (not (s.cargo_basis ? b2.code) or abs((s.cargo_basis->>b2.code)::numeric - b2.basis) > 1e-9);
  if v_n <> 0 then
    raise exception '0082 self-assert FAIL: % hull(s) carrying an opened good do not carry its figure', v_n;
  end if;
  for b in select * from books_0082 where verdict = 'OPENED' and fleet_id <> v_fleet1 loop
    if abs(public.fleet_cargo_basis(b.fleet_id, b.code) - b.basis) > 1e-9 then
      raise exception '0082 self-assert FAIL: the reader answers % for an opened %, the books say %', public.fleet_cargo_basis(b.fleet_id, b.code), b.code, b.basis;
    end if;
  end loop;

  -- (d) NOTHING ELSE MOVED: the ten bodies and their ACLs, the writer-and-reader count 0081 pinned,
  --     both halves of the posture, the world.
  for r in select fn, def, acl from defs_before_0082 loop
    if pg_get_functiondef(r.fn::regprocedure) <> r.def then
      raise exception '0082 self-assert FAIL: % moved, and this file declared it would not', r.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = r.fn::regprocedure), '') is distinct from r.acl then
      raise exception '0082 self-assert FAIL: the ACL of % moved', r.fn;
    end if;
  end loop;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc ~ '(^|[^_a-z])cargo_basis'
     and n.nspname || '.' || p.proname not in ('public.fleet_load', 'public.fleet_unload',
                                               'public.fleet_cargo_basis', 'public.fleet_cargo_basis_map',
                                               'world.fleets');
  if v_n <> 0 then
    raise exception '0082 self-assert FAIL: % catalogued body(ies) besides 0081''s five name cargo_basis — this file was to leave no second authority behind', v_n;
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%fleet_cargo_basis(%' and p.proname <> 'fleet_cargo_basis') <> 4 then
    raise exception '0082 self-assert FAIL: public.fleet_cargo_basis no longer has exactly 4 callers';
  end if;
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then raise exception '0082 self-assert FAIL: % client write grant(s)', v_n; end if;
  select count(*) into v_n from public.client_executable_writers();
  if v_n <> 0 then raise exception '0082 self-assert FAIL: % client-executable writer(s)', v_n; end if;
  if (select goods from world_before_0082) <> (select count(*) from public.goods)
     or (select market_rows from world_before_0082) <> (select count(*) from public.port_goods)
     or (select ports from world_before_0082) <> (select count(*) from public.ports)
     or (select players from world_before_0082) + 2 <> (select count(*) from public.players)
     or (select sheds from world_before_0082) <> (select count(*) from public.player_storage)
     or (select events from world_before_0082) > (select count(*) from public.events) then
    raise exception '0082 self-assert FAIL: this file moved something it declared it would not (goods, market rows, ports, houses other than its two, sheds, events)';
  end if;

  -- (e) THE RECEIPT — every pair the real ledger was asked about, by name, with its verdict.
  select count(*) filter (where verdict = 'OPENED'), count(*) filter (where verdict = 'REFUSED'), count(*) filter (where verdict = 'KEPT')
    into v_opened, v_refused, v_kept from books_0082;
  for b in select bk.*, pl.company_name from books_0082 bk join public.players pl on pl.id = bk.player_id
            order by pl.company_name, bk.fleet_name, bk.code loop
    v_lines := v_lines || format(E'\n    %s · %s · %s: %s', b.company_name, b.fleet_name, b.code,
      case b.verdict
        when 'OPENED' then format('OPENED — %s t at %s d./t', pg_temp.n82(b.hold_qty), round(b.basis, 4)::text)
        when 'KEPT'   then 'KEPT — ' || b.reason
        else 'REFUSED — ' || b.reason end);
  end loop;
  select coalesce(string_agg(format('%s × "%s"', n, reason), '; '), 'none')
    into v_reasons from (select reason, count(*) as n from books_0082 where verdict = 'REFUSED' group by reason order by n desc, reason) x;

  raise notice '0082 self-assert ok: THE BOOKS ARE OPENED FOR WHAT IS ALREADY ABOARD. The ledger was replayed per (house, fleet, good) with 0081''s one blend, and a basis was written ONLY where the replay is provably right: % pair(s) OPENED, % REFUSED (%), % KEPT as 0081 left them. Predicted first on a fixture ledger of twelve goods at distinct instants — the OWNER''S OWN production figures open 35 t at % d./t (4,447 over 55, the sale of 20 leaving it unchanged) and 3 t at % d./t (3,817 over 3); a round trip through a shed in another city opens 25 t at 124.0000; a good sold out and bought again opens at its new price alone; a same-instant buy-and-sell, a TAKE from an unfilled shed, two arrivals in one instant, an unpriced purchase, a STORE from an unplaceable fleet, a STORE no city remembers, and a hold of 12 against a ledger of 10 all REFUSE, each for its stated reason; and a key already on the books is KEPT. Then on the REAL ledger: house 1 (Casa dos Livros at %) bought % t of % for % d. and % t for % d. through the real verbs — 0081 recorded % d./t, the figure was struck from both hulls, and the replay found % d./t again, (%+%)/(%+%), written onto both hulls and read back through the one reader; its third good, 5 t of % for % d., OPENED at % d./t on the SAME hull as the first, so a hull with two opened goods carries both; its second good, 5 t bought and 3 t hand-loaded, REFUSED by quantity; a previewed SELL of 5 t then realised a profit against the opened figure and the sale of all 20 t agreed and dropped the key. The one write changed exactly the opened keys on exactly the hulls carrying them; the ten 0081 bodies and ACLs are byte-identical, cargo_basis is still named by exactly five bodies and the reader still has four callers, 0 client write grants, 0 client-executable writers; no good, price row, port or shed row was written and no event was lost. THE PAIRS:%',
    v_opened, v_refused, v_reasons, v_kept,
    round(4447.0 / 55, 4), round(3817.0 / 3, 4),
    (select v from fx_0082 where k = 'port1'), v_q1, v_code, v_t1, v_q2, v_t2, round(v_basis81, 4), round(v_basis81, 4), v_t1, v_t2, v_q1, v_q2,
    v_code3, v_t5, round(v_basis3, 4),
    v_lines;
end $$;
