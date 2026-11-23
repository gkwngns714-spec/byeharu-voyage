-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 187 - THE COUNTRY RACE  (migration 0484; docs/design/roadmap-2026-11-23.md slice 15; docs/dev-log/2026-11-23-country-race.md)
--
--   The migration's self-assert counts each door by its function and settles a week written by hand. This proof plays the race as
--   companies live it: a Portuguese company sells in a contested harbour, fulfils its request (a job: the bonus x3) from HQ's served card,
--   which says what it adds and who leads, and gives to the city; a Castilian company outscores her in a second harbour; her home harbour
--   charges her half the dock fee; the hourly job settles the week at next Monday's clock (the winner, the champions' Reputation once) and
--   the read names it all; the cost of a lit sale's hook, the marks, the read and the tick. Rolled back by proof.mjs.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: world.hq_board (world.best_sales inside) is asked once, for its request card alone.
--   THE WEEK: proof.mjs runs this file in ONE transaction (now() is one instant), so every book row falls in one race week; the settle's
--   clock is named (next Monday 01:00 UTC), so no scene straddles a Monday.
--
-- @pass NR_DARK      dark: a sale, a gift and the board add nothing; the read and the tick are {"on": false}
-- @pass NR_SALE      lit: her sale in a contested harbour counts floor(total / 100) for Portugal, on the SOLD event and in the book
-- @pass NR_BOARD     HQ's served request card in that harbour says what it adds (the sale's part + the bonus x3) and that Portugal leads
-- @pass NR_JOB       one press fulfils it: the book grows by exactly the card's points
-- @pass NR_GIFT      a gift into the city's purse counts x10; into her home city nothing
-- @pass NR_FEE       her dock fee at a Portuguese harbour is half the dark fee; a Castilian's there, and hers elsewhere, as dark
-- @pass NR_SETTLE    next Monday's run settles the week once: the winner by cities led, its champion paid Reputation once
-- @pass NR_READ      the read: the countries in order, the cities' leaders, her points and place
-- @pass NR_COST      a lit sale's hook, the marks, the read and one tick, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0484-4000-8000-0000000001a1';
  c_b     constant uuid := '00000000-0484-4000-8000-0000000001b1';
  v_w0    bigint := public.nation_race_week(now());
  v_a     uuid;
  v_b     uuid;
  v_fa    uuid;
  v_fb    uuid;
  v_c1    uuid;
  v_c1code text;
  v_c2    uuid;
  v_home  uuid;
  v_else  uuid;
  v_good  uuid;
  v_gcode text;
  v_k     uuid;
  v_r     jsonb;
  v_hq    jsonb;
  v_card  jsonb;
  v_sold  jsonb;
  v_p0    bigint;
  v_p1    bigint;
  v_f     record;
  v_t     timestamptz;
  v_ms    numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  v_ms4   numeric;
  k       int;
