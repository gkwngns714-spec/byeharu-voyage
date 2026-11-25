-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0500 - FIT TO SAIL  (a repair of the standing fleet jobs of 0481 / 0494 / 0498; no switch, no knob, no table)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD'S PROD FACTS, 2026-11-24 (one company, one fleet docked at Island of Mozambique, towed there after a ransom on 23 Nov):
--   A. her stopped land job was retried: the tick said ok, runs 1, and two minutes later the job stopped with E_FLAGSHIP_DISABLED
--      "the flagship is not fit to sail". The plan and the job door asked nothing of her hull: seven SAIL lines were issued, the
--      first was refused when it ran (voyage.sail_refusal), cmd.release_failed cancelled the rest, and the next plan read that
--      failed order and stopped the job. A stop on that code waited for the player for ever.
--   B. that tick took 10,659 ms (its plan 3,055 ms) against 40-120 ms.
--   D. (the owner, 24 Nov about 23:43 UTC) read "Order 200 was refused: the flagship is not fit to sail ... Gaivota is free": order
--      200 had failed at 17:40 and she had been repaired at 23:36. A refused order stays in her served queue until dismissed (0186),
--      and the queue serves no time, so the client could not tell an old record from news. cmd.queue now serves when each order ran.
--   C. (the lead, 25 Nov) a job stopped on E_CREW_SHORT ("Crew 7 / 8" after a raid) is the same class: the sail's other gate that
--      no harbour between mends. She waits where crew can be hired, and goes on once manned.
--   Dev log docs/dev-log/2026-11-25-fit-to-sail.md. Reproduced locally to the letter before the hunks (this file's own scene).
--
-- WHAT:
--   public.fleet_unfit(fleet)     THE ONE FITNESS RULE, lifted whole out of voyage.sail_refusal, its two gates in their order: a ship
--                                 short of the crew she needs: cmd.refusal('E_CREW_SHORT', ...), which reads "Crew 7 / 8" (the crew
--                                 figures); her flagship's hull at 0 or under (or no flagship): cmd.refusal('E_FLAGSHIP_DISABLED',
--                                 'the flagship is not fit to sail'); else null. A fleet the one state rule calls wrecked
--                                 (public.fleet_state_of: no hull above 0) is always unfit by it: her flagship is one of her hulls.
--                                 STABLE, server only.
--   voyage.sail_refusal           (1 hunk) asks public.fleet_unfit where it counted her crew and read her flagship itself: the same
--                                 gates, in the same place and order, with the same answers. So the sail, the job tick and the job
--                                 door ask ONE rule.
--   public.port_hires(port)       CAN CREW BE HIRED AT THIS PORT? Hands on its quay (crew_pool above 0): the fact cmd.do_hire refuses
--                                 E_CREW_POOL by, lifted; cmd.do_hire (1 hunk) asks it here. STABLE, server only.
--   public.fleet_job_plan         (1 hunk) a docked, idle fleet that is not fit is NOT PLANNED: {wait: unfit, code, sentence}. No
--                                 course is read, no leg judged, no line issued, no run counted. Short of crew where no crew can
--                                 be hired (public.port_hires), she cannot mend it where she lies: the job STOPS on E_CREW_SHORT,
--                                 with nothing issued, and goes on once she is manned.
--   public.fleet_job_note         (2 hunks) that wait is written on her job: last {wait: <the code>, sentence}, asked again 10 minutes
--                                 on; the job is NOT stopped. And a job stopped on E_FLAGSHIP_DISABLED or E_CREW_SHORT that is
--                                 asked again (she is fit now) has its stop and its failed plan lifted, whatever the new plan says.
--   public.fleet_jobs_due         (1 hunk) a job that waits for her repair or her crew is due at the first run after it (not 10
--                                 minutes later); a job ALREADY STOPPED on either code is due once she is fit. Neither is asked
--                                 while she is not: her ships' crew and her flagship read, a job a run.
--   public.fleet_job_set_for      (1 hunk) the door refuses a new job for her with the sail's own code and sentence.
--   public.fleet_job_open         (1 hunk) says how long the quay kept the open waiting (a transaction's own setting).
--   public.tick_fleet_jobs        (6 hunks) THE RECEIPT NAMES ITS PARTS: a step carries collect_ms (a land job's collect, inside
--                                 plan_ms as before), wait_ms (the wait for the gap after the beat) and quay_ms (the wait for the
--                                 quay, inside open_ms as before) beside plan_ms and open_ms. Nothing else in the tick moves.
--   cmd.queue                     (1 hunk) each served order carries `at`: when it ran (a refused one: when it was refused; null while
--                                 it waits). One key more; nothing else of the queue moves.
--   world.workers                 NOT HUNKED: her row already serves `wait` from the job's own `last` and next_at (0498), so it reads
--                                 wait {code: E_FLAGSHIP_DISABLED, sentence, retry_at}; a job stopped on that code reads `stop` as before.
-- THE HUNKS (15; each once in the live body, each reverses): voyage.sail_refusal x1, cmd.do_hire x1, cmd.queue x1, fleet_job_plan x1,
--   fleet_job_note x2, fleet_jobs_due x1, fleet_job_set_for x1, fleet_job_open x1, tick_fleet_jobs x6. NEW: public.fleet_unfit,
--   public.port_hires.
-- THE TICK'S COST. The reported tick could NOT be reproduced: the same scene on the chain's world (PGlite) is 45-95 ms, cold plans
--   too (scripts/ops/harness/fit-to-sail/profile-tick.mjs; the dev log has the parts). After this file a fleet that cannot sail costs
--   one flagship read and one small write in 10 minutes. Where prod's ten seconds went is not known here: the receipt's new stamps
--   say it at the next slow tick. No line is split across ticks: nothing measured says the lines are the cost.
-- NOT CHANGED: every knob and switch; cmd.issue_lines, cmd.do_sail, cmd.do_repair, public.tow_for; the repair's and the crew's price; any table,
--   column or cron job; world.workers and every client read's shape (a receipt step gains three keys).
-- ROWS: no new row kind. A wrecked fleet's job no longer writes its plan's orders (seven SAILs in the report) nor counts a run.
-- budget: no table, no cron job, no autovacuum or fillfactor change.
-- LOCKS: CREATE OR REPLACE x9 by hunks (eight functions, one procedure), CREATE FUNCTION x2. TIME: about a second. BUDGET:
--   statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): a migration reversing the fifteen hunks (OLD texts below verbatim) and dropping the two functions. QUICK:
--   none of its own; fleet_jobs_enabled false stops every job, as before.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no knob moved; the new function STABLE and server only. THE SCENE (rolled back), before the hunks and after: a
--   healthy fleet's plan is the same lines to the letter; the wrecked fleet's tick before is the report (runs 1, a SAIL failed, then
--   stopped for ever); after it waits with the code, nothing issued, no run counted, her row says wait, the door refuses, and she
--   sails by herself at the first run after her hull is mended. A job already stopped on the code is left alone while she is wrecked
--   and goes on once she is fit. The sail's refusal reads as it did. SHORT OF CREW: where crew can be hired she waits with
--   E_CREW_SHORT; where none can she stops on it with nothing issued; manned, she sails at the next run; the door refuses her.
--   NO REAL COMPANY'S JOB IS ASKED OR WRITTEN (2026-11-25, after 0498 was refused on prod by a probe that leaned on the live world).
--   The scenes ran public.tick_fleet_jobs after pushing every other company's next_at a day on (a write to every real job's row), and
--   that did not hold a real job back once the hunks were in: a job stopped on E_FLAGSHIP_DISABLED whose fleet is mended, or one that
--   waits for crew she now has, is due whatever its next_at (the very rule this file adds), so the run "that asks nothing" asked it and
--   the assert failed on a world that holds one (reproduced: one such company, and 0500 refused itself). Now pg_temp.tick_mine_0500
--   runs the tick only when the scene's own job is due, with that job the longest-waiting (its own `since` and last.at set back) and
--   fleet_jobs_per_tick 1 for the scene: the run plans the scene's job and no other. A run that must ask nothing is read from
--   public.fleet_jobs_due (her job is not in it). Rows written: the scenes' own companies, world_config (switches, the run's count),
--   ISL's crew_pool (the hire's gate is the port's), all rolled back. No market price is read for a sign: the plan is a land job's sails.
-- news: this file posts its own UPDATE row (public.news_update('0500', ...)).
-- VERSION: 0500 (after 0499 `near-round`).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)', 'cmd.do_hire(uuid,jsonb)', 'cmd.queue(uuid)', 'public.fleet_job_plan(uuid)', 'public.fleet_job_note(uuid,jsonb)',
                                    'public.fleet_jobs_due()', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'public.fleet_job_open(uuid,jsonb)',
                                    'public.tick_fleet_jobs(boolean)'];
  c_new    constant text[] := array['public.fleet_unfit(uuid)', 'public.port_hires(uuid)'];
  c_ua     constant uuid := '00000000-0500-4000-8000-0000000000a1';
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
  v_ask       boolean;
  v_d0        jsonb;
  v_d1        jsonb;
  v_isl       uuid;
  v_a         uuid;
  v_fa        uuid;
  v_o         uuid;
  v_r         jsonb;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.fleet_unfit(uuid)') is not null then
    raise exception '0500 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.fleet_job_legs(uuid,uuid,uuid)') is null or to_regprocedure('public.jobs_wait_on()') is null
     or to_regprocedure('public.workers_for(uuid)') is null or to_regprocedure('public.fleet_state(uuid)') is null
     or to_regprocedure('cmd.refusal(text,text,jsonb)') is null then
    raise exception '0500 refuses: 0494 (the harbour legs), 0496 (the workers), 0498 (the jobs wait) or 0448 (the one state rule) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function, run before the hunks and after): the reported fleet at ISL, healthy, wrecked, mended ──
  -- THE RUN, FOR THE SCENE'S JOB ALONE (the header): false, and no run, when her job is not due (the run would not ask her); else her
  -- job is made the longest-waiting (its own row), the run takes one job, and it is hers. No other company's job is planned or written.
  execute $f$
