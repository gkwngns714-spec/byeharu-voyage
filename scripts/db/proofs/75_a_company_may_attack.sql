-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 75 — A COMPANY MAY ATTACK  (migration 0375: attack_enabled is lit; owner row 324; docs/COMBAT_LOG.md 3.6)
--
--   0375's self-assert reads the switch, the catalog and two refusals on a rolled-back probe. This proof plays what the light opens, on the chain as 0375 leaves it, through the
--   CLIENT'S OWN DOORS (cmd.preview_attack, cmd.attack, cmd.battle_stance, world.battle, world.fights) and the real minute job (public.tick_battles), with the switches production
--   has lit (the armed cargo ship, the navy, regard, crown hulls at their level) lit here too. The economy is closed, as on prod. Rolled back by the runner.
--   EVERY BUILT WORLD HAS ITS OWN DICE (0031): nothing here assumes how a fight goes. scripts/ops/harness/attacks/proof-0375.mjs --proofs runs it under ten other worlds' dice.
--
-- @pass LIT_BY_THE_FILE     the chain as 0375 leaves it: attack_enabled is on, the news row is there once in English and Korean, and no battle, round or WANTED row exists
-- @pass LIT_A_BATTLE        a company's whole battle through the client's doors and the minute job: the read before the press, the press, six rounds logged a minute apart, the close at the clock, the report, the regard that fell, gold by 0374's rule, every purse summed 0, both fleets free
-- @pass LIT_AFTER_CHECK     the seven lines of the after-check hold on that battle: none FIGHTING past its clock, the logged rounds are a re-run of the sheet, LOOT in the ledger = the result = the report and under the caps, no fleet left IN_BATTLE or busy, and the held cargo ship arrives having settled the days of a voyage never held
-- @pass LIT_NO_PVP          lit, the press on another player's fleet is refused (E_HUMAN_TARGET), on a ship of her own country (E_YOUR_OWN_COUNTRY), with no guns (E_NO_GUNS), and nothing is opened
-- @pass LIT_SWITCH_OFF      the rollback: attack_enabled false refuses a new press (E_NOT_IN_USE) and a battle already being fought still closes by the job and pays; on again, the door opens
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── LIT_BY_THE_FILE: before this proof touches anything ──
do $$
declare
  v_en text := (select n.detail #>> '{words,title,en}' from public.world_news n where n.key = 'update:0375');
  v_ko text := (select n.detail #>> '{words,title,ko}' from public.world_news n where n.key = 'update:0375');
begin
  if not public.attack_on() or public.wc('attack_enabled') is distinct from 'true'::jsonb then
    raise exception 'PROOF 75 FAIL: attack_enabled is not on in the chain as 0375 leaves it';
  end if;
  if (select count(*) from public.world_news n where n.key = 'update:0375') <> 1 or coalesce(v_en, '') = '' or coalesce(v_ko, '') = '' or v_en = v_ko then
    raise exception 'PROOF 75 FAIL: the news row of 0375 is not there once in both languages: % / %', v_en, v_ko;
  end if;
  if exists (select 1 from public.battles) or exists (select 1 from public.battle_rounds) or exists (select 1 from public.wanted) then
    raise exception 'PROOF 75 FAIL: a battle, a round or a WANTED row exists before anyone attacked';
  end if;
  raise notice 'PASS: LIT_BY_THE_FILE — attack_enabled on; the news row once ("%" / "%"); no battle, round or WANTED row', v_en, v_ko;
end $$;

do $$
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite', 'convoy_armed_enabled', 'navy_enabled', 'regard_enabled', 'npc_ship_level_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'pirates_bite', 'raid_orders_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports set crew_pool = 5000;

  -- THE SEA IS QUIET: the battle is the only thing that rolls, and a voyage's days are its own
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_75;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  execute $f$
create function pg_temp.purses()
returns bigint language sql as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  -- a human company: her one fleet of p_ships hulls of p_class, full complements, her hold empty. Answers her auth uid's fleet.
  execute $f$
create function pg_temp.house_75(p_n int, p_nation text, p_port text, p_class text, p_ships int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0375-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Luz ' || p_n, p_nation, p_port, 'Luz ' || p_n, p_class, 'Luz ' || p_n, null, false);
  v_f   uuid;
  i     int;
begin
  select id into v_f from public.fleets where player_id = v_p;
  for i in 2 .. p_ships loop
    perform public.commission_ship(v_p, v_f, p_class, 'Luz ' || p_n || '.' || i, false, true);
  end loop;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  execute $f$
create function pg_temp.ship_75(p_ducats bigint, p_at timestamptz, p_nation text)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null and n.code = p_nation and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 75 FAIL: no cargo ship of % left to sail', p_nation;
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  if public.cargo_ship_step(c.fleet_id, p_at) <> 'SAILED' then
    raise exception 'PROOF 75 FAIL: the cargo ship did not sail';
  end if;
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  execute $f$
create function pg_temp.lie_by(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;
end $$;

-- ── LIT_A_BATTLE + LIT_AFTER_CHECK ──
do $$
declare
  t0     timestamptz := now();
  v_es   uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_cap  uuid;
  v_f    uuid;
  v_p    uuid;
  v_d    uuid;
  v_uid  uuid := '00000000-0375-4000-8000-000000000001';
  v_was  bigint;
  v_sum  bigint;
  v_pre  jsonb;
  v_hit  jsonb;
  v_b    uuid;
  v_rd   jsonb;
  v_res  jsonb;
  v_want bigint;
  v_voy  public.voyages%rowtype;
  v_free numeric;
  v_sim  numeric;
  g      int;
  v_n    int;
  v_rep  jsonb;
begin
  v_cap := public.realm_capital(v_es);
  for g in 1 .. 2 loop perform public.tick_cargo_ships(t0, v_es); end loop;
  insert into public.navy_realms (nation_id, ships, read_at) values (v_es, 25, t0) on conflict (nation_id) do update set ships = 25, read_at = t0;
  perform public.navy_commission(v_es, 1, v_cap, public.refit_yard(v_cap), v_cap, t0);
  update public.ships s set crew = k.crew_required from public.ship_classes k, public.navy_ships n where k.id = s.class_id and n.fleet_id = s.fleet_id;
  perform public.crown_hull_level_fix();
  if not (public.attack_ready() ->> 'ready')::boolean or not (public.attack_ready() ->> 'lived')::boolean then
    raise exception 'PROOF 75 FAIL: this world is lit as production will be and public.attack_ready says %', public.attack_ready();
  end if;

  v_f := pg_temp.house_75(1, 'PRT', 'LIS', 'galion', 2);
  v_p := (select f.player_id from public.fleets f where f.id = v_f);
  v_d := pg_temp.ship_75(400000, t0, 'ESP');
  perform pg_temp.lie_by(v_f, v_d, t0);
  v_was := (select pl.ducats from public.players pl where pl.id = v_p);
  v_sum := pg_temp.purses();
  perform cmd.assume_identity(v_uid);

  -- the read before the press: words, never a figure; it writes nothing
  v_pre := cmd.preview_attack(v_f, v_d);
  if not (v_pre ->> 'ok')::boolean or v_pre #>> '{estimate,word}' not in ('weaker', 'even', 'stronger', 'far_stronger') or v_pre #>> '{estimate,funds}' not in ('none', 'light', 'heavy')
     or exists (select 1 from public.battles) or (select f.status from public.fleets f where f.id = v_f) <> 'ANCHORED' then
    raise exception 'PROOF 75 FAIL: the preview: % (battles %)', v_pre, (select count(*) from public.battles);
  end if;
  -- the press
  v_hit := cmd.attack(v_f, v_d, null);
  if not (v_hit ->> 'ok')::boolean or v_hit ->> 'word' is distinct from v_pre #>> '{estimate,word}' then
    raise exception 'PROOF 75 FAIL: the press: % (the preview said %)', v_hit, v_pre;
  end if;
  v_b := (v_hit ->> 'battle_id')::uuid;
  t0 := (select b.started_at from public.battles b where b.id = v_b);
  if (select f.status from public.fleets f where f.id = v_f) <> 'IN_BATTLE' or (select f.busy_until from public.fleets f where f.id = v_d) is null
     or (select b.resolves_at - b.started_at from public.battles b where b.id = v_b) <> interval '420 seconds'
     or public.regard_of(v_p, v_es) > (public.wc('regard_stance_base') ->> public.power_stance((select pl.nation_id from public.players pl where pl.id = v_p), v_es))::numeric - 149 then
    raise exception 'PROOF 75 FAIL: after the press: her fleet %, the target busy until %, the clock %, her regard %', (select f.status from public.fleets f where f.id = v_f),
      (select f.busy_until from public.fleets f where f.id = v_d), (select b.resolves_at - b.started_at from public.battles b where b.id = v_b), public.regard_of(v_p, v_es);
  end if;
  -- her card and the map's ring read it
  v_rd := world.battle(v_f);
  if not (v_rd ->> 'on')::boolean or v_rd ->> 'status' <> 'FIGHTING' or v_rd -> 'may' <> '["FIGHT", "FLEE"]'::jsonb or (v_rd ->> 'rounds_done')::int <> 0
     or not exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_b::text and e ->> 'mine' = v_f::text) then
    raise exception 'PROOF 75 FAIL: her card or the ring: % / %', v_rd - 'log', world.fights();
  end if;
  -- THE MINUTE JOB, minute by minute: a round a minute, never two, never one early
  for g in 1 .. 6 loop
    perform public.tick_battles(t0 + make_interval(secs => g * 60 - 1));
    if (select count(*) from public.battle_rounds r where r.battle_id = v_b) > g - 1 and (select b.status from public.battles b where b.id = v_b) = 'FIGHTING' then
      raise exception 'PROOF 75 FAIL: round % was fought a second early', g;
    end if;
    perform public.tick_battles(t0 + make_interval(secs => g * 60));
    exit when (select b.status from public.battles b where b.id = v_b) <> 'FIGHTING';
    if (select count(*) from public.battle_rounds r where r.battle_id = v_b) <> g then
      raise exception 'PROOF 75 FAIL: after minute % the log holds % round(s)', g, (select count(*) from public.battle_rounds r where r.battle_id = v_b);
    end if;
  end loop;
  perform public.tick_battles(t0 + interval '420 seconds');
  perform public.tick_battles(t0 + interval '480 seconds');   -- a retry: it closes once
  v_res := (select b.result from public.battles b where b.id = v_b);
  if (select b.status from public.battles b where b.id = v_b) = 'FIGHTING' or v_res is null then
    raise exception 'PROOF 75 FAIL: the job did not close the battle at its clock';
  end if;
  -- gold by 0374's rule, moved
  v_want := public.loot_due(v_res ->> 'outcome', floor(400000 * public.loot_risk(v_res))::bigint, 0);
  if (select pl.ducats from public.players pl where pl.id = v_p) - v_was <> v_want or (v_res ->> 'loot')::bigint <> v_want or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 75 FAIL: %: she took %, the result says %, the rule %; every purse summed moved %', v_res ->> 'outcome',
      (select pl.ducats from public.players pl where pl.id = v_p) - v_was, v_res ->> 'loot', v_want, pg_temp.purses() - v_sum;
  end if;
  -- the report, once, with its log; her card closed
  select count(*), max(e.payload::text)::jsonb into v_n, v_rep from public.events e where e.player_id = v_p and e.kind = 'BATTLE_REPORT';
  v_rd := world.battle(v_f);
  if v_n <> 1 or (v_rep ->> 'loot')::bigint <> v_want or v_rep #> '{fights,0,log}' is null or v_rd ->> 'status' = 'FIGHTING' or (v_rd ->> 'loot')::bigint <> v_want
     or (select count(*) from public.events e where e.player_id = v_p and e.kind = 'REGARD_CHANGED') < 1 then
    raise exception 'PROOF 75 FAIL: the report (% of them): %; her card %', v_n, v_rep - 'fights', v_rd - 'log';
  end if;
  raise notice 'PASS: LIT_A_BATTLE — two galleons on an armed cargo ship with 400,000 aboard, through cmd.preview_attack, cmd.attack, world.battle, world.fights and the minute job: % after % round(s), she took % (her share %), every purse summed 0; one report with its log; her regard with Spain %',
    v_res ->> 'outcome', v_res ->> 'rounds_fought', v_want, round(public.loot_risk(v_res), 3), round(public.regard_of(v_p, v_es));

  -- ── THE AFTER-CHECK'S SEVEN LINES, on this battle ──
  if exists (select 1 from public.battles b where b.status = 'FIGHTING') then
    raise exception 'PROOF 75 FAIL: a battle is FIGHTING past its clock';
  end if;
  if (select coalesce(jsonb_agg(r."row" order by r.g), '[]'::jsonb) from public.battle_rounds r where r.battle_id = v_b) is distinct from public.battle_fight(v_b, null) -> 'rounds'
     or v_res -> 'rounds' is distinct from public.battle_fight(v_b, null) -> 'rounds' or v_res ->> 'outcome' is distinct from public.battle_fight(v_b, null) ->> 'outcome' then
    raise exception 'PROOF 75 FAIL: the logged rounds are not a re-run of the sheet';
  end if;
  if (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'LOOT') <> v_want
     or v_want > public.wc_num('loot_per_ship') or public.loot_today(v_p, t0 + interval '480 seconds') > public.wc_num('loot_per_company_day') then
    raise exception 'PROOF 75 FAIL: LOOT in the ledger is not the result''s, or a cap is passed';
  end if;
  if exists (select 1 from public.fleets f join public.battle_sides bs on bs.fleet_id = f.id where bs.battle_id = v_b and (f.status = 'IN_BATTLE' or f.busy_until is not null))
     or exists (select 1 from public.navy_ships n where n.battle_id = v_b) then
    raise exception 'PROOF 75 FAIL: a fleet is left IN_BATTLE or busy, or a navy ship tied, after the battle closed';
  end if;
  -- the held cargo ship sails on at her own speed and arrives: the days of a voyage never held (unless she was sunk and sent home a wreck, which is another voyage)
  select * into v_voy from public.voyages v where v.fleet_id = v_d and v.status = 'SAILING';
  if v_voy.id is not null then
    v_free := voyage.hold_free_hours(v_voy.id);
    update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric * 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o)) where vo.id = v_voy.id;
    perform voyage.recompute_eta(v_voy.id);
    perform voyage.settle(v_d, t0 + interval '2 days');
    select * into v_voy from public.voyages v where v.id = v_voy.id;
    v_sim := voyage.sim_hours(v_voy.id);
    if v_free <= 0 or v_voy.status <> 'ARRIVED' or v_voy.last_settled_day <> greatest(1, ceil((v_sim + greatest(0, v_voy.delay_hours - voyage.hold_free_hours(v_voy.id))) / 24)::int)
       or voyage.total_days(v_voy.id) <> v_voy.last_settled_day then
      raise exception 'PROOF 75 FAIL: the held voyage: % after % day(s), sim % h, delay % h of which free % h', v_voy.status, v_voy.last_settled_day, v_sim, v_voy.delay_hours, voyage.hold_free_hours(v_voy.id);
    end if;
  end if;
  raise notice 'PASS: LIT_AFTER_CHECK — none FIGHTING past its clock; the % logged round(s) are the re-run of the sheet; LOOT in the ledger % = the result = the report, under both caps; no fleet IN_BATTLE or busy, no navy ship tied; the held cargo ship %',
    (select count(*) from public.battle_rounds r where r.battle_id = v_b), v_want,
    case when v_voy.id is null then 'was sunk (no held voyage to read)' else format('arrived after %s day(s), the days of a voyage never held (%s h of hold were free)', v_voy.last_settled_day, round(v_free, 1)) end;
end $$;

-- ── LIT_NO_PVP ──
do $$
declare
  t0    timestamptz := now() + interval '1 day';
  v_f   uuid := pg_temp.house_75(2, 'PRT', 'LIS', 'galion', 1);
  v_h   uuid := pg_temp.house_75(3, 'ESP', 'SVQ', 'galion', 1);
  v_own uuid := pg_temp.house_75(4, 'ESP', 'SVQ', 'galion', 1);
  v_gun uuid := pg_temp.house_75(5, 'PRT', 'LIS', 'barca', 1);
  v_es  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_d   uuid;
  v_n   int := (select count(*) from public.battles);
  r     jsonb;
begin
  perform public.tick_cargo_ships(t0, v_es);
  v_d := pg_temp.ship_75(100000, now(), 'ESP');
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon from voyage.fleet_point(v_d, now()) p where f.id in (v_f, v_h, v_own, v_gun);
  perform cmd.assume_identity('00000000-0375-4000-8000-000000000002');
  r := cmd.attack(v_f, v_h, null);
  if (r ->> 'ok')::boolean or r ->> 'error_code' <> 'E_HUMAN_TARGET' or (cmd.preview_attack(v_f, v_h) ->> 'error_code') <> 'E_HUMAN_TARGET' then
    raise exception 'PROOF 75 FAIL: another player''s fleet: %', r;
  end if;
  perform cmd.assume_identity('00000000-0375-4000-8000-000000000004');
  r := cmd.attack(v_own, v_d, null);
  if (r ->> 'ok')::boolean or r ->> 'error_code' <> 'E_YOUR_OWN_COUNTRY' then
    raise exception 'PROOF 75 FAIL: a ship of her own country: %', r;
  end if;
  perform cmd.assume_identity('00000000-0375-4000-8000-000000000005');
  r := cmd.attack(v_gun, v_d, null);
  if (r ->> 'ok')::boolean or r ->> 'error_code' <> 'E_NO_GUNS' then
    raise exception 'PROOF 75 FAIL: a fleet with no guns: %', r;
  end if;
  if (select count(*) from public.battles) <> v_n or exists (select 1 from public.fleets f where f.id in (v_f, v_h, v_own, v_gun, v_d) and (f.status = 'IN_BATTLE' or f.busy_until is not null)) then
    raise exception 'PROOF 75 FAIL: a refused press opened a battle or stopped a fleet';
  end if;
  raise notice 'PASS: LIT_NO_PVP — lit: another player''s fleet E_HUMAN_TARGET (the press and the preview), a ship of her own country E_YOUR_OWN_COUNTRY, a fleet with no guns E_NO_GUNS; no battle opened, no fleet stopped';

  -- ── LIT_SWITCH_OFF: the rollback ──
  declare
    v_b   uuid;
    v_p   uuid := (select f.player_id from public.fleets f where f.id = v_f);
    v_was bigint := (select pl.ducats from public.players pl where pl.id = v_p);
    v_st  timestamptz;
    v_res jsonb;
  begin
    perform cmd.assume_identity('00000000-0375-4000-8000-000000000002');
    r := cmd.attack(v_f, v_d, null);
    if not (r ->> 'ok')::boolean then
      raise exception 'PROOF 75 FAIL: the press that should open: %', r;
    end if;
    v_b := (r ->> 'battle_id')::uuid;
    v_st := (select b.started_at from public.battles b where b.id = v_b);
    update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
    perform cmd.assume_identity('00000000-0375-4000-8000-000000000005');
    r := cmd.attack(v_gun, v_d, null);
    if (r ->> 'ok')::boolean or r ->> 'error_code' <> 'E_NOT_IN_USE' or (world.fights() ->> 'on')::boolean is null then
      raise exception 'PROOF 75 FAIL: the switch off: a new press answers %', r;
    end if;
    perform public.tick_battles(v_st + interval '421 seconds');
    v_res := (select b.result from public.battles b where b.id = v_b);
    if (select b.status from public.battles b where b.id = v_b) = 'FIGHTING'
       or (select pl.ducats from public.players pl where pl.id = v_p) - v_was <> public.loot_due(v_res ->> 'outcome', floor(100000 * public.loot_risk(v_res))::bigint, 0)
       or exists (select 1 from public.fleets f where f.id in (v_f, v_d) and (f.status = 'IN_BATTLE' or f.busy_until is not null)) then
      raise exception 'PROOF 75 FAIL: the switch off: the running battle did not close and pay as it would have: %', v_res - 'rounds';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
    perform cmd.assume_identity('00000000-0375-4000-8000-000000000005');
    r := cmd.attack(v_gun, v_d, null);
    if r ->> 'error_code' is not distinct from 'E_NOT_IN_USE' then
      raise exception 'PROOF 75 FAIL: on again, the door still says it is not in use';
    end if;
    raise notice 'PASS: LIT_SWITCH_OFF — attack_enabled false: a new press E_NOT_IN_USE; the battle already being fought closed by the job (%) and paid what it would have; on again, the door answers for itself (%)',
      v_res ->> 'outcome', coalesce(r ->> 'error_code', 'ok');
  end;
end $$;
