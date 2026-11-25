-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 213 - A COMPANY IS RESTARTED  (migration 0509; docs/dev-log/2026-11-25-restart-company.md)
--
--   The owner, 2026-11-25 (R1): "I need a way to restart the game." Played through the real doors with the economy CLOSED, the purses lit
--   and every kind of holding on the company: a fleet in port, one at sea, one wrecked, a job, a request and a contract with coin held, a
--   contract she carries, shares with a dividend set aside, a debt, a shed, gear, a captain, a land party, the mayor's seat, influence, a
--   standing on the board. Rolled back by proof.mjs.
--   TIME-PROOF: one transaction, one instant. WORLD-PROOF: it founds its own companies and reads no figure of the founding purse.
--
-- @pass RC_DARK      dark: no card, the door says E_NOT_IN_USE, nothing moves
-- @pass RC_REFUSED   in battle (in port, or a wreck still on a side), a posted contract another carries, a wrong name typed, a country outside Europe, a bad name: each in plain words, and nothing moves
-- @pass RC_COIN      the world's coin (purses, cities, set aside, every escrow) is the same before and after, to the coin; her ledger closes at 0; the poster gets the collateral of the contract she carried
-- @pass RC_RETIRED   the old row stays, with no account, country or coin; its events, ledger and level book stay; it holds nothing else
-- @pass RC_NOWHERE   Rank, the leaderboard, the Town Hall, the mayor, the influence book, the week and the ticks do not know her
-- @pass RC_NEW       the account is on a new company: the ordinary start, HQ in its capital, a free rename; the old name is free and can be taken
-- @pass RC_DAY       a second restart the same real day is refused; the next real day it is open; another account is not held back; her own name may be kept
-- @pass RC_DOORS     the door is for a signed-in player alone and takes no player id; the core, the rule and the tables are for no client and not service_role
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.world_coin() returns numeric language sql as $w$
  select (select coalesce(sum(p.ducats), 0) from public.players p)
       + (select coalesce(sum(t.ducats), 0) from public.port_treasury t) + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f)
       + (select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open')
       + (select coalesce(sum(s.accrued), 0) from public.city_shares s) + public.funds_aboard()
       + (select coalesce(sum(m.escrow), 0) from public.market_requests m where m.status = 'open')
       + (select coalesce(sum(c.reward + case when c.status = 'taken' then c.collateral else 0 end), 0) from public.courier_contracts c where c.status in ('open', 'taken'))
$w$;

do $p$
declare
  c_a constant uuid := '00000000-0509-4000-8000-0000000002a1';
  c_b constant uuid := '00000000-0509-4000-8000-0000000002b1';
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_svq uuid := (select p.id from public.ports p where p.code = 'SVQ');
  v_prt uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_esp uuid := (select n.id from public.nations n where n.code = 'ESP');
  v_na text; v_nb text; v_nc text; v_names text[];
  v_a uuid; v_b uuid; v_n uuid; v_f1 uuid; v_f2 uuid; v_f3 uuid; v_fb uuid; v_g record; v_r jsonb; x record;
  v_coin numeric; v_coin2 numeric; v_k uuid; v_k2 uuid; v_ev int; v_led int; v_lvl int; v_bp bigint; v_bat uuid; v_t text; v_cnt bigint;
begin
  insert into auth.users (id) values (c_a), (c_b) on conflict do nothing;
  select array_agg(c.nm order by c.i) into v_names
    from (select i, format('Casa Prova 213 %s', i) as nm from generate_series(1, 5000) i
           where not exists (select 1 from public.players p where lower(p.company_name) = lower(format('Casa Prova 213 %s', i))) order by i limit 3) c;
  v_na := v_names[1]; v_nb := v_names[2]; v_nc := v_names[3];
  select g.id, g.code, g.bulk into v_g from public.goods g order by g.bulk, g.code limit 1;
  -- the purses lit and the economy closed, whatever this world had; two capitals hold coin enough for a start
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'influence_enabled', 'contracts_enabled', 'fair_gift_enabled');
  perform public.treasury_post(v_lis, 'DONATION', 5000000, null, null, true);
  perform public.treasury_post(v_svq, 'DONATION', 5000000, null, null, true);
  perform cmd.assume_identity(c_a);
  v_r := cmd.found_house(v_na, 'PRT');
  v_a := public.current_player_id();
  perform cmd.assume_identity(c_b);
  v_r := cmd.found_house(v_nb, 'ESP');
  v_b := public.current_player_id();
  perform public.city_pays(v_lis, v_a, 'PREMIUM', 50000);
  perform public.city_pays(v_svq, v_b, 'PREMIUM', 50000);
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.id into v_f1 from public.fleets f where f.player_id = v_a;
  update public.world_config set value = '5'::jsonb where key = 'fleet_max';
  v_f2 := public.form_fleet(v_a, 'Segunda 213', v_lis); perform public.commission_ship(v_a, v_f2, 'barca', 'Nau 213 A', true, true);
  v_f3 := public.form_fleet(v_a, 'Terceira 213', v_lis); perform public.commission_ship(v_a, v_f3, 'barca', 'Nau 213 B', true, true);
  perform cmd.assume_identity(c_a);
  -- fleet 2 at sea, fleet 3 a wreck, fleet 1 in port with cargo
  update public.ships set cargo = jsonb_build_object(v_g.code, 5) where fleet_id = v_f1;
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_f2, v_a, '[[38.7,-9.2],[37.0,-9.0],[36.5,-6.4]]'::jsonb, 300, '{}'::jsonb, now(), now() + interval '2 hours', 'SAILING', v_lis, v_svq);
  update public.fleets set status = 'SAILING', port_id = null where id = v_f2;
  update public.ships set durability = 0 where fleet_id = v_f3;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_f3;
  -- holdings
  perform public.storage_put(v_a, v_lis, v_g.id, 4, 10);
  insert into public.player_items (player_id, port_id, item_code, qty) select v_a, v_lis, i.code, 1 from public.item_kinds i order by i.code limit 1;
  insert into public.player_officers (player_id, officer_id) select v_a, o.id from public.officers o order by o.id limit 1;
  insert into public.land_parties (player_id, port_id) values (v_a, v_lis) on conflict do nothing;
  insert into public.fleet_jobs (fleet_id, player_id, kind, since, seen_at) values (v_f1, v_a, 'best', now(), now());
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb) values (v_f1, v_a, 900213, 'SAIL SVQ', 'SAIL');
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values (v_lis, 'docks', v_a, 2, 100, 321, world.game_day());
  perform public.city_month_post(v_a, v_lis, 'DONATION', 999999999);
  insert into public.port_influence (port_id, nation_id, player_id, points) values (v_lis, v_prt, v_a, 1e9);
  insert into public.port_mayor (port_id, player_id, since) values (v_lis, v_a, now()) on conflict (port_id) do update set player_id = excluded.player_id;
  insert into public.house_regard (player_id, nation_id, points) values (v_a, v_esp, 5) on conflict do nothing;
  insert into public.port_fee_debts (player_id, port_id, ducats, kind) values (v_a, v_svq, 60, 'PORT_FEE');
  insert into public.houses_week (week, player_id, net) values (current_date, v_a, 10);
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, fulfilled_by, fulfilled_fleet, fulfilled_at)
  values (v_lis, v_g.id, -213, 1, 1, 10, 10, 1, 1, 5, 'fulfilled', v_a, v_f1, now());
  perform public.level_grant(v_a, 'request', 5000);
  -- coin held: a request (500), her open contract (reward 700), a contract of B's she carries (B's reward 900, her collateral 400)
  perform public.credit(v_a, 'REQUEST_ESCROW', -500);
  insert into public.market_requests (player_id, port_id, good_id, qty, unit_price, escrow) values (v_a, v_lis, v_g.id, 5, 100, 500);
  perform public.storage_put(v_a, v_lis, v_g.id, 2, 10);
  v_k := public.courier_post('company', v_a, v_lis, v_svq, v_g.id, 2, 700, 0, 7200);
  v_k2 := public.courier_post('house', v_b, v_lis, v_svq, v_g.id, 3, 900, 400, 7200);
  perform public.credit(v_a, 'CONTRACT_COLLATERAL', -400);
  update public.courier_contracts set status = 'taken', carrier_id = v_a, fleet_id = v_f1, taken_at = now(), deliver_by = now() + interval '2 hours' where id = v_k2;
  perform public.settle_standings(now());
  v_coin := pg_temp.world_coin();
  select count(*) into v_ev from public.events e where e.player_id = v_a;
  select count(*) into v_led from public.ledger l where l.player_id = v_a;
  select count(*) into v_lvl from public.level_book l where l.player_id = v_a;
  v_bp := (select p.ducats from public.players p where p.id = v_b);

  -- RC_DARK
  v_r := cmd.restart_company(v_na, v_nc, 'ESP');
  if v_r->>'error_code' is distinct from 'E_NOT_IN_USE' or world.player()->'player'->'restart' <> 'null'::jsonb or pg_temp.world_coin() <> v_coin then
    raise exception 'RC_DARK: %', v_r;
  end if;
  raise notice 'PASS: RC_DARK — no card, E_NOT_IN_USE';
  update public.world_config set value = 'true'::jsonb where key = 'restart_enabled';

  -- RC_REFUSED
  for x in select * from (values ('wrong', v_nc, 'ESP', 'E_CONFIRM'), (lower(v_na), v_nc, 'ESP', 'E_CONFIRM'), (v_na, v_nc, 'JPN', 'E_NOT_EUROPE'), (v_na, v_nc, 'PIR', 'E_NOT_EUROPE'),
                                 (v_na, v_nc, null, 'E_NOT_EUROPE'), (v_na, v_nb, 'ESP', 'E_NAME_TAKEN'), (v_na, 'Lisbon', 'ESP', 'E_NAME_TAKEN'), (v_na, 'A*B', 'ESP', 'E_BAD_NAME'), (v_na, null, 'ESP', 'E_BAD_NAME')) t(c, n, k, code) loop
    v_r := cmd.restart_company(x.c, x.n, x.k);
    if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from x.code or coalesce(v_r->>'error_message', '') = '' then
      raise exception 'RC_REFUSED: (%, %, %) wanted %, answered %', x.c, x.n, x.k, x.code, v_r;
    end if;
  end loop;
  update public.fleets set status = 'IN_BATTLE' where id = v_f1;
  v_r := cmd.restart_company(v_na, v_nc, 'ESP');
  if v_r->>'error_code' is distinct from 'E_IN_BATTLE' or world.player()->'player'->'restart'->'refusal'->>'code' is distinct from 'E_IN_BATTLE' then
    raise exception 'RC_REFUSED: in battle: %', v_r;
  end if;
  update public.fleets set status = 'DOCKED' where id = v_f1;
  insert into public.battles (kind, site, started_at, resolves_at, status) values ('PROBE', '{}'::jsonb, now(), now() + interval '1 hour', 'FIGHTING') returning id into v_bat;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_bat, v_f3, 'DEFENDER', now(), now());
  v_r := cmd.restart_company(v_na, v_nc, 'ESP');
  if v_r->>'error_code' is distinct from 'E_IN_BATTLE' then raise exception 'RC_REFUSED: a wreck on a side: %', v_r; end if;
  update public.battles set status = 'BROKEN_OFF' where id = v_bat;
  update public.courier_contracts set status = 'taken', carrier_id = v_b, fleet_id = v_fb, taken_at = now(), deliver_by = now() + interval '2 hours' where id = v_k;
  v_r := cmd.restart_company(v_na, v_nc, 'ESP');
  if v_r->>'error_code' is distinct from 'E_CONTRACT_OUT' then raise exception 'RC_REFUSED: a contract out: %', v_r; end if;
  update public.courier_contracts set status = 'open', carrier_id = null, fleet_id = null, taken_at = null, deliver_by = null where id = v_k;
  if pg_temp.world_coin() <> v_coin or public.current_player_id() <> v_a or (select count(*) from public.ledger l where l.player_id = v_a) <> v_led
     or not exists (select 1 from public.city_shares s where s.player_id = v_a and s.accrued = 321) then
    raise exception 'RC_REFUSED: a refusal moved something';
  end if;
  raise notice 'PASS: RC_REFUSED — nine bad presses, two battles and a contract out, nothing moved';

  -- THE PRESS
  v_r := cmd.restart_company(v_na, v_nc, 'ESP');
  if not coalesce((v_r->>'ok')::boolean, false) then raise exception 'RC_COIN: refused %', v_r; end if;
  v_n := public.current_player_id();
  -- RC_COIN
  v_coin2 := pg_temp.world_coin();
  if v_coin2 <> v_coin then raise exception 'RC_COIN: the world held % and holds % (%)', v_coin, v_coin2, v_r; end if;
  if (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_a) <> 0 or (select p.ducats from public.players p where p.id = v_a) <> 0 then
    raise exception 'RC_COIN: her ledger does not close at 0';
  end if;
  if (select p.ducats from public.players p where p.id = v_b) <> v_bp + 900 + 400 then
    raise exception 'RC_COIN: B got % more, not 1300', (select p.ducats from public.players p where p.id = v_b) - v_bp;
  end if;
  if (select f.ducats from public.treasury_flows f where f.player_id = v_a and f.kind = 'COMPANY_CLOSED') is distinct from (v_r->'closed'->>'ducats')::bigint
     or (v_r->'closed'->>'debts_paid')::bigint <> 60 or (v_r->'closed'->>'dividends')::bigint <> 321 or (v_r->'closed'->>'requests')::bigint <> 500
     or (v_r->'closed'->>'contracts_cancelled')::int <> 1 or (v_r->'closed'->>'contracts_failed')::int <> 1 or (v_r->'closed'->>'port') <> 'LIS' then
    raise exception 'RC_COIN: the receipt: %', v_r;
  end if;
  perform public.assert_ledger_reconciles(v_a); perform public.assert_ledger_reconciles(v_n); perform public.assert_ledger_reconciles(v_b);
  raise notice 'PASS: RC_COIN — % coin before and after; % closed into Lisbon', v_coin, v_r->'closed'->>'ducats';

  -- RC_RETIRED
  if not exists (select 1 from public.players p where p.id = v_a and p.auth_uid is null and p.nation_id is null and p.retired_at is not null and not p.is_npc) then
    raise exception 'RC_RETIRED: the row';
  end if;
  if (select count(*) from public.events e where e.player_id = v_a) < v_ev + 1 or (select count(*) from public.ledger l where l.player_id = v_a) < v_led + 1
     or (select count(*) from public.level_book l where l.player_id = v_a) <> v_lvl then
    raise exception 'RC_RETIRED: a book was cut';
  end if;
  foreach v_t in array array['fleets','ships','voyages','orders','fleet_jobs','city_shares','player_storage','player_items','player_officers','land_parties','port_mayor','port_influence','house_regard',
                             'port_fee_debts','standings','houses_week','nation_race_book','wanted','standing_routes','armadas','hull_orders','early_sightings','sea_choices','insured_voyages','company_hqs',
                             'provision_presets','skill_queue'] loop
    execute format('select count(*) from public.%I where player_id = $1', v_t) into v_cnt using v_a;
    if v_cnt <> 0 then raise exception 'RC_RETIRED: % row(s) left in %', v_cnt, v_t; end if;
  end loop;
  if exists (select 1 from public.courier_contracts c where v_a in (c.poster_id, c.carrier_id) and c.status in ('open', 'taken'))
     or exists (select 1 from public.market_requests m where m.player_id = v_a and m.status = 'open')
     or (select c.status from public.courier_contracts c where c.id = v_k2) <> 'failed' or (select c.status from public.courier_contracts c where c.id = v_k) <> 'cancelled'
     or (select t.status from public.trade_contracts t where t.posted_day = -213) <> 'spent' then
    raise exception 'RC_RETIRED: a contract or request stands';
  end if;
  raise notice 'PASS: RC_RETIRED — the row and the books stay, nothing else does';

  -- RC_NOWHERE (asked as B, who is another company)
  perform cmd.assume_identity(c_b);
  delete from public.standings where board_slot = public.standings_slot_of(now());
  perform public.settle_standings(now());
  v_t := (select p.company_name from public.players p where p.id = v_a);
  if exists (select 1 from public.standings s where s.player_id = v_a) or position(v_t in world.stats_me()::text) > 0 or position(v_t in world.town_hall(v_lis)::text) > 0
     or position(v_t in world.city_history(v_lis)::text) > 0 or position(v_t in world.nation_standings()::text) > 0 or position(v_t in world.houses_week()::text) > 0
     or position(v_na in world.town_hall(v_lis)::text) > 0 or exists (select 1 from public.fleet_jobs_due() j where j.player_id = v_a) then
    raise exception 'RC_NOWHERE: a board knows her';
  end if;
  perform public.tick_influence(now()); perform public.city_coupon_hour(now()); perform public.houses_week_settle(now());
  if exists (select 1 from public.port_mayor m where m.player_id = v_a) or exists (select 1 from public.houses_week h where h.player_id = v_a) or (select p.ducats from public.players p where p.id = v_a) <> 0 then
    raise exception 'RC_NOWHERE: a tick paid, seated or ranked her';
  end if;
  perform cmd.assume_identity(c_a);
  raise notice 'PASS: RC_NOWHERE — no board, office, vote or tick';

  -- RC_NEW
  v_r := world.player()->'player';
  if v_r->>'id' <> v_n::text or v_r->>'company_name' <> v_nc or v_r->>'nation' <> 'ESP' or v_r->'hq'->>'at' <> 'SVQ' or (v_r->>'fleets')::int <> 1 or not (v_r->>'rename_free')::boolean
     or public.home_port_of(v_n) <> v_svq or (select count(*) from public.ledger l where l.player_id = v_n) <> 1 then
    raise exception 'RC_NEW: %', v_r - 'levels';
  end if;
  v_r := cmd.rename_company(v_na);
  if not (v_r->>'ok')::boolean then raise exception 'RC_NEW: the old name was not free: %', v_r; end if;
  raise notice 'PASS: RC_NEW — the ordinary start in Seville, the old name taken again';

  -- RC_DAY
  if cmd.restart_company(v_na, v_nc, 'PRT')->>'error_code' is distinct from 'E_RESTART_TODAY' or public.restart_refusal(v_b, now()) is not null
     or public.restart_refusal(v_n, now() + interval '1 day') is not null then
    raise exception 'RC_DAY: %', public.restart_refusal(v_n, now());
  end if;
  update public.company_retirements set retired_at = retired_at - interval '1 day' where player_id = v_a;
  v_coin := pg_temp.world_coin();
  v_r := cmd.restart_company(v_na, v_na, 'PRT');   -- and she may keep her own name
  if not coalesce((v_r->>'ok')::boolean, false) or (select p.company_name from public.players p where p.auth_uid = c_a) <> v_na or pg_temp.world_coin() <> v_coin then
    raise exception 'RC_DAY: %', v_r;
  end if;
  raise notice 'PASS: RC_DAY — once a real day, the same name kept, the coin still the same';

  -- RC_DOORS
  if not has_function_privilege('authenticated', 'cmd.restart_company(text,text,text)', 'execute') or has_function_privilege('anon', 'cmd.restart_company(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'cmd.restart_company(text,text,text)', 'execute')
     or exists (select 1 from unnest(array['public.company_retire(uuid,timestamptz)', 'public.restart_refusal(uuid,timestamptz)', 'public.restart_card(uuid)', 'public.hq_card(uuid)', 'public.company_heir(uuid)']) f(q),
                              unnest(array['anon', 'authenticated', 'service_role']) g(r) where has_function_privilege(g.r, f.q, 'execute'))
     or exists (select 1 from unnest(array['public.company_retirements', 'public.company_hqs', 'public.hq_steps']) f(q), unnest(array['anon', 'authenticated', 'service_role']) g(r)
                 where has_table_privilege(g.r, f.q, 'select, insert, update, delete')) then
    raise exception 'RC_DOORS: a grant is wrong';
  end if;
  perform cmd.assume_identity('00000000-0509-4000-8000-0000000002ff');
  if cmd.restart_company('x', 'y', 'PRT')->>'error_code' is distinct from 'E_NO_HOUSE' then raise exception 'RC_DOORS: an account with no company'; end if;
  raise notice 'PASS: RC_DOORS — a signed-in player alone';
  set constraints all immediate;
end $p$;
