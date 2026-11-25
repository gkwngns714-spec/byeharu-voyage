-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights ammo_enabled)
-- 0520 - AMMO  (dark: ammo_enabled. Slice `ammo`, docs/design/rounds-2026-11-25.md section 6)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- AMMO IS TWO GOODS IN THE HOLD: Gunpowder and Shot and Ball. A round of a work that shoots (round_works.ammo) spends `ammo` units of EACH for
--   every 100 points of attack her hulls have (public.round_ammo_need); what is aboard is one more bound on the most rounds (public.round_terms:
--   `ammo`), so a run never starts a round it cannot shoot. Only rounds spend it: a raid and a battle of today spend none (the owner's default).
-- 0.01 a round a 100 attack, about 9 coin at the goods' base values (tuned 2026-11-25, docs/dev-log/2026-11-25-rounds-balance.md): data on the work's row.
-- A job of rounds may carry `ammo` (units of each to hold): at her base it BUYS the two, where the quay sells them and as far as she can.
-- NOT CHANGED: prices, the quay, any fight. ROWS: none. -- budget: none. -- retention: none (no table).
-- LOCKS: ALTER TABLE round_works (a column), CREATE FUNCTION x3, CREATE OR REPLACE x5 by hunks. BUDGET: 60 s, 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): ammo_enabled false (a round costs no ammo). FULL: a migration reversing the hunks.
-- SELF-ASSERT: the hunks once and reversing; no other function moved; a probe (rolled back): dark no cost; lit the bound, the spend to the unit, the buy line.
-- VERSION: 0520 (after 0519).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_terms(uuid,text,jsonb)', 'public.round_settle(uuid,timestamp with time zone)', 'public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 'public.round_plan(uuid)', 'public.round_job_param(uuid,uuid,jsonb)']::text[];
  c_new    constant text[] := array['public.ammo_on()', 'public.round_ammo_need(uuid,numeric)', 'public.round_ammo_aboard(uuid)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['ammo_enabled']::text[];
  c_ua     constant uuid := '00000000-0520-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  -- ── 0. GUARD ──
  if to_regprocedure('public.ammo_on()') is not null then
    raise exception '0520 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.round_plan(uuid)', 'public.round_settle(uuid,timestamptz)']::text[]) f where to_regprocedure(f) is null) then
    raise exception '0520 refuses: what it stands on is not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0520 (fn text primary key, def text) on commit drop;
  insert into pre_0520 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  -- ── 2. THE KNOBS AND THE DATA ──
  insert into public.world_config (key, value, description) values
    ('ammo_enabled', 'false'::jsonb, '0520: THE SWITCH (the owner''s). true: a round of a work that shoots spends Gunpowder and Shot and Ball from the hold.');
  alter table public.round_works add column ammo numeric not null default 0 check (ammo >= 0);
  comment on column public.round_works.ammo is '0520: units of Gunpowder and of Shot and Ball a round, for every 100 points of her attack (while ammo_enabled).';

  -- ── 3. THE RULES ──
  execute $f$
