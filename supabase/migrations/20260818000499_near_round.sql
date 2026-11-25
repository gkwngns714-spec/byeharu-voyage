-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights near_round_enabled)
-- 0499 - THE NEAR ROUND  (dark: the owner's switch near_round_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD, 2026-11-25: "a `best` job with params {within: nm}: each cycle takes the best paying good/harbour within it by the server's
--   own quotes, never at a loss, sails home when nothing does, waits there as 0498 waits. One authority: extend the best plan, no
--   second planner. Offered in world.actions first. Served `sentence` in plain words."
--   Measured first (docs/dev-log/2026-11-25-what-binds-a-repeat.md): a waiting Repeat is stopped by its own price after 1 to 8 runs a
--   day; a round over many goods that sails home when nothing pays made 2,700 to 23,000 coin an hour at 40,000 coin, 5 to 50 times
--   the Repeat, at all five homes.
--
-- WHAT (lit; dark every body answers as before):
--   public.near_round_on()         THE SWITCH, read once: world_config near_round_enabled.
--   public.near_round_params       THE DOOR'S JUDGE for a `best` job's settings. None sent: {} (the Best run, as before). `within` sent,
--                                  dark: E_NOT_IN_USE. Lit: {within: nm, base: code}: `within` a number, held between 50 and 3,000
--                                  nautical miles HERE (no knob); `base` a harbour of her choice, else her home harbour
--                                  (public.home_port_of); none: E_NO_HOME.
--   public.lines_nm                the sea miles of a plan's SAIL lines (their courses, as voyage.segments_from_course measures them).
--   public.near_round_sentence     its plain words: "Trade near Lisbon".
--   public.near_round_action       the option world.actions serves first (id sea:near), in the one shape, with what the door takes.
--   public.fleet_job_set_for       (1 hunk) a `best` job's settings are public.near_round_params' answer.
--   public.fleet_job_plan          (2 hunks) THE BEST PLAN, EXTENDED (no second planner). A job with `within`: a card whose sale's lines
--                                  (public.sale_lines: 0494's harbour legs) are longer than `within` is passed over, so she takes the
--                                  best paying card, by profit a second, within her round. None pays: away from her base she sails to
--                                  it (public.fleet_job_sails); at her base she WAITS as 0498 waits ({wait: low}: asked again 10
--                                  minutes on, not stopped). Its cards are the ones 0498 cuts (public.cards_fit).
--   public.workers_for             (2 hunks) her action's id is sea:near and it carries `within`, `base` and `sentence`.
--   public.sea_actions_for         (1 hunk) the near round stands first in world.actions' options.
-- NEVER AT A LOSS: a card is taken only with a profit above nought (the best plan's own filter); lit with 0498, for the units its
--   sale's harbour takes. The sail home carries nothing and costs its wages and stores: that is in her ledger, and in her measured rate.
-- NO per_hour IS SERVED FOR IT (basis `none`). A round's hour depends on what the next harbours pay, which only world.best_sales
--   read THERE can say: a day of it cannot be simulated in a read without a best_sales read a harbour (a second each), and one card
--   over its seconds is wrong by tens of times (0496's measurement of the Best run). Her own runs give it (basis `runs`, 0496).
-- NOT DONE, SAID: "prefers legs that end where something pays". What pays at a card's far end is a world.best_sales read there; the plan
--   makes ONE such read (where she lies) and no more. She takes the best card within her round and comes home when nothing pays.
-- COST, BOUNDED: one plan a job a tick, as before (public.tick_fleet_jobs: its receipt carries plan_ms). The plan's one
--   world.best_sales read is the one it made already; `within` adds one sum of course miles a card looked at. A round with nothing to
--   do at her base is one plan in 600 s (0498's wait).
-- NOT CHANGED: any knob but the new switch; world.best_sales; any command's name; any table; the ledger; a job without `within`.
-- ROWS: one world_config row. No table, no index, no cron, no beat step. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit: a near round is the Best job's rows (orders, voyages) at
--   the Best job's pace; no new kind of row.
-- LOCKS: one INSERT (world_config); CREATE FUNCTION x5; CREATE OR REPLACE x4 by hunks. TIME: a few seconds. BUDGET: statement_timeout
--   90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, near_round_enabled false (the door refuses `within`; a job that carries it plans as the Best
--   run). FULL: a migration reversing the six hunks (OLD texts below verbatim) and dropping the five functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the new functions server only; one knob added (false), no other moved. THE PROBE (rolled back): dark, the door
--   refuses `within`, world.actions starts with the Best run and a best plan is what it was; lit, the near round stands first with
--   its sentence and no rate, the door keeps {within, base} and holds `within` in its bounds, her plan sails within her round, a round
--   too small to reach a sale waits at her base and sails to her base from elsewhere, and her row says what she does.
--   THE PROBE'S PAYING SALE IS BUILT, NEVER FOUND (2026-11-25, after 0498 was refused on prod by a probe that read the live market):
--   the first good Lisbon offers, in world.best_sales' own order (so a read its 2.5 s budget cuts still carries it), and her nearest
--   remembered harbour that takes it; the two market rows of that good the quote reads (public.port_goods) are written inside the
--   probe: Lisbon at the price band's floor, the harbour at its ceiling. A Best run at Lisbon therefore plans with any market (empty
--   quays, every price at its floor, no price differing: each refused the probe before), and a sale within 1,440 miles pays. A plan
--   compared with a plan (two time-budgeted reads) is asked again, twice at most, before it is held to differ. No real company's
--   job is asked: the probe plans her own job (public.fleet_job_plan) and never runs the tick.
-- VERSION: 0499 (after 0498 `jobs-never-lose`).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'public.fleet_job_plan(uuid)', 'public.workers_for(uuid)',
                                    'public.sea_actions_for(uuid,uuid)'];
  c_new    constant text[] := array['public.near_round_on()', 'public.near_round_params(uuid,jsonb)', 'public.lines_nm(jsonb)',
                                    'public.near_round_sentence(text)', 'public.near_round_action(uuid)'];
  c_uid    constant uuid := '00000000-0499-4000-8000-000000000001';
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
  v_fl        uuid;
  v_lis       uuid;
  v_x         uuid;
  v_a         jsonb;
  v_r         jsonb;
  v_p         jsonb;
  v_p0        jsonb;
  v_w         jsonb;
  v_note      text := '';
  v_good      text;
  v_gid       uuid;
  v_sell      text;
  v_dest      uuid;
  v_rq        jsonb;
  v_same      boolean := false;
  v_try       int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'near_round_enabled') or to_regprocedure('public.near_round_on()') is not null then
    raise exception '0499 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.jobs_wait_on()') is null or to_regprocedure('public.cards_fit(uuid,uuid,uuid,jsonb,integer,boolean)') is null
     or to_regprocedure('public.sale_lines(uuid,uuid,jsonb,jsonb)') is null or to_regprocedure('public.fleet_job_sails(uuid,uuid,text[])') is null
     or to_regprocedure('public.home_port_of(uuid)') is null or to_regprocedure('public.sea_actions_for(uuid,uuid)') is null then
    raise exception '0499 refuses: 0498 (the jobs wait), 0496 (the workers), 0494 (the harbour legs) or 0482 (a sale''s lines) is not in this world';
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

  -- ── 2. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('near_round_enabled', 'false'::jsonb,
     '0499: THE SWITCH (the owner''s). true: cmd.set_fleet_job ''best'' takes {within: nautical miles, base: a harbour}: a NEAR ROUND. Each run she takes the best paying sale within those miles of where she lies; when nothing pays she sails to her base (her home harbour unless named) and waits there, asked again 10 minutes on; world.actions offers it first. false: the door refuses `within`, and a job that carries it plans as the Best run.');

  -- ── 3. THE RULES ──
  execute $f$
create function public.near_round_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0499: THE SWITCH, read once: world_config near_round_enabled.
  select public.wc('near_round_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.near_round_sentence(p_base text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0499: A NEAR ROUND IN PLAIN WORDS, by its base harbour's name: "Trade near Lisbon".
  select 'Trade near ' || coalesce((select p.name from public.ports p where p.code = p_base), 'home')
$body$
  $f$;

  execute $f$
create function public.lines_nm(p_lines jsonb)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0499: THE SEA MILES OF A PLAN'S LINES: its SAIL lines' courses, as voyage.segments_from_course measures them (the miles
  -- cmd.issue_lines will sail; public.job_trip's own sum). A line with no course adds none.
  select coalesce(sum((s->>'nm')::numeric), 0)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
   cross join lateral jsonb_array_elements(voyage.segments_from_course(l->'path')) s
   where jsonb_typeof(l->'path') = 'array'
$body$
  $f$;

  execute $f$
create function public.near_round_params(p_player uuid, p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0499: THE DOOR'S JUDGE FOR A `best` JOB'S SETTINGS (public.fleet_job_set_for). No `within`: {} (the Best run: what the door kept
-- before). `within`: a NEAR ROUND. Dark: E_NOT_IN_USE. Lit: {within, base}: `within` nautical miles, a number, held between c_min and
-- c_max here; `base` the harbour she comes back to: the one named, else her home harbour (public.home_port_of). Refusals raise
-- 'E_CODE: sentence' (the door makes the envelope).
declare
  c_min  constant numeric := 50;
  c_max  constant numeric := 3000;
  v_base text;
begin
  if not (coalesce(p_params, '{}'::jsonb) ? 'within') then
    return '{}'::jsonb;
  end if;
  if not public.near_round_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'a near round is not open yet');
  end if;
  if jsonb_typeof(p_params->'within') <> 'number' then
    perform cmd.refuse('E_BAD_ORDER', 'a near round names its miles');
  end if;
  if p_params->>'base' is not null then
    v_base := (select p.code from public.ports p where p.code = p_params->>'base' and p.kind = 'HARBOUR');
    if v_base is null then
      perform cmd.refuse('E_NO_SUCH_PORT', 'no harbour is called that');
    end if;
  else
    v_base := (select p.code from public.ports p where p.id = public.home_port_of(p_player) and p.kind = 'HARBOUR');
    if v_base is null then
      perform cmd.refuse('E_NO_HOME', 'a near round needs a harbour to come back to');
    end if;
  end if;
  return jsonb_build_object('within', round(greatest(c_min, least(c_max, (p_params->>'within')::numeric))), 'base', v_base);
end
$body$
  $f$;

  execute $f$
create function public.near_round_action(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0499: THE NEAR ROUND AS world.actions OFFERS IT, in the one shape (public.action_shape): id sea:near, what the door takes
-- (cmd.set_fleet_job 'best' {within: 1440}), its base (her home harbour) and its plain sentence. NO RATE (basis none, the figures
-- null): what a round brings an hour is what the next harbours pay, which no read here knows; her own runs say it (basis runs).
declare
  c_within constant numeric := 1440;
  v_base   text := (select p.code from public.ports p where p.id = public.home_port_of(p_player) and p.kind = 'HARBOUR');
begin
  return public.action_shape('sea:near', 'sea', 'trading', 1, null, null, null, null, null, null, 'none',
    jsonb_build_object('job', jsonb_build_object('kind', 'best', 'params', jsonb_build_object('within', c_within)),
                       'within', c_within, 'base', v_base, 'sentence', public.near_round_sentence(v_base), 'returns', true, 'varies', true));
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0499 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0499 values
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  if p_kind = 'best' then
    v_p := '{}'::jsonb;
$h$,
$h$  if p_kind = 'best' then
    -- 0499: {} as before, or a near round's {within, base} (public.near_round_params; dark it refuses `within`)
    v_p := public.near_round_params(p_player, p_params);
$h$),
  ('public.fleet_job_plan(uuid)', 1,
$h$      v_s := public.sale_lines(f.id, f.port_id, s.e, v_stops->(s.e->>'port'));
      continue when v_s ? 'missing';
$h$,
$h$      v_s := public.sale_lines(f.id, f.port_id, s.e, v_stops->(s.e->>'port'));
      continue when v_s ? 'missing';
      -- 0499 (near_round_enabled): a near round passes over a sale farther than its miles
      continue when j.params ? 'within' and public.near_round_on() and public.lines_nm(v_s->'lines') > (j.params->>'within')::numeric;
$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$    return jsonb_build_object('wait', 'nothing');
  end if;
end
$h$,
$h$    -- 0499 (near_round_enabled): A NEAR ROUND WITH NOTHING PAYING WITHIN ITS MILES. Away from her base she sails to it (0494's legs); at
    -- her base she waits as 0498 waits (public.fleet_job_note: asked again 10 minutes on; not stopped)
    if j.params ? 'within' and public.near_round_on() then
      if j.params->>'base' is not null and v_at is distinct from j.params->>'base' then
        v_s := public.fleet_job_sails(f.id, f.port_id, array[j.params->>'base']);
        if v_s ? 'missing' then
          return jsonb_build_object('pause', coalesce(v_s->>'pause', 'E_NO_COURSE'),
                                    'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing')));
        end if;
        return jsonb_build_object('lines', v_s->'lines', 'version', f.version,
                                  'note', jsonb_build_object('kind', 'best', 'from', v_at, 'to', j.params->>'base', 'leg', 'home'));
      end if;
      return jsonb_build_object('wait', 'low', 'sentence', 'prices low');
    end if;
    return jsonb_build_object('wait', 'nothing');
  end if;
end
$h$),
  ('public.workers_for(uuid)', 1,
$h$      v_id := case r.jkind when 'best' then 'sea:best'
$h$,
$h$      v_id := case r.jkind when 'best' then case when r.params ? 'within' then 'sea:near' else 'sea:best' end   -- 0499: a near round
$h$),
  ('public.workers_for(uuid)', 2,
$h$        'returns', r.jkind <> 'best', 'varies', r.jkind = 'best', 'left', r.params->'left'));
$h$,
$h$        'returns', r.jkind <> 'best' or r.params ? 'within', 'varies', r.jkind = 'best', 'left', r.params->'left',
        -- 0499: a near round's miles, its base and its plain words
        'within', r.params->'within', 'base', r.params->'base',
        'sentence', case when r.jkind = 'best' and r.params ? 'within' then public.near_round_sentence(r.params->>'base') end));
