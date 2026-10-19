-- ── 6. THE PROBES (their own company's rows; every block rolled back whole) ─────────────────────
create temp table probe_0211 (k text primary key, j jsonb) on commit drop;

-- THE PROBE'S COMPANY at Lisbon: the founding barca, resupplied, with two goods on board at a known cost
-- (40 of the first at 25, 10 of the second at 100 — a cargo worth exactly 2,000), a deep purse, and Lisbon's
-- purse lit with no reserve. Goods: the first two by code whose bulk is 1, so the hold arithmetic is plain.
create or replace function pg_temp.house_0211()
returns jsonb
language plpgsql
as $$
declare
  c_uid  constant uuid := '00000000-0211-4000-8000-000000000001';
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_f    uuid;
  v_a    text;
  v_b    text;
  v_la   numeric;
  v_lb   numeric;
begin
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_p := public.new_house(c_uid, 'Casa do Seguro 0211', 'PRT', 'LIS');
  select id into v_f from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0211', 1000000);
  begin   -- full casks already (a founding barca) or topped up now: both are a ship that can make Funchal
      perform cmd.do_provision(v_f, jsonb_build_object('mode', 'DAYS', 'days', 12));
    exception when others then if sqlerrm not like 'E_HOLD_FULL%' then raise; end if; end;
  select code into v_a from public.goods where bulk = 1 order by code limit 1;
  select code into v_b from public.goods where bulk = 1 and code > v_a order by code limit 1;
  v_la := public.fleet_load(v_f, v_a, 40, 25);
  v_lb := public.fleet_load(v_f, v_b, 10, 100);
  if v_la <> 40 or v_lb <> 10 or public.fleet_stock_at_cost(v_f) <> 2000 then
    raise exception '0211 self-assert FAIL: the probe''s cargo did not load (% of 40 %, % of 10 %, worth %)',
      v_la, v_a, v_lb, v_b, public.fleet_stock_at_cost(v_f);
  end if;
  update public.port_treasury set reserve = 0 where port_id in (v_lis, v_fnc);
  perform public.treasury_post(v_lis, 'PROBE_0211', 10000000, null, null, true);
  return jsonb_build_object('player', v_p, 'fleet', v_f, 'lis', v_lis, 'fnc', v_fnc, 'a', v_a, 'b', v_b,
    'course', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                        jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                 from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc));
end $$;

-- every day of THIS voyage a raid (its own path's hazard_mult; nothing but PIRATES in any sea's mix; the
-- path's seas at the most raiders a sea breeds, piracy 1), then the voyage set back 30 days so one settle lands her.
-- p_lit: the fight decides, and with no evasion an unarmed barca's crew always surrenders → PLUNDERED (0202).
-- Dark: DESIGN B.6's table, escort ~3 against raiders 20–60 → STRIPPED.
create or replace function pg_temp.raided_0211(p_voyage uuid, p_lit boolean)
returns void
language plpgsql
as $$
begin
  update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = to_jsonb(p_lit) where key = 'combat_bite';
  update public.world_config set value = '0'::jsonb where key = 'fight_evade_max';
  -- every other kind OUT of the mix (no band at all, so no draw can land outside PIRATES: no lottery)
  update public.voyage_event_kinds set in_sea_mix = false, is_rolled = false, mix_base = null, mix_danger = null, mix_raiders = null
   where in_sea_mix and code <> 'PIRATES';
  update public.seas s set piracy_index = 1
   where s.id in (select (e->>'sea_id')::uuid from public.voyages v, jsonb_array_elements(v.path) e where v.id = p_voyage);
  update public.voyages vo
     set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                   from jsonb_array_elements(vo.path) with ordinality t(e, o)),
         departed_at = departed_at - interval '30 days', eta = eta - interval '30 days'
   where vo.id = p_voyage;
end $$;

-- what the raids should have carried off and what the insurance should have paid, re-derived day by day from the
-- cargo at departure, the knobs and the day's own roll (an independent re-statement of raid_takes / insurance_claim)
create or replace function pg_temp.expected_0211(p_voyage uuid, p_cargo jsonb, p_basis jsonb, p_surplus bigint)
returns jsonb
language plpgsql
as $$
declare
  ve      record;
  e       record;
  v_have  jsonb := p_cargo;
  v_share numeric;
  v_take  numeric;
  v_lostv numeric;
  v_owed  bigint;
  v_pay   bigint;
  v_left  bigint := p_surplus;
  v_days  jsonb := '[]'::jsonb;
  v_sum_owed bigint := 0;
  v_sum_paid bigint := 0;
  v_taken jsonb;
