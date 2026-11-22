-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 175 - THE FIRST HOUR  (migration 0472; docs/design/playable-2026-11-22.md section 5, S1-S3; docs/dev-log/2026-11-22-first-hour.md)
--
--   The migration's self-assert holds every hunk to its pre-image dark, on copies. This proof plays what a fresh Lisbon company meets,
--   dark and lit: the Trade cards (world.best_sales), the trip board a card opens (world.good_board at the card's units), the yard's
--   quote (world.hull_quote) and its order door (cmd.order_hull). Her Trading level is the mark she was last paid for
--   (public.house_level_marks), set here. Rolled back by proof.mjs.
--
-- @pass FH_DARK     dark: a card bought at Lisbon is priced for the full load (at least one costs more than half her coin) and her second
--                   Barca's order is labour + materials + the knob's fee, with no `first`
-- @pass FH_HALF     lit: every card bought at Lisbon is priced at no more than least(the dark units, floor(purse / 2 / ask)) units, and
--                   a card is the trip board's own row for those units (profit and cost to the coin): the one number the sheet opens at
-- @pass FH_NEAR     lit, a horizon of 0.04 h: a company at Trading 1 is offered a paying sale within it where one at Trading 5 is offered
--                   a farther one; never a nearer loss
-- @pass FH_ORDER    lit: her second Barca is quoted at the floor (`first`), the door refuses it to her 40,000 and takes it from 60,000;
--                   the next hull is the knob's price again
-- @pass FH_DISCOUNT lit with Trading's unlocks: at Trading 5 the raised fee is 10 % less (labour and materials untouched)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0472-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0472-4000-8000-0000000000b1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_b    uuid;
  v_fa   uuid;
  v_fb   uuid;
  v_s    jsonb;
  v_d    jsonb;
  v_q    jsonb;
  v_r    jsonb;
  v_row  jsonb;
  v_purse numeric;
  v_floor bigint;
  v_n    int := 0;
  v_m    int := 0;
  v_k    int := 0;
  x      record;
  p      record;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('level_perks_on', 'yard_order_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('first_hour_enabled', 'level_unlocks_enabled');
  v_a := public.new_house(c_a, 'Casa da Hora A 175', 'PRT');
  v_b := public.new_house(c_b, 'Casa da Hora B 175', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a limit 1;
  select f.id into v_fb from public.fleets f where f.player_id = v_b limit 1;
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 1), (v_b, 'trading', 5)
    on conflict (player_id, track) do update set level = excluded.level;
  v_floor := public.wc_num('first_hull_order_floor')::bigint;

  -- ── FH_DARK ──
  perform cmd.assume_identity(c_a);
  select p2.ducats into v_purse from public.players p2 where p2.id = v_a;
  v_d := world.best_sales(v_fa, v_lis);
  if not exists (select 1 from jsonb_array_elements(v_d -> 'goods') e
                  where e ->> 'basis' <> 'on_board' and (e ->> 'cost')::numeric > v_purse * 0.5) then
    raise exception 'PROOF 175 FAILED: dark, no card at Lisbon costs more than half her coin: %', v_d -> 'goods';
  end if;
  v_q := world.hull_quote(v_lis, 'barca');
  if v_q ? 'first'
     or (v_q ->> 'fee')::bigint <> round(((v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint then
    raise exception 'PROOF 175 FAILED: dark, her second Barca is %', v_q;
  end if;
  raise notice 'PASS: FH_DARK — dark: the cards at Lisbon price the full load (purse %); her second Barca % (fee % at the knob).', v_purse, v_q ->> 'price', v_q ->> 'fee';

  update public.world_config set value = 'true'::jsonb where key = 'first_hour_enabled';

  -- ── FH_HALF ──
  v_s := world.best_sales(v_fa, v_lis);
  if (v_s ->> 'cut')::boolean or (v_d ->> 'cut')::boolean then
    raise exception 'PROOF 175 FAILED: the cards ran out of their budget (a cut answer cannot be compared)';
  end if;
  for x in
    select n.e as card, (o.e ->> 'units')::numeric as u_dark, g.id as good,
           (select greatest(1, floor(v_purse * 0.5 / q.ask)) from world.price(v_lis, g.id) q where q.ask > 0) as half
      from jsonb_array_elements(v_s -> 'goods') n(e)
      join jsonb_array_elements(v_d -> 'goods') o(e) on o.e ->> 'good' = n.e ->> 'good'
      join public.goods g on g.code = n.e ->> 'good'
     where n.e ->> 'basis' <> 'on_board' and n.e ->> 'port' is not null and o.e ->> 'port' is not null
  loop
    v_n := v_n + 1;
    if (x.card ->> 'units')::numeric > least(x.u_dark, x.half) then
      raise exception 'PROOF 175 FAILED: lit, % is priced for % units (dark %, half her coin %)', x.card ->> 'good', x.card ->> 'units', x.u_dark, x.half;
    end if;
    -- the trip the card opens: world.good_board bought here at the card's units; its row for the card's city is the card
    v_r := world.good_board(x.good, v_fa, v_lis, (x.card ->> 'units')::numeric);
    select e into v_row from jsonb_array_elements(v_r -> 'sell') e where e ->> 'port' = x.card ->> 'port';
    if v_row is not null and (v_row ->> 'units')::numeric = (x.card ->> 'units')::numeric then
      v_m := v_m + 1;
      if (v_row ->> 'profit')::numeric is distinct from (x.card ->> 'profit')::numeric
         or (v_row ->> 'cost')::numeric is distinct from (x.card ->> 'cost')::numeric then
        raise exception 'PROOF 175 FAILED: lit, the card of % (% units, profit %, cost %) is not the board''s row (profit %, cost %)',
          x.card ->> 'good', x.card ->> 'units', x.card ->> 'profit', x.card ->> 'cost', v_row ->> 'profit', v_row ->> 'cost';
      end if;
    end if;
    if (x.card ->> 'units')::numeric < x.u_dark then
      v_k := v_k + 1;
    end if;
  end loop;
  if v_n = 0 or v_m = 0 or v_k = 0 then
    raise exception 'PROOF 175 FAILED: lit, % cards, % held to the board, % halved: nothing was proved', v_n, v_m, v_k;
  end if;
  raise notice 'PASS: FH_HALF — lit: % cards bought at Lisbon, % priced at half her coin, % held to the trip board''s own row to the coin.', v_n, v_k, v_m;

  -- ── FH_NEAR ──
  update public.world_config set value = '0.04'::jsonb where key = 'first_hour_trip_hours';
  v_n := 0;
  for p in select pt.id, pt.code from public.ports pt where pt.kind = 'HARBOUR' and pt.code in ('LIS', 'LON', 'GOA', 'VEN', 'AMS') order by pt.code loop
    -- ONE company, her mark moved (two companies sail different rolled hulls, so their cards differ for that alone)
    update public.fleets set port_id = p.id where id = v_fa;
    perform cmd.assume_identity(c_a);
    update public.house_level_marks set level = 1 where player_id = v_a and track = 'trading';
    v_s := world.best_sales(v_fa, p.id);
    update public.house_level_marks set level = 5 where player_id = v_a and track = 'trading';
    v_d := world.best_sales(v_fa, p.id);
    update public.house_level_marks set level = 1 where player_id = v_a and track = 'trading';
    for x in
      select a.e as near, b.e as far
        from jsonb_array_elements(v_s -> 'goods') a(e)
        join jsonb_array_elements(v_d -> 'goods') b(e) on b.e ->> 'good' = a.e ->> 'good'
       where a.e ->> 'port' is distinct from b.e ->> 'port'
    loop
      if not (x.near ->> 'pays')::boolean or (x.near ->> 'seconds')::numeric > 0.04 * 3600
         or (x.far ->> 'seconds')::numeric <= 0.04 * 3600 then
        raise exception 'PROOF 175 FAILED: at %, Trading 1 is offered % and Trading 5 % (horizon 0.04 h)', p.code, x.near, x.far;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  if v_n = 0 then
    raise exception 'PROOF 175 FAILED: no card differed between Trading 1 and Trading 5 at a 0.04 h horizon: the preference was not seen';
  end if;
  update public.world_config set value = '2'::jsonb where key = 'first_hour_trip_hours';
  update public.fleets set port_id = v_lis where id = v_fa;
  raise notice 'PASS: FH_NEAR — lit, horizon 0.04 h: % cards where Trading 1 was offered a paying sale within it and Trading 5 a farther one.', v_n;

  -- ── FH_ORDER ──
  perform cmd.assume_identity(c_a);
  v_q := world.hull_quote(v_lis, 'barca');
  if (v_q ->> 'first') is distinct from 'true' or (v_q ->> 'price')::bigint <> greatest(v_floor, (v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint
       + round(((v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint) then
    raise exception 'PROOF 175 FAILED: lit, her second Barca is quoted % (floor %)', v_q, v_floor;
  end if;
  v_r := cmd.order_hull(v_lis, 'barca');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_FUNDS' then
    raise exception 'PROOF 175 FAILED: lit, the door took her second Barca from %: %', v_purse, v_r;
  end if;
  update public.players set ducats = 60000 where id = v_a;
  v_r := cmd.order_hull(v_lis, 'barca');
  if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'price')::bigint <> (v_q ->> 'price')::bigint
     or (select p2.ducats from public.players p2 where p2.id = v_a) <> 60000 - (v_q ->> 'price')::bigint then
    raise exception 'PROOF 175 FAILED: lit, the door at 60,000: % (quoted %)', v_r, v_q ->> 'price';
  end if;
  -- the next hull (one ship and one on order): the knob's price, no `first`
  v_r := public.hull_order_price(v_a, v_lis, 'barca');
  if v_r ? 'first' or (v_r ->> 'fee')::bigint <> round(((v_r ->> 'labour')::bigint + (v_r ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint then
    raise exception 'PROOF 175 FAILED: lit, her third hull is %', v_r;
  end if;
  raise notice 'PASS: FH_ORDER — lit: her second Barca % (first), refused to %, taken from 60,000; the next %.', v_q ->> 'price', v_purse, v_r ->> 'price';

  -- ── FH_DISCOUNT ──
  update public.world_config set value = 'true'::jsonb where key = 'level_unlocks_enabled';
  v_r := public.hull_order_price(v_b, v_lis, 'barca');   -- B: one ship, none on order, paid for Trading 5
  if (v_r ->> 'first') is distinct from 'true'
     or (v_r ->> 'fee')::bigint <> round((v_floor - (v_r ->> 'labour')::bigint - (v_r ->> 'materials')::bigint) * 0.9)::bigint
     or (v_r ->> 'labour') <> (v_q ->> 'labour') or (v_r ->> 'materials') <> (v_q ->> 'materials') then
    raise exception 'PROOF 175 FAILED: lit, at Trading 5 her second Barca is % (Trading 1: %)', v_r, v_q;
  end if;
  raise notice 'PASS: FH_DISCOUNT — lit, Trading 5: her second Barca % against % at Trading 1 (the raised fee 10 %% less).', v_r ->> 'price', v_q ->> 'price';
end $p$;
