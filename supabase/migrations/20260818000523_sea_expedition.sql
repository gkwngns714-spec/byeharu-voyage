-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights expedition_rounds_enabled)
-- 0523 - SEA EXPEDITIONS  (dark: expedition_rounds_enabled. Slice `sea-expedition`, docs/design/rounds-2026-11-25.md section 4.2)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R3): the expedition is a repeating activity with a log; it uses provisions and crew; "when your level is high enough, will provide
--   provisions"; crews die, the rate by the level; gold and Reputation.
-- A WORK OF KIND sea, as data: 15 minutes a round, half a day of food and water, 1 per cent of the hands less 0.04 a level of Exploration (never under 0.3),
--   and its yield (round_works.yield): {gold 30, rp 2, prov_level 8, prov 0.5}.
--   PROVISIONS   from Exploration 8 the rounds bring back half of what they eat (yield.prov): a round's food and water are that much less, so a run is twice
--                as long on the same stores. Frozen in the terms, so the stop stays arithmetic.
--   REPUTATION   yield.rp a round (kind `round`, in the day's cap), at each settle.
--   GOLD         yield.gold a round, paid when the run is over, OUT OF HER COUNTRY'S CAPITAL'S PURSE (public.capital_pays, kind EXPEDITION, moved). A capital that
--                cannot pay it pays nothing then: it waits in her run (carry.gold_due) and is asked again at the end of her next run. Nothing is minted.
-- If she is attacked: she sails no voyage while she works, so there is no raid on her and no RUN to order (R6's RUN stays what it is for voyages).
-- ROWS, lit: a settle 2 to 4 rows more (Reputation, a ledger row and two treasury rows at the end). -- budget: that. -- retention: none (no table).
-- LOCKS: rows of data, CREATE FUNCTION x2, CREATE OR REPLACE x3 by hunks.
-- ROLLBACK (forward, owner only): expedition_rounds_enabled false. FULL: a migration reversing the hunks and deleting the rows.
-- VERSION: 0523 (after 0522).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_settle(uuid,timestamp with time zone)', 'public.round_terms(uuid,text,jsonb)', 'public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 'public.round_home_for(uuid,uuid,timestamp with time zone)']::text[];
  c_new    constant text[] := array['public.expedition_rounds_on()', 'public.round_finds(uuid,integer,integer,boolean,timestamptz)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['expedition_rounds_enabled']::text[];
  c_ua     constant uuid := '00000000-0523-4000-8000-0000000000a1';
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
  if to_regprocedure('public.expedition_rounds_on()') is not null then
    raise exception '0523 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)', 'public.round_spoils(uuid,integer,integer,timestamptz)']::text[]) f where to_regprocedure(f) is null) then
    raise exception '0523 refuses: what it stands on is not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0523 (fn text primary key, def text) on commit drop;
  insert into pre_0523 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
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
    ('expedition_rounds_enabled', 'false'::jsonb, '0523: THE SWITCH (the owner''s). true: the work "expedition" may be sent on (while rounds_enabled).');
  insert into public.round_works (code, ord, kind, word, skill, level, seconds, food_days, water_days, crew_pct, crew_less, crew_least, ammo, yield, lit_by)
  values ('expedition', 2, 'sea', 'Expedition', 'exploration', 1, 900, 0.5, 0.5, 1, 0.04, 0.3, 0, '{"gold": 30, "rp": 2, "prov_level": 8, "prov": 0.5}', 'expedition_rounds_enabled');
  insert into public.stats_flow_words (kind, side, word, ord) values ('EXPEDITION', 'moved', 'Expeditions', (select max(w.ord) + 1 from public.stats_flow_words w));

  -- ── 3. THE RULES ──
  execute $f$