begin
  for ve in select day_index, kind, payload from public.voyage_events where voyage_id = p_voyage and kind = 'PIRATES' order by day_index loop
    v_share := case ve.payload->>'outcome' when 'STRIPPED' then 1
                    when 'PLUNDERED' then public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng(p_voyage, ve.day_index, 'plunder')
                    else 0 end;
    v_lostv := 0; v_taken := '{}'::jsonb;
    for e in select key, (value)::text::numeric as q from jsonb_each(v_have) order by key loop
      v_take := case when v_share >= 1 then e.q else floor(e.q * v_share) end;
      if v_take > 0 then
        v_taken := v_taken || jsonb_build_object(e.key, v_take);
        v_have := v_have || jsonb_build_object(e.key, e.q - v_take);
        v_lostv := v_lostv + v_take * (p_basis->>e.key)::numeric;
      end if;
    end loop;
    v_owed := round(round(v_lostv) * (1 - public.wc_num('insurance_keep_pct')));
    v_pay := least(v_owed, greatest(v_left, 0));
    v_left := v_left - v_pay;
    v_sum_owed := v_sum_owed + v_owed;
    v_sum_paid := v_sum_paid + v_pay;
    v_days := v_days || jsonb_build_object('day', ve.day_index, 'outcome', ve.payload->>'outcome', 'taken', v_taken,
                                           'served', coalesce(ve.payload->'cargo_lost', '{}'::jsonb), 'owed', v_owed, 'paid', v_pay);
  end loop;
  return jsonb_build_object('days', v_days, 'owed', v_sum_owed, 'paid', v_sum_paid, 'left', v_have);
end $$;

