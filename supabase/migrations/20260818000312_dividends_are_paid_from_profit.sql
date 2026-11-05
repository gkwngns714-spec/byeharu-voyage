-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0312 — DIVIDENDS ARE PAID FROM PROFIT: 9 % of what was paid, per REAL day, and never more than the city earned that day
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05 ("yes do all"): city purses must rise; fix dividends. docs/dev-log/2026-11-05-dividends.md holds the measurements.
--
-- WHY (measured on prod, read-only, 2026-11-05, head 0310). The live body of public.tick_city step 6 was
--     due = paid * works_coupon_pct (0.003) * (today - accrued_day) * influence mult;   payable = least(sum of dues, city_surplus)
-- run every hour. The rate was "a game day", and a real day was 30 of those (game_day_seconds 2880). game_day_seconds went to 60 on 2026-10-30 (updated_at
-- 00:11:35 UTC, no migration) and works_coupon_pct stayed: 18 % an HOUR, 432 % a real day, so the only limit left was city_surplus. Measured:
--     about 5 M d. a day to 10-29 -> 1,075 M d. in the ONE tick of 10-30 00:37 -> 951 M on 11-02 (the day 0302 multiplied the purses) -> 585 M a day now,
--     on city_shares.paid 693 M. The "84 % a day" is the surplus limit biting, not a rate.
-- A SECOND CAUSE: the 10-30 sweep. game_day() is epoch / game_day_seconds, so the clock change moved "today" by 29 million days and (today - accrued_day)
-- was 29 million days of coupons in one tick: every city's whole surplus. Any scale that keeps reading that index can do it again, so the index is now
-- only ever a bounded fraction of a real day.
--
-- WHAT THIS FILE DOES
--   1. one knob: works_coupon_day 0.09, of what was paid, per REAL day; works_coupon_pct goes. 0 pays nothing.
--   2. port_treasury.profit: the city's own net since its last coupon day, added in the ROLL (the one place a flow enters a purse). NOT read from
--      public.treasury_daybook: treasury_days_kept is 30 game days, 30 minutes today, so step 2 CARRY has eaten half an hour-old roll before step 6 runs.
--      port_treasury.coupon_day: the real day (UTC) of the last coupon.
--   3. public.real_day(at), public.flow_is_profit(kind), public.city_coupons(port, now): the coupon, moved whole out of step 6 so it runs on a probe.
--   4. public.tick_city: 3 hunks. The roll adds profit; step 6 calls public.city_coupons for each harbour once per real day.
--
-- THE RULE: once a real day, the first tick of a new UTC day (00:37), each harbour pays
--     payable = least(sum of dues, city_surplus, profit);  a loss pays nothing; profit and coupon_day reset whether it paid or not; nothing is owed.
-- DECIDED BY DEFAULT (owner may reverse):
--   - ONCE A DAY, not hourly. An hourly limit cannot hold "a day's dividends never exceed the day's net": hour 1 earns 100 and pays it, hour 2 loses 100,
--     the day netted 0 and paid 100. Paying once is the only exact form. Holders collect at arrival as before; their `accrued` simply grows daily.
--   - NOTHING ACCRUES AS A DEBT, and a loss does not carry: tomorrow starts at 0. An unpaid profit does not carry either.
--   - OUT OF PROFIT: CROWN_AID, CROWN_CALL, CROWN_TAX, DIVIDEND (the owner's list) and CONVOY_LOAD, CONVOY_DELIVER, CONVOY_RETURN (0309, dark: the same aid
--     by ship, "aid can never leak out as dividends"); and SHARE: share money is capital, not profit, or 0313's gold would leave again as dividends at the
--     next 00:37. DONATION is in: the owner's words are income less spending. One function to change.
--   - city_shares.accrued (1.53 B d. set aside) is the holders' money: never touched, still collected at arrival.
-- accrued_day stays: public.invest_for stamps it, and it pro-rates a holder's first part-day. It is read only as a fraction of the days since the last
-- coupon, floored at 0, so a clock change can neither sweep a purse nor stop a coupon.
--
-- NOT TOUCHED: public.collect_coupons, public.invest_for, public.influence_coupon_mult, public.city_surplus, world.town_hall (reads no rate), world.holdings,
-- every switch.
--
-- SELF-ASSERT (a probe harbour and two probe houses, rolled back; no real city, no real game step, docs/OPS_HEALTH.md section 4): 9 % a day, the same at both
-- clocks; a part-day pro rata; the profit limit; the surplus limit; a loss; nothing owed; old accrued untouched; both clock jumps; two missed days; knob 0;
-- the kinds; the hunks reverse; nothing else moved. THE REAL public.tick_city OVER THE WHOLE WORLD IS PROVED IN CI: proof 22, scripts/db/proofs/22_dividends.sql.
-- Mutation controls: scripts/ops/harness/dividends/proof-0312.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Deploy away from minute :37. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): docs/dev-log/2026-11-05-dividends.md. Stop paying at once: works_coupon_day = 0.
-- VERSION: 0312 - prod head 0311 (2026-11-05).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_old  text[];
  v_new  text[];
  v_def0 text;
  v_def  text;
  v_acl0 text;
  v_cfg0 text;
  v_fn_before  text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
  v_i    int;
  v_n    int;
  v_mark bigint;
  v_port uuid;
  v_nat  uuid;
  v_a    uuid;
  v_b    uuid;
  v_all  jsonb;
  v_res  jsonb := '{}'::jsonb;
  v_x    jsonb;
  s      record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.tick_city(timestamp with time zone)') is null or to_regprocedure('public.city_surplus(uuid)') is null
     or to_regprocedure('public.influence_coupon_mult(uuid,uuid)') is null then
    raise exception '0312 refuses: 0122 / 0123 / 0148 (the purse, the coupon) are not in this world';
  end if;
  if to_regprocedure('public.city_coupons(uuid,timestamp with time zone)') is not null or to_regprocedure('public.flow_is_profit(text)') is not null
     or to_regprocedure('public.real_day(timestamp with time zone)') is not null
     or exists (select 1 from public.world_config c where c.key = 'works_coupon_day')
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'port_treasury' and c.column_name in ('profit', 'coupon_day')) then
    raise exception '0312 refuses: it has been applied once';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.tick_city(timestamp with time zone)'::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key <> 'works_coupon_pct';
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
    into v_def0, v_acl0, v_cfg0
    from pg_proc p where p.oid = 'public.tick_city(timestamp with time zone)'::regprocedure;

  -- ── 1. THE KNOB ──
  delete from public.world_config where key = 'works_coupon_pct';
  insert into public.world_config (key, value, description) values
    ('works_coupon_day', to_jsonb(0.09),
     '0312: a share earns this share of what was paid per REAL day (0.09 = the 9 % of docs/ECONOMY_LOOP.md 3.5), whatever game_day_seconds says. Paid once a day, only from the city''s own profit (public.city_coupons). 0 = no coupons.');

  -- ── 2. THE BOOK ──
  alter table public.port_treasury
    add column profit bigint not null default 0,
    add column coupon_day int not null default 0;
  comment on column public.port_treasury.profit is
    '0312: the city''s own net since its last coupon day (public.flow_is_profit), added in the roll of public.tick_city, set to 0 by public.city_coupons. What it may pay out as dividends.';
  comment on column public.port_treasury.coupon_day is
    '0312: the real day (public.real_day) of its last coupon.';

  -- ── 3. THE RULE ──
  execute $f$
