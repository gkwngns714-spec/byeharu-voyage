-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 69 — AN ARMADA FIGHTS AS ONE  (migration 0395; docs/ARMADA.md section 7; owner row 323)
--
--   The migration's self-assert plays barcas on its own rows and does not close a battle. Here the game is real: real companies with gunned fleets, the REAL forming door
--   (cmd.armada_form), the REAL order (cmd.armada_sail), the REAL attack and its dry run (cmd.attack, cmd.preview_attack), a real cargo ship at sea with gold aboard and a real
--   navy ship, the REAL job (public.tick_battles), the REAL close (public.battle_resolve, public.attack_close), the REAL door (cmd.battle_stance) and reads (world.battle,
--   world.fights). OLD AGAINST NEW is not taken on trust: the migration's own 13 hunks are held below (written by scripts/ops/harness/armada-battle/gen-checks.mjs
--   --proof-write from the migration's text), each NEW text is found once in the live body and reversed, and the rebuild is judged as a round trip on the live body.
--   A battle's seed is its id, so every play pins the id it opens (the column's default, inside a subtransaction) and is rolled back; the same battle is then played several ways.
--   EVERY BUILT WORLD HAS ITS OWN world_secret (0031), so every roll here is some other world's roll: NOTHING BELOW ASSERTS ONE OUTCOME OF A FIGHT. What is held is what is true
--   under any dice: who is on the sheet, who is held and freed, that a row logged is the re-run's row, that tick by tick is one late call is a re-run, and that the shares add up
--   by their rule whatever the fight did. (Run under 24 world secrets by the builder: scripts/ops/harness/armada-battle/run.mjs --secrets=24.)
--   The attack's reach is set wide here (attack_reach_nm, in this proof's own transaction): reach is 0327's gate and is not what is proved; who of an armada IS THERE is read at
--   the knob's own 240 on the leaf. Everything rolls back with proof.mjs's transaction; every switch this proof needs it writes here.
--
-- @pass AB_DARK_PARITY      attack_enabled false, armadas standing in port: every door a client has to a battle (cmd.attack, cmd.preview_attack, cmd.battle_stance, world.battle, world.fights, world.fight, world.fleets, world.armadas), the cores, the job and the closer answer the same text under the nine old bodies and the new; the attack refuses by the switch and nothing is written
-- @pass AB_NO_PVP           lit: a fleet of an armada cannot attack a company's fleet by public.battle_open (either kind), public.attack_for or cmd.attack; no battle row, no side, and her sister is not held
-- @pass AB_ALONE_OLD_IS_NEW lit: a fleet in no armada attacks a cargo ship and a navy ship, played tick by tick under the old bodies and under the new with the same seed: the dry run, the answer, the open, every read at every tick, the rounds, the result, hulls, hands, purse, ledger, report and the target's voyage the same text; and a fleet of an armada with nobody there is that same lone fleet
-- @pass AB_WHO_IS_THERE     who takes part: the fleets of her armada docked in her port, or sailing under her lead voyage within reach; not a fleet in another port (she is not held and reads no battle), not when she lies at anchor, not once the armada is disbanded
-- @pass AB_GATES_PREVIEW    the dry run reads the whole armada: its word is the armada's, it names her and her fleets, and it is the attack's own answer; it leaves no trace; a sister with cargo, a sister not free and a sister inside the cooldown each refuse the attack AND the dry run under the sister's name, and nothing moved
-- @pass AB_TWO_TICK_LATE    an armada of two attacks a cargo ship: both fleets on the sheet in order, both held and both freed; the map's card counts three fleets; each tick logs at most one row and both fleets read one battle; tick by tick, one late call and a re-run leave the same rows, result, hulls, hands, purse, ledger and report; one report; the shares are the rule's
-- @pass AB_LOOT_RISK       with 0374 (loot follows the risk taken): the gold that reaches the purse is 0374's own figure, public.loot_due over floor(aboard x public.loot_risk(the battle's result)), where the risk is read on the WHOLE armada's hull; it is then shared by the guns each fleet brought, to the ducat; held with the rule as shipped, with a floor of 0.4 (gold moves) and with the rule off
-- @pass AB_STANCE_FLEE      Flee set before round 3: the first rows are the battle's fought through; from round 3 not a gun of the whole side fires; Flee from the first round: away is BROKEN_OFF with no loot and every fleet's hands by the beaten row; the door's one press is the stance both fleets read, and another company's press is refused
-- @pass AB_NAVY             the armada attacks a navy ship: no gold, the shares say so, her own fleets are never counted as the navy that came, the ship set upon is freed; tick by tick is one late call
-- @pass AB_OF_SIX           six fleets formed by the door: the fleet that attacks first, then the armada's own order; seven fleets on the map's card; six fleets held and freed; six shares that add up; the seventh fleet of the company takes no part
-- @pass AB_AT_SEA           an armada sailing on one order attacks: both fleets are held at sea for the same span, the hold is cut with the battle for both, and they still arrive at one instant; at the knob's own reach a sister at the same point is there, and at no reach she is not
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table hunks_69 (fn text, n int, old text, new text) on commit drop;
insert into hunks_69 (fn, n, old, new) values
-- hunks:begin
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 1, $h$  foreach v_fleet in array array[least(p_fleet, p_target), greatest(p_fleet, p_target)] loop
$h$, $h$  -- 0395 (docs/ARMADA.md section 7): a fleet of an armada attacks with every fleet of hers that is there. Each of them is judged before anything moves, and one refused
  -- refuses the attack under her name (public.attack_armada_gates). A fleet in no armada: one primary-key probe, and nothing.
  perform public.attack_armada_gates(p_player, p_fleet, p_now);
  foreach v_fleet in array array[least(p_fleet, p_target), greatest(p_fleet, p_target)] loop
$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 2, $h$    'resolves_at', (select b.resolves_at from public.battles b where b.id = v_battle));
$h$, $h$    'resolves_at', (select b.resolves_at from public.battles b where b.id = v_battle))
    || public.battle_armada_note(v_battle);   -- 0395: an armada's battle says her name and her fleets, and the word is the armada's; any other battle: {}
$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1, $h$  foreach v_fleet in array array[p_attacker, p_defender] loop
$h$, $h$  -- 0395 (docs/ARMADA.md section 7): the fleets of her armada that are there join her side now, before the sheet is frozen, and are stopped by this same loop
  foreach v_fleet in array array[p_attacker, p_defender] || public.battle_armada_join(v_id, p_kind, p_attacker, p_now) loop
$h$),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 1, $h$  v_st := public.battle_opening_stance(v_def);
$h$, $h$  perform public.battle_armada_sheet(p_battle);   -- 0395: an armada's sheet names her and her fleets, and its word reads all of them; any other sheet: nothing
  v_st := public.battle_opening_stance(v_def);
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1, $h$    if s.side = 'ATTACKER' and not s.is_npc then
$h$, $h$    if s.side = 'ATTACKER' and not s.is_npc   -- 0395: one report a battle, under the fleet that attacked: a fleet that joined as her armada sends none
       and not exists (select 1 from public.battle_sides x where x.battle_id = p_battle and x.fleet_id = s.fleet_id and x.how = 'ARMADA') then
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1, $h$   where bs.battle_id = p_battle and bs.side = 'ATTACKER';
$h$, $h$   where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';   -- 0395: the fleet that attacked; her armada's fleets are public.attack_armada_close's
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 2, $h$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
$h$, $h$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost)
      || public.attack_armada_close(p_battle, p_fight, v_gold, v_lost);   -- 0395: her armada's fleets lose their hands by the same row, and each fleet's share is said; no armada: {}
