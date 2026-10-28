-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0267 — EACH COMPANY ACTS IN HER OWN TRANSACTION  (the hourly companies' step leaves its one long quay hold:
--        a company a transaction, the quay held for her act alone; what is decided is unchanged)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ROOT CAUSE, MEASURED (prod, read-only, head 0266, 2026-10-28 02:07-06:23 UTC) ────────────
-- In the hourly reconcile minute (:07) merchant lap starts lag: lap_start_runs at 05:07 p95 11.1 s (max 12.0),
-- at 06:07 p95 21.1 s (max 21.8) with 11 due left, and 06:08 p95 23.7 s (max 24.4, the 06:07 leftovers); every
-- other minute ~5.5 s. In both :07 runs ONE open step (public.lap_start_open, under the quay) took 5.8 / 7.3 s
-- (open_ms_max), and 10 opens waited their full 1.5 s for a beat's gap (late 10).
-- The beats say why: at 06:07:30.001 the beat WAITED 8,838 ms for the quay (splits.q), then ran 102 fleets due at
-- once (3.5 s); at 05:07:32 the beat waited 8,023 ms. No other beat in :07-:08 of the last 6 h waited over 1.5 s.
-- The holder is tick_reconcile's COMPANIES' STEP, one transaction under public.hold_the_quay(): its phase took
-- 5,881 / 8,097 / 5,728 / 8,553 / 8,898 ms (02:07 … 06:07), and it starts right after the tend phase (06:07:00 +
-- 29.8 s = 06:07:29.8, the beat at :30 waited until :39). The tend steps hold the quay a merchant at a time
-- (the longest beat wait in that phase 1.2 s). The compactor (0265) is off the quay (its :07 sweep held houses,
-- SKIP LOCKED, 5.3 s in all, no lap start busy) and the city tick runs at :37, not :07: neither is the stall.
-- WHAT THE STEP DOES UNDER THAT ONE HOLD: public.npc_tend_houses — npc_invest over its roster (501 companies
-- above npc_invest_above × capital on prod; 5 invested + 52 donated at 06:07), then capital_gift_pass (its roster
-- prices EVERY merchant's worth, 821, to order the broke), then the purse check of EVERY company (821 ledger sums,
-- ~2.8 ms each in pg_stat_user_functions = ~2.3 s). All of it under the quay, though only the acts write.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) The two passes are cut at the company, with the rules unchanged:
--     public.npc_invest_roster(p_only)  — npc_invest's roster query, verbatim (p_only narrows it to one company);
--     public.npc_invest_one(p_now, h)   — npc_invest's loop body for one company, verbatim: she is re-read through
--                                         the roster (her own row, the same predicate), then the deadline, then
--                                         her stake / gift exactly as before;
--     public.capital_gift_roster(p_now, p_only) — capital_gift_pass's roster query, verbatim;
--     public.capital_gift_one(p_now, h) — its loop body for one company, verbatim, her row re-read the same way.
--     public.npc_invest and public.capital_gift_pass become the roster walked through the body: in ONE
--     transaction they decide exactly what they decided (proved below on the live world). npc_tend_houses,
--     npc_tend and player_gift, which call them, are unmoved.
-- (2) tick_reconcile's companies' step (1 hunk, and 1 for its locals): the rosters are read OUTSIDE the quay (plain reads), then each
--     company in its own transaction: the quay, the hour's scope, her act, HER purse checked before her COMMIT.
--     A company that fails is rolled back alone and noted. The quay is held for one company's act (~10 ms),
--     not for the step (5.7-8.9 s). The 821-company check leaves the step: a company's purse moves only in her
--     own act, which checks it, and the whole-world check that follows (unchanged) still reads every one.
-- (3) THE RECEIPT (3 hunks): reconcile_runs.receipt.quay = {tend, companies}: per step the transactions under the
--     quay, the ms held in all, the longest hold, the ms waited and the longest wait (public.quay_tally).
--
-- ── WHY THE RESULTS ARE THE SAME ───────────────────────────────────────────────────────────────
-- Inside one transaction, re-reading her through the roster gives the row the roster gave: a company's act moves
-- her own purse, stakes and influence and a city's purse and works, never ANOTHER company's roster row (her
-- purse, capital, her country's capital, her worth). The rosters are read before any act, as the old loops'
-- ordered, limited queries were (a sort reads every row before the first). PROBE (rolled back, on the world it
-- is applied to — prod's live companies when deployed): the OLD npc_tend_houses (before this file replaces
-- anything), the NEW npc_tend_houses, and the new step as tick_reconcile now runs it (a company at a time, her
-- purse checked), each from the same state: byte-identical rows (every company's purse and version, invested_at,
-- city_shares, city_works, port_influence, port_fee_debts, and the step's new ledger, events, treasury_flows and
-- capital_gifts rows) and the same answer. When the step commits between companies, a beat may run between
-- two of them; each company is then read as she is when she acts (as each merchant's tend step already is, 0137).
--
-- ── NO DEADLOCK, BY CONSTRUCTION ───────────────────────────────────────────────────────────────
-- Each company's transaction takes the quay FIRST, then exactly the locks the old step took for her, in the same
-- order (the same callees: invest_for, donate_for, capital_pays, port_fee_collect, emit_event, unmoved). So at any
-- wait it holds a SUBSET of what the old step held at the same point (the companies before her are committed),
-- and waits for the same lock. Any cycle of waits through it would be a cycle through the old step, with the
-- other writers unchanged: the new wait-for graph is a subgraph of the old one. The quay itself is still taken
-- first by every writer that takes it (beat, tend, companies, lap open), so no two quay holders wait on each
-- other. The rosters take no lock (asserted: no lock clause, no advisory lock, no quay, no credit). Holding the
-- quay for less time is the only change to the lock graph.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the five tick_reconcile hunks (each OLD text is here verbatim). npc_invest and
-- capital_gift_pass may stay as they are (they decide the same); the new functions are harmless left alone.
--
-- VERSION: 0267 (prod head 0266 when cut). Hunks cut from the LIVE tick_reconcile on prod at head 0266, LF.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.lap_start_open(uuid)') is null or to_regprocedure('public.tick_compact(boolean,boolean)') is null
     or to_regprocedure('public.npc_invest(timestamptz)') is null or to_regprocedure('public.capital_gift_pass(timestamptz,uuid)') is null
     or position('-- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop'
                 in pg_get_functiondef('public.npc_invest(timestamptz)'::regprocedure)) = 0
     or position('pl.ducats < h.capital * v_pct               -- 0236: BROKE'
                 in pg_get_functiondef('public.capital_gift_pass(timestamptz,uuid)'::regprocedure)) = 0 then
    raise exception '0267 refuses: 0266 (and the npc_invest / capital_gift_pass it was cut against) is not in this world';
  end if;
  if to_regprocedure('public.npc_invest_one(timestamptz,uuid)') is not null or to_regprocedure('public.quay_tally(jsonb,timestamptz,timestamptz)') is not null then
    raise exception '0267 refuses: it has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0267(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0267 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_reconcile(boolean)')) f(fn);

