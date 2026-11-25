-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights artifacts_enabled)
-- 0524 - ARTIFACTS  (dark: artifacts_enabled. Slice `artifacts`, docs/design/rounds-2026-11-25.md section 8)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R3): "Also artifacts (uncommon - very rare) that can be given to the capital, for gold + reputation + special gear/ship (will add later)".
-- FOUND   a round of an expedition finds one by its own dice (voyage.rng by fleet, round and Send: the same run finds the same), by the tiers of the knob
--         artifact_tiers: uncommon 4 %, rare 1.5 %, very rare 0.5 %; from Exploration 15 twice as often. Kept with THE FLEET that found it
--         (public.fleet_artifacts: one row a fleet a tier): she must carry it home.
-- GIVEN   cmd.artifact_report(fleet): docked in her country's capital, all she carries: gold from THE CAPITAL'S PURSE (public.capital_pays, kind EXPEDITION) and
--         Reputation (kind `artifact`, not in the day's cap: 15, 60, 300). A capital that cannot pay: refused with the reason and she keeps them (E_CITY_BROKE);
--         nothing is minted and no Reputation is paid without the gold. Special gear and ships: LATER (the owner's word).
-- READ    world.rounds serves `artifacts`: [{fleet, tier, qty}] and the tiers' worth.
-- ROWS, lit: one row a fleet a tier, at most 3 a fleet; a report deletes them and writes a ledger row, two treasury rows, a Reputation row, an event.
-- budget: that. -- retention: none, bounded by construction: at most three rows a fleet, gone with it or with its report.
-- LOCKS: CREATE TABLE (a foreign key to fleets), rows of data, CREATE FUNCTION x4, CREATE OR REPLACE x3 by hunks.
-- ROLLBACK (forward, owner only): artifacts_enabled false: none is found and none is taken; what is kept stays. FULL: a migration reversing the hunks.
-- VERSION: 0524 (after 0523).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_finds(uuid,integer,integer,boolean,timestamp with time zone)', 'world.rounds(uuid)', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.artifacts_on()', 'public.round_artifacts(uuid,integer,integer)', 'public.artifact_report_for(uuid,uuid)']::text[];
  c_doors  constant text[] := array['cmd.artifact_report(uuid)']::text[];
  c_knobs  constant text[] := array['artifacts_enabled', 'artifact_tiers']::text[];
  c_ua     constant uuid := '00000000-0524-4000-8000-0000000000a1';
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
  if to_regprocedure('public.artifacts_on()') is not null then
    raise exception '0524 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.round_finds(uuid,integer,integer,boolean,timestamptz)']::text[]) f where to_regprocedure(f) is null) then
    raise exception '0524 refuses: what it stands on is not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0524 (fn text primary key, def text) on commit drop;
  insert into pre_0524 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
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
    ('artifacts_enabled', 'false'::jsonb, '0524: THE SWITCH (the owner''s). true: an expedition''s rounds may find artifacts, and a capital takes them for gold and Reputation.'),
    ('artifact_tiers', '[{"tier": "uncommon", "pct": 4, "gold": 400, "rp": 15}, {"tier": "rare", "pct": 1.5, "gold": 2500, "rp": 60}, {"tier": "very_rare", "pct": 0.5, "gold": 15000, "rp": 300}]'::jsonb, '0524: the artifacts: the chance a round in per cent, and what a capital gives for one (the owner: 15,000 and 300 at the top).');
  insert into public.reputation_kinds (code, sign, capped, word) values ('artifact', 1, false, 'Artifacts');
  -- retention: none, bounded by construction: at most three rows a fleet, gone with it or with its report
  create table public.fleet_artifacts (fleet_id uuid not null references public.fleets(id) on delete cascade, tier text not null check (tier in ('uncommon', 'rare', 'very_rare')), qty int not null check (qty > 0), primary key (fleet_id, tier));
  comment on table public.fleet_artifacts is '0524: the artifacts a fleet carries home (found on an expedition''s rounds, given by cmd.artifact_report at her capital). Server only.';
  alter table public.fleet_artifacts enable row level security;
  revoke all on table public.fleet_artifacts from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.artifacts_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0524: THE SWITCH, read once: world_config artifacts_enabled.
  select public.wc('artifacts_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_artifacts(p_fleet uuid, p_from integer, p_to integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0524: THE ARTIFACTS THE ROUNDS p_from .. p_to FOUND, kept with the fleet; {tier: count} of this call. One roll a round (voyage.rng by fleet, round and Send) on the
-- tiers' chances laid side by side (doubled from level 15 of the terms).
declare
  r     public.round_runs%rowtype;
  v_k   numeric;
  v_out jsonb := '{}'::jsonb;
  z     record;
begin
  if not public.artifacts_on() then
    return v_out;
  end if;
  select * into r from public.round_runs x where x.fleet_id = p_fleet;
  v_k := case when coalesce((r.terms->>'level')::int, 1) >= 15 then 2 else 1 end / 100.0;
  for z in
    select t.tier, count(*)::int as n
      from generate_series(p_from, p_to) g
      cross join lateral (select voyage.rng(p_fleet, g, 'artifact:' || extract(epoch from r.sent_at)::text) as roll) d
      join (select e->>'tier' as tier, coalesce(sum((e->>'pct')::numeric) over (order by o rows between unbounded preceding and 1 preceding), 0) * v_k as lo, sum((e->>'pct')::numeric) over (order by o) * v_k as hi
              from jsonb_array_elements(public.wc('artifact_tiers')) with ordinality q(e, o)) t on d.roll >= t.lo and d.roll < t.hi
     group by t.tier
  loop
    insert into public.fleet_artifacts as a (fleet_id, tier, qty) values (p_fleet, z.tier, z.n) on conflict (fleet_id, tier) do update set qty = a.qty + excluded.qty;
    v_out := v_out || jsonb_build_object(z.tier, z.n);
  end loop;
  return v_out;
end
$body$
  $f$;
  execute $f$
create function public.artifact_report_for(p_player uuid, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0524: A FLEET GIVES HER ARTIFACTS TO HER CAPITAL (server only; the door is cmd.artifact_report): all she carries, gold from the capital's purse, then Reputation.
declare
  f      public.fleets%rowtype;
  v_cap  uuid;
  v_nat  uuid;
  v_gold bigint;
  v_rp   int;
  v_n    int;
  v_w    jsonb;
  v_paid jsonb;
begin
  if not public.artifacts_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'artifacts are not open yet');
  end if;
  select * into f from public.fleets x where x.id = p_fleet for update;
  if f.id is null or f.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  select n.id, h.id into v_nat, v_cap from public.players p join public.nations n on n.id = p.nation_id left join public.ports h on h.code = n.capital_port_code and h.kind = 'HARBOUR' where p.id = p_player;
  if f.status <> 'DOCKED' or v_cap is null or f.port_id is distinct from v_cap then
    perform cmd.refuse('E_NOT_HOME', format('%s must lie in %s', f.name, coalesce((select h.name from public.ports h where h.id = v_cap), 'your capital')));
  end if;
  select sum(a.qty), sum(a.qty * (t.e->>'gold')::bigint), sum(a.qty * (t.e->>'rp')::int), jsonb_object_agg(a.tier, a.qty)
    into v_n, v_gold, v_rp, v_w
    from (select * from public.fleet_artifacts x where x.fleet_id = p_fleet for update) a
    join jsonb_array_elements(public.wc('artifact_tiers')) t(e) on t.e->>'tier' = a.tier;
  if coalesce(v_n, 0) < 1 then
    perform cmd.refuse('E_NO_CARGO', format('%s carries no artifact', f.name));
  end if;
  if not public.city_treasury_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'the cities'' purses are not open');
  end if;
  v_paid := public.capital_pays(v_cap, v_nat, p_player, 'EXPEDITION', v_gold, null, false,
              jsonb_build_object('kind', 'ARTIFACTS_GIVEN', 'payload', jsonb_build_object('fleet', f.name, 'port', (select h.code from public.ports h where h.id = v_cap), 'artifacts', v_w, 'gold', v_gold, 'rp', v_rp)));
  if coalesce((v_paid->>'paid')::bigint, 0) <= 0 then
    perform cmd.refuse('E_CITY_BROKE', format('%s cannot pay for them now', (select h.name from public.ports h where h.id = v_cap)));
  end if;
  delete from public.fleet_artifacts x where x.fleet_id = p_fleet;
  v_rp := public.reputation_credit(p_player, 'artifact', v_rp, null, jsonb_build_object('artifacts', v_w));
  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'artifacts', v_w, 'gold', v_gold, 'rp', v_rp);
