-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 179 - FIRST VOYAGES  (migration 0476; docs/design/roadmap-2026-11-23.md slice 8; docs/dev-log/2026-11-23-first-voyages.md)
--
--   The migration's self-assert walks the chain with the purses dark. This proof plays it as production runs: the economy closed and the
--   city purses lit, so every coin a step pays leaves her capital (or her realm) and none is new; hold jobs planted at the harbours
--   nearest Lisbon (never a game day's dice); a realm that cannot pay; and the read's cost. Rolled back by proof.mjs.
--
-- @pass FV_DARK   dark: the read is {"on": false} and pays nothing, whatever she has done
-- @pass FV_JOB    lit, step 1: the job named is an open hold job with a source that sells its good, its trip from her capital the shortest
--                 of every such job that fits twice in the time it stands, and its seconds a Barca's
-- @pass FV_NONE   the same with no such job: the deliver step stands and names none (a JSON null)
-- @pass FV_PAY    lit, purses lit: a delivered request pays step 1 from Lisbon's purse (a moved coin: her purse up, the city's down, the
--                 same figure), its Reputation once, and hands on to the profit step
-- @pass FV_WAIT   a realm that cannot pay: the step waits (nothing written, nothing paid, `waiting` true); paid when it can
-- @pass FV_ONCE   every step paid once, in order, to the end (16,000 coin, 160 Reputation in all); reads after the end pay nothing
-- @pass FV_OLD    a company founded eight days ago, and a caller with no company, are offered nothing
-- @pass FV_COST   the read's cost on the deliver step (the hold jobs read) and on the profit step (her ledger read), timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0476-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0476-4000-8000-0000000000b1';
  c_o    constant uuid := '00000000-0476-4000-8000-0000000000c1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_b    uuid;
  v_o    uuid;
  v_p    uuid;
  v_r    jsonb;
  v_job  jsonb;
  v_min  numeric;
  v_nm   numeric;
  v_c    public.trade_contracts%rowtype;
  v_p0   bigint;
  v_t0   bigint;
  v_t1   bigint;
  v_rep0 bigint;
  v_sell bigint;
  v_off  uuid;
  v_n    int := 0;
  v_x    record;
  v_ms1  numeric;
  v_ms2  numeric;
  v_at   timestamptz;
  i      int;