$h$),
  ('public.sea_actions_for(uuid,uuid)', 1,
$h$      jsonb_build_array(coalesce(v_best, public.action_shape('sea:best', 'sea', 'trading', 1, null, null, null, null, null, null, 'none',
$h$,
$h$      -- 0499 (near_round_enabled): the near round first (public.near_round_action)
      case when public.near_round_on() then jsonb_build_array(public.near_round_action(p_player)) else '[]'::jsonb end ||
      jsonb_build_array(coalesce(v_best, public.action_shape('sea:best', 'sea', 'trading', 1, null, null, null, null, null, null, 'none',
$h$);

  for v_h in select h.fn from hunks_0499 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0499 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0499 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0499 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0499 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0499 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the knob ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0499 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0499 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef) <> 5
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0499 self-assert FAIL: a new function is reachable by a client or service_role, or is not a definer';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> 'near_round_enabled') <> v_cfg_before
     or public.wc('near_round_enabled') is distinct from 'false'::jsonb or public.near_round_on() then
    raise exception '0499 self-assert FAIL: a knob other than near_round_enabled moved, or the switch is not false';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel (its own company's rows alone) ──
  begin
    v_me := public.new_house(c_uid, 'Casa da Ronda 0499', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.players p set ducats = 40000 where p.id = v_me;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'jobs_wait_enabled');
    perform cmd.assume_identity(c_uid);

    -- THE PAYING SALE, BUILT (the header): static rows choose the pair, the market chooses nothing
    select g.code, g.id, k.code, k.to_port into v_good, v_gid, v_sell, v_dest
      from public.npc_known_legs(v_lis) k
      join public.port_goods ps on ps.port_id = k.to_port
      join public.goods g on g.id = ps.good_id
      join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
     where public.port_offers(v_lis, g.id)
       and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
       and not public.culture_refuses(pd.culture, g.culture_mask)
       and public.fleet_free_hold(v_fl) >= 20 * g.bulk
       and k.nm <= 1440
     order by g.code, k.nm, k.code limit 1;
    if v_good is null then
      raise exception '0499 self-assert FAIL: the probe found no good Lisbon offers that a remembered harbour within 1,440 miles takes (static rows, not the market)';
    end if;
    update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0,
                                    glut = 0.5, glut_at = now(), haul = 1
     where pg.port_id = v_lis and pg.good_id = v_gid;
    update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0,
                                    glut = -0.5, glut_at = now()
     where pg.port_id = v_dest and pg.good_id = v_gid;
    v_rq := public.fleet_run_quote(v_me, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    if coalesce((v_rq->>'net')::numeric, 0) <= 0 then
      raise exception '0499 self-assert FAIL: the probe did not build a paying run (% from LIS to %, floor against ceiling): % ; the fault is the probe''s, not the market''s',
        v_good, v_sell, v_rq;
    end if;

    -- (a) DARK: the door refuses `within`; world.actions starts with the Best run; a best job's settings and plan are what they were
    v_r := cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 1440));
    v_a := world.actions('fleet:' || v_fl);
    if (v_r->>'ok')::boolean is not false or v_r::text not like '%E_NOT_IN_USE%'
       or v_a #>> '{options,0,id}' <> 'sea:best' or exists (select 1 from jsonb_array_elements(v_a->'options') e where e->>'id' = 'sea:near') then
      raise exception '0499 self-assert FAIL: dark, the door took a near round or world.actions offers one: % / %', v_r, left(v_a::text, 300);
    end if;
    v_r := cmd.set_fleet_job(v_fl, 'best', '{}'::jsonb);
    v_p0 := public.fleet_job_plan(v_fl);
    if (v_r->>'ok')::boolean is not true or v_r->'params' <> '{}'::jsonb or not (v_p0 ? 'lines') then
      raise exception '0499 self-assert FAIL: dark, the Best run is not set or planned as before: % / %', v_r, left(v_p0::text, 300);
    end if;

    -- (b) LIT: the near round first, with its sentence and no rate; the door keeps {within, base}, and holds the miles in bounds
    update public.world_config set value = 'true'::jsonb where key = 'near_round_enabled';
    -- two plans are two time-budgeted reads (world.best_sales, 2.5 s): a pair that differs is asked again, dark then lit, twice at most
    for v_try in 1 .. 3 loop
      v_p := public.fleet_job_plan(v_fl);
      v_same := v_p - 'version' is not distinct from v_p0 - 'version';
      exit when v_same or v_try = 3;
      update public.world_config set value = 'false'::jsonb where key = 'near_round_enabled';
      v_p0 := public.fleet_job_plan(v_fl);
      update public.world_config set value = 'true'::jsonb where key = 'near_round_enabled';
    end loop;
    if not v_same or not (v_p0 ? 'lines') then
      raise exception '0499 self-assert FAIL: lit, a Best run with no `within` is planned otherwise: dark % / lit %', left(v_p0::text, 300), left(v_p::text, 300);
    end if;
    v_a := world.actions('fleet:' || v_fl);
    if v_a #>> '{options,0,id}' <> 'sea:near' or v_a #>> '{options,1,id}' <> 'sea:best' or v_a #>> '{options,0,basis}' <> 'none'
       or jsonb_typeof(v_a #> '{options,0,per_hour}') <> 'null' or v_a #>> '{options,0,sentence}' <> 'Trade near Lisbon'
       or v_a #> '{options,0,job}' <> jsonb_build_object('kind', 'best', 'params', jsonb_build_object('within', 1440)) or v_a #>> '{options,0,base}' <> 'LIS' then
      raise exception '0499 self-assert FAIL: lit, the near round is not offered first as written: %', v_a #> '{options,0}';
    end if;
    v_r := cmd.set_fleet_job(v_fl, v_a #>> '{options,0,job,kind}', v_a #> '{options,0,job,params}');
    v_w := world.workers() #> '{workers,0}';
    if (v_r->>'ok')::boolean is not true or v_r->'params' <> jsonb_build_object('within', 1440, 'base', 'LIS')
       or v_w #>> '{action,id}' <> 'sea:near' or v_w #>> '{action,sentence}' <> 'Trade near Lisbon' or (v_w #>> '{action,within}')::numeric <> 1440
       or v_w #>> '{action,base}' <> 'LIS' or jsonb_typeof(v_w #> '{action,per_hour}') <> 'null' then
      raise exception '0499 self-assert FAIL: the door did not take the offered near round, or her row is not it: % / %', v_r, v_w;
    end if;
    if (cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 99999)) #>> '{params,within}')::numeric <> 3000
       or (cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 1)) #>> '{params,within}')::numeric <> 50
       or (cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 'far')) ->> 'ok')::boolean is not false
       or (cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 500, 'base', 'NOWHERE')) ->> 'ok')::boolean is not false then
      raise exception '0499 self-assert FAIL: the door does not hold a round''s miles in bounds or takes a bad setting';
    end if;

    -- (c) HER PLAN: within 1,440 miles a paying sale is taken and its lines are within the round
    v_r := cmd.set_fleet_job(v_fl, 'best', jsonb_build_object('within', 1440));
    v_p := public.fleet_job_plan(v_fl);
    if not (v_p ? 'lines') or public.lines_nm(v_p->'lines') > 1440 or public.lines_nm(v_p->'lines') <= 0 or (v_p #>> '{note,profit}')::numeric <= 0 then
      raise exception '0499 self-assert FAIL: a near round at Lisbon takes no paying sale within its miles: %', left(v_p::text, 400);
    end if;
    v_note := format('the sale built: %s from LIS to %s; at Lisbon within 1,440 nm: %s to %s, %s nm, +%s', v_good, v_sell, v_p #>> '{note,good}', v_p #>> '{note,to}', round(public.lines_nm(v_p->'lines')), v_p #>> '{note,profit}');

    -- (d) A ROUND TOO SMALL TO REACH ANY SALE (its miles written past the door's floor, on her own job's row): at her base she waits
    -- as 0498 waits; from another harbour she sails to her base
    update public.fleet_jobs set params = jsonb_build_object('within', 1, 'base', 'LIS') where fleet_id = v_fl;
    v_p := public.fleet_job_plan(v_fl);
    if v_p->>'wait' is distinct from 'low' or v_p ? 'lines' then
      raise exception '0499 self-assert FAIL: with nothing within her round she does not wait at her base: %', left(v_p::text, 300);
    end if;
    select k.to_port into v_x from public.npc_known_legs(v_lis) k join public.ports p on p.id = k.to_port
     where p.kind = 'HARBOUR' and public.fleet_job_course(v_fl, k.to_port, v_lis) is not null order by k.nm, k.code limit 1;
    update public.fleets set port_id = v_x where id = v_fl;
    v_p := public.fleet_job_plan(v_fl);
    if not (v_p ? 'lines') or v_p #>> '{note,leg}' <> 'home' or v_p #>> '{note,to}' <> 'LIS'
       or exists (select 1 from jsonb_array_elements(v_p->'lines') l where l->>'text' !~ '^SAIL ')
       or (select l->>'text' from jsonb_array_elements(v_p->'lines') with ordinality z(l, i) order by i desc limit 1) <> 'SAIL LIS' then
      raise exception '0499 self-assert FAIL: with nothing within her round, away from her base, she does not sail home: %', left(v_p::text, 400);
    end if;
    v_note := v_note || '; nothing within her round: she waits at her base, and sails to it from elsewhere';
    raise exception using errcode = 'ZX499', message = 'PROBE_ROLLBACK_0499';
  exception when sqlstate 'ZX499' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0499 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Ronda 0499' or p.auth_uid = c_uid) then
    raise exception '0499 self-assert FAIL: the probe left something behind';
  end if;
  -- the new switch is false and every other knob is as the file found it (0498's may be lit by now)
  if public.wc('near_round_enabled') is distinct from 'false'::jsonb
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> 'near_round_enabled') <> v_cfg_before then
    raise exception '0499 self-assert FAIL: a switch is not as it was found after the probe';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0499 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0499 self-assert ok: THE NEAR ROUND (dark). Six hunks once and reversing; five new functions server only; no other function moved; one knob (near_round_enabled false). Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
