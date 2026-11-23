-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 183 - THE HQ BOARD FROM THE SERVER  (migration 0480; docs/design/hq-command-2026-11-23.md section 2, v2 items 1-3;
--             docs/dev-log/2026-11-23-hq-board-server.md)
--
--   The migration's self-assert never asks world.best_sales (hq_board_fleets 0) and compares the request card with cmd.preview_fulfil.
--   This proof plays the board as a company sees it: her idle fleets' trade runs (world.best_sales, the desk's read), the fleet count and
--   a busy fleet, requests at two harbours, the rate's 24-hour window, a course's risk, and the cost of one call. Rolled back by
--   proof.mjs. NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: a trade card is checked for its own shape and its own arithmetic, never
--   against a second best_sales answer. THE DAY: the rate is a rolling 24 hours (now() - 24 h), not a UTC day, and proof.mjs runs this
--   file in ONE transaction (now() is one instant), so no scene can straddle a midnight; the requests' deadlines are days ahead.
--
-- @pass HB_DARK      dark: world.hq_board() is {"on": false} for a company with every kind of move open
-- @pass HB_TRADE     lit: her idle fleet's trade runs (at most hq_board_runs), each its own coin an hour, the desk's trip as its act, a risk
-- @pass HB_FLEETS    hq_board_fleets 1: the second idle fleet is named in `unpriced`; a fleet with orders waiting is neither priced nor named
-- @pass HB_REQUEST   requests at every harbour where a fleet of hers lies, each card's net cmd.preview_fulfil's, its act cmd.fulfil
-- @pass HB_ORDER     the moves in the rule's order: the band, then coin an hour, then the profit, then the id
-- @pass HB_RATE      the rate: her ledger's last 24 hours over 24 (a row a minute inside counts, a minute outside does not)
-- @pass HB_RISK      a course's danger is the highest level of its harbours' waters; a bounty pirate's home on it carries her bounty
-- @pass HB_COST      one world.hq_board() call lit, timed (one idle fleet, then two)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0480-4000-8000-0000000000a1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_set   uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_f1    uuid;
  v_f2    uuid;
  v_g1    uuid;
  v_c1    text;
  v_g2    uuid;
  v_c2    text;
  v_k1    uuid;
  v_k2    uuid;
  v_b     jsonb;
  v_m     jsonb;
  v_p     jsonb;
  v_r     jsonb;
  v_n     int;
  v_t     timestamptz;
  v_ms1   numeric;
  v_ms2   numeric;
  v_pirate uuid;