-- the two passes as they were (their calls are compared below), and their posture
create temp table passes_before_0267 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
  from (values ('public.npc_invest(timestamptz)'), ('public.capital_gift_pass(timestamptz,uuid)')) f(fn)
  join pg_proc p on p.oid = f.fn::regprocedure;

-- the functions this file must leave byte for byte: everything the companies' acts run, the purse, the quay, its
-- other holders, and the callers of the two passes
create temp table kept_0267 on commit drop as
select f.fn from (values ('public.npc_tend_houses(timestamptz)'), ('public.npc_tend(timestamptz,uuid)'),
                         ('public.player_gift(uuid,timestamptz)'), ('public.invest_for(uuid,uuid,text,integer)'),
                         ('public.donate_for(uuid,uuid,bigint)'), ('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)'),
                         ('public.port_fee_collect(uuid,uuid,bigint)'), ('public.emit_event(uuid,text,jsonb)'),
                         ('public.pay_city(uuid,uuid,text,bigint,uuid)'), ('public.city_pays(uuid,uuid,text,bigint,uuid)'),
                         ('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'), ('public.treasury_lock(uuid)'),
                         ('public.influence_post(uuid,uuid,bigint,text)'), ('public.credit(uuid,text,bigint,uuid)'),
                         ('public.npc_closest_race(uuid)'), ('public.npc_upkeep_spent()'), ('public.npc_worth(uuid)'),
                         ('public.player_worth(uuid)'), ('public.ledger_sum(uuid)'), ('public.assert_ledger_reconciles(uuid)'),
                         ('public.hold_the_quay()'), ('public.npc_upkeep_scope(timestamptz)'), ('public.npc_tend_sum(jsonb,jsonb)'),
                         ('public.npc_step_failed(jsonb,text)'), ('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'),
                         ('public.npc_tend_roster()'), ('public.tick_arrivals(timestamptz)'), ('public.tick_arrivals_each_second(int)'),
                         ('public.tick_lap_starts(boolean)'), ('public.lap_start_open(uuid)'), ('public.lap_start_plan(uuid)'),
                         ('public.tick_compact(boolean,boolean)'), ('public.npc_compact_locked(uuid[],timestamptz)'),
                         ('public.economy_closed()'), ('public.city_treasury_on()'), ('public.npc_traders_on()')) f(fn);

create temp table before_0267 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0267 k) as kept_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers;

-- ── THE PROBE'S EYES: the rows a companies' step can write ─────────────────────────────────────
-- Every company's purse and version and invested_at; every stake, works row, influence row and fee debt; and the
-- step's NEW ledger, events, treasury flows and capital gifts (created in this transaction: created_at >= now()),
-- without their generated ids (a sequence or a random uuid differs between two runs of the same step).
create or replace function pg_temp.world_0267()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'companies', (select md5(coalesce(string_agg(concat_ws('|', p.id, p.ducats, p.version, h.invested_at), ',' order by p.id), ''))
                    from public.players p left join public.npc_houses h on h.player_id = p.id where p.is_npc),
    'shares', (select md5(coalesce(string_agg(concat_ws('|', s.port_id, s.kind, s.player_id, s.shares, s.paid, s.accrued, s.accrued_day), ','
                                              order by s.port_id, s.kind, s.player_id), '')) from public.city_shares s),
    'works', (select md5(coalesce(string_agg(concat_ws('|', w.port_id, w.kind, w.level, w.subscribed, w.updated_at), ',' order by w.port_id, w.kind), ''))
                from public.city_works w),
    'influence', (select md5(coalesce(string_agg(concat_ws('|', i.port_id, i.nation_id, i.player_id, i.points, i.day_given, i.updated_at), ','
                                                 order by i.port_id, i.nation_id, i.player_id), '')) from public.port_influence i),
    'fee_debts', (select md5(coalesce(string_agg(concat_ws('|', d.player_id, d.port_id, d.kind, d.ducats, d.updated_at), ','
                                                 order by d.player_id, d.port_id, d.kind), '')) from public.port_fee_debts d),
    'ledger', (select md5(coalesce(string_agg(x, ',' order by x), '')) from (
                 select concat_ws('|', l.player_id, l.kind, l.ducats_delta, l.balance_after, l.created_at) x
                   from public.ledger l join public.players p on p.id = l.player_id and p.is_npc where l.created_at >= now()) z),
    'events', (select md5(coalesce(string_agg(x, ',' order by x), '')) from (
                 select concat_ws('|', e.player_id, e.kind, e.payload::text, e.created_at) x
                   from public.events e join public.players p on p.id = e.player_id and p.is_npc where e.created_at >= now()) z),
    'flows', (select md5(coalesce(string_agg(x, ',' order by x), '')) from (
                select concat_ws('|', f.port_id, f.kind, f.ducats, f.player_id, f.created_at) x
                  from public.treasury_flows f join public.players p on p.id = f.player_id and p.is_npc where f.created_at >= now()) z),
    'gifts', (select md5(coalesce(string_agg(x, ',' order by x), '')) from (
                select concat_ws('|', g.port_id, g.player_id, g.ducats, g.called_from, g.created_at) x
                  from public.capital_gifts g where g.created_at >= now()) z),
    'n', jsonb_build_object(
      'ledger', (select count(*) from public.ledger l join public.players p on p.id = l.player_id and p.is_npc where l.created_at >= now()),
      'events', (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc where e.created_at >= now()),
      'flows', (select count(*) from public.treasury_flows f join public.players p on p.id = f.player_id and p.is_npc where f.created_at >= now()),
      'gifts', (select count(*) from public.capital_gifts g where g.created_at >= now())))
