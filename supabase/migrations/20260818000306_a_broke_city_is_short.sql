-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0306 — A BROKE CITY IS SHORT: the crown tops a city up to a floor, even a city that has stopped paying sellers
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: step 1 of the REVIEW at the top of docs/CITY_CONVOYS.md ("Fix the reserve floor so a broke city counts as short").
--
-- WHY A BROKE CITY READ AS FINE: public.treasury_reserve is 3 days of the city's own recent sale payouts. A broke city pays out little, so its
-- reserve is near zero and CROWN_AID (public.city_day) judges it not short. Measured: 101 harbours under 10,000 d., 43 with zero outflow.
--
-- WHY THE FLOOR IS NOT IN public.treasury_reserve (read on prod, 2026-11-05, head 0305). port_treasury.reserve is not only the aid's yardstick:
--   public.city_bid_factor   the bid falls linearly to city_bid_floor (0.5) as the purse falls under the reserve. A floor there cuts what a player's
--                            sale pays at 121 harbours today (mean -29 %, worst -50 %), at the moment a city most needs cargo.
--   public.city_surplus      "the one figure every spender reads": capital_pays, insurance_claim, forced_home, coupons, tick_contracts' bounties, and
--                            CROWN_AID's own capital term. A floor there locks 50,000 d. of every capital's and every city's surplus.
--   world.town_hall, public.stats_watch   both print the reserve.
-- So the floor changes NEITHER the reserve NOR any of those. It enters ONE new reader, used by the aid decision alone (decided by default, owner's brief).
--
-- WHAT THIS FILE DOES:
--   1. one knob, treasury_reserve_floor, 50,000 d. (0 = today's behaviour).
--   2. public.city_aid_target(port): THE level the crown tops a city up to, greatest(the floor, the rolled reserve). STABLE.
--   3. public.crown_aid(p_only_capital): the aid loop of public.city_day MOVED out (hunk 4), the one place a city is judged short. A city under
--      its target is topped up to it from public.city_surplus(its capital), locks and order as they were. p_only_capital narrows the pass to
--      one realm (a probe; the live call passes null) so the self-assert never runs on real cities.
--   4. public.city_day calls public.crown_aid(null); it answers the same 'aided' and 'aid' keys. Five hunks, each once, each reversed.
--
-- NOT TOUCHED: public.treasury_reserve, port_treasury.reserve, city_bid_factor, city_surplus, the economy switches, mint_guard. Nothing minted:
-- CROWN_AID stays two public.treasury_post rows, out of the capital and into the city. A capital still gives only above ITS OWN reserve.
--
-- SELF-ASSERT (a probe realm of five rolled-back harbours; no real city, no real game step, per docs/OPS_HEALTH.md section 4):
--   a broke city with zero outflow reads short and gets exactly the top-up; a floor of 0 equals today's rule, city by city; a capital stops at its
--   reserve, and one under it gives nothing; the realm's sum of purses is unchanged; a second pass gives nothing; bid, surplus, reserve are the
--   same at both floors; the hunks reverse; nothing else moved. THE REAL public.city_day OVER THE WHOLE WORLD IS PROVED IN CI, not here: proof 16,
--   scripts/db/proofs/16_reserve_floor.sql. Mutation controls: scripts/ops/harness/reserve-floor/proof-0306.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: one row, two functions, one re-cut,
--   catalog reads, a few probe passes (each a 246-harbour candidate read). Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): update public.world_config set value = '0' where key = 'treasury_reserve_floor';
--   the next hourly public.tick_city is then today's rule. Gold already moved stays where it went.
-- VERSION: 0306 - prod head 0305 (2026-11-05).
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
  v_b uuid; v_c uuid; v_d uuid; v_e uuid;
  v_all  jsonb;
  v_zero jsonb;
  v_full jsonb;
  v_poor jsonb;
  v_none jsonb;
  v_r    jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.city_day(timestamptz)') is null or to_regprocedure('public.city_surplus(uuid)') is null
     or to_regprocedure('public.treasury_reserve(uuid)') is null then
    raise exception '0306 refuses: 0122 / 0172 (the purses, the crown''s aid) are not in this world';
  end if;
  if to_regprocedure('public.city_aid_target(uuid)') is not null or to_regprocedure('public.crown_aid(uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = 'treasury_reserve_floor') then
    raise exception '0306 refuses: it has been applied once';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'public.city_day(timestamptz)'::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
    into v_def0, v_acl0, v_cfg0
    from pg_proc p where p.oid = 'public.city_day(timestamptz)'::regprocedure;

  -- ── 1. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('treasury_reserve_floor', to_jsonb(50000),
     '0306: the crown tops a city of its country up to at least this many ducats (public.city_aid_target), whatever its reserve. The aid decision alone reads it: the reserve, the bid and every spender do not. 0 = the aid judges the reserve alone.');

  -- ── 2. THE ONE READER ──
  execute $f$
create function public.city_aid_target(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0306: THE level the crown tops a city up to: its rolled reserve, never under treasury_reserve_floor. A city under it is short (a broke city
  -- pays out little, so its reserve alone would call it fine). The aid decision alone reads this. The reserve itself stays what it was: it
  -- also drives the bid (public.city_bid_factor) and every spender (public.city_surplus), and the floor must move neither.
  select greatest(coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0),
                  round(public.wc_num('treasury_reserve_floor')))::bigint
$body$
  $f$;
  revoke all on function public.city_aid_target(uuid) from public, anon, authenticated;

  -- ── 3. THE AID, MOVED OUT OF public.city_day ──
  execute $f$
create function public.crown_aid(p_only_capital uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0306 (the loop of 0172's public.city_day, moved): a city under public.city_aid_target is topped up to it from what its capital holds above
-- ITS reserve (public.city_surplus). Every movement is public.treasury_post; harbours are locked (public.treasury_lock) before an outflow is
-- judged, the city before its capital. A capital is never aided by itself. p_only_capital narrows the pass to one realm: a probe's; the live
-- call passes null. Called with the purses lit (public.city_day). Answers {aided, aid}.
declare
  r       record;
  v_a     bigint;
  v_aided int := 0;
  v_aid   bigint := 0;
begin
  for r in select t.port_id, a.target, public.city_capital(t.port_id) as cap
             from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
            cross join lateral (select public.city_aid_target(t.port_id) as target) a
            where a.target > 0 and public.treasury_balance(t.port_id) < a.target
              and (p_only_capital is null or public.city_capital(t.port_id) = p_only_capital)
            order by p.code loop
    continue when r.cap is null or r.cap = r.port_id;
    perform public.treasury_lock(r.port_id);
    perform public.treasury_lock(r.cap);
    v_a := least(r.target - public.treasury_balance(r.port_id), greatest(0, public.city_surplus(r.cap)));
    if v_a > 0 then
      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
  return jsonb_build_object('aided', v_aided, 'aid', v_aid);
end
$body$
  $f$;
  revoke all on function public.crown_aid(uuid) from public, anon, authenticated;

  -- ── 4. THE RE-CUT OF public.city_day: five hunks, each occurs once ──
  v_old := array[
$h$-- Then, every call, CROWN_AID: a city of a country below its reserve is topped up to it from what the
-- capital holds above ITS reserve. Every movement is public.treasury_post; harbours are locked
$h$,
$h$  v_e      bigint;
  v_a      bigint;
  v_cities int := 0;
$h$,
$h$  v_aided  int := 0;
  v_aid    bigint := 0;
begin
$h$,
$h$  -- THE CROWN'S AID: a city under its reserve, from what its capital holds above its own
  for r in select t.port_id, t.reserve, public.city_capital(t.port_id) as cap
             from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
            where t.reserve > 0 and public.treasury_balance(t.port_id) < t.reserve
            order by p.code loop
    continue when r.cap is null or r.cap = r.port_id;
    perform public.treasury_lock(r.port_id);
    perform public.treasury_lock(r.cap);
    v_a := least(r.reserve - public.treasury_balance(r.port_id), greatest(0, public.city_surplus(r.cap)));
    if v_a > 0 then
      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
$h$,
$h$                            'aided', v_aided, 'aid', v_aid);
$h$];
  v_new := array[
$h$-- Then, every call, CROWN_AID: public.crown_aid (0306). Every movement is public.treasury_post; harbours are locked
$h$,
$h$  v_e      bigint;
  v_cities int := 0;
$h$,
$h$  v_aid    jsonb;
begin
$h$,
$h$  -- THE CROWN'S AID: public.crown_aid (0306), the one place a city is judged short
  v_aid := public.crown_aid(null);
$h$,
$h$                            'aided', v_aid -> 'aided', 'aid', v_aid -> 'aid');
$h$];
  v_def := v_def0;
  for v_i in 1 .. array_length(v_old, 1) loop
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0306 self-assert FAIL: hunk % of public.city_day occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_n;
    end if;
    v_def := replace(v_def, v_old[v_i], v_new[v_i]);
  end loop;
  execute v_def;

  -- ── 5. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  v_def := replace(pg_get_functiondef('public.city_day(timestamptz)'::regprocedure), E'\r', '');
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0306 self-assert FAIL: hunk % is not in the new body exactly once', v_i;
    end if;
    v_def := replace(v_def, v_new[v_i], v_old[v_i]);
  end loop;
  if v_def <> v_def0 then
    raise exception '0306 self-assert FAIL: public.city_day does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.city_day(timestamptz)'::regprocedure) <> v_acl0
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.city_day(timestamptz)'::regprocedure) <> v_cfg0 then
    raise exception '0306 self-assert FAIL: public.city_day''s grants or settings moved';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.city_aid_target(uuid)'::regprocedure) <> 's'
     or not (select p.prosecdef from pg_proc p where p.oid = 'public.city_aid_target(uuid)'::regprocedure)
     or not (select p.prosecdef from pg_proc p where p.oid = 'public.crown_aid(uuid)'::regprocedure) then
    raise exception '0306 self-assert FAIL: the new functions are not what this file made';
  end if;
  if has_function_privilege('anon', 'public.city_aid_target(uuid)', 'execute') or has_function_privilege('authenticated', 'public.city_aid_target(uuid)', 'execute')
     or has_function_privilege('anon', 'public.crown_aid(uuid)', 'execute') or has_function_privilege('authenticated', 'public.crown_aid(uuid)', 'execute') then
    raise exception '0306 self-assert FAIL: a client can reach the aid';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.city_day(timestamptz)'::regprocedure, 'public.city_aid_target(uuid)'::regprocedure, 'public.crown_aid(uuid)'::regprocedure)) <> v_fn_before then
    raise exception '0306 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'treasury_reserve_floor') <> v_cfg_before then
    raise exception '0306 self-assert FAIL: a world_config row moved';
  end if;

  -- ── 6. THE SELF-ASSERT: a probe realm, every row rolled back ──
  -- One pass of the aid over the probe realm at a given floor: what each harbour's own flows came to, the capital, the realm's sum, a second pass.
  execute $f$
create function pg_temp.pass_0306(p_nation uuid, p_cap uuid, p_mark bigint, p_floor bigint)
returns jsonb
language plpgsql
as $b$
declare
  v_sum0 bigint;
  v_r    jsonb;
  v_again jsonb;
begin
  update public.world_config set value = to_jsonb(p_floor) where key = 'treasury_reserve_floor';
  select sum(public.treasury_balance(a.port_id)) into v_sum0 from public.port_allegiance a where a.nation_id = p_nation;
  v_r := public.crown_aid(p_cap);
  v_again := public.crown_aid(p_cap);
  return v_r || jsonb_build_object(
    'again', v_again,
    'by', coalesce((select jsonb_object_agg(x.code, x.d)
                      from (select p.code, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
                             where f.id > p_mark and f.created_at = now() and f.kind = 'CROWN_AID'
                               and f.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = p_nation)
                             group by p.code) x), '{}'::jsonb),
    'sum_moved', (select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a where a.nation_id = p_nation) - v_sum0,
    'cap_after', public.treasury_balance(p_cap),
    'cap_reserve', (select t.reserve from public.port_treasury t where t.port_id = p_cap));
