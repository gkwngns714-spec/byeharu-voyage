-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0316 — INSURANCE PAYS ITS WAY: a ship that reaches her port on her last cask has arrived, so the city does not pay for a hold she never lost
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, slice W0b of docs/WORLD_POWERS.md: cities paid out 29.5 M d. in 24 h and took in 7.4 M d. Measure, root cause. docs/dev-log/2026-11-05-insurance.md holds the numbers.
--
-- WHY (measured on prod, read-only, 2026-11-05, head 0312). Premiums are not the cause and no rate moves here.
--   Every claim on record: 142 FORCED_HOME (cities paid 6.57 M d., 92 %; owed 15.44 M d.) and 31 raids (paid 0.60 M d.; owed 1.09 M d.). Storms take no cargo.
--   Premiums on those same 23,248 policies: 1.90 M d., so raids alone are covered 1.74 times. Insurance earned until 10-29 (+0.62 M d. that day) and turned the day 0279 went live.
--   280 of the 283 forced homes in the record, and ALL 142 of the insured ones, fell on a day whose boundary IS the voyage's ETA: she had arrived. 279 of them were "forced" into their
--   own destination, losing the whole hold on the quay, hull damage on top. The other 3 were real (FOUL_WATER, 0.1 to 0.3 of a day short of port), with empty holds and no claim.
--
-- THE BUG. 0279's guard is `d < v_cap`, written for "the trailing day" that voyage.day_ends_at clamps at the ETA. But a CALM or a STORM stacks SEVERAL days there, not one: voyage.total_days
-- counts the delay (ceil((sim + delay) / 24)), and every boundary after the delay is pushed by it as well (d * 24 + delay), so any day with d * 24 >= sim lands on the ETA instant. A merchant
-- carries ceil(1.15 * sim / 24) + 1 days of stores, so 1.5 to 4 days of delay runs her casks dry on one of those stacked days, d < v_cap holds, and she is turned away from the harbour she is
-- entering. Every such ship was a claim for 100 % of a hold she still had.
--
-- WHAT THIS FILE DOES: one hunk of voyage.settle. The test becomes the fact it meant: `v_bound < v.eta`, a day that ends before she arrives. It covers the old final-day case too (a final day
-- always ends on the ETA). A ship that runs dry at sea is forced home, claims and all, exactly as before.
--
-- NOT TOUCHED: every knob and rate (insurance_raid_loss, insurance_margin, insurance_keep_pct, endurance_margin), voyage.risk_quote, public.insurance_price, public.insurance_claim,
-- voyage.forced_home, voyage.day_ends_at, voyage.total_days, the merchants' stores. Past claims stay paid; `short` was never owed.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - A delay alone never strands her. Once her sailing time is done (d * 24 >= sim) the next boundary IS her arrival, so a ship dry after that docks, even if a long calm held her out for hours
--     on empty casks. The other reading, cutting her mid-calm, loses the same holds, all but on her destination's doorstep: the same drain, then priced as a real risk.
--   - The cover for a real dry day stays as the owner set it (row 223), and it stays unpriced: 3 real ones in 7 hours, all with empty holds.
--
-- SELF-ASSERT (own probe houses, every row rolled back; no real voyage, no world_config row): the bug reproduced on the pre-image body and gone on the new one, settled at once and day by day;
-- a real dry day at sea still forced home with its claim; a dry final day still an arrival; the hunk reverses; nothing else moved.
-- Mutation controls: scripts/ops/harness/insurance/proof-0316.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): swap this file's v_old and v_new. Nothing else was changed, and no row of data was written.
-- VERSION: 0316, after 0313-0315. Cut from prod head 0312; the hunk must still occur once at the rebase (0313 does not touch voyage.settle).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_old  text := $h$    -- A DRY FINAL DAY IS AN ARRIVAL, NOT A STRANDING: d < v_cap. voyage.day_ends_at clamps the
    -- trailing day at the ETA, so a ship that drinks her last cask as she makes port docks there
    -- (the arrival arm below) instead of being turned away from a harbour she is entering.
    if v_end <= 0 and d < v_cap$h$;
  v_new  text := $h$    -- A DRY DAY THAT ENDS ON THE ETA IS AN ARRIVAL, NOT A STRANDING (0316, was d < v_cap): voyage.day_ends_at
    -- clamps at the ETA, and a delay stacks SEVERAL trailing days there, not one, because voyage.total_days
    -- counts it and every later boundary is pushed by it too. A ship that drinks her last cask on any of them
    -- docks (the arrival arm below) instead of being turned away from the harbour she is entering, and no
    -- insurance pays for a hold she still has. v was re-read at the end of the last day, so v.eta is current.
    if v_end <= 0 and v_bound < v.eta$h$;
  v_settle regprocedure := 'voyage.settle(uuid,timestamp with time zone)'::regprocedure;
  v_def0 text;
  v_def  text;
  v_acl0 text;
  v_cfg0 text;
  v_fn_before  text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
  v_all  jsonb;
  v_res  jsonb := '{}'::jsonb;
  v_x    jsonb;
  s      record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('voyage.forced_home(uuid,integer,uuid)') is null or to_regprocedure('public.insurance_claim(uuid,integer,jsonb,text)') is null then
    raise exception '0316 refuses: 0213 / 0279 (the insurance, the forced home) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> v_settle;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
    into v_def0, v_acl0, v_cfg0
    from pg_proc p where p.oid = v_settle;

  -- ── 1. THE PRE-IMAGE, kept callable for the old-against-new probe ──
  if (length(v_def0) - length(replace(v_def0, 'CREATE OR REPLACE FUNCTION voyage.settle(', ''))) / length('CREATE OR REPLACE FUNCTION voyage.settle(') <> 1 then
    raise exception '0316 self-assert FAIL: the head of voyage.settle is not where it was expected';
  end if;
  execute replace(v_def0, 'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE OR REPLACE FUNCTION pg_temp.settle_b0316(');

  -- ── 2. THE HUNK ──
  if (length(v_def0) - length(replace(v_def0, v_old, ''))) / length(v_old) <> 1 then
    raise exception '0316 self-assert FAIL: the hunk of voyage.settle occurs % time(s), not once: the deployed body is not what this file was written against',
      (length(v_def0) - length(replace(v_def0, v_old, ''))) / length(v_old);
  end if;
  v_def := replace(v_def0, v_old, v_new);
  execute v_def;

  -- ── 3. THE SELF-ASSERT: the hunk reverses, nothing else moved ──
  v_def := replace(pg_get_functiondef(v_settle), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception '0316 self-assert FAIL: the hunk is not in the new body once';
  end if;
  if replace(v_def, v_new, v_old) <> v_def0 then
    raise exception '0316 self-assert FAIL: voyage.settle does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = v_settle) <> v_acl0
     or (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_settle) <> v_cfg0 then
    raise exception '0316 self-assert FAIL: the ACL, volatility, definer or config of voyage.settle moved';
  end if;

  -- ── 4. THE SELF-ASSERT: one laden, insured voyage on a probe house, every row rolled back ──
  -- Lisbon to Funchal, a cargo of exactly 2,000, hazards off on HER OWN path. p: the settle to run ('new' or 'old'), `calm` hours of delay written on day 1, `days` of stores left
  -- when that day is done, `slow` to sail three times as long, `step` to settle every boundary in turn rather than once at the end. Answers what became of her.
  execute $f$
create function pg_temp.scene_0316(p_uid uuid, p jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_f    uuid;
  v_voy  uuid;
  v_a    text;
  v_b    text;
  v_la   numeric;
  v_lb   numeric;
  v_sim  numeric;
  v_dry  int;
  v_days numeric;
  v_calm numeric := (p ->> 'calm')::numeric;
  v_d    int;
  v_hull numeric;
  v_at   timestamptz;
  v_eta  timestamptz;
begin
  v_p := public.new_house(p_uid, 'Casa Enxuta ' || right(p_uid::text, 4), 'PRT', 'LIS', 'Enxuta ' || right(p_uid::text, 4), 'barca', 'Enxuta ' || right(p_uid::text, 4), null, false);
  select id into v_f from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0316', 1000000);
  select code into v_a from public.goods where bulk = 1 order by code limit 1;
  select code into v_b from public.goods where bulk = 1 and code > v_a order by code limit 1;
  v_la := public.fleet_load(v_f, v_a, 40, 25);
  v_lb := public.fleet_load(v_f, v_b, 10, 100);
  if v_la <> 40 or v_lb <> 10 or public.fleet_stock_at_cost(v_f) <> 2000 then
    raise exception '0316 self-assert FAIL: the probe''s cargo did not load (% of 40, % of 10, worth %)', v_la, v_lb, public.fleet_stock_at_cost(v_f);
  end if;
  v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'insured', true,
             'path', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                        from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc)))->>'voyage_id')::uuid;
  if not exists (select 1 from public.insured_voyages i where i.voyage_id = v_voy and i.value = 2000) then
    raise exception '0316 self-assert FAIL: the probe''s voyage is not insured for 2,000';
  end if;
  update public.voyages vo set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 0) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o))
   where vo.id = v_voy;
  if (p ->> 'slow')::boolean then
    -- a passage three times as long, on her own row: past a calm she still has days at sea ahead of her.
    update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 3) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
     where vo.id = v_voy;
    perform voyage.recompute_eta(v_voy);
  end if;
  v_sim := voyage.sim_hours(v_voy);
  v_dry := ceil(v_sim / 24);   -- the first day that ends on or past her sailing time: with any delay written, it is clamped at the ETA
  if v_calm > 0 then
    -- day 1 was a calm: the same row and the same recompute as voyage.settle's own arm.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 1, 'CALM', jsonb_build_object('delay_hours', v_calm), now());
    update public.voyages set last_settled_day = 1 where id = v_voy;
    perform voyage.recompute_eta(v_voy);
    if v_dry < 2 then v_dry := 2; end if;
  end if;
  v_d := (select last_settled_day from public.voyages where id = v_voy);
  -- her stores: what `days` days drink, or by default just enough to run out on v_dry, the first stacked day.
  v_days := case when p ? 'days' then (p ->> 'days')::numeric else v_dry - v_d end;
  update public.ships
     set water_t = crew * public.wc_num('water_per_crew_day') * v_days, food_t = crew * public.wc_num('food_per_crew_day') * v_days
   where fleet_id = v_f;
  select coalesce(sum(durability), 0) into v_hull from public.ships where fleet_id = v_f;
  v_eta := (select eta from public.voyages where id = v_voy);
  if p ->> 'run' = 'old' then
    perform pg_temp.settle_b0316(v_f, v_eta + interval '1 second');
  elsif (p ->> 'step')::boolean then
    for v_at in select voyage.day_ends_at(v_voy, g.d) from generate_series(1, voyage.total_days(v_voy)) g(d) order by 1 loop
      perform voyage.settle(v_f, v_at);
    end loop;
    perform voyage.settle(v_f, v_eta + interval '1 second');
  else
    perform voyage.settle(v_f, v_eta + interval '1 second');
  end if;
  return jsonb_build_object(
    'sim', v_sim, 'dry_day', v_dry, 'cap', voyage.total_days(v_voy), 'stores_days', v_days,
    'bound', voyage.day_ends_at(v_voy, v_dry) >= v_eta,
    'voyage', (select status from public.voyages where id = v_voy),
    'fleet', (select status from public.fleets where id = v_f),
    'at_dest', (select port_id from public.fleets where id = v_f) = v_fnc,
    'hold', public.fleet_stock_at_cost(v_f),
    'stores', (select coalesce(sum(water_t + food_t), 0) from public.ships where fleet_id = v_f),
    'hull_lost', v_hull - (select coalesce(sum(durability), 0) from public.ships where fleet_id = v_f),
    'forced_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
    'forced_days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'FORCED_HOME'),
    'claims', (select i.claims from public.insured_voyages i where i.voyage_id = v_voy),
    'owed', (select i.paid + i.short from public.insured_voyages i where i.voyage_id = v_voy));
