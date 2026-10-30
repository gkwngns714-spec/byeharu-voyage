-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0282 — THE OLD HOLD IS CASHED OUT BEFORE THE REPRICE
--        The first half of the owner-approved sim slice (docs/OWNER_REQUESTS.md row 224): before
--        the raw-material prices are re-based on real-world values (0283), every held trade good
--        is converted to cash at TODAY's goods.base_value, so no house is left carrying stock
--        whose worth is about to be re-priced underneath it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S INSTRUCTION ────────────────────────────────────────────────────────────────────
--   "the merchants and players holding the trade goods that are based before, convert them into
--    cash first then do the work." (2026-10-30)
--
-- ── WHAT IS LIQUIDATED, AND AT WHAT PRICE ──────────────────────────────────────────────────────
-- Held trade goods live in exactly two places (docs/design/raw-materials-economy/
-- SIM_SLICE_FACTS.md §2): aboard a hull in public.ships.cargo (jsonb goods.code -> qty) and
-- ashore in public.player_storage (player, port, good, qty). NPC merchants hold theirs in the
-- SAME tables — a merchant is a public.players row with is_npc = true (0097:10-16), not a
-- separate purse — so "every player" is literally every row of public.players: no is_npc filter.
--
-- The price is the good's CURRENT public.goods.base_value — the figure 0283 is about to re-base.
-- Not mid, not bid, not a stepped world.quote: those carry stock, spread, tax and the city's
-- purse, and would pay two houses different prices for the same good. base_value is the one
-- catalogue figure, equal for everyone, and it is exactly the number that changes next.
--
-- ── HOW THE MONEY MOVES ────────────────────────────────────────────────────────────────────────
-- One public.credit(player, 'LIQUIDATION', total, null) per house for the whole hold — not one
-- per good, not one per hull. credit() is THE one purse writer (0004:216-245); writing
-- players.ducats directly would trip the deferred reconciliation triggers (0004:205-213).
-- LIQUIDATION is registered in public.stats_flow_words with side = 'moved': a re-denomination of
-- wealth the house already owned, not new money. While the economy is closed and its purses lit,
-- public.mint_guard refuses only a positive MINTED kind (0240:236-259); a 'moved' kind passes.
-- This file's probe proves both under the same settings — a minted FOUNDING refused, the
-- LIQUIDATION that follows it credited.
--
-- ── THE ORDER OF THE TWO MIGRATIONS ────────────────────────────────────────────────────────────
-- 0282 MUST be applied before 0283. Migrations deploy in strict number order, so the value read
-- here is the pre-rebase catalogue. The function that does the work is created, called and
-- DROPPED inside this one transaction, so it cannot be called again once the prices have moved.
--
-- ── WHAT IT DOES NOT TOUCH ─────────────────────────────────────────────────────────────────────
-- No city purse (port_treasury) moves: this is a re-denomination of a house's own wealth, not a
-- sale to a city, so no treasury flow, no profit tax, no dock fee, no SOLD event and no market
-- stock is written. No row of public.goods changes here; 0283 owns that.
--
-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
-- Its own probe only: a throwaway player, fleet, ship + cargo and one storage row are inserted,
-- the liquidation is run again (the real houses are already empty), and the probe's own credit,
-- ledger row, zeroed cargo / cargo_basis and deleted storage are asserted. The whole probe runs
-- in a plpgsql subtransaction that is deliberately rolled back; the rollback is checked by the
-- probe's own ids, never by a sum over a live table. While closed and lit, a positive MINTED kind
-- is proven refused beside the liquidation that passes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.player_storage') is null
     or to_regclass('public.stats_flow_words') is null
     or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.mint_guard(text,bigint)') is null then
    raise exception '0282 refuses: the chain is missing a table or function this file cashes out through';
  end if;
  if exists (select 1 from public.stats_flow_words where kind = 'LIQUIDATION') then
    raise exception '0282 refuses: LIQUIDATION is already a flow kind — this one-time backfill has run';
  end if;
  if to_regprocedure('public.cash_out_holds()') is not null then
    raise exception '0282 refuses: public.cash_out_holds() already exists';
  end if;
end $guard$;

-- ── 1. THE WINDOW (taken inside cash_out_holds, §3) ───────────────────────────────────────────
-- SHARE conflicts with the ROW EXCLUSIVE lock every INSERT / UPDATE / DELETE takes, so a live
-- trade cannot add or move a good between the value this file reads and the hold it zeroes. The
-- lock is taken at the TOP of the function, not here: db push applies each top-level statement in
-- its own transaction, so a top-level LOCK TABLE has no transaction to live in (SQLSTATE 25P01).
-- lock_timeout makes a busy quay fail the push cleanly instead of waiting on the live game.

