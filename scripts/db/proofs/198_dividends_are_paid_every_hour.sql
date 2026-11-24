-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 198 - DIVIDENDS ARE PAID EVERY HOUR  (migration 0495; docs/design/hq-corp-2026-11-24.md D6, economy file section 9)
--
--   The owner, row 373: "investing will give you dividends every hour". 0495's own self-assert runs public.city_coupons and
--   public.city_coupon_hour on a probe place alone (a migration never runs a real game step). This proof runs the REAL
--   public.tick_city over the WHOLE world for a whole day of 24 hourly runs:
--     me        a PLAYER with NO FLEET who buys shares at Lisbon through the real door (public.invest_for): no fleet can ever arrive
--     merchant  a MERCHANT (players.is_npc) holding 1,000,000 d. at Lisbon beside her
--     owner     a fleetless player holding the owner's own 461,384 d. at a second harbour, with 555 d. set aside from before
--     sad       the same holding at a third harbour, whose city loses money that day
--   The same day is run twice from the same books: DARK (today's rule, rolled back) and LIT. Rolled back by proof.mjs.
--
-- @pass DH_DARK       dark (as deployed): the real tick pays no purse, writes no DIVIDEND ledger row and marks no row
-- @pass DH_SAME_DAY   lit, the day's coupon is the dark day's to the coin: the receipt's coupons_paid, every city's DIVIDEND flow and
--                     every merchant's `accrued` are equal, and each player's `accrued` plus what she was paid is her dark `accrued`.
--                     The city never pays more than today's rule lets it
-- @pass DH_NO_FLEET   lit: the player with no fleet is paid 1/24 of her day's coupon straight to her purse by the tick
-- @pass DH_OWNER      lit: 461,384 d. of shares earn 346 d. an hour where the city's day covered the coupon, and 0 where the city lost
-- @pass DH_ONCE       a second tick in the same real hour pays nothing, and neither does the pay-out called again by itself
-- @pass DH_MERCHANT   the merchant is never paid hourly: her purse, her ledger and her row's marks do not move in 24 lit hours
-- @pass DH_DAY        24 hourly ticks pay the owner 24 x 346 = 8,304 d., each hour once, and her old 555 d. is still set aside
-- @pass DH_CLOSED     no coin is minted: each player's purse rose by exactly what her `accrued` fell, no city paid a DIVIDEND
--                     beyond the day's coupon, and the world's sum (purses, city purses, flows, set aside) is the same across a lit tick
-- @pass DH_ACCRUED    old `accrued` is never paid out hourly and is still collected by public.collect_coupons
-- @pass DH_COST       no error in any step of any tick; the step's ms and the rows of one lit hour are printed
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  -- tomorrow's 00:37 UTC: the run that pays the day's coupon; the 23 hourly runs after it stay inside the same real day
  v_at    timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc' + interval '1 day 37 minutes';
  v_rday  int := public.real_day(v_at);
  v_gday  int := world.game_day(v_at);
  v_nat   uuid := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
  v_lis   uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_h2    uuid;
  v_h3    uuid;
  v_me    uuid;
  v_mer   uuid;
  v_own   uuid;
  v_sad   uuid;
  v_kind  text;
  v_n     int;
  v_buy   jsonb;
  v_cost  bigint;
  v_me0   bigint;
  v_dark  jsonb;
  v_lit   jsonb;
  v_r     jsonb;
  v_r1    jsonb;
  v_r1b   jsonb;
  v_w0    numeric;
  v_w1    numeric;
  v_led0  bigint;
  v_led1  bigint;
  v_sl0   bigint;
  v_sl1   bigint;
  v_me_h  bigint;
  v_x     bigint;
  v_bal   jsonb;
  v_k     int;
begin
  if v_lis is null then
    raise exception 'PROOF 198 FAIL: no Lisbon in this world';
  end if;
  select x.id into v_h2 from public.ports x where x.kind = 'HARBOUR' and x.id <> v_lis order by x.code limit 1;
  select x.id into v_h3 from public.ports x where x.kind = 'HARBOUR' and x.id not in (v_lis, v_h2) order by x.code limit 1;

  -- the purses lit, the rate as on prod (0.018 a real day), every harbour with a purse row and money, the books settled
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  update public.world_config set value = to_jsonb(0.018) where key = 'works_coupon_day';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set coupon_day = v_rday, earned_day = v_gday - 1;
  perform public.treasury_post(v_lis, 'BUY', 10000000, null, null);
  perform public.treasury_post(v_h2, 'BUY', 10000000, null, null);
  perform public.treasury_post(v_h3, 'BUY', 10000000, null, null);
  perform public.tick_city(v_at);
  perform public.tick_city(v_at);

  -- THE HOLDERS. `me` buys at Lisbon through the real door; no proof house owns a fleet.
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 me', v_nat, 5000000, false) returning id into v_me;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 merchant', v_nat, 0, true) returning id into v_mer;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 owner', v_nat, 0, false) returning id into v_own;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 sad', v_nat, 0, false) returning id into v_sad;
  select k.kind, least(public.city_offered(v_lis, k.kind), greatest(1, ceil(200000::numeric / public.works_share_price(coalesce(w.level, 0)))::int))
    into v_kind, v_n
    from unnest(array['docks', 'market', 'production', 'inn']) with ordinality k(kind, o)
    left join public.city_works w on w.port_id = v_lis and w.kind = k.kind
   where public.city_offered(v_lis, k.kind) > 0
   order by k.o limit 1;
  if v_kind is null then
    raise exception 'PROOF 198 FAIL: Lisbon offers no shares in any work';
  end if;
  v_buy  := public.invest_for(v_me, v_lis, v_kind, v_n);
  v_cost := (v_buy->>'cost')::bigint;
  if not coalesce((v_buy->>'ok')::boolean, false) or round(public.coupon_day_of(v_lis, v_me, v_cost) / 24) < 1 then
    raise exception 'PROOF 198 FAIL: the buy did not go through, or its hourly coupon is nought: %', v_buy;
  end if;
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
    (v_lis, 'inn', v_mer, 10, 1000000, 0, v_gday),
    (v_h2, 'docks', v_own, 10, 461384, 555, v_gday),
    (v_h3, 'docks', v_sad, 10, 461384, 555, v_gday);
  if exists (select 1 from public.fleets f where f.player_id in (v_me, v_mer, v_own, v_sad)) then
    raise exception 'PROOF 198 FAIL: a proof house has a fleet';
  end if;
  update public.world_config set value = '0'::jsonb where key = 'works_level_max';   -- no city builds: a city's profit is what this proof posts

  -- THE DAY'S BOOKS, as the 00:37 run finds them: the buy's SHARE flow rolled (capital, not profit); a whole real day since the last
  -- coupon and since every stamp; Lisbon and the second harbour earned 240,000 d.; the third lost 4,000
  perform public.tick_city(v_at);
  update public.port_treasury set profit = 0, coupon_day = v_rday - 1;
  update public.city_shares set accrued_day = v_gday - 1000 where player_id in (v_me, v_mer, v_own, v_sad);
  perform public.treasury_post(v_lis, 'BUY', 240000, null, null);
  perform public.treasury_post(v_h2, 'BUY', 240000, null, null);
  perform public.treasury_post(v_h3, 'BUY', 1000, null, null);
  perform public.treasury_post(v_h3, 'SELL', -5000, null, null);
  v_me0 := (select pl.ducats from public.players pl where pl.id = v_me);

  -- ── DARK: the real tick, as deployed. Its figures are "today's rule" for this day. Rolled back. ──
  begin
    v_r := public.tick_city(v_at);
    if v_r->'errors' <> '{}'::jsonb
       or (select pl.ducats from public.players pl where pl.id = v_own) <> 0 or (select pl.ducats from public.players pl where pl.id = v_me) <> v_me0
       or exists (select 1 from public.ledger l where l.player_id in (v_me, v_mer, v_own, v_sad) and l.kind = 'DIVIDEND')
       or exists (select 1 from public.city_shares cs where cs.drip_left <> 0 or cs.drip_hour <> 0 or cs.drip_at <> 0) then
      raise exception 'PROOF 198 FAIL: dark, the tick paid a purse or marked a row: %', v_r;
    end if;
    raise exception using errcode = 'ZX198', message = jsonb_build_object(
      'paid', v_r->'coupons_paid', 'ms', v_r->'ms',
      'me', (select cs.accrued from public.city_shares cs where cs.player_id = v_me),
      'mer', (select cs.accrued from public.city_shares cs where cs.player_id = v_mer),
      'own', (select cs.accrued from public.city_shares cs where cs.player_id = v_own),
      'sad', (select cs.accrued from public.city_shares cs where cs.player_id = v_sad),
      'bal', jsonb_build_array(public.treasury_balance(v_lis), public.treasury_balance(v_h2), public.treasury_balance(v_h3)))::text;
  exception when sqlstate 'ZX198' then v_dark := sqlerrm::jsonb;
  end;
  if (v_dark->>'own')::bigint <> 555 + 8305 or (v_dark->>'sad')::bigint <> 555 or (v_dark->>'mer')::bigint <> 18000 then
    raise exception 'PROOF 198 FAIL: the dark day is not the day this proof wrote: %', v_dark;
  end if;
  raise notice 'PASS: DH_DARK - a dark tick paid the day''s coupon (% d.) into `accrued`; no purse paid, no DIVIDEND ledger row, no row marked', v_dark->>'paid';

  -- ── LIT: the same day from the same books ──
  update public.world_config set value = 'true'::jsonb where key = 'dividend_hourly_enabled';
  v_led0 := (select count(*) from public.ledger);
  v_sl0  := (select count(*) from public.stats_live_deltas);
  v_w0 := (select coalesce(sum(pl.ducats), 0) from public.players pl) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t)
        + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f) + (select coalesce(sum(cs.accrued), 0) from public.city_shares cs);
  v_r1 := public.tick_city(v_at);
  v_w1 := (select coalesce(sum(pl.ducats), 0) from public.players pl) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t)
        + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f) + (select coalesce(sum(cs.accrued), 0) from public.city_shares cs);
  v_led1 := (select count(*) from public.ledger);
  v_sl1  := (select count(*) from public.stats_live_deltas);
  if v_r1->'errors' <> '{}'::jsonb then
    raise exception 'PROOF 198 FAIL: the lit tick answered an error: %', v_r1;
  end if;
  v_bal := jsonb_build_array(public.treasury_balance(v_lis), public.treasury_balance(v_h2), public.treasury_balance(v_h3));
  v_lit := jsonb_build_object(
    'me', (select cs.accrued from public.city_shares cs where cs.player_id = v_me) + (select pl.ducats from public.players pl where pl.id = v_me) - v_me0,
    'mer', (select cs.accrued from public.city_shares cs where cs.player_id = v_mer),
    'own', (select cs.accrued from public.city_shares cs where cs.player_id = v_own) + (select pl.ducats from public.players pl where pl.id = v_own),
    'sad', (select cs.accrued from public.city_shares cs where cs.player_id = v_sad) + (select pl.ducats from public.players pl where pl.id = v_sad));
  if v_r1->'coupons_paid' <> v_dark->'paid' or v_bal <> v_dark->'bal'
     or v_lit->'mer' <> v_dark->'mer' or v_lit->'me' <> v_dark->'me' or v_lit->'own' <> v_dark->'own' or v_lit->'sad' <> v_dark->'sad' then
    raise exception 'PROOF 198 FAIL: lit, the day''s coupon is not the dark day''s: lit % % % dark %', v_r1->'coupons_paid', v_bal, v_lit, v_dark;
  end if;
  raise notice 'PASS: DH_SAME_DAY - lit and dark the cities paid % d.; the three purses stand at %; the merchant''s accrued % both ways; each player''s accrued + paid = her dark accrued',
    v_r1->>'coupons_paid', v_bal, v_lit->>'mer';

  v_me_h := (select pl.ducats from public.players pl where pl.id = v_me) - v_me0;
  if v_me_h <> round(public.coupon_day_of(v_lis, v_me, v_cost) / 24)
     or (select count(*) from public.ledger l where l.player_id = v_me and l.kind = 'DIVIDEND' and l.ducats_delta = v_me_h) <> 1 then
    raise exception 'PROOF 198 FAIL: the player with no fleet was paid % d. to her purse, not %', v_me_h, round(public.coupon_day_of(v_lis, v_me, v_cost) / 24);
  end if;
  raise notice 'PASS: DH_NO_FLEET - she bought % x% at Lisbon for % d., owns no fleet, and the tick paid her % d. (1/24 of %) to her purse',
    v_kind, v_n, v_cost, v_me_h, round(public.coupon_day_of(v_lis, v_me, v_cost));

  if (select pl.ducats from public.players pl where pl.id = v_own) <> 346 or (select pl.ducats from public.players pl where pl.id = v_sad) <> 0 then
    raise exception 'PROOF 198 FAIL: 461,384 d. earned % where the city earned and % where it lost (346 and 0 expected)',
      (select pl.ducats from public.players pl where pl.id = v_own), (select pl.ducats from public.players pl where pl.id = v_sad);
  end if;
  raise notice 'PASS: DH_OWNER - 461,384 d. of shares: 346 d. an hour where the city''s day covered the coupon, 0 d. where the city lost 4,000';

  if v_w1 <> v_w0 then
    raise exception 'PROOF 198 FAIL: the world''s sum moved across a lit tick: % -> %', v_w0, v_w1;
  end if;

  v_r1b := public.tick_city(v_at);
  if v_r1b->'errors' <> '{}'::jsonb or (public.city_coupon_hour(v_at)->>'paid')::bigint <> 0
     or (select pl.ducats from public.players pl where pl.id = v_own) <> 346
     or (select pl.ducats from public.players pl where pl.id = v_me) - v_me0 <> v_me_h then
    raise exception 'PROOF 198 FAIL: a second tick in the same hour paid: %', v_r1b;
  end if;
  raise notice 'PASS: DH_ONCE - the same hour again, by the tick and by the pay-out itself: nothing more paid';

  -- ── THE REST OF THE DAY: 23 more hourly ticks ──
  for v_k in 1 .. 23 loop
    v_r := public.tick_city(v_at + make_interval(hours => v_k));
    if v_r->'errors' <> '{}'::jsonb or (v_r->>'coupons_paid')::bigint <> 0 then
      raise exception 'PROOF 198 FAIL: hour %: an error, or a city paid a second coupon in the day: %', v_k, v_r;
    end if;
    if (select pl.ducats from public.players pl where pl.id = v_own) <> 346 * (v_k + 1) then
      raise exception 'PROOF 198 FAIL: hour %: the owner holds % d., not %', v_k, (select pl.ducats from public.players pl where pl.id = v_own), 346 * (v_k + 1);
    end if;
  end loop;
  if (select pl.ducats from public.players pl where pl.id = v_mer) <> 0 or exists (select 1 from public.ledger l where l.player_id = v_mer)
     or (select cs.accrued from public.city_shares cs where cs.player_id = v_mer) <> 18000
     or exists (select 1 from public.city_shares cs join public.players pl on pl.id = cs.player_id
                 where pl.is_npc and (cs.drip_left <> 0 or cs.drip_hour <> 0 or cs.drip_at <> 0)) then
    raise exception 'PROOF 198 FAIL: a merchant was paid hourly or marked';
  end if;
  raise notice 'PASS: DH_MERCHANT - 24 lit hours: the merchant''s purse 0, no ledger row, 18,000 d. set aside as the dark day set it, no merchant row marked';

  if (select pl.ducats from public.players pl where pl.id = v_own) <> 24 * 346
     or (select count(*) from public.ledger l where l.player_id = v_own and l.kind = 'DIVIDEND' and l.ducats_delta = 346) <> 24
     or (select cs.accrued from public.city_shares cs where cs.player_id = v_own) <> 555 + 8305 - 24 * 346
     or (select pl.ducats from public.players pl where pl.id = v_sad) <> 0 then
    raise exception 'PROOF 198 FAIL: the day did not pay the owner 24 x 346 d. in 24 rows';
  end if;
  raise notice 'PASS: DH_DAY - 24 hourly ticks paid the owner % d. in 24 ledger rows of 346; % d. stay set aside (her old 555 and 1 d. for the next day)',
    24 * 346, 555 + 8305 - 24 * 346;

  -- each player's purse rose by exactly what her `accrued` fell; no city paid a DIVIDEND beyond the day's coupon (flows and daybook)
  if (select cs.accrued from public.city_shares cs where cs.player_id = v_me) + (select pl.ducats from public.players pl where pl.id = v_me) - v_me0 <> (v_dark->>'me')::bigint
     or (select cs.accrued from public.city_shares cs where cs.player_id = v_own) + (select pl.ducats from public.players pl where pl.id = v_own) <> (v_dark->>'own')::bigint
     or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.kind = 'DIVIDEND')
        + (select coalesce(sum(d.ducats), 0) from public.treasury_daybook d where d.kind = 'DIVIDEND') <> -(v_dark->>'paid')::bigint then
    raise exception 'PROOF 198 FAIL: coin was minted or lost over the day';
  end if;
  raise notice 'PASS: DH_CLOSED - over 24 hours each player''s purse rose by what her accrued fell; the cities'' DIVIDEND flows and books hold the day''s coupon and no more (% d.); the world''s sum % before and after a lit tick', v_dark->>'paid', v_w0;

  v_x := public.collect_coupons(v_own, v_h2, null);
  if v_x <> 555 + 8305 - 24 * 346 or (select pl.ducats from public.players pl where pl.id = v_own) <> 555 + 8305
     or (public.city_coupon_hour(v_at + interval '25 hours')->>'paid')::bigint <> (select least(cs.drip_hour, cs.drip_left, cs.accrued) from public.city_shares cs where cs.player_id = v_me)
     or (select pl.ducats from public.players pl where pl.id = v_own) <> 555 + 8305 then
    raise exception 'PROOF 198 FAIL: old accrued is no longer collected, or was paid twice';
  end if;
  raise notice 'PASS: DH_ACCRUED - an arrival collected the % d. left (the old 555 with it); she holds % d. = 555 + 8,305, and the next hour paid her nothing',
    v_x, 555 + 8305;

  raise notice 'PASS: DH_COST - no error in any of 26 ticks. Step 6 ms (PGlite): dark (the day''s coupon) % of %, lit (the day''s coupon + the hour) % of %, a lit hour with no coupon % of %. The first lit hour here (2 players paid): % ledger rows, % stats_live_deltas rows, 0 purse rows, 0 flows of its own',
    v_dark #>> '{ms,coupons}', v_dark #>> '{ms,total}', v_r1 #>> '{ms,coupons}', v_r1 #>> '{ms,total}', v_r #>> '{ms,coupons}', v_r #>> '{ms,total}',
    v_led1 - v_led0, v_sl1 - v_sl0;
  raise notice 'TIMING: tick_city step 6 dark % ms, lit % ms, a lit hour % ms', v_dark #>> '{ms,coupons}', v_r1 #>> '{ms,coupons}', v_r #>> '{ms,coupons}';
end
$p$;