$$;

create temp table probe_0267 (how text primary key, answer jsonb, world jsonb, before jsonb) on commit drop;

-- ── THE OLD STEP, BEFORE ANYTHING IS REPLACED (rolled back) ───────────────────────────────────────
-- As tick_reconcile ran it at head 0266: the hour's scope, npc_tend_houses, every company's purse checked.
do $$
declare
  v_res  jsonb;
  v_w0   jsonb := pg_temp.world_0267();
  h      record;
begin
  begin
    perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
    v_res := public.npc_tend_houses(now());
    for h in select p.id from public.players p where p.is_npc order by p.id loop
      perform public.assert_ledger_reconciles(h.id);
    end loop;
    raise exception using errcode = 'ZY267', message = jsonb_build_object('a', v_res, 'w', pg_temp.world_0267())::text;
  exception when sqlstate 'ZY267' then
    v_res := sqlerrm::jsonb;
  end;
  insert into probe_0267 values ('old', v_res->'a', v_res->'w', v_w0);
end $$;

-- ── 1. THE QUAY'S TALLY ─────────────────────────────────────────────────────────────────────────
create function public.quay_tally(p_acc jsonb, p_asked timestamptz, p_got timestamptz)
returns jsonb
language sql
volatile
set search_path = public, pg_temp
as $fn$
-- 0267: one transaction under the quay added to a step's tally: n, the ms held (from the quay's grant, p_got, to
-- now: call it after the COMMIT), the longest hold, the ms waited for the quay (p_asked → p_got), the longest wait.
-- Called by public.tick_reconcile alone; its receipt keeps one tally a step (receipt.quay).
  select jsonb_build_object(
    'n', coalesce((p_acc->>'n')::int, 0) + 1,
    'held_ms', round(coalesce((p_acc->>'held_ms')::numeric, 0) + extract(epoch from clock_timestamp() - p_got) * 1000, 1),
    'hold_max_ms', round(greatest(coalesce((p_acc->>'hold_max_ms')::numeric, 0), extract(epoch from clock_timestamp() - p_got) * 1000), 1),
    'wait_ms', round(coalesce((p_acc->>'wait_ms')::numeric, 0) + extract(epoch from p_got - p_asked) * 1000, 1),
    'wait_max_ms', round(greatest(coalesce((p_acc->>'wait_max_ms')::numeric, 0), extract(epoch from p_got - p_asked) * 1000), 1))
$fn$;
comment on function public.quay_tally(jsonb, timestamptz, timestamptz) is
  '0267: adds one quay transaction (asked at, granted at; held until now) to a step''s tally {n, held_ms, hold_max_ms, wait_ms, wait_max_ms}. Server-only; called by public.tick_reconcile.';
revoke all on function public.quay_tally(jsonb, timestamptz, timestamptz) from public, anon, authenticated;

