-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0257 — A HUNDRED HOUSES ARE CUT AT ONCE  (the hourly compactor rolls a batch of ~100 merchant houses
--        per transaction with set-based reads, instead of one house per transaction)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, 2026-10-27, the four hourly runs under 0249 / 0253) ──────────────
-- Every run since 0249 succeeds (57-75 s), but the compactor's 30 s finished only 12-34 of 821 houses
-- a run, so the slice of 0253 never finished (`upto` null) and ~1.01 M merchant events (943 k ledger
-- rows: p50 1,111 a house, max 3,290) still wait from 10-25. One house step is ~1-2 s, nearly all of it
-- random page reads: her ledger rows, events and voyages lie one to a page across two days, and each
-- step also sums her WHOLE ledger (public.assert_ledger_reconciles → public.ledger_sum, ~1,000 scattered
-- rows; IO counters during the 17:07 run: ledger 25.8 k heap + 16.5 k index blocks from disk). The same
-- whole-ledger sum runs on every merchant `credit` (two deferred triggers) in every arrivals beat.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- 1. public.npc_compact_houses(houses uuid[], now): npc_compact_house's rules, SET-BASED for a batch.
--    The same four steps in the same order (her ended voyages, her past trade_daily days, her ledger
--    before the cut rolled into ONE NPC_CARRIED row with the balance computed from the purse and then
--    asserted, her events), each one statement for the whole batch: `player_id = any(batch)` on the
--    (player_id, created_at) indexes is a bitmap scan, so each page is read once, in block order, for all
--    the batch's houses together. Only merchants are touched (the batch is filtered on players.is_npc).
-- 2. public.npc_compact_house(house, now) becomes the batch of one (one hunk): ONE authority for the rules.
--    public.npc_compact (the whole world in one transaction) is unchanged and so now runs through it too.
-- 3. tick_reconcile's compact step (3 hunks) keeps 0253's slices (oldest six hours first) and its order
--    (the house with the oldest row awaiting a roll first), but takes the houses 100 to a transaction:
--    hold_the_quay(), npc_upkeep_scope, npc_compact_houses(batch, slice), commit. A batch that fails is
--    rolled back whole and its houses are then done one at a time, each its own transaction (the 0249
--    step), so a bad house holds back only herself. The 30 s budget is checked before each transaction.
--    The receipt adds `batches`.
-- The ledger_sum itself is NOT changed: it is THE statement of the purse invariant (0004) and, once a
-- house is rolled, it sums her NPC_CARRIED row plus the last ~6-7 hours of rows (~26 a house-hour), all
-- recently written and in the cache. The drain is what makes it cheap again; a running total would be a
-- second authority for the purse. (Dev-log 2026-10-27-reconcile-timeout.md, "0257".)
-- Batch ≡ house by house: the houses' rows are disjoint, and no ledger row names another house's event
-- (prod, read-only 10-27 17:13: 0 of 811,251 named events cross houses), so the one difference a batch
-- could make (an event freed by another house's roll in the same batch) does not arise; it would be
-- what the next hour does anyway. Asserted below on a rolled-back probe of four houses.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the four hunks below (each OLD text is here verbatim). public.npc_compact_houses
-- is additive and harmless if left in place.
--
-- VERSION: 0257 (prod head 0255 when cut; 0256, the departure trim, deploys first and touches none of
-- these bodies). Hunks cut from the LIVE bodies on prod at head 0255, LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_compact_house(uuid,timestamptz)') is null or to_regclass('public.reconcile_runs') is null
     or to_regprocedure('public.hold_the_quay()') is null then
    raise exception '0257 refuses: 0249 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0257(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0257 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_compact_house(uuid,timestamptz)'), ('public.tick_reconcile(boolean)')) f(fn);

create temp table before_0257 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                         'public.npc_compact_orders(timestamptz)'::regprocedure,
                                         'public.ledger_sum(uuid)'::regprocedure,
                                         'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                         'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                         'public.tick_arrivals(timestamptz)'::regprocedure,
                                         'public.tick_arrivals_each_second(int)'::regprocedure)) as others_md5;

-- the 0249 house step, kept for the self-assert's comparison run
do $$
begin
  if pg_temp.occurs_0257((select def from defs_before_0257 where fn = 'public.npc_compact_house(uuid,timestamptz)'),
                         'FUNCTION public.npc_compact_house(') <> 1 then
    raise exception '0257 self-assert FAIL: npc_compact_house''s definition does not name itself once';
  end if;
  execute replace((select def from defs_before_0257 where fn = 'public.npc_compact_house(uuid,timestamptz)'),
                  'FUNCTION public.npc_compact_house(', 'FUNCTION pg_temp.npc_compact_house_old_0257(');
