-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 2 — LEDGER RECONCILIATION  (DESIGN Appendix 2, CI apply-proof requirement 2)
--
--   "Σ ledger.ducats_delta = players.ducats after a randomised 500-order soak."
--
-- WHY A SOAK AND NOT A UNIT TEST
--   The invariant is easy to hold on a path somebody thought about. It breaks on the path nobody
--   did: a trade that partially filled, a voyage that arrived mid-order, wages paid on a day the
--   purse could not cover, a queue that halted between a debit and a credit. So this proof does
--   not choose its 500 orders — it draws them at random from every V0 verb, against three houses,
--   with time jumping forward underneath them, and then asks the invariant to still be true.
--
-- HOW IT REFUSES TO PASS VACUOUSLY
--   * Orders must actually have SUCCEEDED (a soak in which everything was rejected reconciles
--     trivially: nothing moved).
--   * Orders must also have FAILED (if nothing was ever refused, the halt/rollback paths — the
--     ones most likely to leave a half-applied trade — were never exercised).
--   * Ducats must actually have MOVED, in both directions.
--   * And the check itself is proven able to fail: a purse is deliberately falsified at the end
--     and the reconciler must raise on it.
--
-- @pass LEDGER_SOAK_ORDERS_ISSUED   500 randomised orders were issued across 3 houses
-- @pass LEDGER_SOAK_MIXED_OUTCOMES  the soak contains both successes and refusals
-- @pass LEDGER_SOAK_MONEY_MOVED     ducats moved in both directions, over many ledger rows
-- @pass LEDGER_SOAK_RECONCILES      every house: purse = Σ ledger.ducats_delta, exactly
-- @pass LEDGER_SOAK_SAILING_INVARIANT  fleets.status='SAILING' ⟺ one SAILING voyage, still true
-- @pass LEDGER_SOAK_CHECK_BITES     the reconciler RAISES on a purse falsified by one ducat
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth   constant uuid[] := array['00000000-0f02-4000-8000-000000000001'::uuid,
                                    '00000000-0f02-4000-8000-000000000002'::uuid,
                                    '00000000-0f02-4000-8000-000000000003'::uuid];
  c_names  constant text[] := array['Casa Soak A', 'Casa Soak B', 'Casa Soak C'];
  v_players uuid[] := '{}';
  v_fleets  uuid[] := '{}';
  v_ports   text[];
  v_goods   text[];
  i         int;
  k         int;
  h         int;
  v_cmd     text;
  v_roll    numeric;
  v_issued  int := 0;
  v_done    int := 0;
  v_failed  int := 0;
  v_debits  int;
  v_credits int;
  v_rows    int;
  v_bad     int;
  v_purse   bigint;
  v_sum     bigint;
  v_bites   boolean := false;
  r         record;
