-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0302 — THE OWNER FILLS THE CITY PURSES   (every harbour's purse x100, the 23 nation capitals x500; the one new gold the closed economy lets in)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ORDER (owner, 2026-11-02) ───────────────────────────────────────────────────────────────
--   "enlarge city purse by 100 fold, capital ... by 500", with NO famous-city tier. So: every harbour's city purse x 100; the 23 nation capitals
--   (public.nations.capital_port_code -> public.ports.code) x 500. Nothing else changes: no knob, no cron job, no switch, no economy rule - except the ONE
--   documented exception to the mint guard below, which exists so this file, and nothing else, can make the coin.
--
-- ── WHY THE GUARD NEEDS AN EXCEPTION (docs/CLOSED_ECONOMY.md section 0.2, 8 E7) ──────────────────────────────
--   The economy is closed and the purses are lit on prod, so public.mint_guard refuses (E_NO_NEW_GOLD) every positive post of a MINTED kind
--   (public.stats_flow_words.side = 'minted'). A purse top-up IS new money, so it must be a minted kind - the books must show it as new - and the guard must
--   let it through. Same shape as 0240's paid_by_city exception and the FAUCET exception docs/CORP_STORAGE_FORGE.md plans (:93, :183, :200):
--     * a NEW flow kind OWNER_GRANT, registered 'minted' ('New money: owner grant', ord 8): Stats counts it as new money since the close, in the open;
--     * public.mint_guard gains ONE exception, nothing else: kind OWNER_GRANT passes while the transaction-local setting byeharu.owner_grant = 'on'.
--       This file sets it for its own top-up loop only and puts it back to 'off' after. Every other minted kind stays refused whatever the setting;
--       OWNER_GRANT itself stays refused whenever the setting is not 'on'. The guard still takes THE MINT GATE (0268, shared) before it judges, so the
--       coin is made under the gate like every other coin and the economy switch still sees a world with no coin in flight.
--     * the setting is a plain GUC: a client cannot reach it (treasury_post and mint_guard are server-only, no grant), so the exception is open only to a
--       migration or a server function that sets it. No function other than this file's DO block sets it.
--   No bypass: the top-up goes through public.treasury_post, the one writer of a city purse, and treasury_post calls the guard exactly as always.
--
-- ── THE TOP-UP ──────────────────────────────────────────────────────────────────────────────────
--   For each harbour (public.ports.kind = 'HARBOUR', one public.port_treasury row each): old = public.treasury_balance(port) AT RUN TIME (the rolled purse
--   plus the flows not yet rolled - the live purse the game pays and bids against), multiplier m = 500 for a nation capital, else 100, and
--       public.treasury_post(port, 'OWNER_GRANT', (m - 1) * old)
--   so the purse becomes exactly old x m. No number is written here: the delta is computed from the balance in the transaction. A harbour at 0 stays 0
--   (treasury_post writes nothing for a zero delta). public.treasury_flows is locked EXCLUSIVE for the whole block (reads go on; a writer waits, lock_timeout 5 s),
--   so no flow lands between the balance read and the post. Everything is ONE DO block (the runner is not a transaction block): any failed assert rolls the lot back.
--
-- ── THE BOOKS ───────────────────────────────────────────────────────────────────────────────────
--   treasury_post inserts the flow (public.treasury_flows, kind OWNER_GRANT) and the 0224 hook in it hands the same delta to public.stats_live_add, so the
--   live Stats 'cities' figure and the world total move in the same transaction as the purses. tick_city (the hourly roll, :37) folds the flows into
--   treasury_daybook (by game-day and kind) and port_treasury.ducats and asserts purse = daybook as it always does. The closed economy's stamp
--   (world_config.economy_closed_total) is NOT touched: it is the world total at the close; the top-up shows as New money: owner grant on the minted side
--   of the Stats money log, which is the point. The hourly reconcile (tick_reconcile) and the Stats count (tick_stats) are not changed.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   Every function in public / cmd / world / voyage but public.mint_guard (md5 by identity, asserted); every world_config row (md5, asserted - both owner
--   switches, the stamp, every knob); every cron job and schedule (asserted); no function or grant is added.
--
-- ── BUDGET (docs/OPS_HEALTH.md section 4) ───────────────────────────────────────────────────────
--   bv-deploy.sh pauses every cron job for the whole push. statement_timeout 90 s and lock_timeout 5 s from the first statement. Work: 246 harbours, one
--   post each, two catalog reads of the function table, one sum over the unrolled flows (~12,000 rows on prod).
--
-- ── SELF-ASSERT (all inside the one block) ──────────────────────────────────────────────────────
--   (a) after: every harbour's treasury_balance = old x its multiplier (23 capitals x500, the rest x100), the harbour set unchanged, the capital count 23;
--   (b) the books: purse = rolled purse + sum of flows, the rolled purse = sum of daybook (tick_city's invariant, held before and after), the OWNER_GRANT flows
--       number the harbours that were funded and are exactly (m - 1) x old each; the live Stats 'cities' figure (base + journal) moved by exactly that sum;
--   (c) the guard, in a sub-block that closes the economy and lights the purses for itself and is ROLLED BACK (the switches are asserted as found):
--       OWNER_GRANT without the setting: refused; every other minted kind with the setting on: still refused (positive control); OWNER_GRANT with it on:
--       passes; and the setting is 'off' when the block ends;
--   (d) nothing else moved: every other function md5, world_config md5, the cron jobs, treasury_post's md5.
-- ROLLBACK (forward, a NEW migration, owner only): post a negative OWNER_GRANT per harbour (a negative post is not new gold) - the flows are history and stay.
-- VERSION: 0302 - prod head 0301 (2026-11-02).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_guard_0268 constant text := 'ea6953152d91d2a08f61a8a16388edfe';  -- md5 of pg_get_functiondef(public.mint_guard), LF-normalised, as 0268 left it (prod head 0301)
  v_def           text;
  v_fn_before     text;
  v_cfg_before    text;
  v_cron_before   text;
  v_n_cron        text;
  v_tp_before     text;
  v_n             int;
  v_caps          int;
  v_sum_old       bigint;
  v_sum_delta     bigint;
  v_cities_before bigint;
  v_cities_after  bigint;
  v_closed        jsonb;
  v_lit           jsonb;
  r               record;
  v_errm          text;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: this has not been applied; the pieces are the ones this file was cut against ──
  if to_regprocedure('public.mint_guard(text,bigint)') is null or to_regprocedure('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)') is null
     or to_regprocedure('public.treasury_balance(uuid)') is null or to_regclass('public.stats_flow_words') is null
     or to_regclass('public.port_treasury') is null or to_regclass('public.treasury_flows') is null or to_regclass('public.nations') is null then
    raise exception '0302 refuses: the purse, flow or guard machinery (0122 / 0214 / 0240 / 0268) is not in this world';
  end if;
  if exists (select 1 from public.stats_flow_words where kind = 'OWNER_GRANT') or exists (select 1 from public.treasury_flows where kind = 'OWNER_GRANT') then
    raise exception '0302 refuses: the OWNER_GRANT kind already exists - this top-up has been applied once';
  end if;
  v_def := replace(pg_get_functiondef('public.mint_guard(text,bigint)'::regprocedure), E'\r', '');
  if md5(v_def) <> c_guard_0268 then
    raise exception '0302 refuses: the live public.mint_guard is not the body this exception was cut against (md5 %)', md5(v_def);
  end if;
  if not public.city_treasury_on() and exists (select 1 from public.port_treasury where ducats > 0) then
    raise exception '0302 refuses: the city purses are dark (city_treasury_enabled false) yet some purse holds money - treasury_post would write nothing';
  end if;
  if exists (select 1 from public.port_treasury t where t.ducats <> coalesce((select sum(d.ducats) from public.treasury_daybook d where d.port_id = t.port_id), 0)) then
    raise exception '0302 refuses: a rolled purse does not equal its daybook before the top-up (tick_city invariant)';
  end if;

  -- what must not move (read once, compared after)
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.mint_guard(text,bigint)'::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  if to_regclass('cron.job') is not null then  -- pg_cron is absent from the local PGlite world; on Supabase it is there
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  v_tp_before := md5(replace(pg_get_functiondef('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'::regprocedure), E'\r', ''));

  -- ── 1. THE WORD (minted: the books show it as new money) ──
  insert into public.stats_flow_words (kind, side, word, ord) values ('OWNER_GRANT', 'minted', 'New money: owner grant', 8);

  -- ── 2. THE ONE EXCEPTION IN THE GUARD (0268's body verbatim, plus one early return) ──
  execute $mg$
create or replace function public.mint_guard(p_kind text, p_delta bigint)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
-- 0240 (docs/CLOSED_ECONOMY.md §0.2, §8 E7): NO NEW GOLD. THE one judge, asked by the two money writers (public.credit,
-- public.treasury_post) for a positive delta: while the economy is closed (and the purses lit — 0234's founding_credit
-- test), a MINTED kind (public.stats_flow_words.side = 'minted') is refused, E_NO_NEW_GOLD. Open: nothing, ever.
-- A city that pays (public.city_pays) is not asked: its credit is money moved, not made.
-- 0268: a positive minted kind first holds THE MINT GATE, shared, to the commit (public.mint_gate), and only then reads
-- the flags — in a new statement of a VOLATILE function, so on a snapshot taken after the gate is held. The switch takes
-- the gate exclusive before it reads the world total: a coin made under the open rules is inside its stamp, and a coin
-- asked for after the flip is judged by the flag the switch wrote. (0240's guard was STABLE: it read the caller's
-- snapshot, and a sale in flight across the flip minted 138 past the stamp on 2026-10-26.) The verdict is 0240's.
-- 0302: THE ONE EXCEPTION (owner's order of 2026-11-02, the city purses x100 / x500): kind OWNER_GRANT passes while
-- byeharu.owner_grant = 'on', a transaction-local setting that migration 0302 alone sets for its own top-up and puts back.
-- Every other minted kind is refused whatever the setting; OWNER_GRANT is refused whenever the setting is not 'on'.
begin
  if coalesce(p_delta, 0) > 0
     and exists (select 1 from public.stats_flow_words w where w.kind = p_kind and w.side = 'minted') then
    perform public.mint_gate(false);
    if p_kind = 'OWNER_GRANT' and coalesce(current_setting('byeharu.owner_grant', true), '') = 'on' then
      return;
    end if;
    if public.economy_closed() and public.city_treasury_on() then
      perform cmd.refuse('E_NO_NEW_GOLD',
        format('the economy is closed: no %s is made from nothing (%s d.) — a city must pay it', p_kind, p_delta),
        cmd.figures(0, p_delta, 'ducats'));
    end if;
  end if;
end $$;
$mg$;

  -- ── 3. THE TOP-UP, through the one writer ──
  lock table public.treasury_flows in exclusive mode;
  create temp table before_0302 on commit drop as
    select p.id as port_id, p.code, (n.capital_port_code is not null) as is_capital,
           case when n.capital_port_code is not null then 500 else 100 end as mult,
           public.treasury_balance(p.id) as old_bal
      from public.ports p join public.port_treasury t on t.port_id = p.id
      left join public.nations n on n.capital_port_code = p.code
     where p.kind = 'HARBOUR';
  select count(*), count(*) filter (where is_capital), sum(old_bal), sum(old_bal * (mult - 1)) into v_n, v_caps, v_sum_old, v_sum_delta from before_0302;
  if v_caps <> (select count(distinct capital_port_code) from public.nations) or v_caps <> 23 then
    raise exception '0302 FAIL: % capital harbour(s) found among % harbours, the order names 23 (nations: %)', v_caps, v_n, (select count(*) from public.nations);
  end if;
  if v_n <> (select count(*) from public.port_treasury) then
    raise exception '0302 FAIL: % harbours in the top-up but % purses', v_n, (select count(*) from public.port_treasury);
  end if;
  select coalesce((select cities from public.stats_live), 0) + coalesce((select sum(cities) from public.stats_live_deltas), 0) into v_cities_before;

  perform set_config('byeharu.owner_grant', 'on', true);
  for r in select * from before_0302 where old_bal > 0 order by port_id loop
    perform public.treasury_post(r.port_id, 'OWNER_GRANT', r.old_bal * (r.mult - 1));
  end loop;
  perform set_config('byeharu.owner_grant', 'off', true);

  -- ── 4. SELF-ASSERT ──
  select count(*) into v_n from before_0302 b where public.treasury_balance(b.port_id) <> b.old_bal * b.mult;
  if v_n <> 0 then
    raise exception '0302 self-assert FAIL: % harbour purse(s) are not old x multiplier', v_n;
  end if;
  if (select count(*) from public.port_treasury t join public.ports p on p.id = t.port_id where p.kind = 'HARBOUR') <> (select count(*) from before_0302) then
    raise exception '0302 self-assert FAIL: the set of harbours moved';
  end if;
  select count(*) into v_n from before_0302 b
   where public.treasury_balance(b.port_id) <> (select t.ducats from public.port_treasury t where t.port_id = b.port_id)
                                              + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = b.port_id);
  if v_n <> 0 then
    raise exception '0302 self-assert FAIL: % purse(s) are not the rolled purse plus the flows', v_n;
  end if;
  if exists (select 1 from public.port_treasury t where t.ducats <> coalesce((select sum(d.ducats) from public.treasury_daybook d where d.port_id = t.port_id), 0)) then
    raise exception '0302 self-assert FAIL: a rolled purse no longer equals its daybook';
  end if;
  if (select count(*) from public.treasury_flows where kind = 'OWNER_GRANT') <> (select count(*) from before_0302 where old_bal > 0)
     or (select coalesce(sum(ducats), 0) from public.treasury_flows where kind = 'OWNER_GRANT') <> v_sum_delta
     or exists (select 1 from public.treasury_flows f join before_0302 b using (port_id) where f.kind = 'OWNER_GRANT' and f.ducats <> b.old_bal * (b.mult - 1)) then
    raise exception '0302 self-assert FAIL: the OWNER_GRANT flows are not one post of (m-1) x old per funded harbour (expected sum %)', v_sum_delta;
  end if;
  select coalesce((select cities from public.stats_live), 0) + coalesce((select sum(cities) from public.stats_live_deltas), 0) into v_cities_after;
  if v_cities_after - v_cities_before <> v_sum_delta then
    raise exception '0302 self-assert FAIL: the live Stats cities figure moved by %, the top-up is %', v_cities_after - v_cities_before, v_sum_delta;
  end if;
  if coalesce(current_setting('byeharu.owner_grant', true), '') <> 'off' then
    raise exception '0302 self-assert FAIL: byeharu.owner_grant was not put back';
  end if;

  -- (c) THE GUARD, closed and lit for this sub-block only, then rolled back by a sentinel exception
  v_closed := public.wc('economy_closed');
  v_lit := public.wc('city_treasury_enabled');
  begin
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
    if not (public.economy_closed() and public.city_treasury_on()) then
      raise exception '0302 self-assert FAIL: the probe could not close and light the world';
    end if;
    -- (c1) OWNER_GRANT with the setting off: refused
    begin
      perform public.mint_guard('OWNER_GRANT', 1);
      raise exception '0302 self-assert FAIL: OWNER_GRANT passed the guard with the setting off';
    exception when others then
      get stacked diagnostics v_errm = message_text;
      if v_errm not like 'E_NO_NEW_GOLD:%' then raise; end if;
    end;
    perform set_config('byeharu.owner_grant', 'on', true);
    -- (c2) every other minted kind, setting on: still refused (the positive control)
    for r in select kind from public.stats_flow_words where side = 'minted' and kind <> 'OWNER_GRANT' loop
      begin
        perform public.mint_guard(r.kind, 1);
        raise exception '0302 self-assert FAIL: minted kind % passed the guard with the owner setting on', r.kind;
      exception when others then
        get stacked diagnostics v_errm = message_text;
        if v_errm not like 'E_NO_NEW_GOLD:%' then raise; end if;
      end;
    end loop;
    -- (c3) OWNER_GRANT with the setting on: passes
    perform public.mint_guard('OWNER_GRANT', 1);
    raise exception 'PROBE_0302_ROLLBACK';
  exception when others then
    get stacked diagnostics v_errm = message_text;
    if v_errm <> 'PROBE_0302_ROLLBACK' then raise; end if;
  end;
  perform set_config('byeharu.owner_grant', 'off', true);
  if public.wc('economy_closed') is distinct from v_closed or public.wc('city_treasury_enabled') is distinct from v_lit then
    raise exception '0302 self-assert FAIL: the owner switches moved';
  end if;

  -- (d) nothing else moved
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.mint_guard(text,bigint)'::regprocedure) <> v_fn_before then
    raise exception '0302 self-assert FAIL: a function other than public.mint_guard changed';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0302 self-assert FAIL: a world_config row moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_n_cron;
    if v_n_cron is distinct from v_cron_before then
      raise exception '0302 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if md5(replace(pg_get_functiondef('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'::regprocedure), E'\r', '')) <> v_tp_before then
    raise exception '0302 self-assert FAIL: treasury_post changed';
  end if;

  raise notice '0302 self-assert ok: % harbours (% capitals x500, rest x100); purses % -> % d.; % OWNER_GRANT flows, sum % d.; Stats cities figure +%; guard: OWNER_GRANT refused without the setting, every other minted kind refused with it, OWNER_GRANT passes with it; setting off; only mint_guard changed.',
    (select count(*) from before_0302), v_caps, v_sum_old, v_sum_old + v_sum_delta, (select count(*) from before_0302 where old_bal > 0), v_sum_delta, v_cities_after - v_cities_before;
end
$m$;