begin
  v_a := public.new_house(c_a, 'Casa do Quadro 183', 'PRT');
  perform cmd.assume_identity(c_a);
  select f.id into v_f1 from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 60000 where p.id = v_a;
  -- a good Lisbon trades and a good Setubal trades (the requests' goods)
  select g.id, g.code into v_g1, v_c1 from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  select g.id, g.code into v_g2, v_c2 from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and g.id <> v_g1 and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;

  -- HB_DARK
  if world.hq_board() is distinct from '{"on": false}'::jsonb then
    raise exception 'HB_DARK: dark, the read is %', left(world.hq_board()::text, 300);
  end if;
  raise notice 'PASS: HB_DARK — dark, world.hq_board() = {"on": false}';
  update public.world_config set value = 'true'::jsonb where key = 'hq_board_enabled';

  -- HB_COST (one idle fleet) and HB_TRADE: her one idle fleet at Lisbon, priced by world.best_sales
  v_t := clock_timestamp();
  v_b := world.hq_board();
  v_ms1 := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  select count(*) into v_n from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade';
  if v_n < 1 or v_n > public.wc_int('hq_board_runs') or jsonb_array_length(v_b->'unpriced') <> 0 then
    raise exception 'HB_TRADE: % trade cards (runs %), unpriced %', v_n, public.wc_int('hq_board_runs'), v_b->'unpriced';
  end if;
  if exists (select 1 from jsonb_array_elements(v_b->'moves') m(e)
              where m.e->>'kind' = 'trade'
                and not ((m.e->>'fleet')::uuid = v_f1 and m.e->>'at' = 'LIS' and (m.e->>'profit')::numeric > 0 and (m.e->>'seconds')::numeric > 0
                         and (m.e->>'score')::numeric = round((m.e->>'profit')::numeric * 3600 / (m.e->>'seconds')::numeric)
                         and m.e #>> '{act,rpc}' = 'cmd.issue_lines' and (m.e #>> '{act,args,fleet}')::uuid = v_f1
                         and m.e #>> '{act,args,plan,sell_at}' = m.e #>> '{needs,to}' and m.e #>> '{act,args,plan,good}' = m.e #>> '{needs,good}'
                         and coalesce(m.e #>> '{act,args,plan,buy_at}', 'LIS') = 'LIS'
                         and jsonb_typeof(m.e #> '{act,args,plan,stops}') = 'array'
                         and (m.e #>> '{risk,danger}')::int between 1 and 5
                         and exists (select 1 from public.goods g where g.code = m.e #>> '{needs,good}'))) then
      raise exception 'HB_TRADE: a trade card is not its own: %', left((v_b->'moves')::text, 800);
  end if;
  select m.e into v_m from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade' limit 1;
  raise notice 'PASS: HB_TRADE — % trade card(s) for her idle fleet at Lisbon; the first: % to %, +% in % s (% an hour), danger %, act %',
    v_n, v_m #>> '{needs,good}', v_m #>> '{needs,to}', v_m->>'profit', v_m->>'seconds', v_m->>'score', v_m #>> '{risk,danger}', v_m #>> '{act,rpc}';

  -- HB_FLEETS: a second idle fleet at Lisbon (the house keeps two): priced with the first (the cost of two), then with one fleet priced named
  -- in `unpriced`; then with an order waiting, neither priced nor named
  v_f2 := public.form_fleet(v_a, 'Andorinha', v_lis);
  perform public.commission_ship(v_a, v_f2, 'barca', 'Andorinha', true, true);
  v_t := clock_timestamp();
  v_b := world.hq_board();
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  if not exists (select 1 from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade' and (m.e->>'fleet')::uuid = v_f2)
     or jsonb_array_length(v_b->'unpriced') <> 0 then
    raise exception 'HB_FLEETS: her second idle fleet was not priced: %', v_b->'unpriced';
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'hq_board_fleets';
  v_b := world.hq_board();
  -- the oldest first (created_at, then id: both fleets were formed in this one transaction, so the id decides)
  select f.id into v_k1 from public.fleets f where f.player_id = v_a order by f.created_at, f.id limit 1;
  if v_b->'unpriced' <> jsonb_build_array(case when v_k1 = v_f1 then v_f2 else v_f1 end)
     or exists (select 1 from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade' and (m.e->>'fleet')::uuid <> v_k1) then
    raise exception 'HB_FLEETS: with one fleet priced, unpriced is % (want the younger fleet)', v_b->'unpriced';
  end if;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status)
  values (v_k1, v_a, 1, 'WAIT', 'WAIT', '{}'::jsonb, 'pending');
  v_b := world.hq_board();
  if jsonb_array_length(v_b->'unpriced') <> 0
     or exists (select 1 from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade' and (m.e->>'fleet')::uuid = v_k1)
     or not exists (select 1 from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'trade') then
    raise exception 'HB_FLEETS: a fleet with an order waiting was priced or named: %', v_b->'unpriced';
  end if;
  delete from public.orders o where o.fleet_id = v_k1;
  raise notice 'PASS: HB_FLEETS — two idle fleets both priced; hq_board_fleets 1: the oldest priced, the other named in unpriced; the oldest with an order waiting: neither priced nor named, the other priced';
  update public.world_config set value = to_jsonb(0) where key = 'hq_board_fleets';

  -- HB_REQUEST: a request at Lisbon (her first fleet holds its good) and one at Setubal (her second fleet sails there, holding its good)
  update public.ships s set cargo = jsonb_build_object(v_c1, 25), cargo_basis = jsonb_build_object(v_c1, 1) where s.fleet_id = v_f1;
  update public.ships s set cargo = jsonb_build_object(v_c2, 12), cargo_basis = jsonb_build_object(v_c2, 1) where s.fleet_id = v_f2;
  update public.fleets f set port_id = v_set where f.id = v_f2;
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size)
  values (v_lis, v_g1, world.game_day(), 98, 40, 20, 100, 6.5, 260, world.game_day() + 3, 'open', 260, 'city') returning id into v_k1;
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size)
  values (v_set, v_g2, world.game_day(), 98, 40, 20, 100, 9.25, 370, world.game_day() + 3, 'open', 370, 'city') returning id into v_k2;
  v_b := world.hq_board();
  for v_m in select m.e from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'request' and (m.e #>> '{act,args,contract}')::uuid in (v_k1, v_k2) loop
    v_p := cmd.preview_fulfil((v_m #>> '{act,args,fleet}')::uuid, (v_m #>> '{act,args,contract}')::uuid);
    if (v_p->>'ok')::boolean is not true or (v_m->>'profit')::numeric is distinct from (v_p #>> '{estimate,totals,net}')::numeric
       or (v_m #>> '{needs,units}')::numeric is distinct from (v_p #>> '{estimate,contract,qty}')::numeric or v_m #>> '{act,rpc}' <> 'cmd.fulfil' then
      raise exception 'HB_REQUEST: the card % is not cmd.preview_fulfil''s %', left(v_m::text, 300), left(v_p::text, 300);
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(v_b->'moves') m(e)
       where m.e->>'kind' = 'request' and ((m.e #>> '{act,args,contract}')::uuid, (m.e->>'fleet')::uuid) in ((v_k1, v_f1), (v_k2, v_f2))) <> 2 then
    raise exception 'HB_REQUEST: the two requests are not both on the board: %', left((v_b->'moves')::text, 600);
  end if;
  raise notice 'PASS: HB_REQUEST — a request at Lisbon and one at Setubal, each where her fleet lies with the good; each net = cmd.preview_fulfil''s';

  -- HB_ORDER
  if exists (select 1 from (select (m.e->>'band')::int as b, (m.e->>'score')::numeric as s, (m.e->>'profit')::numeric as pr, m.e->>'id' as id, k,
                                   lag((m.e->>'band')::int) over (order by k) as pb, lag((m.e->>'score')::numeric) over (order by k) as ps,
                                   lag((m.e->>'profit')::numeric) over (order by k) as ppr, lag(m.e->>'id') over (order by k) as pid
                              from jsonb_array_elements(v_b->'moves') with ordinality m(e, k)) z
              where z.b < z.pb or (z.b = z.pb and z.ps is null and z.s is not null) or (z.b = z.pb and z.s > z.ps)
                 or (z.b = z.pb and z.s is not distinct from z.ps and z.pr > z.ppr)
                 or (z.b = z.pb and z.s is not distinct from z.ps and z.pr is not distinct from z.ppr and z.id < z.pid)) then
    raise exception 'HB_ORDER: the moves are not in the rule''s order: %', left((v_b->'moves')::text, 800);
  end if;
  raise notice 'PASS: HB_ORDER — % moves, in the rule''s order (band, coin an hour, profit, id)', jsonb_array_length(v_b->'moves');

  -- HB_RATE: a row a minute inside the 24 hours and one a minute outside
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at)
  values (v_a, 'SELL', 2400, 60000, now() - interval '23 hours 59 minutes'), (v_a, 'SELL', 7777, 60000, now() - interval '24 hours 1 minute'),
         (v_a, 'BUY', -1200, 60000, now() - interval '3 hours');
  v_r := world.hq_board()->'rate';
  if (v_r->>'net_24h')::numeric <> 1200 or (v_r->>'per_hour')::numeric <> 50 then
    raise exception 'HB_RATE: the rate is % (want net 1200, 50 an hour)', v_r;
  end if;
  raise notice 'PASS: HB_RATE — net % in the last 24 hours, % an hour (the row a minute outside left out)', v_r->>'net_24h', v_r->>'per_hour';

  -- HB_RISK: a sea's level is world.sea_danger's; the bounties lit, a pirate whose home is Setubal rides the Lisbon-Setubal course
  if exists (select 1 from jsonb_array_elements(world.sea_danger()) d join public.seas s on s.code = d->>'sea_code'
              where public.hq_sea_level(s.id) <> (d->>'level')::int) then
    raise exception 'HB_RISK: a sea''s level is not world.sea_danger''s';
  end if;
  v_r := public.hq_course_risk(array['LIS', 'SET']);
  if v_r->>'bounty' is not null and not public.bounty_on() then
    raise exception 'HB_RISK: a bounty with the bounties dark: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('pirate_bounties_enabled', 'pirates_bite', 'city_treasury_enabled');
  select f.id into v_pirate from public.fleets f where f.player_id <> v_a order by f.id limit 1;
  insert into public.pirate_bounties (slot, fleet_id, epithet, given, home_port, named_at, taken, took)
  values (49, v_pirate, 'Proof', 'Quadro', v_set, now() - interval '3 hours', 2, '[]'::jsonb);
  v_r := public.hq_course_risk(array['LIS', 'SET']);
  if not public.bounty_on() or (v_r->>'bounty')::numeric is distinct from round(public.bounty_value(now() - interval '3 hours', 2, now()))
     or (v_r->>'danger')::int <> greatest(public.hq_sea_level((select p.sea_id from public.ports p where p.id = v_lis)),
                                          public.hq_sea_level((select p.sea_id from public.ports p where p.id = v_set)))
     or public.hq_course_risk(array['LIS'])->>'bounty' is not null then
    raise exception 'HB_RISK: the course''s risk is % (bounty on %)', v_r, public.bounty_on();
  end if;
  raise notice 'PASS: HB_RISK — every sea''s level is world.sea_danger''s; Lisbon-Setubal %, Lisbon alone no bounty', v_r;

  raise notice 'PASS: HB_COST — one world.hq_board() call lit: % ms with one idle fleet priced, % ms with two (hq_board_fleets 4, budget % ms)',
    v_ms1, v_ms2, public.wc_int('hq_board_budget_ms');
end $p$;
