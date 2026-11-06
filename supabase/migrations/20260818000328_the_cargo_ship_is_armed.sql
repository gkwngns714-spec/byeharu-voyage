-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0328 — THE CARGO SHIP IS ARMED: an armed hull, a crew, stores and an upkeep her city pays. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 283, slice W8 of docs/WORLD_POWERS.md (section 3.2): *"cargoship should have defense and attacking power too"*.
--
-- ITS OWN SWITCH, BECAUSE `convoys_enabled` IS ALREADY LIT. The crewless hulls sail today, so a change behind public.convoys_on() would change live play the minute it deployed.
-- Everything here turns on `convoy_armed_enabled`, false, read by public.cargo_armed_on() alone, and that one reader decides one thing: which class a cargo ship should be (public.cargo_class).
-- OFF (today, and after this file): the class is `convoy_ship_class`, every ship already is it, and no hull carries guns. So nothing below finds any work to do.
-- ON: the class is `convoy_armed_class`. Everything else follows from WHAT SHE IS, never from the switch, so a ship at sea when the switch moves is looked after until she is home.
-- WHEN THE OWNER KEEPS IT ON, `convoy_ship_class` and this switch die in their own slice: the switch is a window, not a second way to run the game.
--
-- THE LIVE HULLS, DECIDED BY DEFAULT. They are refitted where they lie, free, as they come idle at home: same ship, same fleet, same house, same number, same book, same lap. A ship with funds aboard or on a lap is
-- not touched; she takes her new hull when her lap closes. The old hull goes, a new one is laid by public.commission_ship (the one place a hull enters `ships`), so no second writer of a hull or of her roll exists.
-- A hull is a world object and costs no gold (docs/WORLD_POWERS.md section 3.2): no purse moves at a refit, and nothing is minted. Lit at the switch, a realm's fleet is mixed for up to one lap.
--
-- WHAT THIS FILE ADDS:
--   public.cargo_armed_on   THE one reader of the switch. convoys_on() and the knob.
--   public.cargo_class      THE class a cargo ship is built as. Read by public.cargo_ships_commission and public.cargo_hull.
--   public.cargo_armed      THE answer to whether she has guns: her hull's class. Hands, stores and upkeep follow it.
--   public.fleet_hands      Hands from the quay above npc_crew_pool_floor, up to her complement. public.npc_refit_step's own lines, lifted, so there is one copy.
--   public.cargo_hull       The refit: her hull made the class she should be. Her hands go back on the quay. Free. Called only with no load, at home.
--   public.cargo_upkeep     At each departure of an armed ship: hands, stores to convoy_store_days, then her origin pays convoy_upkeep_per_leg to the harbour she leaves, moved, kind CONVOY_UPKEEP.
--   Four knobs: convoy_armed_enabled false, convoy_armed_class 'navire', convoy_upkeep_per_leg, convoy_store_days. One moved flow kind, CONVOY_UPKEEP.
--
-- THE RE-CUTS (hunks of the live bodies), each occurs once and reverses to its pre-image:
--   public.cargo_ship_step (3):        idle at home she takes her hull; each sailing leg passes her upkeep.
--   public.cargo_rebase (1):           the rebase leg passes her upkeep.
--   public.cargo_ships_commission (1): a new ship is laid as public.cargo_class.
--   public.fleet_wage (1):             a cargo ship's hands owe nothing: her upkeep is their wage. Read only for a fleet with hands aboard.
--   public.npc_refit_step (2):         the lines lifted into public.fleet_hands. A merchant only, as before.
--
-- WHY OFF EQUALS TODAY: no live hull has guns, so public.cargo_upkeep answers 0 on its first read; every live hull is her class, so public.cargo_hull answers false on its first; no live cargo ship has hands, so the
-- fleet_wage branch is never entered. Parity is proved, not argued: scripts/ops/harness/rich-cities/dark-scene.sql and scripts/ops/harness/armed-cargo/dark-scene.sql, before and after this file, digests equal.
--
-- GOLD. Nothing is minted. The upkeep is two rows of one moved kind, origin out and harbour in. Leaving her origin, she pays nobody: paying yourself moves nothing. A city pays only from its surplus, what it can: a
-- broke origin pays nothing and she sails all the same, because stopping her would stop the aid. Hands and stores are free: the upkeep is their price (docs/WORLD_POWERS.md section 3.2).
-- A donor's lock is never waited for (0307's rule): a busy origin pays nothing for that leg, and she sails.
--
-- DECIDED BY DEFAULT (owner may reverse): docs/dev-log/2026-11-06-the-cargo-ship-is-armed.md lists them.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob, word or job; the switch off; no hull armed; the class is real and has guns.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 36, scripts/db/proofs/36_armed_cargo.sql. Mutation controls: scripts/ops/harness/armed-cargo/proof-0328.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `convoy_armed_enabled` false is the switch; each ship goes back to the old class as she comes idle at home, her hands back on the quay. Nothing strands, no gold moves.
-- To remove: swap this file's old and new, then drop what it created. CONVOY_UPKEEP rows stay.
-- VERSION: 0328 - prod head 0324 (2026-11-06). 0325 (#527), 0326 (#534) and 0327 (#529) deploy first. 0326 cuts public.cargo_ships_commission and none of the lines here; the others touch none of these bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_words_before text;
  v_cron_before text;
  v_cron_after  text;
  v_class text;
  c_keys constant text[] := array['convoy_armed_enabled', 'convoy_armed_class', 'convoy_upkeep_per_leg', 'convoy_store_days'];
  c_new_fns constant text[] := array[
    'public.cargo_armed_on()', 'public.cargo_class()', 'public.cargo_armed(uuid)', 'public.fleet_hands(uuid,uuid)', 'public.cargo_hull(uuid)', 'public.cargo_upkeep(uuid,uuid)'];
  c_hunked constant text[] := array[
    'public.cargo_ship_step(uuid,timestamp with time zone)', 'public.cargo_rebase(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'public.cargo_ships_commission(uuid)',
    'public.fleet_wage(uuid,boolean,integer)', 'public.npc_refit_step(uuid,timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.cargo_armed_on()') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.stats_flow_words w where w.kind = 'CONVOY_UPKEEP') then
    raise exception '0328 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.cargo_rebase(uuid,uuid,timestamp with time zone,timestamp with time zone)') is null or to_regprocedure('public.npc_refit_step(uuid,timestamp with time zone)') is null then
    raise exception '0328 refuses: 0322 / 0324 (the refit, the rebase) are not in this world';
  end if;
  if not exists (select 1 from public.ship_classes c where c.code = 'navire' and c.attack > 0 and c.crew_required > 0) then
    raise exception '0328 refuses: no armed class navire in this world';
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

  -- ── 1. THE KNOBS AND THE WORD ──
  insert into public.world_config (key, value, description) values
    ('convoy_armed_enabled', 'false'::jsonb, '0328: THE switch of armed cargo ships. False: a cargo ship is convoy_ship_class, as 0308. True, with convoys_enabled: she is convoy_armed_class, refitted free as she comes idle at home. Owner only.'),
    ('convoy_armed_class', to_jsonb('navire'::text), '0328: public.ship_classes.code of an armed cargo ship, read by public.cargo_class while convoy_armed_enabled is on. A class with no attack sails crewless and pays no upkeep.'),
    ('convoy_upkeep_per_leg', to_jsonb(500), '0328: ducats an armed cargo ship''s origin pays, from its surplus, to the harbour she leaves, each departure. Moved, kind CONVOY_UPKEEP. Her wages and stores count as paid by it.'),
    ('convoy_store_days', to_jsonb(90), '0328: days of stores an armed cargo ship is topped up to, free, at each departure. Must cover her longest leg with room for delays: proof 36 checks it against every leg of the world.');
  insert into public.stats_flow_words (kind, side, word, ord) values ('CONVOY_UPKEEP', 'moved', 'Cargo upkeep', 51);

  -- ── 2. THE NEW FUNCTIONS ──
  execute $f$