begin
  -- the places: two contested harbours with a purse (the first by code with a good she may sell there, which the city does not make), a
  -- Portuguese home with a purse, and a harbour with a purse Portugal does not hold
  select p.id, p.code, g.id, g.code into v_c1, v_c1code, v_good, v_gcode
    from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
    join public.port_treasury t on t.port_id = p.id
   cross join lateral (select gg.id, gg.code from public.port_goods pg join public.goods gg on gg.id = pg.good_id
                         where pg.port_id = p.id and gg.bulk > 0 and not public.culture_refuses(p.culture, gg.culture_mask)
                         order by gg.bulk, gg.code limit 1) g
   where not a.home
   order by p.code limit 1;
  select p.id into v_c2 from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
   where not a.home and p.id <> v_c1 order by p.code limit 1;
  select p.id into v_home from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
   where a.home and a.nation_id = (select n.id from public.nations n where n.code = 'PRT') order by p.code limit 1;
  select p.id into v_else from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
   where a.nation_id is distinct from (select n.id from public.nations n where n.code = 'PRT') and not public.port_is_free(p.id) order by p.code limit 1;
  v_a := public.new_house(c_a, 'Casa da Coroa 187', 'PRT');
  v_b := public.new_house(c_b, 'Casa del Rey 187', 'ESP');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  update public.players p set ducats = 200000 where p.id in (v_a, v_b);
  update public.fleets set status = 'DOCKED', port_id = v_c1 where id = v_fa;
  update public.fleets set status = 'DOCKED', port_id = v_c2 where id = v_fb;
  perform public.fleet_load(v_fa, v_gcode, 40, 1);

  -- NR_DARK
  perform cmd.assume_identity(c_a);
  v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_good, 'qty', 5));
  perform public.pay_city(v_a, v_c1, 'DONATION', 1000, null);
  if exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'SOLD' and e.payload ? 'race')
     or exists (select 1 from public.nation_race_book) or world.nation_race() is distinct from '{"on": false}'::jsonb
     or public.tick_nation_race(now()) is distinct from '{"on": false}'::jsonb then
    raise exception 'NR_DARK: dark, the race moved';
  end if;
  raise notice 'PASS: NR_DARK — dark: a sale at % and a gift wrote nothing; the read and the tick {"on": false}', v_c1code;

  -- NR_SALE
  update public.world_config set value = 'true'::jsonb where key in ('nation_race_enabled', 'hq_board_enabled');
  v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_good, 'qty', 10));
  select e.payload into v_sold from public.events e where e.player_id = v_a and e.kind = 'SOLD' and e.payload ? 'race' limit 1;
  v_p0 := (select coalesce(sum(b.points), 0) from public.nation_race_book b where b.player_id = v_a);
  if v_sold is null or (v_sold #>> '{race,points}')::bigint <> floor((v_sold->>'total')::numeric / 100) or v_p0 <> (v_sold #>> '{race,points}')::bigint
     or (select n.code from public.nation_race_book b join public.nations n on n.id = b.nation_id where b.player_id = v_a) <> 'PRT' then
    raise exception 'NR_SALE: her sale did not count for Portugal: % / %', v_sold, v_p0;
  end if;
  raise notice 'PASS: NR_SALE — % % sold at % for %: +% for Portugal (SOLD race %)', v_sold->>'qty', v_gcode, v_c1code, v_sold->>'total', v_p0, v_sold->'race';

  -- NR_BOARD: a request for her good at C1; her served board's card carries race {points, lead}
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size)
  values (v_c1, v_good, world.game_day(), 98, 40, 20, 100, 40, 800, world.game_day() + 3, 'open', 800, 'city') returning id into v_k;
  v_hq := world.hq_board();
  select e into v_card from jsonb_array_elements(v_hq->'moves') e where e->>'kind' = 'request' and (e #>> '{act,args,contract}')::uuid = v_k;
  if v_card is null or v_card->'race' is null or v_card #>> '{race,lead}' <> 'mine'
     or (v_card #>> '{race,points}')::bigint <> floor(((v_card->>'profit')::numeric - (v_card #>> '{needs,bonus}')::numeric) / 100)
                                              + floor((v_card #>> '{needs,bonus}')::numeric * 3 / 100) then
    raise exception 'NR_BOARD: her request card does not say what it adds: %', coalesce(v_card, v_hq->'moves');
  end if;
  raise notice 'PASS: NR_BOARD — the card "Fulfil % at %": net %, bonus %, race %', v_gcode, v_c1code, v_card->>'profit', v_card #>> '{needs,bonus}', v_card->'race';

  -- NR_JOB: one press (the card's act)
  v_r := cmd.fulfil((v_card #>> '{act,args,fleet}')::uuid, v_k, (v_card #>> '{act,args,version}')::int);
  v_p1 := (select coalesce(sum(b.points), 0) from public.nation_race_book b where b.player_id = v_a);
  if (v_r->>'ok')::boolean is false or v_r ? 'error_code'
     or v_p1 - v_p0 <> floor((v_r #>> '{lines,0,total}')::numeric / 100) + floor((v_r #>> '{contract,premium}')::numeric * 3 / 100) then
    raise exception 'NR_JOB: the fulfil did not add the sale''s and the job''s points: % (% -> %)', v_r, v_p0, v_p1;
  end if;
  raise notice 'PASS: NR_JOB — fulfilled % for % (bonus %): +% for Portugal (card said %)', v_r #>> '{contract,qty}', v_r #>> '{lines,0,total}',
    v_r #>> '{contract,premium}', v_p1 - v_p0, v_card #>> '{race,points}';

  -- NR_GIFT
  v_p0 := v_p1;
  perform public.pay_city(v_a, v_c1, 'DONATION', 3000, null);
  perform public.pay_city(v_a, v_home, 'DONATION', 3000, null);
  v_p1 := (select coalesce(sum(b.points), 0) from public.nation_race_book b where b.player_id = v_a);
  if v_p1 - v_p0 <> 300 or exists (select 1 from public.nation_race_book b where b.port_id = v_home) then
    raise exception 'NR_GIFT: a gift of 3,000 did not add 300 at % and nothing at home (% -> %)', v_c1code, v_p0, v_p1;
  end if;
  raise notice 'PASS: NR_GIFT — 3,000 given at %: +300; at her home city: nothing', v_c1code;

  -- NR_FEE: the closed economy and the purses lit (as prod), her fee at a Portuguese harbour half the dark fee (a fee is a plain read, not
  -- time-budgeted: the three dark fees are read with the switch off, then the three lit ones)
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = 'false'::jsonb where key = 'nation_race_enabled';
  select jsonb_build_object('home', public.port_fee(v_home, v_a, 50000), 'else', public.port_fee(v_else, v_a, 50000), 'his', public.port_fee(v_home, v_b, 50000))
    into v_sold;
  update public.world_config set value = 'true'::jsonb where key = 'nation_race_enabled';
  for v_f in select public.port_fee(v_home, v_a, 50000) as hers_home, (v_sold->>'home')::bigint as dark_home,
                    public.port_fee(v_else, v_a, 50000) as hers_else, (v_sold->>'else')::bigint as dark_else,
                    public.port_fee(v_home, v_b, 50000) as his_home, (v_sold->>'his')::bigint as dark_his loop
    if v_f.dark_home < 4 or abs(v_f.hers_home * 2 - v_f.dark_home) > 2 or v_f.hers_else <> v_f.dark_else or v_f.his_home <> v_f.dark_his then
      raise exception 'NR_FEE: home % / %, elsewhere % / %, his % / %', v_f.hers_home, v_f.dark_home, v_f.hers_else, v_f.dark_else, v_f.his_home, v_f.dark_his;
    end if;
    raise notice 'PASS: NR_FEE — her dock fee at her home harbour % (dark %); elsewhere % (dark %); a Castilian''s there % (dark %)',
      v_f.hers_home, v_f.dark_home, v_f.hers_else, v_f.dark_else, v_f.his_home, v_f.dark_his;
  end loop;
  update public.world_config set value = 'false'::jsonb where key in ('city_treasury_enabled', 'economy_closed');

  -- NR_SETTLE: Castile outscores her at C2 (a gift); next Monday 01:00 the job settles this week: one city each, the points decide
  perform public.pay_city(v_b, v_c2, 'DONATION', 1000, null);
  v_r := public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '1 hour');
  v_hq := public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '2 hours');   -- again: nothing
  if (v_r->>'week')::bigint <> v_w0 or v_r #>> '{settled,winner}' <> 'PRT' or (v_r #>> '{settled,cities}')::int <> 2
     or v_hq->'settled' <> 'null'::jsonb
     or (select (w.champions->0->>'player')::uuid from public.nation_race_weeks w where w.week = v_w0) <> v_a
     or (select count(*) from public.reputation_book rb where rb.player_id = v_a and rb.kind = 'nation_race')
        <> (case when public.wc('reputation_on') = 'true'::jsonb then 1 else 0 end)
     or exists (select 1 from public.reputation_book rb where rb.player_id = v_b and rb.kind = 'nation_race') then
    raise exception 'NR_SETTLE: the week did not settle once for Portugal: % / % / %', v_r, v_hq, (select to_jsonb(w) from public.nation_race_weeks w where w.week = v_w0);
  end if;
  raise notice 'PASS: NR_SETTLE — next Monday''s run: %; the second run settled nothing; champion paid % Reputation once', v_r->'settled',
    (select rb.delta from public.reputation_book rb where rb.player_id = v_a and rb.kind = 'nation_race');

  -- NR_READ
  v_r := world.nation_race();
  if (v_r->>'on')::boolean is not true or v_r #>> '{mine,nation}' <> 'PRT' or (v_r #>> '{mine,points}')::bigint <> v_p1 or (v_r #>> '{mine,place}')::int <> 1
     or v_r #>> '{nations,0,nation}' <> 'PRT' or (v_r #>> '{nations,0,cities}')::int <> 1 or v_r #>> '{nations,1,nation}' <> 'ESP'
     or (select count(*) from jsonb_array_elements(v_r->'cities')) <> 2
     or not exists (select 1 from jsonb_array_elements(v_r->'cities') c where c->>'port' = v_c1code and c->>'nation' = 'PRT') then
    raise exception 'NR_READ: the read: %', v_r;
  end if;
  raise notice 'PASS: NR_READ — % ; ends %', v_r->'nations'->0, v_r->>'ends_at';

  -- NR_COST
  v_t := clock_timestamp();
  for k in 1 .. 100 loop
    perform public.nation_race_sale(v_a, v_c1, 1000);
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 100, 3);
  v_t := clock_timestamp();
  perform public.nation_race_marks(v_a, jsonb_build_array(v_card, v_card, v_card));
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  v_t := clock_timestamp();
  perform world.nation_race();
  v_ms3 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  v_t := clock_timestamp();
  perform public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '3 hours');
  v_ms4 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  raise notice 'PASS: NR_COST — a lit sale''s hook % ms; the marks % ms; the read % ms; a run with nothing to settle % ms (% book rows)',
    v_ms, v_ms2, v_ms3, v_ms4, (select count(*) from public.nation_race_book);
end
$p$;
