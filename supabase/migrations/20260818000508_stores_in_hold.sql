-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0508 - STORES IN THE HOLD  (dark: the switch is 0345's ship_stores_separate, TRUE today; this file does not move it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-2026-11-25.md, answer 2): "Food and water take cargo space."
--   docs/design/owner-spec-plan-2026-11-25.md section 0.5 and 0.6: `stores-in-hold`, one switch, one guard.
-- WHAT IS THERE ALREADY (0345): ship_stores_separate. True (prod since 2026-11-13): each ship carries her water and food in a stores
--   space of her own. False: the one pool again, free hold = hold - cargo - water - food (public.stores_in_hold, read by every reader
--   of her room: public.fleet_free_hold, public.fleet_load, world.trip_stow, world.board_legs). THE GUARD ASKED FOR IS THERE TOO:
--   public.fleet_free_hold is a sum of greatest(0, ...) a ship, so a fleet over her hold reads 0, never under. Proved below, not rebuilt.
-- WHAT WAS MISSING, MEASURED FIRST (docs/dev-log/2026-11-25-stores-in-hold.md; a Barca, full crew, a fixed job, the pool lit by hand):
--   the standing jobs were built while stores had their own space. A fixed job buys `ALL`: the whole hold. In the one pool that leaves
--   no room for the stores its SAIL takes on, and the SAIL is refused (E_ENDURANCE) with the cargo aboard: Lisbon - Las Palmas stopped
--   on its third run 409,665 coin down in unsold cargo, Lisbon - Cape Town on its first, at Luanda. And the run's quote
--   (public.fleet_run_quote, 0498) priced a hold she could not sail with.
-- WHAT THIS FILE ADDS (all answer as before while stores have their own space: nothing changes for a player today):
--   public.ship_hold_over(ship)       THE RULE of an over-full ship: the tuns by which her cargo, water and food pass her hold. 0: not over.
--   public.fleet_trip_stores(fleet, from, codes)
--                                     THE STORES HER WAY TO A SALE WILL TAKE ON, IN THE HOLD: {days, tons}. days: the longest leg of the
--                                     job's sails (public.fleet_job_sails, harbour by harbour), in the days cmd.do_sail tops her up to
--                                     (public.npc_leg_days) at her speed with a full hold (the slowest she sails it). tons: what
--                                     PROVISION DAYS <days> would take on now, hull by hull, by cmd.do_provision's own reading
--                                     (public.stores_topup). Stores in their own space: {days: null, tons: 0}. No estimate of its own.
--   public.stores_in_hold_ready()     what the light would meet, by the rule: ships, fleets and standing jobs over their hold, the tuns.
--   public.stores_in_hold_light()     THE ONE STEP that puts the stores back in the hold: ship_stores_separate false, and its news row.
--                                     Refuses when they are there already. Server only; the lead runs it on the owner's word.
--   public.fleet_job_plan             (2 hunks) a fixed run's and a land haul's plan, where her way's stores take hold room: a first line
--                                     `PROVISION DAYS <days>`, so the load that follows (BUY ALL, TAKE ALL) is what fits BESIDE them, hull
--                                     by hull, by the one authority of her room (public.fleet_free_hold). She eats on the way and each
--                                     harbour's top-up refills no more than she ate: the cargo never crowds the casks.
--   public.ship_stores_room           (1 hunk) the light's grace (below); never read while stores have their own space.
--   public.fleet_run_quote            (1 hunk) the units a run is quoted for are cut to what fits beside those stores, so the quote is of
--                                     the run she will sail (`cut` true: the plan's BUY names them).
-- ONE AUTHORITY FOR THE HOLD: nothing here measures room. Her room is public.fleet_free_hold's; a top-up's size is
--   public.stores_topup's; a leg's days are public.npc_leg_days'; the legs are public.fleet_job_sails'.
-- A FLEET OVER HER HOLD ON THE DAY OF THE LIGHT keeps her cargo and her stores, and loads nothing until she is under (her free hold
--   is 0). BY THE RULE, that is every ship whose cargo is within her water and food of her hold: a job's fleet between its BUY ALL and
--   its sale, a merchant or a crown cargo ship laden to the brim, and any hull with a full hold in port. public.stores_in_hold_ready()
--   counts them; it was not run on prod. SHE IS NEVER STRANDED: without more, a hull whose cargo fills her hold has no room for the next
--   leg's water, so a run laden before the light would be refused its SAIL (E_ENDURANCE) at its first harbour after it. The light gives
--   every hull whose cargo and stores space together pass her hold a GRACE (public.ships.hold_grace_until, 7 days): while it lasts her
--   top-ups go by her own space as the day before (public.ship_stores_room, the one reader of a top-up's room). Her free hold counts her
--   stores all the same: the grace carries stores, never cargo. It lapses by itself; nothing clears it.
-- NOT CHANGED: the switch; any knob; world.best_sales (a Best run's units are world.board_legs' `units_fit`, which takes the stores off
--   in the one pool since 0345); a hand trade; any command; voyage.settle; the speed (stores weigh in both worlds).
-- NOT DONE HERE: the client ("food and water inside the hold bar"); riot and storm (0511).
-- ROWS: none. One nullable column on public.ships (no default, no rewrite); no table, index, cron or knob. 0 new rows a minute. The
--   light writes that column once, on the laden hulls only.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit, a fixed run's plan reads its sails twice and one top-up a hull.
-- LOCKS: ALTER TABLE ships ADD COLUMN (nullable, instant); CREATE FUNCTION x4; CREATE OR REPLACE x3 by hunks. TIME: about a second. BUDGET: statement_timeout 90 s, lock_timeout 5 s;
--   fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, ship_stores_separate true (0345's switch: every reader is today's again). FULL: a migration
--   reversing the four hunks (OLD texts below verbatim) and dropping the four functions and the column.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no knob moved (the switch as it was found); three new STABLE reads and the light step, server only. THE PROBE
--   (rolled back by a raised sentinel; its own company's rows and one market row of Lisbon's and of the sale's harbour, pinned so
--   that her hold is what binds, never a price: no sign is asked of the market, no real company's job is planned, no tick is run):
--   STORES IN THEIR OWN SPACE: no stores are asked of the hold, the plan is BUY ALL, the quote is uncut. IN THE HOLD: the stores of
--   her way are what PROVISION takes on; the plan provisions first; the quote is cut to what fits beside them; BUY ALL and a SAIL
--   without the provision is refused (the fault measured); the job's own plan sails, every hull within her hold. OVER HER HOLD: her
--   free hold is 0, she can buy nothing; with empty casks there is no room for a sail's stores, and in the grace she sails. THE LIGHT STEP flips the switch once and refuses a second time.
-- VERSION: 0508 (the owner's-spec slices start here; built on 0498 `jobs-never-lose`, whose public.fleet_run_quote it hunks; 0499
--   `near-round` and 0500 `fit-to-sail` hunk other lines of public.fleet_job_plan and were applied under it in the test).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.ship_stores_room(uuid,numeric)', 'public.fleet_job_plan(uuid)', 'public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])'];
  c_new    constant text[] := array['public.ship_hold_over(uuid)', 'public.fleet_trip_stores(uuid,uuid,text[])',
                                    'public.stores_in_hold_ready()', 'public.stores_in_hold_light()'];
  c_uid    constant uuid := '00000000-0508-4000-8000-000000000001';
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
  v_good      text;
  v_gid       uuid;
  v_bulk      numeric;
  v_sell      text;
  v_dest      uuid;
  v_ts        jsonb;
  v_p         jsonb;
  v_rq        jsonb;
  v_r         jsonb;
  v_cap       jsonb;
  v_sail      jsonb;
  v_free      numeric;
  v_crew      numeric;
  v_o         int;
  v_code      text;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.fleet_trip_stores(uuid,uuid,text[])') is not null or to_regprocedure('public.stores_in_hold_light()') is not null then
    raise exception '0508 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])') is null or to_regprocedure('public.stores_in_hold(numeric)') is null
     or to_regprocedure('public.fleet_job_sails(uuid,uuid,text[])') is null or to_regprocedure('public.npc_leg_days(numeric,numeric)') is null
     or to_regprocedure('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or not exists (select 1 from public.world_config where key = 'ship_stores_separate') then
    raise exception '0508 refuses: 0498 (the run''s quote), 0494 (a job''s sails) or 0345 (the stores'' switch) is not in this world';
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

  -- ── 2. THE RULES ──
  alter table public.ships add column hold_grace_until timestamptz;
  comment on column public.ships.hold_grace_until is '0508: laden past her stores space when the stores went back in the hold (public.stores_in_hold_light): until then a top-up goes by her own stores space (public.ship_stores_room). Null: none.';

  execute $f$
create function public.ship_hold_over(p_ship uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0508: THE RULE OF AN OVER-FULL SHIP, with the stores in her hold: the tuns by which her cargo, her water and her food pass her hold
  -- (public.ship_hold_capacity, public.ship_cargo_tuns). 0: she is not over. The same answer whatever the switch says: it is what the
  -- light would meet. She keeps both, may sail, and loads nothing until she is under (public.fleet_free_hold reads 0 for her).
  select greatest(0, public.ship_cargo_tuns(s.id) + coalesce(s.water_t, 0) + coalesce(s.food_t, 0) - public.ship_hold_capacity(s.id))
    from public.ships s where s.id = p_ship
$body$
  $f$;

  execute $f$
create function public.fleet_trip_stores(p_fleet uuid, p_from uuid, p_codes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0508: THE STORES HER WAY TO A SALE WILL TAKE ON, IN THE HOLD, for the fleet lying at p_from and sailing p_codes in turn (the harbours
-- of the way OUT, her cargo aboard). Stores in their own space (public.ship_stores_separate): {days: null, tons: 0}: they ask nothing
-- of her hold. In the hold:
--   days   the longest leg of her sails (public.fleet_job_sails: the job's own legs, harbour by harbour) in the days cmd.do_sail tops
--          her up to (public.npc_leg_days), at her speed with a FULL hold (voyage.fleet_speed_of: the slowest she will sail it), rounded
--          up to a hundredth. She eats on the way; a later harbour's top-up refills no more than she ate.
--   tons   what PROVISION DAYS <days> takes on now, hull by hull, exactly as cmd.do_provision reads it (public.stores_topup with her
--          room beside her cargo and her full mark).
-- No way through, or no leg: {days: null, tons: 0} (the plan's own judge says it). Writes nothing.
declare
  v_s     jsonb;
  v_laden jsonb;
  v_speed numeric;
  v_nm    numeric;
  v_days  numeric := 0;
  v_tons  numeric;
  l       jsonb;
begin
  if public.ship_stores_separate() then
    return jsonb_build_object('days', null, 'tons', 0);
  end if;
  v_s := public.fleet_job_sails(p_fleet, p_from, p_codes);
  if v_s ? 'missing' or jsonb_array_length(coalesce(v_s->'lines', '[]'::jsonb)) = 0 then
    return jsonb_build_object('days', null, 'tons', 0);
  end if;
  -- her hulls with a full hold: the cargo that fits beside the casks she carries now
  select jsonb_agg(h.e || jsonb_build_object('cargo', greatest(coalesce((h.e->>'cargo')::numeric, 0),
           (h.e->>'cap')::numeric - coalesce((h.e->>'water')::numeric, 0) - coalesce((h.e->>'food')::numeric, 0))))
    into v_laden from jsonb_array_elements(world.trip_hulls(p_fleet)) h(e);
  v_speed := greatest(voyage.fleet_speed_of(voyage.fleet_speed_parts(p_fleet), null, v_laden), 0.1);
  for l in select e from jsonb_array_elements(v_s->'lines') e loop
    select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(l->'path')) s;
    v_days := greatest(v_days, coalesce(public.npc_leg_days(v_nm, v_speed), 0));
  end loop;
  v_days := trim_scale(ceil(v_days * 100) / 100);
  if v_days <= 0 then
    return jsonb_build_object('days', null, 'tons', 0);
  end if;
  select coalesce(sum(t.water_t + t.food_t), 0) into v_tons
    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as hold, public.ship_cargo_tuns(s.id) as cargo_t offset 0) c
   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_stores_room(s.id, c.hold - c.cargo_t), v_days,
                                          public.ship_stores_room(s.id, c.hold * s.store_ratio)) t
   where s.fleet_id = p_fleet;
  return jsonb_build_object('days', v_days, 'tons', v_tons);
end
$body$
  $f$;

  execute $f$
create function public.stores_in_hold_ready()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0508: WHAT THE LIGHT WOULD MEET, BY THE RULE (public.ship_hold_over): the ships whose cargo, water and food pass their hold, the
  -- fleets they sail in, the standing jobs of those fleets, and the tuns over. `in_hold`: the stores are in the hold already. Reads
  -- every ship once: the lead's read before the light, never a player's. Writes nothing.
  select jsonb_build_object(
           'in_hold', not public.ship_stores_separate(),
           'ships', count(*),
           'ships_over', count(*) filter (where o.over > 0),
           'company_ships_over', count(*) filter (where o.over > 0 and not pl.is_npc),
           'fleets_over', count(distinct s.fleet_id) filter (where o.over > 0),
           'company_fleets_over', count(distinct s.fleet_id) filter (where o.over > 0 and not pl.is_npc),
           'jobs_over', (select count(*) from public.fleet_jobs j
                          where exists (select 1 from public.ships x where x.fleet_id = j.fleet_id and public.ship_hold_over(x.id) > 0)),
           'tuns_over', coalesce(round(sum(o.over) filter (where o.over > 0), 1), 0),
           'graced', count(*) filter (where s.hold_grace_until > now()))
    from public.ships s
    left join public.fleets f on f.id = s.fleet_id
    left join public.players pl on pl.id = f.player_id
   cross join lateral (select public.ship_hold_over(s.id) as over offset 0) o
$body$
  $f$;

  execute $f$
create function public.stores_in_hold_light()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0508: THE ONE STEP THAT PUTS THE STORES BACK IN THE HOLD: ship_stores_separate false (0345's switch: every reader of her room takes
-- her water and food off it at once) and the news row of this step. It refuses, changing nothing, when they are there already. A
-- fleet over her hold keeps her cargo and her stores and loads nothing until she is under; every hull whose cargo and stores space
-- together pass her hold has 7 days of grace for her top-ups (public.ships.hold_grace_until, public.ship_stores_room). Server only: the lead
-- runs it on the owner's word, after reading public.stores_in_hold_ready(). Its rollback is the switch.
declare
  v_n int;
begin
  if not public.ship_stores_separate() then
    raise exception 'stores_in_hold_light refuses: the stores are in the hold already' using errcode = 'P0001';
  end if;
  update public.ships s set hold_grace_until = now() + interval '7 days'
   where public.ship_cargo_tuns(s.id) > 0
     and public.ship_cargo_tuns(s.id) + public.ship_stores_space(s.id) > public.ship_hold_capacity(s.id);
  get diagnostics v_n = row_count;
  update public.world_config set value = 'false'::jsonb, updated_at = now() where key = 'ship_stores_separate';
  perform public.news_update('0508', 'Food and water take hold space', 'Food and water take hold space');
  return jsonb_build_object('in_hold', not public.ship_stores_separate(), 'graced', v_n, 'lit_at', now());
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0508 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0508 values
  ('public.fleet_job_plan(uuid)', 1,
$h$      v_lines := jsonb_build_array(jsonb_build_object('text', coalesce(v_end->>'buy', format('BUY %s ALL', v_g)))) || coalesce(v_s->'lines', '[]'::jsonb)
$h$,
$h$      -- 0508 (stores in the hold): the stores of her way out are taken on FIRST (public.fleet_trip_stores), so the load is what fits beside them
      v_lines := (select case when (t.j->>'tons')::numeric > 0
                              then jsonb_build_array(jsonb_build_object('text', format('PROVISION DAYS %s', t.j->>'days'))) else '[]'::jsonb end
                    from (select public.fleet_trip_stores(f.id, f.port_id, v_st || v_sell) as j) t)
                 || jsonb_build_array(jsonb_build_object('text', coalesce(v_end->>'buy', format('BUY %s ALL', v_g)))) || coalesce(v_s->'lines', '[]'::jsonb)
$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$      v_lines := jsonb_build_array(jsonb_build_object('text', format('TAKE %s ALL', v_g))) || coalesce(v_s->'lines', '[]'::jsonb)
$h$,
$h$      -- 0508 (stores in the hold): a haul's stores first too, so what she takes out of the shed fits beside them
      v_lines := (select case when (t.j->>'tons')::numeric > 0
                              then jsonb_build_array(jsonb_build_object('text', format('PROVISION DAYS %s', t.j->>'days'))) else '[]'::jsonb end
                    from (select public.fleet_trip_stores(f.id, f.port_id, array[v_to]) as j) t)
                 || jsonb_build_array(jsonb_build_object('text', format('TAKE %s ALL', v_g))) || coalesce(v_s->'lines', '[]'::jsonb)
$h$),
  ('public.ship_stores_room(uuid,numeric)', 1,
$h$  select case when not public.ship_stores_separate() then p_dark
$h$,
$h$  -- 0508: in the hold, p_dark too, but for a hull in the light's grace (ships.hold_grace_until): her own space, as the day before.
  select case when not public.ship_stores_separate() and coalesce(s.hold_grace_until, '-infinity'::timestamptz) <= now() then p_dark
$h$),
  ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 1,
$h$  v_n := least(v_u0, floor(coalesce(v_left, v_u0)));
$h$,
$h$  -- 0508 (stores in the hold): and to what fits beside the stores her way to the sale takes on (public.fleet_trip_stores: the legs up
  -- to p_sell; her room is public.fleet_free_hold's). Stores in their own space: v_u0, as before.
  v_n := least(v_u0, floor(coalesce(v_left, v_u0)),
               (select case when (t.j->>'tons')::numeric > 0
                            then floor(greatest(0, public.fleet_free_hold(p_fleet) - (t.j->>'tons')::numeric)
                                       / (select g.bulk from public.goods g where g.id = v_gid))
                            else v_u0 end
                  from (select public.fleet_trip_stores(p_fleet, p_from, p_codes[1:coalesce(array_position(p_codes, p_sell), 0)]) as j) t));
$h$);

  for v_h in select h.fn from hunks_0508 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0508 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0508 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0508 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0508 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0508 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0508 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0508 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when p.proname = 'stores_in_hold_light' then 'v' else 's' end) <> 4
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0508 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0508 self-assert FAIL: a knob moved (this file moves none: the stores'' switch stays as it was found)';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (its own company's rows, and the two market rows that make her hold bind) ──
  begin
    v_me := public.new_house(c_uid, 'Casa do Porao 0508', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.players p set ducats = 5000000 where p.id = v_me;
    -- a full crew and empty casks: the most her way's stores can ask of her hold
    update public.ships s set crew = c.crew_max, water_t = 0, food_t = 0 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
    select sum(s.crew) into v_crew from public.ships s where s.fleet_id = v_fl;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
    -- the plan is BUY ALL whatever the prices (0498's wait is not this file's; its quote is read directly below)
    update public.world_config set value = 'false'::jsonb where key = 'jobs_wait_enabled';
    perform cmd.assume_identity(c_uid);
    -- THE PAIR, from static rows (never from a price): a good Lisbon offers and her nearest remembered harbour that takes it
    select g.code, g.id, g.bulk, k.code, k.to_port into v_good, v_gid, v_bulk, v_sell, v_dest
      from public.npc_known_legs(v_lis) k
      join public.port_goods ps on ps.port_id = k.to_port
      join public.goods g on g.id = ps.good_id
      join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
     where public.port_offers(v_lis, g.id)
       and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
       and not public.culture_refuses(pd.culture, g.culture_mask)
       and public.fleet_free_hold(v_fl) >= 20 * g.bulk
     order by k.nm, g.code limit 1;
    if v_good is null then
      raise exception '0508 self-assert FAIL: the probe found no good Lisbon offers that a remembered harbour takes (static rows, not the market)';
    end if;
    -- HER HOLD IS WHAT BINDS: Lisbon's quay full and cheap, both marks high (the day's allowance is the mark's share), so neither the
    -- stock, the allowance nor her purse cuts the load before her hold does
    update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0,
                                    glut = 0.5, glut_at = now(), haul = 1
     where pg.port_id = v_lis and pg.good_id = v_gid;
    update public.port_goods pg set stock_target = 1000000 where pg.port_id = v_dest and pg.good_id = v_gid;
    v_free := public.fleet_free_hold(v_fl);
    v_cap := public.fleet_buy_capacity(v_fl, v_gid);
    if v_cap->>'bound_by' is distinct from 'hold' or (v_cap->>'max_qty')::numeric <> floor(v_free / v_bulk) then
      raise exception '0508 self-assert FAIL: the probe did not make her hold the bound (%, free % t, bulk %): the fault is the probe''s, not the market''s', v_cap, v_free, v_bulk;
    end if;
    perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));

    -- (a) STORES IN THEIR OWN SPACE (the world as it is): nothing is asked of her hold; the plan and the quote are what they were
    update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
    v_ts := public.fleet_trip_stores(v_fl, v_lis, array[v_sell]);
    v_p := public.fleet_job_plan(v_fl);
    v_rq := public.fleet_run_quote(v_me, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    if (v_ts->>'tons')::numeric <> 0 or v_ts->'days' <> 'null'::jsonb
       or v_p #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_good)
       or exists (select 1 from jsonb_array_elements(v_p->'lines') l where l->>'text' like 'PROVISION%')
       or (v_rq->>'units')::numeric is distinct from (v_cap->>'max_qty')::numeric or (v_rq->>'cut')::boolean is not false then
      raise exception '0508 self-assert FAIL: with the stores in their own space the plan or the quote moved: stores % / plan % / quote %', v_ts, left(v_p::text, 300), v_rq;
    end if;
    v_note := format('%s from LIS to %s, crew %s, free hold %s t; own space: BUY ALL, %s units quoted', v_good, v_sell, v_crew, v_free, v_rq->>'units');

    -- (b) IN THE HOLD: her way's stores are what PROVISION takes on; the plan takes them on first; the quote is cut to what fits beside
    update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
    v_ts := public.fleet_trip_stores(v_fl, v_lis, array[v_sell]);
    v_p := public.fleet_job_plan(v_fl);
    v_rq := public.fleet_run_quote(v_me, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    if coalesce((v_ts->>'days')::numeric, 0) <= 0 or coalesce((v_ts->>'tons')::numeric, 0) <= 0
       -- empty casks, room to spare: each store to those days for every hand (public.stores_topup rounds a hull's two to the thousandth)
       or abs((v_ts->>'tons')::numeric - v_crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * (v_ts->>'days')::numeric) > 0.01 then
      raise exception '0508 self-assert FAIL: in the hold, her way''s stores are not her crew''s days: % (crew %)', v_ts, v_crew;
    end if;
    if v_p #>> '{lines,0,text}' is distinct from format('PROVISION DAYS %s', v_ts->>'days')
       or v_p #>> '{lines,1,text}' is distinct from format('BUY %s ALL', v_good)
       or v_p #>> '{lines,-1,text}' is distinct from format('SELL %s ALL', v_good) then
      raise exception '0508 self-assert FAIL: in the hold, the plan does not take her stores on before her load: %', left(v_p::text, 400);
    end if;
    if (v_rq->>'units')::numeric is distinct from floor((v_free - (v_ts->>'tons')::numeric) / v_bulk)
       or (v_rq->>'units')::numeric >= (v_cap->>'max_qty')::numeric or (v_rq->>'cut')::boolean is not true then
      raise exception '0508 self-assert FAIL: in the hold, the quote is not cut to what fits beside her stores: % (free % t, stores %, bulk %)', v_rq, v_free, v_ts, v_bulk;
    end if;
    v_sail := (select l from jsonb_array_elements(v_p->'lines') l where l->>'text' like 'SAIL %' limit 1);
    -- THE FAULT MEASURED: BUY ALL and the sail, without the provision: her hold is full and the sail's stores have no room
    begin
      v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', format('BUY %s ALL', v_good)), v_sail), null);
      select o.error_code into v_code from public.orders o where o.fleet_id = v_fl and o.verb = 'SAIL' and o.status = 'failed';
      if v_code is null or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
        raise exception '0508 self-assert FAIL: BUY ALL then SAIL with the stores in the hold and no provision was not refused: %', left(v_r::text, 400);
      end if;
      raise exception using errcode = 'ZY508', message = 'FAULT_ROLLBACK_0508';
    exception when sqlstate 'ZY508' then null;
    end;
    -- OVER HER HOLD (a fleet loaded while her stores had their own space, on the day of the light): her free hold is 0, never
    -- under; she can buy nothing; she sails
    begin
      update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
      v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', format('BUY %s ALL', v_good))), null);
      update public.ships s set water_t = v_crew * public.wc_num('water_per_crew_day') * 9, food_t = v_crew * public.wc_num('food_per_crew_day') * 9 where s.fleet_id = v_fl;
      update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
      if (select min(public.ship_hold_over(s.id)) from public.ships s where s.fleet_id = v_fl) <= 0
         or public.fleet_free_hold(v_fl) <> 0 or (public.fleet_buy_capacity(v_fl, v_gid)->>'max_qty')::numeric <> 0
         or (cmd.preview(v_fl, format('BUY %s 1', v_good))->>'ok')::boolean is not false then
        raise exception '0508 self-assert FAIL: over her hold, her free hold is not 0 or she can still load: over %, free %, capacity %, preview %',
          (select min(public.ship_hold_over(s.id)) from public.ships s where s.fleet_id = v_fl), public.fleet_free_hold(v_fl),
          public.fleet_buy_capacity(v_fl, v_gid), cmd.preview(v_fl, format('BUY %s 1', v_good));
      end if;
      -- her casks eaten empty on the way, as at her first harbour after the light: no room for a sail's stores; then the light's grace
      update public.ships s set water_t = 0, food_t = 0 where s.fleet_id = v_fl;
      if (select n.fits from public.supply_need(v_fl, 100) n) is not false then
        raise exception '0508 self-assert FAIL: a full hold and empty casks found room for a sail''s stores without the grace';
      end if;
      update public.ships s set hold_grace_until = now() + interval '7 days' where s.fleet_id = v_fl;
      v_r := cmd.issue_lines(v_fl, jsonb_build_array(v_sail), null);
      if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING'
         or exists (select 1 from public.orders o where o.fleet_id = v_fl and o.status = 'failed')
         or public.fleet_free_hold(v_fl) <> 0 then
        raise exception '0508 self-assert FAIL: over her hold, in the light''s grace, she did not sail: %', left(v_r::text, 400);
      end if;
      raise exception using errcode = 'ZY508', message = 'OVER_ROLLBACK_0508';
    exception when sqlstate 'ZY508' then null;
    end;
    -- THE JOB'S OWN PLAN, opened as the tick opens it (public.fleet_job_open, for her job alone): she sails, every hull within her hold
    v_o := public.fleet_job_open(v_fl, v_p);
    if v_o <> 1 or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING'
       or exists (select 1 from public.orders o where o.fleet_id = v_fl and o.status = 'failed')
       or exists (select 1 from public.ships s where s.fleet_id = v_fl and public.ship_hold_over(s.id) > 0.01)
       or (select sum(s.water_t + s.food_t) from public.ships s where s.fleet_id = v_fl) <= 0
       or coalesce(public.fleet_cargo_qty(v_fl, v_good), 0) < 1 then
      raise exception '0508 self-assert FAIL: in the hold, the job''s plan did not sail with her stores and her load within her hold (open %): %',
        v_o, (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fl);
    end if;
    v_note := v_note || format('; in the hold: %s days and %s t of stores first, %s units quoted, she sailed with %s aboard; BUY ALL without them: the sail refused (%s); over her hold: free hold 0, nothing bought, no room for a sail''s stores, and in the grace she sailed',
                               v_ts->>'days', v_ts->>'tons', v_rq->>'units', trim_scale(public.fleet_cargo_qty(v_fl, v_good)), v_code);

    -- (c) THE LIGHT STEP: once, and never twice
    update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
    v_r := public.stores_in_hold_light();   -- its grace on real hulls is undone with this block
    if public.ship_stores_separate() or (v_r->>'in_hold')::boolean is not true then
      raise exception '0508 self-assert FAIL: the light step did not put the stores in the hold: %', v_r;
    end if;
    begin
      perform public.stores_in_hold_light();
      raise exception '0508 self-assert FAIL: the light step ran twice';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'stores_in_hold_light refuses:%' then raise; end if;
    end;
    v_note := v_note || '; the light step flips the switch once and refuses a second time';
    raise exception using errcode = 'ZX508', message = 'PROBE_ROLLBACK_0508';
  exception when sqlstate 'ZX508' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0508 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa do Porao 0508' or p.auth_uid = c_uid) then
    raise exception '0508 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0508 self-assert FAIL: a knob is not as it was found after the probe';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0508 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0508 self-assert ok: STORES IN THE HOLD (dark: the stores'' switch not moved). Four hunks once and reversing; four new functions server only; no other function moved; no knob moved. Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
