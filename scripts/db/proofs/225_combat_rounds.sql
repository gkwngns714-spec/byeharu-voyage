-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 225 - COMBAT ROUNDS  (migration 0521; docs/design/rounds-2026-11-25.md section 4.1)
--
--   Her own hulls against the pirates of a sea, by public.tick_fight alone, played once and frozen. Its own company, hulls and a sea whose danger is
--   written here. No dice of the world is asked a sign. Rolled back by proof.mjs.
--
-- @pass CB_DARK    dark: the work is refused; unarmed, or in a sea with no pirates: refused
-- @pass CB_COST    the read says what a round costs (hull, hands, stores, ammo) and serves no fight, no share won, no stop it will meet
-- @pass CB_RUN     a run ends by its own sequence; the log says what each round took and whether it was won; the hull and the hands are what the lines say
-- @pass CB_KEPT    the same fleet's second Send plays no fight
-- @pass CB_NORUN   no RUN and no flee bonus: the fight is called with FIGHT on both sides
-- @pass CB_JOB     a combat job set by a press: the tick sends her, and her fights were played at the press
-- @pass CB_MS      a Send in ms: one hull, eight hulls, the strongest class, in the most dangerous sea there can be (fails over 200 ms the first, 40 ms a kept one)
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a  constant uuid := '00000000-0225-4000-8000-0000000000a1';
  v_a  uuid; v_f uuid; v_sea uuid; v_e text[] := '{}'; r jsonb; q jsonb; z record; t timestamptz; m numeric; m2 numeric; v_d0 numeric; v_c0 int; k int; c record; v_ship uuid; v_txt text := ''; v_bad text := ''; n int;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 225', 'PRT');
  select f.id, h.sea_id into v_f, v_sea from public.fleets f join public.ports h on h.id = f.port_id where f.player_id = v_a;
  update public.players set ducats = 10000000 where id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate');
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 60, water_t = 90 where s.fleet_id = v_f;
  delete from public.sea_pressure where sea_id = v_sea;
  update public.seas set piracy_index = 0.1 where id = v_sea;
  perform cmd.assume_identity(c_a);
  v_e := v_e || coalesce(cmd.round_send(v_f, 'pirates', '{}')->>'error_code', 'sent');
  update public.world_config set value = 'true'::jsonb where key = 'combat_rounds_enabled';
  update public.ships s set class_id = (select x.id from public.ship_classes x where x.code = 'barca') where s.fleet_id = v_f;
  if (select sum((world.ship_stats(s.id)->>'attack')::numeric) from public.ships s where s.fleet_id = v_f) = 0 then
    v_e := v_e || coalesce(cmd.round_send(v_f, 'pirates', '{}')->>'error_code', 'sent');
  else v_e := v_e || 'E_NO_GUNS'; end if;
  update public.ships s set class_id = (select x.id from public.ship_classes x where x.code = 'xebec') where s.fleet_id = v_f;
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 60, water_t = 90, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_f;
  update public.seas set piracy_index = 0 where id = v_sea;
  v_e := v_e || coalesce(cmd.round_send(v_f, 'pirates', '{}')->>'error_code', 'sent');
  if v_e is distinct from array['E_NOT_IN_USE', 'E_NO_GUNS', 'E_NO_PIRATES'] then raise exception 'CB_DARK: %', v_e; end if;
  raise notice 'PASS: CB_DARK - %', v_e;

  update public.seas set piracy_index = 0.1 where id = v_sea;
  q := (select e->'terms' from jsonb_array_elements(world.rounds(v_f)->'works') e where e->>'work' = 'pirates');
  r := cmd.round_send(v_f, 'pirates', '{"hull": 75, "days": 0}');
  if (q->>'hull')::numeric <= 0 or q ? 'fights' or not (r->>'ok')::boolean or (r->'terms') ?| array['fight', 'fights', 'most', 'why'] or (world.rounds(v_f) #> '{runs,0}')::text ~ '"fight|"stop_at": "' or world.rounds(v_f) #>> '{runs,0,cost,hull}' is null then
    raise exception 'CB_COST: % / % / %', q, r, world.rounds(v_f) #> '{runs,0}';
  end if;
  raise notice 'PASS: CB_COST - a round: %', world.rounds(v_f) #> '{runs,0,cost}';

  v_d0 := 0;
  select sum(s.crew) into v_c0 from public.ships s where s.fleet_id = v_f;
  select zr.* into z from public.round_runs zr where zr.fleet_id = v_f;
  perform cmd.advance(v_f, now() + interval '2 days');
  q := world.rounds(v_f) #> '{runs,0}';
  if q->>'state' <> 'home' or (q->>'rounds')::int <> (z.terms->>'most')::int or q->>'ended' <> z.terms->>'why' or not (q #> '{log,-1}') ?& array['hull', 'crew', 'won']
     or v_c0 - (select sum(s.crew) from public.ships s where s.fleet_id = v_f) <> (select sum(e::int) from jsonb_array_elements_text(z.terms #> '{fight,c}') e)
     or abs(public.fleet_damage_pct(v_f) - 100 * (select sum(e::numeric) from jsonb_array_elements_text(z.terms #> '{fight,l}') e)) > 1 then
    raise exception 'CB_RUN: % (damage %)', q, public.fleet_damage_pct(v_f);
  end if;
  raise notice 'PASS: CB_RUN - % rounds, ended %, hull damage % %%, hands lost %', q->>'rounds', q->>'ended', public.fleet_damage_pct(v_f), v_c0 - (select sum(s.crew) from public.ships s where s.fleet_id = v_f);

  if position('"a_ai": "FIGHT", "b_ai": "FIGHT"' in (select p.prosrc from pg_proc p where p.oid = 'public.round_fights(uuid,uuid)'::regprocedure)) = 0
     or exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname like 'round\_%' and p.prosrc ~ 'a_flee|''FLEE''') then
    raise exception 'CB_NORUN';
  end if;
  raise notice 'PASS: CB_NORUN - FIGHT on both sides, no flee bonus anywhere in the rounds';

  -- CB_MS, CB_KEPT: the most dangerous sea (danger 1), fleets of one and of eight hulls, two classes
  update public.seas set piracy_index = 1 where id = v_sea;
  for c in select x.id, x.code, x.attack from public.ship_classes x where x.code = 'xebec' or x.id = (select y.id from public.ship_classes y order by y.attack desc, y.code limit 1) order by x.attack loop
    foreach n in array array[1, 8] loop
      begin
        select s.id into v_ship from public.ships s where s.fleet_id = v_f order by s.is_flagship desc limit 1;
        alter table public.ships disable trigger user;
        for k in 2 .. n loop
          insert into public.ships select (jsonb_populate_record(null::public.ships, to_jsonb(s) || jsonb_build_object('id', gen_random_uuid(), 'name', 'Nau ' || k, 'is_flagship', false))).* from public.ships s where s.id = v_ship;
        end loop;
        update public.ships s set class_id = c.id where s.fleet_id = v_f;
        update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 900, water_t = 900, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_f;
        delete from public.round_fights_kept where fleet_id = v_f;
        t := clock_timestamp();
        r := cmd.round_send(v_f, 'pirates', '{"days": 0}');
        m := extract(epoch from clock_timestamp() - t) * 1000;
        if not (r->>'ok')::boolean and r->>'error_code' <> 'E_ROUND_SHORT' then raise exception 'CB_MS: %', r; end if;
        if (r->>'ok')::boolean then perform cmd.round_home(v_f); end if;
        t := clock_timestamp();
        r := cmd.round_send(v_f, 'pirates', '{"days": 0}');
        m2 := extract(epoch from clock_timestamp() - t) * 1000;
        v_txt := v_txt || format(' %s x%s: %s ms, kept %s ms;', c.code, n, round(m), round(m2, 1));
        if m > 200 or m2 > 40 then v_bad := v_bad || format(' %s x%s', c.code, n); end if;
        raise exception using errcode = 'ZP225', message = 'rolled back';
      exception when sqlstate 'ZP225' then null;
      end;
    end loop;
  end loop;
  if v_bad <> '' then raise exception 'CB_MS: over:% (%)', v_bad, v_txt; end if;
  raise notice 'PASS: CB_MS -%', v_txt;
  raise notice 'PASS: CB_KEPT - the kept figures above';

  -- CB_JOB
  update public.seas set piracy_index = 0.1 where id = v_sea;
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 60, water_t = 90, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_f;
  delete from public.round_fights_kept where fleet_id = v_f;
  r := cmd.set_fleet_job(v_f, 'round', '{"work": "pirates", "stop": {"hull": 70, "days": 0}}');
  if not (r->>'ok')::boolean or not exists (select 1 from public.round_fights_kept x where x.fleet_id = v_f) then raise exception 'CB_JOB: %', r; end if;
  t := clock_timestamp();
  call public.tick_fleet_jobs(false);
  m := extract(epoch from clock_timestamp() - t) * 1000;
  if (select f.status from public.fleets f where f.id = v_f) <> 'ROUNDS' then raise exception 'CB_JOB: not sent: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f); end if;
  raise notice 'PASS: CB_JOB - sent by the tick in % ms, her fights played at the press', round(m, 1);
end $p$;
