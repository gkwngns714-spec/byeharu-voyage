-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0259 — THE OLDEST HOURS ARE CUT FIRST, A FEW HOUSES AT A TIME  (0253's six-hour slices come back; 0258's
--        clock-sized transactions stay inside them)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, 2026-10-27 21:07, the first hourly run under 0258) ───────────────
-- 0258 compacted every house at the normal cut. A house's FIRST roll is then her whole backlog (~900 ledger
-- rows, ~1,100 events, ~200 voyages and their rows over two days), and those rows lie one to a page, cold:
-- ONE house took 3.2 s inside the quay lock (batch_ms_max 3,188; ms_house 3,188), so every transaction was
-- one house and 6 houses were done in the 30 s (5,463 ledger rows, 6,550 events, 1,231 voyages). 0257, with
-- 6-hour slices, rolled ~25-30 k ledger rows a run. At 0258's pace the backlog GROWS (~15-20 k ledger rows
-- cross the cut each hour). What 0258 did right, kept: no transaction started past the budget (compact
-- 29.9 s), and the beats waited less (p95 5.1 s / max 6.9 s during the run; 0257's 20:07 run: 13.3 s / 21.1 s).
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- tick_reconcile's compact step (3 hunks): 0253's slices again (every house compacted as of v_slice, six
-- hours past the last slice finished, oldest first; `slices` / `upto` back in the receipt), and inside each
-- slice 0258's clock unchanged: each transaction timed inside the quay lock, the next sized to the 1.5 s
-- hold by the measured rate (1 to 25 houses), none started unless it ends inside the 30 s budget, a failed
-- batch redone one house a transaction. A slice's rows lie together, so its batches share their pages.
-- public.npc_compact_houses (THE rules, with 0258's set-based voyages) is unchanged: md5-asserted.
-- Compacting as of T and then a later T' leaves what compacting once as of T' leaves: asserted below on a
-- rolled-back probe, four ways (once, in two slices, the house step, npc_compact). (Dev-log
-- 2026-10-27-reconcile-timeout.md, "0259".)
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the three hunks below (each OLD text is here verbatim).
--
-- VERSION: 0259 (prod head 0258 when cut). Hunks cut from the LIVE body on prod at head 0258, LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_compact_houses(uuid[],timestamptz)') is null or to_regclass('public.reconcile_runs') is null
     or to_regprocedure('public.hold_the_quay()') is null
     or position('v_hold     constant numeric := 1500' in pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure)) = 0 then
    raise exception '0259 refuses: 0258 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0259(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0259 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_reconcile(boolean)')) f(fn);

create temp table before_0259 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                         'public.npc_compact_houses(uuid[],timestamptz)'::regprocedure,
                                         'public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                         'public.npc_compact_orders(timestamptz)'::regprocedure,
                                         'public.ledger_sum(uuid)'::regprocedure,
                                         'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                         'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                         'public.hold_the_quay()'::regprocedure,
                                         'public.npc_upkeep_scope(timestamptz)'::regprocedure,
                                         'public.tick_arrivals(timestamptz)'::regprocedure,
                                         'public.tick_arrivals_each_second(int)'::regprocedure)) as others_md5;