end
$body$
  $f$;
  execute $f$
create function cmd.artifact_report(p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0524: give her artifacts to her capital (public.artifact_report_for). A refusal is the envelope.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.artifact_report_for(v_player, p_fleet);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
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
  create temp table hunks_0524 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0524 values
  ('public.round_finds(uuid,integer,integer,boolean,timestamp with time zone)', 1,
$h$  if p_over and coalesce($h$,
$h$  if p_to >= p_from and not p_over then   -- 0524: the artifacts these rounds found
    r.carry := r.carry || (select case when q.a = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('artifacts', coalesce(r.carry->'artifacts', '[]'::jsonb) || jsonb_build_array(q.a)) end
                             from (select public.round_artifacts(p_fleet, p_from, p_to) as a) q);
  end if;
  if p_over and coalesce($h$),
  ('world.rounds(uuid)', 1,
$h$  return jsonb_build_object('on', true, 'company', true, 'now', now(),
$h$,
$h$  return jsonb_build_object('artifacts', case when public.artifacts_on() then jsonb_build_object('tiers', public.wc('artifact_tiers'),   -- 0524
                              'kept', (select coalesce(jsonb_agg(jsonb_build_object('fleet', a.fleet_id, 'tier', a.tier, 'qty', a.qty) order by a.fleet_id, a.tier), '[]'::jsonb)
                                         from public.fleet_artifacts a join public.fleets f on f.id = a.fleet_id where f.player_id = v_me)) end,
                            'on', true, 'company', true, 'now', now(),
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'round_home',            'uuid'),
$h$,
$h$      ('cmd',         'round_home',            'uuid'),
      -- 0524: a fleet gives her artifacts to her capital (dark E_NOT_IN_USE)
      ('cmd',         'artifact_report',       'uuid'),
$h$);

  for x in select distinct h.fn from hunks_0524 h loop
    v_pre := (select p.def from pre_0524 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0524 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0524 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0524 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0524 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0524 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0524 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0524 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.artifacts_on() then
    raise exception '0524 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0524 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 5. THE PROBE (its own company, work, stores; rolled back) ──
  begin
    declare
      v_pl uuid; v_fl uuid; v_lis uuid; v_cap uuid; d text; a jsonb; b jsonb; x1 jsonb; x2 jsonb; v_p0 bigint; v_c0 numeric; v_e text; v_away text; n int;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0524', 'PRT');
      select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on', 'expedition_rounds_enabled');
      v_cap := (select h.id from public.ports h join public.nations q on q.capital_port_code = h.code join public.players p on p.nation_id = q.id where p.id = v_pl and h.kind = 'HARBOUR');
      perform cmd.assume_identity(c_ua);
      d := cmd.artifact_report(v_fl)->>'error_code';
      insert into public.round_runs (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms)
      values (v_fl, v_pl, 'expedition', (select h.sea_id from public.ports h where h.id = v_lis), 'home', now(), now(), '{"kind": "sea", "level": 1}');
      if public.round_artifacts(v_fl, 1, 500) <> '{}'::jsonb then raise exception 'dark finds'; end if;
      update public.world_config set value = 'true'::jsonb where key = 'artifacts_enabled';
      -- the dice of this run, 2,000 rounds: the same run finds the same, at once or in two; level 15 twice as often, every roll of level 1 among them
      x1 := public.round_artifacts(v_fl, 1, 2000);
      delete from public.fleet_artifacts q where q.fleet_id = v_fl;
      perform public.round_artifacts(v_fl, 1, 700);
      perform public.round_artifacts(v_fl, 701, 2000);
      x2 := (select coalesce(jsonb_object_agg(q.tier, q.qty), '{}'::jsonb) from public.fleet_artifacts q where q.fleet_id = v_fl);
      delete from public.fleet_artifacts q where q.fleet_id = v_fl;
      insert into public.fleet_artifacts (fleet_id, tier, qty) values (v_fl, 'uncommon', 2), (v_fl, 'very_rare', 1);
      update public.fleets set port_id = (select h.id from public.ports h where h.kind = 'HARBOUR' and h.id <> v_cap order by h.code limit 1) where id = v_fl;
      v_away := cmd.artifact_report(v_fl)->>'error_code';
      update public.fleets set port_id = v_cap where id = v_fl;
      insert into public.port_treasury (port_id) values (v_cap) on conflict (port_id) do nothing;
      update public.port_treasury set ducats = ducats + 50000000 where port_id = v_cap;
      v_p0 := (select p.ducats from public.players p where p.id = v_pl);
      select coalesce(sum(q.ducats), 0) into v_c0 from public.treasury_flows q where q.player_id = v_pl;
      a := cmd.artifact_report(v_fl);
      b := jsonb_build_object('gold', (select p.ducats from public.players p where p.id = v_pl) - v_p0, 'city', (select coalesce(sum(q.ducats), 0) from public.treasury_flows q where q.player_id = v_pl) - v_c0,
              'rp', (select coalesce(sum(q.delta), 0) from public.reputation_book q where q.player_id = v_pl and q.kind = 'artifact'), 'left', (select count(*) from public.fleet_artifacts q where q.fleet_id = v_fl),
              'again', cmd.artifact_report(v_fl)->>'error_code', 'read', world.rounds(null) #> '{artifacts,kept}');
      raise exception using errcode = 'ZX524', message = jsonb_build_object('dark', d, 'away', v_away, 'same', x1 = x2, 'found', x1, 'report', a, 'b', b)::text;
    end;
  exception when sqlstate 'ZX524' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce(v_l->>'dark' = 'E_NOT_IN_USE' and v_l->>'away' = 'E_NOT_HOME' and (v_l->>'same')::boolean and (v_l #>> '{report,ok}')::boolean and (v_l #>> '{b,gold}')::int = 15800 and (v_l #>> '{b,city}')::numeric = -15800
     and (v_l #>> '{b,rp}')::int = 330 and (v_l #>> '{b,left}')::int = 0 and v_l #>> '{b,again}' = 'E_NO_CARGO' and v_l #> '{b,read}' = '[]'::jsonb, false) then
    raise exception '0524 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0524') or public.artifacts_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0524 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0524 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0524 self-assert ok: ARTIFACTS (dark). Hunks once and reversing; no other function moved; three functions server only, one door. Probe (rolled back): % . % ms.', v_l, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0524;
  drop table pre_0524;
end $m$;