create function public.ammo_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0520: THE SWITCH, read once: world_config ammo_enabled.
  select public.wc('ammo_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_ammo_need(p_fleet uuid, p_ammo numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0520: units of each of the two goods one round spends: p_ammo for every 100 points of her attack (world.ship_stats). Dark or a work that does not shoot: 0.
  select case when coalesce(p_ammo, 0) <= 0 or not public.ammo_on() then 0
              else round(p_ammo * coalesce((select sum((world.ship_stats(s.id)->>'attack')::numeric) from public.ships s where s.fleet_id = p_fleet), 0) / 100, 4) end
$body$
  $f$;
  execute $f$
create function public.round_ammo_aboard(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0520: the rounds' ammo aboard: the less of her Gunpowder and her Shot and Ball.
  select least(coalesce(public.fleet_cargo_qty(p_fleet, 'gunpowder'), 0), coalesce(public.fleet_cargo_qty(p_fleet, 'shot-and-ball'), 0))
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;
  -- ── 4. THE HUNKS ──
  create temp table hunks_0520 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0520 values
  ('public.round_terms(uuid,text,jsonb)', 1,
$h$  v_why   text;
begin
$h$,
$h$  v_why   text;
  v_am    numeric;   -- 0520: units of each ammo good a round
begin
$h$),
  ('public.round_terms(uuid,text,jsonb)', 2,
$h$  select m.n, m.why into v_most, v_why
$h$,
$h$  v_am := public.round_ammo_need(p_fleet, w.ammo);   -- 0520
  select m.n, m.why into v_most, v_why
$h$),
  ('public.round_terms(uuid,text,jsonb)', 3,
$h$                 ((p_stop->>'rounds')::numeric, 'rounds', 4),
$h$,
$h$                 (case when v_am > 0 then floor(public.round_ammo_aboard(p_fleet) / v_am) end, 'ammo', 3),   -- 0520
                 ((p_stop->>'rounds')::numeric, 'rounds', 4),
$h$),
  ('public.round_terms(uuid,text,jsonb)', 4,
$h$'food', v_fr, 'water', v_wr,
$h$,
$h$'food', v_fr, 'water', v_wr, 'ammo', v_am,
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 1,
$h$    select coalesce(jsonb_agg(z.l order by z.o), '[]'::jsonb) into v_log
$h$,
$h$    -- 0520: the ammo of the rounds booked, whole units by the running fraction, of each good
    if coalesce((r.terms->>'ammo')::numeric, 0) > 0 then
      perform public.fleet_unload(p_fleet, g.code, floor((r.terms->>'ammo')::numeric * (r.booked + v_n)) - floor((r.terms->>'ammo')::numeric * r.booked))
         from (values ('gunpowder'), ('shot-and-ball')) g(code);
    end if;
    select coalesce(jsonb_agg(z.l order by z.o), '[]'::jsonb) into v_log
$h$),
  ('public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 1,
$h$when 'crew' then 'not enough crew above the least for one round'$h$,
$h$when 'ammo' then 'not enough ammo for one round' when 'crew' then 'not enough crew above the least for one round'$h$),
  ('public.round_plan(uuid)', 1,
$h$when 'crew' then 'not enough crew for a round'$h$,
$h$when 'ammo' then 'not enough ammo for a round' when 'crew' then 'not enough crew for a round'$h$),
  ('public.round_plan(uuid)', 2,
$h$  v_dmg := public.fleet_damage_pct(p_fleet);
$h$,
$h$  -- 0520: the ammo to hold, where the quay sells it, as far as her hold, her purse and the day allow
  if j.params ? 'ammo' and public.ammo_on() then
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('text', format('BUY %s %s', z.code, z.n)) order by z.code), '[]'::jsonb) into v_lines
      from (select g.code, trim_scale(floor(least((j.params->>'ammo')::numeric - coalesce(public.fleet_cargo_qty(p_fleet, g.code), 0),
                                                  (public.fleet_buy_capacity(p_fleet, g.id)->>'max_qty')::numeric))) as n
              from public.goods g where g.code in ('gunpowder', 'shot-and-ball') and public.port_offers(f.port_id, g.id)
                and exists (select 1 from public.port_goods pg where pg.port_id = f.port_id and pg.good_id = g.id)) z
     where z.n >= 1;
  end if;
  v_dmg := public.fleet_damage_pct(p_fleet);
$h$),
  ('public.round_job_param(uuid,uuid,jsonb)', 1,
$h$('days', 1, 120, 'the days of food and water')) t(code, lo, hi, word) loop
    continue when coalesce(jsonb_typeof(p_params->k.code), 'null') = 'null';$h$,
