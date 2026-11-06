-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0335 — A REALM PAYS FOR ITS NAVY: a capital that cannot pay for its ships draws on its realm, the richest city first. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner question 9 of docs/dev-log/2026-11-06-a-country-has-a-navy.md, row 285, answered by the owner on 2026-11-07: "use your recommended defaults". Measured on prod, read only, 2026-11-07, head 0334: LIS, SVQ and SAK alone can pay
-- for a hull; France's realm holds 3,360 M d. and MRS has 163,526 d. above its reserve. A cargo ship's aid cannot lift a capital to a hull, so the money must be fetched from where it is.
--
-- DARK: both callers are behind `navy_enabled`, which this file does not touch. public.navy_add and public.navy_pay run only lit (public.tick_navy), so dark no line below runs, except public.crown_call's lifted read, which reads the
-- same harbours in the same order. Parity is proved, not argued: scripts/ops/harness/realm-pays/proof-0335.mjs runs the rich-cities, armed-cargo and navy scenes before and after this file, every line equal.
--
-- THE RULE, in one place, the payer: public.capital_draw. NOTHING NEW MOVES GOLD. It composes public.crown_call (0307), the flow a capital already fills itself with for its short cities: CROWN_CALL, moved, nothing minted, nothing owed;
-- the harbours of its realm, the most public.crown_call_room first, each once, each by public.treasury_try_lock and never waited for, each judged again under that lock, none taken under its reserve, its aid target or its cover. The capital
-- then pays exactly as 0331 wrote: BUILD_NAVY to the yard, NAVY_PAY to the harbour she lies at, from public.city_surplus, under its lock. A capital that can pay calls nothing.
--   BUILD: ALL OR NOTHING. A hull is one payment, so a call that cannot reach the whole cost must not happen: public.capital_can_draw asks first, with no lock, so a poor realm is never locked, and public.capital_draw(.., true) rolls its
--          own call back if a busy donor leaves it short. If it did not, each minute would walk 10 % of the realm's room into a capital that still could not build: a ratchet, not a purchase. The yard is found before any gold moves.
--   PAY:   AS FAR AS IT GOES. Ships are paid one by one, so what the realm can give is taken, and the ships it covers are paid, lowest ord first, as 0331. The need is every ship at work, so a ship at the capital, who moves no gold, counts
--          as 0331 counts her; her slice stays at the capital and the next hour's call is smaller by it. It cannot climb.
--   WAKE:  MOVES NOTHING. She costs no gold to wake, so she needs only public.capital_can_draw for her next slice; the next hour's pay fetches it.
-- WHY public.crown_call AND NOT public.capital_pays: capital_pays pays a COMPANY (public.city_pays, a house's row), and it WAITS on a realm harbour's lock. A ship has no purse and the job must not wait. crown_call is the one that fits.
-- WHY NOT THE RICH CITY PAYING THE YARD ITSELF: a donor's limits would then be judged in a second place, and a hull's cost could not be shared by two donors. The capital stays the one payer of its navy; the realm fills the capital.
--
-- ONE AUTHORITY, FOLDED. public.crown_donors is lifted out of public.crown_call, same statement: THE harbours a capital may call on, richest first. public.capital_can_draw adds up the same rows, so "can the realm pay" cannot disagree with
-- "who pays". public.crown_call keeps its roster shape: public.capital_draw passes it one line, the capital itself, with a target that is its balance plus the need, so no second loop over donors exists anywhere.
--
-- RICH CITIES (0324). This does NOT read public.rich_cities_on(). When that is lit, public.crown_aid and public.capital_pays stop calling, because a city's aid must be seen sailing; a navy's upkeep and a hull's price are moved across the
-- realm at once, as NAVY_PAY always was. So 0324's "no CROWN_CALL lit" becomes "no CROWN_CALL for a city's aid". THE SLICE THAT DELETES THE OFF ARM OF public.crown_aid MUST KEEP public.crown_call: it now has a second caller.
--
-- THE RE-CUTS (hunks of the live bodies, read on prod at head 0334; each occurs once and reverses to its pre-image; these supersede the same lines of 0307's public.crown_call and 0331's public.navy_add and public.navy_pay):
--   public.crown_call (2): its donor read, lifted; a line saying who calls it.
--   public.navy_add (4):   the header; the read before the lock; the read under the lock; the draw before a hull.
--   public.navy_pay (2):   the header; the draw before the slices are counted.
--
-- NEW: public.crown_donors, public.capital_can_draw, public.capital_draw. No table, no knob, no kind, no word, no job. crown_call_share 0, 0307's rollback, stops this too: no room, so no donor.
-- NOT TOUCHED: public.crown_call_room, public.treasury_try_lock, public.city_surplus, public.capital_pays, public.navy_commission, public.tick_navy, public.cargo_origins (it holds its own read of nearly the same rows, with a course and a
-- limit: named in the dev-log, not folded here), every switch.
--
-- LOCKS. The capital by public.treasury_try_lock, as 0331; each donor by public.treasury_try_lock, as 0307. No wait is added, so no cycle is. Both are held to the commit, and public.tick_navy does this last.
--
-- SELF-ASSERT: the catalog, then public.capital_can_draw and public.capital_draw on a probe nation of its own rolled-back harbours, with a richer harbour outside it. Purses are written straight onto the probe's own rows, so no minted kind is
-- credited: CI's economy is open and prod's closed, and this file passes the same on both. It runs no game step and touches no real harbour's purse (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 42,
-- scripts/db/proofs/42_a_realm_pays.sql, the real job and the real purses. Mutation controls: scripts/ops/harness/realm-pays/mutations-0335.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, owner only): `navy_enabled` false, the switch of the whole navy. Gold already moved stays where it went.
-- VERSION: 0335 - prod head 0334 (read 2026-11-07).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_nat  uuid;
  v_cap  uuid;
  v_mark bigint;
  v_all  jsonb;
  v_res  jsonb := '{}'::jsonb;
  v_x    jsonb;
  s      record;
  c_new_fns constant text[] := array['public.crown_donors(uuid)', 'public.capital_can_draw(uuid,bigint)', 'public.capital_draw(uuid,bigint,boolean)'];
  c_hunked constant text[] := array['public.crown_call(jsonb)', 'public.navy_add(timestamp with time zone,uuid)', 'public.navy_pay(timestamp with time zone,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.crown_donors(uuid)') is not null or to_regprocedure('public.capital_draw(uuid,bigint,boolean)') is not null then
    raise exception '0335 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.navy_add(timestamp with time zone,uuid)') is null or to_regprocedure('public.crown_call(jsonb)') is null then
    raise exception '0335 refuses: 0307 or 0331 is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 1. WHO A CAPITAL MAY CALL ON ──
  execute $f$