create function public.cargo_armed_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0328: THE one reader of convoy_armed_enabled. It needs ships to sail: convoys off, no ship is refitted, whatever this knob says.
  select public.convoys_on() and public.wc('convoy_armed_enabled') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.cargo_class()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0328: THE class a cargo ship is built as. The only thing the switch decides. Read by public.cargo_ships_commission and public.cargo_hull.
  select case when public.cargo_armed_on() then public.wc_text('convoy_armed_class') else public.wc_text('convoy_ship_class') end
$$
  $f$;

  execute $f$
create function public.cargo_armed(p_fleet uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0328: THE answer to whether she has guns, read off her hull and not off the switch: an armed ship at sea when the switch goes off still needs her hands and stores until she is home.
  select exists (select 1 from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet and k.attack > 0)
$$
  $f$;

  execute $f$
create function public.fleet_hands(p_fleet uuid, p_port uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0328: hands from the quay for an NPC ship lying at p_port: what public.crew_hire_cost says it can give her, up to her complement. public.npc_refit_step's own lines, lifted. Free: whoever calls has said who pays.
-- With nothing to give it takes no lock. Answers the hands taken. A ship short of hands sails short: a quay at its floor never holds her.
declare
  v_short int := public.fleet_crew_shortfall(p_fleet);
  v_hands int;
  v_left  int;
  v_give  int;
  s       record;
begin
  if v_short <= 0 or (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int <= 0 then
    return 0;
  end if;
  perform 1 from public.ports p where p.id = p_port for update;
  v_hands := (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int;
  v_left := v_hands;
  update public.ports p set crew_pool = p.crew_pool - v_hands where p.id = p_port;
  for s in select x.id, greatest(0, c.crew_required - x.crew) as need
             from public.ships x join public.ship_classes c on c.id = x.class_id
            where x.fleet_id = p_fleet order by x.id loop
    exit when v_left <= 0;
    v_give := least(v_left, s.need);
    update public.ships set crew = crew + v_give where id = s.id;
    v_left := v_left - v_give;
  end loop;
  return v_hands;
end
$$
  $f$;

  execute $f$
create function public.cargo_hull(p_fleet uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0328: THE refit of a cargo ship: her hull made the class she should be (public.cargo_class). Same fleet, house, number and book. The old hull goes and public.commission_ship, the one place a hull is put into `ships`, lays
-- the new one under the old name, empty and crewless: her first departure brings her hands and stores (public.cargo_upkeep). Her hands, if any, go back on the quay she lies at. Free, as a cargo ship's hull always was: no purse
-- moves. Called only by public.cargo_ship_step, idle at home with no load. Off, on a ship of the class: false, two reads. Answers whether she was refitted.
declare
  s        public.ships%rowtype;
  v_class  text := public.cargo_class();
  v_code   text;
begin
  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;
  select k.code into v_code from public.ship_classes k where k.id = s.class_id;
  if s.id is null or v_code = v_class then
    return false;
  end if;
  if s.crew > 0 then
    update public.ports p set crew_pool = p.crew_pool + s.crew where p.id = (select f.port_id from public.fleets f where f.id = p_fleet);
  end if;
  delete from public.ships x where x.id = s.id;
  perform public.commission_ship(s.player_id, p_fleet, v_class, s.name, true, false);
  return true;
end
$$
  $f$;

  execute $f$
create function public.cargo_upkeep(p_fleet uuid, p_port uuid)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0328: what an armed cargo ship takes as she leaves p_port (docs/WORLD_POWERS.md section 3.2). Called by public.cargo_ship_step and public.cargo_rebase, just before voyage.depart, and nowhere else.
-- No guns: 0, one read. Otherwise: hands from the quay (public.fleet_hands); stores topped up free to convoy_store_days (public.stores_topup, the one top-up); then her origin pays convoy_upkeep_per_leg to this harbour,
-- moved, two rows, from its surplus, what it can. Her wages and stores count as paid by that (public.fleet_wage answers 0 for her). Leaving her origin she pays nobody: paying yourself moves nothing.
-- She sails whatever the answer: a broke or busy origin pays nothing, and no quay and no purse ever holds the aid in port. Answers the ducats moved.
declare
  v_home uuid;
  v_pay  bigint;
  s      record;
begin
  if not public.cargo_armed(p_fleet) then
    return 0;
  end if;
  perform public.fleet_hands(p_fleet, p_port);
  for s in select x.id, t.water_t, t.food_t
             from public.ships x
            cross join lateral (select public.ship_hold_capacity(x.id) as cap offset 0) hc
            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, hc.cap, public.wc_num('convoy_store_days'), hc.cap * x.store_ratio) t
            where x.fleet_id = p_fleet loop
    if s.water_t > 0 or s.food_t > 0 then
      update public.ships x set water_t = x.water_t + s.water_t, food_t = x.food_t + s.food_t where x.id = s.id;
    end if;
  end loop;
  v_home := public.fleet_origin(p_fleet);
  if v_home is not distinct from p_port or not public.treasury_try_lock(v_home) then
    return 0;
  end if;
  v_pay := least(public.wc_int('convoy_upkeep_per_leg')::bigint, greatest(public.city_surplus(v_home), 0));
  if v_pay <= 0 then
    return 0;
  end if;
  perform public.treasury_post(v_home, 'CONVOY_UPKEEP', -v_pay, null, null);
  perform public.treasury_post(p_port, 'CONVOY_UPKEEP', v_pay, null, null);
  return v_pay;
end
$$
  $f$;

  revoke all on function public.cargo_armed_on() from public, anon, authenticated;
  revoke all on function public.cargo_class() from public, anon, authenticated;
  revoke all on function public.cargo_armed(uuid) from public, anon, authenticated;
  revoke all on function public.fleet_hands(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.cargo_hull(uuid) from public, anon, authenticated;
  revoke all on function public.cargo_upkeep(uuid, uuid) from public, anon, authenticated;

  -- ── 3. THE HUNKS ──
  create temp table hunks_0328 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0328 values
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$--   Then, port time done (fleets.ready_at), the next leg. Off she still sails: she is carrying funds home, and the circuit is the only way she knows.
$h$,
$h$--   Then, port time done (fleets.ready_at), the next leg. Off she still sails: she is carrying funds home, and the circuit is the only way she knows.
--   0328: idle at home she takes the hull she should have (public.cargo_hull), and every leg passes her upkeep (public.cargo_upkeep). Both find nothing to do until the switch is lit.
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$    if v_load is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$,
$h$    if v_load is null then
      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 3,
$h$  perform voyage.depart(p_fleet, l.segments, f.port_id, l.to_port, p_now);
$h$,
$h$  perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: hands, stores, her origin pays. No guns: one read
  perform voyage.depart(p_fleet, l.segments, f.port_id, l.to_port, p_now);
$h$),
  ('public.cargo_rebase(uuid,uuid,timestamp with time zone,timestamp with time zone)', 1,
$h$  perform voyage.depart(p_fleet, voyage.segments_from_course(v_leg -> 'course'), p_port, v_to, p_now);
$h$,
$h$  perform public.cargo_upkeep(p_fleet, p_port);   -- 0328: this leg too, or an armed ship sails it with no stores
  perform voyage.depart(p_fleet, voyage.segments_from_course(v_leg -> 'course'), p_port, v_to, p_now);
$h$),
  ('public.cargo_ships_commission(uuid)', 1,
$h$    perform public.commission_ship(v_player, v_fleet, public.wc_text('convoy_ship_class'), format('Cargo ship %s', v_n), true, false);
$h$,
$h$    perform public.commission_ship(v_player, v_fleet, public.cargo_class(), format('Cargo ship %s', v_n), true, false);   -- 0328: the class she should be
$h$),
  ('public.fleet_wage(uuid,boolean,integer)', 1,
$h$  -- (0149's early exit: a house holding no HOUSE-scope skill — every merchant — reads nothing more)
$h$,
$h$  -- 0328: a cargo ship's hands are paid by her upkeep (public.cargo_upkeep), so she owes nothing, ever. Read only for a fleet with hands aboard; no live cargo ship has any until convoy_armed_enabled.
  if v_crew > 0 and public.fleet_kind(p_fleet) = 'CARGO_SHIP' then
    return 0;
  end if;
  -- (0149's early exit: a house holding no HOUSE-scope skill — every merchant — reads nothing more)
$h$),
  ('public.npc_refit_step(uuid,timestamp with time zone)', 1,
$h$  v_why    text;
  v_short  int;
  v_hands  int;
  v_give   int;
  v_ev     uuid;
  s        record;
begin
$h$,
$h$  v_why    text;
  v_ev     uuid;
begin
$h$),
  ('public.npc_refit_step(uuid,timestamp with time zone)', 2,
$h$  -- A merchant's hands from the quay, what public.crew_hire_cost says it can give her. The rest she hires herself. A cargo ship sails crewless until W8.
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
$h$,
$h$  -- A merchant's hands from the quay (0328: public.fleet_hands, these lines lifted). The rest she hires herself. A cargo ship takes hers as she leaves (public.cargo_upkeep), if she has guns.
  if public.fleet_kind(p_fleet) = 'MERCHANT' then
    perform public.fleet_hands(p_fleet, v_home);
  end if;
$h$);

  for v_h in select h.fn from hunks_0328 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0328 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0328 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0328 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0328 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0328 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog and stable reads. No game step. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0328 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0328 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> 'CONVOY_UPKEEP') <> v_words_before then
    raise exception '0328 self-assert FAIL: a flow word moved';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'CONVOY_UPKEEP') is distinct from 'moved' then
    raise exception '0328 self-assert FAIL: CONVOY_UPKEEP is not a moved kind';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0328 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0328 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if public.cargo_armed_on() then
    raise exception '0328 self-assert FAIL: the rule is not dark';
  end if;
  if public.cargo_class() is distinct from public.wc_text('convoy_ship_class') then
    raise exception '0328 self-assert FAIL: off, the class is not convoy_ship_class';
  end if;
  if exists (select 1 from public.cargo_ships c where public.cargo_armed(c.fleet_id)) then
    raise exception '0328 self-assert FAIL: a live hull has guns: the upkeep would run dark';
  end if;
  v_class := public.wc_text('convoy_armed_class');   -- a variable: the planner folds a STABLE read in a WHERE on this block's own older snapshot, which has no such key yet
  if not exists (select 1 from public.ship_classes k where k.code = v_class and k.attack > 0 and k.crew_required > 0) then
    raise exception '0328 self-assert FAIL: convoy_armed_class has no guns or needs no hands';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.cargo_armed_on()'::regprocedure, 'public.cargo_class()'::regprocedure, 'public.cargo_armed(uuid)'::regprocedure]::oid[])) <> 'sss' then
    raise exception '0328 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0328 self-assert FAIL: a new function can be called from a client';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0328 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0328 self-assert ok: THE CARGO SHIP IS ARMED, dark behind convoy_armed_enabled. % hunks once each and reversing; no other function, knob, word or job; no game step ran (proof 36 runs them in CI). % ms.',
    (select count(*) from hunks_0328), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0328;
end
$m$;