end
$b$
$f$;

  for s in select * from (values
      ('bug_old',  '00000000-0316-4000-8000-000000000001'::uuid, '{"run":"old","calm":72,"step":false}'::jsonb),   -- the bug itself, on the pre-image body
      ('fixed',    '00000000-0316-4000-8000-000000000002'::uuid, '{"run":"new","calm":72,"step":false}'::jsonb),   -- the same scene, the new body
      ('stepped',  '00000000-0316-4000-8000-000000000003'::uuid, '{"run":"new","calm":72,"step":true}'::jsonb),    -- settled day by day: a late settle lands the same
      ('storm',    '00000000-0316-4000-8000-000000000004'::uuid, '{"run":"new","calm":36,"step":false}'::jsonb),   -- a storm's 36 hours, the smallest delay on record
      ('at_sea',   '00000000-0316-4000-8000-000000000005'::uuid, '{"run":"new","calm":0,"days":0,"step":false}'::jsonb),      -- dry on day 1, hours short of port: a real forced home
      ('at_sea_c', '00000000-0316-4000-8000-000000000006'::uuid, '{"run":"new","calm":72,"days":0,"slow":true,"step":false}'::jsonb),     -- a long passage, no stores after a calm: dry with days of sailing left, delay or no delay
      ('final',    '00000000-0316-4000-8000-000000000007'::uuid, '{"run":"new","calm":0,"step":false}'::jsonb)     -- no delay: dry on her true final day, as 0279 proved
    ) v(name, uid, p) loop
    begin
      raise exception using errcode = 'ZX316', message = pg_temp.scene_0316(s.uid, s.p)::text;
    exception when sqlstate 'ZX316' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
  end loop;
  v_all := v_res;
  drop function pg_temp.scene_0316(uuid, jsonb);
  drop function pg_temp.settle_b0316(uuid, timestamp with time zone);

  -- THE SCENE IS THE BUG: on the old body a ship dry on a stacked day, at her own ETA, lost her hold and claimed all of it.
  v_x := v_all -> 'bug_old';
  if (v_x ->> 'bound')::boolean is not true or (v_x ->> 'dry_day')::int >= (v_x ->> 'cap')::int then
    raise exception '0316 self-assert FAIL: the probe''s dry day is not a stacked day on the ETA: %', v_x;
  end if;
  if v_x ->> 'voyage' <> 'ABORTED' or (v_x ->> 'hold')::numeric <> 0 or (v_x ->> 'claims')::int <> 1 or (v_x ->> 'owed')::bigint <> 1800 or (v_x ->> 'forced_events')::int <> 1 then
    raise exception '0316 self-assert FAIL: the pre-image did not reproduce the bug: %', v_x;
  end if;

  -- FIXED: the same ship has arrived, with everything she carried, and the city pays nothing. Whether she settles at once, day by day, or after a storm's 36 hours.
  foreach v_def in array array['fixed', 'stepped', 'storm'] loop
    v_x := v_all -> v_def;
    if (v_x ->> 'bound')::boolean is not true or (v_x ->> 'dry_day')::int >= (v_x ->> 'cap')::int then
      raise exception '0316 self-assert FAIL: scene % is not a stacked dry day: %', v_def, v_x;
    end if;
    if (v_x ->> 'stores')::numeric <> 0 then
      raise exception '0316 self-assert FAIL: scene % did not run dry: %', v_def, v_x;
    end if;
    if v_x ->> 'voyage' <> 'ARRIVED' or v_x ->> 'fleet' <> 'DOCKED' or (v_x ->> 'at_dest')::boolean is not true then
      raise exception '0316 self-assert FAIL: a ship dry on the ETA did not arrive (%): %', v_def, v_x;
    end if;
    if (v_x ->> 'hold')::numeric <> 2000 or (v_x ->> 'hull_lost')::numeric <> 0 then
      raise exception '0316 self-assert FAIL: a ship that arrived lost her hold or her hull (%): %', v_def, v_x;
    end if;
    if (v_x ->> 'claims')::int <> 0 or (v_x ->> 'owed')::bigint <> 0 or (v_x ->> 'forced_events')::int <> 0 or (v_x ->> 'forced_days')::int <> 0 then
      raise exception '0316 self-assert FAIL: the insurance paid for a hold she still has (%): %', v_def, v_x;
    end if;
  end loop;
  v_def := null;
  if (v_all -> 'stepped') - 'sim' is distinct from (v_all -> 'fixed') - 'sim' then   -- sim: her speed is rolled per voyage; the outcome is what must match
    raise exception '0316 self-assert FAIL: a late settle lands differently from a day-by-day settle: % against %', v_all -> 'stepped', v_all -> 'fixed';
  end if;

  -- STILL A FORCED HOME: a ship dry on a day that ends before she arrives is exactly what 0279 and the owner's row 223 said. The hold, the claim, the hull.
  foreach v_def in array array['at_sea', 'at_sea_c'] loop
    v_x := v_all -> v_def;
    if v_x ->> 'voyage' <> 'ABORTED' or (v_x ->> 'forced_events')::int <> 1 or (v_x ->> 'forced_days')::int <> 1 or (v_x ->> 'hold')::numeric <> 0
       or (v_x ->> 'claims')::int <> 1 or (v_x ->> 'owed')::bigint <> 1800 or (v_x ->> 'hull_lost')::numeric <= 0 then
      raise exception '0316 self-assert FAIL: a real dry day at sea is no longer a forced home (%): %', v_def, v_x;
    end if;
  end loop;
  v_def := null;

  -- 0279'S OWN CASE, unmoved: no delay, dry on the true final day.
  v_x := v_all -> 'final';
  if v_x ->> 'voyage' <> 'ARRIVED' or (v_x ->> 'hold')::numeric <> 2000 or (v_x ->> 'forced_events')::int <> 0 or (v_x ->> 'stores')::numeric <> 0
     or (v_x ->> 'dry_day')::int <> (v_x ->> 'cap')::int then
    raise exception '0316 self-assert FAIL: a dry final day is no longer an arrival: %', v_x;
  end if;

  -- ── 5. NOTHING ELSE MOVED, nothing of the probe survives ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> v_settle) <> v_fn_before then
    raise exception '0316 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0316 self-assert FAIL: a world_config row moved';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa Enxuta %') then
    raise exception '0316 self-assert FAIL: the probe left rows behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0316 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0316 self-assert ok: INSURANCE PAYS ITS WAY. voyage.settle: a dry day is a forced home only when it ends before the ETA. The pre-image: dry on stacked day % of %, % owed on a hold she still had. The new body: she arrives, hold 2000, nothing owed, the same day by day and after 36 hours of storm. A real dry day at sea: forced home, 1800 owed. A dry final day: an arrival. One hunk reverses; no other function, no knob. % ms',
    (v_all -> 'bug_old' ->> 'dry_day'), (v_all -> 'bug_old' ->> 'cap'), (v_all -> 'bug_old' ->> 'owed'), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