begin
  select array_agg(code order by code) into v_ports from public.ports;
  select array_agg(code order by code) into v_goods from public.goods;

  for i in 1 .. 3 loop
    v_players := v_players || public.new_house(c_auth[i], c_names[i], 'PRT');
    v_fleets  := v_fleets  || (select id from public.fleets where player_id = v_players[i]);
  end loop;

  -- ── the soak
  for k in 1 .. 500 loop
    h := 1 + floor(random() * 3)::int;
    perform cmd.assume_identity(c_auth[h]);
    v_roll := random();
    v_cmd := case
      when v_roll < 0.30 then format('BUY %s %s',   v_goods[1 + floor(random() * array_length(v_goods, 1))::int],
                                                    (1 + floor(random() * 90))::int)
      when v_roll < 0.52 then format('SELL %s %s',  v_goods[1 + floor(random() * array_length(v_goods, 1))::int],
                                                    case when random() < 0.5 then 'ALL' else 'HALF' end)
      when v_roll < 0.78 then format('SAIL TO %s',  v_ports[1 + floor(random() * array_length(v_ports, 1))::int])
      when v_roll < 0.86 then 'PROVISION FULL'
      when v_roll < 0.93 then format('HIRE %s', (1 + floor(random() * 12))::int)
      when v_roll < 0.97 then 'REPAIR'
      else                    'CLEAR'
    end;

    r := null;
    begin
      if (cmd.issue(v_fleets[h], v_cmd)->>'ok')::boolean then
        v_done := v_done + 1;
      else
        v_failed := v_failed + 1;
      end if;
    exception when others then
      -- An RPC that THREW rather than returning an envelope is itself a defect: cmd.issue owns the
      -- refusal contract. Fail loudly rather than counting it as a refusal.
      raise exception 'PROOF 2 FAILED: cmd.issue("%") threw instead of returning a refusal: %', v_cmd, sqlerrm;
    end;
    v_issued := v_issued + 1;

    -- Every 20 orders, jump time forward under the fleets: voyages complete, queues run on,
    -- markets drift and regenerate. This is where the interesting money movement happens.
    if k % 20 = 0 then
      update public.voyages set departed_at = departed_at - interval '40 minutes',
                                eta = eta - interval '40 minutes'
       where status = 'SAILING';
      update public.fleets set busy_until = busy_until - interval '40 minutes' where busy_until is not null;
      update public.port_goods set drift_slot = drift_slot - 1, last_regen_day = last_regen_day - 1;
      perform public.tick_arrivals();
      perform public.tick_market_drift();
    end if;
  end loop;

  -- one last catch-up so nothing is left mid-flight
  update public.voyages set departed_at = departed_at - interval '6 hours', eta = eta - interval '6 hours'
   where status = 'SAILING';
  update public.fleets set busy_until = busy_until - interval '6 hours' where busy_until is not null;
  perform public.tick_arrivals();

  if v_issued <> 500 then
    raise exception 'PROOF 2 FAILED: % orders were issued, not 500', v_issued;
  end if;
  raise notice 'PASS: LEDGER_SOAK_ORDERS_ISSUED — % randomised orders across 3 houses', v_issued;

  if v_done = 0 or v_failed = 0 then
    raise exception 'PROOF 2 FAILED: the soak had % successes and % refusals; both must be non-zero or the invariant held over nothing',
      v_done, v_failed;
  end if;
  raise notice 'PASS: LEDGER_SOAK_MIXED_OUTCOMES — % succeeded, % were refused', v_done, v_failed;

  select count(*) filter (where ducats_delta < 0), count(*) filter (where ducats_delta > 0), count(*)
    into v_debits, v_credits, v_rows from public.ledger;
  if v_debits < 20 or v_credits < 5 or v_rows < 50 then
    raise exception 'PROOF 2 FAILED: only % debit(s) and % credit(s) over % ledger row(s) — too little money moved to be a soak',
      v_debits, v_credits, v_rows;
  end if;
  raise notice 'PASS: LEDGER_SOAK_MONEY_MOVED — % ledger rows: % debits, % credits', v_rows, v_debits, v_credits;

  -- ── THE INVARIANT
  v_bad := 0;
  for i in 1 .. 3 loop
    select ducats into v_purse from public.players where id = v_players[i];
    v_sum := public.ledger_sum(v_players[i]);
    if v_purse <> v_sum then
      v_bad := v_bad + 1;
      raise warning 'house % : purse % vs ledger sum % (difference %)', c_names[i], v_purse, v_sum, v_purse - v_sum;
    end if;
  end loop;
  if v_bad <> 0 then
    raise exception 'PROOF 2 FAILED: % of 3 houses do not reconcile', v_bad;
  end if;
  perform public.tick_reconcile();
  raise notice 'PASS: LEDGER_SOAK_RECONCILES — all 3 houses: purse = Σ ledger.ducats_delta exactly (purses %, %, %)',
    (select ducats from public.players where id = v_players[1]),
    (select ducats from public.players where id = v_players[2]),
    (select ducats from public.players where id = v_players[3]);

  perform voyage.assert_sailing_invariant();
  raise notice 'PASS: LEDGER_SOAK_SAILING_INVARIANT — % fleet(s) and % SAILING voyage(s) agree',
    (select count(*) from public.fleets), (select count(*) from public.voyages where status = 'SAILING');

  -- ── POSITIVE CONTROL: the reconciler must be able to fail. One ducat, no ledger row.
  update public.players set ducats = ducats + 1 where id = v_players[1];
  begin
    perform public.tick_reconcile();
  exception when others then
    if sqlerrm ~ 'LEDGER RECONCILIATION FAILED' then v_bites := true; end if;
  end;
  if not v_bites then
    raise exception 'PROOF 2 FAILED: a purse inflated by ONE ducat with no ledger row behind it was ACCEPTED. Everything above proves nothing.';
  end if;
  raise notice 'PASS: LEDGER_SOAK_CHECK_BITES — a single unbacked ducat was caught, so the reconciliation above is a real check';
end $$;