begin
  -- the three companies are founded first, as a sign-up is
  v_a := public.new_house(c_a, 'Casa da Viagem A 179', 'PRT');
  v_b := public.new_house(c_b, 'Casa da Viagem B 179', 'PRT');
  v_o := public.new_house(c_o, 'Casa da Viagem O 179', 'PRT');
  update public.players set created_at = now() - interval '8 days' where id = v_o;
  -- every harbour's purse well above its reserve (as proof 174 seeds them), so the capital pays and a realm call is never needed
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;

  -- THE JOBS ARE PLANTED (a game day's dice may leave none that fits twice in its time): of the trips Lisbon - a harbour that sells a good - another harbour
  -- that takes none of its own, the three shortest. The shortest is already out of time, the second fits, the third fits and is longer
  update public.trade_contracts set status = 'expired' where status = 'open';
  for v_x in
    select distinct on (t.nm) sp.id as src, jp.id as dst, g.id as good, t.nm
      from (select p.id, p.code, (r.reaches ->> p.code)::numeric as nm from public.ports p join public.sea_reaches r on r.port_id = v_lis
             where p.kind = 'HARBOUR' and p.id <> v_lis and r.reaches ? p.code order by 3, 2 limit 6) sp
      join public.sea_reaches rs on rs.port_id = sp.id
      join public.ports jp on jp.kind = 'HARBOUR' and jp.id not in (sp.id, v_lis) and rs.reaches ? jp.code
      cross join lateral (select sp.nm + (rs.reaches ->> jp.code)::numeric as nm) t
      cross join lateral (select x.id from public.goods x join public.port_specialties s on s.port_id = sp.id and s.good_id = x.id order by x.code limit 1) g
     where t.nm < 800
     order by t.nm, sp.code, jp.code limit 3
  loop
    v_n := v_n + 1;
    insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size, source_port_id)
    values (v_x.dst, v_x.good, world.game_day() - 2, 190 + v_n, 20, 0.2, 100, 20, 400, world.game_day() + case when v_n = 1 then 0 else 2 end, 'open', 0, 'hold', v_x.src);
  end loop;
  if v_n <> 3 then
    raise exception 'PROOF 179 FAILED: % trips to plant, not three (static rows)', v_n;
  end if;

  -- ── FV_DARK ──
  perform cmd.assume_identity(c_a);
  perform public.credit(v_a, 'PREMIUM', 500, null);
  update public.world_config set value = 'false'::jsonb where key = 'first_voyages_enabled';
  if world.first_voyages() is distinct from '{"on": false}'::jsonb or exists (select 1 from public.first_voyages fv where fv.player_id = v_a) then
    raise exception 'PROOF 179 FAILED: dark, the read is not {"on": false} or it paid';
  end if;
  raise notice 'PASS: FV_DARK — dark: {"on": false}, nothing paid (she had delivered a request).';

  -- light it as production runs
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled', 'reputation_on', 'first_voyages_enabled');

  -- ── FV_JOB, on a company who has delivered nothing (B) ──
  perform cmd.assume_identity(c_b);
  v_r := world.first_voyages();
  v_job := v_r -> 'job';
  if (v_r ->> 'open')::boolean is distinct from true or (v_r ->> 'step')::int <> 1 or v_r ->> 'code' <> 'deliver' or (v_r ->> 'have')::int <> 0
     or jsonb_array_length(v_r -> 'just') <> 0 then
    raise exception 'PROOF 179 FAILED: lit, a fresh company is not on step 1 (deliver) with nothing paid: %', v_r;
  end if;
  select min(t.nm) into v_min
    from public.trade_contracts c
    join public.ports sp on sp.id = c.source_port_id
    join public.ports jp on jp.id = c.port_id
    join public.sea_reaches rc on rc.port_id = v_lis
    join public.sea_reaches rs on rs.port_id = c.source_port_id
   cross join lateral (select case when sp.id = v_lis then 0 else (rc.reaches ->> sp.code)::numeric end + (rs.reaches ->> jp.code)::numeric as nm) t
   where c.status = 'open' and c.size = 'hold' and c.premium_per_unit > 0
     and t.nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression') * 2
         < extract(epoch from public.clock_start('game_day', c.expires_day) - now());
  if v_min is null then
    raise exception 'PROOF 179 FAILED: % hold jobs planted near Lisbon and none fits twice in its time', v_n;
  end if;
  if v_min <= (select min(case when sp.id = v_lis then 0 else (rc.reaches ->> sp.code)::numeric end + (rs.reaches ->> jp.code)::numeric)
                 from public.trade_contracts c join public.ports sp on sp.id = c.source_port_id join public.ports jp on jp.id = c.port_id
                 join public.sea_reaches rc on rc.port_id = v_lis join public.sea_reaches rs on rs.port_id = c.source_port_id
                where c.status = 'open' and c.size = 'hold') then
    raise exception 'PROOF 179 FAILED: the planted job out of time is not the shortest: the scene proves nothing';
  end if;
  select * into v_c from public.trade_contracts c where c.id = (v_job ->> 'id')::uuid;
  v_nm := (case when v_c.source_port_id = v_lis then 0
                else (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = v_lis and sp.id = v_c.source_port_id) end)
        + (select (r.reaches ->> jp.code)::numeric from public.sea_reaches r, public.ports jp where r.port_id = v_c.source_port_id and jp.id = v_c.port_id);
  if v_c.id is null or v_c.status <> 'open' or v_c.size <> 'hold'
     or not exists (select 1 from public.port_specialties s where s.port_id = v_c.source_port_id and s.good_id = v_c.good_id)
     or (select p.code from public.ports p where p.id = v_c.source_port_id) <> v_job -> 'from' ->> 'code'
     or (select p.code from public.ports p where p.id = v_c.port_id) <> v_job -> 'port' ->> 'code'
     or abs(v_nm - v_min) > 0.5 or abs(round(v_nm) - (v_job ->> 'nm')::numeric) > 0.5
     or abs((v_job ->> 'sail_seconds')::numeric - v_nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression')) > 1 then
    raise exception 'PROOF 179 FAILED: the job named is not the shortest open hold job from Lisbon that fits (min % nm): % / %', v_min, v_job, to_jsonb(v_c);
  end if;
  raise notice 'PASS: FV_JOB — % hold jobs planted near Lisbon; named: % x % bought at %, delivered to %: % nm, % s for a Barca (the shortest that fits)',
    v_n, v_job ->> 'qty', v_job -> 'good' ->> 'code', v_job -> 'from' ->> 'code', v_job -> 'port' ->> 'code', v_job ->> 'nm', v_job ->> 'sail_seconds';

  -- ── FV_NONE: none fits: the step stands, no job named (a JSON null, as the client reads it) ──
  begin
    update public.trade_contracts set status = 'expired' where status = 'open' and size = 'hold' and expires_day > world.game_day();
    v_r := world.first_voyages();
    if v_r ->> 'code' <> 'deliver' or (v_r ->> 'open')::boolean is not true or not (v_r ? 'job') or jsonb_typeof(v_r -> 'job') <> 'null' or public.first_voyage_job(v_b) is not null then
      raise exception 'PROOF 179 FAILED: no job fits, yet the step names one or is gone: %', v_r;
    end if;
    raise notice 'PASS: FV_NONE — none fits: step % stands, job null', v_r ->> 'code';
    raise exception using errcode = 'ZP179', message = 'undo';
  exception when sqlstate 'ZP179' then null;
  end;

  -- ── FV_COST (the deliver step: her ledger, and the hold jobs) ──
  v_at := clock_timestamp();
  for i in 1 .. 20 loop
    perform world.first_voyages();
  end loop;
  v_ms1 := round(extract(epoch from clock_timestamp() - v_at) * 1000 / 20, 2);

  -- ── FV_PAY: A delivered a request; Lisbon pays her step 1 ──
  perform cmd.assume_identity(c_a);
  v_p0 := (select p.ducats from public.players p where p.id = v_a);
  v_rep0 := coalesce((select b.balance from public.reputation_balance b where b.player_id = v_a), 0);
  v_t0 := (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.player_id = v_a and f.kind = 'VOYAGE_REWARD');
  v_r := world.first_voyages();
  v_t1 := (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.player_id = v_a and f.kind = 'VOYAGE_REWARD');
  if v_r -> 'just' <> '[{"step": 1, "code": "deliver", "ducats": 2000, "reputation": 20}]'::jsonb or v_r ->> 'code' <> 'profit'
     or (select p.ducats from public.players p where p.id = v_a) <> v_p0 + 2000
     or v_t1 - v_t0 <> -2000
     or not exists (select 1 from public.treasury_flows f where f.player_id = v_a and f.kind = 'VOYAGE_REWARD' and f.port_id = v_lis)
     or coalesce((select b.balance from public.reputation_balance b where b.player_id = v_a), 0) <> v_rep0 + 20 then
    raise exception 'PROOF 179 FAILED: step 1 did not pay 2,000 from Lisbon''s purse and 20 Reputation: % (purse % -> %, flows %)', v_r, v_p0,
      (select p.ducats from public.players p where p.id = v_a), v_t1 - v_t0;
  end if;
  raise notice 'PASS: FV_PAY — step 1 paid: purse % -> % (+2,000), Lisbon''s flows -2,000 (moved, no new gold), Reputation +20; now step 2 (profit %/%)',
    v_p0, v_p0 + 2000, v_r ->> 'have', v_r ->> 'need';

  -- ── FV_COST (the profit step: her ledger summed) ──
  v_at := clock_timestamp();
  for i in 1 .. 20 loop
    perform world.first_voyages();
  end loop;
  v_ms2 := round(extract(epoch from clock_timestamp() - v_at) * 1000 / 20, 2);

  -- ── FV_WAIT: no Portuguese harbour holds anything above its reserve ──
  v_sell := 10000 - coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = v_a and public.ledger_is_trade(l.kind)), 0);
  perform public.city_pays(v_lis, v_a, 'SELL', v_sell, null);
  update public.port_treasury t set reserve = t.ducats + 1000000000
   where public.port_nation(t.port_id) = (select p.nation_id from public.players p where p.id = v_a);
  v_p0 := (select p.ducats from public.players p where p.id = v_a);
  v_r := world.first_voyages();
  if (v_r ->> 'waiting')::boolean is distinct from true or jsonb_array_length(v_r -> 'just') <> 0 or v_r ->> 'code' <> 'profit'
     or (select count(*) from public.first_voyages fv where fv.player_id = v_a) <> 1
     or (select p.ducats from public.players p where p.id = v_a) <> v_p0 then
    raise exception 'PROOF 179 FAILED: a realm that cannot pay did not leave the step waiting with nothing written: %', v_r;
  end if;
  update public.port_treasury t set reserve = 0
   where public.port_nation(t.port_id) = (select p.nation_id from public.players p where p.id = v_a);
  v_r := world.first_voyages();
  if v_r -> 'just' -> 0 ->> 'code' <> 'profit' or (v_r ->> 'waiting')::boolean or (select p.ducats from public.players p where p.id = v_a) <> v_p0 + 3000 then
    raise exception 'PROOF 179 FAILED: the realm able again, the profit step did not pay 3,000: %', v_r;
  end if;
  raise notice 'PASS: FV_WAIT — every Portuguese reserve above its purse: `waiting`, nothing written or paid; reserves back: the profit step paid 3,000.';

  -- ── FV_ONCE: Trading 3, a captain, a hull on order; then reads after the end ──
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 3)
    on conflict (player_id, track) do update set level = 3;
  select o.id into v_off from public.officers o order by o.code limit 1;
  insert into public.player_officers (player_id, officer_id) values (v_a, v_off) on conflict do nothing;
  insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
  values (v_a, v_lis, 'barca', 15000, 2566, 30991, 48557, now(), now() + interval '30 minutes');
  v_r := world.first_voyages();
  if (select array_agg(e ->> 'code' order by o) from jsonb_array_elements(v_r -> 'just') with ordinality j(e, o)) <> array['trading', 'captain', 'hull']
     or (v_r ->> 'open')::boolean or (v_r ->> 'done')::int <> 5 then
    raise exception 'PROOF 179 FAILED: the last three steps did not pay in order and close the chain: %', v_r;
  end if;
  for i in 1 .. 3 loop
    if jsonb_array_length(world.first_voyages() -> 'just') <> 0 then
      raise exception 'PROOF 179 FAILED: a read after the end paid again';
    end if;
  end loop;
  if (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_a and l.kind = 'VOYAGE_REWARD') <> 16000
     or (select count(*) from public.ledger l where l.player_id = v_a and l.kind = 'VOYAGE_REWARD') <> 5
     or (select sum(f.ducats) from public.treasury_flows f where f.player_id = v_a and f.kind = 'VOYAGE_REWARD') <> -16000
     or (select sum(b.delta) from public.reputation_book b where b.player_id = v_a and b.kind = 'first_voyage') <> 160
     or (select count(*) from public.first_voyages fv where fv.player_id = v_a) <> 5 then
    raise exception 'PROOF 179 FAILED: the chain did not pay 16,000 coin (moved) and 160 Reputation in five rows';
  end if;
  raise notice 'PASS: FV_ONCE — five steps, five rows, 16,000 coin from the cities'' purses (flows -16,000), 160 Reputation; three reads after the end paid nothing.';

  -- ── FV_OLD ──
  perform public.credit(v_o, 'PREMIUM', 500, null);
  perform cmd.assume_identity(c_o);
  v_r := world.first_voyages();
  if v_r <> '{"on": true, "open": false}'::jsonb or exists (select 1 from public.first_voyages fv where fv.player_id = v_o) then
    raise exception 'PROOF 179 FAILED: a company founded eight days ago was offered or paid the chain: %', v_r;
  end if;
  perform cmd.assume_identity('00000000-0476-4000-8000-0000000000ff');
  if world.first_voyages() <> '{"on": true, "open": false}'::jsonb then
    raise exception 'PROOF 179 FAILED: a caller with no company was offered the chain';
  end if;
  raise notice 'PASS: FV_OLD — founded eight days ago (a request delivered): open false, nothing paid; no company: open false.';

  raise notice 'PASS: FV_COST — the read: % ms on the deliver step (with % hold jobs open), % ms on the profit step (20 reads each)',
    v_ms1, (select count(*) from public.trade_contracts c where c.status = 'open' and c.size = 'hold'), v_ms2;
end $p$;
