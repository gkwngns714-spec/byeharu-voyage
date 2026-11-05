-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0307 — A CAPITAL DRAWS ON ITS NATION: before it funds its cities, a capital calls the shortfall from its nation's rich cities
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: step 2 of the REVIEW at the top of docs/CITY_CONVOYS.md ("Let the capital draw on its nation's rich cities before funding").
--
-- WHY: public.crown_aid (0306) pays a short city only from what its capital holds above its reserve. Measured on prod, 2026-11-05 02:48 UTC, head 0306:
-- seven of the ten working capitals could not fund their cities while the nation held plenty elsewhere (IST capital 7,186 d. and short 993,462 d.,
-- VLL in its realm 244 M; AMS capital 106,453 d., COP 1.28 B; MRS capital 84,594 d., GOA 3.36 B).
--
-- WHAT THIS FILE DOES (CROWN_CALL, the flow public.capital_pays already uses for merchant gifts: no second mechanism, a moved kind, nothing minted):
--   1. two knobs: crown_call_share 0.10 (0 = 0306's behaviour) and crown_call_cover 20.
--   2. public.crown_call_room(port): THE gold a harbour can be called for in one run, a share of what it holds above public.city_aid_target (never
--      under its reserve, and never making it a short city), leaving crown_call_cover reserves above that. STABLE.
--   3. public.treasury_try_lock(port): public.treasury_lock's key, not waited for.
--   4. public.crown_call(short): per capital, what its short cities need less its surplus, called from its realm's harbours, the richest room first.
--   5. public.crown_aid: 4 hunks. The roster is read once; its harbours are locked; the calls run; the aid then pays out exactly as 0306 did.
--
-- LOCKS (0265, 0267, 0268 rules, read on prod): only public.tick_city calls this (city_day -> crown_aid), under no quay. Every wait stays in 0306's order
-- (a city, then its capital), and all of them now happen BEFORE the first donor is touched. A donor is never waited for: public.treasury_try_lock, and a
-- busy donor is passed over till the next hour. After that point this run takes no lock it can wait on, so a donor can sit on no cycle of waits it made:
-- not the beat's (house, then harbour), not public.capital_pays's (a realm harbour, then its capital).
--
-- NOT TOUCHED: public.city_day, public.capital_pays, public.treasury_lock, public.city_surplus, public.treasury_reserve, public.city_bid_factor, mint_guard,
-- every switch. A capital still gives only above its own reserve; the aid decides as 0306 did.
--
-- SELF-ASSERT (a probe nation of eight rolled-back harbours, and a ninth outside it; no real city, no real game step, per docs/OPS_HEALTH.md section 4): the shortfall is called
-- exactly and the capital ends exactly at its reserve; a rich capital calls nothing; the richest room pays first; the share cap holds; a donor never goes
-- under its reserve, its target or its cover; a busy donor is passed over; a capital under its reserve is made whole; knob 0 equals the pre-image of
-- 0306's body, scene by scene; the nation's sum of purses does not move; the hunks reverse; nothing else moved. THE REAL public.city_day OVER THE WHOLE
-- WORLD IS PROVED IN CI, not here: proof 17, scripts/db/proofs/17_crown_call.sql. Mutation controls: scripts/ops/harness/crown-call/proof-0307.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: two rows, three functions, one re-cut, catalog
--   reads, twenty-six probe passes. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): update public.world_config set value = '0' where key = 'crown_call_share';
--   the next hourly public.tick_city is then 0306's rule. Gold already moved stays where it went.
-- VERSION: 0307 - prod head 0306 (2026-11-05).
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
  v_nat  uuid;
  v_cap  uuid;
  v_busy uuid;
  v_all  jsonb;
  v_res  jsonb := '{}'::jsonb;
  v_x    jsonb;
  s      record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.crown_aid(uuid)') is null or to_regprocedure('public.city_aid_target(uuid)') is null
     or to_regprocedure('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)') is null then
    raise exception '0307 refuses: 0234 / 0306 (a capital pays, the aid) are not in this world';
  end if;
  if to_regprocedure('public.crown_call(jsonb)') is not null or to_regprocedure('public.crown_call_room(uuid)') is not null
     or to_regprocedure('public.treasury_try_lock(uuid)') is not null
     or exists (select 1 from public.world_config c where c.key in ('crown_call_share', 'crown_call_cover')) then
    raise exception '0307 refuses: it has been applied once';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.crown_aid(uuid)'::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
    into v_def0, v_acl0, v_cfg0
    from pg_proc p where p.oid = 'public.crown_aid(uuid)'::regprocedure;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('crown_call_share', to_jsonb(0.10),
     '0307: in one run a capital may call at most this share of what a harbour of its nation holds above public.city_aid_target (public.crown_call_room). 0 = no call: public.crown_aid is 0306''s.'),
    ('crown_call_cover', to_jsonb(20),
     '0307: a harbour called by its capital keeps at least this many of its reserves above public.city_aid_target. The reserve is 3 game days of its sale payouts and a game day is a minute, so 20 reserves are an hour of payouts: a call never brings near the reserve a city that sets its bid by it.');

  -- ── 2. WHAT A HARBOUR CAN BE CALLED FOR ──
  execute $f$