end $$;

-- ── 1. THE RULES, SET-BASED, FOR A BATCH OF HOUSES ─────────────────────────────────────────────
create function public.npc_compact_houses(p_houses uuid[], p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0257: THE merchant compaction rules (0097 → 0249's npc_compact_house, moved here unchanged in what they
-- keep and what they delete), for a BATCH of houses at once: her ended voyages (her fleets', not read by a
-- route's open lap; their voyage_events and insurance cascade), her past game-days of trade_daily, her ledger
-- before the cut rolled into ONE NPC_CARRIED row (the balance computed from the purse, then asserted), her
-- events (not of a kept kind, not named by a remaining ledger row). Each step is ONE statement for the whole
-- batch, so the (player_id, created_at) indexes give bitmap scans that read each page once, in block order,
-- for every house in it (one house a statement read a page per row). Only merchants are touched: the batch is
-- filtered on players.is_npc here, and public.forbid_mutation's exemption allows a merchant's row alone.
-- public.npc_compact_house is the batch of one; public.tick_reconcile runs ~100 a transaction.
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  v_hs      uuid[];          -- the batch's merchants
  v_roll    uuid[];          -- the houses with two or more rows before the cut, and their roll:
  v_n       int[];
  v_sum     bigint[];
  v_at      timestamptz[];
  v_bal     bigint[];
  v_i       int;
  v_voy     int := 0;
  v_led     int := 0;
  v_ev      int := 0;
  v_td      int := 0;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  v_hs := array(select p.id from public.players p where p.id = any(p_houses) and p.is_npc order by p.id);
  if cardinality(v_hs) = 0 then
    return jsonb_build_object('voyages', 0, 'ledger_rolled', 0, 'events', 0, 'trade_daily', 0);
  end if;
  perform set_config('byeharu.npc_compact', 'on', true);

  delete from public.voyages v
   using public.fleets f
   where v.fleet_id = f.id and f.player_id = any(v_hs)
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.trade_daily td
   where td.player_id = any(v_hs) and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  -- each house's rows before the cut, in one read: how many, their sum, their last instant
  select coalesce(array_agg(o.player_id order by o.player_id), '{}'), coalesce(array_agg(o.n order by o.player_id), '{}'),
         coalesce(array_agg(o.s order by o.player_id), '{}'), coalesce(array_agg(o.at order by o.player_id), '{}')
    into v_roll, v_n, v_sum, v_at
    from (select l.player_id, count(*)::int as n, coalesce(sum(l.ducats_delta), 0)::bigint as s, max(l.created_at) as at
            from public.ledger l where l.player_id = any(v_hs) and l.created_at < v_cut
           group by l.player_id having count(*) >= 2) o;
  if cardinality(v_roll) > 0 then
    -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED (0097): the purse now, less every delta
    -- booked after the cut — exact by construction, whatever the order inside a tick.
    v_bal := array(select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                                where l2.player_id = r.id and l2.created_at >= v_cut), 0)
                     from unnest(v_roll) with ordinality r(id, k)
                     join public.players p on p.id = r.id
                    order by r.k);
    delete from public.ledger l where l.player_id = any(v_roll) and l.created_at < v_cut;
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
    select v_roll[k], 'NPC_CARRIED', v_sum[k], v_bal[k], null, v_at[k]
      from generate_series(1, cardinality(v_roll)) k
     order by k;
    for v_i in 1 .. cardinality(v_roll) loop
      perform public.assert_ledger_reconciles(v_roll[v_i]);
      v_led := v_led + v_n[v_i];
    end loop;
  end if;
  delete from public.events ev
   where ev.player_id = any(v_hs) and ev.created_at < v_cut
     and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
     and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
  get diagnostics v_ev = row_count;

  perform set_config('byeharu.npc_compact', 'off', true);
  return jsonb_build_object('voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev, 'trade_daily', v_td);
end $$;
comment on function public.npc_compact_houses(uuid[], timestamptz) is
  '0257: THE merchant compaction rules, set-based for a batch of houses (each step one statement, each page read once). public.npc_compact_house is the batch of one; public.tick_reconcile runs ~100 houses a transaction. Server-only.';
revoke all on function public.npc_compact_houses(uuid[], timestamptz) from public, anon, authenticated;

-- ── 2 + 3. THE HUNKS ───────────────────────────────────────────────────────────────────────────
create temp table hunks_0257 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0257 (fn, n, old, new) values
('public.npc_compact_house(uuid,timestamptz)', 1,
$h$-- never touched (only a merchant's: here, and in public.forbid_mutation's exemption).
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  v_n       int;
  v_sum     bigint;
  v_bal     bigint;
  v_at      timestamptz;
  v_voy     int := 0;
  v_led     int := 0;
  v_ev      int := 0;
  v_td      int := 0;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  if not exists (select 1 from public.players p where p.id = p_house and p.is_npc) then
    return jsonb_build_object('voyages', 0, 'ledger_rolled', 0, 'events', 0, 'trade_daily', 0);
  end if;
  perform set_config('byeharu.npc_compact', 'on', true);

  delete from public.voyages v
   using public.fleets f
   where v.fleet_id = f.id and f.player_id = p_house
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.trade_daily td
   where td.player_id = p_house and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  select count(*), coalesce(sum(l.ducats_delta), 0), max(l.created_at)
    into v_n, v_sum, v_at
    from public.ledger l where l.player_id = p_house and l.created_at < v_cut;
  if v_n >= 2 then
    -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED (0097): the purse now, less every delta
    -- booked after the cut — exact by construction, whatever the order inside a tick.
    select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                 where l2.player_id = p_house and l2.created_at >= v_cut), 0)
      into v_bal from public.players p where p.id = p_house;
    delete from public.ledger l where l.player_id = p_house and l.created_at < v_cut;
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
    values (p_house, 'NPC_CARRIED', v_sum, v_bal, null, v_at);
    perform public.assert_ledger_reconciles(p_house);
    v_led := v_n;
  end if;
  delete from public.events ev
   where ev.player_id = p_house and ev.created_at < v_cut
     and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
     and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
  get diagnostics v_ev = row_count;

  perform set_config('byeharu.npc_compact', 'off', true);
  return jsonb_build_object('voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev, 'trade_daily', v_td);
end $h$,
$h$-- never touched (only a merchant's: here, and in public.forbid_mutation's exemption).
-- 0257: THE BATCH OF ONE. The rules live in public.npc_compact_houses (set-based, one authority); this is
-- that function for one house, with the same answer.
begin
  return public.npc_compact_houses(array[p_house], p_now);
end $h$),
('public.tick_reconcile(boolean)', 1,
$h$  v_slices   int := 0;
begin
$h$,
$h$  v_slices   int := 0;
  -- 0257: the slice's houses, ~100 a transaction (public.npc_compact_houses)
  v_order    uuid[];
  v_batch    uuid[];
  v_bsize    constant int := 100;
  v_i        int;
  v_j        int;
  v_bfail    text;
  v_batches  int := 0;
begin
$h$),
('public.tick_reconcile(boolean)', 2,
$h$      v_cleft := 0;
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
$h$,
$h$      v_cleft := 0;
      -- the house with the oldest row awaiting a roll first (her NPC_CARRIED row skipped: two index entries),
      -- so a slice the budget cuts short is never short of the same houses twice
      v_order := array(select p.id from public.players p where p.is_npc
                        order by (select min(l.created_at) from public.ledger l
                                   where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id);
      -- 0257: A HUNDRED HOUSES A TRANSACTION (public.npc_compact_houses: the same rules, each page of the slice
      -- read once for the hundred, in block order; one house a transaction read a page per row). A batch that
      -- fails is rolled back whole, then its houses are done one at a time, each its own transaction, so a
      -- bad house holds back only herself. The 30 s budget is checked before every transaction.
      v_i := 1;
      while v_i <= coalesce(cardinality(v_order), 0) loop
        if clock_timestamp() >= v_cby then
          v_cleft := v_cleft + cardinality(v_order) - v_i + 1;
          exit;
        end if;
        v_batch := v_order[v_i : v_i + v_bsize - 1];
        v_i := v_i + v_bsize;
        v_bfail := null;
        if p_commit then perform public.hold_the_quay(); end if;
        perform public.npc_upkeep_scope(v_deadline);
        begin
          v_ch := public.npc_compact_houses(v_batch, v_slice);
          v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
          v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
          v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
          v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
          v_cdone := v_cdone + cardinality(v_batch);
          v_batches := v_batches + 1;
        exception when others then
          v_bfail := sqlerrm;
        end;
        if p_commit then commit; end if;
        if v_bfail is not null then
          v_cnote := coalesce(v_cnote, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
          for v_j in 1 .. cardinality(v_batch) loop
            if clock_timestamp() >= v_cby then
              v_cleft := v_cleft + cardinality(v_batch) - v_j + 1;
              exit;
            end if;
            if p_commit then perform public.hold_the_quay(); end if;
            perform public.npc_upkeep_scope(v_deadline);
            begin
              v_ch := public.npc_compact_house(v_batch[v_j], v_slice);
              v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
              v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
              v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
              v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
              v_cdone := v_cdone + 1;
            exception when others then
              v_cfail := v_cfail + 1;
              v_cnote := coalesce(v_cnote, 'house ' || v_batch[v_j] || ': ' || sqlerrm);
            end;
            if p_commit then commit; end if;
          end loop;
        end if;
      end loop;
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    'slices', v_slices, 'upto', v_upto,   -- 0253: slices finished this run; the last instant every house is compacted as of
$h$,
$h$    'slices', v_slices, 'upto', v_upto,   -- 0253: slices finished this run; the last instant every house is compacted as of
    'batches', v_batches,                 -- 0257: transactions of ~100 houses that committed
$h$);

create or replace function pg_temp.recut_0257(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0257 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0257 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0257(v_def, h.old);
    if v_n <> 1 then
      raise exception '0257 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0257(fn) from defs_before_0257 order by fn;

-- ── THE PROBE: a batch leaves what the houses one at a time leave ──────────────────────────────
-- Four houses with rows from before a 2026-08-01 cut (earlier than every real row on prod — the first are
-- from 2026-08-22 — so only the probe's rows are touched): A and C merchants with rows to roll, B a merchant
-- with ONE old ledger row (not rolled, her old event still goes), P a PLAYER (never touched). Compacted from
-- the same rolled-back state four ways: (old) the 0249 house step, kept in pg_temp, house by house; (batch)
-- public.npc_compact_houses of all four at once; (one) the new public.npc_compact_house house by house;
-- (all) public.npc_compact, the whole world. All four must leave byte-identical rows and the same answers.
create or replace function pg_temp.digest_0257(p_house uuid)
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
    'voyage_events_n', (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                          join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'trade_daily', (select md5(coalesce(string_agg(concat_ws('|', td.port_id, td.good_id, td.game_day, td.qty), ',' order by td.game_day), ''))
                      from public.trade_daily td where td.player_id = p_house),
    'purse', (select p.ducats from public.players p where p.id = p_house),
    'ledger_sum', public.ledger_sum(p_house))
$$;

create or replace function pg_temp.run_0257(p_how text, p_houses uuid[], p_now timestamptz)
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
    if p_how = 'batch' then
      v_a := public.npc_compact_houses(p_houses, p_now);
    elsif p_how = 'all' then
      v_a := public.npc_compact(p_now) - 'orders' - 'before';
    else
      foreach h in array (select array_agg(x order by x) from unnest(p_houses) x) loop
        if p_how = 'old' then v_r := pg_temp.npc_compact_house_old_0257(h, p_now);
        else v_r := public.npc_compact_house(h, p_now); end if;
        for k in select jsonb_object_keys(v_r) loop
          v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
        end loop;
      end loop;
    end if;
    foreach h in array p_houses loop
      v_d := v_d || jsonb_build_object(h::text, pg_temp.digest_0257(h));
    end loop;
    raise exception using errcode = 'ZY257',
      message = jsonb_build_object('a', v_a, 'd', v_d)::text;
  exception when sqlstate 'ZY257' then
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
  select * into v_before from before_0257;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0257 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0257 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0257(v_def, v_h.new) <> 1 then
        raise exception '0257 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0257 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0257 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                       'public.npc_compact_orders(timestamptz)'::regprocedure,
                                       'public.ledger_sum(uuid)'::regprocedure,
                                       'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                       'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                       'public.tick_arrivals(timestamptz)'::regprocedure,
                                       'public.tick_arrivals_each_second(int)'::regprocedure)) <> v_before.others_md5 then
    raise exception '0257 self-assert FAIL: npc_compact, the orders step, the purse invariant, credit, the beat or the arrivals run moved';
  end if;
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0257(v_def, 'public.npc_compact_houses(v_batch, v_slice)') <> 1
     or pg_temp.occurs_0257(v_def, 'public.npc_compact_house(v_batch[v_j], v_slice)') <> 1
     or pg_temp.occurs_0257(v_def, 'public.npc_compact_house(') <> 1
     or pg_temp.occurs_0257(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 5
     or pg_temp.occurs_0257(v_def, 'if p_commit then commit; end if;') <> 5 then
    raise exception '0257 self-assert FAIL: tick_reconcile does not compact by batch (one house at a time only after a failed batch), each after the quay lock';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and p.oid <> 'public.tick_reconcile(boolean)'::regprocedure
         and p.oid <> 'public.tick_arrivals_each_second(int)'::regprocedure
         and pg_get_functiondef(p.oid) like '%hold_the_quay()%'
         and p.oid <> 'public.hold_the_quay()'::regprocedure) <> 0 then
    raise exception '0257 self-assert FAIL: another function takes the quay lock';
  end if;
  if has_function_privilege('anon', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute') then
    raise exception '0257 self-assert FAIL: a client can run the batch compactor';
  end if;

  -- (b) A BATCH LEAVES WHAT THE HOUSES ONE AT A TIME LEAVE (rolled back whole)
  begin
    declare
      v_a    uuid; v_b uuid; v_c uuid; v_p uuid;
      v_all4 uuid[];
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      v_old jsonb; v_batch jsonb; v_one jsonb; v_all jsonb; v_pre jsonb := '{}'::jsonb;
      v_m   uuid; v_f uuid; v_k int;
      e1 uuid; e2 uuid; e3 uuid; e4 uuid; v0 uuid; v1 uuid;
    begin
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0257 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_a := public.new_house(null, 'Casa dos Cem A 0257', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_b := public.new_house(null, 'Casa dos Cem B 0257', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_c := public.new_house(null, 'Casa dos Cem C 0257', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_p := public.new_house(null, 'Casa dos Cem P 0257', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => false);
      v_all4 := array[v_a, v_b, v_c, v_p];
      v_k := 0;
      foreach v_m in array v_all4 loop
        v_k := v_k + 1;
        v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
        if v_f is null then
          insert into public.fleets (player_id, name, port_id) values (v_m, 'Cem 0257 ' || v_k, v_port) returning id into v_f;
        end if;
        e1 := gen_random_uuid(); e2 := gen_random_uuid(); e3 := gen_random_uuid(); e4 := gen_random_uuid();
        v0 := gen_random_uuid(); v1 := gen_random_uuid();
        -- E1, E2 old (both go), E3 named by a kept ledger row (stays), E4 FOUNDED (stays)
        insert into public.events (id, player_id, kind, payload, created_at) values
          (e1, v_m, 'PROBE_0257', '{}', c_old - interval '3 hours'), (e2, v_m, 'PROBE_0257', '{}', c_old),
          (e3, v_m, 'PROBE_0257', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day');
        if v_m = v_b then
          -- B: ONE old ledger row (summing to 0 with the purse kept): nothing to roll; E2 is not named by it
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0257', 0, 1000, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0257', 0, 1000, e3, c_now);
        else
          -- old rows summing to 0 (C's amounts differ from A's), one of them naming E2; E3 named by a new row
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0257', 100 * v_k, 1000 + 100 * v_k, null, c_old - interval '3 hours'),
            (v_m, 'PROBE_0257', 300, 1300 + 100 * v_k, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0257', -300 - 100 * v_k + 50, 1050, null, c_old - interval '1 hour'),
            (v_m, 'PROBE_0257', -50, 1000, e2, c_old),
            (v_m, 'PROBE_0257', 0, 1000, e3, c_now);
        end if;
        insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                    origin_port_id, dest_port_id, created_at) values
          (v0, v_f, v_m, '[]', 100, '{}', c_old - interval '1 day', c_old - interval '3 hours', 'ARRIVED', v_port, v_port2, c_old - interval '1 day'),
          (v1, v_f, v_m, '[]', 100, '{}', c_old - interval '2 hours', c_old, 'ARRIVED', v_port2, v_port, c_old - interval '2 hours');
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
        select v.id, 1, k.code, '{}', c_old
          from (values (v0), (v1)) v(id), (select code from public.voyage_event_kinds order by code limit 1) k;
        insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values
          (v_m, v_port, v_good, v_gd - 2, 3), (v_m, v_port, v_good, v_gd - 1, 5), (v_m, v_port, v_good, v_gd, 7);
        v_pre := v_pre || jsonb_build_object(v_m::text, pg_temp.digest_0257(v_m));
      end loop;

      v_old   := pg_temp.run_0257('old',   v_all4, c_now);
      v_batch := pg_temp.run_0257('batch', v_all4, c_now);
      v_one   := pg_temp.run_0257('one',   v_all4, c_now);
      v_all   := pg_temp.run_0257('all',   v_all4, c_now);

      if v_old->'d' is distinct from v_batch->'d' or v_old->'d' is distinct from v_one->'d' or v_old->'d' is distinct from v_all->'d' then
        raise exception '0257 self-assert FAIL: a batch left other rows than house by house (old %, batch %, one %, whole world %)',
          v_old, v_batch, v_one, v_all;
      end if;
      if v_old->'a' is distinct from v_batch->'a' or v_old->'a' is distinct from v_one->'a' or v_old->'a' is distinct from v_all->'a' then
        raise exception '0257 self-assert FAIL: a batch answered otherwise than house by house (old %, batch %, one %, whole world %)',
          v_old->'a', v_batch->'a', v_one->'a', v_all->'a';
      end if;
      -- what went is exactly what the rules say: A and C roll 4 rows into 1 and lose E1, E2, both voyages, two
      -- trade days; B rolls nothing (one old row) and loses E1, E2, both voyages, two trade days; P is untouched
      if v_old->'a' <> jsonb_build_object('voyages', 6, 'ledger_rolled', 8, 'events', 6, 'trade_daily', 6) then
        raise exception '0257 self-assert FAIL: the probe did not compact as the rules say: %', v_old->'a';
      end if;
      if v_old->'d'->v_p::text is distinct from v_pre->v_p::text then
        raise exception '0257 self-assert FAIL: a player''s rows were touched (before %, after %)', v_pre->v_p::text, v_old->'d'->v_p::text;
      end if;
      foreach v_m in array array[v_a, v_c] loop
        if (v_old->'d'->v_m::text->>'carried')::int <> 1
           or (v_old->'d'->v_m::text->>'ledger_n')::int <> (v_pre->v_m::text->>'ledger_n')::int - 3
           or (v_old->'d'->v_m::text->>'events_n')::int <> (v_pre->v_m::text->>'events_n')::int - 2
           or (v_old->'d'->v_m::text->>'voyages_n')::int <> (v_pre->v_m::text->>'voyages_n')::int - 2
           or (v_old->'d'->v_m::text->>'voyage_events_n')::int <> (v_pre->v_m::text->>'voyage_events_n')::int - 2
           or (v_old->'d'->v_m::text->>'ledger_sum')::bigint <> (v_pre->v_m::text->>'purse')::bigint
           or (v_old->'d'->v_m::text->>'purse')::bigint <> (v_pre->v_m::text->>'purse')::bigint then
          raise exception '0257 self-assert FAIL: house % did not compact as the rules say (before %, after %)',
            v_m, v_pre->v_m::text, v_old->'d'->v_m::text;
        end if;
      end loop;
      if (v_old->'d'->v_b::text->>'carried')::int <> 0
         or (v_old->'d'->v_b::text->>'ledger')::text <> (v_pre->v_b::text->>'ledger')::text
         or (v_old->'d'->v_b::text->>'events_n')::int <> (v_pre->v_b::text->>'events_n')::int - 2 then
        raise exception '0257 self-assert FAIL: the one-row house did not compact as the rules say (before %, after %)',
          v_pre->v_b::text, v_old->'d'->v_b::text;
      end if;
      v_res := jsonb_build_object('answer', v_batch->'a', 'houses', 4);
      raise exception using errcode = 'ZY25E', message = v_res::text;
    end;
  exception when sqlstate 'ZY25E' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name like 'Casa dos Cem % 0257') then
    raise exception '0257 self-assert FAIL: a probe house was left behind';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0257 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0257 self-assert FAIL: a wall moved';
  end if;

  raise notice '0257 self-assert ok: A HUNDRED HOUSES ARE CUT AT ONCE. public.npc_compact_houses holds the compaction rules set-based; npc_compact_house is its batch of one (1 hunk); tick_reconcile compacts each slice ~100 houses a transaction after the quay lock, house by house only after a failed batch (3 hunks); all reverse to their pre-images, ACL / volatility / definer / config unmoved; npc_compact, the orders step, ledger_sum, assert_ledger_reconciles, credit, the beat and tick_arrivals unmoved; no other function takes the quay lock; registry unchanged; walls 0. PROBE (3 merchants + 1 player, rows before a 2026-08-01 cut, rolled back): the 0249 house step one at a time, the batch, the new house step and npc_compact left byte-identical rows and answers: %. The player untouched. Nothing left behind.',
    v_res;
end $$;
