-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 68 — AN ARMADA SAILS AS ONE  (migration 0367; docs/ARMADA.md; owner row 323: "with more than one fleet, max 6 fleet - an armada")
--
--   0367's own self-assert runs one small probe. This proof runs the REAL doors (cmd.armada_form, cmd.preview_armada_sail, cmd.armada_sail, cmd.armada_disband, cmd.issue), the REAL
--   mover (cmd.do_sail), the REAL day (voyage.settle's PIRATES arm) and the REAL engine (public.fight_sides through voyage.raid_report), on probe companies, all rolled back.
--   The pre-images of voyage.hazard_roll and voyage.settle are the live bodies with 0367's hunks taken out again, so "a fleet in no armada is what she was" is measured.
--   The sea is stubbed on one setting for the raid days, as proofs 37, 38, 46 and 56 stub it; the real roll is proved equal before the stub goes in.
--
-- @pass NO_ARMADA_OLD_IS_NEW      every fleet of this world reads the speed it read (alone = old, at her own fill and full); a company's fleet and a merchant's, in no armada, sail a passage of raid days to the same events, hulls, crews, holds and purse under the old settle and the new, byte for byte, and roll the same days under the old roll and the new
-- @pass ARMADA_REFUSALS           one fleet, another company's fleet, a fleet at anchor, a fleet in another port, a fleet with an order waiting, a fleet already in an armada, a bad name, nobody, another company: each refused whole with its own code; a fleet of an armada does not sail or turn alone
-- @pass ARMADA_SAILS_AS_ONE       the dry run keeps nothing and says what the order says; the order leaves every fleet through the one mover on one path, one speed (the slowest fleet's) and one arrival; each fleet's insurance is her own; a fleet refused refuses the armada under her name and nothing moved
-- @pass ARMADA_SAME_SEA           every day of the passage, a sister's roll IS the lead's roll, and the lead's roll is what the old body rolls for her
-- @pass ARMADA_RAID_ONE_SIDE      a raid day (the passage lengthened to ten days of one dangerous sea, the same for both voyages): fought ONCE, every hull of both fleets on one side against twice the raiders one fleet draws; both fleets' days carry the same fight, the same log naming both fleets, the same outcome; each ship lost exactly what that one fight says; it is the fight the engine fights for that side and seed
-- @pass ARMADA_PLUNDER_BY_HOLD    what the raiders carried off: from each fleet's own hold, her own roll's share of every good; a sister's settling touches no hold but her own; each fleet's insurance pays for her own loss
-- @pass ARMADA_OF_SIX             with room for seven fleets: a taken name is refused and a company keeps two armadas; seven fleets are refused and six are formed and sail on one schedule; six fleets' hulls stand on one side against six times the raiders
-- @pass ARMADA_ARRIVES_DISBANDS   both fleets make the port at the one instant; the armada reads PORT there and may be sent again; disbanded, each fleet is her own again and sails alone
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.as_house(p_uid uuid) returns void language sql as $b$
  select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
         set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
$b$;

-- a path of p_days voyage-days, every day in sea p_sea at p_speed (proof 46's and 56's: a day is the speed x 24 to the digit)
create function pg_temp.through(p_speed numeric, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', p_speed * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

-- ── THE PRE-IMAGES: the live bodies with 0367's hunks taken out, under pg_temp names ──
do $$
declare
  h     record;
  v_def text;
  v_fn  text;
begin
  create temp table hunks_68 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_68 values
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$,
$h$  -- 0367 (docs/ARMADA.md section 4): a voyage sailed in an armada rolls her LEAD voyage's days, so every fleet of hers meets the same sea on the same day and they arrive together.
  -- Any other voyage: one primary-key probe of a small table, and the roll it always had.
  p_voyage := coalesce((select av.lead_voyage_id from public.armada_voyages av where av.voyage_id = p_voyage), p_voyage);
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
$h$,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
  v_arm     jsonb;     -- 0367: an armada's one fight of the day (voyage.armada_fight); null for a voyage in no armada
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
$h$,
$h$      -- 0367 (docs/ARMADA.md section 6): a voyage sailed in an armada meets the raid with every hull of the armada on one side, against the raiders all her fleets draw; the
      -- fight is fought once and every fleet of hers reads it (voyage.armada_fight). Below, each fleet takes her own hulls', crew's and hold's share as ever. Null: the day it always was.
      v_arm := voyage.armada_fight(v.id, d, p_fleet, v_pirate, v_raider);
      if v_arm is not null then
        v_raider := (v_arm->>'raider')::numeric;
        v_escort := (v_arm->>'escort')::numeric;
        v_fight := v_arm->'fight';
      else
      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
      end if;
$h$);
  foreach v_fn in array array['voyage.hazard_roll(uuid,integer)', 'voyage.settle(uuid,timestamp with time zone)'] loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    for h in select * from hunks_68 x where x.fn = v_fn order by x.ord desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'PROOF 68 FAIL: hunk % of % is not in the live body exactly once', h.ord, h.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if position('armada' in v_def) > 0 then
      raise exception 'PROOF 68 FAIL: the pre-image of % still names an armada', v_fn;
    end if;
    v_def := replace(replace(v_def, 'CREATE OR REPLACE FUNCTION voyage.hazard_roll(', 'CREATE FUNCTION pg_temp.hazard_roll_old_68('),
                     'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE FUNCTION pg_temp.settle_old_68(');
    execute v_def;
  end loop;
end
$$;

-- A PASSAGE OF RAID DAYS for a fleet in no armada, in a subtransaction that is rolled back: under the old settle or the new. The voyage id is pinned (the fight's seed).
-- Answers what it left: every day, her hulls, crews and holds, her purse, her events.
create function pg_temp.passage_68(p_fleet uuid, p_sea uuid, p_days int, p_at timestamptz, p_old boolean) returns jsonb language plpgsql as $b$
declare
  c_voy  constant uuid := '00000000-0068-4000-8000-0000000000aa';
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_voy  uuid;
  v_out  jsonb;
  v_eta  timestamptz;
begin
  begin
    v_voy := voyage.depart(p_fleet, pg_temp.through(voyage.fleet_speed(p_fleet), p_sea, p_days), v_port, v_port, p_at);
    update public.voyages set id = c_voy where id = v_voy;
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    perform set_config('byeharu.proof_day', '', true);
    loop
      select o.eta into v_eta from public.voyages o where o.id = c_voy and o.status = 'SAILING';
      exit when v_eta is null;
      if p_old then perform pg_temp.settle_old_68(p_fleet, v_eta); else perform voyage.settle(p_fleet, v_eta); end if;
    end loop;
    perform set_config('byeharu.proof_sea', '', true);
    v_out := jsonb_build_object(
      'days', (select jsonb_agg(jsonb_build_object('d', e.day_index, 'kind', e.kind, 'payload', e.payload, 'at', e.resolved_at) order by e.day_index)
                 from public.voyage_events e where e.voyage_id = c_voy),
      'ships', (select jsonb_agg(jsonb_build_array(s.name, s.durability, s.crew, s.cargo, s.water_t, s.food_t) order by s.name) from public.ships s where s.fleet_id = p_fleet),
      'fleet', (select jsonb_build_array(f.status, f.port_id) from public.fleets f where f.id = p_fleet),
      'purse', (select p.ducats from public.players p where p.id = v_pl),
      'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload - 'voyage_id') order by e.kind, e.payload::text), '[]'::jsonb)
                   from public.events e where e.player_id = v_pl and e.id <> all (v_ev)));
    raise exception using errcode = 'ZP068', message = 'PASSAGE_ROLLBACK_68';
  exception when sqlstate 'ZP068' then
    null;
  end;
  return v_out;
end
$b$;

do $$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_prt  uuid := (select id from public.nations where code = 'PRT');
  v_sea  uuid := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  c_ua   constant uuid := '00000000-0068-4000-8000-00000000000a';
  c_ub   constant uuid := '00000000-0068-4000-8000-00000000000b';
  c_uc   constant uuid := '00000000-0068-4000-8000-00000000000c';
  v_t    timestamptz := now();
  v_a    uuid;      -- the armada's company
  v_b    uuid;      -- a company in no armada
  v_m    uuid;      -- a merchant
  v_c    uuid;      -- a company with room for seven fleets
  v_f1   uuid;
  v_f2   uuid;
  v_fb   uuid;
  v_fb2  uuid;
  v_fm   uuid;
  v_arm  uuid;
  v_six  uuid[];
  v_path jsonb;
  v_r    jsonb;
  v_x    jsonb;
  v_old  jsonb;
  v_new  jsonb;
  v_lead uuid;
  v_sis  uuid;
  v_ga   text;
  v_gb   text;
  v_n    int := 0;
  v_days int;
  v_day  int;
  v_pred jsonb;
  v_side jsonb;
  v_one  numeric;
  v_p1   jsonb;
  v_p2   jsonb;
  v_hull jsonb;
  v_hold jsonb;
  v_ans  jsonb;
  v_speed numeric;
  v_eta  timestamptz;
  h      record;
  d      int;
  i      int;
begin
  if not public.armada_on() or public.wc_int('armada_fleet_max') <> 6 or public.wc_num('armada_raid_scale') <> 1 then
    raise exception 'PROOF 68 FAIL: the armada knobs of this world are not lit, 6 and 1';
  end if;
  if not public.combat_bite_on() then
    raise exception 'PROOF 68 FAIL: combat_bite is off in this world; this proof reads the fight';
  end if;
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_path
    from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;
  select code into v_ga from public.goods where bulk = 1 order by code limit 1;
  select code into v_gb from public.goods where bulk = 1 and code > v_ga order by code limit 1;

  -- ── THE PROBES ──
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_ua, 'Casa da Armada 68', v_prt, 800000, false) returning id into v_a;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_ub, 'Casa Sozinha 68', v_prt, 800000, false) returning id into v_b;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Mercante 68', v_prt, 800000, true) returning id into v_m;
  v_f1 := public.form_fleet(v_a, 'Capitania 68', v_lis);
  v_f2 := public.form_fleet(v_a, 'Almiranta 68', v_lis);
  v_fb := public.form_fleet(v_b, 'Sozinha 68', v_lis);
  v_fb2 := public.form_fleet(v_b, 'Vizinha 68', v_fnc);
  v_fm := public.form_fleet(v_m, 'Mercante 68', v_lis);
  perform public.commission_ship(v_a, v_f1, 'barca', 'Capitania Um', true, true);
  perform public.commission_ship(v_a, v_f2, 'barca', 'Almiranta Um', true, true);
  perform public.commission_ship(v_b, v_fb, 'barca', 'Sozinha Um', true, true);
  perform public.commission_ship(v_b, v_fb2, 'barca', 'Vizinha Um', true, true);
  perform public.commission_ship(v_m, v_fm, 'barca', 'Mercante Um', true, true);
  if public.fleet_load(v_f1, v_ga, 40, 25) <> 40 or public.fleet_load(v_f1, v_gb, 9, 100) <> 9 or public.fleet_load(v_f2, v_ga, 21, 25) <> 21
     or public.fleet_load(v_fb, v_ga, 30, 25) <> 30 or public.fleet_load(v_fm, v_ga, 30, 25) <> 30 then
    raise exception 'PROOF 68 FAIL: the probes'' cargo did not load';
  end if;

  -- ══ NO_ARMADA_OLD_IS_NEW ══
  -- (1) the speed of every fleet of this world: alone IS the old body (0367's self-assert holds the text equal), and the new reading answers it for a fleet in no armada
  for h in select f.id from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id) loop
    if voyage.fleet_speed_at(h.id, null) is distinct from voyage.fleet_speed_alone_at(h.id, null) or voyage.fleet_speed_at(h.id, 1) is distinct from voyage.fleet_speed_alone_at(h.id, 1)
       or voyage.fleet_speed(h.id) is distinct from voyage.fleet_speed_alone_at(h.id, null) then
      raise exception 'PROOF 68 FAIL: the speed of fleet % moved', h.id;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n < 5 then
    raise exception 'PROOF 68 FAIL: only % fleets were there to hold the speed equal on', v_n;
  end if;
  if replace(replace(pg_get_functiondef('voyage.fleet_speed_alone_at(uuid,numeric)'::regprocedure), E'\r', ''), 'voyage.fleet_speed_alone_at(', 'voyage.fleet_speed_at(') like '%armada%' then
    raise exception 'PROOF 68 FAIL: the speed formula names an armada';
  end if;
  -- (2) the real roll, old against new, on a company's voyage and a merchant's
  for h in select x.fl from (values (v_fb), (v_fm)) x(fl) loop
    begin
      v_lead := voyage.depart(h.fl, pg_temp.through(voyage.fleet_speed(h.fl), v_sea, 12), v_lis, v_lis, v_t);
      for d in 1 .. 12 loop
        if (select to_jsonb(x) from voyage.hazard_roll(v_lead, d) x) is distinct from (select to_jsonb(x) from pg_temp.hazard_roll_old_68(v_lead, d) x) then
          raise exception 'PROOF 68 FAIL: day % of a voyage in no armada rolls another day under the new body', d;
        end if;
      end loop;
      raise exception using errcode = 'ZP068', message = 'ROLL_ROLLBACK_68';
    exception when sqlstate 'ZP068' then
      null;
    end;
  end loop;

  -- ── the sea on one setting from here on (proof 56's stub, and a day: '' every day) ──
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_68;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
  v_d text := coalesce(current_setting('byeharu.proof_day', true), '');
  v_on boolean := v_s <> '' and (v_d = '' or v_d::int = p_day);
begin
  return query select v_on, case when v_on then v_s end, 0.5::numeric, 1::numeric;
end
$b$
  $f$;
  -- (3) a passage of six raid days, whole, under the old settle and the new: a company's fleet and a merchant's
  for h in select x.fl, x.who from (values (v_fb, 'a company'), (v_fm, 'a merchant')) x(fl, who) loop
    v_old := pg_temp.passage_68(h.fl, v_sea, 6, v_t, true);
    v_new := pg_temp.passage_68(h.fl, v_sea, 6, v_t, false);
    if v_old is null or v_new is null or v_old is distinct from v_new or jsonb_array_length(v_new -> 'days') < 1
       or not exists (select 1 from jsonb_array_elements(v_new -> 'days') e where e.value ->> 'kind' = 'PIRATES') then
      raise exception 'PROOF 68 FAIL: %''s passage of raid days is not what it was: old % new %', h.who, v_old, v_new;
    end if;
    if h.who = 'a company' and not exists (select 1 from jsonb_array_elements(v_new -> 'days') e where e.value -> 'payload' -> 'fight' ? 'log') then
      raise exception 'PROOF 68 FAIL: the company''s raid kept no log, so the parity read no fight';
    end if;
  end loop;
  if exists (select 1 from public.armada_fights) or exists (select 1 from public.armada_voyages) then
    raise exception 'PROOF 68 FAIL: a fleet in no armada left an armada row';
  end if;
  raise notice 'PASS: NO_ARMADA_OLD_IS_NEW — % fleets read the speed they read; a company''s fleet and a merchant''s rolled 12 days and sailed 6 raid days to the same events, hulls, holds and purse under the old bodies and the new', v_n;

  -- ══ ARMADA_REFUSALS ══
  perform pg_temp.as_house(c_ua);
  if public.current_player_id() is distinct from v_a then
    raise exception 'PROOF 68 FAIL: the probe is not signed in as its house';
  end if;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 30, lon = -20 where id = v_f2;
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Ao Largo 68') ->> 'error_code' is distinct from 'E_NOT_DOCKED' then
    raise exception 'PROOF 68 FAIL: a fleet at anchor joined an armada';
  end if;
  update public.fleets set status = 'DOCKED', port_id = v_fnc, lat = null, lon = null where id = v_f2;
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Dois Portos 68') ->> 'error_code' is distinct from 'E_NOT_SAME_PORT' then
    raise exception 'PROOF 68 FAIL: fleets in two ports formed an armada';
  end if;
  update public.fleets set port_id = v_lis where id = v_f2;
  -- an order waiting: a SAIL kept in her queue while her port time runs (cmd.advance leaves it pending)
  update public.fleets set ready_at = now() + interval '1 hour' where id = v_f2;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values (v_f2, v_a, 1, 'SAIL TO FNC', 'SAIL', jsonb_build_object('dest', v_fnc));
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Ocupada 68') ->> 'error_code' is distinct from 'E_FLEET_BUSY' then
    raise exception 'PROOF 68 FAIL: a fleet with an order waiting joined an armada';
  end if;
  delete from public.orders where fleet_id = v_f2;
  update public.fleets set ready_at = null where id = v_f2;
  for h in select * from (values
      (jsonb_build_array(v_f1), 'Uma So 68', 'E_ARMADA_SIZE'), (jsonb_build_array(v_f1, v_fb), 'Alheia 68', 'E_NO_SUCH_FLEET'),
      (jsonb_build_array(v_f1, v_f2), 'x', 'E_BAD_NAME'), (jsonb_build_array(v_f1, v_f2), null, 'E_BAD_NAME'), ('{}'::jsonb, 'Nada 68', 'E_PARSE')) t(fl, nm, want) loop
    v_r := cmd.armada_form(h.fl, h.nm);
    if v_r ->> 'error_code' is distinct from h.want then
      raise exception 'PROOF 68 FAIL: forming "%" answered % and not %', h.nm, v_r, h.want;
    end if;
  end loop;
  if exists (select 1 from public.armadas) or exists (select 1 from public.events e where e.player_id = v_a and e.kind like 'ARMADA%') then
    raise exception 'PROOF 68 FAIL: a refused armada left a mark';
  end if;
  -- nobody, and another company, form nothing of hers
  perform pg_temp.as_house(null);
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Ninguem 68') ->> 'error_code' is distinct from 'E_NO_HOUSE' then
    raise exception 'PROOF 68 FAIL: nobody formed an armada';
  end if;
  perform pg_temp.as_house(c_ub);
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Roubada 68') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET' then
    raise exception 'PROOF 68 FAIL: another company formed an armada of her fleets';
  end if;
  perform pg_temp.as_house(c_ua);
  v_r := cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Armada Real 68');
  v_arm := (v_r ->> 'armada_id')::uuid;
  if v_arm is null or (world.armadas() -> 'armadas' -> 0 ->> 'state') <> 'PORT' then
    raise exception 'PROOF 68 FAIL: the armada was not formed: %', v_r;
  end if;
  if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Segunda 68') ->> 'error_code' is distinct from 'E_IN_ARMADA'
     or cmd.issue(v_f2, 'SAIL TO FNC', null, v_path) ->> 'error_code' is distinct from 'E_IN_ARMADA'
     or (select f.status from public.fleets f where f.id = v_f2) <> 'DOCKED' then
    raise exception 'PROOF 68 FAIL: a fleet of an armada joined another, or sailed alone';
  end if;
  perform cmd.clear(v_f2, true);
  -- another company reads none of hers, and cannot send or disband her
  perform pg_temp.as_house(c_ub);
  if world.armadas() -> 'armadas' <> '[]'::jsonb or cmd.armada_sail(v_arm, 'FNC', v_path, false) ->> 'error_code' is distinct from 'E_NO_SUCH_ARMADA'
     or cmd.armada_disband(v_arm) ->> 'error_code' is distinct from 'E_NO_SUCH_ARMADA' then
    raise exception 'PROOF 68 FAIL: another company read, sent or disbanded her armada';
  end if;
  perform pg_temp.as_house(c_ua);
  raise notice 'PASS: ARMADA_REFUSALS — at anchor, two ports, an order waiting, one fleet, another company''s fleet, a bad name, nobody, another company, already in an armada: each refused whole; a fleet of an armada did not sail alone';

  -- ══ ARMADA_SAILS_AS_ONE ══
  update public.ships set durability = durability * 0.6 where fleet_id = v_f2;   -- the second fleet is the slower: her speed is the armada's
  if voyage.fleet_speed(v_f1) <> voyage.fleet_speed_alone_at(v_f2, null) or voyage.fleet_speed_alone_at(v_f1, null) <= voyage.fleet_speed_alone_at(v_f2, null) then
    raise exception 'PROOF 68 FAIL: the armada does not read her slowest fleet''s speed';
  end if;
  -- a fleet refused refuses the armada, under her name, and nothing moved
  update public.ships set crew = 0 where fleet_id = v_f2;
  v_r := cmd.armada_sail(v_arm, 'FNC', v_path, true);
  if v_r ->> 'error_code' is distinct from 'E_CREW_SHORT' or v_r ->> 'error_message' not like '%Almiranta 68%' or (v_r -> 'figures') is null
     or exists (select 1 from public.voyages v where v.player_id = v_a) or exists (select 1 from public.fleets f where f.player_id = v_a and f.status <> 'DOCKED')
     or (select p.ducats from public.players p where p.id = v_a) <> 800000 or exists (select 1 from public.insured_voyages i where i.player_id = v_a) then
    raise exception 'PROOF 68 FAIL: a refused fleet did not refuse the whole armada under her name: %', v_r;
  end if;
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f2;
  v_x := cmd.preview_armada_sail(v_arm, 'FNC', v_path, true);
  if not coalesce((v_x ->> 'ok')::boolean, false) or not (v_x ->> 'dry')::boolean or exists (select 1 from public.voyages v where v.player_id = v_a)
     or (select p.ducats from public.players p where p.id = v_a) <> 800000 or exists (select 1 from public.insured_voyages i where i.player_id = v_a)
     or exists (select 1 from public.armada_voyages) or exists (select 1 from public.events e where e.player_id = v_a and e.kind in ('DEPARTED', 'ARMADA_SAILED')) then
    raise exception 'PROOF 68 FAIL: the dry run kept something: %', v_x;
  end if;
  v_r := cmd.armada_sail(v_arm, 'FNC', v_path, true);
  v_lead := (select v.id from public.voyages v where v.fleet_id = v_f1 and v.status = 'SAILING');
  v_sis := (select v.id from public.voyages v where v.fleet_id = v_f2 and v.status = 'SAILING');
  if not coalesce((v_r ->> 'ok')::boolean, false) or v_lead is null or v_sis is null or (v_r ->> 'lead_voyage_id')::uuid <> v_lead
     or (v_r ->> 'cost')::bigint <> (v_x ->> 'cost')::bigint or (v_r ->> 'speed_kn') <> (v_x ->> 'speed_kn') or (v_r ->> 'cost')::bigint < 0
     or 800000 - (select p.ducats from public.players p where p.id = v_a) + (v_r ->> 'on_credit')::bigint <> (v_r ->> 'cost')::bigint
     or (select count(distinct (v.path::text, v.speed_profile::text, v.eta, v.departed_at, v.total_nm, v.dest_port_id)) from public.voyages v where v.id in (v_lead, v_sis)) <> 1
     or (select (v.speed_profile ->> 0)::numeric from public.voyages v where v.id = v_lead) <> voyage.fleet_speed_alone_at(v_f2, null)
     or (select count(*) from public.armada_voyages av where av.lead_voyage_id = v_lead and av.armada_id = v_arm) <> 2
     or (select count(*) from public.insured_voyages i where i.voyage_id in (v_lead, v_sis) and i.value > 0) <> 2
     or (select i.value from public.insured_voyages i where i.voyage_id = v_lead) <> 40 * 25 + 9 * 100 or (select i.value from public.insured_voyages i where i.voyage_id = v_sis) <> 21 * 25
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'DEPARTED') <> 2
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'ARMADA_SAILED') <> 1
     or world.armadas() -> 'armadas' -> 0 ->> 'state' <> 'SEA' then
    raise exception 'PROOF 68 FAIL: the armada did not leave as one: % (dry %)', v_r, v_x;
  end if;
  if cmd.divert(v_f2, v_lis, null, null) ->> 'error_code' is distinct from 'E_IN_ARMADA' then
    raise exception 'PROOF 68 FAIL: a fleet of an armada turned alone';
  end if;
  raise notice 'PASS: ARMADA_SAILS_AS_ONE — refused whole under the refused fleet''s name; the dry run kept nothing and quoted % d.; the order left both fleets on one path at % kn (the slower fleet''s), one arrival, each insured on her own hold',
    v_r ->> 'cost', v_r ->> 'speed_kn';

  -- ══ ARMADA_SAME_SEA ══ (the real roll, 0367's body, under the name the stub left it)
  v_days := voyage.total_days(v_lead);
  for d in 1 .. greatest(v_days, 8) loop
    if (select to_jsonb(x) from voyage.hazard_roll_real_68(v_sis, d) x) is distinct from (select to_jsonb(x) from voyage.hazard_roll_real_68(v_lead, d) x)
       or (select to_jsonb(x) from voyage.hazard_roll_real_68(v_lead, d) x) is distinct from (select to_jsonb(x) from pg_temp.hazard_roll_old_68(v_lead, d) x) then
      raise exception 'PROOF 68 FAIL: day % is not the lead''s day for her sister, or the lead''s own roll moved', d;
    end if;
  end loop;
  raise notice 'PASS: ARMADA_SAME_SEA — % days: the sister rolls the lead''s day, and the lead rolls what she always rolled', greatest(v_days, 8);

  -- ══ ARMADA_RAID_ONE_SIDE and ARMADA_PLUNDER_BY_HOLD ══
  -- The passage is lengthened to 10 days of a sea whose danger is written on the leg (0.6: one fleet alone draws 0.6 x 40 x (0.5 + 0.5) = 24), the same for both voyages, so a raid
  -- day that takes cargo can be CHOSEN: the engine is asked, as the armada's side stands, which day it would plunder (it is a pure function of the lead voyage, the day and the side).
  v_speed := (select (v.speed_profile ->> 0)::numeric from public.voyages v where v.id = v_lead);
  update public.voyages v
     set path = (select jsonb_agg(e.value || jsonb_build_object('danger', 0.6) order by e.ord) from jsonb_array_elements(pg_temp.through(v_speed, v_sea, 10)) with ordinality e(value, ord)),
         speed_profile = (select jsonb_agg(v_speed) from generate_series(1, 10)), total_nm = v_speed * 24 * 10,
         eta = v.departed_at + make_interval(secs => (10 * 24 * 3600 / public.wc_num('time_compression'))::double precision)
   where v.id in (v_lead, v_sis);
  v_one := voyage.leg_danger(voyage.leg_at_day(v_lead, 1)) * 40 * (0.5 + 0.5);
  if v_one <> 24 then
    raise exception 'PROOF 68 FAIL: one fleet would draw % and not 24 on this leg', v_one;
  end if;
  v_side := voyage.armada_side(v_lead);
  if (v_side ->> 'n')::int <> 2 or jsonb_array_length(v_side -> 'ships') <> 2 or v_side -> 'fleets' <> '[["Capitania 68", 1], ["Almiranta 68", 1]]'::jsonb
     or (v_side ->> 'escort')::numeric <> voyage.escort_score(v_f1) + voyage.escort_score(v_f2)
     or (v_side -> 'ships')::text <> (voyage.fleet_hulls(v_f1) || voyage.fleet_hulls(v_f2))::text then
    raise exception 'PROOF 68 FAIL: the armada''s side is not both fleets'' hulls, the flagship fleet first: %', v_side;
  end if;
  for d in 2 .. 9 loop
    v_pred := voyage.raid_report(v_lead, d, v_one * 2, (v_side ->> 'escort')::numeric, v_side -> 'ships', voyage.raid_opts(v_lead, d, v_f1));
    if v_pred ->> 'outcome' in ('PLUNDERED', 'STRIPPED') then
      v_day := d;
      exit;
    end if;
  end loop;
  if v_day is null then
    raise exception 'PROOF 68 FAIL: no day of 8 would take cargo from two barcas against 48 of raiders; the last read %', v_pred ->> 'outcome';
  end if;
  select jsonb_object_agg(s.id::text, s.durability) into v_hull from public.ships s where s.fleet_id in (v_f1, v_f2);
  select jsonb_object_agg(s.fleet_id::text, s.cargo) into v_hold from public.ships s where s.fleet_id in (v_f1, v_f2);
  -- the days before are quiet; the chosen day is the raid. THE SISTER IS SETTLED FIRST: she fights the fight and keeps it.
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform set_config('byeharu.proof_day', v_day::text, true);
  perform voyage.settle(v_f2, voyage.day_ends_at(v_sis, v_day));
  select e.payload into v_p2 from public.voyage_events e where e.voyage_id = v_sis and e.day_index = v_day and e.kind = 'PIRATES';
  if v_p2 is null or (select s.cargo from public.ships s where s.fleet_id = v_f1) is distinct from (v_hold -> v_f1::text)
     or (select s.durability from public.ships s where s.fleet_id = v_f1) is distinct from (select (v_hull ->> s.id::text)::numeric from public.ships s where s.fleet_id = v_f1)
     or exists (select 1 from public.voyage_events e where e.voyage_id = v_lead) then
    raise exception 'PROOF 68 FAIL: the sister''s raid day is not there, or settling her touched the lead fleet: %', v_p2;
  end if;
  perform voyage.settle(v_f1, voyage.day_ends_at(v_lead, v_day));
  select e.payload into v_p1 from public.voyage_events e where e.voyage_id = v_lead and e.day_index = v_day and e.kind = 'PIRATES';
  perform set_config('byeharu.proof_sea', '', true);
  perform set_config('byeharu.proof_day', '', true);
  select g.answer into v_ans from public.armada_fights g where g.voyage_id = v_lead and g.day = v_day;
  if v_p1 is null or v_ans is null or (select count(*) from public.armada_fights) <> 1
     or exists (select 1 from public.voyage_events e where e.voyage_id in (v_lead, v_sis) and e.kind = 'PIRATES' and e.day_index <> v_day) then
    raise exception 'PROOF 68 FAIL: the raid day was not fought once and kept once';
  end if;
  if v_p1 ->> 'outcome' <> v_pred ->> 'outcome' or v_p2 ->> 'outcome' <> v_pred ->> 'outcome'
     or (v_p1 ->> 'raider')::numeric <> v_one * 2 or (v_p2 ->> 'raider')::numeric <> v_one * 2
     or (v_p1 ->> 'escort')::numeric <> round((v_side ->> 'escort')::numeric, 2) or (v_p2 ->> 'escort')::numeric <> (v_p1 ->> 'escort')::numeric
     or v_p1 -> 'rounds' is distinct from v_p2 -> 'rounds' or v_p1 -> 'rounds' is distinct from v_pred -> 'rounds'
     or v_p1 -> 'fight' -> 'log' is distinct from v_p2 -> 'fight' -> 'log'
     or (v_p1 -> 'fight' -> 'log') - 'fleets' is distinct from v_pred -> 'log'
     or v_p1 -> 'fight' -> 'log' -> 'fleets' <> '[["Capitania 68", 1], ["Almiranta 68", 1]]'::jsonb
     or jsonb_array_length(v_p1 -> 'fight' -> 'log' -> 'you') <> 2
     or v_ans -> 'fight' -> 'hull_lost' is distinct from v_pred -> 'hull_lost' then
    raise exception 'PROOF 68 FAIL: both fleets'' days are not the one fight the engine fights for that side: lead % sister % engine %', v_p1, v_p2, v_pred;
  end if;
  -- each ship lost exactly what the one fight says for her
  for h in select s.id, s.name, s.durability from public.ships s where s.fleet_id in (v_f1, v_f2) loop
    if h.durability <> greatest(0, (v_hull ->> h.id::text)::numeric - coalesce((v_ans -> 'fight' -> 'hull_lost' ->> h.id::text)::numeric, 0)) then
      raise exception 'PROOF 68 FAIL: % did not lose what the one fight says: % from % less %', h.name, h.durability, v_hull ->> h.id::text, v_ans -> 'fight' -> 'hull_lost' ->> h.id::text;
    end if;
  end loop;
  raise notice 'PASS: ARMADA_RAID_ONE_SIDE — day %: fought once (the sister settled first), 2 hulls of 2 fleets against % of raiders (one fleet alone draws %); both days carry the same fight and log, %; each ship lost what that fight says',
    v_day, v_one * 2, v_one, v_pred ->> 'outcome';
  -- THE PLUNDER, by hold: each fleet her own roll's share of her own goods
  for h in select x.fl, x.voy, x.p, x.who from (values (v_f1, v_lead, v_p1, 'the lead'), (v_f2, v_sis, v_p2, 'the sister')) x(fl, voy, p, who) loop
      if (select jsonb_object_agg(k.key, case when voyage.plunder_share(h.voy, v_day, h.p ->> 'outcome') >= 1 then (k.value)::text::numeric
                                              else floor((k.value)::text::numeric * voyage.plunder_share(h.voy, v_day, h.p ->> 'outcome')) end)
            from jsonb_each(v_hold -> h.fl::text) k
           where case when voyage.plunder_share(h.voy, v_day, h.p ->> 'outcome') >= 1 then (k.value)::text::numeric
                      else floor((k.value)::text::numeric * voyage.plunder_share(h.voy, v_day, h.p ->> 'outcome')) end > 0)
         is distinct from h.p -> 'cargo_lost' then
        raise exception 'PROOF 68 FAIL: % did not lose her own roll''s share of her own hold: % of %', h.who, h.p -> 'cargo_lost', v_hold -> h.fl::text;
      end if;
      if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'INSURANCE_PAID' and (e.payload ->> 'voyage_id')::uuid = h.voy and e.payload -> 'lost' = h.p -> 'cargo_lost') <> 1 then
        raise exception 'PROOF 68 FAIL: %''s insurance did not pay for her own loss', h.who;
      end if;
  end loop;
  if v_p1 -> 'cargo_lost' is null or v_p2 -> 'cargo_lost' is null or not (v_p1 -> 'cargo_lost' ? v_ga) or not (v_p2 -> 'cargo_lost' ? v_ga) or (v_p2 -> 'cargo_lost' ? v_gb) then
    raise exception 'PROOF 68 FAIL: the raiders did not take from both holds, each her own goods: % / %', v_p1 -> 'cargo_lost', v_p2 -> 'cargo_lost';
  end if;
  raise notice 'PASS: ARMADA_PLUNDER_BY_HOLD — the lead lost % of %, the sister % of %: each her own roll''s share of her own hold, each paid by her own insurance',
    v_p1 -> 'cargo_lost', v_hold -> v_f1::text, v_p2 -> 'cargo_lost', v_hold -> v_f2::text;

  -- ══ ARMADA_ARRIVES_DISBANDS ══
  loop
    select v.eta into v_eta from public.voyages v where v.id = v_lead and v.status = 'SAILING';
    exit when v_eta is null;
    perform voyage.settle(v_f1, v_eta);
    perform voyage.settle(v_f2, v_eta);
  end loop;
  -- UNDER ANY DICE: a fleet whose flagship the raid left with no hull makes the port all the same and lies there unable to sail (voyage.settle's own rule), so both are read
  if (select count(*) from public.fleets f where f.id in (v_f1, v_f2) and f.status in ('DOCKED', 'UNABLE_TO_SAIL') and f.port_id = v_fnc) <> 2
     or (select count(distinct v.eta) from public.voyages v where v.id in (v_lead, v_sis) and v.status = 'ARRIVED') <> 1
     or (select count(*) from public.voyages v where v.id in (v_lead, v_sis) and v.status = 'ARRIVED') <> 2 then
    raise exception 'PROOF 68 FAIL: the two fleets did not make Funchal at one instant';
  end if;
  -- the raid's dead are replaced and its damage made good (straight, as a yard would), so the next order is judged on the passage alone
  update public.ships s set crew = c.crew_required, durability = (select b.durability from public.ship_base(s.id) b)
    from public.ship_classes c where c.id = s.class_id and s.fleet_id in (v_f1, v_f2);
  update public.fleets set ready_at = null, status = 'DOCKED' where id in (v_f1, v_f2);
  v_r := world.armadas() -> 'armadas' -> 0;
  if v_r ->> 'state' <> 'PORT' or v_r ->> 'port' <> 'FNC' then
    raise exception 'PROOF 68 FAIL: the armada does not read PORT at Funchal: %', v_r;
  end if;
  v_x := cmd.preview_armada_sail(v_arm, 'LIS', (select jsonb_build_array(v_path -> 1, v_path -> 0)), false);
  if not coalesce((v_x ->> 'ok')::boolean, false) then
    raise exception 'PROOF 68 FAIL: the armada cannot be sent again from Funchal: %', v_x;
  end if;
  v_r := cmd.armada_disband(v_arm);
  if not coalesce((v_r ->> 'ok')::boolean, false) or exists (select 1 from public.armadas) or exists (select 1 from public.armada_fleets)
     or voyage.fleet_speed(v_f1) <> voyage.fleet_speed_alone_at(v_f1, null)
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'ARMADA_DISBANDED') <> 1 then
    raise exception 'PROOF 68 FAIL: the armada was not disbanded: %', v_r;
  end if;
  v_r := cmd.issue(v_f1, 'SAIL TO LIS', null, (select jsonb_build_array(v_path -> 1, v_path -> 0)));
  if not coalesce((v_r ->> 'ok')::boolean, false) or (select f.status from public.fleets f where f.id = v_f1) <> 'SAILING' or (select f.status from public.fleets f where f.id = v_f2) <> 'DOCKED'
     or exists (select 1 from public.armada_voyages av join public.voyages v on v.id = av.voyage_id where v.fleet_id = v_f1 and v.status = 'SAILING') then
    raise exception 'PROOF 68 FAIL: disbanded, the fleet does not sail alone: %', v_r;
  end if;
  raise notice 'PASS: ARMADA_ARRIVES_DISBANDS — both fleets made Funchal at one instant; the armada read PORT there and could be sent again; disbanded, the lead fleet sailed alone and her sister stayed';

  -- ══ ARMADA_OF_SIX ══ (the owner's number: with room for seven fleets, seven is refused and six sail as one)
  update public.world_config set value = to_jsonb(7) where key in ('fleet_max', 'fleet_hard_max');   -- fleet_hard_max too: since 0370 fleet room is lit and that knob is the top (unread while dark)
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_uc, 'Casa dos Seis 68', v_prt, 800000, false) returning id into v_c;
  v_six := '{}';
  for i in 1 .. 7 loop
    v_six := v_six || public.form_fleet(v_c, 'Frota ' || i || ' 68', v_lis);
    perform public.commission_ship(v_c, v_six[i], 'barca', 'Nau ' || i || ' 68', true, true);
  end loop;
  perform pg_temp.as_house(c_uc);
  if cmd.armada_form(to_jsonb(v_six), 'Sete 68') ->> 'error_code' is distinct from 'E_ARMADA_SIZE' then
    raise exception 'PROOF 68 FAIL: seven fleets formed an armada';
  end if;
  -- a name she already uses is taken, whatever its case; a company keeps several armadas
  v_r := cmd.armada_form(to_jsonb(v_six[1:2]), 'Dupla 68');
  v_x := cmd.armada_form(to_jsonb(v_six[3:4]), 'DUPLA 68');
  v_ans := cmd.armada_form(to_jsonb(v_six[3:4]), 'Outra Dupla 68');
  if not coalesce((v_r ->> 'ok')::boolean, false) or v_x ->> 'error_code' is distinct from 'E_NAME_TAKEN'
     or not coalesce((v_ans ->> 'ok')::boolean, false)
     or jsonb_array_length(world.armadas() -> 'armadas') <> 2 then
    raise exception 'PROOF 68 FAIL: a taken name was not refused, or a company could not keep two armadas: % / % / %', v_r, v_x, v_ans;
  end if;
  perform cmd.armada_disband((a.value ->> 'id')::uuid) from jsonb_array_elements(world.armadas() -> 'armadas') a;
  if exists (select 1 from public.armadas x where x.player_id = v_c) then
    raise exception 'PROOF 68 FAIL: the two armadas were not disbanded';
  end if;
  v_r := cmd.armada_form(to_jsonb(v_six[1:6]), 'Armada Real 68');   -- the name another company used: names are a company's own
  v_arm := (v_r ->> 'armada_id')::uuid;
  if v_arm is null or jsonb_array_length(world.armadas() -> 'armadas' -> 0 -> 'fleets') <> 6 then
    raise exception 'PROOF 68 FAIL: six fleets did not form an armada: %', v_r;
  end if;
  v_r := cmd.armada_sail(v_arm, 'FNC', v_path, false);
  v_lead := (v_r ->> 'lead_voyage_id')::uuid;
  if not coalesce((v_r ->> 'ok')::boolean, false) or jsonb_array_length(v_r -> 'voyages') <> 6
     or (select count(distinct (v.path::text, v.speed_profile::text, v.eta)) from public.voyages v where v.player_id = v_c and v.status = 'SAILING') <> 1
     or (select f.status from public.fleets f where f.id = v_six[7]) <> 'DOCKED' then
    raise exception 'PROOF 68 FAIL: six fleets did not leave as one: %', v_r;
  end if;
  v_ans := voyage.armada_fight((select v.id from public.voyages v where v.fleet_id = v_six[4] and v.status = 'SAILING'), 1, v_six[4], null, 10);
  if (v_ans ->> 'fleets')::int <> 6 or (v_ans ->> 'raider')::numeric <> 60 or jsonb_array_length(v_ans -> 'fight' -> 'log' -> 'you') <> 6
     or jsonb_array_length(v_ans -> 'fight' -> 'log' -> 'fleets') <> 6 or v_ans -> 'fight' -> 'log' -> 'fleets' -> 0 ->> 0 <> 'Frota 1 68' then
    raise exception 'PROOF 68 FAIL: six fleets are not one side against six times the raiders: %', v_ans;
  end if;
  raise notice 'PASS: ARMADA_OF_SIX — seven refused, six formed and sailed on one schedule; a raid day: 6 hulls of 6 fleets on one side against % (10 for one fleet), %', v_ans ->> 'raider', v_ans -> 'fight' ->> 'outcome';
  perform pg_temp.as_house(null);
end
$$;
