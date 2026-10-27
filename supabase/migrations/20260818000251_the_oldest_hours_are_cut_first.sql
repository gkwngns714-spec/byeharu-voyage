-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0251 — THE OLDEST HOURS ARE CUT FIRST  (the hourly compactor works through its backlog six hours at a
--        time, every house per slice, instead of one house's whole backlog at a time)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, 2026-10-27 14:07 UTC, the first run under 0249) ─────────────────
-- The run succeeded (75.4 s; before it, 11 of the last 14 runs had hit the 120 s timeout) and wrote its
-- receipt (public.reconcile_runs): tend 33.1 s, companies 4.3 s, compact 34.5 s, check 3.3 s. But the
-- compactor finished only 12 of 821 houses in its 30 s (3,141 ledger rows, 3,349 events, 589 voyages,
-- 818 trade_daily rows, 200 orders; 809 left) — about 2.9 s a house. Those were rows from 10-25 and 10-26,
-- long out of the cache (shared_buffers 320 MB; events alone are 512 MB). One house's rows of a day and a
-- half lie one to a page across the whole span, so a house read a page per row from disk. At that rate the
-- backlog would take days, and the beats waited on those slow steps (14:07-14:08 beats avg 1.2-1.5 s,
-- max 8.7 s, against 0.5 s just before).
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- tick_reconcile's compact step (one hunk, plus its declarations and two receipt keys) walks the backlog by
-- TIME: a slice is "compact every house as of instant T" (public.npc_compact_house(house, T), the same rules,
-- the same function), with T six hours past the last slice finished and never past now. All the houses of
-- one slice read the same few hours of rows, which sit together on disk and stay in the cache, so a house
-- step is milliseconds. A slice finished is recorded in the run's receipt (`upto`, public.reconcile_runs); a
-- slice the 30 s budget cut short is done again next hour (the houses it reached have nothing left in it).
-- An empty stretch is jumped: the next slice is six hours past the later of the last slice finished and the
-- oldest merchant ledger row still awaiting a roll beyond it.
-- Compacting as of T and then as of a later T' leaves exactly what compacting once as of T' leaves: the
-- carried row's sum, last instant and balance are each computed from the rows, and every delete is "older
-- than the cut" (asserted below on a probe house). Nothing else moves: no rule, no knob, no other step, the
-- quay lock, public.tick_arrivals.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the three hunks below (each OLD text is here verbatim).
--
-- VERSION: 0251 (prod head 0250). Hunks cut from the LIVE body on prod at head 0249 (0250 does not touch it), LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_compact_house(uuid,timestamptz)') is null or to_regclass('public.reconcile_runs') is null then
    raise exception '0251 refuses: 0249 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0251(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0251 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_reconcile(boolean)')) f(fn);

create temp table before_0251 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p where p.oid in ('public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                         'public.npc_compact(timestamptz)'::regprocedure,
                                         'public.tick_arrivals(timestamptz)'::regprocedure,
                                         'public.tick_arrivals_each_second(int)'::regprocedure)) as others_md5;