create function public.crown_call_room(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0307: THE gold a harbour can be called for in one run: crown_call_share of what it holds above public.city_aid_target (at or above its reserve, so
  -- a donor never goes under its reserve and a city the crown would top up is never a donor), leaving crown_call_cover reserves above that target.
  select greatest(0, floor(least(public.wc_num('crown_call_share') * x.above, x.above - public.wc_num('crown_call_cover') * x.reserve)))::bigint
    from (select public.treasury_balance(p_port) - public.city_aid_target(p_port) as above,
                 coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0) as reserve) x
$body$
  $f$;
  revoke all on function public.crown_call_room(uuid) from public, anon, authenticated;

  -- ── 3. A HARBOUR'S LOCK, NOT WAITED FOR ──
  execute $f$
create function public.treasury_try_lock(p_port uuid)
returns boolean
language sql
as $body$ select pg_try_advisory_xact_lock(hashtextextended('byeharu.treasury:' || p_port::text, 0)) $body$
  $f$;
  revoke all on function public.treasury_try_lock(uuid) from public, anon, authenticated;

  -- ── 4. THE CALL ──
  execute $f$
create function public.crown_call(p_short jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0307: p_short is public.crown_aid's roster, every city and capital in it already locked. Per capital: what its cities need, less its surplus (a capital
-- under its reserve makes that up too, because the aid pays only above it), called (CROWN_CALL: two public.treasury_post rows, moved, nothing minted) from
-- the harbours of its nation, the most public.crown_call_room first, each once. A donor is taken with public.treasury_try_lock and judged again under
-- that lock; a busy one is passed over till the next hour. Answers {called, donors}.
declare
  k        record;
  d        record;
  v_gap    bigint;
  v_c      bigint;
  v_called bigint := 0;
  v_donors int := 0;
begin
  for k in select x.cap, sum(x.target - public.treasury_balance(x.port_id))::bigint as need
             from jsonb_to_recordset(p_short) as x(port_id uuid, target bigint, cap uuid)
            group by x.cap
            order by x.cap loop
    v_gap := k.need - public.city_surplus(k.cap);
    continue when v_gap <= 0;
    for d in select h.id
               from public.ports h join public.port_treasury t on t.port_id = h.id
              cross join lateral (select public.crown_call_room(h.id) as room) c
              where h.kind = 'HARBOUR' and h.id <> k.cap and public.city_capital(h.id) = k.cap and c.room > 0
              order by c.room desc, h.code loop
      exit when v_gap <= 0;
      continue when not public.treasury_try_lock(d.id);
      v_c := least(v_gap, public.crown_call_room(d.id));
      continue when v_c <= 0;
      perform public.treasury_post(d.id, 'CROWN_CALL', -v_c, null, null);
      perform public.treasury_post(k.cap, 'CROWN_CALL', v_c, null, null);
      v_gap := v_gap - v_c;
      v_called := v_called + v_c;
      v_donors := v_donors + 1;
    end loop;
  end loop;
  return jsonb_build_object('called', v_called, 'donors', v_donors);