$h$),
  ('public.battle_log(jsonb,jsonb,text)', 1, $h$  return (v_log - 'end') || '{"atk": true}'::jsonb || case when v_end is null then '{}'::jsonb else jsonb_build_object('end', v_end) end;
$h$, $h$  return (v_log - 'end') || '{"atk": true}'::jsonb || case when v_end is null then '{}'::jsonb else jsonb_build_object('end', v_end) end
      || case when p_sheet ? 'fleets' then jsonb_build_object('fleets', p_sheet->'fleets') else '{}'::jsonb end;   -- 0395: an armada's log names her fleets above their ships, as a raid's does (0367)
$h$),
  ('world.battle(uuid)', 1, $h$   where bs.fleet_id = p_fleet and bs.how = 'OPENED' and f.player_id = v_player and bt.sheet is not null
$h$, $h$   where bs.fleet_id = p_fleet and bs.how in ('OPENED', 'ARMADA') and f.player_id = v_player and bt.sheet is not null   -- 0395: any fleet of hers in it reads the battle
$h$),
  ('world.battle(uuid)', 2, $h$                                    'navy', b.result #> '{navy,line}') end;
$h$, $h$                                    'navy', b.result #> '{navy,line}') end
    || public.battle_armada_view(b.id, p_fleet);   -- 0395: her armada's name, her fleets, the side's stance and, closed, each fleet's share; no armada: {}
$h$),
  ('public.navy_close(uuid,timestamp with time zone)', 1, $h$  select count(*) filter (where bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at),
$h$, $h$  select count(*) filter (where bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at),   -- 0395: her own armada is no navy
$h$),
  ('public.navy_close(uuid,timestamp with time zone)', 2, $h$         bool_or(bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at or ($h$, $h$         bool_or(bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at or ($h$),
  ('public.battle_navy_served(uuid)', 1, $h$                     join public.battle_sides o on o.battle_id = b.id and o.how <> 'OPENED' and o.arrives_at <= b.resolves_at
$h$, $h$                     join public.battle_sides o on o.battle_id = b.id and o.how not in ('OPENED', 'ARMADA') and o.arrives_at <= b.resolves_at   -- 0395: her own armada is no help coming to the other side
$h$)
-- hunks:end
;

-- the bodies as they are now, by digest: what a rolled-back rebuild must come back to
create temp table live_69 on commit drop as
select f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5
  from (select distinct x.fn from hunks_69 x) f;

-- THE OLD BODIES, rebuilt from the live ones, whatever a later migration has made of them: each hunk's NEW text occurs exactly once in the live body and is reversed; each OLD
-- text then occurs exactly once; putting the NEW texts back gives the live body again, to the character. Called only inside a subtransaction that is rolled back.
create function pg_temp.to_old_69() returns void language plpgsql as $b$
declare
  f      record;
  h      record;
  v_live text;
  v_def  text;
  v_back text;
begin
  for f in select l.fn from live_69 l order by l.fn loop
    v_live := replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '');
    v_def := v_live;
    for h in select * from hunks_69 x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'PROOF 69 FAIL: hunk % of % is not in the live body exactly once: a later migration re-cut the very text 0395 added, and must amend this proof''s copy of the hunk', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    v_back := v_def;
    for h in select * from hunks_69 x where x.fn = f.fn order by x.n loop
      if (length(v_back) - length(replace(v_back, h.old, ''))) / length(h.old) <> 1 then
        raise exception 'PROOF 69 FAIL: hunk % of %: its OLD text is not in the rebuilt body exactly once', h.n, f.fn;
      end if;
      v_back := replace(v_back, h.old, h.new);
    end loop;
    if v_back is distinct from v_live or v_def = v_live then
      raise exception 'PROOF 69 FAIL: the rebuilt % does not come back to the live body when 0395''s hunks are put back (or nothing was reversed)', f.fn;
    end if;
    if v_def ~ 'armada' then
      raise exception 'PROOF 69 FAIL: the rebuilt % still names an armada', f.fn;
    end if;
    execute v_def;
  end loop;
  if exists (select 1 from live_69 l where md5(replace(pg_get_functiondef(l.fn::regprocedure), E'\r', '')) = l.md5) then
    raise exception 'PROOF 69 FAIL: the old bodies were not rebuilt';
  end if;
end
$b$;

create function pg_temp.live_69_ok() returns boolean language sql as $b$
  select (select count(*) from live_69) = 9
     and not exists (select 1 from live_69 l where md5(replace(pg_get_functiondef(l.fn::regprocedure), E'\r', '')) is distinct from l.md5)
$b$;

create function pg_temp.as_house(p_uid uuid) returns void language sql as $b$
  select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
         set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
$b$;

create function pg_temp.uid_69(p_n int) returns uuid language sql immutable as $b$
  select ('00000000-0395-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid
$b$;

-- ══ THE GAME ══
do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled', 'npc_refits_enabled', 'navy_enabled', 'pirates_bite', 'raid_orders_enabled');
  update public.world_config set value = to_jsonb(7) where key in ('fleet_max', 'fleet_hard_max');   -- room for the six, and one more that stays out (proof 68 sets it so; fleet_hard_max too since 0370 lit fleet room)
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports p set crew_pool = 2000;
  if not public.armada_on() or public.wc_int('armada_fleet_max') <> 6 then
    raise exception 'PROOF 69 FAIL: the armada knobs of this world are not lit and 6';
  end if;

  -- THE SEA IS QUIET (proof 40 stubs it so): no storm, calm or raid moves a hull or an arrival in these scenes
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_69;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- a human company of Portugal with p_fleets fleets in Lisbon, one ship each: the first and every odd one the best guns there are, the even ones the next class down (so the
  -- fleets bring different guns and the shares differ), 100 hands on the first and fewer on the rest, every hold empty
  execute $f$
create function pg_temp.house_69(p_n int, p_fleets int)
returns uuid
language plpgsql
as $b$
declare
  v_c1  text := (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1);
  v_c2  text := (select c.code from public.ship_classes c where c.attack > 0 order by c.attack desc, c.code offset 1 limit 1);
  v_p   uuid := public.new_house(pg_temp.uid_69(p_n), 'Casa Armada ' || p_n, 'PRT', 'LIS', 'Frota ' || p_n || '-1', v_c1, 'Nau ' || p_n || '-1', null, false);
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_f   uuid;
  k     int;
begin
  for k in 2 .. p_fleets loop
    v_f := public.form_fleet(v_p, 'Frota ' || p_n || '-' || k, v_lis);
    perform public.commission_ship(v_p, v_f, case when k % 2 = 0 then v_c2 else v_c1 end, 'Nau ' || p_n || '-' || k, true, true);
  end loop;
  update public.players set ducats = 800000 where id = v_p;
  -- made one after another (this proof makes them in one instant): the armada's own order reads when a fleet was made
  update public.fleets f set created_at = now() - make_interval(mins => 100 - right(f.name, 1)::int) where f.player_id = v_p;
  update public.ships s set crew = 100 - 7 * (x.k - 1), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 100000, food_t = 100000
    from (select f.id, row_number() over (order by f.created_at, f.id) as k from public.fleets f where f.player_id = v_p) x
   where s.fleet_id = x.id;
  return v_p;
end
$b$
  $f$;

  -- the next cargo ship in port, not of Portugal, with p_ducats aboard, sailed at p_at and slowed so she is still at sea when the proof looks (proof 60's ship)
  execute $f$
create function pg_temp.ship_69(p_ducats bigint, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null and n.code <> 'PRT'
     and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by n.code, x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 69 FAIL: no cargo ship left to sail';
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 69 FAIL: the cargo ship did not sail: %', v_st;
  end if;
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  -- a navy ship of Spain, in service, sailed from a harbour near her capital toward it at p_at and slowed so she is at sea for the whole proof; every other navy ship is laid up
  -- first, so nobody is there to be called (proof 40's ship and its clearing)
  execute $f$
create function pg_temp.navy_69(p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_cap uuid := public.realm_capital(v_nat);
  v_ord int;
  v_st  uuid;
  v_leg jsonb;
  v_n   uuid;
  r     record;
begin
  update public.navy_ships n set laid_up_at = p_at, mission = 'PATROL', battle_id = null, called_to = null, escort_of = null where n.laid_up_at is null;
  for r in select x.port_id from voyage.reach_from(v_cap) x join public.ports p on p.id = x.port_id
            where p.kind = 'HARBOUR' and not p.is_ice_closed and x.port_id <> v_cap and x.nm <= public.wc_num('navy_reach_nm') order by x.nm, x.code loop
    if public.cargo_circuit_plan(v_nat, r.port_id, v_cap) #> '{legs,0}' is not null then
      v_st := r.port_id;
      exit;
    end if;
  end loop;
  if v_st is null then
    raise exception 'PROOF 69 FAIL: no harbour within reach of the capital to sail a navy ship from';
  end if;
  v_ord := coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = v_nat), 0) + 1;
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, v_ord + 24, p_at) on conflict (nation_id) do update set ships = v_ord + 24, read_at = p_at;
  v_n := public.navy_commission(v_nat, v_ord, v_cap, public.refit_yard(v_cap), v_st, p_at);
  v_leg := public.cargo_circuit_plan(v_nat, v_st, v_cap) #> '{legs,0}';
  perform public.navy_sail(v_n, v_st, voyage.segments_from_course(v_leg -> 'course'), v_cap, null, 0, p_at);
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 5000) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = v_n and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = v_n and vo.status = 'SAILING'));
  if (select f.status from public.fleets f where f.id = v_n) <> 'SAILING' then
    raise exception 'PROOF 69 FAIL: the navy ship did not sail';
  end if;
  return v_n;
end
$b$
  $f$;

  -- every great power's ships and circuits
  declare
    v_nat uuid;
    v_n   int;
  begin
    for v_nat in select g.nation_id from public.great_powers g loop
      for v_n in 1 .. 3 loop
        perform public.tick_cargo_ships(now(), v_nat);
      end loop;
    end loop;
  end;
end
$$;

-- ONE BATTLE, PLAYED ONE WAY, in a subtransaction that is rolled back. The battle's id is pinned (it is the fight's seed). The attack is the REAL door at now() (the transaction's
-- instant, the same for every play), after its dry run. p_stances are rows at instants of the scene's choosing ([[seconds after the open, stance], ...]: what the door writes at
-- that instant); p_door, when given, is pressed through the real door right after the open. Played by the real job: 'TICK' at every round's instant and the clock's end, 'LATE'
-- by one call an hour after, 'OLD' tick by tick under the rebuilt old bodies. Answers everything it left.
create function pg_temp.play_69(p_id uuid, p_a uuid, p_d uuid, p_mode text, p_stances jsonb default '[]'::jsonb, p_door text default null)
returns jsonb language plpgsql as $b$
declare
  v_t     timestamptz := now();
  v_pl    uuid := (select f.player_id from public.fleets f where f.id = p_a);
  v_uid   uuid := (select p.auth_uid from public.players p where p.id = v_pl);
  v_mine  uuid[] := array(select f.id from public.fleets f where f.player_id = v_pl order by f.created_at, f.id);
  v_ev    uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led   uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  v_rate  numeric := (public.wc('attack_crew_lost') ->> 'beaten')::numeric;
  v_b     uuid;
  v_x     jsonb;
  v_pre   jsonb;
  v_trace boolean;
  v_s0    jsonb;
  v_p0    bigint;
  v_ab0   bigint;
  v_td0   bigint;
  v_res   jsonb;
  v_open  jsonb;
  v_sides jsonb;
  v_f0    jsonb;
  v_card  jsonb;
  v_door  jsonb;
  v_ticks jsonb := '[]'::jsonb;
  v_grow  int[] := '{}';
  v_closed int := 0;
  v_rs    int;
  v_out   jsonb;
  g       int;
