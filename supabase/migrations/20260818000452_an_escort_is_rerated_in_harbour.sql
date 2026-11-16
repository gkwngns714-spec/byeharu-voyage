-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0452 - AN ESCORT IS RE-RATED IN HARBOUR  (0451's ladder refused every navy ship escorting a cargo ship, and one always is)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE BUG (prod 2026-11-16, head 0451, read only): the ladder (0451, public.npc_ladder_refit) had re-rated the navy fleets, but the last ship of
--   the line of ENG, ESP, JPN, MNG, MUG, NLD, OTT and PRT was never re-rated: 8 fleets, each with navy_ships.escort_of set; none busy, in a
--   fight, called out, unpaid, laid up or holding goods. (FRA's escort was already her rung's.) scripts/ops/harness/escort-refit/before.sql,
--   00:25 UTC: 46 navy fleets, 38 at their rung, the 8 escorts due (3 in harbour, 5 at sea), each still one galion.
-- THE CAUSE: public.npc_ladder_refit refused any navy ship whose escort_of is set. public.navy_escort_step (0333, 0342) sets escort_of on the last
--   ship of a realm's line while one of her country's cargo ships sails with funds aboard, and clears it only when none does. With a hundred
--   cargo ships at sea that is never: in harbour she waits for her ward or takes the next leg, escort_of always set. So no window opened, ever.
--   Reproduced on the local world (scripts/ops/harness/escort-refit/scene.sql): ord 1 re-rated in the first minute, the escort refused in every
--   minute after.
-- WHAT THE REFUSAL PROTECTED: nothing the refit's other refusals do not. At sea she is refused by her status (DOCKED or UNABLE_TO_SAIL only); in a
--   fight by navy_ships.battle_id and a FIGHTING side; sent for by called_to. Her duty IS her row in public.navy_ships (mission ESCORT,
--   escort_of), which the refit never writes: it swaps her hulls (public.ships) and nothing else. A raid on her ward finds her by that row
--   (public.navy_call), takes her fleet row SKIP LOCKED, and needs one hull above 0 health: a re-rating keeps her health share, so she answers
--   as before, on her new hulls. The one thing she can miss is a call in the few milliseconds the refit holds her row, as any navy ship can.
-- THE FIX (decided by default): the refit does not refuse an escort. An escort in harbour (not at sea, not in a fight, not called out, not busy)
--   is re-rated as any other navy fleet, by the one re-rating (public.npc_ladder_refit, from public.npc_ladder_pass) and inside its limits (two
--   of a kind a minute, harbour only, free); her mission and her ward are untouched. No second path, no new rule for escorts.
-- HUNKS: public.npc_ladder_refit (2): the refusal's line without `or n.escort_of is not null`; her header comment says so.
-- ROWS: no table, job or knob. About 8 one-time re-ratings (one per escort, about 20 rows each, as she next lies in harbour; inside 0451's two
--   a kind a minute, so at most 40 extra rows a minute for a few minutes, about 160 rows in all), then nothing more than 0451's own.
-- LOCKS: CREATE OR REPLACE x1. TIME: under 2 s. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/escort-refit/rollback-0452.sql (a draft: the hunks swapped back).
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved. THE PROBE, rolled
--   back, on any world (its own fleets; a navy ship at ord 900, which no world uses): an escort in harbour IS re-rated, her mission and ward
--   unmoved; the same escort called out, in a fight, at sea is not.
-- VERSION: 0452 = prod head 0451 + 1. Both hunks occur once in prod's live body (read before the PR).
-- news: none (a repair: eight navy ships take the rank 0451 already gave the rest, as they next lie in harbour)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_meta      text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_nat       uuid;
  v_cap       uuid;
  v_pl        uuid;
  v_ward      uuid;
  v_fl        uuid;
  v_bat       uuid;
  v_now       timestamptz := date_trunc('minute', now()) + interval '1 day';   -- a minute of the ladder's room nobody else has taken
  v_want      text;
  v_have      text;
  v_note      text;
  x           record;
  c_fn        constant text := 'public.npc_ladder_refit(uuid,timestamp with time zone)';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.npc_hulls_sig(uuid)') is null or to_regclass('public.npc_fleet_rungs') is null
     or to_regprocedure('public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)') is null then
    raise exception '0452 refuses: the ladder (0451) or the navy''s escort (0333) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;
  select p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure;

  -- ── 2. THE HUNKS ──
  create temp table hunks_0452 (ord int, old text, new text) on commit drop;
  insert into hunks_0452 values
  (1,
$h$-- wreck lying: public.pirate_reborn calls it before the mend), never busy, never on a side of a battle being fought, never a navy ship called to a
-- fight or escorting, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). Her old hulls go and
$h$,
$h$-- wreck lying: public.pirate_reborn calls it before the mend), never busy, never on a side of a battle being fought, never a navy ship called to a
-- fight, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). An escort in harbour is re-rated as any other
-- (0452): her duty is her row of public.navy_ships (mission, escort_of), which this never writes. Her old hulls go and
$h$),
  (2,
$h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null or n.escort_of is not null)) then
$h$,
$h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null)) then   -- 0452: not escort_of, which is set while any cargo ship of hers sails with funds, so always
$h$);

  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  v_pre := v_def;
  for x in select * from hunks_0452 h order by h.ord loop
    v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
    if v_n <> 1 then
      raise exception '0452 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against (applied twice?)', x.ord, c_fn, v_n;
    end if;
    v_def := replace(v_def, x.old, x.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for x in select * from hunks_0452 h order by h.ord desc loop
    v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
    if v_n <> 1 then
      raise exception '0452 self-assert FAIL: hunk % of % is not in the new body once', x.ord, c_fn;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0452 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0452 self-assert FAIL: another function moved';
  end if;
  if (select p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) is distinct from v_meta then
    raise exception '0452 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;

  -- ── 4. THE PROBE, rolled back by a raised sentinel. Its own fleets: a ward, and an escort at ord 900 (no world's navy reaches it). Knobs are
  --   written only by UPDATE. Its minute is a day ahead, so the ladder's room is its own.
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_ladder_enabled' and value is distinct from 'true'::jsonb;
    select g.nation_id into v_nat from public.great_powers g join public.nations n on n.id = g.nation_id
     where not g.pirate and public.realm_capital(g.nation_id) is not null order by (n.code = 'ESP') desc, n.code limit 1;
    v_cap := public.realm_capital(v_nat);
    if v_nat is null or v_cap is null then
      raise exception '0452 self-assert FAIL: no crown with a capital in this world';
    end if;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0452 ward', v_nat, 0, true) returning id into v_pl;
    v_ward := public.form_fleet(v_pl, 'Probe 0452 ward', v_cap);
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0452', v_nat, 0, true) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Probe 0452', v_cap);
    perform public.commission_ship(v_pl, v_fl, public.wc_text('navy_ship_class'), 'Probe 0452', true, false);
    -- her duty, as public.navy_escort_step writes it
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at, mission, escort_of)
    values (v_fl, v_pl, v_nat, 900, v_cap, v_cap, now(), 'ESCORT', v_ward);
    v_want := public.npc_hulls_sig(v_fl);
    if v_want is null or v_want = public.wc_text('navy_ship_class') || '*1' then
      raise exception '0452 self-assert FAIL: the probe escort (ord 900) wants %: not a re-rating', v_want;
    end if;

    -- refused: called out, in a fight, at sea
    update public.navy_ships set called_to = v_cap where fleet_id = v_fl;
    if public.npc_ladder_refit(v_fl, v_now) then
      raise exception '0452 self-assert FAIL: an escort called to a fight was re-rated';
    end if;
    update public.navy_ships set called_to = null where fleet_id = v_fl;
    insert into public.battles (kind, site, started_at, resolves_at, status) values ('RAID', '{}'::jsonb, now(), now() + interval '1 hour', 'FIGHTING') returning id into v_bat;
    update public.navy_ships set battle_id = v_bat where fleet_id = v_fl;
    if public.npc_ladder_refit(v_fl, v_now) then
      raise exception '0452 self-assert FAIL: an escort in a fight was re-rated';
    end if;
    update public.navy_ships set battle_id = null where fleet_id = v_fl;
    update public.fleets set status = 'SAILING', port_id = null where id = v_fl;
    if public.npc_ladder_refit(v_fl, v_now) then
      raise exception '0452 self-assert FAIL: an escort at sea was re-rated';
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_cap where id = v_fl;

    -- in harbour: re-rated, her duty untouched
    if not public.npc_ladder_refit(v_fl, v_now) then
      raise exception '0452 self-assert FAIL: an escort in harbour was refused';
    end if;
    select string_agg(h.code || '*' || h.n, '+' order by h.code) into v_have
      from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl group by k.code) h;
    if v_have is distinct from v_want
       or (select count(*) from public.navy_ships n where n.fleet_id = v_fl and n.mission = 'ESCORT' and n.escort_of = v_ward and n.battle_id is null and n.called_to is null) <> 1
       or (select count(*) from public.ships s where s.fleet_id = v_fl and s.is_flagship and s.name = 'Probe 0452') <> 1
       or not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = v_fl and g.kind = 'NAVY' and g.hulls = v_want) then
      raise exception '0452 self-assert FAIL: the escort was not re-rated to %, or her duty moved: has %, row %', v_want, v_have,
        (select to_jsonb(n) from public.navy_ships n where n.fleet_id = v_fl);
    end if;
    v_note := (select n.code from public.nations n where n.id = v_nat) || ' escort (ord 900) ' || public.wc_text('navy_ship_class') || ' -> ' || v_have
              || ' in harbour, still ESCORT of her ward; refused called out, in a fight, at sea';
    raise exception sqlstate 'BV452' using message = v_note;
  exception when sqlstate 'BV452' then
    get stacked diagnostics v_note = message_text;
  end;
  if exists (select 1 from public.players p where p.company_name in ('Probe 0452', 'Probe 0452 ward')) then
    raise exception '0452 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0452 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0452 self-assert ok: AN ESCORT IS RE-RATED IN HARBOUR. % hunks once each and reversing; grants and volatility unmoved; no other function moved. Probe: %. % ms.',
    (select count(*) from hunks_0452), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0452;
end $m$;
