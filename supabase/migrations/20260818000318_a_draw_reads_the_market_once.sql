-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0318 — A DRAW READS THE MARKET ONCE: a request's draw stops asking every good's daily cap one function call at a time, so byeharu-voyage:contract-wind stops spending the first seconds of every minute on the processor
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT WAS MEASURED ON PROD (docs/dev-log/2026-11-06-a-draw-reads-the-market-once.md), read-only, head 0315, the job's first 45 minutes:
--   THE JOB HOLDS NO LOCK ANYONE WAITS ON. Each post is one short transaction, and the draw before its insert locks nothing. It takes no advisory lock (a BOUNTY post has no p_player, so no public.treasury_lock) and not the quay. Wait samples at about :02 of the minute: on the processor every time it
--     was caught, never on a lock.
--   WHAT IT COSTS IS PROCESSOR TIME, AT THE WORST SECOND. A post costs about 1.5 s, nearly all of it public.contract_draw: 629 goods x world.daily_cap_remaining, each a nest of SECURITY DEFINER calls with SET (wc_num, player_skill_bonus, works_factor, city_level, game_day). Warm and alone a draw is about
--     0.75 s. pg_cron starts the job at :00 with arrivals, lap-starts, drift, compact and cargo-ships, every one a new session, so it adds 4-6.5 s of work to the only seconds that were already short.
--   THE BEATS, THE SAME SECONDS BEFORE AND AFTER: the figures are in the dev-log. In short: seconds 0-4 of the minute got slower, second 13 on did not move, and a first beat over 1 s is OLDER than the job.
--   LAP STARTS: lag p95 6.3 s -> 10.4-12.8 s: her job starts its minute later, behind the longer first beat.
-- THE FIX:
--   public.daily_cap_base (new): what a daily cap is per unit of stock_target for a house at a port, the part that does not depend on the good. Not SECURITY DEFINER, no SET, one SELECT: the planner inlines it, so a reader of the cap pays nothing for it.
--   world.daily_cap_remaining: one hunk: it reads that base. The same figure; still THE authority for one good's cap.
--   public.contract_draw: two hunks: the base once, port_goods joined once, the port's offered goods anti-joined once (public.port_offered_goods, the roster's one reading). The same candidates in the same order, so the same good, quantity and bonus for every port, day and seq: a draw stays pure.
--   public.tick_contract_wind: contract_wind_posts, the job's own count of harbours asked in a run. It was the clock that held it to about 3: 4,000 ms at about 1.5 s a post. With a cheap draw the clock would let far more through and empty city purses into escrow in minutes instead of 2 hours.
--     3 keeps the measured pace (2.74 posted a run, 2.81 asked).
-- WHAT DOES NOT CHANGE: what merchants answer, the bonus, the budget, the 6-hour wait, the cron job and its schedule, contract_wind_ms (it stays the ceiling), the read door. NOT moved off :00: a job this cheap should not need it, and a sleeping job holds a connection. If the after-check says otherwise, that is the next step.
-- SELF-ASSERT: hunks, reversal, grants, nothing else moved, cron untouched; then, every row rolled back: the old cap (a pg_temp copy of the pre-image) equals the new for every good; the old draw equals the new at 3 harbours, with a market work built and with a cap that excludes about half the goods;
--   a draw makes one works_factor call, not hundreds; the job stops at its count; 0 asks nobody. Mutation controls: scripts/ops/harness/city-requests/proof-0318.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 60 s, lock_timeout 5 s first. Work: three bodies, one function, one knob, about 6 pre-image draws at about 1 s. It writes no market row. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): the bodies back to their pre-images (digests in the PR's PROD CHECK 1), the helper and the knob dropped. To stop the job at once, no code: contract_wind_ms 0.
-- VERSION: 0318, after 0316 and 0317, which change none of these bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn    text[];
  v_old   text[];
  v_new   text[];
  v_oids  oid[];
  v_def0  jsonb := '{}'::jsonb;
  v_acl0  jsonb := '{}'::jsonb;
  v_cur   jsonb := '{}'::jsonb;
  v_def   text;
  v_i     int;
  v_n     bigint;
  v_fn_before   text;
  v_cfg_after   text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_t0    timestamptz := clock_timestamp();
  v_day   int := world.game_day();
  v_ports uuid[];
  v_port  uuid;
  v_q     uuid;
  v_who   uuid;
  v_open  int;
  v_a     jsonb;
  v_b     jsonb;
  v_s     int;
  v_track boolean;
  v_c0    bigint;
  v_c1    bigint;
  v_c2    bigint;
  v_mid   numeric;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.tick_contract_wind(boolean, uuid)') is null then
    raise exception '0318 refuses: 0315 is not in this world';
  end if;
  if to_regprocedure('public.daily_cap_base(uuid, uuid)') is not null or exists (select 1 from public.world_config where key = 'contract_wind_posts') then
    raise exception '0318 refuses: it has been applied once';
  end if;

  v_fn := array[
    'public.contract_draw(uuid,integer,integer)', 'public.contract_draw(uuid,integer,integer)',
    'world.daily_cap_remaining(uuid,uuid,uuid)',
    'public.tick_contract_wind(boolean,uuid)', 'public.tick_contract_wind(boolean,uuid)'];

  select array_agg(p.oid) into v_oids
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in (select f::regprocedure::oid from unnest(v_fn) f);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before from pg_proc p where p.oid = any (v_oids);
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def0 := v_def0 || jsonb_build_object(v_fn[v_i], replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', ''));
    v_acl0 := v_acl0 || jsonb_build_object(v_fn[v_i], (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
                                                         from pg_proc p where p.oid = v_fn[v_i]::regprocedure));
  end loop;
  v_cur := v_def0;

  -- ── 1. THE PRE-IMAGES, KEPT FOR THE COMPARISON, IN THIS SESSION ONLY ──
  execute replace(v_def0 ->> 'world.daily_cap_remaining(uuid,uuid,uuid)', 'CREATE OR REPLACE FUNCTION world.daily_cap_remaining(', 'CREATE FUNCTION pg_temp.cap_0318(');
  execute replace(replace(v_def0 ->> 'public.contract_draw(uuid,integer,integer)', 'CREATE OR REPLACE FUNCTION public.contract_draw(', 'CREATE FUNCTION pg_temp.draw_0318('),
                  'world.daily_cap_remaining(null::uuid, p_port, g.id)', 'pg_temp.cap_0318(null::uuid, p_port, g.id)');

  -- ── 2. THE KNOB AND THE HELPER ──
  insert into public.world_config (key, value, description) values
    ('contract_wind_posts', to_jsonb(3), '0318: how many harbours the byeharu-voyage:contract-wind job asks in one run. contract_wind_ms stays the ceiling on its time, but a draw no longer costs about 1,000 ms, so this is what holds the pace. 0 = it asks nobody.');
  select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) into v_cfg_after from public.world_config x;

  execute $f$
create function public.daily_cap_base(p_player uuid, p_port uuid)
returns numeric
language sql
stable
as $body$
  -- 0318: THE ONE reading of a house's daily cap per unit of a good's stock_target at a port: everything in the cap but the good. No SECURITY DEFINER and no SET, on purpose: the planner inlines this, so world.daily_cap_remaining pays nothing for it.
  select public.wc_num('daily_cap_fraction')
         * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))
         * public.works_factor(p_port, 'market', 'market_cap_per_level')   -- 0123