create function pg_temp.tick_mine_0500(p_fleet uuid)
returns boolean
language plpgsql
as $body$
begin
  if not exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = p_fleet) then
    return false;
  end if;
  update public.fleet_jobs j
     set since = '2000-01-01 00:00:00+00',
         last = case when j.last ? 'at' then jsonb_set(j.last, '{at}', to_jsonb('2000-01-01 00:00:00+00'::timestamptz)) else j.last end
   where j.fleet_id = p_fleet;
  update public.world_config set value = to_jsonb(1) where key = 'fleet_jobs_per_tick';
  if (select d.fleet_id from public.fleet_jobs_due() d order by d.turn, d.fleet_id limit 1) is distinct from p_fleet then
    raise exception '0500 self-assert FAIL: the scene''s job is not the first the run would take';
  end if;
  call public.tick_fleet_jobs(false);
  if (select r.receipt #>> '{steps,0,fleet}' from public.fleet_job_runs r where r.at = now()) is distinct from p_fleet::text
     or (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 1 then
    raise exception '0500 self-assert FAIL: the run did not take the scene''s job and that job alone: %', (select r.receipt from public.fleet_job_runs r where r.at = now());
  end if;
  return true;
end
$body$
  $f$;
  execute $f$
create function pg_temp.scene_0500(p_uid uuid)
returns jsonb
language plpgsql
as $body$
declare
  v_isl uuid := (select p.id from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR');
  v_pl  uuid;
  v_fl  uuid;
  v_pln jsonb;
  v_j1  jsonb;
  v_j2  jsonb;
  v_j3  jsonb;
  v_rc1 jsonb;
  v_rc2 jsonb;
  v_row jsonb;
  v_door jsonb;
  v_sr  jsonb;
  v_sr0 jsonb;
  v_st  text;
  v_a1  boolean;
  v_a2  boolean;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0500', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players p set ducats = 2000000 where p.id = v_pl;
  update public.fleets set port_id = v_isl, status = 'DOCKED', ready_at = null where id = v_fl;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
  perform cmd.assume_identity(p_uid);
  perform public.land_party(v_pl);
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fl, v_pl, 'land', '{"to": "CAD"}'::jsonb, now(), now());

  -- (healthy) her plan, and the sail's own answer for her
  v_pln := public.fleet_job_plan(v_fl);
  v_sr0 := voyage.sail_refusal(v_fl, null, null, 0);

  -- (wrecked) every hull at 0, as a ransom and a tow leave her: DOCKED at a yard, not fit
  update public.ships set durability = 0 where fleet_id = v_fl;
  v_sr := voyage.sail_refusal(v_fl, null, null, 0);
  v_st := public.fleet_state(v_fl);
  v_a1 := pg_temp.tick_mine_0500(v_fl);
  select to_jsonb(j) || jsonb_build_object('waits', coalesce(j.next_at > now(), false)) into v_j1 from public.fleet_jobs j where j.fleet_id = v_fl;
  v_rc1 := case when v_a1 then (select r.receipt from public.fleet_job_runs r where r.at = now()) end;
  v_j1 := v_j1 || jsonb_build_object(
    'orders', (select count(*) from public.orders o where o.fleet_id = v_fl),
    'failed', (select jsonb_agg(o.error_code order by o.seq) from public.orders o where o.fleet_id = v_fl and o.status = 'failed'));
  v_a2 := pg_temp.tick_mine_0500(v_fl);
  select to_jsonb(j) into v_j2 from public.fleet_jobs j where j.fleet_id = v_fl;
  v_rc2 := case when v_a2 then (select r.receipt from public.fleet_job_runs r where r.at = now()) end;
  v_row := (select w from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fl::text);
  -- the door, asked for her while she is wrecked (taken back at once: before the hunks it would take the job and start it afresh)
  begin
    v_door := cmd.set_fleet_job(v_fl, 'land', '{"to": "CAD"}'::jsonb);
    raise exception using errcode = 'ZD500', message = 'DOOR_ROLLBACK_0500';
  exception when sqlstate 'ZD500' then null;
  end;

  -- (mended) her hulls whole again (the yard's own write, cmd.do_repair: durability back to her base), and the very next run
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  perform pg_temp.tick_mine_0500(v_fl);
  select to_jsonb(j) into v_j3 from public.fleet_jobs j where j.fleet_id = v_fl;
  return jsonb_build_object(
    'plan', (select jsonb_agg(l->>'text' order by i) from jsonb_array_elements(v_pln->'lines') with ordinality t(l, i)),
    'plan_md5', md5((v_pln - 'version')::text),
    'sail_fit', v_sr0, 'sail_wreck', v_sr, 'state', v_st,
    'j1', v_j1, 'rc1', v_rc1, 'asked1', v_a1, 'j2', v_j2, 'rc2', v_rc2, 'asked2', v_a2, 'row', v_row, 'door', v_door,
    'j3', v_j3, 'status3', (select f.status from public.fleets f where f.id = v_fl),
    'texts3', (select jsonb_agg(o.raw_text order by o.seq) from public.orders o where o.fleet_id = v_fl and o.plan_id = (v_j3->>'last_plan')::uuid));
end
$body$
  $f$;

  begin
    v_d0 := pg_temp.scene_0500(c_ua);
    raise exception using errcode = 'ZX500', message = 'PROBE_ROLLBACK_0500_BEFORE';
  exception when sqlstate 'ZX500' then null;
  end;
  -- THE REPORT, BEFORE: the wrecked fleet's lines are issued and a run counted; the SAIL fails; the next run stops the job; mended, it stays stopped
  if jsonb_array_length(coalesce(v_d0->'plan', '[]'::jsonb)) < 2 or v_d0 #>> '{plan,-1}' is distinct from 'SAIL LIS'
     or v_d0->'sail_fit' <> 'null'::jsonb or v_d0 #>> '{sail_wreck,code}' is distinct from 'E_FLAGSHIP_DISABLED' or v_d0->>'state' is distinct from 'wrecked'
     or v_d0 #>> '{j1,runs}' is distinct from '1' or v_d0 #>> '{j1,failed,0}' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_d0 #>> '{j2,paused_reason}' is distinct from 'E_FLAGSHIP_DISABLED' or v_d0 #>> '{j2,last,sentence}' is distinct from 'the flagship is not fit to sail'
     or v_d0 #>> '{j3,paused_reason}' is distinct from 'E_FLAGSHIP_DISABLED' or v_d0->>'status3' is distinct from 'DOCKED'
     or v_d0 #>> '{door,ok}' is distinct from 'true' or v_d0 #>> '{asked1}' is distinct from 'true' or v_d0 #>> '{asked2}' is distinct from 'true' then
    raise exception '0500 self-assert FAIL: before the hunks the wrecked fleet''s job did not go as the lead reported: %', left(v_d0::text, 1500);
  end if;

  -- ── 3. THE RULE ──
  execute $f$
create function public.fleet_unfit(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0500: THE ONE FITNESS RULE: IS THIS FLEET NOT FIT TO SAIL? The two gates of voyage.sail_refusal (0007, 0047, 0050) that no harbour
-- between mends, lifted whole and in their order; the sail asks them here now. (1) A ship with fewer crew than she needs: the sail's
-- own refusal {code: E_CREW_SHORT, sentence, figures: the crew aboard those ships and what they need}. (2) Her flagship's hull at 0 or
-- under, or no flagship at all: {code: E_FLAGSHIP_DISABLED, sentence}. Else null. A fleet public.fleet_state_of calls wrecked (no hull
-- above 0) is unfit by it: her flagship is one of her hulls (one a fleet: ships_one_flagship_per_fleet). Read by voyage.sail_refusal
-- (the SAIL), public.fleet_job_plan (the tick), public.fleet_jobs_due (who is asked), public.fleet_job_note and
-- public.fleet_job_set_for (the job door). Her ships by their fleet index. Writes nothing.
declare
  v_short int;
  v_crew  numeric;
  v_full  numeric;
  v_flag  numeric;
begin
  -- the same predicate 0047 counted by; the two sums are the figures for the very ships it counts
  select count(*), coalesce(sum(s.crew), 0), coalesce(sum(c.crew_required), 0)
    into v_short, v_crew, v_full
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    return cmd.refusal('E_CREW_SHORT', format('%s ship(s) are short of crew', v_short),
                       cmd.figures(v_crew, v_full, 'crew'));
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    return cmd.refusal('E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail');
  end if;
  return null;
end
$body$
  $f$;

  execute $f$
create function public.port_hires(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0500: CAN CREW BE HIRED AT THIS PORT? Hands on its quay (ports.crew_pool above 0): the fact cmd.do_hire refuses E_CREW_POOL by
  -- ("no crew to be had in this port"), lifted; cmd.do_hire asks it here now. Read by public.fleet_job_plan: short of crew where
  -- this is true she waits for her hire; where it is not her job stops. False for no such port.
  select coalesce((select p.crew_pool > 0 from public.ports p where p.id = p_port), false)
$body$
  $f$;

  -- grants: server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0500 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0500 values
  ('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)', 1,
$h$  -- the same predicate 0047 counted by; the two sums are the figures for the very ships it counts
  select count(*), coalesce(sum(s.crew), 0), coalesce(sum(c.crew_required), 0)
    into v_short, v_crew, v_full
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    return cmd.refusal('E_CREW_SHORT', format('%s ship(s) are short of crew', v_short),
                       cmd.figures(v_crew, v_full, 'crew'));
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    return cmd.refusal('E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail');
  end if;$h$,
$h$  -- 0500: THE ONE FITNESS RULE (public.fleet_unfit: her crew, then her flagship's hull, as these lines read them themselves); the
  -- job tick and the job door ask it too
  v_gate := public.fleet_unfit(p_fleet);
  if v_gate is not null then
    return v_gate;
  end if;$h$),
  ('cmd.do_hire(uuid,jsonb)', 1,
$h$  if v_pool <= 0 and v_urg = v_count then$h$,
$h$  if not public.port_hires(f.port_id) and v_urg = v_count then   -- 0500: the one reading of "crew can be hired here"$h$),
  ('cmd.queue(uuid)', 1,
$h$           'result', o.result) order by o.seq), '[]'::jsonb)$h$,
$h$           'result', o.result,
           'at', o.executed_at)   -- 0500: when it ran (a refused order: when it was refused), so a screen can tell an old record from news
           order by o.seq), '[]'::jsonb)$h$),
  ('public.fleet_job_plan(uuid)', 1,
$h$    return jsonb_build_object('wait', 'busy');
  end if;$h$,
$h$    return jsonb_build_object('wait', 'busy');
  end if;
  -- 0500: A FLEET THAT CANNOT SAIL IS NOT PLANNED (public.fleet_unfit, the sail's own rule): no course read, no leg judged, no line
  -- issued, no run counted. She WAITS with the sail's code and sentence (public.fleet_job_note) and goes on by herself once mended.
  v_s := public.fleet_unfit(p_fleet);
  if v_s is not null then
    -- short of crew where none can be hired (public.port_hires): she cannot mend it where she lies, so the job stops on the code
    -- (nothing issued); public.fleet_jobs_due asks it again once she is manned
    if v_s->>'code' = 'E_CREW_SHORT' and not public.port_hires(f.port_id) then
      return jsonb_build_object('pause', v_s->>'code', 'sentence', v_s->>'sentence');
    end if;
    return jsonb_build_object('wait', 'unfit', 'code', v_s->>'code', 'sentence', v_s->>'sentence');
  end if;$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$begin
  if p_plan ? 'pause' then$h$,
$h$begin
  -- 0500: a job stopped because she was not fit to sail (her flagship, her crew), asked again now that she is (public.fleet_jobs_due
  -- asks it only then): the stop is lifted, and the plan that failed on it is forgotten, whatever this plan says
  update public.fleet_jobs set paused_reason = null, last_plan = null
   where fleet_id = p_fleet and paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT') and public.fleet_unfit(p_fleet) is null;
  if p_plan ? 'pause' then$h$),
  ('public.fleet_job_note(uuid,jsonb)', 2,
$h$  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then$h$,
$h$  elsif p_plan->>'wait' = 'unfit' then
    -- 0500: she cannot sail: the job WAITS with the sail's code and sentence, asked again 10 minutes on, or at the first run after
    -- her repair or her hire (public.fleet_jobs_due); it is not stopped
    update public.fleet_jobs
       set next_at = now() + interval '10 minutes',
           last = jsonb_build_object('at', now(), 'wait', coalesce(p_plan->>'code', 'E_FLAGSHIP_DISABLED'), 'sentence', p_plan->>'sentence')
     where fleet_id = p_fleet and paused_reason is null;
  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then$h$),
  ('public.fleet_jobs_due()', 1,
$h$              and coalesce((j.last->>'at')::timestamptz, j.since) <= now() - interval '10 minutes'))
     and (j.next_at is null or j.next_at <= now())$h$,
