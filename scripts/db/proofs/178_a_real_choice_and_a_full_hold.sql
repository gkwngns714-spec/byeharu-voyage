-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 178 - A REAL CHOICE AND A FULL HOLD  (migration 0475; docs/design/roadmap-2026-11-23.md slice 4; docs/design/playable-2026-11-22.md
--   section 6, findings 7, 8, 13; docs/dev-log/2026-11-23-near-choice.md)
--
--   The migration's self-assert holds every hunk to its pre-image dark, on copies. This proof plays what a fresh company meets with the
--   first hour lit, dark and lit: the Trade cards (world.best_sales), the trip board a moved card opens (world.good_board at the card's
--   units), the one press that buys both goods (cmd.issue_lines: BUY, BUY at the quay), and the near rule's horizon
--   (public.first_hour_near_seconds). Rolled back by proof.mjs.
--
--   THE MARKET IS PINNED (proof.pin_market, scripts/db/market-fixture.mjs: the one authority, this proof's own key). Which Lisbon goods pay
--   within the horizon, which card moves and which load is topped up are facts of the market, and every from-zero apply deals another
--   (0010's random() drift): on main's from-zero run of 2026-11-24 every Lisbon good had a paying sale near by, so no card was far and
--   NC_MARK had nothing to mark; three of ten other deals do the same. The pinned market is drawn on the authored codes, the same in every
--   world: Lisbon holds near cards and far ones, cards move, loads are topped up. Every assertion is as it was.
--
-- @pass NC_DARK    dark: no card carries `spread`, `top` or `near`; a Trading 5 newcomer has no near horizon (0472's rule)
-- @pass NC_SPREAD  lit: at Lisbon and Amsterdam a card moved off a harbour holding the knob's count, to a paying harbour of its good
--                  within the knob of its best an hour of play; the moved card is the trip board's own row (profit and cost to the
--                  coin); the cards name no fewer harbours than dark (a move may land on a harbour already named)
-- @pass NC_MARK    lit: a paying card bought here says `near`; at Lisbon one is near and one is far (a far sale is marked, not hidden)
-- @pass NC_TOPUP   lit: a card's second good is another good, within a quarter of her purse and the room left, its cost world.quote's
--                  to the coin, its sale there above its cost; the one press (BUY, BUY) puts both in her hold
-- @pass NC_END     lit: a Trading 5 newcomer keeps her horizon; founded three hours ago, or owning the knob's ships, she has none
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0475-4000-8000-0000000000a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_fa   uuid;
  v_d    jsonb;
  v_s    jsonb;
  v_r    jsonb;
  v_row  jsonb;
  v_card jsonb;
  v_purse numeric;
  v_per  int;
  v_hd   int := 0;
  v_hl   int := 0;
  v_n    int := 0;
  v_m    int := 0;
  v_k    int := 0;
  v_q    record;
  x      record;
  p      record;
begin
  v_r := proof.pin_market('00000000-0475-4000-8000-000000000174'::uuid, 'proof-178');
  if (v_r ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 178 FAILED: the market was not pinned: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'first_hour_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'near_choice_enabled';
  v_a := public.new_house(c_a, 'Casa da Escolha A 178', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a limit 1;
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 5)
    on conflict (player_id, track) do update set level = excluded.level;
  v_per := public.wc_int('near_choice_per_harbour');

  -- ── NC_DARK ──
  perform cmd.assume_identity(c_a);
  if public.first_hour_near_seconds(v_a) is not null then
    raise exception 'PROOF 178 FAILED: dark, a Trading 5 company has a near horizon (0472: under Trading 5 only)';
  end if;
  update public.house_level_marks set level = 1 where player_id = v_a and track = 'trading';
  for p in select pt.id, pt.code from public.ports pt where pt.kind = 'HARBOUR' and pt.code in ('LIS', 'AMS') order by pt.code loop
    update public.fleets set port_id = p.id where id = v_fa;
    v_d := world.best_sales(v_fa, p.id);
    if exists (select 1 from jsonb_array_elements(v_d -> 'goods') e where e ? 'spread' or e ? 'top' or e ? 'near') then
      raise exception 'PROOF 178 FAILED: dark, a card at % carries a lit key: %', p.code, v_d -> 'goods';
    end if;
    v_hd := v_hd + (select count(distinct e ->> 'port') from jsonb_array_elements(v_d -> 'goods') e where e ->> 'port' is not null);
  end loop;
  raise notice 'PASS: NC_DARK — dark: no card at Lisbon or Amsterdam carries spread, top or near; a Trading 5 company has no horizon.';

  update public.world_config set value = 'true'::jsonb where key = 'near_choice_enabled';

  -- ── NC_SPREAD ──
  for p in select pt.id, pt.code from public.ports pt where pt.kind = 'HARBOUR' and pt.code in ('LIS', 'AMS') order by pt.code loop
    update public.fleets set port_id = p.id where id = v_fa;
    update public.world_config set value = 'false'::jsonb where key = 'near_choice_enabled';
    v_d := world.best_sales(v_fa, p.id);
    update public.world_config set value = 'true'::jsonb where key = 'near_choice_enabled';
    v_s := world.best_sales(v_fa, p.id);
    if (v_s ->> 'cut')::boolean or (v_d ->> 'cut')::boolean then
      raise exception 'PROOF 178 FAILED: the cards at % ran out of their budget (a cut answer cannot be compared)', p.code;
    end if;
    v_hl := v_hl + (select count(distinct e ->> 'port') from jsonb_array_elements(v_s -> 'goods') e where e ->> 'port' is not null);
    for x in
      select n.e as now, o.e as was, g.id as good
        from jsonb_array_elements(v_s -> 'goods') n(e)
        join jsonb_array_elements(v_d -> 'goods') o(e) on o.e ->> 'good' = n.e ->> 'good'
        join public.goods g on g.code = n.e ->> 'good'
       where n.e ->> 'port' is distinct from o.e ->> 'port'
    loop
      v_n := v_n + 1;
      if x.now ->> 'spread' is distinct from x.was ->> 'port' or not (x.now ->> 'pays')::boolean
         or (select count(*) from jsonb_array_elements(v_s -> 'goods') e where e ->> 'port' = x.was ->> 'port') < v_per
         or (x.now ->> 'near')::boolean is distinct from (x.was ->> 'seconds')::numeric <= public.first_hour_near_seconds(v_a) then
        raise exception 'PROOF 178 FAILED: lit, at % the card of % moved % -> %: %', p.code, x.now ->> 'good', x.was ->> 'port', x.now ->> 'port', x.now;
      end if;
      -- within the knob of its best an hour of play
      if (x.now ->> 'profit')::numeric / ((x.now ->> 'seconds')::numeric + public.wc_num('near_choice_turn_seconds'))
         < (x.was ->> 'profit')::numeric / (greatest((x.was ->> 'seconds')::numeric, 1) + public.wc_num('near_choice_turn_seconds'))
           * public.wc_num('near_choice_similar_pct') / 100 * 0.99 then
        raise exception 'PROOF 178 FAILED: lit, at % the card of % moved to a harbour under the knob: % against %', p.code, x.now ->> 'good', x.now, x.was;
      end if;
      -- the trip the moved card opens: world.good_board bought here at the card's units; its row for the new harbour is the card
      v_r := world.good_board(x.good, v_fa, p.id, (x.now ->> 'units')::numeric);
      select e into v_row from jsonb_array_elements(v_r -> 'sell') e where e ->> 'port' = x.now ->> 'port';
      if v_row is not null and (v_row ->> 'units')::numeric = (x.now ->> 'units')::numeric then
        v_m := v_m + 1;
        if (v_row ->> 'profit')::numeric is distinct from (x.now ->> 'profit')::numeric
           or (v_row ->> 'cost')::numeric is distinct from (x.now ->> 'cost')::numeric then
          raise exception 'PROOF 178 FAILED: lit, the moved card of % (% at %, cost %) is not the board''s row (profit %, cost %)',
            x.now ->> 'good', x.now ->> 'profit', x.now ->> 'port', x.now ->> 'cost', v_row ->> 'profit', v_row ->> 'cost';
        end if;
      end if;
    end loop;
  end loop;
  if v_n = 0 or v_m = 0 or v_hl < v_hd then
    raise exception 'PROOF 178 FAILED: lit, % cards moved, % held to the board, harbours % dark against % lit: nothing was proved', v_n, v_m, v_hd, v_hl;
  end if;
  raise notice 'PASS: NC_SPREAD — lit: % cards moved off a harbour holding % cards, % held to the trip board''s row to the coin; harbours named % dark, % lit (Lisbon and Amsterdam).', v_n, v_per, v_m, v_hd, v_hl;

  -- ── NC_MARK ──
  update public.fleets set port_id = v_lis where id = v_fa;
  v_s := world.best_sales(v_fa, v_lis);
  if exists (select 1 from jsonb_array_elements(v_s -> 'goods') e
              where e ->> 'basis' <> 'on_board' and (e ->> 'pays')::boolean and e ->> 'have' is null and not (e ? 'near'))
     or not exists (select 1 from jsonb_array_elements(v_s -> 'goods') e where (e ->> 'near')::boolean)
     or not exists (select 1 from jsonb_array_elements(v_s -> 'goods') e
                     where (e ->> 'near')::boolean is false and (e ->> 'seconds')::numeric > public.first_hour_near_seconds(v_a)) then
    raise exception 'PROOF 178 FAILED: lit, the cards at Lisbon are not marked near and far: %', v_s -> 'goods';
  end if;
  raise notice 'PASS: NC_MARK — lit: every paying card at Lisbon says near or far; % near, % far (shown, marked).',
    (select count(*) from jsonb_array_elements(v_s -> 'goods') e where (e ->> 'near')::boolean),
    (select count(*) from jsonb_array_elements(v_s -> 'goods') e where (e ->> 'near')::boolean is false);

  -- ── NC_TOPUP ──
  select p2.ducats into v_purse from public.players p2 where p2.id = v_a;
  for x in
    select e as card, g.id as good, t.id as top_good, t.bulk as top_bulk, g.bulk as bulk, pt.id as dest
      from jsonb_array_elements(v_s -> 'goods') e
      join public.goods g on g.code = e ->> 'good'
      join public.goods t on t.code = e -> 'top' ->> 'good'
      join public.ports pt on pt.code = e ->> 'port' and pt.kind = 'HARBOUR'
  loop
    v_k := v_k + 1;
    select q.units, q.total into v_q from world.quote(v_lis, x.top_good, (x.card -> 'top' ->> 'units')::numeric, 'buy', null, v_fa) q;
    if x.card -> 'top' ->> 'good' = x.card ->> 'good' or (x.card -> 'top' ->> 'profit')::numeric <= 0
       or (x.card -> 'top' ->> 'cost')::numeric > v_purse * public.wc_num('near_choice_topup_coin_pct') / 100
       or (x.card -> 'top' ->> 'cost')::numeric + (x.card ->> 'cost')::numeric > v_purse
       or v_q.total is distinct from (x.card -> 'top' ->> 'cost')::bigint or v_q.units is distinct from (x.card -> 'top' ->> 'units')::numeric
       or (x.card ->> 'units')::numeric * x.bulk + (x.card -> 'top' ->> 'units')::numeric * x.top_bulk > public.fleet_free_hold(v_fa)
       or (select q.total from world.quote(x.dest, x.top_good, (x.card -> 'top' ->> 'units')::numeric, 'sell', null, v_fa) q)
            < (x.card -> 'top' ->> 'cost')::numeric + (x.card -> 'top' ->> 'profit')::numeric then
      raise exception 'PROOF 178 FAILED: lit, the second good of % is % (buy quote % for %, purse %)', x.card ->> 'good', x.card -> 'top', v_q.total, v_q.units, v_purse;
    end if;
    if v_card is null then
      v_card := x.card;
    end if;
  end loop;
  if v_card is null then
    raise exception 'PROOF 178 FAILED: lit, no card at Lisbon names a second good: %', v_s -> 'goods';
  end if;
  -- THE ONE PRESS: the first good and the second, bought at the quay (the lines the client writes before its SAIL)
  v_r := cmd.issue_lines(v_fa, jsonb_build_array(
           jsonb_build_object('text', format('BUY %s %s', v_card ->> 'good', v_card ->> 'units')),
           jsonb_build_object('text', format('BUY %s %s', v_card -> 'top' ->> 'good', v_card -> 'top' ->> 'units'))), null);
  if (v_r ->> 'ok')::boolean is not true
     or exists (select 1 from jsonb_array_elements(v_r -> 'orders') o where o ->> 'status' in ('failed', 'cancelled'))
     or coalesce(public.fleet_cargo_qty(v_fa, v_card ->> 'good'), 0) <> (v_card ->> 'units')::numeric
     or coalesce(public.fleet_cargo_qty(v_fa, v_card -> 'top' ->> 'good'), 0) <> (v_card -> 'top' ->> 'units')::numeric then
    raise exception 'PROOF 178 FAILED: lit, the one press did not buy both (% and %): %', v_card ->> 'good', v_card -> 'top', v_r;
  end if;
  raise notice 'PASS: NC_TOPUP — lit: % cards at Lisbon name a second good, each its buy quote to the coin, within a quarter of her purse and the room; % % and % % bought in one press.',
    v_k, v_card ->> 'units', v_card ->> 'good', v_card -> 'top' ->> 'units', v_card -> 'top' ->> 'good';

  -- ── NC_END ──
  update public.house_level_marks set level = 5 where player_id = v_a and track = 'trading';
  if public.first_hour_near_seconds(v_a) is distinct from public.wc_num('first_hour_trip_hours') * 3600 then
    raise exception 'PROOF 178 FAILED: lit, a Trading 5 newcomer has horizon % (want the first hour''s)', public.first_hour_near_seconds(v_a);
  end if;
  update public.world_config set value = '1'::jsonb where key = 'near_choice_ships_below';
  if public.first_hour_near_seconds(v_a) is not null then
    raise exception 'PROOF 178 FAILED: lit, a company owning the knob''s ships still has a near horizon';
  end if;
  update public.world_config set value = '3'::jsonb where key = 'near_choice_ships_below';
  update public.players set created_at = now() - interval '3 hours' where id = v_a;
  if public.first_hour_near_seconds(v_a) is not null then
    raise exception 'PROOF 178 FAILED: lit, a company founded three hours ago still has a near horizon';
  end if;
  raise notice 'PASS: NC_END — lit: a Trading 5 newcomer keeps her % s horizon; owning the knob''s ships, or founded three hours ago, none.',
    public.wc_num('first_hour_trip_hours') * 3600;
end $p$;
