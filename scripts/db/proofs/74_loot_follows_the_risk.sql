-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 74 — LOOT FOLLOWS THE RISK TAKEN  (migration 0374; owner row 324; docs/COMBAT_LOG.md 3.6, R11)
--
--   0374's self-assert is the catalog and arithmetic. This proof fights REAL battles: the real door's own function (public.attack_for), the real engine (public.fight_sides, not pinned),
--   the real rounds and the real close (public.battle_resolve -> public.attack_close -> public.loot_take), on probes, rolled back by the runner. The economy is closed, as on prod.
--   EVERY BUILT WORLD HAS ITS OWN DICE (0031's world_secret): nothing here assumes how a fight goes. What is held is what is true of ANY fight:
--     the gold she took = public.loot_due(the outcome, floor(what was aboard x public.loot_risk(the battle's kept result)), what she had taken that day), to the ducat;
--     public.loot_risk = least(1, her own hull lost / her hull at the start / loot_risk_full), read off the kept result by this proof's own arithmetic;
--     a ship with no guns cannot hurt her, so she takes NOTHING from one, whatever the dice.
--   scripts/ops/harness/attacks/run.mjs --proofs=74 --dice=10 runs it under ten other worlds' dice.
--
-- @pass LOOT_RISK_REAL       eight real battles (two galleons and a Nau against the armed cargo ship): each one's gold is the rule's, to the ducat, by the kept result; the report and the ledger say the same; every purse summed moves 0
-- @pass LOOT_RISK_UNARMED    three real battles against the old unarmed cargo ship: the attacker loses no hull and takes nothing, whatever the dice; nothing moves
-- @pass LOOT_RISK_OFF        the same battle closed twice, the rule on and the rule off (loot_risk_full 0): the same fight, and off it pays what 0327 paid
-- @pass LOOT_RISK_CAPS       3,000,000 aboard: never above loot_per_ship; and a company's day never above loot_per_company_day
-- @pass LOOT_RISK_ELSE_SAME  what the rule does not touch: the regard, the hands, the lap and the freed fleets are the same with the rule on and off
-- @pass CALLED_ONCE          a navy ship lying in the harbour nearest the battle when she is called is on the sheet once, from round 1 (0357 froze her at the open and added her again: she fought as two ships)
-- @pass ATTACK_READY         public.attack_ready, the one reading 0375's guard refuses by: in a world where cargo ships sail it is ready only with regard, the crown level (written), the armed cargo ship and the navy lit, the loot rule on, a sane clock and at most a tenth of the cargo ships at sea unarmed; each one off refuses and says why
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite', 'attack_enabled', 'regard_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'navy_enabled', 'pirates_bite', 'raid_orders_enabled', 'convoy_armed_enabled');
  update public.world_config set value = '0.075'::jsonb where key = 'loot_risk_full';
  update public.world_config set value = '0'::jsonb where key = 'loot_risk_floor';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports set crew_pool = 5000;

  -- THE SEA IS QUIET (no storm and no raid on the way): the fight is the only thing that rolls
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_74;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- every purse of the world, summed: cities, companies, funds aboard
  execute $f$
create function pg_temp.purses()
returns bigint language sql as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  -- a human company of Portugal: her one fleet of p_ships hulls of p_class, full complements, her hold empty
  execute $f$
create function pg_temp.house_74(p_n int, p_class text, p_ships int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0374-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Risco ' || p_n, 'PRT', 'LIS', 'Risco ' || p_n, p_class, 'Risco ' || p_n, null, false);
  v_f   uuid;
  i     int;
begin
  select id into v_f from public.fleets where player_id = v_p;
  for i in 2 .. p_ships loop
    perform public.commission_ship(v_p, v_f, p_class, 'Risco ' || p_n || '.' || i, false, true);
  end loop;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- the next cargo ship of p_nation in port, sailed at p_at with p_ducats aboard, slowed so she is still at sea
  execute $f$
create function pg_temp.ship_74(p_ducats bigint, p_at timestamptz, p_nation text)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null and n.code = p_nation
     and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 74 FAIL: no cargo ship of % left to sail', p_nation;
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 74 FAIL: the cargo ship did not sail: %', v_st;
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

  -- ONE REAL BATTLE, opened at p_at and closed by one late call of the real closer: {battle, result, got (her purse), aboard_before, taken_before, purses_moved, risk (by this proof's own arithmetic)}
  execute $f$
create function pg_temp.battle_74(p_fleet uuid, p_target uuid, p_at timestamptz)
returns jsonb
language plpgsql
as $b$
declare
  v_p     uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_was   bigint;
  v_sum   bigint;
  v_ab    bigint;
  v_taken bigint;
  v_b     uuid;
  v_r     jsonb;
  v_h0    numeric;
  v_h1    numeric;
  v_led   bigint;
begin
  perform pg_temp.lie_by(p_fleet, p_target, p_at);
  v_led := (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'LOOT');
  v_was := (select pl.ducats from public.players pl where pl.id = v_p);
  v_ab := (select a.aboard from public.cargo_ship_aboard(p_target) a);
  v_taken := public.loot_today(v_p, p_at + interval '421 seconds');
  v_sum := pg_temp.purses();
  v_b := (public.attack_for(v_p, p_fleet, p_target, null, p_at) ->> 'battle_id')::uuid;
  if not public.battle_resolve(v_b, p_at + interval '421 seconds') then
    raise exception 'PROOF 74 FAIL: the battle did not close at its clock';
  end if;
  v_r := (select b.result from public.battles b where b.id = v_b);
  v_h0 := (v_r #>> '{hull,b_start}')::numeric;
  v_h1 := (v_r #>> '{hull,b}')::numeric;
  return jsonb_build_object('battle', v_b, 'result', v_r, 'got', (select pl.ducats from public.players pl where pl.id = v_p) - v_was, 'aboard', v_ab, 'taken', v_taken,
    'moved', pg_temp.purses() - v_sum,
    'risk', case when v_h0 > 0 then least(1, greatest(0, v_h0 - v_h1) / v_h0 / 0.075) else 1 end,
    'ledger', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'LOOT') - v_led);
end
$b$
  $f$;
end $$;

-- ── LOOT_RISK_REAL + LOOT_RISK_CAPS (the day) ──
do $$
declare
  t0      timestamptz := now();
  v_es    uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_big   uuid;
  v_nau   uuid;
  v_f     uuid;
  v_d     uuid;
  x       jsonb;
  i       int;
  v_won   int := 0;
  v_paid  int := 0;
  v_parts text := '';
  v_want  bigint;
  v_day   bigint := 0;
begin
  -- the armed cargo ship, as production sails her (convoy_armed_enabled lit): Spain's
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  for i in 1 .. 3 loop perform public.tick_cargo_ships(t0, v_es); end loop;
  if (select count(*) from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id where c.nation_id = v_es and k.attack > 0) < 9 then
    raise exception 'PROOF 74 FAIL: Spain has not nine armed cargo ships';
  end if;
  v_big := pg_temp.house_74(1, 'galion', 2);
  v_nau := pg_temp.house_74(2, 'nau', 1);
  for i in 1 .. 8 loop
    v_f := case when i % 2 = 1 then v_big else v_nau end;
    -- one battle a fleet in attack_cooldown_minutes: each fleet's battles are 40 minutes apart
    v_d := pg_temp.ship_74(400000, t0 + make_interval(mins => 40 * ((i - 1) / 2)), 'ESP');
    x := pg_temp.battle_74(v_f, v_d, t0 + make_interval(mins => 40 * ((i - 1) / 2)));
    if public.loot_risk(x -> 'result') is distinct from (x ->> 'risk')::numeric then
      raise exception 'PROOF 74 FAIL: battle %: public.loot_risk says %, the kept hulls say % (%)', i, public.loot_risk(x -> 'result'), x ->> 'risk', x #> '{result,hull}';
    end if;
    v_want := public.loot_due(x #>> '{result,outcome}', floor((x ->> 'aboard')::bigint * (x ->> 'risk')::numeric)::bigint, (x ->> 'taken')::bigint);
    if (x ->> 'got')::bigint is distinct from v_want or (x #>> '{result,loot}')::bigint is distinct from v_want or (x ->> 'ledger')::bigint is distinct from v_want then
      raise exception 'PROOF 74 FAIL: battle % (%): she took %, the result says %, the ledger %, the rule says % (aboard %, risk %, taken that day %)',
        i, x #>> '{result,outcome}', x ->> 'got', x #>> '{result,loot}', x ->> 'ledger', v_want, x ->> 'aboard', x ->> 'risk', x ->> 'taken';
    end if;
    if (x ->> 'moved')::bigint <> 0 then
      raise exception 'PROOF 74 FAIL: battle %: every purse summed moved %', i, x ->> 'moved';
    end if;
    if (x #>> '{result,outcome}') not in ('PLUNDERED', 'RANSOM') and v_want <> 0 then
      raise exception 'PROOF 74 FAIL: battle %: a fight that was not won (%) paid %', i, x #>> '{result,outcome}', v_want;
    end if;
    if (x ->> 'risk')::numeric = 0 and v_want <> 0 then
      raise exception 'PROOF 74 FAIL: battle %: a fight that cost her no hull paid %', i, v_want;
    end if;
    -- never more than the whole share of 0327, and never more than a ship's cap
    if v_want > public.loot_due(x #>> '{result,outcome}', (x ->> 'aboard')::bigint, 0) or v_want > public.wc_num('loot_per_ship') then
      raise exception 'PROOF 74 FAIL: battle %: % is more than the old rule or a ship''s cap allows', i, v_want;
    end if;
    if (x #>> '{result,outcome}') in ('PLUNDERED', 'RANSOM') then v_won := v_won + 1; end if;
    if v_want > 0 then v_paid := v_paid + 1; end if;
    v_day := v_day + v_want;
    v_parts := v_parts || format(' %s:%s/%s%%/%s', i, left(x #>> '{result,outcome}', 4), round((x ->> 'risk')::numeric * 100), v_want);
  end loop;
  if (select max(public.loot_today(p.id, t0 + interval '5 hours')) from public.players p where p.company_name like 'Casa Risco %') > public.wc_num('loot_per_company_day') then
    raise exception 'PROOF 74 FAIL: a company took more than loot_per_company_day in a day';
  end if;
  raise notice 'PASS: LOOT_RISK_REAL — 8 real battles on the armed cargo ship (two galleons, a Nau; 400,000 aboard): % won, % paid, each to the ducat by public.loot_due(outcome, floor(aboard x risk), taken); the result, the purse and the ledger agree; every purse summed moved 0. battle:outcome/share/gold%', v_won, v_paid, v_parts;

  -- ── LOOT_RISK_CAPS: 3,000,000 aboard ──
  v_f := pg_temp.house_74(3, 'galion', 2);
  v_d := pg_temp.ship_74(3000000, t0, 'ESP');
  x := pg_temp.battle_74(v_f, v_d, t0);
  v_want := public.loot_due(x #>> '{result,outcome}', floor(3000000 * (x ->> 'risk')::numeric)::bigint, 0);
  if (x ->> 'got')::bigint is distinct from v_want or v_want > public.wc_num('loot_per_ship') or (x ->> 'moved')::bigint <> 0 then
    raise exception 'PROOF 74 FAIL: 3,000,000 aboard: she took %, the rule says %, the cap is %', x ->> 'got', v_want, public.wc_num('loot_per_ship');
  end if;
  raise notice 'PASS: LOOT_RISK_CAPS — 3,000,000 aboard (%, share % %%): she took %, never above loot_per_ship (%); the day of the eight battles above: % of loot_per_company_day (%)',
    x #>> '{result,outcome}', round((x ->> 'risk')::numeric * 100), v_want, public.wc_num('loot_per_ship'), v_day, public.wc_num('loot_per_company_day');
end $$;

-- ── LOOT_RISK_UNARMED ──
do $$
declare
  t0   timestamptz := now();
  v_fr uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'FRA');
  v_f  uuid;
  v_d  uuid;
  x    jsonb;
  i    int;
  v_o  text := '';
begin
  -- the old hull: France's ships are made with convoy_armed_enabled off
  update public.world_config set value = 'false'::jsonb where key = 'convoy_armed_enabled';
  for i in 1 .. 2 loop perform public.tick_cargo_ships(t0, v_fr); end loop;
  if exists (select 1 from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id where c.nation_id = v_fr and k.attack > 0) then
    raise exception 'PROOF 74 FAIL: France''s cargo ships are armed: the old hull is wanted here';
  end if;
  for i in 1 .. 3 loop
    v_f := pg_temp.house_74(10 + i, case i when 1 then 'kobaya' when 2 then 'nau' else 'galion' end, 1);
    v_d := pg_temp.ship_74(400000, t0, 'FRA');
    x := pg_temp.battle_74(v_f, v_d, t0);
    if (x #>> '{result,hull,b}')::numeric <> (x #>> '{result,hull,b_start}')::numeric or (x ->> 'risk')::numeric <> 0 then
      raise exception 'PROOF 74 FAIL: a ship with no guns hurt her attacker: %', x #> '{result,hull}';
    end if;
    if (x ->> 'got')::bigint <> 0 or (x #>> '{result,loot}')::bigint <> 0 or (x ->> 'moved')::bigint <> 0 or (x ->> 'ledger')::bigint <> 0
       or (select a.aboard from public.cargo_ship_aboard(v_d) a) is distinct from 400000 then
      raise exception 'PROOF 74 FAIL: an unarmed ship paid: % (%)', x ->> 'got', x #>> '{result,outcome}';
    end if;
    v_o := v_o || ' ' || (x #>> '{result,outcome}');
  end loop;
  raise notice 'PASS: LOOT_RISK_UNARMED — a Kobaya, a Nau and a galleon each set upon an old unarmed cargo ship with 400,000 aboard (the fights:%): no hull lost, nothing taken, her funds whole, no purse moved', v_o;
end $$;

-- ── LOOT_RISK_OFF + LOOT_RISK_ELSE_SAME: one battle closed twice ──
do $$
declare
  t0    timestamptz := now() + interval '1 day';
  v_es  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_f   uuid;
  v_p   uuid;
  v_d   uuid;
  v_b   uuid;
  v_was bigint;
  v_on  jsonb;
  v_off jsonb;
  i     int;
begin
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  perform public.tick_cargo_ships(t0, v_es);
  v_f := pg_temp.house_74(20, 'galion', 2);
  v_p := (select f.player_id from public.fleets f where f.id = v_f);
  v_d := pg_temp.ship_74(400000, t0, 'ESP');
  perform pg_temp.lie_by(v_f, v_d, t0);
  v_was := (select pl.ducats from public.players pl where pl.id = v_p);
  v_b := (public.attack_for(v_p, v_f, v_d, null, t0) ->> 'battle_id')::uuid;
  for i in 0 .. 1 loop
    begin
      update public.world_config set value = (case i when 0 then '0.075' else '0' end)::jsonb where key = 'loot_risk_full';
      if not public.battle_resolve(v_b, t0 + interval '421 seconds') then
        raise exception 'PROOF 74 FAIL: the battle did not close';
      end if;
      raise exception using errcode = 'ZX374', message = jsonb_build_object(
        'result', (select b.result from public.battles b where b.id = v_b), 'got', (select pl.ducats from public.players pl where pl.id = v_p) - v_was,
        'regard', (select coalesce(sum(r.points), 0) from public.house_regard r where r.player_id = v_p),
        'hands', (select jsonb_agg(s.crew order by s.id) from public.ships s where s.fleet_id in (v_f, v_d)),
        'hulls', (select jsonb_agg(s.durability order by s.id) from public.ships s where s.fleet_id in (v_f, v_d)),
        'fleets', (select jsonb_agg(jsonb_build_array(f.status, f.busy_until) order by f.id) from public.fleets f where f.id in (v_f, v_d)),
        'lap', (select c.last_attacked_lap from public.cargo_ships c where c.fleet_id = v_d),
        'wanted', (select count(*) from public.wanted w where w.battle_id = v_b),
        'report', (select e.payload - 'loot' from public.events e where e.player_id = v_p and e.kind = 'BATTLE_REPORT' order by e.created_at desc limit 1))::text;
    exception when sqlstate 'ZX374' then
      if i = 0 then v_on := sqlerrm::jsonb; else v_off := sqlerrm::jsonb; end if;
    end;
  end loop;
  if (v_on -> 'result') - 'loot' is distinct from (v_off -> 'result') - 'loot' then
    raise exception 'PROOF 74 FAIL: the rule moved the fight itself';
  end if;
  if (v_off ->> 'got')::bigint is distinct from public.loot_due(v_off #>> '{result,outcome}', 400000, 0) then
    raise exception 'PROOF 74 FAIL: the rule off: she took %, 0327 paid %', v_off ->> 'got', public.loot_due(v_off #>> '{result,outcome}', 400000, 0);
  end if;
  if (v_on ->> 'got')::bigint is distinct from public.loot_due(v_on #>> '{result,outcome}', floor(400000 * public.loot_risk(v_on -> 'result'))::bigint, 0)
     or (v_on ->> 'got')::bigint > (v_off ->> 'got')::bigint then
    raise exception 'PROOF 74 FAIL: the rule on: she took % (off: %)', v_on ->> 'got', v_off ->> 'got';
  end if;
  raise notice 'PASS: LOOT_RISK_OFF — one battle (%), closed twice: the same fight to the last figure; the rule on she took % (her share %), the rule off % = what 0327 paid',
    v_on #>> '{result,outcome}', v_on ->> 'got', round(public.loot_risk(v_on -> 'result'), 4), v_off ->> 'got';
  if (v_on - 'result' - 'got') is distinct from (v_off - 'result' - 'got') then
    raise exception 'PROOF 74 FAIL: the rule moved something else: on %, off %', v_on - 'result' - 'got', v_off - 'result' - 'got';
  end if;
  raise notice 'PASS: LOOT_RISK_ELSE_SAME — the regard, both sides'' hands and hulls, the freed fleets, her lap, the WANTED row and the report (but its loot) are the same with the rule on and off';
end $$;

-- ── ATTACK_READY: the one reading 0375's guard refuses by, in a world where the crown's cargo ships sail ──
do $$
declare
  r     jsonb;
  k     text;
  v_n   int := 0;
begin
  if not (public.attack_ready() ->> 'lived')::boolean then
    raise exception 'PROOF 74 FAIL: cargo ships sail in this proof''s world and public.attack_ready says it is not lived in';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('regard_enabled', 'npc_ship_level_enabled', 'convoy_armed_enabled', 'navy_enabled', 'convoys_enabled');
  perform public.crown_hull_level_fix();
  -- France's old unarmed ships are at sea from the block above: more than a tenth of the cargo ships at sea
  r := public.attack_ready();
  if (r ->> 'ready')::boolean or (r #>> '{checks,cargo_safe}')::boolean or (r #>> '{cargo,unarmed_at_sea}')::int < 1 or jsonb_array_length(r -> 'why') <> 1 then
    raise exception 'PROOF 74 FAIL: unarmed cargo ships at sea and public.attack_ready says %', r;
  end if;
  -- they come home and are refitted (here: given the armed hull's class, as public.cargo_hull lays it)
  update public.ships s set class_id = (select c.id from public.ship_classes c where c.code = public.wc_text('convoy_armed_class'))
   where s.fleet_id in (select x.fleet_id from public.cargo_ships x) and s.class_id in (select c.id from public.ship_classes c where c.attack = 0);
  r := public.attack_ready();
  if not (r ->> 'ready')::boolean or jsonb_array_length(r -> 'why') <> 0 or exists (select 1 from jsonb_each(r -> 'checks') e where e.value <> 'true'::jsonb) then
    raise exception 'PROOF 74 FAIL: everything is lit and every cargo ship armed, and public.attack_ready says %', r;
  end if;
  -- each switch off in turn: not ready, that check false, one reason
  for k in select unnest(array['regard_enabled:regard_lit', 'npc_ship_level_enabled:npc_levels_lit', 'convoy_armed_enabled:convoy_armed_lit', 'navy_enabled:navy_lit']) loop
    update public.world_config set value = 'false'::jsonb where key = split_part(k, ':', 1);
    r := public.attack_ready();
    if (r ->> 'ready')::boolean or (r -> 'checks' ->> split_part(k, ':', 2))::boolean or jsonb_array_length(r -> 'why') <> 1 then
      raise exception 'PROOF 74 FAIL: % off, and public.attack_ready says %', split_part(k, ':', 1), r;
    end if;
    update public.world_config set value = 'true'::jsonb where key = split_part(k, ':', 1);
    v_n := v_n + 1;
  end loop;
  -- the levels not written, the loot rule off, the clock out of its range
  delete from public.ship_xp e using public.ships s join public.cargo_ships x on x.fleet_id = s.fleet_id where e.ship_id = s.id;
  if (public.attack_ready() ->> 'ready')::boolean or (public.attack_ready() #>> '{checks,levels_written}')::boolean then
    raise exception 'PROOF 74 FAIL: no cargo hull carries her level and public.attack_ready says %', public.attack_ready();
  end if;
  perform public.crown_hull_level_fix();
  update public.world_config set value = '0'::jsonb where key = 'loot_risk_full';
  if (public.attack_ready() ->> 'ready')::boolean then raise exception 'PROOF 74 FAIL: the loot rule off and public.attack_ready says ready'; end if;
  update public.world_config set value = '0.075'::jsonb where key = 'loot_risk_full';
  update public.world_config set value = '5'::jsonb where key = 'battle_round_seconds';
  if (public.attack_ready() ->> 'ready')::boolean then raise exception 'PROOF 74 FAIL: a five-second round and public.attack_ready says ready'; end if;
  update public.world_config set value = '60'::jsonb where key = 'battle_round_seconds';
  if not (public.attack_ready() ->> 'ready')::boolean then
    raise exception 'PROOF 74 FAIL: everything put back and public.attack_ready says %', public.attack_ready();
  end if;
  raise notice 'PASS: ATTACK_READY — in a world where cargo ships sail: unarmed ships at sea above a tenth refuse; all lit and armed is ready; each of % switches off, the levels unwritten, the loot rule off and a 5 s round each refuse with their reason; put back, ready', v_n;
end $$;

-- ── CALLED_ONCE: a navy ship lying in the harbour nearest the battle when she is called is on the sheet ONCE (0357's fault: she was frozen at the open and added again for round 1) ──
do $$
declare
  t0    timestamptz := now() + interval '3 days';
  v_es  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_cap uuid;
  v_f   uuid;
  v_p   uuid;
  v_d   uuid;
  v_n   uuid;
  v_b   uuid;
  v_s   jsonb;
  v_log jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('convoy_armed_enabled', 'navy_enabled', 'attack_enabled');
  v_cap := public.realm_capital(v_es);
  perform public.tick_cargo_ships(t0, v_es);
  insert into public.navy_realms (nation_id, ships, read_at) values (v_es, 25, t0) on conflict (nation_id) do update set ships = 25, read_at = t0;
  v_n := public.navy_commission(v_es, 1, v_cap, public.refit_yard(v_cap), v_cap, t0);
  update public.ships s set crew = k.crew_required from public.ship_classes k where k.id = s.class_id and s.fleet_id = v_n;
  v_f := pg_temp.house_74(30, 'galion', 1);
  v_p := (select f.player_id from public.fleets f where f.id = v_f);
  -- a cargo ship just out of the capital: the harbour nearest the battle is the one the navy ship lies in
  v_d := pg_temp.ship_74(100000, t0, 'ESP');
  perform pg_temp.lie_by(v_f, v_d, t0);
  v_b := (public.attack_for(v_p, v_f, v_d, null, t0) ->> 'battle_id')::uuid;
  if not exists (select 1 from public.battle_sides bs where bs.battle_id = v_b and bs.fleet_id = v_n and bs.how = 'CALLED' and bs.arrives_at <= t0) then
    raise exception 'PROOF 74 FAIL: the navy ship in the nearest harbour was not called as already there: %',
      (select jsonb_agg(jsonb_build_array(bs.how, bs.arrives_at - t0)) from public.battle_sides bs where bs.battle_id = v_b);
  end if;
  -- at the open: the ship set upon alone (the called ship joins at her round, through public.battle_advance)
  v_s := (select b.sheet -> 'a' from public.battles b where b.id = v_b);
  if jsonb_array_length(v_s) <> 1 then
    raise exception 'PROOF 74 FAIL: at the open the sheet holds % hull(s) of the side set upon, not the cargo ship alone', jsonb_array_length(v_s);
  end if;
  perform public.tick_battles(t0 + interval '60 seconds');
  v_s := (select b.sheet -> 'a' from public.battles b where b.id = v_b);
  v_log := (select public.battle_log(b.sheet, public.battle_fight(b.id, 1), 'ATTACKER') from public.battles b where b.id = v_b);
  if jsonb_array_length(v_s) <> 2 or (select count(distinct e ->> 'id') from jsonb_array_elements(v_s) e) <> 2
     or (select (e ->> 'from')::int from jsonb_array_elements(v_s) e where e ->> 'fleet' = v_n::text) is distinct from 1
     or (v_log #>> '{foe,k}')::numeric <> 2
     or (v_log #>> '{foe,crew}')::numeric <> (select sum(s.crew) from public.ships s where s.fleet_id in (v_d, v_n)) then
    raise exception 'PROOF 74 FAIL: after round 1 the sheet holds % hull(s) for % ship(s); the log says % ship(s), % crew', jsonb_array_length(v_s),
      (select count(distinct e ->> 'id') from jsonb_array_elements(v_s) e), v_log #>> '{foe,k}', v_log #>> '{foe,crew}';
  end if;
  perform public.tick_battles(t0 + interval '421 seconds');
  if (select b.status from public.battles b where b.id = v_b) = 'FIGHTING'
     or (select jsonb_array_length(b.sheet -> 'a') from public.battles b where b.id = v_b) <> 2 or exists (select 1 from public.navy_ships n where n.battle_id = v_b) then
    raise exception 'PROOF 74 FAIL: the battle with a called ship already there did not close with her on the sheet once and freed';
  end if;
  raise notice 'PASS: CALLED_ONCE — a navy ship in the harbour nearest the battle is called as already there: the sheet holds the cargo ship alone at the open, both ships once from round 1 (the log: 2 ships, % crew), and the battle closes (%) with her freed',
    v_log #>> '{foe,crew}', (select b.result ->> 'outcome' from public.battles b where b.id = v_b);
end $$;
