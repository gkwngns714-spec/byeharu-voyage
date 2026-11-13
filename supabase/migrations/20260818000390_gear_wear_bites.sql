-- ═══════════════════════════════════════════════════════════════════════════════
-- 0390 — GEAR WEAR BITES: this file LIGHTS the switch gear_wear_bite (0158: fittings wear and are repaired). One world_config row, one news row. No function, no table, no other knob, no job.
-- ═══════════════════════════════════════════════════════════════════════════════
-- WHY (owner row 324, 2026-11-13: "do all, make everything work. open them if everything is built and is workable."). 0158 built wear and repair on 2026-10-18 and shipped them dark.
--   docs/dev-log/2026-11-13-gear-wear-lit.md is the reading of what lit does, the measurement and the client that shows it (PR gear-wear, which lands before this file).
-- WHAT A PLAYER MEETS. A mounted fitting that answers to miles, storms or pirates has been gathering wear since 0158 (the writer never asked the switch). From this file on a worn piece's
--   buys count at 1 - wear / 200 in world.ship_stats, world.ship_racks serves each piece its wear card, the yard's REPAIR also mends the fittings and charges them in the same payment
--   (public.unit_repair_cost: the recipe x wear % x gear_repair_pct x running_cost_level), and a worn piece is repaired on its way off. A founding barca carries no fitting: nothing changes for her.
-- MEASURED (cached world at 0367, 40 real round trips a company, the dev-log's table; each world rolls its own sea): 0 to 2 d. a sea day in fittings repair against about 2,000 d. a sea day
--   of trade; a rich two-hull company that never repairs loses 3 % of speed and 17 % of handling after 65,000 nm and owes 517 d.
-- MERCHANTS ARE EXEMPT, AS BUILT: the one writer of wear (public.wear_units_for) is called from voyage.settle inside the players-only block. This file REFUSES if that is no longer so, or if
--   any merchant fitting carries wear. The probe below shows a sample of NPC hulls' figures equal before and after the switch.
-- GUARDS (each refuses loudly and applies nothing): 0158's functions are in this world; the switch row exists and is FALSE (true: lit already, by hand or by this file); the four wear
--   knobs and running_cost_level are the values the measurement was taken at (1, 4, 3, 0.30, 0.2: any other value asks for a new measurement first); the writer is called once and after the
--   merchant test; no merchant fitting is worn.
-- ALTERS LIVE PLAY: it gets its own window. PROD CHECKS, read-only, in order: scripts/ops/harness/gear-wear/volatility.sql, before-light.sql (read what moves at once), after-light.sql as
--   the baseline; after the deploy after-light.sql and scripts/ops/health.sh at +1, +5 and +30 minutes.
-- ROLLBACK (forward, owner only): update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite' (the draft is scripts/ops/harness/gear-wear/rollback-0390.sql). The
--   self-assert plays it inside its probe: at once no card, no fittings bill, the figures whole; the wear stays on the units. NOT UNDONE BY IT: gold a company paid a city for fittings.
-- SELF-ASSERT: the catalog (no function, relation or job moved; exactly one world_config row moved, from false to true); then on a probe of this file's own rows, rolled back: a probe
--   company's barca fitted through public.mount_fitting with one piece worn to 50 is served its card (50, works at 75), her figures fall and none rises, the yard prices exactly
--   public.unit_repair_cost and cmd.do_repair charges exactly it with a whole hull and leaves nothing worn; the switch put out again hides all of it. It counts only its own probe rows.
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 20 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0390', 'Fittings wear: Repair mends them', '장비 마모: 수리에서 고칩니다') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0390. 0364 to 0389 are held by other branches; none cuts a function this file reads the text of (voyage.settle is read, not cut: the guard re-reads it at apply time).
-- ═══════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_def         text;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  v_txt         text;
  v_npc_before  text;
  v_lived       boolean := false;
  v_lis         uuid;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_item        text;
  v_other       text;
  v_whole       jsonb;
  v_worn        jsonb;
  v_card        jsonb;
  v_due         record;
  v_want        bigint;
  v_p0          bigint;
  v_p1          bigint;
  v_k           text;
  v_lower       int := 0;
  v_r           jsonb;
  v_ms_catalog  numeric;
  v_ms_probe    numeric;
  c_key         constant text := 'gear_wear_bite';
  c_uid         constant uuid := '00000000-0390-4000-8000-000000000001';
  c_test        constant text := 'if not (select p.is_npc from public.players p where p.id = f.player_id) then';
  c_call        constant text := 'perform public.wear_units_for(p_fleet, v.id);';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARDS ──
  if exists (select 1 from unnest(array['public.gear_wear_on()', 'public.wear_units_for(uuid,uuid)', 'public.worn_delta(numeric,numeric)', 'public.unit_wear_card(text,numeric)',
                                        'public.unit_repair_cost(text,numeric)', 'public.gear_repair_quote(uuid)', 'public.repair_units_for(uuid)', 'public.fleet_repair_due(uuid,numeric)',
                                        'public.mount_fitting(uuid,text)', 'cmd.do_repair(uuid,jsonb)', 'world.ship_stats(uuid)', 'world.ship_racks(uuid,jsonb)',
                                        'voyage.settle(uuid,timestamp with time zone)', 'public.form_fleet(uuid,text,uuid)', 'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.fitted_units') is null or to_regclass('public.item_use') is null then
    raise exception '0390 refuses: gear wear (0158), the yard or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'false'::jsonb then
    raise exception '0390 refuses: gear_wear_bite is % and this file lights it from false (lit already, or the row is gone)', (select c.value from public.world_config c where c.key = c_key);
  end if;
  if public.wc_num('gear_wear_per_1000nm') <> 1 or public.wc_num('gear_wear_per_fight') <> 4 or public.wc_num('gear_wear_per_storm') <> 3
     or public.wc_num('gear_repair_pct') <> 0.30 or public.wc_num('running_cost_level') <> 0.2 then
    raise exception '0390 refuses: the wear knobs are not the ones the measurement was taken at (1,000 nm %, a fight %, a storm %, repair %, running cost %): measure again (scripts/ops/harness/gear-wear/measure-scene.sql) before lighting',
      public.wc_num('gear_wear_per_1000nm'), public.wc_num('gear_wear_per_fight'), public.wc_num('gear_wear_per_storm'), public.wc_num('gear_repair_pct'), public.wc_num('running_cost_level');
  end if;
  -- MERCHANTS ARE EXEMPT: the one writer is called once, after the one merchant test, and no merchant fitting is worn
  v_def := replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, 'public.wear_units_for(', ''))) / length('public.wear_units_for(') <> 1
     or strpos(v_def, c_call) = 0 or strpos(v_def, c_test) = 0 or strpos(v_def, c_test) > strpos(v_def, c_call) then
    raise exception '0390 refuses: voyage.settle no longer calls public.wear_units_for once, inside the players-only block: read who wears before lighting';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.oid <> 'voyage.settle(uuid,timestamp with time zone)'::regprocedure
                and p.oid <> 'public.wear_units_for(uuid,uuid)'::regprocedure and p.prokind in ('f', 'p') and p.prosrc like '%wear_units_for(%') then
    raise exception '0390 refuses: a function other than voyage.settle calls public.wear_units_for';
  end if;
  if exists (select 1 from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and p.is_npc where u.wear > 0) then
    raise exception '0390 refuses: a merchant''s fitting carries wear: lighting would weaken NPC hulls that never repair';
  end if;

  -- ── 1. BEFORE: the catalog, every other knob, and a sample of NPC hulls' figures ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key <> c_key;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;
  -- twenty NPC hulls that carry fittings, by id: their figures must not move with the switch (in this one transaction nothing else moves them)
  select md5(coalesce(string_agg(x.id::text || world.ship_stats(x.id)::text, '|' order by x.id), '')), count(*) into v_npc_before, v_n
    from (select s.id from public.ships s join public.players p on p.id = s.player_id and p.is_npc
           where exists (select 1 from public.fitted_units u where u.ship_id = s.id) order by s.id limit 20) x;

  -- ── 2. THE CHANGE: the one row, from false to true ──
  update public.world_config c set value = 'true'::jsonb, updated_at = now() where c.key = c_key and c.value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0390 self-assert FAIL: % row(s) of gear_wear_bite were lit, not 1', v_n;
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  v_t := clock_timestamp();
  if not public.gear_wear_on() then
    raise exception '0390 self-assert FAIL: the switch is written and public.gear_wear_on() still answers false';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0390 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> c_key) <> v_cfg_before then
    raise exception '0390 self-assert FAIL: a world_config row other than gear_wear_bite moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0390 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_txt;
    if v_txt is distinct from v_job_before then
      raise exception '0390 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;
  if (select md5(coalesce(string_agg(x.id::text || world.ship_stats(x.id)::text, '|' order by x.id), ''))
        from (select s.id from public.ships s join public.players p on p.id = s.player_id and p.is_npc
               where exists (select 1 from public.fitted_units u where u.ship_id = s.id) order by s.id limit 20) x) is distinct from v_npc_before then
    raise exception '0390 self-assert FAIL: lighting moved an NPC hull''s figures';
  end if;
  v_ms_catalog := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. THE SELF-ASSERT: the doors, on a probe of this file's own rows, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    if v_lis is null or not public.port_has_shipyard(v_lis) then
      raise exception '0390 self-assert FAIL: Lisbon keeps no repair yard to probe';
    end if;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa do Desgaste 0390', (select n.id from public.nations n where n.code = 'PRT'), 40000, false) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Desgaste', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Desgaste 0390', true, true);
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl;
    -- two pieces a company may fit that wear and buy something: the cheapest that mount (the skills a piece asks are the game's own refusal, not this file's)
    for v_r in select to_jsonb(k.code) from public.item_kinds k join public.item_use iu on iu.item_code = k.code and iu.trigger is not null
                 join public.item_profile ip on ip.item_code = k.code and ip.rack <> 'refit'
                where exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
                order by public.item_recipe_value(k.code), k.code loop
      begin
        perform public.mount_fitting(v_sh, v_r #>> '{}');
        if v_item is null then v_item := v_r #>> '{}'; else v_other := v_r #>> '{}'; end if;
      exception when sqlstate 'P0001' then null;
      end;
      exit when v_other is not null;
    end loop;
    if v_item is null or v_other is null then
      raise exception '0390 self-assert FAIL: a new company''s barca could not be fitted with two pieces that wear';
    end if;
    v_whole := world.ship_stats(v_sh);
    if exists (select 1 from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where not (u.value ? 'wear')) then
      raise exception '0390 self-assert FAIL: lit, a piece that wears is served no wear card: %', world.ship_racks(v_sh, null);
    end if;

    -- (a) one piece worn to 50: the card, the figures
    update public.fitted_units u set wear = 50 where u.id = (select u2.id from public.fitted_units u2 where u2.ship_id = v_sh and u2.item_code = v_item limit 1);
    select u.value into v_card from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u
     where u.value ->> 'code' = v_item and (u.value ->> 'wear')::numeric > 0;
    if v_card is null or (v_card ->> 'wear')::numeric <> 50 or (v_card ->> 'works_pct')::numeric <> 75 then
      raise exception '0390 self-assert FAIL: the worn piece is not served 50 worn, works at 75: %', world.ship_racks(v_sh, null);
    end if;
    v_worn := world.ship_stats(v_sh);
    for v_k in select jsonb_object_keys(v_whole) loop
      if (v_worn ->> v_k)::numeric > (v_whole ->> v_k)::numeric then
        raise exception '0390 self-assert FAIL: worn, her % rose (% from %)', v_k, v_worn ->> v_k, v_whole ->> v_k;
      end if;
      if (v_worn ->> v_k)::numeric < (v_whole ->> v_k)::numeric then v_lower := v_lower + 1; end if;
    end loop;
    if v_lower = 0 then
      raise exception '0390 self-assert FAIL: a piece at 50 lowers none of her figures (whole %, worn %)', v_whole, v_worn;
    end if;

    -- (b) the yard: the price is the one price, the hull is whole, REPAIR charges exactly it and leaves nothing worn
    v_want := public.unit_repair_cost(v_item, 50);
    select d.points, d.gear into v_due from public.fleet_repair_due(v_fl, 100) d;
    if v_due.points <> 0 or (v_due.gear ->> 'units')::int <> 1 or (v_due.gear ->> 'cost')::bigint <> v_want or v_want <= 0 then
      raise exception '0390 self-assert FAIL: the yard does not price the one worn piece at % with a whole hull: %', v_want, to_jsonb(v_due);
    end if;
    select pl.ducats into v_p0 from public.players pl where pl.id = v_pl;
    v_r := cmd.do_repair(v_fl, '{}'::jsonb);
    select pl.ducats into v_p1 from public.players pl where pl.id = v_pl;
    if v_p0 - v_p1 <> v_want or (v_r -> 'gear' ->> 'units')::int <> 1 or exists (select 1 from public.fitted_units u where u.ship_id = v_sh and u.wear <> 0)
       or world.ship_stats(v_sh) <> v_whole then
      raise exception '0390 self-assert FAIL: the repair charged % (wanted %), left a piece worn, or her figures are not whole again: %', v_p0 - v_p1, v_want, v_r;
    end if;

    -- (c) THE ROLLBACK, PLAYED: the switch out again, the wear still on the unit: no card, no bill, the figures whole
    update public.fitted_units u set wear = 50 where u.id = (select u2.id from public.fitted_units u2 where u2.ship_id = v_sh and u2.item_code = v_item limit 1);
    update public.world_config c set value = 'false'::jsonb where c.key = c_key;
    if exists (select 1 from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where u.value ? 'wear')
       or (select d.gear from public.fleet_repair_due(v_fl, 100) d) is not null or world.ship_stats(v_sh) <> v_whole
       or not exists (select 1 from public.fitted_units u where u.ship_id = v_sh and u.wear = 50) then
      raise exception '0390 self-assert FAIL: with the switch out again a read still shows her wear, or the wear was lost';
    end if;

    raise exception using errcode = 'ZX390', message = 'PROBE_ROLLBACK_0390';
  exception when sqlstate 'ZX390' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0390 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid = c_uid) then
    raise exception '0390 self-assert FAIL: the probe house outlived the probe';
  end if;
  -- the change outlived the probe's rollback; the rollback played inside it did not
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'true'::jsonb or not public.gear_wear_on() then
    raise exception '0390 self-assert FAIL: after the probe the switch is not lit';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0390', 'Fittings wear: Repair mends them', '장비 마모: 수리에서 고칩니다');
  if (select count(*) from public.world_news w where w.key = 'update:0390') <> 1 then
    raise exception '0390 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0390 self-assert FAIL: the file ran % s, over its 20 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0390 timings: catalog, knobs and 20 NPC hulls % ms; the doors (a probe barca, a card, a repair, the rollback played) % ms', v_ms_catalog, v_ms_probe;
  raise notice '0390 self-assert ok: GEAR WEAR BITES. gear_wear_bite is lit (one row, from false); no function, relation, job or other knob moved; 20 NPC hulls'' figures unmoved; a probe barca''s % at 50 was served "50, works at 75", lowered % of her figures and raised none, was priced % d. and repaired for exactly that; with the switch out again nothing showed and the wear stayed. % ms.',
    v_item, v_lower, v_want, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
