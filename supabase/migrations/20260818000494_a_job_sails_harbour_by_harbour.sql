-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0494 - A JOB SAILS HARBOUR BY HARBOUR  (a repair of the standing fleet jobs of 0481 / 0482 / 0492; no switch, no knob, no table)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER'S REPORT, 2026-11-24 (docs/design/remaster-2026-11-24.md, "One travel rule"): a `land` job, settings {"to": "CAD"}, stopped
--   with E_LEG_TOO_FAR; its report read "Line 1 (SAIL LIS): that leg is 7052 nm and your navigation carries you 1700 nm — study
--   navigation". Dev log docs/dev-log/2026-11-24-job-by-harbours.md.
--
-- THE CAUSE (read, not guessed). The fleet lay at Island of Mozambique (ISL), not at the Land's harbour. A land job that is "anywhere
--   else" sails back to the party's harbour first (0481, public.fleet_job_plan: `v_s := public.fleet_job_sails(f.id, f.port_id,
--   array[v_land]); ... v_to := v_land`), and a party lives in the company's home city (0455, public.land_party: Lisbon for her). So the
--   plan was the one line SAIL LIS and its note said to LIS: `to: CAD` is the yard the goods go to AFTER Lisbon, never this run's
--   harbour. public.fleet_job_sails gave that one SAIL the stored course ISL -> LIS (0482, sea_courses_enabled lit: a course between
--   every two harbours, 7,052 nm), and cmd.issue_lines' reach gate (0188, public.passage_gate) refused it: one leg, 7,052 nm > 1,700.
--   The same fault sits in every kind: a fixed job's legs (her first sail to `buy`, `buy` to `sell`, home) and a bring-home job's are
--   one SAIL each; only `best` asked the harbours between (world.board_passages), and only by the miles table, not her course.
--   The door (public.fleet_job_set_for) asked only whether a course exists, never whether she can sail it.
--
-- THE FIX. ONE AUTHORITY: the SAIL lines of every job are public.fleet_job_sails' (fixed, bring home, land, and `best` through
--   public.sale_lines). By one hunk it asks, for each harbour it is sent, public.fleet_job_legs (new, STABLE):
--     * the course a job sails (public.fleet_job_course, unchanged), measured as cmd.issue_lines measures it
--       (voyage.segments_from_course) and judged by THE leg judge (voyage.leg_refusal: her navigation, then her stores);
--     * open, or shut by anything but its length or its stores: the one SAIL, as before (the door has the last word, as before);
--     * shut by its length or its stores (E_LEG_TOO_FAR, E_ENDURANCE): the harbours between from voyage.reach_passage (THE pathfinder,
--       capped by the legs her stores cover, public.supply_reach, exactly as world.route_legs' `via` and world.good_board ask it), one
--       SAIL a harbour, each with its own course and each judged the same way. No second pathfinder.
--     * no such chain (or a harbour of it with no course, or a leg of it still shut): {pause: <the judge's code>, sentence: "she cannot
--       sail from <A> to <B> harbour by harbour: <the judge's sentence>"}.
--   AT THE DOOR (public.fleet_job_set_for, two hunks): a fixed job's way out and home, and a land job's way to the yard and back, are
--   asked of public.fleet_job_sails, and so is her first sail from where she lies now (docked in a third harbour). No chain: the job is
--   refused when it is set, with that sentence and the judge's code. `best` names no harbour: each run takes only a sale it can sail.
--   A STOPPED JOB IS ASKED AGAIN (public.fleet_jobs_due, one hunk): a job stopped on E_LEG_TOO_FAR or E_ENDURANCE is due again 10
--   minutes after its last word (`last.at`), never sooner. The tick plans it as any job: a chain now -> its lines are sent and the stop
--   is lifted (public.fleet_job_open, one hunk); no chain -> it stays stopped with the sentence above. Every try, whatever came of it,
--   stamps `last.at` (public.tick_fleet_jobs, one hunk), so a stopped job costs at most one plan in 10 minutes. The stop's own failed
--   order is not read a second time on a retry (public.fleet_job_plan, one hunk), and a retry with nothing to carry leaves the stop and
--   its sentence as they are (public.fleet_job_note, one hunk). So the job in the report goes on by itself after this file: no press.
--   DECIDED BY DEFAULT (the owner may reverse): the 10 minutes are a constant, not a knob; a stop on any other code still waits for her.
-- THE HUNKS (10; each once in the live body, each reverses): fleet_job_sails x1, fleet_job_plan x3, fleet_job_set_for x2,
--   fleet_jobs_due x1, fleet_job_open x1, fleet_job_note x1, tick_fleet_jobs x1. NEW: public.fleet_job_leg_shut, public.fleet_job_legs.
-- NOT CHANGED: nav_leg_nm_base and every knob and switch; public.passage_gate, voyage.leg_refusal, voyage.reach_passage,
--   public.fleet_job_course, cmd.issue_lines, cmd.do_sail; any table, column or cron job; any client read's shape.
-- ROWS: no new row kind. A job that used to stop now writes its plan's orders (one SAIL a harbour: Island of Mozambique -> Lisbon is 7).
-- THE TICK'S COST (local, PGlite, this file's own scene; the notice prints them). Before: one course lookup a SAIL line. After: + one
--   measure of that course and one voyage.leg_refusal a SAIL line (a few ms), + ONE voyage.reach_passage for a leg that is shut
--   (local 17-29 ms with 0482's kept matrix) and the lookups of its harbours. A near fixed job's plan: the same lines, a few ms more.
--   A stopped job: was 0 plans; now at most one plan in 10 minutes (the tick still starts at most fleet_jobs_per_tick jobs a run).
-- LOCKS: CREATE OR REPLACE x7 by hunks (six functions, one procedure), CREATE FUNCTION x2. TIME: about a second. BUDGET:
--   statement_timeout 60 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): a migration reversing the ten hunks (OLD texts below verbatim) and dropping the two functions. QUICK:
--   none of its own; fleet_jobs_enabled false stops every job, as before.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; no knob moved; the two new functions STABLE and server only (public, anon, authenticated, service_role). THE PROBES (rolled
--   back by raised sentinels): ONE SCENE run before the hunks and again after: (near) a fixed job on Lisbon's nearest lane: the same
--   set, plan, orders and receipt to the letter; (the report) her fleet at ISL, a land job {"to": "CAD"}: BEFORE it stops E_LEG_TOO_FAR
--   on "Line 1 (SAIL LIS): that leg is ... nm" (the reported case); AFTER it starts, SAIL by SAIL to LIS, every leg within her reach.
--   Then: a job already stopped is left alone inside 10 minutes and re-planned after them; with no chain (the probe shortens her reach,
--   rolled back) it stays stopped with the plain sentence, is stamped, and the next run asks nothing; the door refuses a land and a
--   fixed job with no chain (E_LEG_TOO_FAR); with her real reach the door takes a land, a fixed and a bring-home job and each plans
--   through harbours; a `best` sale's lines (public.sale_lines) do too. Proof 197 plays each kind through the tick.
--   THE PROBES ASK NO REAL JOB: inside each rolled-back block every other company's job is first told to wait a day (rolled back with
--   it), so the probe's tick plans the probe's fleet alone; its receipt is read by this transaction's own instant.
-- VERSION: 0494 (0493 `rate-why` lands first; it touches none of these bodies).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_sails(uuid,uuid,text[])', 'public.fleet_job_plan(uuid)',
                                    'public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'public.fleet_jobs_due()',
                                    'public.fleet_job_open(uuid,jsonb)', 'public.fleet_job_note(uuid,jsonb)', 'public.tick_fleet_jobs(boolean)'];
  c_new    constant text[] := array['public.fleet_job_leg_shut(uuid,uuid,jsonb)', 'public.fleet_job_legs(uuid,uuid,uuid)'];
  c_ua     constant uuid := '00000000-0494-4000-8000-0000000000a1';
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
  v_d0        jsonb;
  v_d1        jsonb;
  v_lis       uuid;
  v_isl       uuid;
  v_a         uuid;
  v_fa        uuid;
  v_g         text;
  v_r         jsonb;
  v_p         jsonb;
  v_reach     numeric;
  v_max       numeric;
  v_base      jsonb;
  v_orders    bigint;
  v_at        timestamptz;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.fleet_job_legs(uuid,uuid,uuid)') is not null or to_regprocedure('public.fleet_job_leg_shut(uuid,uuid,jsonb)') is not null then
    raise exception '0494 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.fleet_job_ends(uuid,uuid,jsonb,text)') is null or to_regprocedure('public.sea_course(uuid,uuid)') is null
     or to_regprocedure('voyage.leg_refusal(uuid,uuid,numeric,jsonb)') is null or to_regprocedure('voyage.reach_passage(uuid,uuid,uuid,numeric)') is null
     or to_regprocedure('public.supply_reach(uuid)') is null or to_regprocedure('voyage.segments_from_course(jsonb)') is null then
    raise exception '0494 refuses: 0492, 0482, 0231 or 0188 is not in this world';
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

  -- ── 2. THE SCENE (a temp function, run before the hunks and after): a near fixed job, then the reported land job at ISL ──
  execute $f$
create function pg_temp.scene_0494(p_uid uuid)
returns jsonb
language plpgsql
as $body$
declare
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_isl uuid := (select p.id from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR');
  v_pl  uuid;
  v_fl  uuid;
  v_xc  text;
  v_x   uuid;
  v_gc  text;
  v_set jsonb;
  v_pln jsonb;
  v_job jsonb;
  v_ord jsonb;
  v_rec jsonb;
  v_ms0 numeric;
  v_near jsonb;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0494', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players p set ducats = 2000000 where p.id = v_pl;
  -- (near) the harbour: Lisbon's nearest merchant lane both ways; the good: the one it offers most (0492's scene)
  select k.to_port, k.code into v_x, v_xc from public.npc_known_legs(v_lis) k join public.ports p on p.id = k.to_port
   where p.kind = 'HARBOUR' and public.fleet_job_course(v_fl, k.to_port, v_lis) is not null order by k.nm, k.code limit 1;
  select g.code into v_gc from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_x and public.port_offers(v_x, g.id) and pg.stock > 0 and g.bulk > 0
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_x), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  update public.fleets set port_id = v_x, status = 'DOCKED' where id = v_fl;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled');
  -- only this scene's job is asked: every other company's job waits a day (rolled back with the scene; no real job is planned here)
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_pl;
  perform cmd.assume_identity(p_uid);
  v_set := cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_gc, 'buy', v_xc, 'sell', 'LIS')) - 'fleet';
  v_pln := public.fleet_job_plan(v_fl) - 'version';
  call public.tick_fleet_jobs(false);
  select jsonb_build_object('kind', j.kind, 'params', j.params, 'runs', j.runs, 'last', j.last - 'at', 'paused', j.paused_reason) into v_job
    from public.fleet_jobs j where j.fleet_id = v_fl;
  select jsonb_agg(jsonb_build_array(o.raw_text, o.verb, o.status, o.error_code) order by o.seq) into v_ord from public.orders o where o.fleet_id = v_fl;
  select r.receipt - 'steps' || jsonb_build_object('steps', (select jsonb_agg(s - 'fleet' - 'plan_ms' - 'open_ms') from jsonb_array_elements(r.receipt->'steps') s)),
         (r.receipt #>> '{steps,0,plan_ms}')::numeric
    into v_rec, v_ms0 from public.fleet_job_runs r where r.at = now();
  v_near := jsonb_build_object('at', v_xc, 'good', v_gc, 'set', v_set, 'plan', v_pln, 'job', v_job, 'orders', v_ord, 'receipt', v_rec,
                               'status', (select f.status from public.fleets f where f.id = v_fl));

  -- (the report) the same fleet, empty, docked at Island of Mozambique; her party ashore at home (Lisbon); a land job {"to": "CAD"}
  delete from public.fleet_jobs where fleet_id = v_fl;
  update public.orders set status = 'cancelled' where fleet_id = v_fl and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fl and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fl;
  perform public.fleet_unload(v_fl, v_gc, public.fleet_cargo_qty(v_fl, v_gc));
  perform public.land_party(v_pl);
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at)
  values (v_fl, v_pl, 'land', '{"to": "CAD"}'::jsonb, now(), now());
  call public.tick_fleet_jobs(false);
  return jsonb_build_object(
    'near', v_near, 'near_plan_ms', v_ms0,
    'far_plan_ms', (select (r.receipt #>> '{steps,0,plan_ms}')::numeric from public.fleet_job_runs r where r.at = now()),
    'far', (select jsonb_build_object(
                     'paused', j.paused_reason, 'runs', j.runs, 'last', j.last - 'at',
                     'texts', (select jsonb_agg(o.raw_text order by o.seq) from public.orders o where o.fleet_id = v_fl and o.plan_id = j.last_plan),
                     'max_nm', (select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(o.args->'path')) s))
                                  from public.orders o where o.fleet_id = v_fl and o.plan_id = j.last_plan and jsonb_typeof(o.args->'path') = 'array'),
                     'reach', public.passage_reach_nm(v_pl),
                     'status', (select f.status from public.fleets f where f.id = v_fl))
              from public.fleet_jobs j where j.fleet_id = v_fl));
end
$body$
  $f$;

  begin
    v_d0 := pg_temp.scene_0494(c_ua);
    raise exception using errcode = 'ZX494', message = 'PROBE_ROLLBACK_0494_BEFORE';
  exception when sqlstate 'ZX494' then null;
  end;
  if v_d0 #>> '{near,set,ok}' is distinct from 'true' or v_d0 #>> '{near,job,runs}' is distinct from '1' then
    raise exception '0494 self-assert FAIL: the near fixed job did not run before the hunks: %', left(v_d0::text, 600);
  end if;
  -- THE REPORTED CASE, BEFORE: one line, SAIL LIS, refused by its length; the job stops and nothing is sent
  if v_d0 #>> '{far,paused}' is distinct from 'E_LEG_TOO_FAR'
     or v_d0 #>> '{far,last,sentence}' not like 'Line 1 (SAIL LIS): that leg is % nm and your navigation carries you % nm%'
     or v_d0 #>> '{far,last,to}' is distinct from 'LIS' or v_d0 #>> '{far,runs}' is distinct from '0' or v_d0 #>> '{far,status}' is distinct from 'DOCKED' then
    raise exception '0494 self-assert FAIL: before the hunks the land job at ISL did not stop as the owner reported: %', v_d0->'far';
  end if;

  -- ── 3. THE RULES ──
  execute $f$
create function public.fleet_job_leg_shut(p_fleet uuid, p_to uuid, p_course jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0494: IS THIS LEG OF A JOB SHUT BY ITS LENGTH OR ITS STORES? The course measured as cmd.issue_lines and cmd.do_sail measure it
-- (voyage.segments_from_course), judged by THE leg judge (voyage.leg_refusal): its refusal {code, sentence, figures} when the code is
-- E_LEG_TOO_FAR or E_ENDURANCE, else null (open, or shut by something a harbour between does not mend: the door says so, as before; a
-- course the server cannot read is the door's to refuse too).
declare
  v_nm numeric;
  v_r  jsonb;
begin
  begin
    select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(p_course)) s;
  exception when others then
    return null;
  end;
  v_r := voyage.leg_refusal(p_fleet, p_to, v_nm, p_course);
  return case when v_r->>'code' in ('E_LEG_TOO_FAR', 'E_ENDURANCE') then v_r end;
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_legs(p_fleet uuid, p_from uuid, p_to uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0494: THE SAILS OF A JOB FROM ONE HARBOUR TO ANOTHER, EACH A LEG SHE CAN SAIL (public.fleet_job_sails asks this for every harbour it is
-- sent; so every kind of job does). {lines: [{text, path}]}: the one SAIL with the course a job sails (public.fleet_job_course) when
-- that leg is open; when it is shut by its length or its stores (public.fleet_job_leg_shut), one SAIL a harbour through the harbours
-- between from voyage.reach_passage (THE pathfinder, capped by the legs her stores cover, as world.route_legs' `via` asks it), each
-- with its own course, each judged the same way. Else {pause, sentence}: E_NO_COURSE when no course joins the two (0481's words), or
-- the judge's own code and a plain sentence when no chain of harbours makes every leg one she can sail.
declare
  v_player uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_code   text := (select p.code from public.ports p where p.id = p_to);
  v_c      jsonb;
  v_shut   jsonb;
  v_stops  text[];
  v_at     uuid := p_from;
  v_hop    uuid;
  v_out    jsonb := '[]'::jsonb;
  v_why    text;
  x        text;
begin
  v_c := public.fleet_job_course(p_fleet, p_from, p_to);
  if v_c is null then
    return jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_code));
  end if;
  v_shut := public.fleet_job_leg_shut(p_fleet, p_to, v_c);
  if v_shut is null then
    return jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_code, 'path', v_c)));
  end if;
  -- too long, or more days than her stores: the harbours between, by the one pathfinder
  v_why := v_shut->>'sentence';
  select r.stops into v_stops
    from voyage.reach_passage(v_player, p_fleet, p_from, (select sr.cap_nm from public.supply_reach(p_fleet) sr)) r
   where r.port_id = p_to and r.nm is not null;
  if coalesce(cardinality(v_stops), 0) > 0 then
    foreach x in array v_stops || v_code loop
      v_hop := (select p.id from public.ports p where p.code = x and p.kind = 'HARBOUR');
      v_c := public.fleet_job_course(p_fleet, v_at, v_hop);
      if v_c is null then
        v_why := format('no course the world remembers reaches %s', x);
        v_out := null;
        exit;
      end if;
      if public.fleet_job_leg_shut(p_fleet, v_hop, v_c) is not null then
        v_out := null;
        exit;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || x, 'path', v_c));
      v_at := v_hop;
    end loop;
    if v_out is not null then
      return jsonb_build_object('lines', v_out);
    end if;
  end if;
  return jsonb_build_object(
    'pause', v_shut->>'code',
    'sentence', format('she cannot sail from %s to %s harbour by harbour: %s',
                       (select p.name from public.ports p where p.id = p_from), (select p.name from public.ports p where p.id = p_to), v_why));
end
$body$
  $f$;

  -- grants: both server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0494 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0494 values
  ('public.fleet_job_sails(uuid,uuid,text[])', 1,
$h$    v_c := public.fleet_job_course(p_fleet, v_at, v_to);
    if v_c is null then
      return jsonb_build_object('missing', x);
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || x, 'path', v_c));$h$,
$h$    -- 0494: harbour by harbour (public.fleet_job_legs): the one SAIL when she can sail that leg, else one a harbour between; no way
    -- through: {missing, pause, sentence}
    v_c := public.fleet_job_legs(p_fleet, v_at, v_to);
    if not (v_c ? 'lines') then
      return v_c || jsonb_build_object('missing', x);
    end if;
    v_out := v_out || (v_c->'lines');$h$),
  ('public.fleet_job_plan(uuid)', 1,
$h$  if j.last_plan is not null then$h$,
$h$  if j.last_plan is not null and j.paused_reason is null then   -- 0494: a stopped job asked again plans afresh (its stop said this once)$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$      return jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$,
$h$      return jsonb_build_object('pause', coalesce(v_s->>'pause', 'E_NO_COURSE'),   -- 0494: or the leg judge's code and sentence
                                'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing')));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$),
  ('public.fleet_job_plan(uuid)', 3,
$h$      return jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version,
                              'note', jsonb_build_object('kind', 'land',$h$,
$h$      return jsonb_build_object('pause', coalesce(v_s->>'pause', 'E_NO_COURSE'),   -- 0494: or the leg judge's code and sentence (land)
                                'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing')));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version,
                              'note', jsonb_build_object('kind', 'land',$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$    if v_s ? 'missing' then
      perform cmd.refuse('E_NO_COURSE', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;$h$,
$h$    -- 0494: and her first sail, from where she lies now to `buy`, when she is docked in a third harbour
    if not (v_s ? 'missing') and f.status = 'DOCKED' and f.port_id is distinct from v_buy and f.port_id is distinct from v_sell
       and exists (select 1 from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR') then
      v_s := public.fleet_job_sails(p_fleet, f.port_id, array[p_params->>'buy']);
    end if;
    if v_s ? 'missing' then   -- 0494: no course, or no chain of harbours she can sail (the leg judge's code and sentence)
      perform cmd.refuse(coalesce(v_s->>'pause', 'E_NO_COURSE'), coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing')));
    end if;$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 2,
$h$    if public.fleet_job_course(p_fleet, lp.port_id, v_to_id) is null then
      perform cmd.refuse('E_NO_COURSE', format('no course the world remembers reaches %s', v_to));
    end if;$h$,
$h$    -- 0494: to the yard, back, and her first sail from where she lies now: each through harbours she can sail (public.fleet_job_sails)
    v_s := public.fleet_job_sails(p_fleet, lp.port_id, array[v_to]);
    if not (v_s ? 'missing') then
      v_s := public.fleet_job_sails(p_fleet, v_to_id, array[(select p.code from public.ports p where p.id = lp.port_id)]);
    end if;
    if not (v_s ? 'missing') and f.status = 'DOCKED' and f.port_id is distinct from lp.port_id and f.port_id is distinct from v_to_id
       and exists (select 1 from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR') then
      v_s := public.fleet_job_sails(p_fleet, f.port_id, array[(select p.code from public.ports p where p.id = lp.port_id)]);
    end if;
    if v_s ? 'missing' then   -- 0494 (land): no course, or no chain of harbours she can sail
      perform cmd.refuse(coalesce(v_s->>'pause', 'E_NO_COURSE'), coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', coalesce(v_s->>'missing', v_to))));
    end if;$h$),
  ('public.fleet_jobs_due()', 1,
$h$     and j.paused_reason is null and (j.next_at is null or j.next_at <= now())$h$,
$h$     -- 0494: a job stopped by a leg's length or its stores is asked again 10 minutes after its last word (public.tick_fleet_jobs stamps
     -- every try), never sooner; a stop on any other code waits for her
     and (j.paused_reason is null
          or (j.paused_reason in ('E_LEG_TOO_FAR', 'E_ENDURANCE')
              and coalesce((j.last->>'at')::timestamptz, j.since) <= now() - interval '10 minutes'))
     and (j.next_at is null or j.next_at <= now())$h$),
  ('public.fleet_job_open(uuid,jsonb)', 1,
$h$       set runs = j.runs + 1, next_at = null,$h$,
$h$       set runs = j.runs + 1, next_at = null, paused_reason = null,   -- 0494: a stopped job whose retry starts goes on$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait')
     where fleet_id = p_fleet;$h$,
$h$           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait')
     where fleet_id = p_fleet and paused_reason is null;   -- 0494: a stopped job asked again keeps its stop and its sentence$h$),
  ('public.tick_fleet_jobs(boolean)', 1,
$h$    v_steps := v_steps || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object($h$,
$h$    -- 0494: a job stopped by a leg's length or its stores has had its try, whatever came of it: asked again 10 minutes on
    update public.fleet_jobs set last = coalesce(last, '{}'::jsonb) || jsonb_build_object('at', now())
     where fleet_id = v_ids[i] and paused_reason in ('E_LEG_TOO_FAR', 'E_ENDURANCE');
    if p_commit then commit; end if;
    v_steps := v_steps || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object($h$);

  for v_h in select h.fn from hunks_0494 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0494 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0494 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0494 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0494 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0494 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  perform public.news_update('0494', 'Fleet jobs sail harbour by harbour: a trip too long for one leg goes through the harbours between, and a stopped job goes on by itself once there is a way',
                             'Fleet jobs sail harbour by harbour: a trip too long for one leg goes through the harbours between, and a stopped job goes on by itself once there is a way');

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the grants ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0494 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0494 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0494 self-assert FAIL: a knob moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's') <> 2
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0494 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;

  -- ── 6. THE PROBES ──
  -- (a) THE SAME SCENE AFTER: the near fixed job to the letter; the reported land job starts, SAIL by SAIL to Lisbon, each leg in reach
  begin
    v_d1 := pg_temp.scene_0494(c_ua);
    raise exception using errcode = 'ZX494', message = 'PROBE_ROLLBACK_0494_AFTER';
  exception when sqlstate 'ZX494' then null;
  end;
  if v_d1->'near' is distinct from v_d0->'near' then
    raise exception '0494 self-assert FAIL: the near fixed job moved: before % / after %', left((v_d0->'near')::text, 700), left((v_d1->'near')::text, 700);
  end if;
  if v_d1 #>> '{far,paused}' is not null or v_d1 #>> '{far,runs}' is distinct from '1' or v_d1 #>> '{far,status}' is distinct from 'SAILING'
     or jsonb_array_length(coalesce(v_d1 #> '{far,texts}', '[]'::jsonb)) < 2 or v_d1 #>> '{far,texts,-1}' is distinct from 'SAIL LIS'
     or exists (select 1 from jsonb_array_elements_text(v_d1 #> '{far,texts}') t(s) where t.s not like 'SAIL %')
     or (v_d1 #>> '{far,max_nm}')::numeric > (v_d1 #>> '{far,reach}')::numeric or v_d1 #>> '{far,last,to}' is distinct from 'LIS' then
    raise exception '0494 self-assert FAIL: after the hunks the land job at ISL did not sail harbour by harbour to Lisbon: %', v_d1->'far';
  end if;
  v_note := format('near fixed job identical %s (%s at %s; plan %s -> %s ms); the report: before "%s", after %s (longest leg %s of %s nm; plan %s -> %s ms)',
                   left(md5((v_d0->'near')::text), 8), v_d0 #>> '{near,good}', v_d0 #>> '{near,at}', v_d0->>'near_plan_ms', v_d1->>'near_plan_ms',
                   v_d0 #>> '{far,last,sentence}', (select string_agg(t.s, ' / ') from jsonb_array_elements_text(v_d1 #> '{far,texts}') t(s)),
                   round((v_d1 #>> '{far,max_nm}')::numeric), round((v_d1 #>> '{far,reach}')::numeric), v_d0->>'far_plan_ms', v_d1->>'far_plan_ms');

  -- (b)-(f): one company (home Lisbon), her fleet docked at Island of Mozambique; rolled back by the sentinel
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select p.id into v_isl from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa do Caminho 0494', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    update public.players p set ducats = 2000000 where p.id = v_a;
    update public.fleets set port_id = v_isl, status = 'DOCKED' where id = v_fa;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
    update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;   -- only the probe's job is asked (rolled back)
    perform cmd.assume_identity(c_ua);
    perform public.land_party(v_a);
    v_reach := public.passage_reach_nm(v_a);
    select g.code into v_g from public.goods g where g.bulk > 0 order by g.code limit 1;

    -- (b) A JOB ALREADY STOPPED (prod's row as it stands): left alone inside 10 minutes; after them re-planned, started, the stop lifted
    insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at, paused_reason, last)
    values (v_fa, v_a, 'land', '{"to": "CAD"}'::jsonb, now() - interval '1 hour', now() - interval '1 hour', 'E_LEG_TOO_FAR',
            jsonb_build_object('at', now() - interval '5 minutes', 'ok', false, 'code', 'E_LEG_TOO_FAR', 'kind', 'land', 'from', 'ISL', 'to', 'LIS',
                               'sentence', 'Line 1 (SAIL LIS): that leg is 7052 nm and your navigation carries you 1700 nm — study navigation'));
    call public.tick_fleet_jobs(false);
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_LEG_TOO_FAR'
       or (select (j.last->>'at')::timestamptz from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from now() - interval '5 minutes'
       or exists (select 1 from public.orders o where o.fleet_id = v_fa) then
      raise exception '0494 self-assert FAIL: a job stopped 5 minutes ago was asked again';
    end if;
    update public.fleet_jobs set last = last || jsonb_build_object('at', now() - interval '11 minutes') where fleet_id = v_fa;
    call public.tick_fleet_jobs(false);
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is not null
       or (select j.runs from public.fleet_jobs j where j.fleet_id = v_fa) <> 1
       or world.away_report() #>> '{jobs,0,state}' is distinct from 'working'
       or not exists (select 1 from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING')
       or (select o.raw_text from public.orders o where o.fleet_id = v_fa order by o.seq desc limit 1) is distinct from 'SAIL LIS' then
      raise exception '0494 self-assert FAIL: a job stopped 11 minutes ago was not re-planned through harbours: %',
        (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;

    -- (c) NO CHAIN, NO HOT LOOP: back at ISL, stopped 11 minutes ago, her reach shortened to 100 nm (this probe's alone, rolled back):
    --     the retry finds no way, the job stays stopped with the plain sentence, is stamped now, and the next run asks nothing
    update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_isl where id = v_fa;
    v_orders := (select count(*) from public.orders o where o.fleet_id = v_fa);
    update public.fleet_jobs set paused_reason = 'E_LEG_TOO_FAR', last_plan = null,
           last = jsonb_build_object('at', now() - interval '11 minutes', 'ok', false, 'code', 'E_LEG_TOO_FAR', 'sentence', 'old') where fleet_id = v_fa;
    v_base := (select c.value from public.world_config c where c.key = 'nav_leg_nm_base');
    update public.world_config set value = to_jsonb(100) where key = 'nav_leg_nm_base';
    call public.tick_fleet_jobs(false);
    select (j.last->>'at')::timestamptz into v_at from public.fleet_jobs j where j.fleet_id = v_fa;
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_LEG_TOO_FAR'
       or (select j.last->>'sentence' from public.fleet_jobs j where j.fleet_id = v_fa) not like 'she cannot sail from Island of Mozambique to Lisbon harbour by harbour: that leg is % nm and your navigation carries you 100 nm%'
       or v_at is distinct from now()
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders
       or (select r.receipt #>> '{steps,0,pause}' from public.fleet_job_runs r where r.at = now()) is distinct from 'E_LEG_TOO_FAR' then
      raise exception '0494 self-assert FAIL: with no chain the stopped job did not stay stopped with its plain sentence, stamped: %',
        (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;
    v_note := v_note || format('; no chain: "%s"', (select j.last->>'sentence' from public.fleet_jobs j where j.fleet_id = v_fa));
    call public.tick_fleet_jobs(false);
    if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 0
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders then
      raise exception '0494 self-assert FAIL: a job that had its try was asked again by the very next run: %',
        (select r.receipt from public.fleet_job_runs r where r.at = now());
    end if;

    -- (d) THE DOOR, NO CHAIN: a land job and a fixed job are refused when set, by the judge's code, and the job she has is not touched
    v_r := cmd.set_fleet_job(v_fa, 'land', '{"to": "CAD"}'::jsonb);
    v_p := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', 'ISL'));
    if v_r->>'error_code' is distinct from 'E_LEG_TOO_FAR' or v_r->>'error_message' not like '%harbour by harbour%'
       or v_p->>'error_code' is distinct from 'E_LEG_TOO_FAR' or v_p->>'error_message' not like '%cannot sail from Lisbon to Island of Mozambique harbour by harbour%'
       or (select j.kind || ':' || j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'land:E_LEG_TOO_FAR' then
      raise exception '0494 self-assert FAIL: with no chain the door did not refuse a land and a fixed job E_LEG_TOO_FAR: % / %', v_r, v_p;
    end if;
    update public.world_config set value = v_base where key = 'nav_leg_nm_base';

    -- (e) THE DOOR AND THE PLAN, HER REAL REACH: land, fixed and bring home are taken and each plans through harbours, every leg in reach
    v_r := cmd.set_fleet_job(v_fa, 'land', '{"to": "CAD"}'::jsonb);
    v_p := public.fleet_job_plan(v_fa);
    select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(l->'path')) s)) into v_max
      from jsonb_array_elements(v_p->'lines') l where l ? 'path';
    if (v_r->>'ok')::boolean is not true or jsonb_array_length(v_p->'lines') < 2 or v_p #>> '{lines,-1,text}' is distinct from 'SAIL LIS'
       or v_max is null or v_max > v_reach then
      raise exception '0494 self-assert FAIL: a land job set at ISL does not plan harbour by harbour to Lisbon: % / %', v_r, left(v_p::text, 300);
    end if;
    v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', 'ISL'));
    v_p := public.fleet_job_plan(v_fa);
    select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(l->'path')) s)) into v_max
      from jsonb_array_elements(v_p->'lines') l where l ? 'path';
    if (v_r->>'ok')::boolean is not true or jsonb_array_length(v_p->'lines') < 2 or v_p #>> '{lines,-1,text}' is distinct from 'SAIL LIS'
       or exists (select 1 from jsonb_array_elements(v_p->'lines') l where l->>'text' not like 'SAIL %') or v_max is null or v_max > v_reach then
      raise exception '0494 self-assert FAIL: a fixed job (she lies at its far end) does not plan home harbour by harbour: % / %', v_r, left(v_p::text, 300);
    end if;
    v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g, 'buy', 'ISL', 'end', 'store'));
    v_p := public.fleet_job_plan(v_fa);
    select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(l->'path')) s)) into v_max
      from jsonb_array_elements(v_p->'lines') l where l ? 'path';
    if (v_r->>'ok')::boolean is not true or v_r #>> '{params,sell}' is distinct from 'LIS' or jsonb_array_length(v_p->'lines') < 4
       or v_p #>> '{lines,0,text}' not like 'BUY ' || v_g || ' %' or v_p #>> '{lines,-1,text}' is distinct from format('STORE %s ALL', v_g)
       or v_p #>> '{lines,-2,text}' is distinct from 'SAIL LIS' or v_max is null or v_max > v_reach then
      raise exception '0494 self-assert FAIL: a bring-home job from ISL does not plan BUY / SAIL harbour by harbour / STORE: % / %', v_r, left(v_p::text, 300);
    end if;

    -- (f) BEST: a sale's lines (public.sale_lines, the one writer of a `best` run's lines) go through harbours too
    v_p := public.sale_lines(v_fa, v_isl, jsonb_build_object('good', v_g, 'port', 'LIS', 'units', 1, 'basis', 'buy'), '[]'::jsonb);
    select max((select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(l->'path')) s)) into v_max
      from jsonb_array_elements(v_p->'lines') l where l ? 'path';
    if jsonb_array_length(coalesce(v_p->'lines', '[]'::jsonb)) < 4 or v_p #>> '{lines,-1,text}' is distinct from format('SELL %s ALL', v_g)
       or v_p #>> '{lines,-2,text}' is distinct from 'SAIL LIS' or v_max is null or v_max > v_reach then
      raise exception '0494 self-assert FAIL: a best sale''s lines from ISL to Lisbon are not harbour by harbour: %', left(v_p::text, 300);
    end if;
    v_note := v_note || '; stopped 5 min ago left alone, 11 min ago re-planned and started; the next run asks nothing; the door refuses land and fixed with no chain (E_LEG_TOO_FAR) and takes land, fixed, bring home with one; best''s sale lines chained';
    raise exception using errcode = 'ZX494', message = 'PROBE_ROLLBACK_0494';
  exception when sqlstate 'ZX494' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0494 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0494' or p.auth_uid = c_ua)
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before
     or public.current_player_id() is not null then
    raise exception '0494 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.scene_0494(uuid);

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0494 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0494 self-assert ok: A JOB SAILS HARBOUR BY HARBOUR. % hunks once and reversing; no other function moved; the hunked bodies'' grants and volatility unmoved; no knob moved; two new functions STABLE and server only. Probes (rolled back): %. % ms.',
    (select count(*) from hunks_0494), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