create function public.crown_donors(p_capital uuid)
returns table (id uuid, room bigint, rank bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0335: THE harbours a capital may call on this run and what each can give, the most public.crown_call_room first. Lifted from public.crown_call, same statement. Rank 1 is the richest city of the realm by what it may give.
  select h.id, c.room, row_number() over (order by c.room desc, h.code)
    from public.ports h join public.port_treasury t on t.port_id = h.id
   cross join lateral (select public.crown_call_room(h.id) as room) c
   where h.kind = 'HARBOUR' and h.id <> p_capital and public.city_capital(h.id) = p_capital and c.room > 0
$body$
  $f$;
  revoke all on function public.crown_donors(uuid) from public, anon, authenticated;

  -- ── 2. CAN THE REALM PAY ──
  execute $f$
create function public.capital_can_draw(p_capital uuid, p_need bigint)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0335: can p_need be laid at this capital this run: what it holds above its reserve, and what its realm can give (public.crown_donors). A capital under its reserve makes that up first, as public.crown_call does. Takes no lock, moves nothing.
  -- A capital that can pay alone reads no donor, so a rich one costs what it cost.
  select case when public.city_surplus(p_capital) >= p_need then true
              else public.city_surplus(p_capital) + coalesce((select sum(d.room) from public.crown_donors(p_capital) d), 0) >= p_need end
$body$
  $f$;
  revoke all on function public.capital_can_draw(uuid, bigint) from public, anon, authenticated;

  -- ── 3. THE DRAW ──
  execute $f$
create function public.capital_draw(p_capital uuid, p_need bigint, p_whole boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0335: THE payer rule of a navy. The caller holds the capital's lock (public.treasury_try_lock) and is about to pay p_need from public.city_surplus. If the surplus covers it nothing happens. If not, the rest is called from the realm by
-- public.crown_call, as one line of its roster, so its order, its locks and its limits are the ones every other call has. Gold moves to the capital; the capital pays. Answers whether the surplus now covers p_need.
-- p_whole: a payment that cannot be cut, a hull. If the realm falls short, a busy donor being the way that happens after public.capital_can_draw said yes, the call is rolled back and nothing has moved. Otherwise what came, stays.
declare
  v_short jsonb;
begin
  if public.city_surplus(p_capital) >= p_need then
    return true;
  end if;
  v_short := jsonb_build_array(jsonb_build_object('port_id', p_capital, 'target', public.treasury_balance(p_capital) + p_need, 'cap', p_capital));
  begin
    perform public.crown_call(v_short);
    if p_whole and public.city_surplus(p_capital) < p_need then
      raise exception using errcode = 'ZX335', message = 'the realm fell short';
    end if;
  exception when sqlstate 'ZX335' then
    return false;
  end;
  return public.city_surplus(p_capital) >= p_need;
end
$body$
  $f$;
  revoke all on function public.capital_draw(uuid, bigint, boolean) from public, anon, authenticated;

  -- ── 4. THE RE-CUTS ──
  create temp table hunks_0335 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0335 values
  ('public.crown_call(jsonb)', 1,
$h$-- that lock; a busy one is passed over till the next hour. Answers {called, donors}.
$h$,
$h$-- that lock; a busy one is passed over till the next hour. Answers {called, donors}.
-- 0335: public.capital_draw is its second caller, with a roster of one line: a capital and what its navy needs. The donors are read from public.crown_donors.
$h$),
  ('public.crown_call(jsonb)', 2,
$h$    for d in select h.id
               from public.ports h join public.port_treasury t on t.port_id = h.id
              cross join lateral (select public.crown_call_room(h.id) as room) c
              where h.kind = 'HARBOUR' and h.id <> k.cap and public.city_capital(h.id) = k.cap and c.room > 0
              order by c.room desc, h.code loop
$h$,
$h$    for d in select x.id from public.crown_donors(k.cap) x order by x.rank loop
$h$),
  ('public.navy_add(timestamp with time zone,uuid)', 1,
$h$-- BUILT, when her capital's surplus covers the class and a yard can be reached. A CAPITAL THAT CANNOT PAY JUST WAITS: nothing is written, and it is asked again next run, so a hull appears the run its capital can pay, and never before.
-- The surplus is read twice: once with no lock, so a poor capital is never locked, and again under the lock, which is what counts. A busy capital is passed over. Answers BUILT, WOKEN or null.
$h$,
$h$-- BUILT, when a yard can be reached and her capital can lay the class's cost on its surplus. A REALM THAT CANNOT PAY JUST WAITS: nothing is written, and it is asked again next run, so a hull appears the run it can be paid for, and never before.
-- 0335: "can pay" is public.capital_can_draw, the capital and its realm, and a hull draws the whole cost or nothing (public.capital_draw). A wake moves no gold: the next hour's pay fetches it.
-- It is read twice: once with no lock, so a poor realm is never locked, and again under the lock, which is what counts. A busy capital is passed over. Answers BUILT, WOKEN or null.
$h$),
  ('public.navy_add(timestamp with time zone,uuid)', 2,
$h$    continue when v_cap is null or v_st is null or public.city_surplus(v_cap) < v_need;
$h$,
$h$    continue when v_cap is null or v_st is null or not public.capital_can_draw(v_cap, v_need);
$h$),
  ('public.navy_add(timestamp with time zone,uuid)', 3,
$h$    continue when not public.treasury_try_lock(v_cap);
    continue when public.city_surplus(v_cap) < v_need;
$h$,
$h$    continue when not public.treasury_try_lock(v_cap);
    continue when not public.capital_can_draw(v_cap, v_need);
$h$),
  ('public.navy_add(timestamp with time zone,uuid)', 4,
$h$      continue when v_yard is null;
      perform public.navy_commission(r.nation_id, v_ord, v_cap, v_yard, v_st, p_now);
$h$,
$h$      continue when v_yard is null;
      continue when not public.capital_draw(v_cap, v_need, true);
      perform public.navy_commission(r.nation_id, v_ord, v_cap, v_yard, v_st, p_now);
$h$),
  ('public.navy_pay(timestamp with time zone,uuid)', 1,
$h$-- nothing. One row out and one row a harbour, so 46 stations write about 1,300 rows a day, whatever the ships. A busy capital is asked again next run. Answers the ducats moved.
$h$,
$h$-- nothing. One row out and one row a harbour, so 46 stations write about 1,300 rows a day, whatever the ships. A busy capital is asked again next run. Answers the ducats moved.
-- 0335: first the capital draws on its realm for the hour of every ship at work (public.capital_draw), as far as the realm can give; its surplus then decides, as above.
$h$),
  ('public.navy_pay(timestamp with time zone,uuid)', 2,
$h$  v_can := floor(greatest(public.city_surplus(v_cap), 0) / v_slice);
$h$,
$h$  perform public.capital_draw(v_cap, v_slice * (select count(*) from public.navy_ships_in_service n where n.nation_id = v_nat));
  v_can := floor(greatest(public.city_surplus(v_cap), 0) / v_slice);
$h$);

  for v_h in select h.fn from hunks_0335 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0335 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0335 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0335 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0335 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0335 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0335 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0335 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.prosecdef and p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> 'svs' then
    raise exception '0335 self-assert FAIL: a new function is not what this file made';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0335 self-assert FAIL: a client can reach the draw';
  end if;

  -- ── 6. THE SELF-ASSERT: a probe nation, every row rolled back. Purses are the probe's own rows, written straight, never a minted kind. ──
  execute $f$
create function pg_temp.scene_0335(p_cap uuid, p_mark bigint, p_purses jsonb, p_need bigint, p_whole boolean)
returns jsonb
language plpgsql
as $b$
declare
  v_sum0 bigint;
  v_can  boolean;
  v_ok   boolean;
begin
  update public.port_treasury t set ducats = (p_purses ->> p.code)::bigint from public.ports p where p.id = t.port_id and p_purses ? p.code;
  select sum(public.treasury_balance(p.id)) into v_sum0 from public.ports p where p.code like 'QZ_';
  v_can := public.capital_can_draw(p_cap, p_need);
  v_ok := public.capital_draw(p_cap, p_need, p_whole);
  return jsonb_build_object(
    'can', v_can, 'ok', v_ok,
    'calls', coalesce((select jsonb_object_agg(x.code, x.d) from (select p.code, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > p_mark and f.kind = 'CROWN_CALL' and p.code like 'QZ_' group by p.code) x), '{}'::jsonb),
    'other', (select count(*) from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark and f.kind <> 'CROWN_CALL' and p.code like 'QZ_'),
    'surplus', public.city_surplus(p_cap),
    'sum_moved', (select sum(public.treasury_balance(p.id)) from public.ports p where p.code like 'QZ_') - v_sum0);
end
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;   -- closed, as prod, in every world
    update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share' and value is distinct from to_jsonb(0.10);
    update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover' and value is distinct from to_jsonb(20);
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor' and value is distinct from to_jsonb(50000);
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX5', 'Probe 0335', 'Z', 'QZA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QZA'), ('QZB'), ('QZC'), ('QZZ')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap := (select p.id from public.ports p where p.code = 'QZA');
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code in ('QZA', 'QZB', 'QZC');
    insert into public.port_treasury (port_id, ducats, reserve, earned_day)
    select p.id, r.ducats, r.reserve, world.game_day()
      from (values ('QZA', 0, 7777), ('QZB', 0, 0), ('QZC', 0, 0), ('QZZ', 1000000000000, 0)) r(code, ducats, reserve)   -- QZZ, the richest of all, is outside the nation
      join public.ports p on p.code = r.code;

    -- A donor's room is 10 % of what stands above 50,000. The need is 1,000,000. The capital's reserve is 7,777, so at 1,000 d. it stands 6,777 under it.
    for s in select * from (values
      ('rich',  2007777::bigint,  10000000::bigint,   5000000::bigint, true),    -- the capital can pay: nothing is called
      ('poor',     1000::bigint, 100050000::bigint,  50050000::bigint, true),    -- the richest alone, the need and the reserve's 6,777, exactly
      ('two',      1000::bigint,   3050000::bigint,   8050000::bigint, true),    -- the richest gives its 800,000, the next the rest
      ('short',    1000::bigint,   1050000::bigint,   2050000::bigint, true),    -- 300,000 of room: a hull cannot be cut, nothing moves
      ('part',     1000::bigint,   1050000::bigint,   2050000::bigint, false)    -- 300,000 of room: an hour's pay takes what there is
    ) v(name, a, b, c, whole) loop
      begin
        raise exception using errcode = 'ZX305', message = pg_temp.scene_0335(v_cap, v_mark, jsonb_build_object('QZA', s.a, 'QZB', s.b, 'QZC', s.c), 1000000, s.whole)::text;
      exception when sqlstate 'ZX305' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
    end loop;
    raise exception using errcode = 'ZX305', message = v_res::text;
  exception when sqlstate 'ZX305' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0335(uuid, bigint, jsonb, bigint, boolean);

  for s in select k from jsonb_object_keys(v_all) k loop
    if (v_all -> s.k ->> 'sum_moved')::bigint <> 0 or (v_all -> s.k ->> 'other')::int <> 0 then
      raise exception '0335 self-assert FAIL: gold was made, or another kind moved, in %: %', s.k, v_all -> s.k;
    end if;
    if (v_all -> s.k -> 'calls') ? 'QZZ' then
      raise exception '0335 self-assert FAIL: a harbour outside the realm paid in %: %', s.k, v_all -> s.k;
    end if;
  end loop;
  v_x := v_all -> 'rich';
  if v_x -> 'calls' <> '{}'::jsonb or not (v_x ->> 'can')::boolean or not (v_x ->> 'ok')::boolean or (v_x ->> 'surplus')::bigint <> 2000000 then
    raise exception '0335 self-assert FAIL: a capital that could pay called: %', v_x;
  end if;
  v_x := v_all -> 'poor';
  if v_x -> 'calls' <> '{"QZA": 1006777, "QZB": -1006777}'::jsonb or not (v_x ->> 'can')::boolean or not (v_x ->> 'ok')::boolean or (v_x ->> 'surplus')::bigint <> 1000000 then
    raise exception '0335 self-assert FAIL: the need was not called exactly, from the richest: %', v_x;
  end if;
  v_x := v_all -> 'two';
  if v_x -> 'calls' <> '{"QZA": 1006777, "QZB": -206777, "QZC": -800000}'::jsonb or not (v_x ->> 'can')::boolean or not (v_x ->> 'ok')::boolean or (v_x ->> 'surplus')::bigint <> 1000000 then
    raise exception '0335 self-assert FAIL: the richest did not pay first, or a donor gave more than its share: %', v_x;
  end if;
  v_x := v_all -> 'short';
  if v_x -> 'calls' <> '{}'::jsonb or (v_x ->> 'can')::boolean or (v_x ->> 'ok')::boolean or (v_x ->> 'surplus')::bigint <> -6777 then
    raise exception '0335 self-assert FAIL: a hull the realm could not pay for moved gold: %', v_x;
  end if;
  v_x := v_all -> 'part';
  if v_x -> 'calls' <> '{"QZA": 300000, "QZB": -100000, "QZC": -200000}'::jsonb or (v_x ->> 'can')::boolean or (v_x ->> 'ok')::boolean or (v_x ->> 'surplus')::bigint <> 293223 then
    raise exception '0335 self-assert FAIL: an hour''s pay did not take what the realm has: %', v_x;
  end if;

  -- nothing of the probe survives, and nothing else moved
  if exists (select 1 from public.ports p where p.code like 'QZ_') or exists (select 1 from public.nations n where n.code = 'QX5') then
    raise exception '0335 self-assert FAIL: the probe left rows behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0335 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0335 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0335 self-assert ok: A REALM PAYS FOR ITS NAVY, dark behind navy_enabled. % hunks once each and reversing; no other function or knob moved. Probe nation: % d. called exactly, the richest first; a hull it could not reach moved nothing; nothing minted. No game step ran (proof 42 runs them in CI). % ms.',
    (select count(*) from hunks_0335), v_all #>> '{poor,calls,QZA}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0335;
end
$m$;