$body$
  $f$;
  revoke all on function public.daily_cap_base(uuid, uuid) from public, anon, authenticated;

  -- ── 3. THE HUNKS: each occurs once ──
  v_old := array[
$h$  v_u      numeric;
$h$,
$h$     cross join lateral (select world.daily_cap_remaining(null::uuid, p_port, g.id) as cap) c
     where not public.port_offers(p_port, g.id)
       and not public.culture_refuses(p.culture, g.culture_mask)
$h$,
$h$           public.wc_num('daily_cap_fraction') * pg.stock_target
             * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))
             * public.works_factor(p_port, 'market', 'market_cap_per_level')   -- 0123
$h$,
$h$  v_floor  bigint := public.wc_int('treasury_reserve_floor');
$h$,
$h$    exit when clock_timestamp() >= v_by;
    v_p := null;
$h$];
  v_new := array[
$h$  v_u      numeric;
  v_base   numeric := public.daily_cap_base(null::uuid, p_port);   -- 0318: read once, not once a good
$h$,
$h$      join public.port_goods pg on pg.port_id = p_port and pg.good_id = g.id   -- 0318: one read of the market. A house that is no one has sold nothing, so its cap is the base on the target (world.daily_cap_remaining)
      left join public.port_offered_goods(p_port) o on o.good_id = g.id
     cross join lateral (select greatest(0, v_base * pg.stock_target) as cap) c
     where o.good_id is null
       and not public.culture_refuses(p.culture, g.culture_mask)
$h$,
$h$           public.daily_cap_base(p_player, p_port) * pg.stock_target   -- 0318
$h$,
$h$  v_floor  bigint := public.wc_int('treasury_reserve_floor');
  v_posts  int := public.wc_int('contract_wind_posts');   -- 0318
$h$,
$h$    exit when clock_timestamp() >= v_by;
    exit when v_tried >= v_posts;   -- 0318: a draw is cheap now, so the clock no longer holds the pace
    v_p := null;
$h$];
  for v_i in 1 .. array_length(v_old, 1) loop
    v_def := v_cur ->> v_fn[v_i];
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0318 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fn[v_i], v_n;
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_old[v_i], v_new[v_i]));
  end loop;
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i > 1 and v_fn[v_i] = v_fn[v_i - 1];   -- several hunks to a body: one write of each
    execute v_cur ->> v_fn[v_i];
  end loop;

  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def := replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', '');
    if v_def <> v_cur ->> v_fn[v_i] then
      raise exception '0318 self-assert FAIL: % is not the body this file wrote', v_fn[v_i];
    end if;
  end loop;
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    v_def := v_cur ->> v_fn[v_i];
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0318 self-assert FAIL: hunk % is not in the new body of % exactly once', v_i, v_fn[v_i];
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_new[v_i], v_old[v_i]));
  end loop;
  if v_cur <> v_def0 then
    raise exception '0318 self-assert FAIL: a body does not reverse to its pre-image';
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fn[v_i]::regprocedure) <> v_acl0 ->> v_fn[v_i] then
      raise exception '0318 self-assert FAIL: the grants or settings of % moved', v_fn[v_i];
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (v_oids)) <> v_fn_before then
    raise exception '0318 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0318 self-assert FAIL: a trigger moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0318 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if has_function_privilege('anon', 'public.daily_cap_base(uuid, uuid)', 'execute') or has_function_privilege('authenticated', 'public.daily_cap_base(uuid, uuid)', 'execute') then
    raise exception '0318 self-assert FAIL: a client can reach the helper';
  end if;
  if public.wc_int('contract_wind_posts') <> 3 then
    raise exception '0318 self-assert FAIL: the knob is not this file''s';
  end if;
  if v_cur ->> 'public.contract_draw(uuid,integer,integer)' is null
     or replace(pg_get_functiondef('public.contract_draw(uuid,integer,integer)'::regprocedure), E'\r', '') ~ 'world\.daily_cap_remaining\(' then
    raise exception '0318 self-assert FAIL: a draw asks the cap good by good';
  end if;

  -- ── 5. THE SAME FIGURES, EVERY ROW ROLLED BACK. The harbours: the fewest open requests, none resting, none overdue, so the probe's writes meet no merchant's delivery. ──
  v_ports := array(select p.id from public.ports p
                    where p.kind = 'HARBOUR' and not exists (select 1 from public.contract_wind w where w.port_id = p.id)
                      and not exists (select 1 from public.trade_contracts c where c.port_id = p.id and c.status = 'open' and c.expires_day <= v_day)
                    order by (select count(*) from public.trade_contracts c where c.port_id = p.id and c.status = 'open'), p.code limit 3);
  if coalesce(array_length(v_ports, 1), 0) < 3 then
    raise exception '0318 self-assert FAIL: fewer than 3 probe harbours';
  end if;
  v_port := v_ports[1];
  select t.player_id into v_who from public.trade_daily t where t.port_id = v_port and t.game_day = v_day limit 1;
  v_who := coalesce(v_who, (select p.id from public.players p order by p.id limit 1));

  begin
    -- (a) THE CAP, every good, a real house, a market work built
    insert into public.city_works (port_id, kind, level) values (v_port, 'market', 3) on conflict (port_id, kind) do update set level = 3;
    update public.world_config set value = to_jsonb(0.1) where key = 'market_cap_per_level';
    select count(*) into v_n from public.goods g
     where world.daily_cap_remaining(v_who, v_port, g.id) is distinct from pg_temp.cap_0318(v_who, v_port, g.id);
    if v_n <> 0 then
      raise exception '0318 self-assert FAIL: the cap moved on % good(s)', v_n;
    end if;

    -- (b) THE DRAW, 3 harbours
    foreach v_q in array v_ports loop
      for v_s in 1 .. case when v_q = v_port then 2 else 1 end loop
        select to_jsonb(d) into v_a from public.contract_draw(v_q, v_day, v_s) d;
        select to_jsonb(d) into v_b from pg_temp.draw_0318(v_q, v_day, v_s) d;
        if v_a is distinct from v_b then
          raise exception '0318 self-assert FAIL: the draw moved at % seq %: %, was %', v_q, v_s, v_a, v_b;
        end if;
      end loop;
    end loop;

    -- (c) THE DRAW, WHEN THE CAP IS WHAT DECIDES: a fraction that leaves about half the goods under the least lot
    select percentile_cont(0.5) within group (order by g.stock_target::double precision)::numeric into v_mid from public.port_goods g where g.port_id = v_port;
    update public.world_config set value = to_jsonb(public.wc_num('trade_step_tuns') * public.wc_int('contract_qty_steps_min') / nullif(v_mid * public.works_factor(v_port, 'market', 'market_cap_per_level'), 0))
     where key = 'daily_cap_fraction';
    select to_jsonb(d) into v_a from public.contract_draw(v_port, v_day, 3) d;
    select to_jsonb(d) into v_b from pg_temp.draw_0318(v_port, v_day, 3) d;
    if v_a is distinct from v_b then
      raise exception '0318 self-assert FAIL: the draw moved where the cap decides: %, was %', v_a, v_b;
    end if;

    -- (d) A DRAW ASKS ONCE, read by the server's own function counters (0262). Where the setting is refused, the body check in section 4 stands alone.
    begin
      perform set_config('track_functions', 'all', true);
      v_track := true;
    exception when others then
      v_track := false;
    end;
    if v_track then
      v_c0 := coalesce(pg_stat_get_xact_function_calls('public.works_factor(uuid,text,text)'::regprocedure), 0);
      perform * from pg_temp.draw_0318(v_port, v_day + 1, 1);
      v_c1 := coalesce(pg_stat_get_xact_function_calls('public.works_factor(uuid,text,text)'::regprocedure), 0);
      perform * from public.contract_draw(v_port, v_day + 1, 1);
      v_c2 := coalesce(pg_stat_get_xact_function_calls('public.works_factor(uuid,text,text)'::regprocedure), 0);
      if v_c1 - v_c0 >= 100 and v_c2 - v_c1 > 1 then   -- the counters counted the old draw, so they count this one
        raise exception '0318 self-assert FAIL: a draw asks the cap good by good: % calls, was %', v_c2 - v_c1, v_c1 - v_c0;
      end if;
    end if;

    -- (e) THE JOB STOPS AT ITS COUNT
    update public.world_config set value = to_jsonb(1) where key = 'daily_cap_fraction';
    update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';
    perform public.treasury_post(v_port, 'CROWN_CALL', 1000000000, null, null, true);
    select count(*) into v_open from public.trade_contracts c where c.port_id = v_port and c.status = 'open';
    update public.world_config set value = to_jsonb(v_open + 3) where key = 'contract_open_max';
    update public.world_config set value = to_jsonb(2) where key = 'contract_wind_posts';
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 2 or (v_a ->> 'posted')::int <> 2 or (select count(*) from public.trade_contracts c where c.port_id = v_port and c.status = 'open') <> v_open + 2 then
      raise exception '0318 self-assert FAIL: the job did not stop at its count: %', v_a;
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'contract_wind_posts';
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 0 then
      raise exception '0318 self-assert FAIL: contract_wind_posts 0 still asks: %', v_a;
    end if;

    raise exception using errcode = 'ZX318', message = 'rolled back';
  exception when sqlstate 'ZX318' then
    null;
  end;
  perform set_config('track_functions', 'none', true);
  drop function pg_temp.draw_0318(uuid, integer, integer);
  drop function pg_temp.cap_0318(uuid, uuid, uuid);

  if (select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) from public.world_config x) <> v_cfg_after then
    raise exception '0318 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0318 self-assert FAIL: over budget, %', clock_timestamp() - v_t0;
  end if;
  raise notice '0318 self-assert ok: the same caps and the same draws, one read of the market a draw, the job stops at its count; in %', clock_timestamp() - v_t0;
end
$m$;