create function public.expedition_rounds_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0523: THE SWITCH, read once: world_config expedition_rounds_enabled.
  select public.wc('expedition_rounds_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_finds(p_fleet uuid, p_from integer, p_to integer, p_over boolean, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0523: WHAT THE ROUNDS p_from .. p_to OF AN EXPEDITION GAVE (public.round_settle calls it for the rounds it books, and once when the run is over): Reputation now;
-- the gold of all its rounds when it is over, from her country's capital, with what an earlier run was owed. The run's `carry`.
declare
  r      public.round_runs%rowtype;
  y      jsonb;
  v_rp   int := 0;
  v_due  bigint;
  v_cap  uuid;
  v_nat  uuid;
  v_paid jsonb;
begin
  select * into r from public.round_runs x where x.fleet_id = p_fleet;
  if r.terms->>'kind' is distinct from 'sea' then
    return r.carry;
  end if;
  select w.yield into y from public.round_works w where w.code = r.work;
  if p_to >= p_from and coalesce((y->>'rp')::int, 0) > 0 then
    v_rp := public.reputation_credit(r.player_id, 'round', (y->>'rp')::int * (p_to - p_from + 1), 'round:' || p_fleet || ':' || extract(epoch from r.sent_at)::text || ':' || p_to, jsonb_build_object('work', r.work));
    r.carry := r.carry || jsonb_build_object('rp', coalesce((r.carry->>'rp')::int, 0) + v_rp);
  end if;
  if p_over and coalesce((y->>'gold')::numeric, 0) > 0 then
    v_due := coalesce((r.carry->>'gold_due')::bigint, 0) + floor((y->>'gold')::numeric * p_to)::bigint;
    select n.id, h.id into v_nat, v_cap from public.players p join public.nations n on n.id = p.nation_id left join public.ports h on h.code = n.capital_port_code and h.kind = 'HARBOUR' where p.id = r.player_id;
    if v_due > 0 and v_cap is not null and public.city_treasury_on() then
      v_paid := public.capital_pays(v_cap, v_nat, r.player_id, 'EXPEDITION', v_due, null, false, null);
    end if;
    if coalesce((v_paid->>'paid')::bigint, 0) > 0 then
      r.carry := (r.carry - 'gold_due') || jsonb_build_object('gold', coalesce((r.carry->>'gold')::bigint, 0) + v_due);
    elsif v_due > 0 then
      r.carry := r.carry || jsonb_build_object('gold_due', v_due);
    end if;
  end if;
  return r.carry;
end
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;
  -- ── 4. THE HUNKS ──
  create temp table hunks_0523 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0523 values
  ('public.round_terms(uuid,text,jsonb)', 1,
$h$  v_am := public.round_ammo_need(p_fleet, w.ammo);   -- 0520
$h$,
$h$  if w.kind = 'sea' and (w.yield->>'prov_level')::int <= v_lv then   -- 0523: her level brings back a share of what a round eats
    v_fr := round(v_fr * (1 - (w.yield->>'prov')::numeric), 4);
    v_wr := round(v_wr * (1 - (w.yield->>'prov')::numeric), 4);
  end if;
  v_am := public.round_ammo_need(p_fleet, w.ammo);   -- 0520
$h$),
  ('public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 1,
$h$terms = excluded.terms, stop = excluded.stop, carry = '{}',$h$,
$h$terms = excluded.terms, stop = excluded.stop,
        carry = case when r.carry ? 'gold_due' then jsonb_build_object('gold_due', r.carry->'gold_due') else '{}'::jsonb end,   -- 0523: what a capital still owes her
       $h$),
  ('public.round_home_for(uuid,uuid,timestamp with time zone)', 1,
$h$  select x.booked into v_n from public.round_runs x where x.fleet_id = p_fleet;
$h$,
$h$  select x.booked into v_n from public.round_runs x where x.fleet_id = p_fleet;
  if exists (select 1 from public.round_runs x where x.fleet_id = p_fleet and x.state = 'out') then   -- 0523: called in before her stop: the gold of the rounds done
    update public.round_runs set carry = public.round_finds(p_fleet, v_n + 1, v_n, true, p_at) where fleet_id = p_fleet;
  end if;
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 1,
$h$    r.carry := public.round_spoils(p_fleet, r.booked + 1, r.booked + v_n, p_at);   -- 0522 (dark: the carry as it is)
$h$,
$h$    r.carry := public.round_spoils(p_fleet, r.booked + 1, r.booked + v_n, p_at);   -- 0522 (dark: the carry as it is)
    update public.round_runs set carry = r.carry where fleet_id = p_fleet and carry is distinct from r.carry;
    r.carry := public.round_finds(p_fleet, r.booked + 1, r.booked + v_n, false, p_at);   -- 0523
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 2,
$h$  if v_n = 0 and not v_over then
$h$,
$h$  if v_over and r.terms->>'kind' = 'sea' then   -- 0523: the run is over: its gold
    update public.round_runs set carry = r.carry where fleet_id = p_fleet and carry is distinct from r.carry;
    r.carry := public.round_finds(p_fleet, r.booked + 1, r.booked, true, p_at);
  end if;
  if v_n = 0 and not v_over then
$h$);

  for x in select distinct h.fn from hunks_0523 h loop
    v_pre := (select p.def from pre_0523 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0523 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0523 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0523 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0523 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0523 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0523 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0523 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.expedition_rounds_on() then
    raise exception '0523 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0523 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 5. THE PROBE (its own company, work, stores; rolled back) ──
  begin
    declare
      v_pl uuid; v_fl uuid; v_cap uuid; d text; t1 jsonb; t8 jsonb; a jsonb; b jsonb; v_p0 bigint; v_c0 numeric; v_r record;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0523', 'PRT');
      select f.id into v_fl from public.fleets f where f.player_id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on');
      update public.world_config set value = to_jsonb(600) where key = 'rep_day_cap';
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 3, water_t = 4 where s.fleet_id = v_fl;
      begin
        perform public.round_send_for(v_pl, v_fl, 'expedition', '{}', now());
      exception when sqlstate 'P0001' then d := sqlerrm;
      end;
      update public.world_config set value = 'true'::jsonb where key = 'expedition_rounds_enabled';
      t1 := public.round_terms(v_fl, 'expedition', '{"days": 0}');
      insert into public.house_level_marks (player_id, track, level) values (v_pl, 'exploration', 8) on conflict (player_id, track) do update set level = 8;
      t8 := public.round_terms(v_fl, 'expedition', '{"days": 0}');
      v_cap := (select h.id from public.ports h join public.nations n on n.capital_port_code = h.code join public.players p on p.nation_id = n.id where p.id = v_pl and h.kind = 'HARBOUR');
      insert into public.port_treasury (port_id) values (v_cap) on conflict (port_id) do nothing;
      update public.port_treasury set ducats = ducats + 50000000 where port_id = v_cap;
      perform public.round_send_for(v_pl, v_fl, 'expedition', '{"rounds": 4, "days": 0}', now());
      v_p0 := (select p.ducats from public.players p where p.id = v_pl);
      select coalesce(sum(q.ducats), 0) into v_c0 from public.treasury_flows q where q.player_id = v_pl;
      perform public.round_settle(v_fl, now() + interval '1 hour 5 minutes');
      select zr.* into v_r from public.round_runs zr where zr.fleet_id = v_fl;
      a := jsonb_build_object('carry', v_r.carry, 'state', v_r.state, 'gold', (select p.ducats from public.players p where p.id = v_pl) - v_p0, 'city', (select coalesce(sum(q.ducats), 0) from public.treasury_flows q where q.player_id = v_pl) - v_c0,
              'rp', (select coalesce(sum(q.delta), 0) from public.reputation_book q where q.player_id = v_pl and q.kind = 'round'));
      raise exception using errcode = 'ZX523', message = jsonb_build_object('dark', d, 'l1', t1, 'l8', t8, 'a', a)::text;
    end;
  exception when sqlstate 'ZX523' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce(v_l->>'dark' ~ '^E_NOT_IN_USE' and (v_l #>> '{l8,food}')::numeric = round((v_l #>> '{l1,food}')::numeric / 2, 4) and (v_l #>> '{l8,crew}')::numeric < (v_l #>> '{l1,crew}')::numeric
     and (v_l #>> '{l8,most}')::int > (v_l #>> '{l1,most}')::int and v_l #>> '{a,state}' = 'home' and (v_l #>> '{a,gold}')::bigint = 120 and (v_l #>> '{a,city}')::numeric = -120
     and (v_l #>> '{a,rp}')::int = 8 and (v_l #>> '{a,carry,gold}')::int = 120 and not (v_l #> '{a,carry}') ? 'gold_due', false) then
    raise exception '0523 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0523') or public.expedition_rounds_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0523 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0523 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0523 self-assert ok: SEA EXPEDITIONS (dark). Hunks once and reversing; no other function moved; two functions server only. Probe (rolled back): % . % ms.', v_l, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0523;
  drop table pre_0523;
end $m$;