create function public.real_day(p_at timestamptz)
returns int
language sql
immutable
as $body$ select floor(extract(epoch from p_at) / 86400)::int $body$
  $f$;
  revoke all on function public.real_day(timestamptz) from public, anon, authenticated;

  execute $f$
create function public.flow_is_profit(p_kind text)
returns boolean
language sql
immutable
as $body$
  -- 0312: THE list of what is not a city's own profit: the crown's money in and out, the same money by cargo ship, the dividend itself, and share money
  -- (capital: it must not leave again as dividends). A DONATION is income.
  select p_kind not in ('CROWN_AID', 'CROWN_CALL', 'CROWN_TAX', 'DIVIDEND', 'CONVOY_LOAD', 'CONVOY_DELIVER', 'CONVOY_RETURN', 'SHARE')
$body$
  $f$;
  revoke all on function public.flow_is_profit(text) from public, anon, authenticated;

  execute $f$
create function public.city_coupons(p_port uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0312 (0123's step 6 of public.tick_city, moved): THE one place a coupon is computed. Once per real day: each row's due is works_coupon_day of what it
-- paid, for the part of the days since this harbour's last coupon that the row has been stamped for (a game-day count turned into real days, so the clock
-- may change; floored at 0 and capped at those days, so a jump of the day number can neither sweep a purse nor stop a coupon). The city pays the least of
-- what is due, what it holds above its reserve and its own profit of the period, pro rata. The shortfall is not owed. The period then closes: profit 0.
-- Answers {paid, due}.
declare
  v_today  int := world.game_day(p_now);
  v_rday   int := public.real_day(p_now);
  v_gds    numeric := public.wc_num('game_day_seconds');
  v_rate   numeric := public.wc_num('works_coupon_day');
  v_last   int;
  v_profit bigint;
  v_pay    bigint;
  v_due    bigint;
begin
  perform public.treasury_lock(p_port);   -- before the purse is judged
  select t.coupon_day, t.profit into v_last, v_profit from public.port_treasury t where t.port_id = p_port;
  if v_last is null or v_last >= v_rday then
    return jsonb_build_object('paid', 0, 'due', 0);
  end if;
  -- ONE statement, under the lock: the rows are read once (locked), their dues summed, the payable taken from the surplus and the profit, split pro rata
  -- and written, so what the rows are credited and the DIVIDEND that leaves the city are the same figure by construction.
  with d as (
    select s.kind, s.player_id,
           round(s.paid * v_rate * least(v_rday - v_last, greatest(0, (v_today - s.accrued_day) * v_gds / 86400))
                 * public.influence_coupon_mult(p_port, s.player_id))::bigint as due   -- 0148 (D10)
      from public.city_shares s where s.port_id = p_port
       for update
  ), t as (
    select coalesce(sum(d.due), 0)::bigint as total,
           least(coalesce(sum(d.due), 0), greatest(0, public.city_surplus(p_port)), greatest(0, v_profit))::bigint as payable
      from d
  ), a as (
    select d.kind, d.player_id, d.due,
           case when t.total > 0 then
             round(sum(d.due) over w * t.payable::numeric / t.total)
             - round((sum(d.due) over w - d.due) * t.payable::numeric / t.total) else 0 end::bigint as pay
      from d cross join t window w as (order by d.due, d.player_id, d.kind)
  ), u as (
    update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today
      from a where s.port_id = p_port and s.kind = a.kind and s.player_id = a.player_id
    returning a.pay, a.due
  )
  select coalesce(sum(u.pay), 0), coalesce(sum(u.due), 0) into v_pay, v_due from u;
  if v_pay > 0 then
    perform public.treasury_post(p_port, 'DIVIDEND', -v_pay, null, null);
  end if;
  update public.port_treasury t set profit = 0, coupon_day = v_rday where t.port_id = p_port;
  return jsonb_build_object('paid', v_pay, 'due', v_due);
end
$body$
  $f$;
  revoke all on function public.city_coupons(uuid, timestamptz) from public, anon, authenticated;

  -- ── 4. THE RE-CUT OF public.tick_city: three hunks, each occurs once ──
  v_old := array[
$h$  v_day     jsonb := '{}'::jsonb;   -- 0172: the day's crown share, earnings and aid
begin
$h$,
$h$       set ducats = t.ducats + s.net, rolled_at = p_now, updated_at = now(),
           invested = case when t.invested is null then null else greatest(0, t.invested + s.inflow) end   -- 0245 (E5)
      from (select f.port_id, sum(f.ducats) as net,
                   coalesce(sum(f.ducats) filter (where f.kind in ('SHARE', 'DONATION')), 0) as inflow
              from f group by 1) s
$h$,
$h$  -- 6. COUPONS (0123, lit): each row's due since its coupon day; a city pays what it holds above
  --    its reserve, pro rata; the shortfall is not owed; accrued_day advances regardless.
  v_t := clock_timestamp();
  if v_lit then
    begin
      for hp in select distinct s.port_id from public.city_shares s
                 where s.accrued_day < v_today order by s.port_id loop
        perform public.treasury_lock(hp.port_id);   -- before the purse is judged
        -- ONE statement, under the lock: the rows are read once (locked), their dues summed, the
        -- payable taken from the surplus, split pro rata and written — so what the rows are
        -- credited and the DIVIDEND that leaves the city are the same figure by construction.
        with d as (
          select s.kind, s.player_id,
                 round(s.paid * public.wc_num('works_coupon_pct') * (v_today - s.accrued_day)
                       * public.influence_coupon_mult(hp.port_id, s.player_id))::bigint as due   -- 0148 (D10)
            from public.city_shares s where s.port_id = hp.port_id and s.accrued_day < v_today
             for update
        ), t as (
          select coalesce(sum(d.due), 0)::bigint as total,
                 least(coalesce(sum(d.due), 0), greatest(0, public.city_surplus(hp.port_id)))::bigint as payable
            from d
        ), a as (
          select d.kind, d.player_id, d.due,
                 case when t.total > 0 then
                   round(sum(d.due) over w * t.payable::numeric / t.total)
                   - round((sum(d.due) over w - d.due) * t.payable::numeric / t.total) else 0 end::bigint as pay
            from d cross join t window w as (order by d.due, d.player_id, d.kind)
        ), u as (
          update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today
            from a where s.port_id = hp.port_id and s.kind = a.kind and s.player_id = a.player_id
          returning a.pay, a.due
        )
        select coalesce(sum(u.pay), 0), coalesce(sum(u.due), 0) into v_pay, v_due from u;
        if v_pay > 0 then
          perform public.treasury_post(hp.port_id, 'DIVIDEND', -v_pay, null, null);
        end if;
        v_paid := v_paid + v_pay;
$h$];
  v_new := array[
$h$  v_day     jsonb := '{}'::jsonb;   -- 0172: the day's crown share, earnings and aid
  v_rday    int := public.real_day(p_now);   -- 0312: the day a coupon is paid on
  v_c       jsonb;
begin
$h$,
$h$       set ducats = t.ducats + s.net, rolled_at = p_now, updated_at = now(),
           profit = t.profit + s.earned,   -- 0312: what public.city_coupons may pay out; the daybook keeps too few days to say
           invested = case when t.invested is null then null else greatest(0, t.invested + s.inflow) end   -- 0245 (E5)
      from (select f.port_id, sum(f.ducats) as net,
                   coalesce(sum(f.ducats) filter (where public.flow_is_profit(f.kind)), 0) as earned,
                   coalesce(sum(f.ducats) filter (where f.kind in ('SHARE', 'DONATION')), 0) as inflow
              from f group by 1) s
$h$,
$h$  -- 6. COUPONS (0123, lit; 0312): once per real day, per harbour, public.city_coupons: what is due, from what it holds above its reserve and from its own
  --    profit of the period; the shortfall is not owed. Harbours with no holder close their period too.
  v_t := clock_timestamp();
  if v_lit then
    begin
      for hp in select t.port_id from public.port_treasury t where t.coupon_day < v_rday order by t.port_id loop
        v_c := public.city_coupons(hp.port_id, p_now);
        v_pay := (v_c ->> 'paid')::bigint;
        v_due := (v_c ->> 'due')::bigint;
        v_paid := v_paid + v_pay;
$h$];
  v_def := v_def0;
  for v_i in 1 .. array_length(v_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0312 self-assert FAIL: hunk % of public.tick_city occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_n;
    end if;
    v_def := replace(v_def, v_old[v_i], v_new[v_i]);
  end loop;
  execute v_def;

  -- ── 5. THE START: every harbour's first period opens now; nothing owed from before ──
  update public.port_treasury set coupon_day = public.real_day(now());

  -- ── 6. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  v_def := replace(pg_get_functiondef('public.tick_city(timestamp with time zone)'::regprocedure), E'\r', '');
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0312 self-assert FAIL: hunk % is not in the new body exactly once', v_i;
    end if;
    v_def := replace(v_def, v_new[v_i], v_old[v_i]);
  end loop;
  if v_def <> v_def0 then
    raise exception '0312 self-assert FAIL: public.tick_city does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.tick_city(timestamp with time zone)'::regprocedure) <> v_acl0
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.tick_city(timestamp with time zone)'::regprocedure) <> v_cfg0 then
    raise exception '0312 self-assert FAIL: public.tick_city''s grants or settings moved';
  end if;
  if position('works_coupon_pct' in pg_get_functiondef('public.tick_city(timestamp with time zone)'::regprocedure)) > 0 then
    raise exception '0312 self-assert FAIL: public.tick_city still reads the old rate';
  end if;
  if has_function_privilege('anon', 'public.city_coupons(uuid,timestamp with time zone)', 'execute') or has_function_privilege('authenticated', 'public.city_coupons(uuid,timestamp with time zone)', 'execute')
     or has_function_privilege('anon', 'public.flow_is_profit(text)', 'execute') or has_function_privilege('authenticated', 'public.flow_is_profit(text)', 'execute')
     or has_function_privilege('anon', 'public.real_day(timestamp with time zone)', 'execute') or has_function_privilege('authenticated', 'public.real_day(timestamp with time zone)', 'execute') then
    raise exception '0312 self-assert FAIL: a client can reach the coupon';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.tick_city(timestamp with time zone)'::regprocedure, 'public.city_coupons(uuid,timestamp with time zone)'::regprocedure,
                           'public.flow_is_profit(text)'::regprocedure, 'public.real_day(timestamp with time zone)'::regprocedure)) <> v_fn_before then
    raise exception '0312 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'works_coupon_day') <> v_cfg_before then
    raise exception '0312 self-assert FAIL: a world_config row moved';
  end if;

  -- ── 7. THE SELF-ASSERT: the kinds ──
  if (select string_agg(k, ',' order by k) from unnest(array['CROWN_AID', 'CROWN_CALL', 'CROWN_TAX', 'DIVIDEND', 'CONVOY_LOAD', 'CONVOY_DELIVER', 'CONVOY_RETURN', 'SHARE']) k
       where public.flow_is_profit(k)) is not null then
    raise exception '0312 self-assert FAIL: aid, capital or a dividend counts as profit';
  end if;
  if (select count(*) from unnest(array['BUY', 'SELL', 'TAX', 'WAGES', 'PORT_FEE', 'POPULATION_TAX', 'WORKS_OUT', 'BOUNTY', 'INSURANCE_PAID', 'DONATION']) k where public.flow_is_profit(k)) <> 10 then
    raise exception '0312 self-assert FAIL: a city''s own trade is not profit';
  end if;

  -- ── 8. THE SELF-ASSERT: a probe harbour, two houses, every row rolled back ──
  -- One scene: the clock, the knob, the purse, the period and the stamps as given; one public.city_coupons; a second the same day; what they did.
  execute $f$
