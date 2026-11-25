-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: this file lights nothing; the step that lights posts its own row, public.news_update('0514', ...))
-- 0514 - THE SEAS RELIT  (dark: this file installs the one guarded step that lights 0215's sea_conditions_bite, and does not run it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: the eight rungs are "GOOD"; "hange 내파 to English" (R11): the word is Wave resistance. The spec reverses row 369 ("remove sea limits entirely",
--   2026-11-23), so the switch is thrown again only WITH THE OWNER'S EYES ON THE RUNG TABLE: the step asks for the table's own mark, which only the read prints.
-- WHAT:
--   public.seas_relit_ready()  STABLE, server only. The rung table (rung, its seas with what each asks, its harbours), how many harbours each rung opens from Lisbon by
--        harbours joined through seas of that rung and below, `mark` (md5 of the table), and EVERY LIVE COMPANY: her Trading and Exploration levels, her rung (the lower),
--        and each fleet: where she lies, that sea and its rung, her wave resistance, inside or beyond her rung, the way home (open / pass / none), the harbours open to
--        her now, her standing job and whether its next harbour is shut. `beyond`, `trapped`, `jobs_shut` count them. It judges through the one gate's own readers
--        (public.sea_closed, public.sea_passes) whatever the switch says, and writes nothing.
--   public.seas_relit_light(p_mark)  VOLATILE, server only, THE STEP. Refuses (nothing changed) when lit already, when the mark is not the table's of this minute, when a
--        fleet has no way home, when the top rung does not open every harbour, or when fleet room is off. Else the switch, one news row, and the figures it lit on.
--   cmd.refusal_line (1 hunk)  the wall says "Wave resistance 12 / 30." where it said "Waves 12 / 30."
-- public.sea_conditions_light (0398) is not touched: it lights without the table. Use this step.
-- TO LIGHT (the lead, on the owner's word): scripts/ops/harness/seas-relit/before-0514.sql, show the owner the table and the companies beyond, then
--   select public.seas_relit_light('<mark>'); scripts/ops/harness/seas-relit/after-check.sql at +1, +10, +30 minutes.
-- ROLLBACK, at once: scripts/ops/harness/seas-relit/rollback-0514.sql (the switch false; every passage is judged as before; no row is undone).
-- ROWS: none (lit: one config row, one news row). No table, column, index, cron or knob.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Tick: 0. The read is the lead's once (about 60 ms a fleet, measured in proof 218), never a player's.
-- LOCKS: CREATE FUNCTION x2; CREATE OR REPLACE x1 by a hunk. TIME: a second. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK OF THE FILE: the hunk reversed, the two functions dropped.
-- SELF-ASSERT: the hunk once and reversing; no other function or knob moved; server only; the switch as it was found; a wrong mark is refused and changes nothing.
--   THE LIGHT ITSELF is played in proof 218 (its guards read every live fleet, so they belong to the moment of lighting on the world being lit).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['cmd.refusal_line(text,jsonb)']::text[];
  c_new    constant text[] := array['public.seas_relit_ready()', 'public.seas_relit_light(text)']::text[];
  c_gone   constant text[] := array[]::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';

begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0514 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0514 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;


  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  execute $f$
create function public.seas_relit_ready()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0514: THE READ BEFORE THE LIGHT (see the head of 0514). Reads every human company and fleet once: the lead's, never a player's. Writes nothing.
declare
  v_open  text[];
  v_n     int;
  v_reach jsonb := '{}'::jsonb;
  v_rungs jsonb;
  v_co    jsonb := '[]'::jsonb;
  v_fl    jsonb;
  v_beyond int := 0; v_trapped int := 0; v_jobs int := 0; v_fleets int := 0;
  v_title int;
  v_prog  jsonb;
  v_shut  text[];
  v_at    uuid;
  v_zone  text;
  v_home  uuid;
  v_way   text;
  v_in    boolean;
  v_next  text;
  h record; f record; k int;
begin
  select jsonb_agg(jsonb_build_object('rung', q.rung, 'harbours', q.n, 'seas', q.seas) order by q.rung) into v_rungs
    from (select z.title_min as rung, sum(x.n)::int as n,
                 jsonb_agg(jsonb_build_object('code', z.code, 'name', z.name, 'level', z.title_min, 'wave', z.wave_min) order by z.ord) as seas
            from public.sea_zones z
           cross join lateral (select count(*) as n from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id
                                where p.kind = 'HARBOUR' and o.zones[1] = z.code) x
           group by z.title_min) q;
  for k in select distinct z.title_min from public.sea_zones z order by 1 loop
    v_open := array['LIS']; v_n := 0;
    while cardinality(v_open) > v_n loop
      v_n := cardinality(v_open);
      select array_agg(distinct q.c) into v_open
        from (select unnest(v_open) as c union
              select b.code from public.ports a join public.sea_leg_asks s on s.from_port = a.id and s.title_min <= k join public.ports b on b.id = s.to_port
               where a.code = any (v_open) and a.kind = 'HARBOUR') q;
    end loop;
    v_reach := v_reach || jsonb_build_object(k::text, v_n);
  end loop;
  for h in select p.id, p.company_name, n.code as country from public.players p left join public.nations n on n.id = p.nation_id where not p.is_npc order by p.company_name, p.id loop
    v_title := public.title_level(h.id);
    v_prog := public.player_progress(h.id);
    v_fl := '[]'::jsonb;
    select p.id into v_home from public.ports p where p.code = public.sea_home(h.id);
    for f in select x.id, x.name, x.status, j.params, j.paused_reason, j.fleet_id is not null as job from public.fleets x left join public.fleet_jobs j on j.fleet_id = x.id
              where x.player_id = h.id order by x.name, x.id loop
      v_fleets := v_fleets + 1;
      v_shut := public.sea_closed(h.id, f.id);
      v_at := public.sea_lies(f.id);
      select o.zones[1] into v_zone from public.sea_leg_asks o where o.from_port = v_at and o.to_port = v_at;
      -- inside: her own level and hull would open the sea she lies in (the floors aside): the one rule, asked plainly
      v_in := public.sea_refusal(v_title, public.fleet_wave(f.id), array[v_zone]) is null;
      v_way := case when v_at = v_home then 'home'
                    when not coalesce((select a.zones && v_shut from public.sea_leg_asks a where a.from_port = v_at and a.to_port = v_home), true) then 'open'
                    when exists (select 1 from public.sea_passes(h.id, v_at)) then 'pass' else 'none' end;
      if not v_in or v_way = 'pass' then v_beyond := v_beyond + 1; end if;
      if v_way = 'none' then v_trapped := v_trapped + 1; end if;
      v_next := case when f.job then (select string_agg(p.code, ' ' order by p.code) from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id
                                       where p.kind = 'HARBOUR' and p.code in (f.params->>'buy', f.params->>'sell') and o.zones[1] = any (v_shut)) end;
      if v_next is not null then v_jobs := v_jobs + 1; end if;
      v_fl := v_fl || jsonb_build_object('fleet', f.name, 'status', f.status, 'at', (select p.code from public.ports p where p.id = v_at),
                'sea', v_zone, 'sea_rung', (select z.title_min from public.sea_zones z where z.code = v_zone), 'wave', public.fleet_wave(f.id), 'inside', v_in, 'way_home', v_way,
                'harbours_open', (select count(*) from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id
                                   where p.kind = 'HARBOUR' and not o.zones[1] = any (v_shut)),
                'kept', to_jsonb(public.seas_kept(f.id)), 'job_shut', v_next);
    end loop;
    v_co := v_co || jsonb_build_object('company', h.company_name, 'country', h.country, 'rung', v_title, 'trading', v_prog->'trading'->'level', 'exploration', v_prog->'exploration'->'level',
              'home', public.sea_home(h.id), 'fleets', v_fl);
  end loop;
  return jsonb_build_object('lit', public.sea_conditions_on(), 'fleet_room', public.fleet_room_on(),
           'mark', (select md5(string_agg(z.code || ':' || z.title_min || ':' || z.wave_min, ',' order by z.code)) from public.sea_zones z),
           'rungs', v_rungs, 'open_by_rung', v_reach, 'harbours', (select count(*) from public.ports p where p.kind = 'HARBOUR'),
           'companies', v_co, 'company_count', jsonb_array_length(v_co), 'fleets', v_fleets, 'beyond', v_beyond, 'trapped', v_trapped, 'jobs_shut', v_jobs);
end
$body$
  $f$;
  revoke all on function public.seas_relit_ready() from public, anon, authenticated, service_role;
  comment on function public.seas_relit_ready() is
    '0514: the read before the seas are lit again: the rung table and its mark, and every live company''s rung and where each fleet lies against it. Server only.';
  execute $f$
create function public.seas_relit_light(p_mark text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0514: THE ONE STEP THAT LIGHTS THE SEAS AGAIN (see the head of 0514): only with the mark of the rung table the owner was shown. Refuses, changing nothing, naming each guard.
declare
  v     jsonb := public.seas_relit_ready();
  v_why text[] := '{}';
begin
  if (v->>'lit')::boolean then
    raise exception 'seas_relit_light refuses: the seas are lit already' using errcode = 'P0001';
  end if;
  if p_mark is distinct from v->>'mark' then
    v_why := v_why || 'the mark is not the rung table''s of this minute (public.seas_relit_ready prints it: show the owner the table first)'::text;
  end if;
  if (v->>'trapped')::int > 0 then
    v_why := v_why || format('%s fleet(s) have no way home', v->>'trapped');
  end if;
  if (v->'open_by_rung'->>(select max(z.title_min)::text from public.sea_zones z))::int <> (v->>'harbours')::int then
    v_why := v_why || format('the top rung opens %s of %s harbours', v->'open_by_rung'->>(select max(z.title_min)::text from public.sea_zones z), v->>'harbours');
  end if;
  if not (v->>'fleet_room')::boolean then
    v_why := v_why || 'fleet_room_bite is off: a company cannot sail her big ship apart from her small one'::text;
  end if;
  if cardinality(v_why) > 0 then
    raise exception 'seas_relit_light refuses: %', array_to_string(v_why, '; ') using errcode = 'P0001';
  end if;
  update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'sea_conditions_bite';
  perform public.news_update('0514', 'Seas open by level and wave resistance', 'Seas open by level and wave resistance');
  return (v - 'rungs' - 'companies') || jsonb_build_object('lit', public.sea_conditions_on(), 'lit_at', now());
end
$body$
  $f$;
  revoke all on function public.seas_relit_light(text) from public, anon, authenticated, service_role;
  comment on function public.seas_relit_light(text) is
    '0514: THE step that lights sea_conditions_bite again, with the mark of the rung table the owner was shown. Server only.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0514 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0514 values
  ('cmd.refusal_line(text,jsonb)', 1,
$h$format('Waves %s / %s.'$h$,
$h$format('Wave resistance %s / %s.'$h$);

  for v_h in select h.fn from hunks_0514 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0514 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0514 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0514 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0514 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0514 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0514 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0514 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when p.proname = 'seas_relit_light' then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0514 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array[]::text[])) <> v_cfg_before then
    raise exception '0514 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. THE SWITCH AS FOUND; A WRONG MARK CHANGES NOTHING (rolled back either way) ──
  begin
    perform public.seas_relit_light('not the mark');
    raise exception '0514 self-assert FAIL: a wrong mark lit the seas';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'seas_relit_light refuses:%' then raise; end if;
    v_note := left(sqlerrm, 160);
  end;
  if cmd.refusal_line('E_SEA_CLOSED', '{"zone": "X", "zone_name": "X", "needs_title": 2, "title": 1, "needs_wave": 30, "wave": 12, "short_title": true, "short_wave": true}'::jsonb) not like '%Wave resistance 12 / 30.%' then
    raise exception '0514 self-assert FAIL: the wall does not say Wave resistance';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0514 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0514 self-assert ok: THE SEAS RELIT (dark: the switch as found). The hunk once and reversing; no other function or knob moved; two new functions server only; the step refuses a wrong mark: %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