-- ── 2. THE WORD: a re-denomination is MOVED wealth, not new gold ──────────────────────────────
insert into public.stats_flow_words (kind, side, word, ord) values
  ('LIQUIDATION', 'moved', 'Goods cashed out', 42);

-- ── 3. THE ONE LIQUIDATION ────────────────────────────────────────────────────────────────────
-- ONE authority for "a hold becomes cash": it prices every held good at goods.base_value, writes
-- ONE LIQUIDATION credit per house through public.credit, then empties both holds. Created,
-- called, and dropped inside this transaction — it is a one-time backfill, not a live verb.
create function public.cash_out_holds()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $co$
declare
  v_bad   text;
  v_cargo numeric := 0;
  v_store numeric := 0;
  v_n     int := 0;
  v_paid  bigint := 0;
  r       record;
begin
  -- THE WINDOW (§1): the SHARE lock is taken HERE so the read of each hold and its zeroing are
  -- one transaction (a top-level LOCK TABLE has no transaction under db push's per-statement apply).
  perform set_config('lock_timeout', '5s', true);
  lock table public.ships, public.player_storage, public.goods in share mode;

  -- A hold this file cannot price is a hold it must not destroy: refuse before any row moves.
  select string_agg(o.code, ', ' order by o.code) into v_bad
    from (select distinct e.key as code
            from public.ships s
            cross join lateral jsonb_each(s.cargo) e
            left join public.goods g on g.code = e.key
           where g.id is null) o;
  if v_bad is not null then
    raise exception '0282 refuses: cargo names good code(s) the catalogue does not have: %', v_bad;
  end if;
  select string_agg(format('%s on %s', e.key, s.name), ', ') into v_bad
    from public.ships s
    cross join lateral jsonb_each(s.cargo) e
   where (e.value)::text::numeric < 0;
  if v_bad is not null then
    raise exception '0282 refuses: a negative cargo cannot be cashed out: %', v_bad;
  end if;

  select coalesce(sum((e.value)::text::numeric), 0) into v_cargo
    from public.ships s cross join lateral jsonb_each(s.cargo) e
   where (e.value)::text::numeric > 0;
  select coalesce(sum(ps.qty), 0) into v_store
    from public.player_storage ps where ps.qty > 0;

  -- ONE credit per house for the whole hold: cargo and shed together, at the catalogue's value.
  -- Ordered by id so two transactions cashing out at the same moment take the same order.
  for r in
    select player_id, round(sum(qty * base_value))::bigint as value
      from (select f.player_id, (e.value)::text::numeric as qty, g.base_value
              from public.ships s
              join public.fleets f on f.id = s.fleet_id
              cross join lateral jsonb_each(s.cargo) e
              join public.goods g on g.code = e.key
             where (e.value)::text::numeric > 0
            union all
            select ps.player_id, ps.qty, g.base_value
              from public.player_storage ps
              join public.goods g on g.id = ps.good_id
             where ps.qty > 0) held
     group by player_id
     order by player_id
  loop
    perform public.credit(r.player_id, 'LIQUIDATION', r.value, null);
    v_n    := v_n + 1;
    v_paid := v_paid + r.value;
  end loop;

  -- The goods that were paid for leave in the same breath: the hold and its cost basis together
  -- (0081's column, including a basis key left with no tuns behind it), and the shed rows deleted
  -- rather than zeroed — the removal 0070/0281 performs.
  update public.ships
     set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
   where cargo <> '{}'::jsonb or cargo_basis <> '{}'::jsonb;
  delete from public.player_storage;

  return jsonb_build_object('players', v_n, 'ducats', v_paid,
                            'cargo_units', v_cargo, 'storage_units', v_store);
end $co$;

revoke all on function public.cash_out_holds() from public, anon, authenticated;

-- ── 4. THE BACKFILL, ONCE ─────────────────────────────────────────────────────────────────────
do $run$
declare v_summary jsonb;
begin
  v_summary := public.cash_out_holds();
  raise notice '0282 receipt: % house(s) cashed out — % ducat(s) credited for % unit(s) aboard and % unit(s) ashore',
    v_summary->>'players', v_summary->>'ducats', v_summary->>'cargo_units', v_summary->>'storage_units';
end $run$;

-- ── 5. SELF-ASSERT (its own probe, rolled back) ───────────────────────────────────────────────
do $probe$
declare
  v_player uuid := '00000000-0282-4000-8000-000000000001';
  v_fleet  uuid;
  v_port   uuid;
  v_class  uuid;
  v_good   uuid;
  v_code   text;
  v_base   numeric;
  v_cargo  numeric := 12;
  v_store  numeric := 7;
  v_expect bigint;
  v_after  bigint;
  v_bad    int;
  v_res    jsonb;
begin
  begin
    select id into v_port from public.ports where kind = 'HARBOUR' order by code limit 1;
    select id into v_class from public.ship_classes order by code limit 1;
    select g.id, g.code, g.base_value into v_good, v_code, v_base
      from public.goods g order by g.base_value desc, g.code limit 1;

    insert into public.players (id, company_name, ducats)
    values (v_player, 'Casa Liquidada 0282', 0);

    insert into public.fleets (player_id, name, status, port_id)
    values (v_player, 'Probe 0282', 'DOCKED', v_port)
    returning id into v_fleet;

    insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, cargo, cargo_basis)
    values (v_player, v_fleet, v_class, 'Probe 0282', 100, 1,
            jsonb_build_object(v_code, v_cargo), jsonb_build_object(v_code, 1.00));

    insert into public.player_storage (player_id, port_id, good_id, qty, basis)
    values (v_player, v_port, v_good, v_store, 2.00);

    v_expect := round(v_cargo * v_base + v_store * v_base)::bigint;

    -- THE GUARD'S SETTING IS PROVEN ON, NOT ASSUMED: closed and lit, a minted kind is refused ...
    update public.world_config set value = 'true'::jsonb
     where key in ('economy_closed', 'city_treasury_enabled');
    begin
      perform public.credit(v_player, 'FOUNDING', 1);
      raise exception '0282 self-assert FAIL: a minted kind was credited while the economy was closed and lit';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_NO_NEW_GOLD:%' then raise; end if;
    end;

    -- ... and LIQUIDATION passes under exactly those settings.
    v_res := public.cash_out_holds();

    select ducats into v_after from public.players where id = v_player;
    if v_after is distinct from v_expect then
      raise exception '0282 self-assert FAIL: the probe was credited % rather than %', v_after, v_expect;
    end if;
    select count(*) into v_bad from public.ledger
     where player_id = v_player and kind = 'LIQUIDATION' and ducats_delta = v_expect;
    if v_bad <> 1 then
      raise exception '0282 self-assert FAIL: the probe has % LIQUIDATION ledger row(s), expected exactly one', v_bad;
    end if;
    select count(*) into v_bad from public.ledger where player_id = v_player;
    if v_bad <> 1 then
      raise exception '0282 self-assert FAIL: the probe has % ledger row(s) in all, expected one', v_bad;
    end if;
    select count(*) into v_bad from public.ships s
     where s.fleet_id = v_fleet and (s.cargo <> '{}'::jsonb or s.cargo_basis <> '{}'::jsonb);
    if v_bad <> 0 then
      raise exception '0282 self-assert FAIL: % probe hull(s) still carry cargo or its basis', v_bad;
    end if;
    select count(*) into v_bad from public.player_storage where player_id = v_player;
    if v_bad <> 0 then
      raise exception '0282 self-assert FAIL: % probe storage row(s) survived the cash-out', v_bad;
    end if;
    if v_res is null or not (v_res ? 'ducats') or not (v_res ? 'players') then
      raise exception '0282 self-assert FAIL: the liquidation returned no receipt: %', v_res;
    end if;

    raise exception using errcode = 'ZX282', message = 'probe ok';
  exception when sqlstate 'ZX282' then
    null;
  end;

  -- THE PROBE LEFT NOTHING BEHIND (its own ids only; never a sum over a live table).
  if exists (select 1 from public.players where id = v_player)
     or exists (select 1 from public.ledger where player_id = v_player)
     or exists (select 1 from public.player_storage where player_id = v_player) then
    raise exception '0282 self-assert FAIL: the rolled-back probe left a row behind';
  end if;

  raise notice '0282 self-assert ok: the one-time cash-out is THE liquidation — one LIQUIDATION credit per house for cargo + shed at goods.base_value, the hold and its cargo_basis zeroed together, the shed rows deleted, no treasury flow, no event. PROVEN on its own rolled-back probe: 19 units (12 aboard + 7 ashore) of one good credited exactly once at base_value, cargo/cargo_basis empty and the storage row gone; while closed and lit a minted FOUNDING is refused (E_NO_NEW_GOLD) beside the LIQUIDATION that passes; the probe leaves no row behind. The helper is dropped below, so it cannot run again after 0283 moves the prices';
end $probe$;

-- ── 6. THE HELPER LEAVES WITH ITS ONE USE ────────────────────────────────────────────────────
drop function public.cash_out_holds();

do $done$
begin
  if to_regprocedure('public.cash_out_holds()') is not null then
    raise exception '0282 self-assert FAIL: the one-time liquidation helper survived the migration';
  end if;
  if not exists (select 1 from public.stats_flow_words where kind = 'LIQUIDATION' and side = 'moved') then
    raise exception '0282 self-assert FAIL: LIQUIDATION is not registered as moved wealth';
  end if;
end $done$;
