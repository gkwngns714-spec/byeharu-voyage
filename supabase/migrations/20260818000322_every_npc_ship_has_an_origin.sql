-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0322 — EVERY NPC SHIP HAS AN ORIGIN: a ship that loses everything is back at her home city, and that city pays to set her afloat. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 287, slice W6 of docs/WORLD_POWERS.md (sections 3.3, 3.4): *"each npc ships should have city of origin set. Once they are attacked and lost, it may lose some cargo/gold and HP.
-- If everything is destroyed(HP), they should respawn at their origin city, funded by the city to start anew"*.
--
-- WHAT THIS FILE ADDS, ALL DARK (`npc_refits_enabled` false):
--   public.fleet_origin     THE one reader of a ship's home: cargo_ships first, then npc_houses. Null for a human. Stands beside public.fleet_kind. No new column.
--   public.npc_wrecked      THE one test: the switch on, she has an origin, she has hulls, and no hull has any left. All three callers below ask this.
--   voyage.npc_wreck        THE wreck: the hold is lost, the insurance pays, funds aboard go back to the origin, the queue is released, she lies UNABLE_TO_SAIL at the origin, the voyage ends, RESPAWNED.
--   public.npc_refit_cost   npc_refit_share x the build cost of her hulls.
--   public.yards_from       THE harbours with a yard reachable from a port. public.tow_for's own query, lifted, and public.refit_yard reads it too.
--   public.refit_yard       Who earns the refit: the nearest yard that is not the origin, a yard of the same country first. Paying yourself moves nothing.
--   public.npc_refit_step   One wreck's hour. A city with the cost above its reserve pays, REFIT, two moved rows; hull whole, crew from the quay, ready after npc_refit_minutes. Else REFIT_WAITING, once a real day.
--   public.tick_npc_refits  pg_cron byeharu-voyage:npc-refits, hourly at :18, a transaction a wreck. Dark, it reads one knob.
--   public.npc_refit_waits  One row a waiting wreck: when she was last worded. The wreck itself is read from the fleet and her hulls, so nothing here can disagree with them.
--   public.ransom_take      A ransom's share of what is aboard. KNOB AND READER ONLY: no gold moves until W11 and W17 give it a payee.
--   voyage.lose_hold        forced_home's own loop, lifted. public.fleet_mend: cargo_ship_step's own line, twice, lifted. One writer each.
--
-- THE HUNKS, each occurs once and reverses to its pre-image:
--   voyage.settle (1): after a day that can take a hull (STORM, PIRATES, SHOAL_WATER) she may be a wreck, and the voyage ends there. Dark: one knob read on those days only.
--   public.npc_tend_route (1): the tow arm leaves a wreck to the refit.
--   public.cargo_ship_step (2): a wreck waits for the refit instead of patching herself; the two mending lines read public.fleet_mend.
--   voyage.forced_home (2): the hold, through voyage.lose_hold. public.tow_for (1): the yard, through public.yards_from.
--
-- DARK IS BYTE-IDENTICAL: public.npc_wrecked answers false after one read of the switch, before any row is read. voyage.lose_hold, public.yards_from and public.fleet_mend are moved code: same statements, same order.
--
-- A WRECK IS EVERY HULL AT 0 ("everything is destroyed"). Today a merchant whose flagship is at 0 and who has a hull left docks UNABLE_TO_SAIL and is towed: that stands.
-- WRECKS NOT MADE BY A SETTLED DAY (a hull at 0 from before the switch: prod holds 3 merchants so today, 2 of them DOCKED): the job finds them by the same test and brings them home first. One path.
-- ROLLBACK OF THE SWITCH MID-WAIT: nothing is stranded. npc_wrecked is false, so the tow arm tows her and cargo_ship_step patches her, as today. public.npc_refit_waits is only a word's date.
--
-- crown_aid CANNOT LOAD A WRECK: public.cargo_ships_load takes only a ship DOCKED with no open load. A wreck is UNABLE_TO_SAIL. Mended, she is DOCKED, ready_at holds her and cargo_ship_step closes her lap at home.
-- A wreck's funds RETURN to the origin. tg_convoy_cargo_closes wants a return at the load's own port, which today is the capital, her home; W7 must keep origin = the port she loaded at.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - Switch `npc_refits_enabled`: the design names none; every slice is dark.
--   - `ransom_share` has no payee until W11 / W17: knob and reader only.
--   - No crew for a cargo ship until W8: she sails crewless. A merchant's crew stay aboard a wreck; the refit fills what she is short from the quay, above npc_crew_pool_floor, free; what the quay
--     cannot give she hires herself. public.crew_hire_cost is the one split.
--   - The refit takes the build cost of every hull she has, not one class: 44 merchants have 2 hulls, 7 have 3.
--   - A city pays when city_surplus >= the cost, so it lands on its reserve at the lowest. It waits, and is asked hourly, under that.
--   - `npc_refits_per_run` 50 (added): docs/OPS_HEALTH.md section 3, a job does a bounded amount a run. Only a refit paid counts, so waiting wrecks cannot starve the rest.
--   - The hold is lost in a wreck found in port too. One rule.
--   - Her insurance pays as today, cause 'WRECK'.
--
-- SELF-ASSERT: the catalog only: hunks once and reversing; ACL, volatility and config unmoved; no other function, no other knob, no other job, no row. THIS FILE RUNS NO GAME STEP, in every
-- environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 30, scripts/db/proofs/30_every_npc_ship.sql. Mutation controls: scripts/ops/harness/npc-origin/proof-0322.mjs (local).
--
-- CRON: a new hourly job is a load change (docs/OPS_HEALTH.md section 2). Dark, one row read. :18 is free: no other job fires then.
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `npc_refits_enabled` false is the switch. To remove: swap this file's v_old and v_new, unschedule the job, then drop what it created. REFIT rows stay.
-- VERSION: 0322 - prod head 0320 (2026-11-06). 0321 (#516) deploys first and hunks public.tow_for on another line (read and applied in that order, 2026-11-06). 0323 (W10) is built beside this.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_words_before text;
  v_meta_before  text;
  v_cron_before  text;
  v_cron_after   text;
  c_keys constant text[] := array['npc_refits_enabled', 'npc_refit_share', 'npc_refit_minutes', 'npc_refits_per_run', 'ransom_share'];
  c_new_fns constant text[] := array[
    'public.npc_refits_on()', 'public.fleet_origin(uuid)', 'public.npc_wrecked(uuid)', 'public.npc_refit_cost(uuid)', 'public.yards_from(uuid)', 'public.refit_yard(uuid)',
    'public.ransom_take(bigint)', 'public.fleet_mend(uuid)', 'voyage.lose_hold(uuid)', 'voyage.npc_wreck(uuid,uuid,integer)', 'public.npc_refit_step(uuid,timestamp with time zone)',
    'public.tick_npc_refits(boolean)'];
  c_hunked constant text[] := array[
    'voyage.settle(uuid,timestamp with time zone)', 'public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 'public.cargo_ship_step(uuid,timestamp with time zone)',
    'voyage.forced_home(uuid,integer,uuid)', 'public.tow_for(uuid,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.npc_refit_waits') is not null or to_regprocedure('public.fleet_origin(uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.stats_flow_words w where w.kind = 'REFIT') then
    raise exception '0322 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.fleet_kind(uuid)') is null or to_regprocedure('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)') is null then
    raise exception '0322 refuses: 0308 / 0309 (cargo ships and their book) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before
    from public.stats_flow_words w;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE TABLE ──
  create table public.npc_refit_waits (
    fleet_id uuid        primary key references public.fleets(id) on delete cascade,
    told_at  timestamptz not null
  );
  comment on table public.npc_refit_waits is
    '0322 (docs/WORLD_POWERS.md section 3.4): when a wreck whose city cannot pay was last worded (REFIT_WAITING, once a real day). A wreck is read from her fleet and hulls, never from here; the row goes when she is paid for. One writer: public.npc_refit_step. Server-only.';
  alter table public.npc_refit_waits enable row level security;
  revoke all on table public.npc_refit_waits from public, anon, authenticated;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('npc_refits_enabled', 'false'::jsonb, '0322: THE switch of the wreck rule. False: a wreck is what it was (towed, or patched where she lies), and the hourly job reads this and stops.'),
    ('npc_refit_share', '0.25'::jsonb, '0322: a refit costs this share of the build cost of her hulls (public.npc_refit_cost).'),
    ('npc_refit_minutes', '30'::jsonb, '0322: minutes from a paid refit until she may sail (fleets.ready_at).'),
    ('npc_refits_per_run', '50'::jsonb, '0322: refits paid in one hourly run at most. The rest wait for the next run.'),
    ('ransom_share', '0.08'::jsonb, '0322: a ransom''s share of what is aboard (public.ransom_take). Read by nothing that moves gold until W11 and W17 give it a payee.');

  -- ── 3. THE MONEY KIND ──
  insert into public.stats_flow_words (kind, side, word, ord) values ('REFIT', 'moved', 'Refits', 49);

  -- ── 4. THE READERS ──
  execute $f$
create function public.npc_refits_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: THE one reader of npc_refits_enabled.
  select public.wc('npc_refits_enabled') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.fleet_origin(p_fleet uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: THE answer to where an NPC ship is from (docs/WORLD_POWERS.md section 3.3): a cargo ship's home, else her merchant house's. Null for a human's fleet. Navies and pirates join here, W12 and W17.
  select coalesce((select c.home_port_id from public.cargo_ships c where c.fleet_id = p_fleet),
                  (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet))
$$
  $f$;

  execute $f$
create function public.npc_wrecked(p_fleet uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: THE test: the rule is lit, she has an origin, she has hulls, and every one is at 0. CASE, so dark reads the switch and no row. A human's fleet and an empty fleet are never a wreck.
  select case when public.npc_refits_on()
              then public.fleet_origin(p_fleet) is not null
                   and coalesce((select bool_and(s.durability <= 0) from public.ships s where s.fleet_id = p_fleet), false)
              else false end
$$
  $f$;

  execute $f$
create function public.npc_refit_cost(p_fleet uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: what a refit costs her city: npc_refit_share x the build cost of every hull she has.
  select round(public.wc_num('npc_refit_share') * coalesce(sum(c.build_cost), 0))::bigint
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet
$$
  $f$;

  execute $f$
create function public.yards_from(p_port uuid)
returns table (port_id uuid, code text, name text, nm numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: THE open harbours with a yard reachable from a port, by the sailed distance (voyage.reach_from, the figure every quote reads), the port itself at 0 miles. 0152's query, lifted from
  -- public.tow_for, which reads the nearest. public.refit_yard reads it too.
  select y.id, y.code, y.name, case when y.id = p_port then 0 else r.nm end
    from public.ports y
    left join voyage.reach_from(p_port) r on r.port_id = y.id
   where y.kind = 'HARBOUR' and not y.is_ice_closed and public.port_has_shipyard(y.id)
     and (y.id = p_port or r.nm is not null)
$$
  $f$;

  execute $f$
create function public.refit_yard(p_port uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: who earns a refit paid by this city: the nearest yard that is not the city itself, a yard of the same country first (paying yourself moves nothing). Null: no yard can be reached.
  select y.port_id
    from public.yards_from(p_port) y
   where y.port_id <> p_port
   order by coalesce(public.port_nation(y.port_id) = public.port_nation(p_port), false) desc, y.nm, y.code
   limit 1
$$
  $f$;

  execute $f$
create function public.ransom_take(p_aboard bigint)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0322: a ransom's share of what is aboard, whole ducats, rounded down (docs/WORLD_POWERS.md section 3.4). Nothing moves gold by this yet: W11 and W17 give it a payee.
  select floor(greatest(coalesce(p_aboard, 0), 0) * public.wc_num('ransom_share'))::bigint
$$
  $f$;

  -- ── 5. THE WRITERS ──
  execute $f$
create function public.fleet_mend(p_fleet uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  -- 0322: every hull of a fleet back to her own rolled best. cargo_ship_step's own line, lifted. Moves no money: the caller has said who paid.
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet
$$
  $f$;

  execute $f$
create function voyage.lose_hold(p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0322: THE HOLD IS LOST: public.fleet_unload, the one unload, every good in full. Answers {good: units}, the word a day's payload calls `cargo_lost`. voyage.forced_home's loop, lifted. No gold: goods have no owner once lost.
declare
  e       record;
  v_lost  jsonb := '{}'::jsonb;
  v_qty   numeric;
begin
  for e in select distinct k.key as code
             from public.ships s0 cross join lateral jsonb_each(s0.cargo) k
            where s0.fleet_id = p_fleet and (k.value)::text::numeric > 0
            order by 1 loop
    v_qty := public.fleet_cargo_qty(p_fleet, e.code);
    if v_qty > 0 then
      v_lost := v_lost || jsonb_build_object(e.code, public.fleet_unload(p_fleet, e.code, v_qty));
    end if;
  end loop;
  return v_lost;
end
$$
  $f$;

  execute $f$
create function voyage.npc_wreck(p_fleet uuid, p_voyage uuid default null, p_day integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0322: THE wreck (docs/WORLD_POWERS.md section 3.4). Called by voyage.settle on the day she lost her last hull, and by public.npc_refit_step for one found in port (no voyage, no claim).
-- This is a respawn, not a voyage: she is at her origin at once, UNABLE_TO_SAIL, drawn nowhere until she sails. Answers what the event says.
declare
  f        public.fleets%rowtype;
  v_home   uuid;
  v_code   text;
  v_name   text;
  v_lost   jsonb;
  v_ins    jsonb;
  v_load   bigint;
  v_left   bigint;
  v_out    jsonb;
begin
  select * into f from public.fleets where id = p_fleet for update;
  v_home := public.fleet_origin(p_fleet);
  if v_home is null then
    raise exception 'E_NO_ORIGIN: fleet % has no city of origin', p_fleet using errcode = 'P0001';
  end if;
  select p.code, p.name into v_code, v_name from public.ports p where p.id = v_home;

  -- (a) The hold, and the insurance if she had it.
  v_lost := voyage.lose_hold(p_fleet);
  if p_voyage is not null then
    v_ins := public.insurance_claim(p_voyage, p_day, v_lost, 'WRECK');
  end if;

  -- (b) Funds aboard are city money: all of it goes home (public.convoy_book, the one writer). The purse rises by what set_aside falls by.
  select a.load_id, a.aboard into v_load, v_left from public.cargo_ship_aboard(p_fleet) a;
  if coalesce(v_left, 0) > 0 then
    perform public.convoy_book('RETURNED', p_fleet, f.player_id, v_home, v_left, v_load);
  end if;

  -- (c) Orders written for the old voyage must not run at home. She lies at her origin. Nothing can run: she is UNABLE_TO_SAIL until she is paid for.
  perform cmd.clear_for(f.player_id, p_fleet, false);
  update public.fleets
     set status = 'UNABLE_TO_SAIL', port_id = v_home, lat = null, lon = null, ready_at = null, version = version + 1
   where id = p_fleet;

  -- (d) The voyage ends. ABORTED is the existing "ended early" status; the reason is the event.
  if p_voyage is not null then
    update public.voyages set status = 'ABORTED' where id = p_voyage;
  end if;

  v_out := jsonb_build_object('fleet', f.name, 'voyage_id', p_voyage, 'day', p_day, 'port', v_code, 'port_name', v_name,
                              'cargo_lost', v_lost, 'insurance', v_ins, 'funds_returned', coalesce(v_left, 0));
  perform public.emit_event(f.player_id, 'RESPAWNED', v_out);
  return v_out;
end
$$
  $f$;

  execute $f$
create function public.npc_refit_step(p_fleet uuid, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0322: one wreck's hour. Answers BUSY, NOT_A_WRECK, PURSES_DARK, WAITING or PAID. No hull is restored unpaid, and a paid wreck is no longer a wreck, so she cannot be paid for twice.
-- The purse is judged under the harbour's lock (public.treasury_lock) because public.treasury_post takes it only for an outflow to a house.
declare
  f        public.fleets%rowtype;
  v_home   uuid;
  v_cost   bigint;
  v_yard   uuid;
  v_why    text;
  v_short  int;
  v_hands  int;
  v_give   int;
  v_ev     uuid;
  s        record;
begin
  select * into f from public.fleets x where x.id = p_fleet for update skip locked;
  if f.id is null then
    return 'BUSY';
  end if;
  if f.status not in ('DOCKED', 'ANCHORED', 'ADRIFT', 'UNABLE_TO_SAIL') or not public.npc_wrecked(p_fleet) then
    return 'NOT_A_WRECK';
  end if;
  if not public.city_treasury_on() then
    return 'PURSES_DARK';   -- no purse can pay, so no hull is restored
  end if;
  v_home := public.fleet_origin(p_fleet);
  if f.status <> 'UNABLE_TO_SAIL' or f.port_id is distinct from v_home then
    perform voyage.npc_wreck(p_fleet);   -- a wreck no settled day brought home
  end if;

  v_cost := public.npc_refit_cost(p_fleet);
  perform public.treasury_lock(v_home);
  if public.city_surplus(v_home) < v_cost then
    v_why := 'broke';
  else
    v_yard := public.refit_yard(v_home);
    if v_yard is null then
      v_why := 'no_yard';
    end if;
  end if;
  if v_why is not null then
    insert into public.npc_refit_waits as w (fleet_id, told_at) values (p_fleet, p_now)
    on conflict (fleet_id) do update set told_at = excluded.told_at where w.told_at <= p_now - interval '1 day';
    if found then
      perform public.emit_event(f.player_id, 'REFIT_WAITING', jsonb_build_object(
        'fleet', f.name, 'port', (select p.code from public.ports p where p.id = v_home), 'cost', v_cost, 'why', v_why));
    end if;
    return 'WAITING';
  end if;

  v_ev := public.emit_event(f.player_id, 'REFITTED', jsonb_build_object(
    'fleet', f.name, 'port', (select p.code from public.ports p where p.id = v_home),
    'yard', (select p.code from public.ports p where p.id = v_yard), 'cost', v_cost));
  perform public.treasury_post(v_home, 'REFIT', -v_cost, null, v_ev);
  perform public.treasury_post(v_yard, 'REFIT', v_cost, null, v_ev);
  perform public.fleet_mend(p_fleet);

  -- A merchant's hands from the quay, what public.crew_hire_cost says it can give her. The rest she hires herself. A cargo ship sails crewless until W8.
  if public.fleet_kind(p_fleet) = 'MERCHANT' then
    v_short := public.fleet_crew_shortfall(p_fleet);
    if v_short > 0 then
      perform 1 from public.ports p where p.id = v_home for update;
      v_hands := (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int;
      update public.ports p set crew_pool = p.crew_pool - v_hands where p.id = v_home;
      for s in select x.id, greatest(0, c.crew_required - x.crew) as need
                 from public.ships x join public.ship_classes c on c.id = x.class_id
                where x.fleet_id = p_fleet order by x.id loop
        exit when v_hands <= 0;
        v_give := least(v_hands, s.need);
        update public.ships set crew = crew + v_give where id = s.id;
        v_hands := v_hands - v_give;
      end loop;
    end if;
  end if;

  update public.fleets
     set status = 'DOCKED', ready_at = p_now + make_interval(mins => public.wc_int('npc_refit_minutes')), version = version + 1
   where id = p_fleet;
  delete from public.npc_refit_waits w where w.fleet_id = p_fleet;
  return 'PAID';
end
$$
  $f$;

  execute $f$
create procedure public.tick_npc_refits(p_commit boolean default true)
language plpgsql
as $$
-- 0322: pg_cron byeharu-voyage:npc-refits, hourly at :18, never in the beat. Each wreck is her own transaction, so a city's lock is held for one step and a step that raises is warned of and the rest go on.
-- Every hull at 0 not at sea and not in a yard is walked; public.npc_refit_step judges her. Only a refit paid counts against npc_refits_per_run, so wrecks that wait cannot starve the rest.
-- Dark: one knob read. p_commit = false: one pass in the caller's transaction (a proof). No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  v_ids   uuid[];
  v_id    uuid;
  v_max   int;
  v_paid  int := 0;
  v_s     text;
  v_steps jsonb := '{}'::jsonb;
begin
  if not public.npc_refits_on() then
    return;
  end if;
  v_max := public.wc_int('npc_refits_per_run');
  v_ids := array(select distinct s.fleet_id
                   from public.ships s join public.fleets f on f.id = s.fleet_id
                  where s.durability <= 0 and f.status in ('DOCKED', 'ANCHORED', 'ADRIFT', 'UNABLE_TO_SAIL')
                    and public.npc_wrecked(s.fleet_id));
  foreach v_id in array v_ids loop
    exit when v_paid >= v_max;
    begin
      perform set_config('lock_timeout', '2s', true);
      v_s := public.npc_refit_step(v_id);
    exception when others then
      raise warning 'tick_npc_refits: fleet % stayed (SQLSTATE %: %)', v_id, sqlstate, sqlerrm;
      v_s := 'ERROR';
    end;
    v_steps := v_steps || jsonb_build_object(v_s, coalesce((v_steps ->> v_s)::int, 0) + 1);
    if v_s = 'PAID' then
      v_paid := v_paid + 1;
    end if;
    if p_commit then commit; end if;
  end loop;
  raise notice 'tick_npc_refits: %', v_steps;
end
$$
  $f$;

  revoke all on function public.npc_refits_on() from public, anon, authenticated;
  revoke all on function public.fleet_origin(uuid) from public, anon, authenticated;
  revoke all on function public.npc_wrecked(uuid) from public, anon, authenticated;
  revoke all on function public.npc_refit_cost(uuid) from public, anon, authenticated;
  revoke all on function public.yards_from(uuid) from public, anon, authenticated;
  revoke all on function public.refit_yard(uuid) from public, anon, authenticated;
  revoke all on function public.ransom_take(bigint) from public, anon, authenticated;
  revoke all on function public.fleet_mend(uuid) from public, anon, authenticated;
  revoke all on function voyage.lose_hold(uuid) from public, anon, authenticated;
  revoke all on function voyage.npc_wreck(uuid, uuid, integer) from public, anon, authenticated;
  revoke all on function public.npc_refit_step(uuid, timestamptz) from public, anon, authenticated;
  revoke all on procedure public.tick_npc_refits(boolean) from public, anon, authenticated;

  -- ── 6. THE HUNKS ──
  create temp table hunks_0322 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0322 values
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$    v_resolved := v_resolved + 1;
  end loop;
$h$,
$h$    v_resolved := v_resolved + 1;
    -- 0322 (docs/WORLD_POWERS.md section 3.4): the days that can take a hull. A ship of the world with no hull left is back at her origin (voyage.npc_wreck), and the voyage ends here. Dark: false, one knob read.
    if v_kind in ('STORM', 'PIRATES', 'SHOAL_WATER') and public.npc_wrecked(p_fleet) then
      perform voyage.npc_wreck(p_fleet, v.id, d);
      perform cmd.advance(p_fleet, p_now);
      return v_resolved;
    end if;
  end loop;
$h$),
  ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 1,
$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass tows her
$h$,
$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null and not public.npc_wrecked(r.fleet_id) then   -- 0322: a wreck is her city's to set afloat (public.npc_refit_step). Dark: false
        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass tows her
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
  end if;
$h$,
$h$  if public.npc_wrecked(p_fleet) then   -- 0322: she waits for her city to pay (public.npc_refit_step). Dark: false, and the patch below stands
    return 'WRECK';
  end if;
  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    perform public.fleet_mend(p_fleet);   -- 0322: the one line
  end if;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$        perform public.convoy_book('RETURNED', p_fleet, c.player_id, f.port_id, v_left, v_load);
      end if;
      update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
$h$,
$h$        perform public.convoy_book('RETURNED', p_fleet, c.player_id, f.port_id, v_left, v_load);
      end if;
      perform public.fleet_mend(p_fleet);   -- 0322: the one line
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 1,
$h$  e        record;
  s        record;
  v_lost   jsonb := '{}'::jsonb;
  v_qty    numeric;
  v_u      numeric;
$h$,
$h$  s        record;
  v_lost   jsonb;
  v_u      numeric;
$h$),
  ('voyage.forced_home(uuid,integer,uuid)', 2,
$h$  for e in select distinct k.key as code
             from public.ships s0 cross join lateral jsonb_each(s0.cargo) k
            where s0.fleet_id = p_fleet and (k.value)::text::numeric > 0
            order by 1 loop
    v_qty := public.fleet_cargo_qty(p_fleet, e.code);
    if v_qty > 0 then
      v_lost := v_lost || jsonb_build_object(e.code, public.fleet_unload(p_fleet, e.code, v_qty));
    end if;
  end loop;
$h$,
$h$  v_lost := voyage.lose_hold(p_fleet);   -- 0322: the same loop, lifted
$h$),
  ('public.tow_for(uuid,uuid)', 1,
$h$  select y.id, y.code, y.name, case when y.id = f.port_id then 0 else r.nm end
    into v_to, v_code, v_name, v_nm
    from public.ports y
    left join voyage.reach_from(f.port_id) r on r.port_id = y.id
   where y.kind = 'HARBOUR' and not y.is_ice_closed and public.port_has_shipyard(y.id)
     and (y.id = f.port_id or r.nm is not null)
   order by case when y.id = f.port_id then 0 else r.nm end, y.code
   limit 1;
$h$,
$h$  select y.port_id, y.code, y.name, y.nm   -- 0322: public.yards_from, the same query, lifted
    into v_to, v_code, v_name, v_nm
    from public.yards_from(f.port_id) y
   order by y.nm, y.code
   limit 1;
$h$);

  for v_h in select h.fn from hunks_0322 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0322 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0322 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0322 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0322 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0322 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 7. THE JOB. Dark, it reads one knob ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:npc-refits', '18 * * * *', 'call public.tick_npc_refits()')$q$;
  end if;

  -- ── 8. THE SELF-ASSERT: the catalog and pure arithmetic. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0322 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0322 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> 'REFIT') <> v_words_before then
    raise exception '0322 self-assert FAIL: a money word moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0322 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:npc-refits'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0322 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:npc-refits' and j.schedule = '18 * * * *' and j.command = 'call public.tick_npc_refits()' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0322 self-assert FAIL: the job is not as written';
    end if;
  end if;
  if public.npc_refits_on() then
    raise exception '0322 self-assert FAIL: the wreck rule is not dark';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'REFIT') <> 'moved' then
    raise exception '0322 self-assert FAIL: REFIT is not a moved kind';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0322 self-assert FAIL: a new function can be called from a client';
  end if;
  if exists (select 1 from public.npc_refit_waits) then
    raise exception '0322 self-assert FAIL: a wait exists';
  end if;
  if exists (select 1 from (values (0::bigint, 0::bigint), (12, 0), (13, 1), (1000000, 80000), (-5, 0)) t(aboard, take)
              where public.ransom_take(t.aboard) <> t.take) then
    raise exception '0322 self-assert FAIL: ransom_take is not 8 per cent, rounded down';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0322 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0322 self-assert ok: EVERY NPC SHIP HAS AN ORIGIN, dark. % hunks once each and reversing; no other function, knob or job; no game step ran (proof 30 runs them in CI). % ms.',
    (select count(*) from hunks_0322), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0322;
end
$m$;
