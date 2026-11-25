-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights passive_slots_enabled)
-- 0509 - PASSIVE SLOTS  (dark: the owner's switch passive_slots_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-2026-11-25.md, answer 3): "trading 3 is good. Number of fleet you can choose to passive
--   trading." docs/design/owner-spec-plan-2026-11-25.md section 0.3: 1 / 2 / 3 / 4 / 5 / 6 fleets at Trading 3 / 5 / 8 / 11 / 14 / 17.
-- WHAT (lit; dark every body answers as before):
--   public.passive_slots_on()         THE SWITCH, read once: world_config passive_slots_enabled.
--   public.fleet_job_passive(k, p)    THE RULE of a passive job: a Best run, a near round (0499: kind best), or a fixed run that is not one
--                                     single run (`times` 1). NOT passive (decided by default): a hand trade, a single run or Bring home
--                                     once, and a land haul (it moves the company's own goods to a yard and sells none).
--   public.passive_slots(player)      THE ONE COUNT: {level, used, max, next, next_max}. level: the Trading level she was last paid for and
--                                     shown (public.house_level_marks, as public.level_perk reads it; one key probe, never the record's
--                                     sum). max: the steps of passive_slots_levels at or below it. used: her fleets that hold a passive
--                                     job, stopped or waiting ones too. next: the first level at which one more than she uses may trade
--                                     (null: none), and next_max what it allows.
--   public.passive_refusal(player, fleet, kind, params)
--                                     THE ONE JUDGE: null, or {code E_PASSIVE_SLOTS, sentence with the level}. A fleet that holds a
--                                     passive job may change it; a job that is not passive is never refused here.
--   public.passive_options(player, fleet, read)
--                                     world.actions' options: each passive one the door would refuse gains `locked` {code, sentence} (and
--                                     `once` true on a fixed run, which the door still takes as a single run).
--   public.fleet_job_set_for          (1 hunk) the door asks the judge, last, under her company's row (two presses cannot both take the
--                                     last slot).
--   world.workers                     (1 hunk) `passive` {level, used, max, next, next_max}; dark: the key is not there.
--   world.actions                     (1 hunk) a fleet's options through public.passive_options.
-- A JOB ALREADY RUNNING KEEPS RUNNING: nothing but the door asks. The job tick, the plan, the open and the retry are not touched; a
--   company with more passive fleets than her level allows keeps them all, may change each, and is refused only a further one.
--   (The plan's players.passive_kept, "keeps at least that number after clearing", is not built: the brief asks no column.)
-- NOT GATED HERE: the old standing routes (0092) are another door with their own cap (public.standing_route_max_for).
-- NOT CHANGED: any knob but the two new; level_benefits (a new kind would break the live client's level words); any table; the tick.
-- ROWS: two world_config rows. No table, column, index or cron. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit: one key probe and at most six fleet_jobs rows a read.
-- LOCKS: one INSERT (world_config); CREATE FUNCTION x5; CREATE OR REPLACE x3 by hunks. TIME: about a second. BUDGET: statement_timeout
--   90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, passive_slots_enabled false. FULL: a migration reversing the three hunks and dropping the five.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; two knobs added, no other moved. THE PROBE (rolled back; its own company of six fleets, its level set on its own
--   mark; no price is read and no tick is run): DARK, six Best jobs at Trading 1 and no `passive` key; LIT, the jobs held stay and may be
--   changed, the ladder at every level from 1 to 20, a further one refused with the level, a single run and the sixth taken.
-- VERSION: 0509 (built on 0498; 0499 and 0500 hunk other lines of public.fleet_job_set_for and were applied under it in the test).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'world.workers()', 'world.actions(text)'];
  c_new    constant text[] := array['public.passive_slots_on()', 'public.fleet_job_passive(text,jsonb)', 'public.passive_slots(uuid)',
                                    'public.passive_refusal(uuid,uuid,text,jsonb)', 'public.passive_options(uuid,uuid,jsonb)'];
  c_keys   constant text[] := array['passive_slots_enabled', 'passive_slots_levels'];
  c_uid    constant uuid := '00000000-0509-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_me        uuid;
  v_fl        uuid[];
  v_id        uuid;
  v_r         jsonb;
  v_s         jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.passive_slots(uuid)') is not null or exists (select 1 from public.world_config where key = any (c_keys)) then
    raise exception '0509 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) q where to_regprocedure(q) is null) or to_regclass('public.house_level_marks') is null
     or to_regprocedure('cmd.refuse(text,text,jsonb)') is null then
    raise exception '0509 refuses: 0481 (the standing jobs), 0496 (the workers) or 0356 (the level marks) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE KNOBS AND THE RULES ──
  insert into public.world_config (key, value, description) values
    ('passive_slots_enabled', 'false'::jsonb,
     '0509: THE SWITCH (the owner''s). true: a company may have as many fleets trading passively (a Best run, a near round, a repeating fixed run) as passive_slots_levels allows at her Trading level; the job door refuses a further one (E_PASSIVE_SLOTS). A job already held keeps running. false: no limit, as before 0509.'),
    ('passive_slots_levels', '[3, 5, 8, 11, 14, 17]'::jsonb,
     '0509: each Trading level here lets one more fleet trade passively (public.passive_slots), lit.');

  execute $f$
create function public.passive_slots_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509: THE one reader of passive_slots_enabled.
  select coalesce(public.wc('passive_slots_enabled') = 'true'::jsonb, false)
$body$
  $f$;

  execute $f$
create function public.fleet_job_passive(p_kind text, p_params jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0509: IS THIS JOB PASSIVE TRADING? A Best run and a near round (kind best), and a fixed run that is not one single run (`times` 1).
  -- A land haul trades nothing.
  select coalesce(p_kind = 'best'
                  or (p_kind = 'fixed' and coalesce(p_params->'times', 'null'::jsonb) is distinct from '1'::jsonb), false)
$body$
  $f$;

  execute $f$
create function public.passive_slots(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509: HOW MANY OF HER FLEETS MAY TRADE PASSIVELY, AND HOW MANY DO: {level, used, max, next, next_max}. level: the Trading level she was
  -- last paid for and shown (public.house_level_marks, as public.level_perk reads it; no mark: 1). max: the steps of passive_slots_levels
  -- at or below it. used: her fleets that hold a passive job, stopped and waiting ones too. next: the first level at which more than
  -- she uses (and more than now) may trade, next_max how many; null when no level gives more.
  select jsonb_build_object('level', b.lvl, 'used', b.used, 'max', b.mx, 'next', n.lvl, 'next_max', n.ord)
    from (select a.lvl, a.used, (select count(*)::int from jsonb_array_elements_text(public.wc('passive_slots_levels')) r where r.value::int <= a.lvl) as mx
            from (select coalesce((select m.level from public.house_level_marks m where m.player_id = p_player and m.track = 'trading'), 1) as lvl,
                         (select count(*)::int from public.fleets f join public.fleet_jobs j on j.fleet_id = f.id
                           where f.player_id = p_player and public.fleet_job_passive(j.kind, j.params)) as used) a) b
    left join lateral (select r.value::int as lvl, r.ord::int from jsonb_array_elements_text(public.wc('passive_slots_levels')) with ordinality r(value, ord)
                        where r.ord > greatest(b.used, b.mx) order by r.ord limit 1) n on true
$body$
  $f$;

  execute $f$
create function public.passive_refusal(p_player uuid, p_fleet uuid, p_kind text, p_params jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0509: THE ONE JUDGE OF A PASSIVE JOB: null (dark; not passive; this fleet holds a passive job already, which she may change; or a
-- slot is free), else {code, sentence}, the level that opens one more in the sentence. Read by the door (public.fleet_job_set_for) and
-- by world.actions' options (public.passive_options). Writes nothing.
declare
  s jsonb;
begin
  if not public.passive_slots_on() or not public.fleet_job_passive(p_kind, p_params)
     or exists (select 1 from public.fleet_jobs j where j.fleet_id = p_fleet and j.player_id = p_player and public.fleet_job_passive(j.kind, j.params)) then
    return null;
  end if;
  s := public.passive_slots(p_player);
  if (s->>'used')::int < (s->>'max')::int then
    return null;
  end if;
  return jsonb_build_object('code', 'E_PASSIVE_SLOTS', 'sentence',
    case when (s->>'max')::int = 0 then format('passive trading opens at Trading %s; yours is %s', public.wc('passive_slots_levels')->>0, s->>'level')
         else format('%s trade%s passively; Trading %s allows %s', case s->>'used' when '1' then '1 fleet' else (s->>'used') || ' fleets' end,
                     case s->>'used' when '1' then 's' else '' end, s->>'level', s->>'max') end
    || case when (s->>'max')::int = 0 and (s->>'used')::int = 0 then ''
            when s->>'next' is null then '; no level opens more'
            else format('; Trading %s allows %s', s->>'next', s->>'next_max') end);
end
$body$
  $f$;

  execute $f$
create function public.passive_options(p_player uuid, p_fleet uuid, p_read jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0509: world.actions' read of one fleet, each passive option the door would refuse marked `locked` {code, sentence}; on a fixed run
-- also `once` true: the door still takes it as a single run (`times` 1). Dark or a slot free: the read as it is.
declare
  v_no jsonb := public.passive_refusal(p_player, p_fleet, 'best', '{}'::jsonb);
begin
  if v_no is null or jsonb_typeof(p_read->'options') is distinct from 'array' then
    return p_read;
  end if;
  return p_read || jsonb_build_object('options', coalesce((
    select jsonb_agg(case when public.fleet_job_passive(o.e #>> '{job,kind}', o.e #> '{job,params}')
                          then o.e || jsonb_build_object('locked', v_no)
                               || case when o.e #>> '{job,kind}' = 'fixed' then jsonb_build_object('once', true) else '{}'::jsonb end
                          else o.e end order by o.ord)
      from jsonb_array_elements(p_read->'options') with ordinality o(e, ord)), '[]'::jsonb));
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0509 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0509 values
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$,
$h$  -- 0509 (passive_slots_enabled): one more fleet trades passively only while her Trading level has a slot (public.passive_refusal), judged
  -- under her company's row, so two presses cannot both take the last one
  if public.passive_slots_on() and public.fleet_job_passive(p_kind, v_p) then
    perform 1 from public.players pl where pl.id = p_player for no key update;
    v_s := public.passive_refusal(p_player, p_fleet, p_kind, v_p);
    if v_s is not null then
      perform cmd.refuse(v_s->>'code', v_s->>'sentence');
    end if;
  end if;

  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$),
  ('world.workers()', 1,
$h$                            'workers', public.workers_for(v_me));
$h$,
$h$                            'workers', public.workers_for(v_me))
         -- 0509: how many of her fleets trade passively, how many may, and the next level (dark: no such key)
         || case when public.passive_slots_on() then jsonb_build_object('passive', public.passive_slots(v_me)) else '{}'::jsonb end;
$h$),
  ('world.actions(text)', 1,
$h$    v_r := public.sea_actions_for(v_me, substr(p_worker, 7)::uuid);
$h$,
$h$    v_r := public.sea_actions_for(v_me, substr(p_worker, 7)::uuid);
    v_r := public.passive_options(v_me, substr(p_worker, 7)::uuid, v_r);   -- 0509: a repeating run with no slot free is `locked`
$h$);

  for v_h in select h.fn from hunks_0509 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0509 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0509 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0509 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0509 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0509 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0509 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0509 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0509 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before
     or public.passive_slots_on() then
    raise exception '0509 self-assert FAIL: a knob moved, or the switch is not dark';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (its own company's rows; no price is read, no tick is run) ──
  begin
    -- six fleets, each a fit hull of her own (the room is not this file's)
    update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
    update public.world_config set value = '6'::jsonb where key = 'fleet_max';
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'assign_home_enabled');
    v_me := public.new_house(c_uid, 'Casa das Vagas 0509', 'PRT');
    select array[f.id] into v_fl from public.fleets f where f.player_id = v_me;
    update public.ships s set crew = c.crew_max from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl[1];
    for v_n in 2 .. 6 loop
      insert into public.fleets (player_id, name, port_id) select f.player_id, format('Vaga 0509 %s', v_n), f.port_id from public.fleets f where f.id = v_fl[1]
      returning id into v_id;
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, is_flagship)
      select s.player_id, v_id, s.class_id, format('Vaga 0509 %s', v_n), s.durability, s.crew, true from public.ships s where s.fleet_id = v_fl[1] and s.is_flagship;
      v_fl := v_fl || v_id;
    end loop;
    insert into public.house_level_marks (player_id, track, level) values (v_me, 'trading', 1)
      on conflict (player_id, track) do update set level = excluded.level;
    perform cmd.assume_identity(c_uid);

    -- (a) DARK: no limit at Trading 1, no key, and an option is never locked
    for v_n in 1 .. 4 loop
      v_r := cmd.set_fleet_job(v_fl[v_n], 'best', '{}'::jsonb);
      if (v_r->>'ok')::boolean is not true then
        raise exception '0509 self-assert FAIL: dark, a Best job was refused: %', v_r;
      end if;
    end loop;
    if world.workers() ? 'passive' or public.passive_refusal(v_me, v_fl[5], 'best', '{}'::jsonb) is not null then
      raise exception '0509 self-assert FAIL: dark, the workers'' read or the judge is not as before';
    end if;

    -- (b) LIT, over her level: the four keep their jobs and may change them; a fifth is refused with the level
    update public.world_config set value = 'true'::jsonb where key = 'passive_slots_enabled';
    v_r := cmd.set_fleet_job(v_fl[4], 'best', '{}'::jsonb);
    v_s := cmd.set_fleet_job(v_fl[5], 'best', '{}'::jsonb);
    if (v_r->>'ok')::boolean is not true or v_s->>'error_code' is distinct from 'E_PASSIVE_SLOTS'
       or v_s->>'error_message' is distinct from 'passive trading opens at Trading 3; yours is 1; Trading 14 allows 5'
       or (select count(*) from public.fleet_jobs j where j.player_id = v_me and j.paused_reason is null) <> 4
       or (select count(*) from public.fleet_jobs_due() d where d.player_id = v_me) <> 4
       or world.workers()->'passive' is distinct from jsonb_build_object('level', 1, 'used', 4, 'max', 0, 'next', 14, 'next_max', 5) then
      raise exception '0509 self-assert FAIL: lit at Trading 1 with four passive fleets: change % / fifth % / due % / read %', v_r, v_s,
        (select count(*) from public.fleet_jobs_due() d where d.player_id = v_me), world.workers()->'passive';
    end if;

    -- (c) THE LADDER at every level; the door at each rung: one more taken, the next refused naming its level
    delete from public.fleet_jobs j where j.player_id = v_me;
    for v_n in 1 .. 20 loop
      update public.house_level_marks set level = v_n where player_id = v_me and track = 'trading';
      if (public.passive_slots(v_me)->>'max')::int is distinct from (case when v_n < 3 then 0 when v_n < 5 then 1 when v_n < 8 then 2 when v_n < 11 then 3
                                                                         when v_n < 14 then 4 when v_n < 17 then 5 else 6 end) then
        raise exception '0509 self-assert FAIL: the ladder at Trading %: %', v_n, public.passive_slots(v_me);
      end if;
    end loop;
    update public.house_level_marks set level = 2 where player_id = v_me and track = 'trading';
    if cmd.set_fleet_job(v_fl[1], 'best', '{}'::jsonb)->>'error_message' is distinct from 'passive trading opens at Trading 3; yours is 2' then
      raise exception '0509 self-assert FAIL: at Trading 2 the first passive fleet is not refused with the level: %', cmd.set_fleet_job(v_fl[1], 'best', '{}'::jsonb);
    end if;
    for x in select r.value::int as lvl, r.ord::int as n from jsonb_array_elements_text(public.wc('passive_slots_levels')) with ordinality r(value, ord) order by 2 loop
      update public.house_level_marks set level = x.lvl where player_id = v_me and track = 'trading';
      v_r := cmd.set_fleet_job(v_fl[x.n], 'best', '{}'::jsonb);
      v_s := case when x.n < 6 then cmd.set_fleet_job(v_fl[x.n + 1], 'best', '{}'::jsonb) end;
      if (v_r->>'ok')::boolean is not true
         or (x.n < 6 and v_s->>'error_message' is distinct from format('%s passively; Trading %s allows %s; Trading %s allows %s', case x.n when 1 then '1 fleet trades' else x.n || ' fleets trade' end, x.lvl, x.n,
                                                                        public.wc('passive_slots_levels')->>x.n, x.n + 1)) then
        raise exception '0509 self-assert FAIL: the door at Trading %: % then %', x.lvl, v_r, v_s;
      end if;
    end loop;
    -- a cleared job gives its slot back
    perform cmd.clear_fleet_job(v_fl[1]);
    if (public.passive_slots(v_me)->>'used')::int <> 5 then
      raise exception '0509 self-assert FAIL: a cleared job keeps its slot: %', public.passive_slots(v_me);
    end if;

    -- (d) WHAT IS PASSIVE, and a locked option
    if not public.fleet_job_passive('best', '{}') or not public.fleet_job_passive('fixed', '{"good": "x"}') or not public.fleet_job_passive('fixed', '{"times": 2}')
       or public.fleet_job_passive('fixed', '{"times": 1}') or public.fleet_job_passive('land', '{}') then
      raise exception '0509 self-assert FAIL: the rule of a passive job';
    end if;
    update public.house_level_marks set level = 1 where player_id = v_me and track = 'trading';
    v_r := public.passive_options(v_me, v_fl[1], '{"options": [{"id": "a", "job": {"kind": "best", "params": {}}}, {"id": "b", "job": {"kind": "fixed", "params": {"good": "x"}}}, {"id": "c", "job": {"kind": "land", "params": {}}}]}');
    if v_r #>> '{options,0,locked,code}' is distinct from 'E_PASSIVE_SLOTS' or v_r #> '{options,0}' ? 'once' or v_r #>> '{options,1,once}' is distinct from 'true'
       or v_r #> '{options,2}' ? 'locked' or jsonb_array_length(v_r->'options') <> 3
       or public.passive_options(v_me, v_fl[2], '{"options": [{"job": {"kind": "best"}}]}') #> '{options,0}' ? 'locked' then
      raise exception '0509 self-assert FAIL: the options are not locked as the door refuses: %', v_r;
    end if;
    raise exception using errcode = 'ZX509', message = 'PROBE_ROLLBACK_0509';
  exception when sqlstate 'ZX509' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.company_name = 'Casa das Vagas 0509' or p.auth_uid = c_uid) then
    raise exception '0509 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before
     or public.passive_slots_on() then
    raise exception '0509 self-assert FAIL: a knob is not as it was found after the probe';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0509 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0509 self-assert ok: PASSIVE SLOTS (dark: passive_slots_enabled false). Three hunks once and reversing; five new functions server only; no other function moved; two knobs added. Probe (rolled back): dark, four Best jobs at Trading 1; lit, the four kept and changed, the fifth refused; 1/2/3/4/5/6 fleets at Trading 3/5/8/11/14/17, each refusal naming the next level. % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
