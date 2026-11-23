-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 182 - GOODS MASTERY  (migration 0479; docs/design/roadmap-2026-11-23.md slice 11; docs/dev-log/2026-11-23-goods-mastery.md)
--
--   The migration's self-assert walks one level-10 good and one new good. This proof plays the ladder as production runs it: the
--   economy closed and the city purses lit (a sale is paid from the purse), the price through the one bid factor and its guard at the
--   quay's ask, the day's allowance and a SELL ALL that takes the bigger one, the money law (W), a merchant, the page and the cost.
--   Rolled back by proof.mjs. THE DAY: the allowance is a day's (trade_daily by world.game_day(now())); proof.mjs runs this file in ONE
--   transaction, so now() is one instant and no scene can straddle a midnight; every allowance compared is read in the same SELECT as
--   the day's traded units. Nothing reads world.best_sales (it is time-budgeted): its cards price through world.quote, which is proven here.
--
-- @pass GM_DARK       dark with a level-10 row: the bid factor is the city's, a sale's quote and the allowance are as before, a sale tells nothing
-- @pass GM_LADDER     the curve (1, 100, 250 ... 16,000 units), and a good's sales climbing it: level 1 at the first, up only when it rises
-- @pass GM_PRICE      lit: the bid is the city's x (1 + level x 0.005), held under the quay's ask; the sale is dearer by it, to the unit's rounding
-- @pass GM_ROUNDTRIP  lit at level 10: a buy and the sale of the same units at one quay never pay
-- @pass GM_CAP        lit at level 10: the day's allowance x 1.5, and a SELL ALL sells all of it (more than the allowance dark)
-- @pass GM_MONEY      a level-10 sale: the purse paid the SOLD total, the house got it, W unchanged to the ducat
-- @pass GM_MERCHANT   a merchant: no row written, her quote's bid the city's, her allowance as before
-- @pass GM_READ       world.goods_mastery(): her goods by level, the specialty, the ladder and the steps
-- @pass GM_COST       the two factors dark and lit, and a quote's terms, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- W: every ducat in the world (the purses, the houses, the coin aboard), as proofs 45-154 count it
create function pg_temp.w_182() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;

-- she sells p_qty of good p_good where she lies (the hold filled to p_hold first; qty null: ALL); answers the SOLD payload and its id
create function pg_temp.sell_182(p_fleet uuid, p_good uuid, p_qty int, p_hold int) returns jsonb language plpgsql as $f$
declare
  v_code text := (select g.code from public.goods g where g.id = p_good);
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_was  uuid[];
begin
  v_was := array(select e.id from public.events e where e.player_id = v_pl and e.kind = 'SOLD');
  update public.ships s set cargo = jsonb_build_object(v_code, p_hold), cargo_basis = jsonb_build_object(v_code, 1) where s.fleet_id = p_fleet;
  perform cmd.do_sell(p_fleet, case when p_qty is null then jsonb_build_object('good', p_good, 'qty_mode', 'ALL')
                                    else jsonb_build_object('good', p_good, 'qty', p_qty) end);
  return (select e.payload || jsonb_build_object('_id', e.id) from public.events e
           where e.player_id = v_pl and e.kind = 'SOLD' and e.id <> all (v_was));
end
$f$;

do $p$
declare
  c_a     constant uuid := '00000000-0479-4000-8000-0000000000a1';
  v_set   uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_fa    uuid;
  v_npc   uuid;
  v_nfl   uuid;
  v_g1    uuid;
  v_c1    text;
  v_g2    uuid;
  v_c2    text;
  v_g3    uuid;
  v_r     jsonb;
  v_s     jsonb;
  v_f     record;
  v_w0    numeric;
  v_d0    bigint;
  v_p0    numeric;
  v_t     timestamptz;
  v_ms1   numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  v_ms4   numeric;
  i       int;