begin
  begin
    if p_mode = 'OLD' then
      perform pg_temp.to_old_69();
    end if;
    v_s0 := (select jsonb_agg(jsonb_build_object('id', s.id, 'fleet', s.fleet_id, 'hull', s.durability, 'crew', s.crew, 'beaten', public.raid_crew_lost(s.fleet_id, s.crew, v_rate)) order by s.id)
               from public.ships s where s.fleet_id = any (v_mine) or s.fleet_id = p_d);
    v_p0 := (select p.ducats from public.players p where p.id = v_pl);
    v_ab0 := coalesce((select x.aboard from public.cargo_ship_aboard(p_d) x), 0);   -- what the ship carries, and what the company has taken today, before the battle: 0374's inputs
    v_td0 := public.loot_today(v_pl, v_t);
    execute format('alter table public.battles alter column id set default %L::uuid', p_id);
    perform pg_temp.as_house(v_uid);
    v_pre := cmd.preview_attack(p_a, p_d);
    v_trace := exists (select 1 from public.battles) or exists (select 1 from public.battle_sides) or exists (select 1 from public.fleets f where f.id = any (v_mine || p_d) and f.busy_until is not null)
               or exists (select 1 from public.voyage_events e where e.kind = 'BATTLE');
    v_x := cmd.attack(p_a, p_d);
    v_b := (v_x ->> 'battle_id')::uuid;
    if v_b is distinct from p_id then
      raise exception 'PROOF 69 FAIL: the attack did not open the pinned battle: %', v_x;
    end if;
    v_open := (select to_jsonb(b) from public.battles b where b.id = v_b);
    v_sides := (select jsonb_agg(jsonb_build_object('fleet', bs.fleet_id, 'side', bs.side, 'how', bs.how, 'joined_at', bs.joined_at, 'arrives_at', bs.arrives_at, 'name', f.name,
                                                    'ships', (select count(*) from public.ships s where s.fleet_id = f.id)) order by bs.joined_at, bs.fleet_id)
                  from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id where bs.battle_id = v_b);
    v_f0 := (select jsonb_object_agg(f.id, jsonb_build_object('status', f.status, 'busy', f.busy_until,
                      'holds', (select jsonb_agg(e.payload order by e.day_index) from public.voyages o join public.voyage_events e on e.voyage_id = o.id and e.day_index >= voyage.hold_floor()
                                 where o.fleet_id = f.id and o.status = 'SAILING')))
               from public.fleets f where f.id = any (v_mine || p_d));
    v_card := (select c from jsonb_array_elements(world.fights() -> 'fights') c where c ->> 'id' = v_b::text);
    v_rs := (select b.round_seconds from public.battles b where b.id = v_b);
    insert into public.battle_stances (battle_id, fleet_id, set_at, stance)
    select v_b, p_a, v_t + make_interval(secs => (e ->> 0)::int), e ->> 1 from jsonb_array_elements(p_stances) e;
    if p_door is not null then
      v_door := jsonb_build_object('answer', cmd.battle_stance(v_b, p_door));   -- its own statement: a statement does not see what a function it calls has just written
      v_door := v_door || jsonb_build_object(
                  'reads', (select jsonb_agg(world.battle(u.f) -> 'stance' order by u.o) from unnest(v_mine) with ordinality u(f, o)),
                  'rows', (select jsonb_agg(jsonb_build_array(s.fleet_id, s.stance) order by s.set_at) from public.battle_stances s where s.battle_id = v_b));
    end if;
    if p_mode in ('TICK', 'OLD') then
      for g in 1 .. v_n + 1 loop
        v_closed := v_closed + public.tick_battles(v_t + make_interval(secs => g * v_rs));
        v_grow := v_grow || (select count(*)::int from public.battle_rounds r where r.battle_id = v_b);
        -- what every fleet of hers reads after this tick
        v_ticks := v_ticks || jsonb_build_array((select jsonb_agg(world.battle(u.f) order by u.o) from unnest(v_mine) with ordinality u(f, o)));
      end loop;
    else
      v_closed := public.tick_battles(v_t + interval '1 hour');
    end if;
    v_res := (select b.result from public.battles b where b.id = v_b);
    v_out := jsonb_build_object(
      -- 0374's own figure for this battle, computed here from its own leaves: what must have reached the purse
      'risk', public.loot_risk(v_res), 'aboard0', v_ab0,
      'want_loot', case when v_res ->> 'outcome' in ('PLUNDERED', 'RANSOM') and v_ab0 > 0
                        then public.loot_due(v_res ->> 'outcome', floor(v_ab0 * public.loot_risk(v_res))::bigint, v_td0) else 0 end,
      'pre', v_pre, 'trace', v_trace, 'attack', v_x, 'open', v_open, 'sides', v_sides, 'fleets0', v_f0, 'card', v_card, 'door', v_door,
      'ticks', v_ticks, 'grow', to_jsonb(v_grow), 'closed', v_closed, 'mine', to_jsonb(v_mine), 'a', p_a, 'd', p_d,
      'battle', (select to_jsonb(b) - 'next_round_at' from public.battles b where b.id = v_b),
      'rounds', (select coalesce(jsonb_agg(jsonb_build_object('g', r.g, 'at', r.at, 'row', r."row") order by r.g), '[]'::jsonb) from public.battle_rounds r where r.battle_id = v_b),
      'stances', (select coalesce(jsonb_agg(jsonb_build_array(s.fleet_id, s.set_at, s.stance) order by s.set_at), '[]'::jsonb) from public.battle_stances s where s.battle_id = v_b),
      'navy_came', (select count(*) from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                     where bs.battle_id = v_b and bs.side = 'DEFENDER' and bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at),
      'navy_free', not exists (select 1 from public.navy_ships n where n.battle_id = v_b),
      'fleets', (select jsonb_object_agg(f.id, jsonb_build_object('status', f.status, 'busy', f.busy_until)) from public.fleets f where f.id = any (v_mine || p_d)),
      'ships0', v_s0,
      'ships', (select jsonb_agg(jsonb_build_object('id', s.id, 'fleet', s.fleet_id, 'hull', s.durability, 'crew', s.crew) order by s.id) from public.ships s where s.fleet_id = any (v_mine) or s.fleet_id = p_d),
      'purse0', v_p0, 'purse', (select p.ducats from public.players p where p.id = v_pl),
      'aboard', (select x.aboard from public.cargo_ship_aboard(p_d) x),
      'events', (select coalesce(jsonb_agg(e.payload order by e.payload::text), '[]'::jsonb) from public.events e where e.player_id = v_pl and e.id <> all (v_ev) and e.kind = 'BATTLE_REPORT'),
      'other_events', (select coalesce(jsonb_agg(e.kind order by e.kind), '[]'::jsonb) from public.events e where e.player_id = v_pl and e.id <> all (v_ev) and e.kind <> 'BATTLE_REPORT'),
      'ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.balance_after desc, l.kind), '[]'::jsonb)
                   from public.ledger l where l.player_id = v_pl and l.id <> all (v_led)),
      'voyages', (select coalesce(jsonb_object_agg(o.fleet_id, jsonb_build_object('eta', o.eta, 'delay', o.delay_hours, 'days', voyage.total_days(o.id), 'status', o.status,
                           'holds', (select jsonb_agg(e.payload order by e.day_index) from public.voyage_events e where e.voyage_id = o.id and e.day_index >= voyage.hold_floor()))), '{}'::jsonb)
                    from public.voyages o where o.fleet_id = any (v_mine || p_d) and o.status = 'SAILING'),
      'rerun', public.battle_fight(v_b, null));
    raise exception using errcode = 'ZX369', message = 'PLAY_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  perform pg_temp.as_house(null);
  if v_out is null then
    raise exception 'PROOF 69 FAIL: a play answered nothing';
  end if;
  return v_out;
end
$b$;

-- what two plays of one battle must agree on, as text (everything they left; not how many calls it took)
create function pg_temp.left_69(p jsonb) returns text language sql immutable as $b$
  select (jsonb_build_object('pre', p -> 'pre', 'attack', p -> 'attack', 'open', p -> 'open', 'sides', p -> 'sides', 'battle', p -> 'battle', 'rounds', p -> 'rounds',
            'stances', p -> 'stances', 'fleets', p -> 'fleets', 'ships', p -> 'ships', 'purse', p -> 'purse', 'aboard', p -> 'aboard', 'events', p -> 'events',
            'other_events', p -> 'other_events', 'ledger', p -> 'ledger', 'voyages', p -> 'voyages', 'rerun', p -> 'rerun'))::text
$b$;

-- WHAT IS TRUE OF AN ARMADA'S BATTLE UNDER ANY DICE, judged on a play's own rows: null when it all holds, else the first thing that does not. p_order: her fleets in the order
-- they must stand on her side (the fleet that attacked first). p_sea: they were sailing (held by a hold, not IN_BATTLE).
create function pg_temp.judge_69(p jsonb, p_order uuid[], p_sea boolean default false) returns text language plpgsql as $b$
declare
  v_n      int := array_length(p_order, 1);
  v_att    jsonb := (select jsonb_agg(e order by o) from jsonb_array_elements(p -> 'sides') with ordinality q(e, o) where e ->> 'side' = 'ATTACKER');
  v_res    jsonb := p -> 'battle' -> 'result';
  v_sheet  jsonb := p -> 'open' -> 'sheet';
  v_end    timestamptz := (p -> 'open' ->> 'resolves_at')::timestamptz;
  v_beaten boolean := v_res ->> 'outcome' = 'DRIVEN_OFF' or coalesce((v_res ->> 'broke_off')::boolean, false);
  v_guns   numeric;
  v_given  bigint := 0;
  v_want   bigint;
  v_f      uuid;
  v_sh     jsonb;
  i        int;