-- what the record says the insurance paid on a voyage: the events, the ledger and the two cities' books
create or replace function pg_temp.paid_0211(p_voyage uuid, p_player uuid, p_lis uuid, p_fnc uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'events', (select count(*) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ev_paid', (select coalesce(sum((e.payload->>'paid')::bigint), 0) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ev_short', (select coalesce(sum((e.payload->>'short')::bigint), 0) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ledger', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = p_player and l.kind = 'INSURANCE_PAID'),
    'lis', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.port_id = p_lis and t.kind = 'INSURANCE_PAID' and t.player_id = p_player),
    'fnc', (select count(*) from public.treasury_flows t where t.port_id = p_fnc and t.kind = 'INSURANCE_PAID' and t.player_id = p_player),
    'policy', (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = p_voyage),
    'cargo', (select coalesce(jsonb_object_agg(k.key, k.q), '{}'::jsonb) from (select e.key, sum((e.value)::text::numeric) q
                from public.ships s cross join lateral jsonb_each(s.cargo) e
               where s.fleet_id = (select fleet_id from public.voyages where id = p_voyage) group by e.key) k),
    'status', (select status from public.voyages where id = p_voyage))
$$;

-- (P1) A PRICE IS CHARGED ONCE. The preview quotes it and writes nothing; the SAIL charges it, to Lisbon, once;
-- the price is value × risk × 0.9 × (1 + margin), the risk re-derived here from the roll's own figures; the
-- voyage to her arrival (and the queue after it) charges nothing more. An unasked SAIL quotes the same price and
-- charges nothing, and sails the same course as the pre-image body.
do $$
declare
  h      jsonb;
  v_f    uuid; v_p uuid; v_lis uuid;
  v_prev jsonb;
  v_r    jsonb;
  v_q    jsonb;
  v_old  jsonb;
  v_voy  uuid;
  v_d0   bigint; v_t0 bigint;
  v_risk numeric;
  v_out  jsonb;
  v_ins_after_prev int;
  v_t    timestamptz;
  v_ms   jsonb := '[]'::jsonb;
  v_k    int;
begin
  begin
    h := pg_temp.house_0211();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_lis := (h->>'lis')::uuid;
    -- the unasked SAIL and the pre-image body, each thrown away
    begin
      v_q := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course'));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    begin
      v_old := pg_temp.do_sail_b0211(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course'));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    v_prev := cmd.preview(v_f, 'SAIL FNC INSURED', h->'course');
    v_ins_after_prev := (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE');
    v_d0 := (select ducats from public.players where id = v_p);
    v_t0 := public.treasury_balance(v_lis);
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true));
    v_voy := (v_r->>'voyage_id')::uuid;
    select round(1 - exp(sum(ln(1 - hr.p_hazard * m.share * public.wc_num('insurance_raid_loss')))), 6) into v_risk
      from generate_series(1, voyage.total_days(v_voy)) g(d)
     cross join lateral voyage.hazard_roll(v_voy, g.d) hr
     cross join lateral (select mx.share from voyage.sea_mix((voyage.leg_at_day(v_voy, g.d)->>'sea_id')::uuid) mx
                          where mx.kind_code = 'PIRATES') m;
    -- the cost of a quote, timed (8 calls, one session)
    for v_k in 1 .. 8 loop
      v_t := clock_timestamp();
      perform voyage.risk_quote(v_voy);
      v_ms := v_ms || to_jsonb(round(extract(epoch from clock_timestamp() - v_t) * 1000, 2));
    end loop;
    v_out := jsonb_build_object('r', v_r, 'q', v_q, 'old', v_old, 'prev', v_prev->'estimate'->'insurance',
      'prev_ok', v_prev->'ok', 'ins_after_prev', v_ins_after_prev, 'risk', v_risk, 'days', voyage.total_days(v_voy),
      'want_price', ceil(2000 * v_risk * (1 - public.wc_num('insurance_keep_pct')) * (1 + public.wc_num('insurance_margin'))),
      'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
      'lis_delta', public.treasury_balance(v_lis) - v_t0,
      'policies', (select count(*) from public.insured_voyages where player_id = v_p),
      'policy', (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = v_voy),
      'quote_ms', v_ms);
    update public.voyages set departed_at = departed_at - interval '30 days', eta = eta - interval '30 days' where id = v_voy;
    perform voyage.settle(v_f, now());
    perform cmd.advance(v_f, now());
    perform voyage.settle(v_f, now());
    v_out := v_out || jsonb_build_object('status', (select status from public.voyages where id = v_voy),
      'charges', (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE'),
      'charged', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE'),
      'lis_flows', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.port_id = v_lis and t.kind = 'INSURANCE' and t.player_id = v_p),
      'insured_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'INSURED'));
    insert into probe_0211 values ('once', v_out);
    raise exception 'RB_0211';
  exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
end $$;

-- (P2) A PLUNDERED VOYAGE IS PAID FOR, BY THE CITY THAT INSURED IT. Lit, every day a raid her crew cannot hold:
-- every day PLUNDERED; each takes its share of what is left; the insurance pays the loss at the policy's basis
-- less 10 %, from Lisbon (where she sailed from), never from Funchal.
-- (P3) A SHORTFALL IS RECORDED. The same voyage with Lisbon's surplus set to 50 after she sails.
-- (P4) STRIPPED. Dark, the table strips her on the first raid: all 2,000 lost, 1,800 paid.
create or replace function pg_temp.loss_0211(p_lit boolean, p_surplus bigint)
returns jsonb
language plpgsql
as $$
declare
  h      jsonb;
  v_f    uuid; v_p uuid; v_lis uuid; v_fnc uuid;
  v_r    jsonb;
  v_voy  uuid;
  v_pol  record;
  v_exp  jsonb;
  v_out  jsonb;
  v_sur  bigint;
  v_t    timestamptz;
begin
  begin
    h := pg_temp.house_0211();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_lis := (h->>'lis')::uuid; v_fnc := (h->>'fnc')::uuid;
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true));
    v_voy := (v_r->>'voyage_id')::uuid;
    select * into v_pol from public.insured_voyages where voyage_id = v_voy;
    if p_surplus is not null then
      perform public.treasury_post(v_lis, 'PROBE_0211', p_surplus - public.city_surplus(v_lis), null, null, true);
    end if;
    v_sur := public.city_surplus(v_lis);
    perform pg_temp.raided_0211(v_voy, p_lit);
    v_t := clock_timestamp();
    perform voyage.settle(v_f, now());
    v_out := jsonb_build_object('settle_ms', round(extract(epoch from clock_timestamp() - v_t) * 1000, 1),
      'value', v_pol.value, 'basis', v_pol.basis, 'cargo0', v_pol.cargo, 'surplus', v_sur,
      'days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.day_index <= voyage.total_days(v_voy)),
      'raids', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'PIRATES'),
      'outcomes', (select jsonb_object_agg(o, n) from (select ve.payload->>'outcome' o, count(*) n from public.voyage_events ve
                     where ve.voyage_id = v_voy and ve.kind = 'PIRATES' group by 1) z),
      'want', pg_temp.expected_0211(v_voy, v_pol.cargo, v_pol.basis, v_sur),
      'got', pg_temp.paid_0211(v_voy, v_p, v_lis, v_fnc));
    raise exception 'RB_0211';
  exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
  return v_out;