end
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX6', 'Probe 0306', 'Z', 'QXA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QXA'), ('QXB'), ('QXC'), ('QXD'), ('QXE')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap := (select p.id from public.ports p where p.code = 'QXA');
    v_b   := (select p.id from public.ports p where p.code = 'QXB');   -- broke, zero outflow, reserve 0: today it is not short
    v_c   := (select p.id from public.ports p where p.code = 'QXC');   -- under a small reserve
    v_d   := (select p.id from public.ports p where p.code = 'QXD');   -- under a reserve above the floor
    v_e   := (select p.id from public.ports p where p.code = 'QXE');   -- zero reserve, above the floor: not short
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code like 'QX_';
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) values
      (v_cap, 10000000, 7777, world.game_day()), (v_b, 1000, 0, world.game_day()), (v_c, 100, 900, world.game_day()),
      (v_d, 30000, 80000, world.game_day()), (v_e, 60000, 0, world.game_day());

    -- what the floor must not move: a sale's bid, what a spender sees, the reserve (read at both floors, before any aid)
    update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_bid_factor(p.id), public.city_surplus(p.id), public.treasury_reserve(p.id)))
      into v_r from public.ports p where p.code like 'QX_';
    v_all := jsonb_build_object('fixed0', v_r, 'target0', public.city_aid_target(v_b), 'outflow', public.city_sell_outflow(v_b));
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_bid_factor(p.id), public.city_surplus(p.id), public.treasury_reserve(p.id)))
      into v_r from public.ports p where p.code like 'QX_';
    v_all := v_all || jsonb_build_object('fixed1', v_r, 'target1', public.city_aid_target(v_b), 'target_d', public.city_aid_target(v_d));

    begin   -- floor 0: today's rule
      raise exception using errcode = 'ZX306', message = pg_temp.pass_0306(v_nat, v_cap, v_mark, 0)::text;
    exception when sqlstate 'ZX306' then v_zero := sqlerrm::jsonb; end;
    begin   -- the floor, a rich capital
      raise exception using errcode = 'ZX306', message = pg_temp.pass_0306(v_nat, v_cap, v_mark, 50000)::text;
    exception when sqlstate 'ZX306' then v_full := sqlerrm::jsonb; end;
    begin   -- the floor, a capital with 5,000 above its reserve: it stops at its reserve
      update public.port_treasury set ducats = 7777 + 5000 where port_id = v_cap;
      raise exception using errcode = 'ZX306', message = pg_temp.pass_0306(v_nat, v_cap, v_mark, 50000)::text;
    exception when sqlstate 'ZX306' then v_poor := sqlerrm::jsonb; end;
    begin   -- the floor, a capital already under its reserve: it gives nothing, and is not aided by itself
      update public.port_treasury set ducats = 1000 where port_id = v_cap;
      raise exception using errcode = 'ZX306', message = pg_temp.pass_0306(v_nat, v_cap, v_mark, 50000)::text;
    exception when sqlstate 'ZX306' then v_none := sqlerrm::jsonb; end;

    raise exception using errcode = 'ZX306', message = v_all::text;
  exception when sqlstate 'ZX306' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.pass_0306(uuid, uuid, bigint, bigint);

  if (v_all ->> 'outflow')::bigint <> 0 or (v_all ->> 'target0')::bigint <> 0 or (v_all ->> 'target1')::bigint <> 50000 or (v_all ->> 'target_d')::bigint <> 80000 then
    raise exception '0306 self-assert FAIL: the target is not greatest(floor, reserve): %', v_all;
  end if;
  if (v_all -> 'fixed0') is distinct from (v_all -> 'fixed1') or (v_all #>> '{fixed1,QXB,0}')::numeric <> 1 or (v_all #>> '{fixed1,QXB,2}')::bigint <> 0 then
    raise exception '0306 self-assert FAIL: the floor moved a bid, a surplus or a reserve: %', v_all;
  end if;
  if (v_zero ->> 'sum_moved')::bigint <> 0 or (v_full ->> 'sum_moved')::bigint <> 0 or (v_poor ->> 'sum_moved')::bigint <> 0 or (v_none ->> 'sum_moved')::bigint <> 0 then
    raise exception '0306 self-assert FAIL: the sum of purses moved: % % % %', v_zero, v_full, v_poor, v_none;
  end if;
  if v_zero -> 'by' <> '{"QXA": -50800, "QXC": 800, "QXD": 50000}'::jsonb or (v_zero ->> 'aided')::int <> 2 or (v_zero ->> 'aid')::bigint <> 50800 then
    raise exception '0306 self-assert FAIL: a floor of 0 is not today''s rule (a zero-reserve city aided, or a short one missed): %', v_zero;
  end if;
  if v_full -> 'by' <> '{"QXA": -148900, "QXB": 49000, "QXC": 49900, "QXD": 50000}'::jsonb or (v_full ->> 'aided')::int <> 3 or (v_full ->> 'aid')::bigint <> 148900 then
    raise exception '0306 self-assert FAIL: the broke city with zero outflow did not get exactly its top-up: %', v_full;
  end if;
  if (v_zero -> 'again' ->> 'aided')::int <> 0 or (v_full -> 'again' ->> 'aided')::int <> 0 then
    raise exception '0306 self-assert FAIL: a second pass gave more: % %', v_zero, v_full;
  end if;
  if v_poor -> 'by' <> '{"QXA": -5000, "QXB": 5000}'::jsonb or (v_poor ->> 'cap_after')::bigint <> (v_poor ->> 'cap_reserve')::bigint then
    raise exception '0306 self-assert FAIL: a capital did not stop exactly at its reserve: %', v_poor;
  end if;
  if v_none -> 'by' <> '{}'::jsonb or (v_none ->> 'aided')::int <> 0 or (v_none ->> 'cap_after')::bigint <> 1000 then
    raise exception '0306 self-assert FAIL: a capital under its reserve gave, or was aided: %', v_none;
  end if;

  -- nothing of the probe survives; the knob stands at its default
  if exists (select 1 from public.ports p where p.code like 'QX_') or exists (select 1 from public.nations n where n.code = 'QX6')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0306 self-assert FAIL: the probe left rows behind';
  end if;
  if public.wc_num('treasury_reserve_floor') <> 50000 then
    raise exception '0306 self-assert FAIL: the knob is not at its default';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0306 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0306 self-assert ok: A BROKE CITY IS SHORT. public.city_aid_target and public.crown_aid made; public.city_day re-cut by 5 hunks, each reversed, grants unmoved; nothing else moved. Probe realm: floor 0 = today (% aided, % d.); floor 50,000: the zero-outflow city got 49,000, % d. in all; a capital stopped at its reserve and one under it gave nothing; sum of purses unchanged; bid, surplus and reserve the same at both floors. The real city_day over the world: proof 16, in CI. Printed, never asserted: % ms.',
    v_zero ->> 'aided', v_zero ->> 'aid', v_full ->> 'aid', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