$h$              and coalesce((j.last->>'at')::timestamptz, j.since) <= now() - interval '10 minutes')
          -- 0500: a job stopped because she was not fit to sail goes on once she is (public.fleet_unfit); never asked while she is not
          or (j.paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT') and public.fleet_unfit(j.fleet_id) is null))
     and (j.next_at is null or j.next_at <= now()
          -- 0500: and a job that waits for her repair or her crew is asked at the first run after it
          or (j.paused_reason is null and j.last->>'wait' in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT') and public.fleet_unfit(j.fleet_id) is null))$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;$h$,
$h$    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  -- 0500: no job is set for a fleet that cannot sail: the sail's own code and sentence (public.fleet_unfit)
  v_s := public.fleet_unfit(p_fleet);
  if v_s is not null then
    perform cmd.refuse(v_s);
  end if;$h$),
  ('public.fleet_job_open(uuid,jsonb)', 1,
$h$  v_r      jsonb;
begin
  perform public.hold_the_quay();$h$,
$h$  v_r      jsonb;
  v_q0     timestamptz := clock_timestamp();   -- 0500
begin
  perform public.hold_the_quay();
  -- 0500: how long the quay kept this open waiting, for the tick's receipt (this transaction's own setting; nothing reads it but the tick)
  perform set_config('byeharu.quay_ms', round(extract(epoch from clock_timestamp() - v_q0)::numeric * 1000, 1)::text, true);$h$),
  ('public.tick_fleet_jobs(boolean)', 1,
$h$  v_om     numeric;$h$,
$h$  v_om     numeric;
  v_cm     numeric;   -- 0500: a land job's collect (inside plan_ms)
  v_wm     numeric;   -- 0500: the wait for the gap after the beat
  v_qm     numeric;   -- 0500: the wait for the quay (inside open_ms)$h$),
  ('public.tick_fleet_jobs(boolean)', 2,
$h$        v_note := coalesce(v_note, 'collect ' || v_ids[i] || ': ' || sqlerrm);
      end;
    end if;$h$,
$h$        v_note := coalesce(v_note, 'collect ' || v_ids[i] || ': ' || sqlerrm);
      end;
    end if;
    v_cm := case when v_kinds[i] = 'land' then round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1) end;   -- 0500$h$),
  ('public.tick_fleet_jobs(boolean)', 3,
$h$    v_om := null;
    v_b := null;$h$,
$h$    v_om := null;
    v_b := null;
    v_wm := null;   -- 0500
    v_qm := null;$h$),
  ('public.tick_fleet_jobs(boolean)', 4,
$h$          perform pg_sleep(0.02);
        end loop;$h$,
$h$          perform pg_sleep(0.02);
        end loop;
        v_wm := round(extract(epoch from clock_timestamp() - v_tw)::numeric * 1000, 1);   -- 0500$h$),
  ('public.tick_fleet_jobs(boolean)', 5,
$h$        v_b := public.fleet_job_open(v_ids[i], v_plan);$h$,
$h$        perform set_config('byeharu.quay_ms', '', true);   -- 0500: the open says how long the quay kept it
        v_b := public.fleet_job_open(v_ids[i], v_plan);
        v_qm := nullif(current_setting('byeharu.quay_ms', true), '')::numeric;$h$),
  ('public.tick_fleet_jobs(boolean)', 6,
$h$'plan_ms', v_pm, 'open_ms', v_om, 'open', v_b,$h$,
$h$'plan_ms', v_pm, 'open_ms', v_om, 'open', v_b, 'collect_ms', v_cm, 'wait_ms', v_wm, 'quay_ms', v_qm,   -- 0500: the receipt names its parts
                 'code', v_plan->>'code',$h$);

  for v_h in select h.fn from hunks_0500 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0500 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0500 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0500 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0500 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0500 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  perform public.news_update('0500', 'A fleet that cannot sail is no longer sent out by her job: the job waits for her repair and goes on by itself once she is mended',
                             'A fleet that cannot sail is no longer sent out by her job: the job waits for her repair and goes on by itself once she is mended');

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the grants ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0500 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0500 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0500 self-assert FAIL: a knob moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's') <> 2
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0500 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;

  -- ── 6. THE PROBES ──
  -- (a) THE SAME SCENE AFTER
  begin
    v_d1 := pg_temp.scene_0500(c_ua);
    raise exception using errcode = 'ZX500', message = 'PROBE_ROLLBACK_0500_AFTER';
  exception when sqlstate 'ZX500' then null;
  end;
  -- a healthy fleet's plan to the letter, and the sail's refusal as it read
  if v_d1->'plan' is distinct from v_d0->'plan' or v_d1->>'plan_md5' is distinct from v_d0->>'plan_md5'
     or v_d1->'sail_fit' is distinct from v_d0->'sail_fit' or v_d1->'sail_wreck' is distinct from v_d0->'sail_wreck' then
    raise exception '0500 self-assert FAIL: a healthy fleet''s plan or the sail''s refusal moved: before % / after %', left(v_d0::text, 500), left(v_d1::text, 500);
  end if;
  -- the wrecked fleet: she WAITS with the code; no line, no run, not stopped; the receipt says so; the very next run asks nothing
  if v_d1 #>> '{j1,runs}' is distinct from '0' or v_d1 #>> '{j1,orders}' is distinct from '0' or v_d1 #>> '{j1,paused_reason}' is not null
     or v_d1 #>> '{j1,last,wait}' is distinct from 'E_FLAGSHIP_DISABLED' or v_d1 #>> '{j1,last,sentence}' is distinct from 'the flagship is not fit to sail'
     or v_d1 #>> '{j1,waits}' is distinct from 'true' or v_d1 #>> '{j1,last_plan}' is not null
     or v_d1 #>> '{rc1,steps,0,wait}' is distinct from 'unfit' or v_d1 #>> '{rc1,steps,0,code}' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_d1 #> '{rc1,steps,0}' ? 'open' or v_d1 #>> '{rc1,started}' is distinct from '0' or v_d1 #>> '{rc1,stopped}' is distinct from '0'
     or v_d1 #>> '{asked1}' is distinct from 'true' or v_d1 #>> '{asked2}' is distinct from 'false' or v_d1 #>> '{j2,paused_reason}' is not null then
    raise exception '0500 self-assert FAIL: the wrecked fleet''s job did not wait with nothing issued: %', left(v_d1::text, 1500);
  end if;
  -- her row: waiting, `wait` with the code and the sentence, no stop, her state by the one rule
  if v_d1 #>> '{row,state}' is distinct from 'waiting' or v_d1 #>> '{row,wait,code}' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_d1 #>> '{row,wait,sentence}' is distinct from 'the flagship is not fit to sail' or v_d1 #>> '{row,wait,retry_at}' is null
     or v_d1 #> '{row,stop}' <> 'null'::jsonb or v_d1 #>> '{row,worker_state}' is distinct from 'wrecked' then
    raise exception '0500 self-assert FAIL: world.workers does not say she waits for her repair: %', v_d1->'row';
  end if;
  -- the door refuses, in the sail's words
  if v_d1 #>> '{door,ok}' is distinct from 'false' or v_d1 #>> '{door,error_code}' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_d1 #>> '{door,error_message}' not ilike '%the flagship is not fit to sail%' then
    raise exception '0500 self-assert FAIL: the door did not refuse a job for a fleet that cannot sail: %', v_d1->'door';
  end if;
  -- mended: the very next run starts her, harbour by harbour, one run counted
  if v_d1 #>> '{j3,runs}' is distinct from '1' or v_d1 #>> '{j3,paused_reason}' is not null or v_d1->>'status3' is distinct from 'SAILING'
     or v_d1->'texts3' is distinct from v_d1->'plan' then
    raise exception '0500 self-assert FAIL: mended, she did not go on by herself at the next run: % / % / %', v_d1->'j3', v_d1->>'status3', v_d1->'texts3';
  end if;
  v_note := format('healthy plan identical %s (%s); wrecked: before runs %s, %s failed, then stopped %s for ever; after runs %s, orders %s, waits "%s", next run asks nothing, door %s; mended: %s, runs %s',
                   left(v_d1->>'plan_md5', 8), (select string_agg(t.s, ' / ') from jsonb_array_elements_text(v_d1->'plan') t(s)),
                   v_d0 #>> '{j1,runs}', v_d0 #>> '{j1,failed,0}', v_d0 #>> '{j3,paused_reason}', v_d1 #>> '{j1,runs}', v_d1 #>> '{j1,orders}',
                   v_d1 #>> '{j1,last,sentence}', v_d1 #>> '{door,error_code}', v_d1->>'status3', v_d1 #>> '{j3,runs}');

  -- (b) A JOB ALREADY STOPPED ON THE CODE (prod's row as it stands, its failed plan behind it): left alone while she is wrecked; mended, it goes on
  begin
    select p.id into v_isl from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa do Reparo 0500', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    update public.players p set ducats = 2000000 where p.id = v_a;
    update public.fleets set port_id = v_isl, status = 'DOCKED', ready_at = null where id = v_fa;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
    perform cmd.assume_identity(c_ua);
    perform public.land_party(v_a);
    update public.ships set durability = 0 where fleet_id = v_fa;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code, error_message)
    values (v_fa, v_a, 1, 'SAIL SOF', 'SAIL', '{}'::jsonb, 'failed', 'E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail') returning id into v_o;
    update public.orders set plan_id = v_o where id = v_o;
    insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at, runs, paused_reason, last, last_plan)
    values (v_fa, v_a, 'land', '{"to": "CAD"}'::jsonb, now() - interval '1 day', now() - interval '1 day', 1, 'E_FLAGSHIP_DISABLED',
            jsonb_build_object('at', now() - interval '1 day', 'ok', false, 'code', 'E_FLAGSHIP_DISABLED', 'sentence', 'the flagship is not fit to sail'), v_o);
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if v_ask
       or (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_FLAGSHIP_DISABLED'
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> 1
       or (select w #>> '{stop,code}' from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text) is distinct from 'E_FLAGSHIP_DISABLED' then
      raise exception '0500 self-assert FAIL: a job stopped on E_FLAGSHIP_DISABLED was asked while she is wrecked, or her row lost its stop';
    end if;
    -- the served queue says when her refused order ran (null here: this probe's row was written with no time; the key is there)
    if (select count(*) from jsonb_array_elements(cmd.queue(v_fa)) q where q ? 'at' and q->>'status' = 'failed') <> 1 then
      raise exception '0500 self-assert FAIL: cmd.queue does not serve when a refused order ran: %', cmd.queue(v_fa);
    end if;
    -- mended, and the plan that is asked says "nothing": the stop and the failed plan are lifted all the same (no loop on the old failure)
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fa;
    perform public.fleet_job_note(v_fa, '{"wait": "nothing"}'::jsonb);
    if (select j.paused_reason is not null or j.last_plan is not null or j.next_at is null from public.fleet_jobs j where j.fleet_id = v_fa) then
      raise exception '0500 self-assert FAIL: a mended fleet''s stop was not lifted by a plan that waits: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;
    -- as prod's row again, mended: the very next run starts her
    update public.fleet_jobs set paused_reason = 'E_FLAGSHIP_DISABLED', last_plan = v_o, next_at = null where fleet_id = v_fa;
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if not v_ask
       or (select j.paused_reason is not null or j.runs <> 2 or j.last_plan is not distinct from v_o from public.fleet_jobs j where j.fleet_id = v_fa)
       or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
      raise exception '0500 self-assert FAIL: a job stopped on E_FLAGSHIP_DISABLED did not go on once she was mended: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;
    -- the receipt names its parts (a land job: its collect; one transaction: no gap wait; the quay answered)
    v_r := (select r.receipt #> '{steps,0}' from public.fleet_job_runs r where r.at = now());
    if not (v_r ? 'collect_ms' and v_r ? 'quay_ms' and v_r ? 'plan_ms' and v_r ? 'open_ms') or v_r ? 'wait_ms' then
      raise exception '0500 self-assert FAIL: the receipt does not name its parts: %', v_r;
    end if;
    -- the door takes a job for her now
    v_r := cmd.clear_fleet_job(v_fa);
    update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
    v_r := cmd.set_fleet_job(v_fa, 'land', '{"to": "CAD"}'::jsonb);
    if (v_r->>'ok')::boolean is not true then
      raise exception '0500 self-assert FAIL: the door refused a fit fleet: %', v_r;
    end if;
    -- (c) SHORT OF CREW (the same class). Her job set, she docked at ISL, one hand short on every ship.
    update public.ports set crew_pool = 50 where id = v_isl;
    update public.ships s set crew = c.crew_required - 1 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fa;
    if voyage.sail_refusal(v_fa, null, null, 0) is distinct from public.fleet_unfit(v_fa) or public.fleet_unfit(v_fa)->>'code' is distinct from 'E_CREW_SHORT'
       or public.fleet_unfit(v_fa)->'figures' is null then
      raise exception '0500 self-assert FAIL: short of crew, the sail and the rule do not give the one answer: % / %', voyage.sail_refusal(v_fa, null, null, 0), public.fleet_unfit(v_fa);
    end if;
    v_n := (select count(*) from public.orders o where o.fleet_id = v_fa);
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if not v_ask
       or (select j.paused_reason is not null or j.last->>'wait' is distinct from 'E_CREW_SHORT' or j.last->>'sentence' not like 'Crew % / %'
               or j.next_at is null or j.runs <> 0 from public.fleet_jobs j where j.fleet_id = v_fa)
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_n
       or (select w #>> '{wait,code}' from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text) is distinct from 'E_CREW_SHORT' then
      raise exception '0500 self-assert FAIL: short of crew where crew can be hired, her job did not wait with nothing issued: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;
    v_r := cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb);
    if v_r->>'error_code' is distinct from 'E_CREW_SHORT' or v_r->'figures' is null then
      raise exception '0500 self-assert FAIL: the door did not refuse a fleet short of crew: %', v_r;
    end if;
    -- no hands on the quay: asked again, the job stops on the code, nothing issued; the hire door says the same of this port
    update public.ports set crew_pool = 0 where id = v_isl;
    update public.fleet_jobs set next_at = null where fleet_id = v_fa;
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if not v_ask
       or (select j.paused_reason is distinct from 'E_CREW_SHORT' or j.runs <> 0 from public.fleet_jobs j where j.fleet_id = v_fa)
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_n
       or public.port_hires(v_isl) or cmd.preview(v_fa, 'HIRE 1')->>'error_code' is distinct from 'E_CREW_POOL' then
      raise exception '0500 self-assert FAIL: short of crew where none can be hired, her job did not stop with nothing issued: % / %',
        (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa), cmd.preview(v_fa, 'HIRE 1');
    end if;
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if v_ask then
      raise exception '0500 self-assert FAIL: a job stopped for want of crew was asked while she is short';
    end if;
    -- manned (the Inn's own write: crew back to what she needs): the very next run starts her
    update public.ports set crew_pool = 50 where id = v_isl;
    if not public.port_hires(v_isl) or (cmd.preview(v_fa, 'HIRE 1')->>'ok')::boolean is not true then
      raise exception '0500 self-assert FAIL: the hire door refuses a quay with hands: %', cmd.preview(v_fa, 'HIRE 1');
    end if;
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fa;
    -- the run first, in its own statement: what it writes is read by the next one
    v_ask := pg_temp.tick_mine_0500(v_fa);
    if not v_ask
       or (select j.paused_reason is not null or j.runs <> 1 from public.fleet_jobs j where j.fleet_id = v_fa)
       or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
      raise exception '0500 self-assert FAIL: manned, she did not go on at the next run: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;
    v_note := v_note || '; a job already stopped on the code is not asked while she is wrecked, is lifted by any plan once mended, and starts at the next run; the receipt carries collect_ms and quay_ms; the door takes a fit fleet; short of crew: waits E_CREW_SHORT where crew can be hired, stops where none can, the door refuses, manned she sails at the next run';
    raise exception using errcode = 'ZX500', message = 'PROBE_ROLLBACK_0500';
  exception when sqlstate 'ZX500' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0500 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0500' or p.auth_uid = c_ua)
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before
     or public.current_player_id() is not null then
    raise exception '0500 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.scene_0500(uuid);
  drop function pg_temp.tick_mine_0500(uuid);

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0500 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0500 self-assert ok: FIT TO SAIL. % hunks once and reversing; no other function moved; the hunked bodies'' grants and volatility unmoved; no knob moved; two new functions STABLE and server only. Probes (rolled back): %. % ms.',
    (select count(*) from hunks_0500), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