end $$;

do $$
begin
  insert into probe_0211 values ('plunder', pg_temp.loss_0211(true, null));
  insert into probe_0211 values ('short', pg_temp.loss_0211(true, 50));
  insert into probe_0211 values ('stripped', pg_temp.loss_0211(false, null));
end $$;

-- (P5) A MERCHANT INSURES BY HERSELF, and sails uninsured when her purse cannot pay. The first merchant fleet of the
-- roster (by roster_ord), brought to Lisbon with the same two goods, sails to Funchal with no INSURED word.
do $$
declare
  v_f   uuid;
  v_p   uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_fnc uuid := (select id from public.ports where code = 'FNC');
  v_a   text := (select code from public.goods where bulk = 1 order by code limit 1);
  v_crs jsonb := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                    from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
  v_r   jsonb;
  v_r2  jsonb;
  v_d0  bigint;
  v_out jsonb;
begin
  select nf.fleet_id, nf.player_id into v_f, v_p from public.npc_fleets nf order by nf.roster_ord, nf.fleet_id limit 1;
  if v_f is null then
    raise exception '0211 self-assert FAIL: there is no merchant fleet to probe';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.voyages set status = 'ABORTED' where fleet_id = v_f and status = 'SAILING';
    update public.orders set status = 'cancelled' where fleet_id = v_f and status in ('pending', 'active', 'failed');
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null where id = v_f;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_f;
    perform public.credit(v_p, 'PROBE_0211', 1000000);
    begin   -- full casks already (a founding barca) or topped up now: both are a ship that can make Funchal
      perform cmd.do_provision(v_f, jsonb_build_object('mode', 'DAYS', 'days', 12));
    exception when others then if sqlerrm not like 'E_HOLD_FULL%' then raise; end if; end;
    perform public.fleet_load(v_f, v_a, 20, 50);
    begin
      perform public.credit(v_p, 'PROBE_0211', -(select ducats from public.players where id = v_p));
      v_r2 := cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_crs));
      v_r2 := v_r2 || jsonb_build_object('charges', (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE' and l.created_at >= now()));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    v_d0 := (select ducats from public.players where id = v_p);
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_crs));
    v_out := jsonb_build_object('r', v_r->'insurance', 'broke', v_r2->'insurance', 'broke_charges', v_r2->'charges',
      'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
      'policy', (select count(*) from public.insured_voyages i where i.voyage_id = (v_r->>'voyage_id')::uuid));
    insert into probe_0211 values ('merchant', v_out);
    raise exception 'RB_0211';
  exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
end $$;