end
$body$
  $f$;
  revoke all on function public.crown_call(jsonb) from public, anon, authenticated;

  -- ── 5. THE RE-CUT OF public.crown_aid: four hunks, each occurs once ──
  v_old := array[
$h$-- call passes null. Called with the purses lit (public.city_day). Answers {aided, aid}.
$h$,
$h$  v_aid   bigint := 0;
begin
$h$,
$h$  for r in select t.port_id, a.target, public.city_capital(t.port_id) as cap
             from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
            cross join lateral (select public.city_aid_target(t.port_id) as target) a
            where a.target > 0 and public.treasury_balance(t.port_id) < a.target
              and (p_only_capital is null or public.city_capital(t.port_id) = p_only_capital)
            order by p.code loop
    continue when r.cap is null or r.cap = r.port_id;
    perform public.treasury_lock(r.port_id);
    perform public.treasury_lock(r.cap);
$h$,
$h$  return jsonb_build_object('aided', v_aided, 'aid', v_aid);
$h$];
  v_new := array[
$h$-- call passes null. Called with the purses lit (public.city_day). Answers {aided, aid, called, donors}.
-- 0307: the roster is read once, every lock it waits on is taken first, then public.crown_call fills the capitals, then the aid pays out.
$h$,
$h$  v_aid   bigint := 0;
  v_short jsonb;
  v_call  jsonb;
begin
$h$,
$h$  select coalesce(jsonb_agg(jsonb_build_object('port_id', x.port_id, 'target', x.target, 'cap', x.cap, 'code', x.code)), '[]'::jsonb) into v_short
    from (select t.port_id, a.target, public.city_capital(t.port_id) as cap, p.code
            from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
           cross join lateral (select public.city_aid_target(t.port_id) as target) a
           where a.target > 0 and public.treasury_balance(t.port_id) < a.target
             and (p_only_capital is null or public.city_capital(t.port_id) = p_only_capital)) x
   where x.cap is not null and x.cap <> x.port_id;
  for r in select x.port_id, x.cap from jsonb_to_recordset(v_short) as x(port_id uuid, cap uuid, code text) order by x.code loop
    perform public.treasury_lock(r.port_id);
    perform public.treasury_lock(r.cap);
  end loop;
  v_call := public.crown_call(v_short);
  for r in select x.port_id, x.target, x.cap from jsonb_to_recordset(v_short) as x(port_id uuid, target bigint, cap uuid, code text) order by x.code loop
$h$,
$h$  return jsonb_build_object('aided', v_aided, 'aid', v_aid) || v_call;
$h$];
  v_def := v_def0;
  for v_i in 1 .. array_length(v_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0307 self-assert FAIL: hunk % of public.crown_aid occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_n;
    end if;
    v_def := replace(v_def, v_old[v_i], v_new[v_i]);
  end loop;
  execute v_def;

  -- ── 6. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  v_def := replace(pg_get_functiondef('public.crown_aid(uuid)'::regprocedure), E'\r', '');
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0307 self-assert FAIL: hunk % is not in the new body exactly once', v_i;
    end if;
    v_def := replace(v_def, v_new[v_i], v_old[v_i]);
  end loop;
  if v_def <> v_def0 then
    raise exception '0307 self-assert FAIL: public.crown_aid does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.crown_aid(uuid)'::regprocedure) <> v_acl0
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.crown_aid(uuid)'::regprocedure) <> v_cfg0 then
    raise exception '0307 self-assert FAIL: public.crown_aid''s grants or settings moved';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.crown_call_room(uuid)'::regprocedure) <> 's'
     or not (select p.prosecdef from pg_proc p where p.oid = 'public.crown_call_room(uuid)'::regprocedure)
     or not (select p.prosecdef from pg_proc p where p.oid = 'public.crown_call(jsonb)'::regprocedure) then
    raise exception '0307 self-assert FAIL: the new functions are not what this file made';
  end if;
  if (select substring(pg_get_functiondef('public.treasury_lock(uuid)'::regprocedure) from 'hashtextextended\(.*\)\)'))
     is distinct from (select substring(pg_get_functiondef('public.treasury_try_lock(uuid)'::regprocedure) from 'hashtextextended\(.*\)\)')) then
    raise exception '0307 self-assert FAIL: public.treasury_try_lock does not take public.treasury_lock''s key';
  end if;
  if has_function_privilege('anon', 'public.crown_call_room(uuid)', 'execute') or has_function_privilege('authenticated', 'public.crown_call_room(uuid)', 'execute')
     or has_function_privilege('anon', 'public.crown_call(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.crown_call(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.treasury_try_lock(uuid)', 'execute') or has_function_privilege('authenticated', 'public.treasury_try_lock(uuid)', 'execute') then
    raise exception '0307 self-assert FAIL: a client can reach the call';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.crown_aid(uuid)'::regprocedure, 'public.crown_call(jsonb)'::regprocedure, 'public.crown_call_room(uuid)'::regprocedure, 'public.treasury_try_lock(uuid)'::regprocedure)) <> v_fn_before then
    raise exception '0307 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('crown_call_share', 'crown_call_cover')) <> v_cfg_before then
    raise exception '0307 self-assert FAIL: a world_config row moved';
  end if;

  -- ── 7. THE SELF-ASSERT: a probe nation, every row rolled back ──
  -- 0306's body, a pg_temp copy: what knob 0 must equal.
  execute replace(v_def0, 'FUNCTION public.crown_aid(', 'FUNCTION pg_temp.crown_aid_0306(');

  -- One scene: the probe purses as given, one pass (0306's body or this one), what each harbour's own flows came to, every purse, a second pass.
  execute $f$
create function pg_temp.scene_0307(p_nat uuid, p_cap uuid, p_mark bigint, p_share numeric, p_purses jsonb, p_old boolean, p_busy uuid)
returns jsonb
language plpgsql
as $b$
declare
  v_sum0  bigint;
  v_r     jsonb;
  v_seen  jsonb;
  v_again jsonb;
begin
  update public.world_config set value = to_jsonb(p_share) where key = 'crown_call_share';
  update public.port_treasury t set ducats = (p_purses ->> p.code)::bigint from public.ports p where p.id = t.port_id and p_purses ? p.code;
  if p_busy is not null then
    execute format('create or replace function public.treasury_try_lock(p_port uuid) returns boolean language sql as %L',
                   format('select p_port <> %L::uuid', p_busy));
  end if;
  select sum(public.treasury_balance(a.port_id)) into v_sum0 from public.port_allegiance a where a.nation_id = p_nat;
  v_r := case when p_old then pg_temp.crown_aid_0306(p_cap) else public.crown_aid(p_cap) end;
  v_seen := jsonb_build_object(
    'flow_aid', coalesce((select jsonb_object_agg(x.code, x.d) from (select p.code, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
                       where f.id > p_mark and f.created_at = now() and f.kind = 'CROWN_AID' and p.code like 'QY_' group by p.code) x), '{}'::jsonb),
    'flow_call', coalesce((select jsonb_object_agg(x.code, x.d) from (select p.code, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > p_mark and f.created_at = now() and f.kind = 'CROWN_CALL' and p.code like 'QY_' group by p.code) x), '{}'::jsonb),
    'purse', (select jsonb_object_agg(p.code, public.treasury_balance(p.id)) from public.ports p where p.code like 'QY_'),
    'under_reserve', (select count(*) from public.ports p join public.port_treasury t on t.port_id = p.id
                       where p.code in ('QYD', 'QYE', 'QYF', 'QYG', 'QYH') and public.treasury_balance(p.id) < t.reserve),
    'under_target', (select count(*) from public.ports p where p.code in ('QYD', 'QYE', 'QYF', 'QYG', 'QYH') and public.treasury_balance(p.id) < public.city_aid_target(p.id)),
    'bid', (select min(public.city_bid_factor(p.id)) from public.ports p where p.code in ('QYD', 'QYE', 'QYF', 'QYG', 'QYH')),
    'sum_moved', (select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a where a.nation_id = p_nat) - v_sum0);
  v_again := case when p_old then pg_temp.crown_aid_0306(p_cap) else public.crown_aid(p_cap) end;
  return v_r || v_seen || jsonb_build_object('again', v_again);
end
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX7', 'Probe 0307', 'Z', 'QYA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QYA'), ('QYB'), ('QYC'), ('QYD'), ('QYE'), ('QYF'), ('QYG'), ('QYH'), ('QYZ')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap  := (select p.id from public.ports p where p.code = 'QYA');
    v_busy := (select p.id from public.ports p where p.code = 'QYD');
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code like 'QY_' and p.code <> 'QYZ';
    insert into public.port_treasury (port_id, ducats, reserve, earned_day)
    select p.id, r.ducats, r.reserve, world.game_day()
      from (values ('QYA', 0, 7777), ('QYB', 0, 0), ('QYC', 0, 900), ('QYD', 0, 1000), ('QYE', 0, 0), ('QYF', 0, 100000), ('QYG', 0, 100000), ('QYH', 0, 0),
                   ('QYZ', 1000000000000, 0)) r(code, ducats, reserve)   -- QYZ, the richest of all, is outside the nation
      join public.ports p on p.code = r.code;

    -- QYB and QYC are the short cities, 98,900 d. between them. QYD, QYE rich donors. QYF is 50,000 d. above 20 reserves over its target, QYG just above
    -- its reserve, QYH exactly at the floor.
    for s in select * from (values
      ('rich',   0.10::numeric, 10000000, 10000000, 5000000, 2150000, 150000, null::uuid),   -- the capital can pay: nothing is called
      ('short',  0.10::numeric,    12777, 10000000, 5000000, 2150000, 150000, null),         -- 5,000 above its reserve: the rest, from the richest
      ('capped', 0.10::numeric,    12777,   350000,  550000,  120000, 150000, null),         -- every donor to its share, and it is not enough
      ('under',  0.10::numeric,     1000, 10000000, 5000000, 2150000, 150000, null),         -- the capital 6,777 under its reserve
      ('cover',  0.10::numeric,    12777,    60000,   60000, 2150000, 150000, null),         -- QYF to its cover, not to its share
      ('thin',   0.10::numeric,    12777,    51000,   52000,  110000, 100500, null),         -- every donor near its line: only QYE's 200 d. can be called
      ('busy',   0.10::numeric,    12777, 10000000, 5000000, 2150000, 150000, v_busy),       -- the richest is busy: passed over
      ('rich0',  0::numeric,    10000000, 10000000, 5000000, 2150000, 150000, null),
      ('short0', 0::numeric,       12777, 10000000, 5000000, 2150000, 150000, null),
      ('under0', 0::numeric,        1000, 10000000, 5000000, 2150000, 150000, null)
    ) v(name, share, a, d, e, f, g, busy) loop
      begin
        raise exception using errcode = 'ZX307', message = pg_temp.scene_0307(v_nat, v_cap, v_mark, s.share,
          jsonb_build_object('QYA', s.a, 'QYB', 1000, 'QYC', 100, 'QYD', s.d, 'QYE', s.e, 'QYF', s.f, 'QYG', s.g, 'QYH', 50000), false, s.busy)::text;
      exception when sqlstate 'ZX307' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
      if s.share = 0 then    -- the same scene through 0306's own body
        begin
          raise exception using errcode = 'ZX307', message = pg_temp.scene_0307(v_nat, v_cap, v_mark, s.share,
            jsonb_build_object('QYA', s.a, 'QYB', 1000, 'QYC', 100, 'QYD', s.d, 'QYE', s.e, 'QYF', s.f, 'QYG', s.g, 'QYH', 50000), true, null)::text;
        exception when sqlstate 'ZX307' then v_res := v_res || jsonb_build_object(s.name || '_old', sqlerrm::jsonb); end;
      end if;
    end loop;

    raise exception using errcode = 'ZX307', message = v_res::text;
  exception when sqlstate 'ZX307' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0307(uuid, uuid, bigint, numeric, jsonb, boolean, uuid);
  drop function pg_temp.crown_aid_0306(uuid);

  for s in select k from jsonb_object_keys(v_all) k loop
    if (v_all -> s.k ->> 'sum_moved')::bigint <> 0 then
      raise exception '0307 self-assert FAIL: the sum of purses moved in %: %', s.k, v_all -> s.k;
    end if;
    if (v_all -> s.k ->> 'under_reserve')::int <> 0 then
      raise exception '0307 self-assert FAIL: a donor went under its reserve in %: %', s.k, v_all -> s.k;
    end if;
    if (v_all -> s.k ->> 'under_target')::int <> 0 then
      raise exception '0307 self-assert FAIL: a donor went under its aid target in %: %', s.k, v_all -> s.k;
    end if;
    if (v_all -> s.k ->> 'bid')::numeric <> 1 then
      raise exception '0307 self-assert FAIL: a donor''s bid fell in %: %', s.k, v_all -> s.k;
    end if;
  end loop;

  v_x := v_all -> 'rich';
  if v_x -> 'flow_call' <> '{}'::jsonb or (v_x ->> 'called')::bigint <> 0 or (v_x ->> 'aid')::bigint <> 98900 then
    raise exception '0307 self-assert FAIL: a capital that could pay called: %', v_x;
  end if;
  v_x := v_all -> 'short';
  if v_x -> 'flow_call' <> '{"QYA": 93900, "QYD": -93900}'::jsonb or (v_x ->> 'called')::bigint <> 93900 or (v_x ->> 'donors')::int <> 1 then
    raise exception '0307 self-assert FAIL: the shortfall was not called exactly, from the richest: %', v_x;
  end if;
  if v_x -> 'flow_aid' <> '{"QYA": -98900, "QYB": 49000, "QYC": 49900}'::jsonb or (v_x #>> '{purse,QYA}')::bigint <> 7777 then
    raise exception '0307 self-assert FAIL: the capital did not fund its cities and stop exactly at its reserve: %', v_x;
  end if;
  if (v_x -> 'again' ->> 'called')::bigint <> 0 or (v_x -> 'again' ->> 'aided')::int <> 0 then
    raise exception '0307 self-assert FAIL: a second pass moved gold: %', v_x;
  end if;
  v_x := v_all -> 'capped';
  if v_x -> 'flow_call' <> '{"QYA": 80000, "QYD": -30000, "QYE": -50000}'::jsonb or (v_x #>> '{purse,QYA}')::bigint <> 7777
     or v_x -> 'flow_aid' <> '{"QYA": -85000, "QYB": 49000, "QYC": 36000}'::jsonb then
    raise exception '0307 self-assert FAIL: a donor gave more than its share, or the richest did not pay first: %', v_x;
  end if;
  v_x := v_all -> 'under';
  if v_x -> 'flow_call' <> '{"QYA": 105677, "QYD": -105677}'::jsonb or (v_x #>> '{purse,QYA}')::bigint <> 7777 or (v_x ->> 'aid')::bigint <> 98900 then
    raise exception '0307 self-assert FAIL: a capital under its reserve was not made whole before it funded its cities: %', v_x;
  end if;
  v_x := v_all -> 'cover';
  if v_x -> 'flow_call' <> '{"QYA": 51000, "QYE": -1000, "QYF": -50000}'::jsonb or (v_x #>> '{purse,QYF}')::bigint <> 2100000 or (v_x #>> '{purse,QYG}')::bigint <> 150000 then
    raise exception '0307 self-assert FAIL: a donor near its reserve gave: %', v_x;
  end if;
  v_x := v_all -> 'thin';
  if v_x -> 'flow_call' <> '{"QYA": 200, "QYE": -200}'::jsonb then
    raise exception '0307 self-assert FAIL: a donor near its line gave more than its share: %', v_x;
  end if;
  v_x := v_all -> 'busy';
  if v_x -> 'flow_call' <> '{"QYA": 93900, "QYE": -93900}'::jsonb then
    raise exception '0307 self-assert FAIL: a busy donor was not passed over: %', v_x;
  end if;
  for s in select k from unnest(array['rich0', 'short0', 'under0']) k loop
    if v_all -> s.k -> 'flow_call' <> '{}'::jsonb or v_all -> s.k -> 'flow_aid' <> v_all -> (s.k || '_old') -> 'flow_aid'
       or v_all -> s.k -> 'purse' <> v_all -> (s.k || '_old') -> 'purse'
       or (v_all -> s.k ->> 'aided')::int <> (v_all -> (s.k || '_old') ->> 'aided')::int
       or (v_all -> s.k ->> 'aid')::bigint <> (v_all -> (s.k || '_old') ->> 'aid')::bigint then
      raise exception '0307 self-assert FAIL: knob 0 is not 0306 in %: % %', s.k, v_all -> s.k, v_all -> (s.k || '_old');
    end if;
  end loop;

  -- nothing of the probe survives; the knobs stand at their defaults
  if exists (select 1 from public.ports p where p.code like 'QY_') or exists (select 1 from public.nations n where n.code = 'QX7')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0307 self-assert FAIL: the probe left rows behind';
  end if;
  if public.wc_num('crown_call_share') <> 0.10 or public.wc_num('crown_call_cover') <> 20
     or position('pg_try_advisory_xact_lock' in pg_get_functiondef('public.treasury_try_lock(uuid)'::regprocedure)) = 0 then
    raise exception '0307 self-assert FAIL: a knob or the try-lock is not at its default';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0307 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0307 self-assert ok: A CAPITAL DRAWS ON ITS NATION. public.crown_call, public.crown_call_room and public.treasury_try_lock made; public.crown_aid re-cut by 4 hunks, each reversed, grants unmoved; nothing else moved. Probe nation: shortfall called exactly (% d.), the capital at exactly its reserve; a rich capital called nothing; the richest paid first, each donor to its share; no donor under its reserve, target or cover, none''s bid fell; a busy donor passed over; a capital under its reserve made whole; knob 0 equals 0306''s body in three scenes; sum of purses unchanged. The real city_day over the world: proof 17, in CI. Printed, never asserted: % ms.',
    v_all -> 'short' ->> 'called', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