begin
  -- the dry run: no trace, and it is the attack's own answer
  if (p ->> 'trace')::boolean or (p -> 'pre' ->> 'ok')::boolean is not true or p -> 'pre' -> 'estimate' is distinct from (p -> 'attack') - 'ok' - 'version' - 'battle_id' then
    return format('the dry run left a trace or is not the attack''s answer: %s against %s', p -> 'pre', p -> 'attack');
  end if;
  -- her side: the fleet that attacked, then her armada, each a microsecond after the last
  if jsonb_array_length(v_att) is distinct from v_n then
    return format('%s fleets on her side, not %s: %s', jsonb_array_length(v_att), v_n, v_att);
  end if;
  for i in 1 .. v_n loop
    if v_att -> (i - 1) ->> 'fleet' is distinct from p_order[i]::text or v_att -> (i - 1) ->> 'how' is distinct from (case when i = 1 then 'OPENED' else 'ARMADA' end)
       or (v_att -> (i - 1) ->> 'arrives_at')::timestamptz is distinct from (p -> 'open' ->> 'started_at')::timestamptz
       or (v_att -> (i - 1) ->> 'joined_at')::timestamptz is distinct from (p -> 'open' ->> 'started_at')::timestamptz + make_interval(secs => (i - 1) * 0.000001) then
      return format('her side is not in order at place %s: %s', i, v_att);
    end if;
  end loop;
  -- the sheet: every hull of every one of them, fleet by fleet, in that order; their names; the armada's; the word read with all of her
  if (select jsonb_agg(e ->> 'id' order by o) from jsonb_array_elements(v_sheet -> 'b') with ordinality q(e, o))
       is distinct from (select jsonb_agg(s.e ->> 'id' order by u.o, s.e ->> 'id') from unnest(p_order) with ordinality u(f, o) join jsonb_array_elements(p -> 'ships0') s(e) on s.e ->> 'fleet' = u.f::text)
     or v_sheet -> 'fleets' is distinct from (select jsonb_agg(jsonb_build_array(e -> 'name', e -> 'ships') order by o) from jsonb_array_elements(v_att) with ordinality q(e, o))
     or coalesce(v_sheet ->> 'armada', '') = '' or v_sheet ->> 'word' is distinct from p -> 'attack' ->> 'word'
     or p -> 'attack' -> 'armada' is distinct from jsonb_build_object('name', v_sheet -> 'armada', 'ships', jsonb_array_length(v_sheet -> 'b'),
                                                    'fleets', (select jsonb_agg(e -> 'name' order by o) from jsonb_array_elements(v_att) with ordinality q(e, o))) then
    return format('the sheet does not hold her fleets'' hulls in order, or does not name them: sheet %s, attack %s', v_sheet - 'a', p -> 'attack');
  end if;
  -- held at the open, every one; free at the end, every one
  foreach v_f in array p_order loop
    if p_sea then
      if p -> 'fleets0' -> v_f::text ->> 'status' is distinct from 'SAILING'
         or (p -> 'fleets0' -> v_f::text -> 'holds' -> 0 ->> 'held_until')::timestamptz is distinct from v_end or (p -> 'fleets0' -> v_f::text -> 'holds' -> 0 ->> 'free')::boolean is not true then
        return format('at sea, fleet %s was not held by a free hold to the battle''s end: %s', v_f, p -> 'fleets0' -> v_f::text);
      end if;
    elsif p -> 'fleets0' -> v_f::text ->> 'status' is distinct from 'IN_BATTLE' or (p -> 'fleets0' -> v_f::text ->> 'busy')::timestamptz is distinct from v_end then
      return format('fleet %s was not held for the battle: %s', v_f, p -> 'fleets0' -> v_f::text);
    end if;
    if p -> 'fleets' -> v_f::text ->> 'busy' is not null or p -> 'fleets' -> v_f::text ->> 'status' = 'IN_BATTLE' then
      return format('fleet %s was not freed at the end: %s', v_f, p -> 'fleets' -> v_f::text);
    end if;
  end loop;
  if p -> 'battle' ->> 'status' not in ('RESOLVED', 'BROKEN_OFF') or (p ->> 'closed')::int is distinct from 1 then
    return format('the battle did not close once: %s, closed %s', p -> 'battle' ->> 'status', p -> 'closed');
  end if;
  -- the map's card: every fleet that is there
  if (p -> 'card' ->> 'size')::int is distinct from jsonb_array_length(p -> 'sides') or (p -> 'card' ->> 'fleets')::int is distinct from jsonb_array_length(p -> 'sides')
     or p -> 'card' ->> 'mine' is distinct from p_order[1]::text
     or (select jsonb_agg(e -> 'fleet' order by o) from jsonb_array_elements(p -> 'card' -> 'sides') with ordinality q(e, o) where e ->> 'side' = 'ATTACKER') is distinct from to_jsonb(p_order) then
    return format('the map''s card does not count and list her fleets: %s', p -> 'card');
  end if;
  -- the rows logged are the re-run's rows
  if exists (select 1 from jsonb_array_elements(p -> 'rounds') r where (r -> 'row')::text is distinct from (p -> 'rerun' -> 'rounds' -> ((r ->> 'g')::int - 1))::text)
     or jsonb_array_length(p -> 'rounds') is distinct from coalesce((p -> 'rerun' ->> 'rounds_fought')::int, 0) then
    return 'a row logged is not the re-run''s row';
  end if;
  -- her own armada is never the navy that came
  if (v_res -> 'navy' ->> 'came')::int is distinct from (p ->> 'navy_came')::int or (p ->> 'navy_free')::boolean is not true then
    return format('the navy''s count reads her own armada, or a navy ship was not freed: %s (came %s)', v_res -> 'navy', p ->> 'navy_came');
  end if;
  -- THE SHARES, by their rule, whatever the fight did
  if jsonb_array_length(v_res -> 'shares') is distinct from v_n or v_res ->> 'armada' is distinct from v_sheet ->> 'armada' then
    return format('the result does not carry a share a fleet: %s', v_res - 'rounds');
  end if;
  select coalesce(sum((e ->> 'attack')::numeric), 0) into v_guns from jsonb_array_elements(v_sheet -> 'b') e;
  for i in reverse v_n .. 1 loop
    v_f := p_order[i];
    v_sh := v_res -> 'shares' -> (i - 1);
    if v_sh ->> 'fleet' is distinct from v_f::text or v_sh ->> 'name' is distinct from v_att -> (i - 1) ->> 'name' then
      return format('share %s is not fleet %s''s: %s', i, v_f, v_sh);
    end if;
    -- hull: what her own ships lost; hands: what her own ships lost
    if abs((v_sh ->> 'hull_lost')::numeric -
         (select coalesce(sum((a.e ->> 'hull')::numeric - (z.e ->> 'hull')::numeric), 0) from jsonb_array_elements(p -> 'ships0') a(e) join jsonb_array_elements(p -> 'ships') z(e) on z.e ->> 'id' = a.e ->> 'id' where a.e ->> 'fleet' = v_f::text)) > 0.11   -- a ship's hull is kept to two places, the share to one
       or (v_sh ->> 'crew_lost')::numeric is distinct from
         (select coalesce(sum((a.e ->> 'crew')::numeric - (z.e ->> 'crew')::numeric), 0) from jsonb_array_elements(p -> 'ships0') a(e) join jsonb_array_elements(p -> 'ships') z(e) on z.e ->> 'id' = a.e ->> 'id' where a.e ->> 'fleet' = v_f::text) then
      return format('fleet %s''s share is not what her own ships lost: %s; before %s after %s', v_f, v_sh, p -> 'ships0', p -> 'ships');
    end if;
    -- the beaten row for every fleet when she was thrown back, broke off or fled; no hand otherwise
    if (v_sh ->> 'crew_lost')::numeric is distinct from
         (case when v_beaten then (select coalesce(sum((a.e ->> 'beaten')::numeric), 0) from jsonb_array_elements(p -> 'ships0') a(e) where a.e ->> 'fleet' = v_f::text) else 0 end) then
      return format('fleet %s''s hands are not the beaten row''s (beaten %s): %s', v_f, v_beaten, v_sh);
    end if;
    -- the gold: by the guns she brought, rounded down; the fleet that attacked takes what is left
    v_want := case when i = 1 then (v_res ->> 'loot')::bigint - v_given
                   when v_guns > 0 then floor((v_res ->> 'loot')::bigint * (select coalesce(sum((e ->> 'attack')::numeric), 0) from jsonb_array_elements(v_sheet -> 'b') e
                                                                             join jsonb_array_elements(p -> 'ships0') s(x) on s.x ->> 'id' = e ->> 'id' where s.x ->> 'fleet' = v_f::text) / v_guns)::bigint
                   else 0 end;
    if (v_sh ->> 'loot')::bigint is distinct from v_want then
      return format('fleet %s''s share of the gold is %s, and the rule says %s (loot %s, guns %s)', v_f, v_sh ->> 'loot', v_want, v_res ->> 'loot', v_guns);
    end if;
    v_given := v_given + (v_sh ->> 'loot')::bigint;
  end loop;
  if v_given is distinct from (v_res ->> 'loot')::bigint or (p ->> 'purse')::bigint - (p ->> 'purse0')::bigint is distinct from (v_res ->> 'loot')::bigint
     or (select coalesce(sum((e ->> 'crew_lost')::numeric), 0) from jsonb_array_elements(v_res -> 'shares') e) is distinct from (v_res ->> 'crew_lost')::numeric then
    return format('the shares do not add up to the loot (%s, purse moved %s) or to the hands lost (%s): %s', v_res ->> 'loot', (p ->> 'purse')::bigint - (p ->> 'purse0')::bigint, v_res ->> 'crew_lost', v_res -> 'shares');
  end if;
  -- THE GOLD IS 0374's FIGURE (loot follows the risk taken, read on the whole armada's hull), untouched by the sharing
  if (v_res ->> 'loot')::bigint is distinct from (p ->> 'want_loot')::bigint then
    return format('the gold that reached the purse is %s, and 0374''s rule says %s (aboard %s, risk %s, outcome %s)', v_res ->> 'loot', p ->> 'want_loot', p ->> 'aboard0', p ->> 'risk', v_res ->> 'outcome');
  end if;
  if coalesce((v_res ->> 'b_fled')::boolean, false) and ((v_res ->> 'loot')::bigint <> 0 or p -> 'battle' ->> 'status' <> 'BROKEN_OFF') then
    return 'she got away and took gold, or the battle is not BROKEN_OFF';
  end if;
  -- ONE report, under the fleet that attacked, with the shares and a log that names her fleets
  if jsonb_array_length(p -> 'events') is distinct from 1 or p -> 'events' -> 0 ->> 'fleet' is distinct from v_att -> 0 ->> 'name'
     or p -> 'events' -> 0 -> 'shares' is distinct from v_res -> 'shares' or p -> 'events' -> 0 #> '{fights,0,log,fleets}' is distinct from v_sheet -> 'fleets' then
    return format('not one report under the fleet that attacked, with the shares and the fleets named: %s', (select jsonb_agg(e - 'fights') from jsonb_array_elements(p -> 'events') e));
  end if;
  return null;
end
$b$;

do $p$
declare
  v_t     timestamptz := now();
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_fnc   uuid := (select id from public.ports where code = 'FNC');
  c_none  constant uuid := '00000000-0395-4000-8000-0000000000ff';
  c_b1    constant uuid := '00000000-0395-4000-8000-0000000000b1';
  c_b2    constant uuid := '00000000-0395-4000-8000-0000000000b2';
  c_b3    constant uuid := '00000000-0395-4000-8000-0000000000b3';
  c_b4    constant uuid := '00000000-0395-4000-8000-0000000000b4';
  c_b5    constant uuid := '00000000-0395-4000-8000-0000000000b5';
  c_b6    constant uuid := '00000000-0395-4000-8000-0000000000b6';
  h1      uuid;   -- a company with an armada of two
  h2      uuid;   -- a company with one fleet, in no armada
  h3      uuid;   -- a company with seven fleets: an armada of six, and one that stays out
  h4      uuid;   -- a company whose armada of two sails
  h5      uuid;   -- a company with an armada of three, one of them in another port
  f1      uuid[];
  f2      uuid;
  f3      uuid[];
  f4      uuid[];
  f5      uuid[];
  d       uuid;   -- a cargo ship at sea, gold aboard
  nv      uuid;   -- a navy ship at sea
  v_path  jsonb;
  v_r     jsonb;
  v_x     jsonb;
  v_old   text;
  v_new   text;
  v_tick  jsonb;
  v_late  jsonb;
  v_again jsonb;
  v_st    jsonb;
  v_stl   jsonb;
  v_fl    jsonb;
  v_e     text;
  v_e1    text;
  v_e2    text;
  v_e3    text;
  v_i     int;
  v_m     int;
  v_six   uuid[];
  v_good  text := (select g.code from public.goods g where g.bulk = 1 order by g.code limit 1);
  v_nfl   uuid;