-- (P6) THE REFOUND NO LONGER RUNS. The first merchant house of the roster, worth nothing (purse 0, holds empty),
-- the traders on, its cooldown off: the PRE-IMAGE body refounds her (the positive control: the probe can see a
-- refound); the new body does not, and moves no coin.
do $$
declare
  v_p   uuid := (select h.player_id from public.npc_houses h order by h.roster_ord, h.player_id limit 1);
  v_old jsonb;
  v_new jsonb;
  v_n0  int;
  v_d0  bigint;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = '0'::jsonb where key = 'npc_refound_cooldown_game_days';
    update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb from public.fleets f where f.id = s.fleet_id and f.player_id = v_p;
    perform public.credit(v_p, 'PROBE_0211', -(select ducats from public.players where id = v_p));
    v_n0 := (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED');
    begin
      v_old := pg_temp.tend_houses_b0211(now());
      v_old := jsonb_build_object('refounds', (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED') - v_n0,
                                  'purse', (select ducats from public.players where id = v_p));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    v_d0 := (select ducats from public.players where id = v_p);
    v_new := public.npc_tend_houses(now()) - 'notes';
    v_new := v_new || jsonb_build_object('refounds', (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED') - v_n0,
                                         'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
                                         'any_refound', (select count(*) from public.ledger l where l.kind = 'NPC_REFOUND' and l.created_at >= now()));
    insert into probe_0211 values ('refound', jsonb_build_object('old', v_old, 'new', v_new));
    raise exception 'RB_0211';
  exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
end $$;

-- (P7) THE WORD, AND WHAT DID NOT MOVE. cmd.parse reads INSURED and nothing else new; the pre-image parse refused
-- it (the change is seen). A voyage of storms, calms and fair winds (no raid) settles to the byte the same under the
-- old body and the new — the no-op proof for every arm this file did not mean to touch.
do $$
declare
  h     jsonb;
  v_f   uuid; v_p uuid;
  v_voy uuid;
  v_a   jsonb; v_b jsonb;
  v_out jsonb;
  v_oldp text;
begin
  begin
    h := pg_temp.house_0211();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid;
    begin
      perform pg_temp.parse_b0211(v_p, v_f, 'SAIL FNC INSURED');
      v_oldp := 'accepted';
    exception when others then v_oldp := sqlerrm; end;
    v_out := jsonb_build_object('new', cmd.parse(v_p, v_f, 'SAIL FNC INSURED'), 'plain', cmd.parse(v_p, v_f, 'SAIL FNC'),
                                'plain_old', pg_temp.parse_b0211(v_p, v_f, 'SAIL FNC'), 'old_insured', v_oldp);
    begin
      perform cmd.parse(v_p, v_f, 'SAIL FNC NOW');
      v_out := v_out || jsonb_build_object('bogus', 'accepted');
    exception when others then v_out := v_out || jsonb_build_object('bogus', sqlerrm); end;
    v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true))->>'voyage_id')::uuid;
    update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
    -- no raid: only STORM, CALM and FAIR_WIND in the mix (the rest out, with no band to land in)
    update public.voyage_event_kinds set in_sea_mix = false, is_rolled = false, mix_base = null, mix_danger = null, mix_raiders = null
     where in_sea_mix and code not in ('STORM', 'CALM', 'FAIR_WIND');
    update public.voyages vo
       set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o)),
           departed_at = departed_at - interval '30 days', eta = eta - interval '30 days'
     where vo.id = v_voy;
    begin
      perform pg_temp.settle_b0211(v_f, now());
      v_a := pg_temp.paid_0211(v_voy, v_p, (h->>'lis')::uuid, (h->>'fnc')::uuid) - 'policy'
             || jsonb_build_object('events', (select jsonb_agg(jsonb_build_array(ve.day_index, ve.kind, ve.payload, ve.resolved_at) order by ve.day_index)
                                                from public.voyage_events ve where ve.voyage_id = v_voy),
                                   'ships', (select jsonb_agg(jsonb_build_array(s.durability, s.crew, s.cargo, s.water_t, s.food_t) order by s.id) from public.ships s where s.fleet_id = v_f),
                                   'ducats', (select ducats from public.players where id = v_p));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    begin
      perform voyage.settle(v_f, now());
      v_b := pg_temp.paid_0211(v_voy, v_p, (h->>'lis')::uuid, (h->>'fnc')::uuid) - 'policy'
             || jsonb_build_object('events', (select jsonb_agg(jsonb_build_array(ve.day_index, ve.kind, ve.payload, ve.resolved_at) order by ve.day_index)
                                                from public.voyage_events ve where ve.voyage_id = v_voy),
                                   'ships', (select jsonb_agg(jsonb_build_array(s.durability, s.crew, s.cargo, s.water_t, s.food_t) order by s.id) from public.ships s where s.fleet_id = v_f),
                                   'ducats', (select ducats from public.players where id = v_p));
      raise exception 'RB_0211';
    exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
    v_out := v_out || jsonb_build_object('same', v_a = v_b, 'hazard_days', jsonb_array_length(coalesce(v_a->'events', '[]'::jsonb)),
                                         'status', v_a->>'status', 'a', case when v_a = v_b then null else v_a end,
                                         'b', case when v_a = v_b then null else v_b end);
    insert into probe_0211 values ('word', v_out);
    raise exception 'RB_0211';
  exception when others then if sqlerrm <> 'RB_0211' then raise; end if; end;
end $$;

-- ── 7. THE ASSERTS ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  o  jsonb := (select j from probe_0211 where k = 'once');
  pl jsonb := (select j from probe_0211 where k = 'plunder');
  sh jsonb := (select j from probe_0211 where k = 'short');
  st jsonb := (select j from probe_0211 where k = 'stripped');
  m  jsonb := (select j from probe_0211 where k = 'merchant');
  rf jsonb := (select j from probe_0211 where k = 'refound');
  w  jsonb := (select j from probe_0211 where k = 'word');
  v_price bigint;
  x  jsonb;
  v_readers text;