-- ── 2. THE INVESTMENT PASS, CUT AT THE COMPANY ──────────────────────────────────────────────────
create function public.npc_invest_roster(p_only uuid default null)
returns table (player_id uuid, capital bigint, ducats bigint, company_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0267: THE companies the investment pass asks, in its order (0123's roster query, verbatim): lit and with the
-- merchants on, at most npc_invest_max_per_hour companies above npc_invest_above × capital, longest-uninvested
-- first. p_only narrows it to one company (public.npc_invest_one re-reads her through it). A plain read.
#variable_conflict use_column
begin
  if not public.city_treasury_on() or not public.npc_traders_on() then
    return;
  end if;
  return query
  select h.player_id, h.capital, pl.ducats, pl.company_name
              from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
             where pl.ducats > h.capital * public.wc_num('npc_invest_above')
               and (p_only is null or h.player_id = p_only)
             order by h.invested_at nulls first, h.roster_ord
             limit public.wc_int('npc_invest_max_per_hour');
end $fn$;
comment on function public.npc_invest_roster(uuid) is
  '0267: npc_invest''s roster (0123, verbatim): the companies the investment pass asks, in order; p_only narrows it to one. A plain read. Server-only.';
revoke all on function public.npc_invest_roster(uuid) from public, anon, authenticated;

create function public.npc_invest_one(p_now timestamptz, p_player uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0267: ONE company's turn in the investment pass (0123 / 0145's loop body, verbatim): she is read through the
-- roster (her own row, the same predicate: not on it → nothing), then 0114's deadline, then her stake and gift.
-- Answers {invested, donated, deferred, failed, notes}. Called by public.npc_invest (the whole pass, one
-- transaction) and by public.tick_reconcile (a company a transaction, under the quay).
declare
  hi         record;
  v_pick     record;
  v_buy      int;
  v_invested int := 0;
  v_deferred int := 0;
  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
  -- 0145 (D12): where she gives, lit
  v_race     uuid;
  v_stake    record;
  v_left     numeric;
  v_room     bigint;
  v_donated  int := 0;
  v_gave     boolean;
begin
  select * into hi from public.npc_invest_roster(p_player) r;
  if hi.player_id is null then
    return jsonb_build_object('invested', 0, 'donated', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      return jsonb_build_object('invested', v_invested, 'donated', v_donated, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
    end if;
    begin
      -- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop
      -- (public.npc_closest_race) — shares there if offered, the rest as a gift under D7's cap. No race
      -- on her loop: 0123's rule below, as it was.
      v_race := null;
      if public.influence_on() then
        select r.port_id into v_race from public.npc_closest_race(hi.player_id) r;
      end if;
      if v_race is not null then
        v_left := hi.ducats - public.wc_num('npc_invest_keep') * hi.capital;
        v_gave := false;
        select w.kind, public.city_offered(w.port_id, w.kind) as offered, public.works_share_price(w.level) as price
          into v_stake
          from public.city_works w
         where w.port_id = v_race and public.city_offered(w.port_id, w.kind) > 0
         order by 2 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind)
         limit 1;
        if v_stake.kind is not null then
          v_buy := least(v_stake.offered, floor(v_left / v_stake.price))::int;
          if v_buy >= 1 and v_buy * v_stake.price >= public.wc_int('invest_min_ducats') then
            perform public.invest_for(hi.player_id, v_race, v_stake.kind, v_buy);
            v_left := v_left - v_buy * v_stake.price;
            v_invested := v_invested + 1;
            v_gave := true;
          end if;
        end if;
        select public.wc_int('influence_day_cap') - coalesce(sum(i.day_given), 0) into v_room
          from public.port_influence i where i.port_id = v_race and i.player_id = hi.player_id;
        if floor(least(v_left, v_room)) >= public.wc_int('donate_min_ducats') then
          perform public.donate_for(hi.player_id, v_race, floor(least(v_left, v_room))::bigint);
          v_donated := v_donated + 1;
          v_gave := true;
        end if;
        if v_gave then
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
        end if;
      else
      select w.port_id, w.kind, public.city_offered(w.port_id, w.kind) as offered,
             public.works_share_price(w.level) as price
        into v_pick
        from (select distinct s.port_id from public.npc_fleets nf
                join public.standing_route_stops s on s.route_id = nf.route_id
               where nf.player_id = hi.player_id) st
        join public.ports po on po.id = st.port_id and po.kind = 'HARBOUR'
        join public.city_works w on w.port_id = st.port_id
       where public.city_offered(w.port_id, w.kind) > 0
       order by 3 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind), po.code
       limit 1;
      if v_pick.port_id is not null then
        v_buy := least(v_pick.offered,
                       floor((hi.ducats - public.wc_num('npc_invest_keep') * hi.capital) / v_pick.price))::int;
        if v_buy >= 1 and v_buy * v_pick.price >= public.wc_int('invest_min_ducats') then
          perform public.invest_for(hi.player_id, v_pick.port_id, v_pick.kind, v_buy);
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
          v_invested := v_invested + 1;
        end if;
      end if;
      end if;   -- 0267: the old loop's `continue` after the race branch
    exception when others then
      v_failed := v_failed + 1;
      v_notes := v_notes || jsonb_build_object('company', hi.company_name, 'invest_error', sqlerrm);
    end;
  return jsonb_build_object('invested', v_invested, 'donated', v_donated, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $fn$;
comment on function public.npc_invest_one(timestamptz, uuid) is
  '0267: one company''s turn in the investment pass (0123 / 0145''s loop body, verbatim), she read through public.npc_invest_roster. Server-only; called by public.npc_invest and public.tick_reconcile.';
revoke all on function public.npc_invest_one(timestamptz, uuid) from public, anon, authenticated;

create or replace function public.npc_invest(p_now timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0123: lit and with the merchants on, at most npc_invest_max_per_hour companies above
-- npc_invest_above × capital, longest-uninvested first, each buy ONE stake at the stop of her loop
-- that offers the most shares (ties: kind order, then port code), toward npc_invest_keep × capital,
-- through public.invest_for — the players' door. Budgeted by 0114's deadline. Called by npc_tend.
-- 0267: THE ROSTER (public.npc_invest_roster) WALKED THROUGH THE BODY (public.npc_invest_one), unchanged, in one
-- transaction; tick_reconcile walks the same two a company a transaction.
declare
  hi         record;
  v_one      jsonb;
  v_invested int := 0;
  v_deferred int := 0;
  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
  v_donated  int := 0;
begin
  if not public.city_treasury_on() or not public.npc_traders_on() then
    return jsonb_build_object('invested', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
  for hi in select r.player_id from public.npc_invest_roster() r loop
    v_one := public.npc_invest_one(p_now, hi.player_id);
    v_invested := v_invested + (v_one->>'invested')::int;
    v_donated := v_donated + (v_one->>'donated')::int;
    v_deferred := v_deferred + (v_one->>'deferred')::int;
    v_failed := v_failed + (v_one->>'failed')::int;
    v_notes := v_notes || (v_one->'notes');
  end loop;
  return jsonb_build_object('invested', v_invested, 'donated', v_donated, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$;

-- ── 3. THE CAPITAL'S GIFT, CUT AT THE COMPANY ───────────────────────────────────────────────────
create function public.capital_gift_roster(p_now timestamptz, p_only uuid default null)
returns table (player_id uuid, capital bigint, nation_id uuid, worth bigint, cap_id uuid, cap_code text, cap_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0267: THE companies the capital's gift pass pays, in its order (0234 / 0236 / 0241's roster query, verbatim):
-- every broke merchant company (her purse under merchant_broke_pct × capital; none in the last gift_cooldown_hours;
-- under gift_max_per_week in 7 days), at most gift_max_per_hour, gifted longest ago (or never) first; p_only narrows
-- it to one company and, for a player, admits her (0241). Empty while the economy is open. A plain read.
#variable_conflict use_column
declare
  v_pct   numeric;
  v_cool  interval;
begin
  if not public.economy_closed() then
    return;
  end if;
  v_pct  := public.wc_num('merchant_broke_pct');
  v_cool := make_interval(hours => public.wc_int('gift_cooldown_hours'));
  return query
    select h.player_id, h.capital, pl.nation_id, w.worth, cp.id as cap_id, cp.code as cap_code, cp.name as cap_name
      -- 0241 (owner row 230): A PLAYER'S COMPANY TOO, but only when asked for her alone (p_only — public.player_gift,
      -- after her sale or at the harbour she makes); the hourly pass stays merchants'. Her capital is the starting money.
      from (select nh.player_id, nh.capital, false as human from public.npc_houses nh
            union all
            select hp.id, public.wc_int('starting_ducats')::bigint, true from public.players hp
             where not hp.is_npc and p_only is not null and hp.id = p_only) h
      join public.players pl on pl.id = h.player_id and pl.is_npc = not h.human
      left join public.nations n on n.id = pl.nation_id
      left join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
      cross join lateral (select case when h.human then public.player_worth(h.player_id) else public.npc_worth(h.player_id) end as worth) w
     where (p_only is null or h.player_id = p_only)
       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
       and (not h.human or w.worth < h.capital * v_pct)   -- 0241: a player — her worth (purse + cargo − debts) under it too
       and not exists (select 1 from public.capital_gifts g where g.player_id = h.player_id
                         and g.created_at > p_now - v_cool and g.created_at <= p_now)
       and (select count(*) from public.capital_gifts g where g.player_id = h.player_id
              and g.created_at > p_now - interval '7 days' and g.created_at <= p_now) < public.wc_int('gift_max_per_week')
     order by (select max(g.created_at) from public.capital_gifts g where g.player_id = h.player_id) nulls first,
              w.worth::numeric / h.capital, h.player_id
     limit public.wc_int('gift_max_per_hour');
end $fn$;
comment on function public.capital_gift_roster(timestamptz, uuid) is
  '0267: capital_gift_pass''s roster (0234 / 0236 / 0241, verbatim): the broke companies the gift pass pays, in order; p_only narrows it to one (and admits a player). A plain read. Server-only.';
revoke all on function public.capital_gift_roster(timestamptz, uuid) from public, anon, authenticated;

create function public.capital_gift_one(p_now timestamptz, p_player uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0267: ONE company's turn in the capital's gift pass (0234 / 0241's loop body, verbatim): she is read through the
-- roster (public.capital_gift_roster narrowed to her: not on it → nothing), then paid her capital by her country's
-- capital (public.capital_pays) in her own sub-transaction. Answers {gifted, gift_ducats, gift_waiting, failed,
-- notes}. Called by public.capital_gift_pass (the whole pass) and by public.tick_reconcile (a company a transaction).
declare
  v_cool  interval;
  r       record;
  v_res   jsonb;
  v_n     int := 0;
  v_d     bigint := 0;
  v_wait  int := 0;
  v_fail  int := 0;
  v_notes jsonb := '[]'::jsonb;
begin
  v_cool := make_interval(hours => public.wc_int('gift_cooldown_hours'));
  select * into r from public.capital_gift_roster(p_now, p_player) g;
  if r.player_id is null or r.cap_id is null then   -- not on it; or a country with no capital gives nothing
    return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
  end if;
    begin
      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, 'CAPITAL_GIFT', r.capital, null, false,
                 jsonb_build_object('kind', 'CAPITAL_GIFT', 'payload', jsonb_build_object(
                   'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth)));
      if v_res ? 'waiting' then
        raise exception using errcode = 'ZG234', message = (v_res->>'gap');
      end if;
      insert into public.capital_gifts (port_id, player_id, ducats, called_from, created_at)
      values (r.cap_id, r.player_id, r.capital, (v_res->>'called_from')::uuid, p_now);
      v_n := v_n + 1;
      v_d := v_d + r.capital;
      perform public.port_fee_collect(r.player_id, null, r.capital);   -- 0241: the gift pays what she owes first
    exception
      when sqlstate 'ZG234' then
        -- THE REALM CANNOT PAY: no money moved, no event written; one GIFT_WAITING a day
        v_wait := v_wait + 1;
        if not exists (select 1 from public.events e where e.player_id = r.player_id and e.kind = 'GIFT_WAITING'
                         and e.created_at > p_now - v_cool) then
          perform public.emit_event(r.player_id, 'GIFT_WAITING', jsonb_build_object(
            'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth, 'gap', sqlerrm::bigint));
        end if;
      when others then
        v_fail := v_fail + 1;
        v_notes := v_notes || jsonb_build_array(jsonb_build_object('step', 'capital_gift', 'player', r.player_id, 'error', sqlerrm));
    end;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
end $fn$;
comment on function public.capital_gift_one(timestamptz, uuid) is
  '0267: one company''s turn in the capital''s gift pass (0234 / 0241''s loop body, verbatim), she read through public.capital_gift_roster. Server-only; called by public.capital_gift_pass and public.tick_reconcile.';
revoke all on function public.capital_gift_one(timestamptz, uuid) from public, anon, authenticated;

create or replace function public.capital_gift_pass(p_now timestamp with time zone, p_only uuid default null::uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0234 (docs/CLOSED_ECONOMY.md §5.2): null while the economy is open. Lit: every broke merchant company (worth under
-- merchant_broke_pct × capital; none in the last gift_cooldown_hours; under gift_max_per_week in 7 days), at most
-- gift_max_per_hour of them, gifted longest ago (or never) first, is paid her capital by her country's capital
-- (public.capital_pays). Each company in its own sub-transaction: one that fails is counted and noted, the rest go on.
-- Answers {gifted, gift_ducats, gift_waiting, failed, notes}. p_only narrows the pass to one company (a probe).
-- 0267: THE ROSTER (public.capital_gift_roster) WALKED THROUGH THE BODY (public.capital_gift_one), unchanged, in one
-- transaction; tick_reconcile walks the same two a company a transaction.
declare
  r       record;
  v_one   jsonb;
  v_n     int := 0;
  v_d     bigint := 0;
  v_wait  int := 0;
  v_fail  int := 0;
  v_notes jsonb := '[]'::jsonb;
begin
  if not public.economy_closed() then
    return null;
  end if;
  for r in select g.player_id from public.capital_gift_roster(p_now, p_only) g loop
    v_one := public.capital_gift_one(p_now, r.player_id);
    v_n := v_n + (v_one->>'gifted')::int;
    v_d := v_d + (v_one->>'gift_ducats')::bigint;
    v_wait := v_wait + (v_one->>'gift_waiting')::int;
    v_fail := v_fail + (v_one->>'failed')::int;
    v_notes := v_notes || (v_one->'notes');
  end loop;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
end $function$;

-- ── 4. TICK_RECONCILE: THE COMPANIES' STEP A COMPANY A TRANSACTION, AND THE QUAY'S TALLY (5 hunks) ──
create temp table hunks_0267 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0267 values
('public.tick_reconcile(boolean)', 1,
$h$  -- 0265: the compactor's locals left with it (public.tick_compact, every minute)
$h$,
$h$  -- 0265: the compactor's locals left with it (public.tick_compact, every minute)
  -- 0267: the companies' step a company a transaction (its deadline, set once), and the quay's tally a step
  v_cdl      timestamptz;
  v_tq       timestamptz;
  v_th       timestamptz;
  v_qt       jsonb := '{}'::jsonb;
  v_qc       jsonb := '{}'::jsonb;
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
    perform public.npc_upkeep_scope(v_deadline);
$h$,
$h$    v_tq := clock_timestamp();   -- 0267: the quay asked for
    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
    v_th := clock_timestamp();   -- 0267: the quay granted
    perform public.npc_upkeep_scope(v_deadline);
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    if p_commit then commit; end if;
  end loop;
  -- 0143: THE COMPANIES' STEP HAS ITS OWN BUDGET.$h$,
$h$    if p_commit then commit; end if;
    v_qt := public.quay_tally(v_qt, v_tq, v_th);   -- 0267
  end loop;
  -- 0143: THE COMPANIES' STEP HAS ITS OWN BUDGET.$h$),
('public.tick_reconcile(boolean)', 4,
$h$  if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
  perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
  begin
    v_step := public.npc_tend_houses(v_now);
    for h in select p.id from public.players p where p.is_npc order by p.id loop
      perform public.assert_ledger_reconciles(h.id);   -- every company's purse, before the COMMIT
    end loop;
    v_tend := public.npc_tend_sum(v_tend, v_step);
  exception when others then
    v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('step', 'companies'), sqlerrm));
  end;
  if p_commit then commit; end if;
$h$,
$h$  -- 0267: A COMPANY A TRANSACTION. The step was ONE transaction under the quay (npc_tend_houses, then every company's
  -- purse): prod 10-28 02:07-06:07 held it 5.7-8.9 s, and the beat and the lap starts waited the whole of it (06:07:30
  -- a beat waited 8.8 s; lap-start lag p95 21 s in that minute). Now the two passes' rosters are read first, outside
  -- the quay (plain reads, as npc_tend_houses read them before its first act), and each company acts in her own
  -- transaction: the quay, the hour's scope (the step's own budget, from the step's start), her act
  -- (public.npc_invest_one, then public.capital_gift_one: npc_tend_houses' two passes, in its order), HER purse
  -- checked before her COMMIT. A company that fails is rolled back alone and noted. In one transaction the step
  -- decides what npc_tend_houses decides (0267's probe); a company's purse moves only in her own act.
  v_cdl := clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds'));
  if v_on then
    for h in select ir.player_id from public.npc_invest_roster() ir loop
      v_tq := clock_timestamp();
      if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
      v_th := clock_timestamp();
      perform public.npc_upkeep_scope(v_cdl);
      begin
        v_step := public.npc_invest_one(v_now, h.player_id);
        perform public.assert_ledger_reconciles(h.player_id);   -- her purse, before her COMMIT
        v_tend := public.npc_tend_sum(v_tend, v_step);
      exception when others then
        v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('step', 'invest', 'company', h.player_id), sqlerrm));
      end;
      if p_commit then commit; end if;
      v_qc := public.quay_tally(v_qc, v_tq, v_th);
    end loop;
    for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop
      v_tq := clock_timestamp();
      if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
      v_th := clock_timestamp();
      perform public.npc_upkeep_scope(v_cdl);
      begin
        v_step := public.capital_gift_one(v_now, h.player_id);
        perform public.assert_ledger_reconciles(h.player_id);   -- her purse, before her COMMIT
        v_tend := public.npc_tend_sum(v_tend, v_step);
      exception when others then
        v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('step', 'capital_gift', 'company', h.player_id), sqlerrm));
      end;
      if p_commit then commit; end if;
      v_qc := public.quay_tally(v_qc, v_tq, v_th);
    end loop;
  end if;
$h$),
('public.tick_reconcile(boolean)', 5,
$h$          jsonb_build_object('players_checked', v_n, 'merchant_upkeep', v_upkeep, 'ms', v_ms))$h$,
$h$          jsonb_build_object('players_checked', v_n, 'merchant_upkeep', v_upkeep, 'ms', v_ms,
                             'quay', jsonb_build_object('tend', v_qt, 'companies', v_qc)))   -- 0267$h$);

create or replace function pg_temp.recut_0267(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0267 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0267 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0267(v_def, h.old);
    if v_n <> 1 then
      raise exception '0267 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0267(fn) from defs_before_0267 order by fn;

-- ── 5. THE PROBE: THE NEW WAYS, FROM THE SAME STATE (rolled back) ───────────────────────────────
-- (new) the new npc_tend_houses; (step) the companies' step as tick_reconcile now runs it, a company at a time, her
-- purse checked after her act (its loops, without the quay and the commits, which p_commit = false also drops).
do $$
declare
  v_res  jsonb;
  v_w0   jsonb := pg_temp.world_0267();
  v_tend jsonb := '{}'::jsonb;
  v_step jsonb;
  v_n    int := 0;
  h      record;
begin
  begin
    perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
    v_res := public.npc_tend_houses(now());
    raise exception using errcode = 'ZY267', message = jsonb_build_object('a', v_res, 'w', pg_temp.world_0267())::text;
  exception when sqlstate 'ZY267' then
    v_res := sqlerrm::jsonb;
  end;
  insert into probe_0267 values ('new', v_res->'a', v_res->'w', v_w0);
  begin
    if public.npc_traders_on() then
      for h in select ir.player_id from public.npc_invest_roster() ir loop
        perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
        v_step := public.npc_invest_one(now(), h.player_id);
        perform public.assert_ledger_reconciles(h.player_id);
        v_tend := public.npc_tend_sum(v_tend, v_step);
        v_n := v_n + 1;
      end loop;
      for h in select gr.player_id from public.capital_gift_roster(now()) gr loop
        perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
        v_step := public.capital_gift_one(now(), h.player_id);
        perform public.assert_ledger_reconciles(h.player_id);
        v_tend := public.npc_tend_sum(v_tend, v_step);
        v_n := v_n + 1;
      end loop;
    end if;
    raise exception using errcode = 'ZY267', message = jsonb_build_object('a', v_tend || jsonb_build_object('companies', v_n), 'w', pg_temp.world_0267())::text;
  exception when sqlstate 'ZY267' then
    v_res := sqlerrm::jsonb;
  end;
  insert into probe_0267 values ('step', v_res->'a', v_res->'w', pg_temp.world_0267());
end $$;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_old  record; v_new record; v_step record;
  v_d record; v_h record; v_pp record; v_def text; v_fn text;
  v_calls_old text[]; v_calls_new text[];
begin
  select * into v_before from before_0267;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0267 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0267 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0267(v_def, v_h.new) <> 1 then
        raise exception '0267 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0267 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0267 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from passes_before_0267 loop
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0267 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn)) from kept_0267 k)
     <> v_before.kept_md5 then
    raise exception '0267 self-assert FAIL: a function the companies'' acts run, the purse, the quay, its other holders, or a caller of the two passes moved';
  end if;

  -- (b) THE SAME CALLS. The two passes, cut, call exactly what they called (plus their own two halves): the
  -- bodies are the old loops, so every lock is taken by the same callees in the same order.
  for v_fn in select unnest(array['npc_invest', 'capital_gift_pass']) loop
    v_calls_old := array(select distinct m[1] from passes_before_0267 b,
                           regexp_matches(regexp_replace(b.def, '--[^\n]*', '', 'g'), 'public\.([a-z_]+)\s*\(', 'g') m
                          where b.fn like 'public.' || v_fn || '(%' and m[1] <> v_fn order by 1);
    v_calls_new := array(select distinct m[1] from pg_proc p,
                           regexp_matches(regexp_replace(pg_get_functiondef(p.oid), '--[^\n]*', '', 'g'), 'public\.([a-z_]+)\s*\(', 'g') m
                          where p.pronamespace = 'public'::regnamespace
                            and p.proname = any(case v_fn when 'npc_invest' then array['npc_invest', 'npc_invest_roster', 'npc_invest_one']
                                                     else array['capital_gift_pass', 'capital_gift_roster', 'capital_gift_one'] end)
                            and m[1] not in ('npc_invest', 'npc_invest_roster', 'npc_invest_one',
                                             'capital_gift_pass', 'capital_gift_roster', 'capital_gift_one')
                          order by 1);
    if v_calls_old <> v_calls_new then
      raise exception '0267 self-assert FAIL: % calls other functions than it did (before %, after %)', v_fn, v_calls_old, v_calls_new;
    end if;
  end loop;
  -- the rosters are plain reads, and no half takes a lock of its own
  for v_fn in select unnest(array['public.npc_invest_roster(uuid)', 'public.capital_gift_roster(timestamptz,uuid)',
                                  'public.npc_invest_one(timestamptz,uuid)', 'public.capital_gift_one(timestamptz,uuid)',
                                  'public.npc_invest(timestamptz)', 'public.capital_gift_pass(timestamptz,uuid)',
                                  'public.quay_tally(jsonb,timestamptz,timestamptz)']) loop
    v_def := lower(regexp_replace(replace(pg_get_functiondef(v_fn::regprocedure), E'\r', ''), '--[^\n]*', '', 'g'));
    if pg_temp.occurs_0267(v_def, 'hold_the_quay') + pg_temp.occurs_0267(v_def, 'advisory') + pg_temp.occurs_0267(v_def, ' for update')
       + pg_temp.occurs_0267(v_def, ' for share') + pg_temp.occurs_0267(v_def, ' for no key update') + pg_temp.occurs_0267(v_def, ' for key share') <> 0
       or (v_fn like '%roster%' and (pg_temp.occurs_0267(v_def, 'insert into') + pg_temp.occurs_0267(v_def, 'update public.')
                                     + pg_temp.occurs_0267(v_def, 'delete from') + pg_temp.occurs_0267(v_def, 'credit(')
                                     + pg_temp.occurs_0267(v_def, 'perform ') <> 0
                                     or (select provolatile from pg_proc where oid = v_fn::regprocedure) <> 's')) then
      raise exception '0267 self-assert FAIL: % takes a lock of its own (or a roster writes)', v_fn;
    end if;
  end loop;
  -- the halves are reached only by the two passes and the hourly step
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
                and p.prokind in ('f', 'p')
                and p.proname not in ('npc_invest', 'capital_gift_pass', 'tick_reconcile', 'npc_invest_one', 'capital_gift_one',
                                      'npc_invest_roster', 'capital_gift_roster', 'quay_tally')
                and regexp_replace(pg_get_functiondef(p.oid), '--[^\n]*', '', 'g') ~ '(npc_invest_one|capital_gift_one|npc_invest_roster|capital_gift_roster|quay_tally)\s*\(') then
    raise exception '0267 self-assert FAIL: another function runs a company''s turn';
  end if;

  -- (c) THE HOURLY STEP: the quay taken by the tend steps and by each company's two turns, never around the
  -- rosters; a commit after each; the old one-transaction step gone. The quay's other holders unchanged.
  v_def := regexp_replace(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''), '--[^\n]*', '', 'g');
  if pg_temp.occurs_0267(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 3
     or pg_temp.occurs_0267(v_def, 'if p_commit then commit; end if;') <> 3
     or pg_temp.occurs_0267(v_def, 'public.npc_tend_houses(') <> 0
     or pg_temp.occurs_0267(v_def, 'v_step := public.npc_invest_one(v_now, h.player_id);') <> 1
     or pg_temp.occurs_0267(v_def, 'v_step := public.capital_gift_one(v_now, h.player_id);') <> 1
     or pg_temp.occurs_0267(v_def, 'perform public.assert_ledger_reconciles(h.player_id);') <> 2
     or pg_temp.occurs_0267(v_def, 'public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k)') <> 1 then
    raise exception '0267 self-assert FAIL: tick_reconcile''s companies are not each in their own quay transaction';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') is distinct from v_before.quay_takers then
    raise exception '0267 self-assert FAIL: the functions that take the quay changed';
  end if;

  -- (d) THE PROBE: three ways, the same rows, the same answer
  select * into v_old from probe_0267 where how = 'old';
  select * into v_new from probe_0267 where how = 'new';
  select * into v_step from probe_0267 where how = 'step';
  if v_old.before <> v_new.before or v_new.before <> v_step.before then
    raise exception '0267 self-assert FAIL: the probe''s ways did not start from the same state (a probe was not rolled back, or the world moved under it)';
  end if;
  if v_old.world <> v_new.world or v_old.world <> v_step.world then
    raise exception '0267 self-assert FAIL: the ways left other rows (old %, new %, step %)', v_old.world, v_new.world, v_step.world;
  end if;
  if v_old.answer is distinct from v_new.answer
     or public.npc_tend_sum(coalesce(v_old.answer, '{}'::jsonb), '{}'::jsonb) <> public.npc_tend_sum(v_step.answer - 'companies', '{}'::jsonb) then
    raise exception '0267 self-assert FAIL: the ways answered otherwise (old %, new %, step %)', v_old.answer, v_new.answer, v_step.answer;
  end if;

  -- (e) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0267 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0267 self-assert FAIL: a wall moved';
  end if;

  raise notice '0267 self-assert ok: EACH COMPANY ACTS IN HER OWN TRANSACTION. tick_reconcile''s companies'' step reads the two passes'' rosters outside the quay (public.npc_invest_roster, public.capital_gift_roster: plain reads), then each company in her own transaction: the quay, the hour''s scope, her turn (public.npc_invest_one, public.capital_gift_one: the old loop bodies), her purse checked before her COMMIT (5 hunks, reverse to the pre-image, ACL / volatility / definer / config unmoved; the quay taken 3 times, by the same functions as before). npc_invest and capital_gift_pass are their roster walked through their turn, calling exactly what they called; npc_tend_houses, npc_tend, player_gift, every callee, the purse, the quay and its other holders unmoved. receipt.quay tallies each step''s holds and waits. PROBE (rolled back, from the same state): the OLD npc_tend_houses + every purse, the NEW npc_tend_houses, and the step a company at a time left byte-identical rows % and answered %. Registry unchanged; walls 0.',
    v_old.world->'n', v_step.answer - 'notes';
end $$;