begin
  -- production's switches: the economy closed, the purses lit and well above their reserves
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.world_config set value = 'true'::jsonb
   where key in ('economy_closed', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
  -- three goods Setubal trades, of its deepest markets (the allowance holds the scenes' sales)
  select g.id, g.code into v_g1, v_c1 from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  select g.id, g.code into v_g2, v_c2 from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and g.id <> v_g1 and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  select g.id into v_g3 from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and g.id not in (v_g1, v_g2) and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  v_a := public.new_house(c_a, 'Casa da Mestria A 182', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.fleets f set status = 'DOCKED', port_id = v_set, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fa;
  update public.players p set ducats = 1000000 where p.id = v_a;
  select f.player_id, f.id into v_npc, v_nfl from public.fleets f join public.players p on p.id = f.player_id where p.is_npc order by f.id limit 1;
  insert into public.goods_mastery (player_id, good_id, units, level) values (v_a, v_g1, 16000, 10);
  perform cmd.assume_identity(c_a);

  -- ── GM_DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'goods_mastery_enabled';
  select k.q_bidf as bidf, public.city_bid_factor(v_set) as city, q.total as q_now, q0.total as q_pre,
         world.daily_cap_remaining(v_a, v_set, v_g1) as cap,
         public.daily_cap_base(v_a, v_set) * pg.stock_target
           - coalesce((select td.qty from public.trade_daily td where td.player_id = v_a and td.port_id = v_set and td.good_id = v_g1
                         and td.game_day = world.game_day()), 0) as cap_pre
    into v_f
    from world.quote_terms(v_set, v_g1, v_fa) k
   cross join world.quote(v_set, v_g1, 30, 'sell', null, v_fa) q
   cross join world.quote_priced(v_set, v_g1, 30, 'sell', null, v_fa, k.q_spread, k.q_nohag, k.q_tax, public.city_bid_factor(v_set)) q0
   cross join public.port_goods pg where pg.port_id = v_set and pg.good_id = v_g1;
  v_s := pg_temp.sell_182(v_fa, v_g1, 10, 40);
  if v_f.bidf <> v_f.city or v_f.q_now <> v_f.q_pre or v_f.cap <> greatest(0, v_f.cap_pre)
     or v_s ? 'mastery' or v_s is null or world.goods_mastery() is distinct from '{"on": false}'::jsonb
     or (select m.units from public.goods_mastery m where m.player_id = v_a and m.good_id = v_g1) <> 16000 then
    raise exception 'PROOF 182 FAILED: dark, mastery moved: % %', to_jsonb(v_f), v_s -> 'mastery';
  end if;
  raise notice 'PASS: GM_DARK — a level-10 row on her: bid % (the city''s), a 30-unit sale % (as before), allowance % (as before); her sale of % told nothing',
    v_f.bidf, v_f.q_now, round(v_f.cap, 1), v_c1;

  -- ── GM_LADDER ──
  update public.world_config set value = 'true'::jsonb where key = 'goods_mastery_enabled';
  if (select array_agg(public.goods_mastery_level(u) order by u) from unnest(array[0, 1, 99, 100, 249, 250, 499, 500, 999, 1000, 1999, 2000, 3499, 3500, 5999, 6000, 9999, 10000, 15999, 16000, 99999]) u)
     <> array[0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10] then
    raise exception 'PROOF 182 FAILED: the ladder is not 1, 100, 250, 500, 1,000, 2,000, 3,500, 6,000, 10,000, 16,000';
  end if;
  v_r := '[]'::jsonb;
  foreach i in array array[10, 90, 50, 100] loop
    v_s := pg_temp.sell_182(v_fa, v_g2, i, i);
    v_r := v_r || jsonb_build_array(v_s -> 'mastery');
  end loop;
  if (select jsonb_agg(jsonb_build_array((m ->> 'level')::int, (m ->> 'from')::int, (m ->> 'up')::boolean, (m ->> 'units')::numeric, (m ->> 'next')::numeric))
        from jsonb_array_elements(v_r) m)
     <> '[[1, 0, true, 10, 100], [2, 1, true, 100, 250], [2, 2, false, 150, 250], [3, 2, true, 250, 500]]'::jsonb
     or (select m.level from public.goods_mastery m where m.player_id = v_a and m.good_id = v_g2) <> 3 then
    raise exception 'PROOF 182 FAILED: the sales of % did not climb 1, 2, 2, 3: %', v_c2, v_r;
  end if;
  raise notice 'PASS: GM_LADDER — the curve 1 / 100 / 250 / 500 / 1,000 / 2,000 / 3,500 / 6,000 / 10,000 / 16,000; % sold 10, 90, 50, 100: level 1 up, 2 up, 2, 3 up', v_c2;

  -- ── GM_PRICE ── level 10 (v_g1) and level 3 (v_g2), against the same quote with the city's bid alone, in ONE SELECT each
  for v_f in
    select x.g, x.lv, k.q_bidf as bidf, public.city_bid_factor(v_set) as city, k.q_spread as s, q.total as q_now, q0.total as q_pre, q.units as u
      from (values (v_g1, 10), (v_g2, 3)) x(g, lv)
     cross join lateral world.quote_terms(v_set, x.g, v_fa) k
     cross join lateral world.quote(v_set, x.g, 30, 'sell', null, v_fa) q
     cross join lateral world.quote_priced(v_set, x.g, 30, 'sell', null, v_fa, k.q_spread, k.q_nohag, k.q_tax, public.city_bid_factor(v_set)) q0
  loop
    if abs(v_f.bidf - v_f.city * least(1 + v_f.lv * 0.005, (1 + v_f.s / 2) / (1 - v_f.s / 2))) > 0.0000001
       or v_f.q_now <= v_f.q_pre or abs(v_f.q_now - v_f.q_pre * v_f.bidf / v_f.city) > v_f.u then
      raise exception 'PROOF 182 FAILED: lit, the bid of a level-% good is not the city''s by its factor: %', v_f.lv, to_jsonb(v_f);
    end if;
    raise notice 'PASS: GM_PRICE — level %: bid x% (spread %, the ask''s ceiling %), a 30-unit sale % -> %',
      v_f.lv, round(v_f.bidf / v_f.city, 4), round(v_f.s, 4), round((1 + v_f.s / 2) / (1 - v_f.s / 2), 4), v_f.q_pre, v_f.q_now;
  end loop;
  -- no fleet named (a quay's own terms) or a good she never sold: the city's
  if (select k.q_bidf from world.quote_terms(v_set, null, null) k) <> public.city_bid_factor(v_set)
     or (select k.q_bidf from world.quote_terms(v_set, v_g3, v_fa) k) <> public.city_bid_factor(v_set) then
    raise exception 'PROOF 182 FAILED: a quote with no fleet, or of a good she never sold, moved';
  end if;

  -- ── GM_ROUNDTRIP ── at level 10: the real trades, a buy of 30 at this quay and the sale of those 30 back to it
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_fa;
  v_r := cmd.do_buy(v_fa, jsonb_build_object('good', v_g1, 'qty', 30));
  v_s := cmd.do_sell(v_fa, jsonb_build_object('good', v_g1, 'qty', 30));
  if (v_r ->> 'qty')::numeric <> 30 or (v_s ->> 'qty')::numeric <> 30 or (v_s ->> 'total')::numeric > (v_r ->> 'total')::numeric then
    raise exception 'PROOF 182 FAILED: at level 10 a round trip at one quay pays: buy % sell %', v_r, v_s;
  end if;
  raise notice 'PASS: GM_ROUNDTRIP — level 10 at SET: 30 % bought for %, the same 30 sold back for % (never more)', v_c1, v_r ->> 'total', v_s ->> 'total';

  -- ── GM_CAP ── at level 10: the allowance x 1.5 (read with the day's traded units), and a SELL ALL sells all of it
  select world.daily_cap_remaining(v_a, v_set, v_g1) as cap,
         public.daily_cap_base(v_a, v_set) * pg.stock_target as dark_whole,
         coalesce((select td.qty from public.trade_daily td where td.player_id = v_a and td.port_id = v_set and td.good_id = v_g1
                     and td.game_day = world.game_day()), 0) as traded
    into v_f
    from public.port_goods pg where pg.port_id = v_set and pg.good_id = v_g1;
  if abs(v_f.cap - (1.5 * v_f.dark_whole - v_f.traded)) > 0.001 or v_f.cap <= v_f.dark_whole - v_f.traded then
    raise exception 'PROOF 182 FAILED: the allowance at level 10 is not x 1.5: %', to_jsonb(v_f);
  end if;
  v_s := pg_temp.sell_182(v_fa, v_g1, null, 5000);
  if (v_s ->> 'qty')::numeric <> floor(v_f.cap) or (v_s ->> 'qty')::numeric <= v_f.dark_whole - v_f.traded
     or world.daily_cap_remaining(v_a, v_set, v_g1) >= 1 then
    raise exception 'PROOF 182 FAILED: SELL ALL did not take the bigger allowance: sold % of %', v_s ->> 'qty', to_jsonb(v_f);
  end if;
  raise notice 'PASS: GM_CAP — % at SET: the day''s allowance % (dark it would be %), and SELL ALL sold %',
    v_c1, round(v_f.cap, 1), round(v_f.dark_whole - v_f.traded, 1), v_s ->> 'qty';

  -- ── GM_MONEY ── a level-10 sale (of a third good: the first's day is spent), paid by the purse, W to the ducat
  insert into public.goods_mastery (player_id, good_id, units, level) values (v_a, v_g3, 16000, 10);
  v_w0 := pg_temp.w_182();
  v_d0 := (select p.ducats from public.players p where p.id = v_a);
  v_p0 := public.treasury_balance(v_set);
  v_s := pg_temp.sell_182(v_fa, v_g3, 40, 40);
  if v_s is null or (v_s #>> '{mastery,level}')::int <> 10
     or pg_temp.w_182() <> v_w0
     or (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.ref_event = (v_s ->> '_id')::uuid and t.kind = 'SELL') <> -(v_s ->> 'total')::numeric
     or (select p.ducats from public.players p where p.id = v_a) <= v_d0 then
    raise exception 'PROOF 182 FAILED: the money law: W % -> %, sale %', v_w0, pg_temp.w_182(), v_s - 'logbook';
  end if;
  raise notice 'PASS: GM_MONEY — a level-10 sale of 40 for % d.: the purse paid it (a SELL flow of -%; the purse % net of the tax back), her purse +%, W unchanged (%)',
    v_s ->> 'total', v_s ->> 'total', public.treasury_balance(v_set) - v_p0, (select p.ducats from public.players p where p.id = v_a) - v_d0, v_w0;

  -- ── GM_MERCHANT ──
  if public.goods_mastery_sale(v_npc, v_g1, 10) <> '{}'::jsonb or public.goods_mastery_cap(v_npc, v_g1) <> 1
     or public.goods_mastery_bid(v_nfl, v_g1, 0.06) <> 1
     or exists (select 1 from public.goods_mastery m where m.player_id = v_npc)
     or exists (select 1 from public.goods_mastery m join public.players p on p.id = m.player_id where p.is_npc) then
    raise exception 'PROOF 182 FAILED: a merchant was written or priced';
  end if;
  raise notice 'PASS: GM_MERCHANT — a merchant''s sale answered {} and wrote nothing; her bid and allowance factors 1';

  -- ── GM_READ ──
  v_r := world.goods_mastery();
  if (v_r ->> 'company')::boolean is not true or jsonb_array_length(v_r -> 'goods') <> 3
     or v_r #>> '{specialty,good}' is distinct from v_c1 or (v_r #>> '{specialty,level}')::int <> 10
     or (v_r #>> '{goods,2,good}') is distinct from v_c2 or (v_r #>> '{goods,2,level}')::int <> 3
     or (v_r #>> '{goods,2,at}')::numeric <> 250 or (v_r #>> '{goods,2,next}')::numeric <> 500
     or v_r -> 'ladder' <> '[1, 100, 250, 500, 1000, 2000, 3500, 6000, 10000, 16000]'::jsonb or (v_r ->> 'top')::int <> 10
     or (v_r ->> 'price_step')::numeric <> 0.005 or (v_r ->> 'cap_step')::numeric <> 0.05 then
    raise exception 'PROOF 182 FAILED: the read: %', left(v_r::text, 800);
  end if;
  raise notice 'PASS: GM_READ — % goods, specialty % (level %), % at % (% -> %)',
    jsonb_array_length(v_r -> 'goods'), v_r #>> '{specialty,good}', v_r #>> '{specialty,level}', v_c2, v_r #>> '{goods,2,level}', v_r #>> '{goods,2,at}', v_r #>> '{goods,2,next}';

  -- ── GM_COST ──
  v_t := clock_timestamp();
  for i in 1 .. 500 loop
    perform public.goods_mastery_bid(v_fa, v_g1, 0.06), public.goods_mastery_cap(v_a, v_g1);
  end loop;
  v_ms1 := extract(epoch from clock_timestamp() - v_t) * 1000 / 500;
  v_t := clock_timestamp();
  for i in 1 .. 500 loop
    perform public.goods_mastery_bid(v_nfl, v_g1, 0.06), public.goods_mastery_cap(v_npc, v_g1);
  end loop;
  v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000 / 500;
  update public.world_config set value = 'false'::jsonb where key = 'goods_mastery_enabled';
  v_t := clock_timestamp();
  for i in 1 .. 500 loop
    perform public.goods_mastery_bid(v_fa, v_g1, 0.06), public.goods_mastery_cap(v_a, v_g1);
  end loop;
  v_ms3 := extract(epoch from clock_timestamp() - v_t) * 1000 / 500;
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform world.quote_terms(v_set, v_g1, v_fa);
  end loop;
  v_ms4 := extract(epoch from clock_timestamp() - v_t) * 1000 / 200;
  if v_ms1 > 0.5 or v_ms2 > 0.5 or v_ms3 > 0.2 then
    raise exception 'PROOF 182 FAILED: too slow: lit % ms, merchant % ms, dark % ms', round(v_ms1, 4), round(v_ms2, 4), round(v_ms3, 4);
  end if;
  raise notice 'PASS: GM_COST — both factors lit % ms, for a merchant % ms, dark % ms; a quote''s terms % ms',
    round(v_ms1, 4), round(v_ms2, 4), round(v_ms3, 4), round(v_ms4, 4);
end
$p$;