-- ── THE HUNKS ───────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0259 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0259 (fn, n, old, new) values
('public.tick_reconcile(boolean)', 1,
$h$  -- 0258: the compactor at the normal cut, a few houses a transaction, sized by the clock
$h$,
$h$  -- 0253 / 0259: the compactor's slices — compact every house as of v_slice, six hours past the last slice finished
  v_keep     interval;
  v_upto     timestamptz;          -- the last slice finished (from the last receipt that says)
  v_slice    timestamptz;
  v_slices   int := 0;
  -- 0258: a few houses a transaction, sized by the clock (0259: inside each slice)
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    -- 0258: AT THE NORMAL CUT, A FEW HOUSES A TRANSACTION, SIZED BY THE CLOCK. Every house is compacted as
    -- of now (public.npc_compact_houses: its cut is now − npc_retention_hours, the cut npc_compact always
    -- used), so she is rolled once for good and her checks sum her recent rows only (0257's 6-hour slices
    -- kept ~1,100 cold rows a house in every check). The house with the oldest row awaiting a roll first
    -- (her NPC_CARRIED row skipped: two index entries), so the houses the budget leaves are first next hour.
    -- Each transaction is timed inside the quay lock; the next one takes as many houses as the measured
    -- rate fits in v_hold (1 to v_bmax; the run's first is one house), and it STARTS only if, at that rate,
    -- it ends inside the 30 s budget. A batch that fails is rolled back whole and its houses are then done
    -- one a transaction, under the same check, so a bad house holds back only herself.
    v_order := array(select p.id from public.players p where p.is_npc
                      order by (select min(l.created_at) from public.ledger l
                                 where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id);
    v_rate := v_hold;   -- no measurement yet: a house is assumed to take the whole hold
    loop
      v_single := v_r <= cardinality(v_retry);
      exit when not v_single and v_i > coalesce(cardinality(v_order), 0);
      if v_single then
        v_bsize := 1;
      else
        v_bsize := greatest(1, least(v_bmax, floor(v_hold / v_rate)::int,
                                     floor(extract(epoch from v_cby - clock_timestamp()) * 1000 / v_rate)::int));
      end if;
      if clock_timestamp() + make_interval(secs => (v_bsize * v_rate / 1000)::double precision) > v_cby then
        v_cleft := greatest(coalesce(cardinality(v_order), 0) - v_i + 1, 0) + cardinality(v_retry) - v_r + 1;
        exit;
      end if;
      if v_single then
        v_batch := array[v_retry[v_r]];
        v_r := v_r + 1;
      else
        v_batch := v_order[v_i : v_i + v_bsize - 1];
        v_i := v_i + v_bsize;
      end if;
      v_bfail := null;
      if p_commit then perform public.hold_the_quay(); end if;
      v_tb := clock_timestamp();
      perform public.npc_upkeep_scope(v_deadline);
      begin
        v_ch := public.npc_compact_houses(v_batch, v_now);
        v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
        v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
        v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
        v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
        v_cdone := v_cdone + cardinality(v_batch);
        if not v_single then v_batches := v_batches + 1; end if;
      exception when others then
        if v_single then
          v_cfail := v_cfail + 1;
          v_cnote := coalesce(v_cnote, 'house ' || v_batch[1] || ': ' || sqlerrm);
        else
          v_bfail := sqlerrm;
        end if;
      end;
      if p_commit then commit; end if;
      -- the rate: ms a house this transaction held the quay (its commit included), and the run's mean
      v_bms := extract(epoch from clock_timestamp() - v_tb) * 1000;
      v_held := v_held + v_bms;
      v_heldh := v_heldh + cardinality(v_batch);
      v_rate := greatest(v_bms / cardinality(v_batch), v_held / v_heldh, 1);
      v_bmsmax := greatest(v_bmsmax, v_bms);
      v_bhmax := greatest(v_bhmax, cardinality(v_batch));
      if v_bfail is not null then
        v_cnote := coalesce(v_cnote, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
        v_retry := v_batch;
        v_r := 1;
      end if;
    end loop;
$h$,
$h$    -- 0259: THE OLDEST HOURS FIRST AGAIN (0253's slices), A FEW HOUSES A TRANSACTION (0258). Measured on prod
    -- 10-27 21:07 under 0258's normal cut: one house's WHOLE backlog took 3.2-5 s alone (her rows lie one to a
    -- page across two days), so 6 houses were done in 30 s (5,463 ledger rows; 0257 rolled ~25 k a run). A slice
    -- compacts every house as of v_slice (public.npc_compact_houses: the same rules); the slice's rows lie
    -- together, so its batches share their pages. A slice finished is kept in the receipt (`upto`); one the
    -- budget cut short is done again next hour. Compacting as of T, then a later T', leaves what compacting as
    -- of T' leaves (0253's self-assert; 0259's). Inside a slice, 0258's clock: each transaction timed inside the
    -- quay lock, the next sized to v_hold by the measured rate (1 to v_bmax), none started unless it ends inside
    -- the 30 s budget, a failed batch redone one house a transaction.
    v_keep := make_interval(hours => public.wc_int('npc_retention_hours'));
    v_upto := (select (rr.receipt->'merchant_upkeep'->'compact'->>'upto')::timestamptz
                 from public.reconcile_runs rr
                where rr.at < v_now and rr.receipt->'merchant_upkeep'->'compact' ? 'upto'
                order by rr.at desc limit 1);
    v_rate := v_hold;   -- no measurement yet: a house is assumed to take the whole hold
    loop
      -- the next slice: six hours past the last one finished, or past the oldest merchant ledger row still
      -- awaiting a roll beyond it, whichever is later (an empty stretch is jumped, not walked); never past now
      v_slice := least(v_now, greatest(coalesce(v_upto, '-infinity'::timestamptz),
                                       coalesce((select min(l.created_at) from public.ledger l
                                                   join public.players p on p.id = l.player_id and p.is_npc
                                                  where l.kind <> 'NPC_CARRIED'
                                                    and l.created_at >= coalesce(v_upto - v_keep, '-infinity'::timestamptz)) + v_keep,
                                                v_now))
                                + interval '6 hours');
      v_cleft := 0;
      -- the house with the oldest row awaiting a roll first (her NPC_CARRIED row skipped: two index entries),
      -- so a slice the budget cuts short is never short of the same houses twice
      v_order := array(select p.id from public.players p where p.is_npc
                        order by (select min(l.created_at) from public.ledger l
                                   where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id);
      v_i := 1;
      v_retry := '{}';
      v_r := 1;
      loop
        v_single := v_r <= cardinality(v_retry);
        exit when not v_single and v_i > coalesce(cardinality(v_order), 0);
        if v_single then
          v_bsize := 1;
        else
          v_bsize := greatest(1, least(v_bmax, floor(v_hold / v_rate)::int,
                                       floor(extract(epoch from v_cby - clock_timestamp()) * 1000 / v_rate)::int));
        end if;
        if clock_timestamp() + make_interval(secs => (v_bsize * v_rate / 1000)::double precision) > v_cby then
          v_cleft := greatest(coalesce(cardinality(v_order), 0) - v_i + 1, 0) + cardinality(v_retry) - v_r + 1;
          exit;
        end if;
        if v_single then
          v_batch := array[v_retry[v_r]];
          v_r := v_r + 1;
        else
          v_batch := v_order[v_i : v_i + v_bsize - 1];
          v_i := v_i + v_bsize;
        end if;
        v_bfail := null;
        if p_commit then perform public.hold_the_quay(); end if;
        v_tb := clock_timestamp();
        perform public.npc_upkeep_scope(v_deadline);
        begin
          v_ch := public.npc_compact_houses(v_batch, v_slice);
          v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
          v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
          v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
          v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
          v_cdone := v_cdone + cardinality(v_batch);
          if not v_single then v_batches := v_batches + 1; end if;
        exception when others then
          if v_single then
            v_cfail := v_cfail + 1;
            v_cnote := coalesce(v_cnote, 'house ' || v_batch[1] || ': ' || sqlerrm);
          else
            v_bfail := sqlerrm;
          end if;
        end;
        if p_commit then commit; end if;
        -- the rate: ms a house this transaction held the quay (its commit included), and the run's mean
        v_bms := extract(epoch from clock_timestamp() - v_tb) * 1000;
        v_held := v_held + v_bms;
        v_heldh := v_heldh + cardinality(v_batch);
        v_rate := greatest(v_bms / cardinality(v_batch), v_held / v_heldh, 1);
        v_bmsmax := greatest(v_bmsmax, v_bms);
        v_bhmax := greatest(v_bhmax, cardinality(v_batch));
        if v_bfail is not null then
          v_cnote := coalesce(v_cnote, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
          v_retry := v_batch;
          v_r := 1;
        end if;
      end loop;
      exit when v_cleft > 0;   -- the budget ran out inside this slice: it is done again next hour
      v_upto := v_slice;
      v_slices := v_slices + 1;
      exit when v_slice >= v_now or clock_timestamp() >= v_cby;
    end loop;
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    'batches', v_batches,                 -- 0257: batch transactions that committed (0258: sized by the clock)
$h$,
$h$    'slices', v_slices, 'upto', v_upto,   -- 0253 / 0259: slices finished this run; the last instant every house is compacted as of
    'batches', v_batches,                 -- 0257: batch transactions that committed (0258: sized by the clock)
$h$);

create or replace function pg_temp.recut_0259(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0259 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0259 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0259(v_def, h.old);
    if v_n <> 1 then
      raise exception '0259 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0259(fn) from defs_before_0259 order by fn;

-- ── THE PROBE: two slices leave what one cut leaves ─────────────────────────────────────────────
-- 0258's four houses (rows before a 2026-08-01 cut, earlier than every real row on prod, so only the probe's
-- rows are touched): A and C merchants with rows to roll, B a merchant with ONE old ledger row, P a PLAYER
-- (never touched); three voyages each with voyage_events and insurance, one old one kept by an open lap.
-- Compacted from the same rolled-back state four ways: (twice) public.npc_compact_houses as of an instant
-- whose cut falls between the old rows, then as of now; (batch) once as of now; (one) public.npc_compact_house
-- house by house; (all) public.npc_compact. All four must leave byte-identical rows.
create or replace function pg_temp.digest_0259(p_house uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'ledger', (select md5(coalesce(string_agg(concat_ws('|', l.kind, l.ducats_delta, l.balance_after, l.ref_event_id, l.created_at),
                                              ',' order by l.created_at, l.kind, l.ducats_delta, l.ref_event_id), ''))
                 from public.ledger l where l.player_id = p_house),
    'ledger_n', (select count(*) from public.ledger l where l.player_id = p_house),
    'carried', (select count(*) from public.ledger l where l.player_id = p_house and l.kind = 'NPC_CARRIED'),
    'events', (select md5(coalesce(string_agg(ev.id::text, ',' order by ev.id), '')) from public.events ev where ev.player_id = p_house),
    'events_n', (select count(*) from public.events ev where ev.player_id = p_house),
    'voyages', (select md5(coalesce(string_agg(v.id::text, ',' order by v.id), '')) from public.voyages v
                  join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyages_n', (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyage_events', (select md5(coalesce(string_agg(concat_ws('|', ve.voyage_id, ve.day_index, ve.kind), ',' order by ve.voyage_id, ve.day_index), ''))
                        from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                        join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyage_events_n', (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                          join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'insured', (select md5(coalesce(string_agg(concat_ws('|', iv.voyage_id, iv.value, iv.written_at), ',' order by iv.voyage_id), ''))
                  from public.insured_voyages iv where iv.player_id = p_house),
    'insured_n', (select count(*) from public.insured_voyages iv where iv.player_id = p_house),
    'trade_daily', (select md5(coalesce(string_agg(concat_ws('|', td.port_id, td.good_id, td.game_day, td.qty), ',' order by td.game_day), ''))
                      from public.trade_daily td where td.player_id = p_house),
    'purse', (select p.ducats from public.players p where p.id = p_house),
    'ledger_sum', public.ledger_sum(p_house))
$$;

create or replace function pg_temp.run_0259(p_how text, p_houses uuid[], p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_a jsonb := '{}'::jsonb;
  v_r jsonb;
  v_d jsonb := '{}'::jsonb;
  h   uuid;
  k   text;
begin
  begin
    if p_how = 'twice' then
      -- two slices: as of an earlier instant (its cut at 2026-07-31 10:30, between the probe's old rows), then p_now
      v_a := public.npc_compact_houses(p_houses, least(timestamptz '2026-07-31 10:30:00+00'
                                                        + make_interval(hours => public.wc_int('npc_retention_hours')),
                                                      p_now - interval '1 minute'));
      v_r := public.npc_compact_houses(p_houses, p_now);
      for k in select jsonb_object_keys(v_r) loop
        v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
      end loop;
    elsif p_how = 'batch' then
      v_a := public.npc_compact_houses(p_houses, p_now);
    elsif p_how = 'all' then
      v_a := public.npc_compact(p_now) - 'orders' - 'before';
    else
      foreach h in array (select array_agg(x order by x) from unnest(p_houses) x) loop
        v_r := public.npc_compact_house(h, p_now);
        for k in select jsonb_object_keys(v_r) loop
          v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
        end loop;
      end loop;
    end if;
    foreach h in array p_houses loop
      v_d := v_d || jsonb_build_object(h::text, pg_temp.digest_0259(h));
    end loop;
    raise exception using errcode = 'ZY259',
      message = jsonb_build_object('a', v_a, 'd', v_d)::text;
  exception when sqlstate 'ZY259' then
    return sqlerrm::jsonb;
  end;
end $$;

do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  c_now   constant timestamptz := '2026-08-01 00:00:00+00';
  c_old   constant timestamptz := '2026-07-31 12:00:00+00';   -- before the cut (2026-07-31 18:00)
  v_res   jsonb;
begin
  select * into v_before from before_0259;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0259 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0259 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0259(v_def, v_h.new) <> 1 then
        raise exception '0259 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0259 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0259 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                       'public.npc_compact_houses(uuid[],timestamptz)'::regprocedure,
                                       'public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                       'public.npc_compact_orders(timestamptz)'::regprocedure,
                                       'public.ledger_sum(uuid)'::regprocedure,
                                       'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                       'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                       'public.hold_the_quay()'::regprocedure,
                                       'public.npc_upkeep_scope(timestamptz)'::regprocedure,
                                       'public.tick_arrivals(timestamptz)'::regprocedure,
                                       'public.tick_arrivals_each_second(int)'::regprocedure)) <> v_before.others_md5 then
    raise exception '0259 self-assert FAIL: the rules (npc_compact_houses), npc_compact, the house step, the orders step, the purse invariant, credit, the quay lock, the scope, the beat or the arrivals run moved';
  end if;
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0259(v_def, 'public.npc_compact_houses(v_batch, v_slice)') <> 1
     or pg_temp.occurs_0259(v_def, 'public.npc_compact_houses(') <> 1
     or pg_temp.occurs_0259(v_def, 'public.npc_compact_house(') <> 0
     or pg_temp.occurs_0259(v_def, 'v_hold     constant numeric := 1500') <> 1
     or pg_temp.occurs_0259(v_def, '''upto'', v_upto') <> 1
     or pg_temp.occurs_0259(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 4
     or pg_temp.occurs_0259(v_def, 'if p_commit then commit; end if;') <> 4 then
    raise exception '0259 self-assert FAIL: tick_reconcile does not compact by slice through the one clock-sized batch call, each transaction after the quay lock';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and p.oid <> 'public.tick_reconcile(boolean)'::regprocedure
         and p.oid <> 'public.tick_arrivals_each_second(int)'::regprocedure
         and pg_get_functiondef(p.oid) like '%hold_the_quay()%'
         and p.oid <> 'public.hold_the_quay()'::regprocedure) <> 0 then
    raise exception '0259 self-assert FAIL: another function takes the quay lock';
  end if;
  if has_function_privilege('anon', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute') then
    raise exception '0259 self-assert FAIL: a client can run the batch compactor';
  end if;

  -- (b) TWO SLICES LEAVE WHAT ONE CUT LEAVES, AND SO DO THE HOUSE STEP AND npc_compact (rolled back whole)
  begin
    declare
      v_a    uuid; v_b uuid; v_c uuid; v_p uuid;
      v_all4 uuid[];
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      v_two jsonb; v_batch jsonb; v_one jsonb; v_all jsonb; v_pre jsonb := '{}'::jsonb;
      v_m   uuid; v_f uuid; v_k int;
      e1 uuid; e2 uuid; e3 uuid; e4 uuid; v0 uuid; v1 uuid; v2 uuid; v_sr uuid; v_lap uuid; v_lap0 uuid;
    begin
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0259 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_a := public.new_house(null, 'Casa dos Poucos A 0259', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_b := public.new_house(null, 'Casa dos Poucos B 0259', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_c := public.new_house(null, 'Casa dos Poucos C 0259', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_p := public.new_house(null, 'Casa dos Poucos P 0259', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => false);
      v_all4 := array[v_a, v_b, v_c, v_p];
      v_k := 0;
      foreach v_m in array v_all4 loop
        v_k := v_k + 1;
        v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
        if v_f is null then
          insert into public.fleets (player_id, name, port_id) values (v_m, 'Poucos 0259 ' || v_k, v_port) returning id into v_f;
        end if;
        e1 := gen_random_uuid(); e2 := gen_random_uuid(); e3 := gen_random_uuid(); e4 := gen_random_uuid();
        v0 := gen_random_uuid(); v1 := gen_random_uuid(); v2 := gen_random_uuid();
        -- E1, E2 old (both go), E3 named by a kept ledger row (stays), E4 FOUNDED (stays)
        insert into public.events (id, player_id, kind, payload, created_at) values
          (e1, v_m, 'PROBE_0259', '{}', c_old - interval '3 hours'), (e2, v_m, 'PROBE_0259', '{}', c_old),
          (e3, v_m, 'PROBE_0259', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day');
        if v_m = v_b then
          -- B: ONE old ledger row (summing to 0 with the purse kept): nothing to roll; E2 is not named by it
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0259', 0, 1000, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0259', 0, 1000, e3, c_now);
        else
          -- old rows summing to 0 (C's amounts differ from A's), one of them naming E2; E3 named by a new row
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0259', 100 * v_k, 1000 + 100 * v_k, null, c_old - interval '3 hours'),
            (v_m, 'PROBE_0259', 300, 1300 + 100 * v_k, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0259', -300 - 100 * v_k + 50, 1050, null, c_old - interval '1 hour'),
            (v_m, 'PROBE_0259', -50, 1000, e2, c_old),
            (v_m, 'PROBE_0259', 0, 1000, e3, c_now);
        end if;
        -- V0, V1 ended before the cut (V0 goes with its voyage_events and insurance; V1 too, but for a
        -- merchant's open lap below); V2 ended after it (stays)
        insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                    origin_port_id, dest_port_id, created_at) values
          (v0, v_f, v_m, '[]', 100, '{}', c_old - interval '1 day', c_old - interval '3 hours', 'ARRIVED', v_port, v_port2, c_old - interval '1 day'),
          (v1, v_f, v_m, '[]', 100, '{}', c_old - interval '2 hours', c_old, 'ARRIVED', v_port2, v_port, c_old - interval '2 hours'),
          (v2, v_f, v_m, '[]', 100, '{}', c_old, c_now, 'ARRIVED', v_port, v_port2, c_old);
        -- V1 is read by her route's OPEN lap (a done SAIL order of that lap names it): it stays, old as it is;
        -- V0 is named by a done SAIL order of a CLOSED lap: it goes
        if v_m <> v_p then
          v_sr := gen_random_uuid(); v_lap := gen_random_uuid(); v_lap0 := gen_random_uuid();
          insert into public.standing_routes (id, player_id, name, fleet_id) values (v_sr, v_m, 'Poucos 0259', null);
          insert into public.standing_route_laps (id, route_id, lap_no, started_at, closed_at) values
            (v_lap0, v_sr, 1, c_old - interval '1 day', c_old - interval '3 hours'),
            (v_lap, v_sr, 2, c_old - interval '2 hours', null);
          update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_sr;
          insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, result, route_lap_id) values
            (v_f, v_m, 900001, 'SAIL probe 0259', 'SAIL', 'done', jsonb_build_object('voyage_id', v0), v_lap0),
            (v_f, v_m, 900002, 'SAIL probe 0259', 'SAIL', 'done', jsonb_build_object('voyage_id', v1), v_lap),
            (v_f, v_m, 900003, 'SAIL probe 0259', 'SAIL', 'done', '{}'::jsonb, v_lap);
        end if;
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
        select v.id, d.i, k.code, '{}', c_old
          from (values (v0), (v1), (v2)) v(id), generate_series(1, 2) d(i),
               (select code from public.voyage_event_kinds order by code limit 1) k;
        insert into public.insured_voyages (voyage_id, fleet_id, player_id, port_id, cargo, basis, value, risk, price, keep_pct, written_at)
        select v.id, v_f, v_m, v_port, '{}', '{}', 100 + v_k, 0.1, 10, 0.1, v.w
          from (values (v0, c_old - interval '1 day'), (v1, c_old - interval '2 hours'), (v2, c_old)) v(id, w);
        insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values
          (v_m, v_port, v_good, v_gd - 2, 3), (v_m, v_port, v_good, v_gd - 1, 5), (v_m, v_port, v_good, v_gd, 7);
        v_pre := v_pre || jsonb_build_object(v_m::text, pg_temp.digest_0259(v_m));
      end loop;

      v_two   := pg_temp.run_0259('twice', v_all4, c_now);
      v_batch := pg_temp.run_0259('batch', v_all4, c_now);
      v_one   := pg_temp.run_0259('one',   v_all4, c_now);
      v_all   := pg_temp.run_0259('all',   v_all4, c_now);

      if v_two->'d' is distinct from v_batch->'d' or v_two->'d' is distinct from v_one->'d' or v_two->'d' is distinct from v_all->'d' then
        raise exception '0259 self-assert FAIL: two slices left other rows than one cut (two %, once %, house step %, whole world %)',
          v_two, v_batch, v_one, v_all;
      end if;
      if v_batch->'a' is distinct from v_one->'a' or v_batch->'a' is distinct from v_all->'a' then
        raise exception '0259 self-assert FAIL: the batch answered otherwise than the house step or npc_compact (once %, house step %, whole world %)',
          v_batch->'a', v_one->'a', v_all->'a';
      end if;
      -- two slices remove the same rows, and roll A's and C's ledger twice: 2 rows, then the carried row + 2 (5 each)
      if v_two->'a' <> jsonb_build_object('voyages', 3, 'ledger_rolled', 10, 'events', 6, 'trade_daily', 6) then
        raise exception '0259 self-assert FAIL: the two slices did not split as the rules say: %', v_two->'a';
      end if;
      -- what went is exactly what the rules say: A and C roll 4 rows into 1 and lose E1, E2, V0 (with its 2
      -- voyage_events and its insurance row), two trade days; B rolls nothing (one old row) and loses E1, E2,
      -- V0, two trade days; every merchant keeps V1 (her open lap reads it) and V2 and their rows; P is untouched
      if v_batch->'a' <> jsonb_build_object('voyages', 3, 'ledger_rolled', 8, 'events', 6, 'trade_daily', 6) then
        raise exception '0259 self-assert FAIL: the probe did not compact as the rules say: %', v_batch->'a';
      end if;
      if v_batch->'d'->v_p::text is distinct from v_pre->v_p::text then
        raise exception '0259 self-assert FAIL: a player''s rows were touched (before %, after %)', v_pre->v_p::text, v_batch->'d'->v_p::text;
      end if;
      foreach v_m in array array[v_a, v_b, v_c] loop
        if (v_batch->'d'->v_m::text->>'voyages_n')::int <> (v_pre->v_m::text->>'voyages_n')::int - 1
           or (v_batch->'d'->v_m::text->>'voyage_events_n')::int <> (v_pre->v_m::text->>'voyage_events_n')::int - 2
           or (v_batch->'d'->v_m::text->>'insured_n')::int <> (v_pre->v_m::text->>'insured_n')::int - 1
           or (v_batch->'d'->v_m::text->>'insured_n')::int < 2
           or (v_batch->'d'->v_m::text->>'events_n')::int <> (v_pre->v_m::text->>'events_n')::int - 2 then
          raise exception '0259 self-assert FAIL: house % did not lose exactly her one unread old voyage and its rows (before %, after %)',
            v_m, v_pre->v_m::text, v_batch->'d'->v_m::text;
        end if;
      end loop;
      foreach v_m in array array[v_a, v_c] loop
        if (v_batch->'d'->v_m::text->>'carried')::int <> 1
           or (v_batch->'d'->v_m::text->>'ledger_n')::int <> (v_pre->v_m::text->>'ledger_n')::int - 3
           or (v_batch->'d'->v_m::text->>'ledger_sum')::bigint <> (v_pre->v_m::text->>'purse')::bigint
           or (v_batch->'d'->v_m::text->>'purse')::bigint <> (v_pre->v_m::text->>'purse')::bigint then
          raise exception '0259 self-assert FAIL: house % did not roll as the rules say (before %, after %)',
            v_m, v_pre->v_m::text, v_batch->'d'->v_m::text;
        end if;
      end loop;
      if (v_batch->'d'->v_b::text->>'carried')::int <> 0
         or (v_batch->'d'->v_b::text->>'ledger')::text <> (v_pre->v_b::text->>'ledger')::text then
        raise exception '0259 self-assert FAIL: the one-row house did not compact as the rules say (before %, after %)',
          v_pre->v_b::text, v_batch->'d'->v_b::text;
      end if;
      v_res := jsonb_build_object('once', v_batch->'a', 'twice', v_two->'a', 'houses', 4);
      raise exception using errcode = 'ZY25G', message = v_res::text;
    end;
  exception when sqlstate 'ZY25G' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name like 'Casa dos Poucos % 0259') then
    raise exception '0259 self-assert FAIL: a probe house was left behind';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0259 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0259 self-assert FAIL: a wall moved';
  end if;

  raise notice '0259 self-assert ok: THE OLDEST HOURS ARE CUT FIRST, A FEW HOUSES AT A TIME. tick_reconcile compacts by six-hour slices again, oldest first, and inside each slice a few houses a transaction sized by the measured rate to a 1.5 s hold (1 to 25), none started unless it ends inside the 30 s budget (3 hunks); they reverse to the pre-image, ACL / volatility / definer / config unmoved; the rules (npc_compact_houses), npc_compact, the house step, the orders step, ledger_sum, assert_ledger_reconciles, credit, the quay lock, the scope, the beat and tick_arrivals unmoved; no other function takes the quay lock; registry unchanged; walls 0. PROBE (3 merchants + 1 player, rows before a 2026-08-01 cut, an open lap keeping one old voyage, rolled back): two slices, one cut, the house step and npc_compact left byte-identical rows; answers %. The player untouched. Nothing left behind.',
    v_res;
end $$;