$h$('days', 1, 120, 'the days of food and water'), ('ammo', 1, 10000, 'the ammo')) t(code, lo, hi, word) loop
    continue when coalesce(jsonb_typeof(p_params->k.code), 'null') = 'null';$h$);

  for x in select distinct h.fn from hunks_0520 h loop
    v_pre := (select p.def from pre_0520 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0520 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0520 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0520 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0520 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0520 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0520 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0520 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.ammo_on() then
    raise exception '0520 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0520 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 5. THE PROBE (its own company, work, stores; rolled back) ──
  begin
    declare
      v_pl uuid; v_fl uuid; d jsonb; t jsonb; v_g0 numeric; v_s0 numeric; v_lis uuid; v_plan jsonb; v_o jsonb; v_e text; v_k int;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0520', 'PRT');
      select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_pl;
      update public.players set ducats = 10000000 where id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate');
      insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct, ammo) values ('probe_work', 99, 'sea', 'Probe', 'exploration', 600, 0, 0, 0, 0.2);
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 10, water_t = 20 where s.fleet_id = v_fl;
      d := public.round_terms(v_fl, 'probe_work', '{}');
      update public.world_config set value = 'true'::jsonb where key = 'ammo_enabled';
      -- her attack is whatever her hull has; the work's figure is set so a round is 1.5 units of each
      update public.round_works set ammo = 150 / greatest(0.0001, coalesce((select sum((world.ship_stats(s.id)->>'attack')::numeric) from public.ships s where s.fleet_id = v_fl), 0)) where code = 'probe_work';
      if coalesce((select sum((world.ship_stats(s.id)->>'attack')::numeric) from public.ships s where s.fleet_id = v_fl), 0) = 0 then
        -- an unarmed hull: she shoots nothing; her cost is given here as a round's own, through the terms of a run
        v_k := 0;
      else
        v_k := 1;
      end if;
      perform public.fleet_load(v_fl, 'gunpowder', 20, 1);
      perform public.fleet_load(v_fl, 'shot-and-ball', 10, 1);
      t := public.round_terms(v_fl, 'probe_work', '{"rounds": 30}');
      perform public.round_send_for(v_pl, v_fl, 'probe_work', '{"rounds": 30}', now());
      update public.round_runs set terms = terms || '{"ammo": 1.5, "most": 6}', stop_at = sent_at + interval '3600 seconds' where fleet_id = v_fl;
      update public.fleets set busy_until = now() + interval '3600 seconds' where id = v_fl;
      perform public.round_settle(v_fl, now() + interval '601 seconds');
      v_g0 := public.fleet_cargo_qty(v_fl, 'gunpowder');
      perform public.round_settle(v_fl, now() + interval '2 hours');
      v_s0 := public.fleet_cargo_qty(v_fl, 'shot-and-ball');
      perform cmd.assume_identity(c_ua);
      v_o := cmd.set_fleet_job(v_fl, 'round', '{"work": "probe_work", "ammo": 30}');
      update public.port_goods pg set stock = 5000, stock_target = 5000 from public.goods g where g.id = pg.good_id and g.code = 'gunpowder' and pg.port_id = v_lis;
      v_plan := public.fleet_job_plan(v_fl);
      raise exception using errcode = 'ZX520', message = jsonb_build_object('dark', d->'ammo', 'guns', v_k, 'why', t->>'why', 'most', t->'most', 'ammo', t->'ammo', 'after1', v_g0, 'after6', v_s0, 'aboard', public.round_ammo_aboard(v_fl),
        'job', v_o #> '{params,ammo}', 'offers', public.port_offers(v_lis, (select g.id from public.goods g where g.code = 'gunpowder')) and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id where g.code = 'gunpowder' and pg.port_id = v_lis),
        'line', v_plan #>> '{lines,0,text}')::text;
    end;
  exception when sqlstate 'ZX520' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce((v_l->>'dark')::numeric = 0 and case when v_l->>'guns' = '1' then v_l->>'why' = 'ammo' and (v_l->>'most')::int = 6 else (v_l->>'ammo')::numeric = 0 end
     and (v_l->>'after1')::numeric = 19 and (v_l->>'after6')::numeric = 1 and (v_l->>'aboard')::numeric = 1 and (v_l->>'job')::int = 30
     and case when (v_l->>'offers')::boolean then v_l->>'line' ~ '^BUY gunpowder [0-9]+$' else true end, false) then
    raise exception '0520 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0520') or public.ammo_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0520 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0520 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0520 self-assert ok: AMMO (dark). Hunks once and reversing; no other function moved; three functions server only. Probe (rolled back): % . % ms.', v_l, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0520;
  drop table pre_0520;
end $m$;