begin
  if o is null or pl is null or sh is null or st is null or m is null or rf is null or w is null then
    raise exception '0211 self-assert FAIL: a probe wrote nothing (once % plunder % short % stripped % merchant % refound % word %)',
      o is not null, pl is not null, sh is not null, st is not null, m is not null, rf is not null, w is not null;
  end if;

  -- (P1) charged once, at the quoted price, to the city she sailed from
  v_price := (o->'r'->'insurance'->>'price')::bigint;
  if not coalesce((o->'r'->'insurance'->>'insured')::boolean, false) or v_price is null or v_price < 1
     or (o->'r'->'insurance'->>'value')::bigint <> 2000 then
    raise exception '0211 self-assert FAIL: an insured SAIL did not insure the cargo worth 2,000: %', o->'r'->'insurance';
  end if;
  if (o->>'risk')::numeric is null or (o->>'risk')::numeric <= 0
     or (o->'r'->'insurance'->>'risk')::numeric <> (o->>'risk')::numeric or v_price <> (o->>'want_price')::bigint then
    raise exception '0211 self-assert FAIL: the price is not value × risk × (1 − keep) × (1 + margin) on the roll''s own risk: served % (risk %), re-derived % (risk %)',
      v_price, o->'r'->'insurance'->>'risk', o->>'want_price', o->>'risk';
  end if;
  if (o->>'purse_delta')::bigint <> -v_price or (o->>'lis_delta')::bigint <> v_price or (o->>'policies')::int <> 1 then
    raise exception '0211 self-assert FAIL: the price did not move once from her purse to Lisbon''s: purse %, Lisbon %, price %, policies %',
      o->>'purse_delta', o->>'lis_delta', v_price, o->>'policies';
  end if;
  if (o->>'status') <> 'ARRIVED' or (o->>'charges')::int <> 1 or (o->>'charged')::bigint <> -v_price
     or (o->>'lis_flows')::bigint <> v_price or (o->>'insured_events')::int <> 1 then
    raise exception '0211 self-assert FAIL: charged more than once by the voyage''s end (status %, % charge(s) totalling %, Lisbon %, % event(s))',
      o->>'status', o->>'charges', o->>'charged', o->>'lis_flows', o->>'insured_events';
  end if;
  if not coalesce((o->>'prev_ok')::boolean, false) or (o->'prev'->>'price')::bigint <> v_price
     or (o->'prev'->>'insured')::boolean is not true or (o->>'ins_after_prev')::int <> 0 then
    raise exception '0211 self-assert FAIL: the preview did not quote the same price without charging it: %, % charge(s)', o->'prev', o->>'ins_after_prev';
  end if;
  if (o->'q'->'insurance'->>'insured')::boolean is not false or (o->'q'->'insurance'->>'price')::bigint <> v_price
     or (o->'q'->>'total_nm') is distinct from (o->'old'->>'total_nm') or (o->'q'->>'voyage_days') is distinct from (o->'old'->>'voyage_days')
     or (o->'q' - 'insurance' - 'voyage_id') <> (o->'old' - 'voyage_id') then
    raise exception '0211 self-assert FAIL: an unasked SAIL did not sail as before and quote the price: new %, old %', o->'q', o->'old';
  end if;

  -- (P2) plundered every day; each took its share of what was left; paid at the basis less 10 %, from Lisbon
  if (pl->>'raids')::int < 2 or (pl->>'raids')::int <> (pl->>'days')::int or pl->'outcomes' <> jsonb_build_object('PLUNDERED', (pl->>'raids')::int) then
    raise exception '0211 self-assert FAIL: the probe passage was not a raid a day, every one PLUNDERED (its precondition): % raid(s) in % day(s), %',
      pl->>'raids', pl->>'days', pl->'outcomes';
  end if;
  for x in select * from jsonb_array_elements(pl->'want'->'days') loop
    if x->'taken' <> x->'served' then
      raise exception '0211 self-assert FAIL: day % took % where 25–50 %% by its own roll is %', x->>'day', x->'served', x->'taken';
    end if;
  end loop;
  if (pl->'got'->'cargo') <> (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(pl->'want'->'left') t(k, v) where (v::text)::numeric > 0) then
    raise exception '0211 self-assert FAIL: what is left on board % is not what the raids should have left %', pl->'got'->'cargo', pl->'want'->'left';
  end if;
  if (pl->'got'->>'ledger')::bigint <> (pl->'want'->>'owed')::bigint or (pl->'got'->>'ev_paid')::bigint <> (pl->'want'->>'owed')::bigint
     or (pl->'got'->>'lis')::bigint <> -(pl->'want'->>'owed')::bigint or (pl->'got'->>'fnc')::int <> 0
     or (pl->'got'->'policy'->>'paid')::bigint <> (pl->'want'->>'owed')::bigint or (pl->'got'->'policy'->>'short')::bigint <> 0
     or (pl->'got'->>'events')::int <> jsonb_array_length(pl->'want'->'days') then
    raise exception '0211 self-assert FAIL: the plundered cargo was not paid at its basis less 10 %% by Lisbon: want %, got %', pl->'want'->>'owed', pl->'got';
  end if;

  -- (P3) the shortfall: Lisbon pays what its surplus holds, and the rest is recorded
  if (sh->>'surplus')::bigint <> 50 or (sh->'want'->>'owed')::bigint <= 50 then
    raise exception '0211 self-assert FAIL: the shortfall probe''s precondition: surplus % (want 50), owed % (want more)', sh->>'surplus', sh->'want'->>'owed';
  end if;
  if (sh->'got'->>'ledger')::bigint <> 50 or (sh->'got'->>'lis')::bigint <> -50
     or (sh->'got'->'policy'->>'paid')::bigint <> 50
     or (sh->'got'->'policy'->>'short')::bigint <> (sh->'want'->>'owed')::bigint - 50
     or (sh->'got'->>'ev_short')::bigint <> (sh->'want'->>'owed')::bigint - 50 then
    raise exception '0211 self-assert FAIL: the shortfall was not paid as far as the purse went and the rest recorded: owed %, got %', sh->'want'->>'owed', sh->'got';
  end if;

  -- (P4) stripped: everything lost, 90 % of 2,000 paid
  if (st->'outcomes'->>'STRIPPED')::int < 1 or (st->'got'->>'ledger')::bigint <> 1800 or (st->'got'->'cargo') <> '{}'::jsonb
     or (st->'got'->'policy'->>'lost_value')::bigint <> 2000 then
    raise exception '0211 self-assert FAIL: a stripped hold was not paid 1,800 of 2,000: %', st;
  end if;

  -- (P5) a merchant insures by herself; a broke one sails uninsured
  if (m->'r'->>'insured')::boolean is not true or (m->>'purse_delta')::bigint <> -(m->'r'->>'price')::bigint
     or (m->>'policy')::int <> 1 or (m->'broke'->>'insured')::boolean is not false or (m->'broke'->>'why') <> 'purse'
     or (m->>'broke_charges')::int <> 0 then
    raise exception '0211 self-assert FAIL: the merchant''s insurance: %', m;
  end if;

  -- (P6) the refound no longer runs (and the probe could see one)
  if (rf->'old'->>'refounds')::int <> 1 or (rf->'new'->>'refounds')::int <> 0 or (rf->'new'->>'purse_delta')::bigint <> 0
     or (rf->'new'->>'any_refound')::int <> 0 or rf->'new' ? 'refounded' then
    raise exception '0211 self-assert FAIL: the refound: pre-image % (want 1 refound), new % (want none)', rf->'old', rf->'new';
  end if;

  -- (P7) the word, and the no-op
  if (w->'new'->'args'->>'insured')::boolean is not true or w->'plain' <> w->'plain_old'
     or (w->>'old_insured') not like 'E_PARSE%' or (w->>'bogus') not like 'E_PARSE%' then
    raise exception '0211 self-assert FAIL: the INSURED word: %', w;
  end if;
  if not (w->>'same')::boolean or (w->>'hazard_days')::int < 2 or (w->>'status') <> 'ARRIVED' then
    raise exception '0211 self-assert FAIL: a voyage with no raid did not settle the same under the old body and the new (% days, %): % / %',
      w->>'hazard_days', w->>'status', w->'a', w->'b';
  end if;

  -- READERS: each new author has the one reader it was written for
  select string_agg(format('%s reads %s', n.nspname || '.' || p.proname, t.f), '; ') into v_readers
    from (values ('voyage.raid_takes', 'voyage.settle'), ('public.insurance_claim', 'voyage.settle'),
                 ('public.insure_voyage', 'cmd.do_sail'), ('voyage.risk_quote', 'public.insure_voyage'),
                 ('public.insurance_price', 'public.insure_voyage')) t(f, owner)
    join pg_proc p on p.prosrc like '%' || t.f || '(%'
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage') and n.nspname || '.' || p.proname <> t.owner;
  if v_readers is not null then
    raise exception '0211 self-assert FAIL: a second reader: %', v_readers;
  end if;
  if (select count(*) from pg_proc p where p.prosrc like '%voyage.raid_takes(%' and p.oid = 'voyage.settle(uuid, timestamp with time zone)'::regprocedure) <> 1
     or (select count(*) from pg_proc p where p.prosrc like '%public.insure_voyage(%' and p.oid = 'cmd.do_sail(uuid, jsonb)'::regprocedure) <> 1 then
    raise exception '0211 self-assert FAIL: the readers are not wired (settle → raid_takes, do_sail → insure_voyage)';
  end if;

  -- WALLS
  if exists (select 1 from public.client_write_grants() g where g.table_name = 'insured_voyages')
     or exists (select 1 from public.client_executable_writers() w2
                 where w2.function_name in ('insure_voyage', 'insurance_claim', 'raid_takes', 'risk_quote', 'insurance_price', 'insurance'))
     or has_table_privilege('authenticated', 'public.insured_voyages', 'select')
     or not has_function_privilege('authenticated', 'world.insurance()', 'execute')
     or has_function_privilege('anon', 'world.insurance()', 'execute')
     or has_function_privilege('authenticated', 'public.insure_voyage(uuid, boolean)', 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'world.insurance()'::regprocedure) then
    raise exception '0211 self-assert FAIL: the walls — a client can write or read past the one read, or the read is not registered';
  end if;
  -- the knobs
  if public.wc_num('insurance_raid_loss') is null or public.wc_num('insurance_keep_pct') <> 0.10
     or public.wc_num('insurance_margin') is null or public.wc_num('plunder_share_min') <> 0.25 or public.wc_num('plunder_share_span') <> 0.25 then
    raise exception '0211 self-assert FAIL: the knobs';
  end if;

  raise notice '0211 probe timings: risk_quote % ms over % days; settle of a raided passage % / % / % ms (plunder / short / stripped)',
    o->'quote_ms', o->>'days', pl->>'settle_ms', sh->>'settle_ms', st->>'settle_ms';
  raise notice '0211 self-assert ok: A CARGO CAN BE INSURED. ONCE: 2,000 insured LIS → FNC over % days at risk % for % (re-derived %), purse −%, Lisbon +%, one charge to the end; the preview quoted it and charged nothing; an unasked SAIL quoted it, charged nothing, sailed as before. PLUNDERED % days: took % of %, paid % (basis less 10 %%) by Lisbon, none by Funchal. SHORT: owed %, Lisbon''s surplus 50 paid 50, % recorded short. STRIPPED: 2,000 lost, 1,800 paid. MERCHANT: insured by herself for %, uninsured when broke. REFOUND: pre-image refounded the broke house (%), the new body none. INSURED parses; the pre-image refused it; a raidless passage of % days settles to the byte as before. Readers one each; walls hold; % hunks reverse, ACLs unchanged.',
    o->>'days', o->>'risk', v_price, o->>'want_price', v_price, v_price,
    pl->>'raids', pl->'want'->'days'->0->'taken', pl->'cargo0', pl->'want'->>'owed',
    sh->'want'->>'owed', (sh->'want'->>'owed')::bigint - 50,
    m->'r'->>'price', rf->'old'->>'refounds', w->>'hazard_days', (select count(*) from hunks_0211);
end $$;

-- THE REFOUND'S KNOBS AND npc_worth GO LAST (the probe's positive control read them through the pre-image)
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'world', 'cmd', 'voyage')
                and (p.prosrc like '%npc_purse_floor_pct%' or p.prosrc like '%npc_refound_cooldown_game_days%'
                     or (p.prosrc like '%npc_worth%' and p.oid <> 'public.npc_worth(uuid)'::regprocedure))) then
    raise exception '0211 self-assert FAIL: the refound''s knobs or public.npc_worth still have a reader: %',
      (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'world', 'cmd', 'voyage')
          and (p.prosrc like '%npc_purse_floor_pct%' or p.prosrc like '%npc_refound_cooldown_game_days%'
               or (p.prosrc like '%npc_worth%' and p.oid <> 'public.npc_worth(uuid)'::regprocedure)));
  end if;
end $$;
delete from public.world_config where key in ('npc_purse_floor_pct', 'npc_refound_cooldown_game_days');
drop function public.npc_worth(uuid);