begin
  h1 := pg_temp.house_69(1, 2);
  h2 := pg_temp.house_69(2, 1);
  h3 := pg_temp.house_69(3, 7);
  h4 := pg_temp.house_69(4, 2);
  h5 := pg_temp.house_69(5, 3);
  f1 := array(select f.id from public.fleets f where f.player_id = h1 order by f.created_at, f.id);
  f2 := (select f.id from public.fleets f where f.player_id = h2);
  f3 := array(select f.id from public.fleets f where f.player_id = h3 order by f.created_at, f.id);
  f4 := array(select f.id from public.fleets f where f.player_id = h4 order by f.created_at, f.id);
  f5 := array(select f.id from public.fleets f where f.player_id = h5 order by f.created_at, f.id);
  d := pg_temp.ship_69(100000, v_t);
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_path
    from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;

  -- the armadas, by the real door (0367). The six: the flagship fleet is the first named; the seventh fleet stays out. The three: one fleet is then moved to another port
  -- (a fixture: an armada parts only at sea, and the same rule reads her as not there).
  perform pg_temp.as_house(pg_temp.uid_69(1));
  v_r := cmd.armada_form(to_jsonb(f1), 'Armada Um');
  perform pg_temp.as_house(pg_temp.uid_69(3));
  v_x := cmd.armada_form(to_jsonb(f3[1:6]), 'Armada dos Seis');
  if (v_r ->> 'ok')::boolean is not true or (v_x ->> 'ok')::boolean is not true then
    raise exception 'PROOF 69 FAIL: the armadas did not form: % / %', v_r, v_x;
  end if;
  perform pg_temp.as_house(pg_temp.uid_69(4));
  v_r := cmd.armada_form(to_jsonb(f4), 'Armada do Mar');
  perform pg_temp.as_house(pg_temp.uid_69(5));
  v_x := cmd.armada_form(to_jsonb(f5), 'Armada dos Tres');
  if (v_r ->> 'ok')::boolean is not true or (v_x ->> 'ok')::boolean is not true then
    raise exception 'PROOF 69 FAIL: the armadas did not form: % / %', v_r, v_x;
  end if;
  update public.fleets set port_id = v_fnc where id = f5[3];
  perform pg_temp.as_house(null);

  -- ══ AB_DARK_PARITY ══ (THE SWITCH OFF: attack_enabled is false here; the lit arm for a fleet in no armada is AB_ALONE_OLD_IS_NEW below)
  for v_i in 1 .. 2 loop
    begin
      if v_i = 1 then
        perform pg_temp.to_old_69();
      end if;
      begin perform public.attack_for(h1, f1[1], d, null, v_t); v_e1 := 'attacked'; exception when others then v_e1 := sqlerrm; end;
      begin perform public.battle_open('ATTACK', f1[1], d, v_t); v_e2 := 'opened'; exception when others then v_e2 := sqlerrm; end;
      begin perform public.battle_open('PROBE', f1[1], d, v_t); v_e3 := 'opened'; exception when others then v_e3 := sqlerrm; end;
      perform pg_temp.as_house(pg_temp.uid_69(1));
      v_r := jsonb_build_object(
        'attack_for', v_e1, 'battle_open', v_e2, 'battle_probe', v_e3,
        'cmd_attack', cmd.attack(f1[1], d), 'cmd_attack_sister', cmd.attack(f1[2], d), 'cmd_preview_attack', cmd.preview_attack(f1[1], d), 'cmd_preview_sister', cmd.preview_attack(f1[2], d),
        'cmd_battle_stance', jsonb_build_array(cmd.battle_stance(c_none, 'FLEE'), cmd.battle_stance(c_none, 'FIGHT')),
        'world_battle', jsonb_build_array(world.battle(f1[1]), world.battle(f1[2])), 'world_fights', world.fights(), 'world_fight', world.fight(c_none),
        'world_fleets', world.fleets(), 'world_armadas', world.armadas(),
        'tick_battles', public.tick_battles(v_t + interval '1 hour'), 'battle_resolve', public.battle_resolve(c_none, v_t), 'navy_served', public.battle_navy_served(f1[1]));
      perform pg_temp.as_house(pg_temp.uid_69(2));
      v_r := v_r || jsonb_build_object('alone', jsonb_build_array(cmd.attack(f2, d), cmd.preview_attack(f2, d), world.battle(f2), world.fights(), world.fleets()),
        'written', jsonb_build_array((select count(*) from public.battles), (select count(*) from public.battle_sides), (select count(*) from public.battle_stances),
                                     (select count(*) from public.fleets f where f.busy_until is not null and f.player_id in (h1, h2))));
      perform pg_temp.as_house(null);
      if v_i = 1 then v_old := v_r::text; else v_new := v_r::text; end if;
      raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
    exception when sqlstate 'ZX369' then
      null;
    end;
  end loop;
  if v_old is null or v_old is distinct from v_new or not pg_temp.live_69_ok() then
    raise exception 'PROOF 69 FAIL: DARK PARITY: a door answers another thing than it did: old % new %', v_old, v_new;
  end if;
  if v_new::jsonb ->> 'attack_for' not like 'E_NOT_IN_USE:%' or v_new::jsonb ->> 'battle_open' not like 'E_NOT_YET:%' or v_new::jsonb -> 'cmd_attack' ->> 'error_code' is distinct from 'E_NOT_IN_USE'
     or v_new::jsonb -> 'cmd_preview_sister' ->> 'error_code' is distinct from 'E_NOT_IN_USE' or v_new::jsonb -> 'cmd_battle_stance' -> 0 ->> 'error_code' is distinct from 'E_NOT_IN_USE'
     or v_new::jsonb -> 'world_battle' is distinct from '[{"on": false}, {"on": false}]'::jsonb or v_new::jsonb -> 'written' is distinct from '[0, 0, 0, 0]'::jsonb
     or jsonb_array_length(v_new::jsonb -> 'world_armadas' -> 'armadas') is distinct from 1 then
    raise exception 'PROOF 69 FAIL: dark, a door did not refuse by the switch, or something was written: %', v_new;
  end if;
  raise notice 'PASS: AB_DARK_PARITY — with attack_enabled false and four armadas standing, the eight client doors, the two cores, the job, the closer and the navy''s clock answer the same text under the nine old bodies and the new (% characters); every door refuses by the switch; no battle, side, stance or hold was written', length(v_new);

  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.world_config set value = to_jsonb(100000) where key = 'attack_reach_nm';

  -- ══ AB_NO_PVP ══
  begin
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id = f2;   -- at anchor: not even "a harbour keeps the peace" stands before the law
    begin perform public.battle_open('ATTACK', f1[1], f2, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
    begin perform public.battle_open('PROBE', f1[1], f2, v_t); v_e2 := 'opened'; exception when others then v_e2 := sqlerrm; end;
    begin perform public.attack_for(h1, f1[1], f2, null, v_t); v_e3 := 'attacked'; exception when others then v_e3 := sqlerrm; end;
    perform pg_temp.as_house(pg_temp.uid_69(1));
    v_r := jsonb_build_array(cmd.attack(f1[1], f2), cmd.attack(f1[2], f2), cmd.preview_attack(f1[1], f2));
    perform pg_temp.as_house(null);
    if v_e1 not like 'E_HUMAN_TARGET:%' or v_e2 not like 'E_HUMAN_TARGET:%' or v_e3 not like 'E_HUMAN_TARGET:%'
       or exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'error_code' is distinct from 'E_HUMAN_TARGET')
       or exists (select 1 from public.battles) or exists (select 1 from public.battle_sides)
       or exists (select 1 from public.fleets f where f.id = any (f1 || f2) and (f.busy_until is not null or f.status = 'IN_BATTLE')) then
      raise exception 'PROOF 69 FAIL: A PLAYER COULD FIGHT A PLAYER: battle_open % / %, attack_for %, the doors %', v_e1, v_e2, v_e3, v_r;
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  raise notice 'PASS: AB_NO_PVP — lit, a fleet of an armada against a company''s fleet at anchor: public.battle_open (ATTACK and PROBE), public.attack_for, cmd.attack (by either fleet of hers) and the dry run all refuse E_HUMAN_TARGET; no battle, no side, nobody held';

  -- the navy ship (her scene is below; she is made here so every play sees the same world)
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  nv := pg_temp.navy_69(v_t);

  -- ══ AB_ALONE_OLD_IS_NEW ══
  v_tick := pg_temp.play_69(c_b1, f2, d, 'TICK');
  v_late := pg_temp.play_69(c_b1, f2, d, 'OLD');
  if v_tick::text is distinct from v_late::text or not pg_temp.live_69_ok() then
    raise exception 'PROOF 69 FAIL: a fleet in no armada, against a cargo ship, is not what she was: %',
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_late -> k.key)) from jsonb_each(v_tick) k where k.value::text is distinct from (v_late -> k.key)::text);
  end if;
  if jsonb_array_length(v_tick -> 'sides') <> 2 or v_tick -> 'open' -> 'sheet' ?| array['armada', 'fleets'] or v_tick -> 'attack' ? 'armada' or v_tick -> 'battle' -> 'result' ? 'shares'
     or v_tick -> 'ticks' -> 0 -> 0 ? 'armada' or jsonb_array_length(v_tick -> 'events') <> 1 or (v_tick ->> 'trace')::boolean
     or v_tick -> 'pre' -> 'estimate' is distinct from (v_tick -> 'attack') - 'ok' - 'version' - 'battle_id' or v_tick -> 'battle' ->> 'status' not in ('RESOLVED', 'BROKEN_OFF') then
    raise exception 'PROOF 69 FAIL: a fleet in no armada took something of 0395: %', v_tick - 'ticks' - 'rerun';
  end if;
  v_m := jsonb_array_length(v_tick -> 'rounds');
  v_st := pg_temp.play_69(c_b2, f2, nv, 'TICK');
  v_stl := pg_temp.play_69(c_b2, f2, nv, 'OLD');
  if v_st::text is distinct from v_stl::text or jsonb_array_length(v_st -> 'sides') <> 2 or v_st -> 'battle' ->> 'status' not in ('RESOLVED', 'BROKEN_OFF') then
    raise exception 'PROOF 69 FAIL: a fleet in no armada, against a navy ship, is not what she was: %',
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_stl -> k.key)) from jsonb_each(v_st) k where k.value::text is distinct from (v_stl -> k.key)::text);
  end if;
  -- a fleet of an armada with nobody there (her sisters are disbanded away in this play's world) is the lone fleet she was: the armada of two, disbanded, old against new
  begin
    perform pg_temp.as_house(pg_temp.uid_69(1));
    perform cmd.armada_disband((a.value ->> 'id')::uuid) from jsonb_array_elements(world.armadas() -> 'armadas') a;
    perform pg_temp.as_house(null);
    v_fl := pg_temp.play_69(c_b3, f1[1], d, 'TICK');
    v_x := pg_temp.play_69(c_b3, f1[1], d, 'OLD');
    if v_fl::text is distinct from v_x::text or jsonb_array_length(v_fl -> 'sides') <> 2 or v_fl -> 'fleets0' -> (f1[2])::text ->> 'status' <> 'DOCKED' then
      raise exception 'PROOF 69 FAIL: disbanded, a fleet does not attack as the lone fleet she was';
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  raise notice 'PASS: AB_ALONE_OLD_IS_NEW — a fleet in no armada, old bodies against new with one seed, tick by tick: against a cargo ship (% rounds, %, loot %) and against a navy ship (% rounds, %): the dry run, the answer, the open, every read, rounds, result, hulls, hands, purse, ledger, report and voyages the same text; a disbanded armada''s fleet attacks alone the same way',
    v_m, v_tick -> 'battle' -> 'result' ->> 'outcome', v_tick -> 'battle' -> 'result' ->> 'loot', jsonb_array_length(v_st -> 'rounds'), v_st -> 'battle' -> 'result' ->> 'outcome';

  -- ══ AB_WHO_IS_THERE ══
  if (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(f1[1], v_t) t) is distinct from jsonb_build_array(f1[2])
     or (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(f1[2], v_t) t) is distinct from jsonb_build_array(f1[1])
     or (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(f3[3], v_t) t) is distinct from jsonb_build_array(f3[1], f3[2], f3[4], f3[5], f3[6])
     or (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(f5[1], v_t) t) is distinct from jsonb_build_array(f5[2])
     or exists (select 1 from public.battle_armada(f5[3], v_t)) or exists (select 1 from public.battle_armada(f2, v_t)) or exists (select 1 from public.battle_armada(f3[7], v_t)) then
    raise exception 'PROOF 69 FAIL: who is there, in port';
  end if;
  begin
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id = f1[1];
    if exists (select 1 from public.battle_armada(f1[1], v_t)) or exists (select 1 from public.battle_armada(f1[2], v_t)) then
      raise exception 'PROOF 69 FAIL: a fleet at anchor has her armada there';
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  -- the armada of three with one fleet in another port: two fight, the third is not held and reads no battle
  v_tick := pg_temp.play_69(c_b4, f5[1], d, 'TICK');
  v_e := pg_temp.judge_69(v_tick, array[f5[1], f5[2]]);
  if v_e is not null or v_tick -> 'fleets0' -> (f5[3])::text ->> 'status' <> 'DOCKED' or v_tick -> 'fleets0' -> (f5[3])::text ->> 'busy' is not null
     or v_tick -> 'ticks' -> 0 -> 2 is distinct from '{"on": false}'::jsonb or (v_tick -> 'ticks' -> 0 -> 1 ->> 'on')::boolean is not true then
    raise exception 'PROOF 69 FAIL: an armada of three with one fleet elsewhere: %; the third %', v_e, v_tick -> 'fleets0' -> (f5[3])::text;
  end if;
  raise notice 'PASS: AB_WHO_IS_THERE — docked in one port: each fleet''s sisters, the flagship fleet first; nobody for a fleet at anchor, a fleet in no armada, the seventh fleet; of an armada of three with one fleet in Funchal, two fought (%) and the third was not held and read no battle', v_tick -> 'battle' -> 'result' ->> 'outcome';

  -- ══ AB_GATES_PREVIEW ══
  perform pg_temp.as_house(pg_temp.uid_69(1));
  v_r := cmd.preview_attack(f1[1], d);
  if (v_r ->> 'ok')::boolean is not true
     or v_r -> 'estimate' ->> 'word' is distinct from public.attack_word(voyage.escort_score(f1[1]) + voyage.escort_score(f1[2]), voyage.escort_score(d))
     or v_r -> 'estimate' -> 'armada' is distinct from jsonb_build_object('name', 'Armada Um', 'fleets', jsonb_build_array('Frota 1-1', 'Frota 1-2'), 'ships', 2)
     or v_r -> 'estimate' ? 'battle_id' or exists (select 1 from public.battles) or exists (select 1 from public.battle_sides)
     or exists (select 1 from public.fleets f where f.id = any (f1) and f.busy_until is not null) then
    raise exception 'PROOF 69 FAIL: the dry run does not read the whole armada, or left a trace: %', v_r;
  end if;
  v_e3 := v_r -> 'estimate' ->> 'word';
  -- by her sister's press the same armada stands, the sister first
  v_x := cmd.preview_attack(f1[2], d);
  if v_x -> 'estimate' -> 'armada' -> 'fleets' is distinct from jsonb_build_array('Frota 1-2', 'Frota 1-1') or v_x -> 'estimate' ->> 'word' is distinct from v_r -> 'estimate' ->> 'word' then
    raise exception 'PROOF 69 FAIL: her sister''s dry run is not the same armada: %', v_x;
  end if;
  begin
    update public.ships set cargo = jsonb_build_object(v_good, 1) where fleet_id = f1[2];   -- one tun in her sister's hold (written here: a warship's hold may take none by the loading door)
    v_r := cmd.preview_attack(f1[1], d);
    v_x := cmd.attack(f1[1], d);
    if v_r ->> 'error_code' is distinct from 'E_HOLD_NOT_EMPTY' or v_x ->> 'error_code' is distinct from 'E_HOLD_NOT_EMPTY' or v_r ->> 'error_message' not like 'Frota 1-2 carries cargo%'
       or v_r - 'fixes' is distinct from v_x - 'fixes' or exists (select 1 from public.battles) or exists (select 1 from public.fleets f where f.id = any (f1) and f.busy_until is not null) then
      raise exception 'PROOF 69 FAIL: a sister with cargo did not refuse the attack under her name: % / %', v_r, v_x;
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  begin
    update public.fleets set busy_until = v_t + interval '5 minutes' where id = f1[2];
    v_r := cmd.preview_attack(f1[1], d);
    v_x := cmd.attack(f1[1], d);
    if v_r ->> 'error_code' is distinct from 'E_FLEET_BUSY' or v_x ->> 'error_code' is distinct from 'E_FLEET_BUSY' or v_r ->> 'error_message' not like 'Frota 1-2 is not free%'
       or exists (select 1 from public.battles) then
      raise exception 'PROOF 69 FAIL: a sister not free did not refuse the attack under her name: % / %', v_r, v_x;
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  begin
    -- the cooldown is every fleet's that fought: the armada attacks the navy ship and the battle is closed; then, ten minutes on, her sister cannot open another on the cargo
    -- ship (the fleet that attacked is inside the cooldown, and so is she), and after the cooldown she can
    v_x := cmd.attack(f1[1], nv);
    v_m := public.tick_battles(v_t + interval '1 hour');
    begin perform public.attack_for(h1, f1[2], d, null, v_t + interval '10 minutes'); v_e1 := 'attacked'; exception when others then v_e1 := sqlerrm; end;
    begin perform public.attack_for(h1, f1[1], d, null, v_t + interval '10 minutes'); v_e2 := 'attacked'; exception when others then v_e2 := sqlerrm; end;
    if (v_x ->> 'ok')::boolean is not true or v_m <> 1 or v_e1 not like 'E_ATTACK_COOLDOWN: Frota 1-1 fought 10 minutes ago%' or v_e2 not like 'E_ATTACK_COOLDOWN: Frota 1-2 fought %'
       or (select count(*) from public.battles) <> 1 then
      raise exception 'PROOF 69 FAIL: the cooldown did not hold for every fleet that fought: % / % (attack %, closed %)', v_e1, v_e2, v_x, v_m;
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  perform pg_temp.as_house(null);
  raise notice 'PASS: AB_GATES_PREVIEW — the dry run of an armada of two: the word is the armada''s (%), it names Armada Um and both fleets, and it left no trace; a sister with cargo (E_HOLD_NOT_EMPTY), a sister not free (E_FLEET_BUSY) and, ten minutes after a battle, either fleet (E_ATTACK_COOLDOWN, under the other''s name) refuse the attack and the dry run alike; nothing moved',
    v_e3;

  -- ══ AB_TWO_TICK_LATE ══
  v_tick := pg_temp.play_69(c_b1, f1[1], d, 'TICK');
  v_late := pg_temp.play_69(c_b1, f1[1], d, 'LATE');
  v_again := pg_temp.play_69(c_b1, f1[1], d, 'TICK');
  v_e := pg_temp.judge_69(v_tick, array[f1[1], f1[2]]);
  if v_e is not null then
    raise exception 'PROOF 69 FAIL: an armada of two against a cargo ship: %', v_e;
  end if;
  if v_tick::text is distinct from v_again::text or pg_temp.left_69(v_tick) is distinct from pg_temp.left_69(v_late) or (v_late ->> 'closed')::int <> 1 then
    raise exception 'PROOF 69 FAIL: tick by tick, one late call and a re-run do not leave the same battle: %',
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_late -> k.key)) from jsonb_each(v_tick) k
        where k.key not in ('ticks', 'grow', 'closed') and k.value::text is distinct from (v_late -> k.key)::text);
  end if;
  -- the log grows at most a row a tick, and every fleet of hers reads the ONE battle at every tick: the same answer to the letter
  if exists (select 1 from generate_series(1, v_n + 1) g where ((v_tick -> 'grow' ->> (g - 1))::int - case when g = 1 then 0 else (v_tick -> 'grow' ->> (g - 2))::int end) not in (0, 1))
     or exists (select 1 from jsonb_array_elements(v_tick -> 'ticks') t where (t -> 0)::text is distinct from (t -> 1)::text or (t -> 0 ->> 'on')::boolean is not true
                   or jsonb_array_length(t -> 0 -> 'fleets') <> 2 or t -> 0 ->> 'lead' is distinct from (f1[1])::text or t -> 0 ->> 'armada' <> 'Armada Um'
                   or t -> 0 -> 'log' -> 'fleets' is distinct from v_tick -> 'open' -> 'sheet' -> 'fleets')
     or v_tick -> 'ticks' -> v_n -> 0 -> 'shares' is distinct from v_tick -> 'battle' -> 'result' -> 'shares' then
    raise exception 'PROOF 69 FAIL: the log did not grow a row a tick, or her two fleets did not read one battle: grow %, last read %', v_tick -> 'grow', v_tick -> 'ticks' -> v_n -> 1;
  end if;
  -- the same battle opened by her SISTER: the sister is first on the sheet and it is still the armada
  v_x := pg_temp.play_69(c_b2, f1[2], d, 'TICK');
  v_e := pg_temp.judge_69(v_x, array[f1[2], f1[1]]);
  if v_e is not null then
    raise exception 'PROOF 69 FAIL: the armada of two, opened by her sister: %', v_e;
  end if;
  raise notice 'PASS: AB_TWO_TICK_LATE — an armada of two against a cargo ship with % aboard: % (% rounds), loot % shared % / %, hands lost %; both fleets on the sheet, held and freed; the card counts 3 fleets; tick by tick = one late call = a re-run; both fleets read one battle at every tick; one report with the shares; opened by her sister it is the same armada, the sister first (%)',
    v_tick ->> 'aboard', v_tick -> 'battle' -> 'result' ->> 'outcome', jsonb_array_length(v_tick -> 'rounds'), v_tick -> 'battle' -> 'result' ->> 'loot',
    v_tick -> 'battle' -> 'result' -> 'shares' -> 0 ->> 'loot', v_tick -> 'battle' -> 'result' -> 'shares' -> 1 ->> 'loot', v_tick -> 'battle' -> 'result' ->> 'crew_lost', v_x -> 'battle' -> 'result' ->> 'outcome';

  -- ══ AB_LOOT_RISK ══ (0374). As shipped (floor 0, whole at 7.5 % of her hull) the plays above already held the gold to 0374's figure, whatever it was. Here the two other
  -- settings an owner has, so gold is seen to move through both rules at once: a floor of 0.4, and the rule off.
  v_e1 := format('%s of %s aboard at risk %s', v_tick -> 'battle' -> 'result' ->> 'loot', v_tick ->> 'aboard0', v_tick ->> 'risk');
  update public.world_config set value = '0.4'::jsonb where key = 'loot_risk_floor';
  v_st := pg_temp.play_69(c_b1, f1[1], d, 'TICK');
  v_e := pg_temp.judge_69(v_st, array[f1[1], f1[2]]);
  if v_e is not null or (v_st ->> 'risk')::numeric < 0.4 or (v_st ->> 'risk')::numeric > 1
     or (v_st -> 'battle' -> 'result' ->> 'outcome' in ('PLUNDERED', 'RANSOM') and (v_st -> 'battle' -> 'result' ->> 'loot')::bigint <= 0) then
    raise exception 'PROOF 69 FAIL: loot at a floor of 0.4: % (risk %, result %)', v_e, v_st ->> 'risk', (v_st -> 'battle' -> 'result') - 'rounds';
  end if;
  -- the risk is the WHOLE armada's: the hull all her fleets lost over the hull all her fleets brought, as public.loot_risk reads side b of the kept result
  if (v_st -> 'battle' -> 'result' #>> '{hull,b_start}')::numeric is distinct from (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_st -> 'open' -> 'sheet' -> 'b') e) then
    raise exception 'PROOF 69 FAIL: the hull the risk is read on is not the whole armada''s: % against the sheet', v_st -> 'battle' -> 'result' -> 'hull';
  end if;
  update public.world_config set value = '0'::jsonb where key = 'loot_risk_floor';
  update public.world_config set value = '0'::jsonb where key = 'loot_risk_full';
  v_stl := pg_temp.play_69(c_b1, f1[1], d, 'TICK');
  v_e := pg_temp.judge_69(v_stl, array[f1[1], f1[2]]);
  if v_e is not null or (v_stl ->> 'risk')::numeric <> 1 then
    raise exception 'PROOF 69 FAIL: loot with the rule off: % (risk %)', v_e, v_stl ->> 'risk';
  end if;
  update public.world_config set value = '0.075'::jsonb where key = 'loot_risk_full';
  raise notice 'PASS: AB_LOOT_RISK — the gold is 0374''s figure in every play, then shared by guns to the ducat. As shipped: %. Floor 0.4: % (risk %): loot % shared %. Rule off: % (risk 1): loot % shared %',
    v_e1, v_st -> 'battle' -> 'result' ->> 'outcome', v_st ->> 'risk', v_st -> 'battle' -> 'result' ->> 'loot', (select jsonb_agg(e -> 'loot') from jsonb_array_elements(v_st -> 'battle' -> 'result' -> 'shares') e),
    v_stl -> 'battle' -> 'result' ->> 'outcome', v_stl -> 'battle' -> 'result' ->> 'loot', (select jsonb_agg(e -> 'loot') from jsonb_array_elements(v_stl -> 'battle' -> 'result' -> 'shares') e);

  -- ══ AB_STANCE_FLEE ══
  -- Flee set 150 s in (before round 3): the first rows are the fought-through battle's; from round 3 on not a gun of her whole side fires and each row carries her chance
  v_st := pg_temp.play_69(c_b1, f1[1], d, 'TICK', '[[150, "FLEE"]]'::jsonb);
  v_stl := pg_temp.play_69(c_b1, f1[1], d, 'LATE', '[[150, "FLEE"]]'::jsonb);
  v_e := pg_temp.judge_69(v_st, array[f1[1], f1[2]]);
  if v_e is not null or pg_temp.left_69(v_st) is distinct from pg_temp.left_69(v_stl) then
    raise exception 'PROOF 69 FAIL: Flee from round 3: % (tick against late: %)', v_e, pg_temp.left_69(v_st) is not distinct from pg_temp.left_69(v_stl);
  end if;
  if exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r ->> 'g')::int <= 2 and (r -> 'row')::text is distinct from (v_tick -> 'rounds' -> ((r ->> 'g')::int - 1) -> 'row')::text)
     or exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r ->> 'g')::int <= 2 and r -> 'row' ? 'b_flee')
     or exists (select 1 from jsonb_array_elements(v_st -> 'rounds') r where (r ->> 'g')::int >= 3 and (not r -> 'row' ? 'b_flee' or (r -> 'row' -> 'b' ->> 'fired')::int is distinct from 0)) then
    raise exception 'PROOF 69 FAIL: Flee before round 3 changed an earlier round, or a fleet of hers fired after it: %', v_st -> 'rounds';
  end if;
  -- Flee from the first round, for the whole armada
  v_fl := pg_temp.play_69(c_b1, f1[1], d, 'TICK', '[[1, "FLEE"]]'::jsonb);
  v_x := pg_temp.play_69(c_b1, f1[1], d, 'LATE', '[[1, "FLEE"]]'::jsonb);
  v_e := pg_temp.judge_69(v_fl, array[f1[1], f1[2]]);
  if v_e is not null or pg_temp.left_69(v_fl) is distinct from pg_temp.left_69(v_x)
     or exists (select 1 from jsonb_array_elements(v_fl -> 'rounds') r where not r -> 'row' ? 'b_flee' or (r -> 'row' -> 'b' ->> 'fired')::int is distinct from 0)
     or (v_fl -> 'rerun' -> 'hits' ->> 'b')::int is distinct from 0 then
    raise exception 'PROOF 69 FAIL: Flee from the first round: % (rounds %)', v_e, v_fl -> 'rounds';
  end if;
  -- THE DOOR: one press, by the company, is the stance BOTH fleets read; it writes one row, the side's; another company's press is refused. Then the job fights it out under it.
  v_r := pg_temp.play_69(c_b5, f1[1], d, 'TICK', '[]'::jsonb, 'FLEE');
  v_e := pg_temp.judge_69(v_r, array[f1[1], f1[2]]);
  if v_e is not null or (v_r -> 'door' -> 'answer' ->> 'ok')::boolean is not true or v_r -> 'door' -> 'reads' is distinct from '["FLEE", "FLEE"]'::jsonb
     or v_r -> 'door' -> 'rows' is distinct from jsonb_build_array(jsonb_build_array(f1[1], 'FLEE'))
     -- every round due after the press is fought under it (the press reads the real clock: a slow run may have a round behind it already)
     or exists (select 1 from jsonb_array_elements(v_r -> 'rounds') r where (r ->> 'at')::timestamptz > (v_r -> 'stances' -> 0 ->> 1)::timestamptz and (r -> 'row' -> 'b' ->> 'fired')::int is distinct from 0) then
    raise exception 'PROOF 69 FAIL: the stance door did not act for the whole armada: % / %', v_e, v_r -> 'door';
  end if;
  begin
    perform pg_temp.as_house(pg_temp.uid_69(1));
    v_x := cmd.attack(f1[1], d);
    -- her sister's own card presses too: the door takes the company, not the fleet, so it is the same stance
    perform pg_temp.as_house(pg_temp.uid_69(2));
    v_e1 := cmd.battle_stance((v_x ->> 'battle_id')::uuid, 'FLEE') ->> 'error_code';
    perform pg_temp.as_house(pg_temp.uid_69(1));
    v_e2 := cmd.battle_stance((v_x ->> 'battle_id')::uuid, 'PAY') ->> 'error_code';
    if v_e1 is distinct from 'E_NOT_YOUR_BATTLE' or v_e2 is distinct from 'E_BAD_STANCE' or exists (select 1 from public.battle_stances)
       or world.battle(f1[2]) ->> 'stance' <> 'FIGHT' or world.battle(f1[2]) -> 'may' is distinct from '["FIGHT", "FLEE"]'::jsonb then
      raise exception 'PROOF 69 FAIL: another company''s press, or a Pay by the side that attacked, was taken: % / %', v_e1, v_e2;
    end if;
    perform pg_temp.as_house(null);
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  raise notice 'PASS: AB_STANCE_FLEE — Flee set before round 3: rounds 1 and 2 the fought-through battle''s, then silent guns on the whole side (% rounds, %); Flee from round 1: % after % round(s), status %, loot %, hands %; by the door: one press, both fleets read FLEE, one row, then % (%); tick = late each time; another company''s press and a Pay are refused',
    jsonb_array_length(v_st -> 'rounds'), v_st -> 'battle' ->> 'status', v_fl -> 'battle' -> 'result' ->> 'outcome', jsonb_array_length(v_fl -> 'rounds'), v_fl -> 'battle' ->> 'status',
    v_fl -> 'battle' -> 'result' ->> 'loot', v_fl -> 'battle' -> 'result' ->> 'crew_lost', v_r -> 'battle' ->> 'status', v_r -> 'battle' -> 'result' ->> 'outcome';

  -- ══ AB_NAVY ══
  v_tick := pg_temp.play_69(c_b6, f1[1], nv, 'TICK');
  v_late := pg_temp.play_69(c_b6, f1[1], nv, 'LATE');
  v_e := pg_temp.judge_69(v_tick, array[f1[1], f1[2]]);
  if v_e is not null or pg_temp.left_69(v_tick) is distinct from pg_temp.left_69(v_late) then
    raise exception 'PROOF 69 FAIL: the armada against a navy ship: % (tick against late: %)', v_e,
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_late -> k.key)) from jsonb_each(v_tick) k
        where k.key not in ('ticks', 'grow', 'closed') and k.value::text is distinct from (v_late -> k.key)::text);
  end if;
  if (v_tick -> 'battle' -> 'result' ->> 'loot')::bigint <> 0 or exists (select 1 from jsonb_array_elements(v_tick -> 'battle' -> 'result' -> 'shares') e where (e ->> 'loot')::bigint <> 0)
     or (v_tick -> 'battle' -> 'result' -> 'navy' ->> 'came')::int <> 0 or v_tick -> 'battle' -> 'result' -> 'navy' ->> 'line' is distinct from 'Her country''s ship fought alone.'
     or v_tick -> 'attack' ? 'navy_minutes' or v_tick -> 'ticks' -> 0 -> 0 ? 'navy_at' then
    raise exception 'PROOF 69 FAIL: a navy ship gave gold, or her own armada was read as the navy coming: % / %', v_tick -> 'battle' -> 'result' - 'rounds', v_tick -> 'attack';
  end if;
  raise notice 'PASS: AB_NAVY — an armada of two against a navy ship: % (% rounds), no gold and every share says 0; the navy that came is 0 with two fleets on her side ("%"); the ship set upon was freed; tick = late',
    v_tick -> 'battle' -> 'result' ->> 'outcome', jsonb_array_length(v_tick -> 'rounds'), v_tick -> 'battle' -> 'result' -> 'navy' ->> 'line';

  -- ══ AB_OF_SIX ══ (the third fleet attacks: she is first, then the armada's own order with her flagship fleet first)
  v_six := array[f3[3], f3[1], f3[2], f3[4], f3[5], f3[6]];
  v_tick := pg_temp.play_69(c_b1, f3[3], d, 'TICK');
  v_late := pg_temp.play_69(c_b1, f3[3], d, 'LATE');
  v_e := pg_temp.judge_69(v_tick, v_six);
  if v_e is not null or pg_temp.left_69(v_tick) is distinct from pg_temp.left_69(v_late) then
    raise exception 'PROOF 69 FAIL: an armada of six: % (tick against late: %)', v_e, pg_temp.left_69(v_tick) is not distinct from pg_temp.left_69(v_late);
  end if;
  if (v_tick -> 'card' ->> 'size')::int <> 7 or jsonb_array_length(v_tick -> 'open' -> 'sheet' -> 'b') <> 6 or jsonb_array_length(v_tick -> 'battle' -> 'result' -> 'shares') <> 6
     or v_tick -> 'fleets0' -> (f3[7])::text ->> 'status' <> 'DOCKED' or v_tick -> 'fleets0' -> (f3[7])::text ->> 'busy' is not null or v_tick -> 'ticks' -> 0 -> 6 is distinct from '{"on": false}'::jsonb
     or exists (select 1 from generate_series(0, 5) k where (v_tick -> 'ticks' -> 0 -> k)::text is distinct from (v_tick -> 'ticks' -> 0 -> 0)::text)
     or (select count(*) from jsonb_array_elements(v_tick -> 'ships0') a join jsonb_array_elements(v_tick -> 'ships') z on z ->> 'id' = a ->> 'id'
          where a ->> 'fleet' = (f3[7])::text and (a ->> 'hull' <> z ->> 'hull' or a ->> 'crew' <> z ->> 'crew')) <> 0 then
    raise exception 'PROOF 69 FAIL: six fleets as one side: card %, the seventh %', v_tick -> 'card', v_tick -> 'fleets0' -> (f3[7])::text;
  end if;
  raise notice 'PASS: AB_OF_SIX — six fleets formed by the door, the third attacks: she is first on the sheet, then the flagship fleet and the rest in order; the card counts 7 fleets; six held and freed; % (% rounds), loot % in six shares %, hands %; tick = late; the seventh fleet took no part',
    v_tick -> 'battle' -> 'result' ->> 'outcome', jsonb_array_length(v_tick -> 'rounds'), v_tick -> 'battle' -> 'result' ->> 'loot',
    (select jsonb_agg(e -> 'loot') from jsonb_array_elements(v_tick -> 'battle' -> 'result' -> 'shares') e), v_tick -> 'battle' -> 'result' ->> 'crew_lost';

  -- ══ AB_AT_SEA ══ (the real order: both fleets leave Lisbon for Funchal on one schedule; then she attacks from the sea)
  -- the sailing armada is manned to sail (a ship of the line asks more hands than the houses above carry) and has the purse for her stores
  update public.ships s set crew = c.crew_required, water_t = 0, food_t = 0 from public.ship_classes c where c.id = s.class_id and s.fleet_id = any (f4);
  update public.players set ducats = 50000000 where id = h4;
  perform pg_temp.as_house(pg_temp.uid_69(4));
  v_r := cmd.armada_sail((select a.id from public.armadas a where a.player_id = h4), 'FNC', v_path, false);
  perform pg_temp.as_house(null);
  if (v_r ->> 'ok')::boolean is not true or (select count(*) from public.fleets f where f.id = any (f4) and f.status = 'SAILING') <> 2 then
    raise exception 'PROOF 69 FAIL: the armada did not sail: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(240) where key = 'attack_reach_nm';   -- the knob's own value, for who is there
  if (select jsonb_agg(t.fleet_id) from public.battle_armada(f4[1], v_t) t) is distinct from jsonb_build_array(f4[2])
     or (select jsonb_agg(t.fleet_id) from public.battle_armada(f4[2], v_t) t) is distinct from jsonb_build_array(f4[1]) then
    raise exception 'PROOF 69 FAIL: two fleets sailing under one lead voyage, at one point, are not there for each other';
  end if;
  update public.world_config set value = to_jsonb(-1) where key = 'attack_reach_nm';
  if exists (select 1 from public.battle_armada(f4[1], v_t)) or not exists (select 1 from public.battle_armada(f1[1], v_t)) then
    raise exception 'PROOF 69 FAIL: with no reach a sister at sea is still there, or a sister in port is not';
  end if;
  begin
    -- and a fleet whose voyage is no longer under her lead (parted) is not there, whatever the reach
    update public.world_config set value = to_jsonb(100000) where key = 'attack_reach_nm';
    delete from public.armada_voyages av using public.voyages v where v.id = av.voyage_id and v.fleet_id = f4[2];
    if exists (select 1 from public.battle_armada(f4[1], v_t)) then
      raise exception 'PROOF 69 FAIL: a fleet that sails under no lead voyage of hers is there';
    end if;
    raise exception using errcode = 'ZX369', message = 'PASS_ROLLBACK_69';
  exception when sqlstate 'ZX369' then
    null;
  end;
  update public.world_config set value = to_jsonb(100000) where key = 'attack_reach_nm';
  v_tick := pg_temp.play_69(c_b1, f4[1], d, 'TICK');
  v_late := pg_temp.play_69(c_b1, f4[1], d, 'LATE');
  v_e := pg_temp.judge_69(v_tick, array[f4[1], f4[2]], true);
  if v_e is not null or pg_temp.left_69(v_tick) is distinct from pg_temp.left_69(v_late) then
    raise exception 'PROOF 69 FAIL: an armada at sea: % (tick against late: %)', v_e,
      (select jsonb_object_agg(k.key, jsonb_build_array(k.value, v_late -> k.key)) from jsonb_each(v_tick) k
        where k.key not in ('ticks', 'grow', 'closed') and k.value::text is distinct from (v_late -> k.key)::text);
  end if;
  -- both held for the same span, the hold cut with the battle for both, and one arrival still
  if v_tick -> 'voyages' -> (f4[1])::text -> 'holds' is distinct from v_tick -> 'voyages' -> (f4[2])::text -> 'holds'
     or jsonb_array_length(v_tick -> 'voyages' -> (f4[1])::text -> 'holds') <> 1
     or (v_tick -> 'voyages' -> (f4[1])::text -> 'holds' -> 0 ->> 'held_until')::timestamptz is distinct from (v_tick -> 'battle' ->> 'resolves_at')::timestamptz
     or (v_tick -> 'voyages' -> (f4[1])::text -> 'holds' -> 0 ->> 'held_from')::timestamptz is distinct from (v_tick -> 'battle' ->> 'started_at')::timestamptz
     or v_tick -> 'voyages' -> (f4[1])::text ->> 'eta' is distinct from v_tick -> 'voyages' -> (f4[2])::text ->> 'eta'
     or v_tick -> 'voyages' -> (f4[1])::text ->> 'delay' is distinct from v_tick -> 'voyages' -> (f4[2])::text ->> 'delay'
     or v_tick -> 'voyages' -> (f4[1])::text ->> 'days' is distinct from v_tick -> 'voyages' -> (f4[2])::text ->> 'days'
     or abs(extract(epoch from (v_tick -> 'voyages' -> (f4[1])::text ->> 'eta')::timestamptz
          - ((select v.eta from public.voyages v where v.fleet_id = f4[1] and v.status = 'SAILING') + ((v_tick -> 'battle' ->> 'resolves_at')::timestamptz - (v_tick -> 'battle' ->> 'started_at')::timestamptz)))) > 1
     or v_tick -> 'fleets' -> (f4[2])::text ->> 'status' <> 'SAILING' then
    raise exception 'PROOF 69 FAIL: at sea the two fleets were not held alike, or do not arrive together: % / % (unheld eta %)', v_tick -> 'voyages' -> (f4[1])::text, v_tick -> 'voyages' -> (f4[2])::text,
      (select v.eta from public.voyages v where v.fleet_id = f4[1] and v.status = 'SAILING');
  end if;
  raise notice 'PASS: AB_AT_SEA — an armada of two sailing for Funchal on one order attacks: both held by one free hold, % (% rounds); the hold is cut at the battle''s end for both and both still arrive at one instant, later by exactly the battle (% s); tick = late; at the knob''s 240 nm a sister at the same point is there, with no reach or under no lead voyage she is not',
    v_tick -> 'battle' -> 'result' ->> 'outcome', jsonb_array_length(v_tick -> 'rounds'),
    extract(epoch from (v_tick -> 'battle' ->> 'resolves_at')::timestamptz - (v_tick -> 'battle' ->> 'started_at')::timestamptz);

  if not pg_temp.live_69_ok() then
    raise exception 'PROOF 69 FAIL: an old body outlived its subtransaction';
  end if;
end
$p$;