create temp table hunks_0251 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0251 (fn, n, old, new) values
('public.tick_reconcile(boolean)', 1,
$h$  v_ctd      int := 0;
begin
$h$,
$h$  v_ctd      int := 0;
  -- 0251: the compactor's slices — compact every house as of v_slice, six hours past the last slice finished
  v_keep     interval;
  v_upto     timestamptz;          -- the last slice finished (from the last receipt that says)
  v_slice    timestamptz;
  v_slices   int := 0;
begin
$h$),
('public.tick_reconcile(boolean)', 2,
$h$  if v_on then
    for h in select p.id from public.players p where p.is_npc
              order by (select min(l.created_at) from public.ledger l where l.player_id = p.id) nulls first, p.id loop
      if clock_timestamp() >= v_cby then
        v_cleft := v_cleft + 1;
        continue;
      end if;
      if p_commit then perform public.hold_the_quay(); end if;
      perform public.npc_upkeep_scope(v_deadline);
      begin
        v_ch := public.npc_compact_house(h.id, v_now);
        v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
        v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
        v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
        v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
        v_cdone := v_cdone + 1;
      exception when others then
        v_cfail := v_cfail + 1;
        v_cnote := coalesce(v_cnote, 'house ' || h.id || ': ' || sqlerrm);
      end;
      if p_commit then commit; end if;
    end loop;
  end if;
$h$,
$h$  if v_on then
    -- 0251: THE OLDEST HOURS FIRST, SIX AT A TIME. A slice compacts every house as of v_slice (the same
    -- rules: public.npc_compact_house). Its houses all read the same few hours of rows, which lie together
    -- and stay in the cache; one house's whole backlog lay a row to a page across days (0249's first run:
    -- 12 houses in 30 s). A slice finished is kept in the receipt (`upto`); one the budget cut short is
    -- done again next hour. Compacting as of T, then as of a later T', leaves what compacting as of T'
    -- leaves (0251's self-assert).
    v_keep := make_interval(hours => public.wc_int('npc_retention_hours'));
    v_upto := (select (rr.receipt->'merchant_upkeep'->'compact'->>'upto')::timestamptz
                 from public.reconcile_runs rr
                where rr.at < v_now and rr.receipt->'merchant_upkeep'->'compact' ? 'upto'
                order by rr.at desc limit 1);
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
      for h in select p.id from public.players p where p.is_npc
                order by (select min(l.created_at) from public.ledger l
                           where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id loop
        if clock_timestamp() >= v_cby then
          v_cleft := v_cleft + 1;
          continue;
        end if;
        if p_commit then perform public.hold_the_quay(); end if;
        perform public.npc_upkeep_scope(v_deadline);
        begin
          v_ch := public.npc_compact_house(h.id, v_slice);
          v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
          v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
          v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
          v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
          v_cdone := v_cdone + 1;
        exception when others then
          v_cfail := v_cfail + 1;
          v_cnote := coalesce(v_cnote, 'house ' || h.id || ': ' || sqlerrm);
        end;
        if p_commit then commit; end if;
      end loop;
      exit when v_cleft > 0;   -- the budget ran out inside this slice: it is done again next hour
      v_upto := v_slice;
      v_slices := v_slices + 1;
      exit when v_slice >= v_now or clock_timestamp() >= v_cby;
    end loop;
  end if;
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    'orders', coalesce((v_cx->>'orders')::int, 0),
$h$,
$h$    'orders', coalesce((v_cx->>'orders')::int, 0),
    'slices', v_slices, 'upto', v_upto,   -- 0251: slices finished this run; the last instant every house is compacted as of
$h$);

create or replace function pg_temp.recut_0251(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0251 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0251 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0251(v_def, h.old);
    if v_n <> 1 then
      raise exception '0251 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0251(fn) from defs_before_0251 order by fn;

-- ── THE PROBE: compacting in two slices leaves what compacting once leaves ──────────────────────
-- One merchant house with rows from before a 2026-08-01 cut (earlier than every real row, so the probe's rows
-- are the only ones touched), compacted from the same rolled-back state (a) once as of c_now, (b) as of c_mid
-- (a cut that splits her old rows) and then as of c_now, (c) by public.npc_compact as of c_now.
create or replace function pg_temp.digest_0251(p_house uuid)
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
    'voyages_n', (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyage_events_n', (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                          join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'trade_daily', (select md5(coalesce(string_agg(concat_ws('|', td.port_id, td.good_id, td.game_day, td.qty), ',' order by td.game_day), ''))
                      from public.trade_daily td where td.player_id = p_house),
    'purse', (select p.ducats from public.players p where p.id = p_house),
    'ledger_sum', public.ledger_sum(p_house))
$$;

create or replace function pg_temp.run_0251(p_how text, p_house uuid, p_mid timestamptz, p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_a jsonb; v_b jsonb;
begin
  begin
    if p_how = 'once' then
      v_a := public.npc_compact_house(p_house, p_now);
    elsif p_how = 'sliced' then
      v_a := public.npc_compact_house(p_house, p_mid);
      v_b := public.npc_compact_house(p_house, p_now);
    else
      v_a := public.npc_compact(p_now);
    end if;
    raise exception using errcode = 'ZY251',
      message = jsonb_build_object('a', v_a, 'b', v_b, 'd', pg_temp.digest_0251(p_house))::text;
  exception when sqlstate 'ZY251' then
    return sqlerrm::jsonb;
  end;
end $$;

do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  c_now   constant timestamptz := '2026-08-01 00:00:00+00';
  c_old   constant timestamptz := '2026-07-31 12:00:00+00';   -- before the cut (2026-07-31 18:00)
  c_mid   constant timestamptz := '2026-07-31 16:30:00+00';   -- its cut, 10:30, splits her old rows
  v_res   jsonb;
begin
  select * into v_before from before_0251;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0251 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0251 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0251(v_def, v_h.new) <> 1 then
        raise exception '0251 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0251 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0251 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid in ('public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                       'public.npc_compact(timestamptz)'::regprocedure,
                                       'public.tick_arrivals(timestamptz)'::regprocedure,
                                       'public.tick_arrivals_each_second(int)'::regprocedure)) <> v_before.others_md5 then
    raise exception '0251 self-assert FAIL: the compactor''s rules, the beat or the arrivals run moved';
  end if;
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0251(v_def, 'public.npc_compact_house(h.id, v_slice)') <> 1
     or pg_temp.occurs_0251(v_def, 'public.npc_compact_house(') <> 1
     or pg_temp.occurs_0251(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 4 then
    raise exception '0251 self-assert FAIL: tick_reconcile does not compact by slice, once, after the quay lock';
  end if;

  -- (b) TWO SLICES LEAVE WHAT ONE LEAVES (rolled back whole)
  begin
    declare
      v_m    uuid;
      v_f    uuid;
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); e3 uuid := gen_random_uuid(); e4 uuid := gen_random_uuid();
      v1 uuid := gen_random_uuid(); v0 uuid := gen_random_uuid();
      v_once jsonb; v_sliced jsonb; v_all jsonb; v_pre jsonb;
    begin
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0251 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_m := public.new_house(null, 'Casa das Fatias 0251', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
      if v_f is null then
        insert into public.fleets (player_id, name, port_id) values (v_m, 'Fatias 0251', v_port) returning id into v_f;
      end if;
      -- E1 before the mid cut, E2 after it (both go), E3 named by a kept ledger row (stays), E4 FOUNDED (stays)
      insert into public.events (id, player_id, kind, payload, created_at) values
        (e1, v_m, 'PROBE_0251', '{}', c_old - interval '3 hours'), (e2, v_m, 'PROBE_0251', '{}', c_old),
        (e3, v_m, 'PROBE_0251', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day');
      -- four old rows summing to 0: two before the mid cut (the first slice rolls them), two after it
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
        (v_m, 'PROBE_0251', 100, 1100, null, c_old - interval '3 hours'),
        (v_m, 'PROBE_0251', 300, 1400, null, c_old - interval '2 hours'),
        (v_m, 'PROBE_0251', -350, 1050, null, c_old - interval '1 hour'),
        (v_m, 'PROBE_0251', -50, 1000, e2, c_old),
        (v_m, 'PROBE_0251', 0, 1000, e3, c_now);
      -- V0 ended before the mid cut, V1 after it: both go
      insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                  origin_port_id, dest_port_id, created_at) values
        (v0, v_f, v_m, '[]', 100, '{}', c_old - interval '1 day', c_old - interval '3 hours', 'ARRIVED', v_port, v_port2, c_old - interval '1 day'),
        (v1, v_f, v_m, '[]', 100, '{}', c_old - interval '2 hours', c_old, 'ARRIVED', v_port2, v_port, c_old - interval '2 hours');
      insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
      select v.id, 1, k.code, '{}', c_old
        from (values (v0), (v1)) v(id), (select code from public.voyage_event_kinds order by code limit 1) k;
      insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values
        (v_m, v_port, v_good, v_gd - 2, 3), (v_m, v_port, v_good, v_gd - 1, 5), (v_m, v_port, v_good, v_gd, 7);
      v_pre := pg_temp.digest_0251(v_m);

      v_once   := pg_temp.run_0251('once', v_m, c_mid, c_now);
      v_sliced := pg_temp.run_0251('sliced', v_m, c_mid, c_now);
      v_all    := pg_temp.run_0251('all', v_m, c_mid, c_now);

      if (v_sliced->'a'->>'ledger_rolled')::int < 2 then
        raise exception '0251 self-assert FAIL: the first slice rolled no rows (%) — the split proved nothing', v_sliced;
      end if;
      if v_once->'d' is distinct from v_sliced->'d' or v_once->'d' is distinct from v_all->'d' then
        raise exception '0251 self-assert FAIL: two slices left other rows than one (once %, sliced %, whole world %)', v_once, v_sliced, v_all;
      end if;
      if (v_once->'d'->>'carried')::int <> 1 or (v_once->'d'->>'events_n')::int <> (v_pre->>'events_n')::int - 2
         or (v_once->'d'->>'voyages_n')::int <> (v_pre->>'voyages_n')::int - 2
         or (v_once->'d'->>'voyage_events_n')::int <> (v_pre->>'voyage_events_n')::int - 2
         or (v_once->'d'->>'ledger_n')::int <> (v_pre->>'ledger_n')::int - 3
         or (v_once->'d'->>'purse')::bigint <> (v_pre->>'purse')::bigint
         or (v_once->'d'->>'ledger_sum')::bigint <> (v_pre->>'purse')::bigint then
        raise exception '0251 self-assert FAIL: the probe did not compact as the rules say (before %, after %)', v_pre, v_once;
      end if;
      v_res := jsonb_build_object('first_slice', v_sliced->'a', 'second_slice', v_sliced->'b', 'once', v_once->'a');
      raise exception using errcode = 'ZY25B', message = v_res::text;
    end;
  exception when sqlstate 'ZY25B' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name = 'Casa das Fatias 0251') then
    raise exception '0251 self-assert FAIL: the probe house was left behind';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0251 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0251 self-assert FAIL: a wall moved';
  end if;

  raise notice '0251 self-assert ok: THE OLDEST HOURS ARE CUT FIRST. tick_reconcile compacts every house as of a slice six hours past the last one finished (3 hunks, reverse to the pre-image, ACL / volatility / definer / config unmoved); npc_compact_house, npc_compact, the beat and tick_arrivals unmoved; registry unchanged; walls 0. PROBE (one merchant house, rolled back): compacting as of 10:30 then 18:00 left byte-identical rows to compacting once as of 18:00, and to npc_compact: %. Nothing left behind.',
    v_res;
end $$;