create function pg_temp.scene_0312(p_port uuid, p_a uuid, p_b uuid, p_mark bigint, p jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_today int;
  v_rday  int := public.real_day(now());
  v_r     jsonb;
  v_again jsonb;
begin
  update public.world_config set value = to_jsonb((p ->> 'gds')::int) where key = 'game_day_seconds';
  update public.world_config set value = to_jsonb((p ->> 'rate')::numeric) where key = 'works_coupon_day';
  v_today := world.game_day(now());
  update public.port_treasury set ducats = (p ->> 'purse')::bigint, reserve = 1000, profit = (p ->> 'profit')::bigint,
         coupon_day = v_rday - (p ->> 'days')::int where port_id = p_port;
  update public.city_shares set accrued_day = v_today + (p ->> 'stamp')::int where port_id = p_port;
  v_r := public.city_coupons(p_port, now());
  v_again := public.city_coupons(p_port, now());
  return v_r || jsonb_build_object(
    'again', v_again,
    'flow', coalesce((select sum(f.ducats) from public.treasury_flows f where f.id > p_mark and f.port_id = p_port and f.kind = 'DIVIDEND' and f.created_at = now()), 0),
    'a', (select s.accrued from public.city_shares s where s.port_id = p_port and s.player_id = p_a),
    'b', (select s.accrued from public.city_shares s where s.port_id = p_port and s.player_id = p_b),
    'left_stamps', (select count(*) from public.city_shares s where s.port_id = p_port and s.accrued_day <> v_today),
    'profit', (select t.profit from public.port_treasury t where t.port_id = p_port),
    'closed', (select t.coupon_day = v_rday from public.port_treasury t where t.port_id = p_port),
    'purse', public.treasury_balance(p_port));
end
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled' and value is distinct from 'true'::jsonb;
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select 'QZD', 'Probe QZD', t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t
    returning id into v_port;
    insert into public.port_treasury (port_id) values (v_port);
    v_nat := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0312 a', v_nat, 0, true) returning id into v_a;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0312 b', v_nat, 0, true) returning id into v_b;
    -- 1,000,000 d. and 3,000,000 d. paid: 360,000 d. due a day, 90,000 and 270,000. House a already has 555 d. set aside: its money, never touched.
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
      (v_port, 'docks', v_a, 10, 1000000, 555, 0), (v_port, 'market', v_b, 30, 3000000, 0, 0);

    for s in select * from (values
      ('full',       60,    0.09::numeric, 10000000::bigint, 1000000::bigint, 1, -1440),     -- a real day at the 60 s clock
      ('full2880',   2880,  0.09::numeric, 10000000, 1000000, 1, -30),                       -- the same day at the 2880 s clock: the same 9 %
      ('half',       60,    0.09::numeric, 10000000, 1000000, 1, -720),                      -- stamped half a day ago: half
      ('thin',       60,    0.09::numeric, 10000000, 100000,  1, -1440),                     -- the profit is the limit
      ('poor',       60,    0.09::numeric, 51000,    1000000, 1, -1440),                     -- the surplus is the limit
      ('loss',       60,    0.09::numeric, 10000000, -500,    1, -1440),                     -- a loss: nothing
      ('nil',        60,    0.09::numeric, 10000000, 0,       1, -1440),                     -- no profit: nothing
      ('jump',       60,    0.09::numeric, 10000000, 100000000, 1, -29000000),               -- the 10-30 jump: one day's coupon, not a sweep
      ('back',       60,    0.09::numeric, 10000000, 100000000, 1, 29000000),                -- the jump the other way: nothing, and the stamps heal
      ('missed',     60,    0.09::numeric, 10000000, 100000000, 2, -2880),                   -- two missed days: two coupons, on two days' profit
      ('knob0',      60,    0::numeric,    10000000, 1000000, 1, -1440)
    ) v(name, gds, rate, purse, profit, days, stamp) loop
      begin
        raise exception using errcode = 'ZX312', message = pg_temp.scene_0312(v_port, v_a, v_b, v_mark,
          jsonb_build_object('gds', s.gds, 'rate', s.rate, 'purse', s.purse, 'profit', s.profit, 'days', s.days, 'stamp', s.stamp))::text;
      exception when sqlstate 'ZX312' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
    end loop;

    raise exception using errcode = 'ZX312', message = v_res::text;
  exception when sqlstate 'ZX312' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0312(uuid, uuid, uuid, bigint, jsonb);

  for s in select k from jsonb_object_keys(v_all) k loop
    v_x := v_all -> s.k;
    if (v_x ->> 'flow')::bigint <> -(v_x ->> 'paid')::bigint or (v_x ->> 'a')::bigint - 555 + (v_x ->> 'b')::bigint <> (v_x ->> 'paid')::bigint then
      raise exception '0312 self-assert FAIL: what left the city is not what the rows were credited in %: %', s.k, v_x;
    end if;
    if (v_x ->> 'profit')::bigint <> 0 or not (v_x ->> 'closed')::boolean or (v_x ->> 'left_stamps')::int <> 0 then
      raise exception '0312 self-assert FAIL: the period did not close in %: %', s.k, v_x;
    end if;
    if (v_x -> 'again' ->> 'paid')::bigint <> 0 then
      raise exception '0312 self-assert FAIL: a second pass paid in %: %', s.k, v_x;
    end if;
    if (v_x ->> 'purse')::bigint < 1000 then
      raise exception '0312 self-assert FAIL: a purse went under its reserve in %: %', s.k, v_x;
    end if;
  end loop;

  if (v_all -> 'full' ->> 'paid')::bigint <> 360000 or (v_all -> 'full' ->> 'a')::bigint <> 90555 or (v_all -> 'full' ->> 'b')::bigint <> 270000 then
    raise exception '0312 self-assert FAIL: a real day is not 9 %% of what was paid: %', v_all -> 'full';
  end if;
  if (v_all -> 'full2880' ->> 'paid')::bigint <> 360000 then
    raise exception '0312 self-assert FAIL: the clock moved the rate: %', v_all -> 'full2880';
  end if;
  if (v_all -> 'half' ->> 'paid')::bigint <> 180000 then
    raise exception '0312 self-assert FAIL: a part-day is not pro rata: %', v_all -> 'half';
  end if;
  v_x := v_all -> 'thin';
  if (v_x ->> 'paid')::bigint <> 100000 or (v_x ->> 'due')::bigint <> 360000 or (v_x ->> 'a')::bigint <> 25555 or (v_x ->> 'b')::bigint <> 75000 then
    raise exception '0312 self-assert FAIL: dividends are not limited by the day''s profit: %', v_x;
  end if;
  if (v_all -> 'poor' ->> 'paid')::bigint <> 50000 or (v_all -> 'poor' ->> 'purse')::bigint <> 1000 then
    raise exception '0312 self-assert FAIL: the surplus no longer limits a coupon: %', v_all -> 'poor';
  end if;
  if (v_all -> 'loss' ->> 'paid')::bigint <> 0 or (v_all -> 'nil' ->> 'paid')::bigint <> 0 or (v_all -> 'loss' ->> 'a')::bigint <> 555 then
    raise exception '0312 self-assert FAIL: a loss paid, or was owed: %', v_all -> 'loss';
  end if;
  if (v_all -> 'jump' ->> 'paid')::bigint <> 360000 then
    raise exception '0312 self-assert FAIL: a jump of the day number swept the purse: %', v_all -> 'jump';
  end if;
  if (v_all -> 'back' ->> 'paid')::bigint <> 0 then
    raise exception '0312 self-assert FAIL: a stamp in the future paid: %', v_all -> 'back';
  end if;
  if (v_all -> 'missed' ->> 'paid')::bigint <> 720000 then
    raise exception '0312 self-assert FAIL: two missed days are not two coupons: %', v_all -> 'missed';
  end if;
  if (v_all -> 'knob0' ->> 'paid')::bigint <> 0 or (v_all -> 'knob0' ->> 'flow')::bigint <> 0 then
    raise exception '0312 self-assert FAIL: knob 0 paid: %', v_all -> 'knob0';
  end if;

  -- nothing of the probe survives; the knob stands at its default
  if exists (select 1 from public.ports p where p.code = 'QZD') or exists (select 1 from public.players p where p.company_name like 'Probe 0312 %')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0312 self-assert FAIL: the probe left rows behind';
  end if;
  if public.wc_num('works_coupon_day') <> 0.09 or exists (select 1 from public.world_config c where c.key = 'works_coupon_pct') then
    raise exception '0312 self-assert FAIL: the knob is not at its default';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0312 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0312 self-assert ok: DIVIDENDS ARE PAID FROM PROFIT. works_coupon_day 0.09 replaces works_coupon_pct; port_treasury.profit and coupon_day; public.real_day, public.flow_is_profit, public.city_coupons made; public.tick_city re-cut by 3 hunks, each reversed, grants unmoved; nothing else moved. Probe harbour: 9 %% a real day at both clocks; pro rata; the profit limit; the surplus limit; a loss paid nothing and nothing was owed; old accrued untouched; a day-number jump paid one day, and the other way nothing; knob 0 paid nothing. The real tick_city over the world: proof 22, in CI. Printed, never asserted: % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
