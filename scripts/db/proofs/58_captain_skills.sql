-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 58 — A CAPTAIN'S SKILL IS RAISED WITH REPUTATION  (migration 0355, slice R2 of docs/REPUTATION.md, owner row 317)
--
--   The migration's self-assert proves the hunks, the parity and one navigator on a hand-made crew. This proof plays the
--   doors the game uses (public.new_house, public.sign_officer, public.seat_captain_for, cmd.captain_skill_up) on a crew
--   of seven in two hulls, and holds every figure to a number worked out here from the tables (the amount, not "more
--   than before") and to the readers that own it: public.crew_pct, the speed, the hold, the price, the sheet, the crew
--   bonuses and the fight. Everything rolls back with proof.mjs's transaction. The switches it needs are set here, in
--   this transaction (as proof 44 does), and go back with it.
--
-- @pass SKILL_MERCHANT_EQUAL  every merchant fleet x 4 effects (speed, hold, spread, crew_saved) reads what it read before a player bought 40 steps; no merchant's captain has a row; a merchant's company is refused
-- @pass SKILL_FIGHT_BYTES     30 seeded fights and the side the fight reads (voyage.fleet_hulls) are byte for byte the same with no step bought, before and after the skills are read and a step is refused; a Gunner at her ceiling moves that side's accuracy and reach and nothing else
-- @pass SKILL_FIRST_UPGRADE   a first step through cmd.captain_skill_up: 50 Reputation, her speed term x 1.04, the fleet's speed up by exactly that, the purse and the ledger untouched, one CAPTAIN_SKILL event, the sheet row printed
-- @pass SKILL_ONE_TERM        at step 3 the speed, the hold and the price terms are x 1.12, and public.crew_pct, voyage.fleet_speed, public.ship_hold_capacity, world.spread_effective, world.captain_stats and world.crew_bonuses all move by that one factor
-- @pass SKILL_REFUSALS        lit with combat off a Gunner's skill does nothing and is refused E_TRAIT_IDLE (and is taken with combat on); at sea E_NOT_IN_PORT; ashore is allowed; each refusal writes nothing
-- @pass SKILL_MAX_BY_GRADE    C stops at 3, B at 5, S at 10, each refused E_TOP_RANK in words; the ten steps cost 50, 150, 300, 500, 750, 1050, 1400, 1800, 2250, 2750 = 11,000 and the book stays chained
-- @pass SKILL_FLOOR           a promoted captain keeps her steps and they stand on her new grade's floor: 5.5 x 1.12, not 4.5 x 1.12 and not the floor alone
-- @pass SKILL_CAP             the cap is the crew's: three navigators' terms add up past 25 % and public.crew_pct reads 25 %; a term above a lowered cap still reads whole
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table merch_58 (fleet uuid not null, effect text not null, v text not null) on commit drop;
create temp table fights_58 (set text not null, raider numeric not null, day int not null, result jsonb not null) on commit drop;

create function pg_temp.po_58(p_player uuid, p_code text) returns uuid language sql stable as $f$
  select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player and o.code = p_code
$f$;
-- her own term for one effect, as public.crew_terms gives it
create function pg_temp.term_58(p_fleet uuid, p_player uuid, p_code text, p_effect text) returns numeric language sql as $f$
  select sum(t.value_pct) from public.crew_terms(p_fleet) t where t.player_officer_id = pg_temp.po_58(p_player, p_code) and t.effect = p_effect
$f$;
-- n steps through the core, each one taken or the proof stops
create function pg_temp.up_58(p_player uuid, p_code text, p_trait text, p_n int) returns jsonb language plpgsql as $f$
declare
  v_r jsonb;
begin
  for i in 1 .. p_n loop
    v_r := public.captain_skill_up_for(p_player, p_code, p_trait);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 58 FAIL: step % of % for % was refused: %', i, p_trait, p_code, v_r;
    end if;
  end loop;
  return v_r;
end $f$;
-- the sheet's part for one effect (world.captain_stats), in per cent
create function pg_temp.sheet_58(p_code text, p_effect text) returns numeric language sql as $f$
  select (p ->> 'pct')::numeric from jsonb_array_elements(world.captain_stats(p_code) -> 'stats') s, jsonb_array_elements(s -> 'parts') p where p ->> 'effect' = p_effect
$f$;

do $p$
declare
  c_uid1  constant uuid := '00000000-0358-4000-8000-000000000001';
  c_seed  constant uuid := '00000000-0358-4000-8000-0000000000f1';
  c_costs constant int[] := array[50, 150, 300, 500, 750, 1050, 1400, 1800, 2250, 2750];
  v_p     uuid;
  v_npc   uuid;
  v_fleet uuid;
  v_s1    uuid;   -- the navire: seats 1 captain, 2 trading, 3 exploration, 4 combat, 5 trading
  v_s2    uuid;   -- the barca:  seats 1 captain, 2 trading, 3 exploration
  v_lis   uuid;
  v_good  uuid;
  v_r     jsonb;
  v_x     jsonb;
  v_c     text;
  v_seat  jsonb;
  v_n     numeric;
  v_m     numeric;
  v_i     int;
  v_cnt   int;
  v_hit   int;
  v_bal   int;
  v_gold  bigint;
  v_led   bigint;
  v_ev    bigint;
  v_sp0   numeric;
  v_sp1   numeric;
  v_t0    jsonb;   -- her terms before any step: {speed, hold, spread}
  v_c0    jsonb;   -- public.crew_pct before
  v_h0    numeric;
  v_q0    numeric;
  v_sum   numeric;
  v_side0 text;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ──
  update public.world_config set value = 'true'::jsonb  where key in ('levels_bite', 'crew_bite', 'combat_bite', 'skills_bite', 'reputation_on');
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  if (select count(*) from public.world_config where key in ('levels_bite', 'crew_bite', 'combat_bite', 'skills_bite', 'reputation_on', 'economy_closed')) <> 6 then
    raise exception 'PROOF 58 FAIL: a switch the proof sets has no world_config row';
  end if;
  if public.wc_int('rep_skill_base') <> 50 or public.wc_num('captain_skill_rank_pct') <> 4 or public.captain_rank_mult(2) <> 1.08
     or (select string_agg(g.code || g.max_rank, ',' order by g.ord) from public.captain_grades g) <> 'C3,B5,A7,S10' then
    raise exception 'PROOF 58 FAIL: the knobs or the ceilings are not the ones this proof works its figures from (50, 4 %%, C 3, B 5, A 7, S 10)';
  end if;
  if exists (select 1 from public.captain_trait_rank) then
    raise exception 'PROOF 58 FAIL: the world under the proof already holds a step';
  end if;

  -- what every merchant fleet reads now, in this world's switches, before any step exists (compared at the end, as text: not a digit may move)
  insert into pg_temp.merch_58
  select f.id, e.e, public.crew_pct(f.id, null, e.e)::text
    from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
   cross join (values ('speed'), ('hold'), ('spread'), ('crew_saved')) e(e);

  -- ── THE PROBE HOUSE, ITS TWO HULLS, ITS CAST (the doors the game uses) ──
  v_p := public.new_house(c_uid1, 'Casa da Pericia 0358', 'PRT', 'LIS', 'Pericia', 'navire', 'Pericia', 400000);
  select f.id, f.port_id into v_fleet, v_lis from public.fleets f where f.player_id = v_p;
  select s.id into v_s1 from public.ships s where s.fleet_id = v_fleet;
  v_s2 := public.commission_ship(v_p, v_fleet, 'barca', 'Segunda', false, true);
  if (select string_agg(public.cabin_focus(c.code, n), ',' order by n) from public.ships s join public.ship_classes c on c.id = s.class_id, generate_series(1, 5) n where s.id = v_s1) <> 'captain,trading,exploration,combat,trading'
     or (select string_agg(public.cabin_focus(c.code, n), ',' order by n) from public.ships s join public.ship_classes c on c.id = s.class_id, generate_series(1, 3) n where s.id = v_s2) <> 'captain,trading,exploration' then
    raise exception 'PROOF 58 FAIL: the hulls'' cabins are not the ones this proof seats for';
  end if;
  foreach v_c in array array['ELCANO', 'COENQM', 'WELSER', 'YIJANGSON', 'TARTAGLIA', 'PIRIREIS', 'DIASNAV', 'BERGENNAV'] loop
    v_r := public.sign_officer(v_p, v_c, null);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 58 FAIL: %''s signing was refused: %', v_c, v_r;
    end if;
  end loop;
  -- ELCANO the exploration cabin, COENQM and WELSER the trading cabins, YIJANGSON the combat cabin, TARTAGLIA the Captain's. PIRIREIS, DIASNAV and BERGENNAV wait ashore.
  for v_seat in select * from jsonb_array_elements('[["ELCANO",3],["COENQM",2],["WELSER",5],["YIJANGSON",4],["TARTAGLIA",1]]'::jsonb) loop
    v_r := public.seat_captain_for(v_p, v_seat ->> 0, v_s1, (v_seat ->> 1)::int);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 58 FAIL: could not seat %: %', v_seat, v_r;
    end if;
  end loop;
  for v_seat in select * from jsonb_array_elements('[["ELCANO",["NAVIGATOR"]],["COENQM",["QUARTERMASTER"]],["WELSER",["PURSER"]],["YIJANGSON",["GUNNER"]],["TARTAGLIA",["GUNNER"]],["PIRIREIS",["NAVIGATOR"]],["DIASNAV",["NAVIGATOR"]],["BERGENNAV",["NAVIGATOR"]]]'::jsonb) loop
    v_r := public.captain_traits_set_for(v_p, v_seat ->> 0, array(select jsonb_array_elements_text(v_seat -> 1)));
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 58 FAIL: could not set the skills %: %', v_seat, v_r;
    end if;
  end loop;
  if (select string_agg(o.code || ':' || cp.grade || ':' || ct.trait || ':' || (ct.base_pct + 0)::float8, ',' order by o.code)
        from public.officers o join public.captain_profile cp on cp.officer_id = o.id join public.captain_traits ct on ct.officer_id = o.id and ct.ord = 1
       where o.code in ('ELCANO', 'WELSER', 'TARTAGLIA', 'PIRIREIS', 'DIASNAV', 'BERGENNAV'))
     is distinct from 'BERGENNAV:C:NAVIGATOR:5,DIASNAV:A:NAVIGATOR:8,ELCANO:S:NAVIGATOR:9,PIRIREIS:S:NAVIGATOR:8.5,TARTAGLIA:C:GUNNER:4.5,WELSER:S:PURSER:9' then
    raise exception 'PROOF 58 FAIL: the cast is not the one this proof works its figures from (ELCANO S 9, PIRIREIS S 8.5, DIASNAV A 8, BERGENNAV C 5, TARTAGLIA C 4.5, WELSER S 9)';
  end if;
  v_i := public.reputation_credit(v_p, 'built', 40000, 'proof58:seed');
  if v_i <> 40000 then
    raise exception 'PROOF 58 FAIL: the probe''s Reputation was not booked';
  end if;
  perform cmd.assume_identity(c_uid1);

  -- ══ SKILL_FIGHT_BYTES ══ (first: no step has been bought anywhere)
  -- The fight reads the fleet through voyage.fleet_hulls (each hull's accuracy, reach and attack, the captains' share in them). Both are kept whole: the side it reads, and 30 seeded fights.
  v_side0 := voyage.fleet_hulls(v_fleet)::text;
  insert into pg_temp.fights_58 select 'before', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  foreach v_c in array array['ELCANO', 'COENQM', 'WELSER', 'YIJANGSON', 'TARTAGLIA'] loop
    perform world.captain_skills(v_c);
  end loop;
  v_r := public.captain_skill_up_for(v_p, 'YIJANGSON', 'NOSUCHSKILL');
  if (v_r ->> 'error_code') is distinct from 'E_TRAIT_NOT_KNOWN' then
    raise exception 'PROOF 58 FAIL: a skill nobody has was not refused: %', v_r;
  end if;
  insert into pg_temp.fights_58 select 'after', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  select count(*), count(*) filter (where b.result::text is distinct from a.result::text), count(*) filter (where a.result ->> 'outcome' <> 'EVADED')
    into v_cnt, v_i, v_hit
    from pg_temp.fights_58 a join pg_temp.fights_58 b on b.set = 'after' and b.raider = a.raider and b.day = a.day where a.set = 'before';
  if v_cnt <> 30 or v_hit < 10 then
    raise exception 'PROOF 58 FAIL: only % of % fights are fought out (a fight that is never fought proves nothing)', v_hit, v_cnt;
  end if;
  if v_i <> 0 or voyage.fleet_hulls(v_fleet)::text <> v_side0 then
    raise exception 'PROOF 58 FAIL: with no step bought % of % fights changed, or the side the fight reads moved', v_i, v_cnt;
  end if;
  -- THE COMPARISON CAN FAIL: YIJANGSON's Gunner (in the combat cabin) raised to her grade's ceiling moves the side the fight reads: the flagship's accuracy and reach.
  -- (A hull's stat is served rounded, and one step of a 7.5 % Gunner is +0.3 points: on this hull it moves reach by 1 and accuracy by none. So the control is the side itself, and the fights that
  -- change with it are counted and printed, not required: a seeded roll seldom falls on the one point of accuracy the ceiling adds.)
  v_m := (select g.max_rank from public.captain_profile cp join public.captain_grades g on g.code = cp.grade join public.officers o on o.id = cp.officer_id where o.code = 'YIJANGSON');
  v_r := pg_temp.up_58(v_p, 'YIJANGSON', 'GUNNER', v_m::int);
  v_x := (select h from jsonb_array_elements(voyage.fleet_hulls(v_fleet)) h where (h ->> 'id')::uuid = v_s1);
  v_r := (select h from jsonb_array_elements(v_side0::jsonb) h where (h ->> 'id')::uuid = v_s1);
  if (v_x ->> 'accuracy')::numeric <= (v_r ->> 'accuracy')::numeric or (v_x ->> 'reach')::numeric <= (v_r ->> 'reach')::numeric
     or (v_x - 'accuracy' - 'reach') is distinct from (v_r - 'accuracy' - 'reach') then
    raise exception 'PROOF 58 FAIL: a Gunner at step % did not raise the accuracy and the reach the fight reads, and those alone: % to %', v_m, v_r, v_x;
  end if;
  insert into pg_temp.fights_58 select 'one', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  select count(*) into v_i from pg_temp.fights_58 a join pg_temp.fights_58 b on b.set = 'one' and b.raider = a.raider and b.day = a.day
   where a.set = 'before' and b.result::text is distinct from a.result::text;
  raise notice 'PASS: SKILL_FIGHT_BYTES — % seeded fights (% fought out) and the side the fight reads are byte for byte the same with no step bought, after 5 reads of the skills and a refused step; with YIJANGSON''s Gunner at step % the flagship the fight reads has accuracy % to % and reach % to %, nothing else moved, and % of the 30 fights differ',
    v_cnt, v_hit, v_m, v_r ->> 'accuracy', v_x ->> 'accuracy', v_r ->> 'reach', v_x ->> 'reach', v_i;

  -- ══ SKILL_FIRST_UPGRADE ══ (through the client's door)
  v_t0 := jsonb_build_object('speed', pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed'), 'hold', pg_temp.term_58(v_fleet, v_p, 'COENQM', 'hold'), 'spread', pg_temp.term_58(v_fleet, v_p, 'WELSER', 'spread'));
  v_c0 := jsonb_build_object('speed', public.crew_pct(v_fleet, null, 'speed'), 'hold', public.crew_pct(v_fleet, null, 'hold'), 'spread', public.crew_pct(v_fleet, null, 'spread'));
  if (v_t0 ->> 'speed')::numeric <> 9 or (v_c0 ->> 'speed')::numeric <> 0.09 or (v_t0 ->> 'hold')::numeric <= 0 or (v_t0 ->> 'spread')::numeric <> 9 then
    raise exception 'PROOF 58 FAIL: before any step the crew does not read ELCANO 9 %% speed, WELSER 9 %% prices and a hold term: % %', v_t0, v_c0;
  end if;
  select g.id into v_good from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_lis order by g.code limit 1;
  v_sp0 := voyage.fleet_speed(v_fleet);
  v_h0  := public.ship_hold_capacity(v_s1);
  v_q0  := world.spread_effective(v_lis, v_good, v_fleet, false);
  select pl.ducats into v_gold from public.players pl where pl.id = v_p;
  v_led := (select count(*) from public.ledger l where l.player_id = v_p);
  v_ev  := (select count(*) from public.events e where e.player_id = v_p);
  v_bal := (world.captain_skills('ELCANO') ->> 'reputation')::int;
  set local role authenticated;
  v_r := cmd.captain_skill_up('elcano', 'navigator');
  v_x := world.captain_skills('ELCANO');
  reset role;
  v_sp1 := voyage.fleet_speed(v_fleet);
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'rank')::int <> 1 or (v_r ->> 'cost')::int <> 50 or (v_r ->> 'reputation')::int <> v_bal - 50
     or (v_x ->> 'reputation')::int <> v_bal - 50 or (v_x -> 'skills' -> 0 ->> 'trait') <> 'NAVIGATOR' or (v_x -> 'skills' -> 0 ->> 'rank')::int <> 1
     or (v_x -> 'skills' -> 0 ->> 'max')::int <> 10 or (v_x -> 'skills' -> 0 ->> 'pct_now')::numeric <> 4 or (v_x -> 'skills' -> 0 ->> 'cost')::int <> 150
     or (v_x -> 'skills' -> 0 ->> 'can')::boolean is not true or jsonb_array_length(v_x -> 'skills') <> 10 then
    raise exception 'PROOF 58 FAIL: the first step through the door is not step 1 for 50, read back as 1 / 10, +4 %%, next 150: % / %', v_r, v_x -> 'skills' -> 0;
  end if;
  if pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed') <> 9 * 1.04 or public.crew_pct(v_fleet, null, 'speed') <> 0.09 * 1.04
     or abs(v_sp1 - v_sp0 / (1 + 0.09) * (1 + 0.09 * 1.04)) > 0.0002 or v_sp1 <= v_sp0 then   -- the speed is served to 4 places
    raise exception 'PROOF 58 FAIL: one step did not make her speed term 9 x 1.04 and the fleet''s speed follow it: term %, crew %, speed % to %',
      pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed'), public.crew_pct(v_fleet, null, 'speed'), v_sp0, v_sp1;
  end if;
  if (select pl.ducats from public.players pl where pl.id = v_p) <> v_gold or (select count(*) from public.ledger l where l.player_id = v_p) <> v_led
     or (select count(*) from public.events e where e.player_id = v_p) <> v_ev + 1
     or (select e.payload from public.events e where e.player_id = v_p and e.kind = 'CAPTAIN_SKILL' and e.payload ->> 'officer' = 'ELCANO')
          is distinct from jsonb_build_object('officer', 'ELCANO', 'name', (select o.name from public.officers o where o.code = 'ELCANO'), 'trait', 'NAVIGATOR', 'word', 'Navigator', 'rank', 1, 'cost', 50) then
    raise exception 'PROOF 58 FAIL: a step moved the purse or the ledger, or did not write exactly one CAPTAIN_SKILL event {officer, name, trait, word, rank, cost}';
  end if;
  set local role anon;
  begin
    perform cmd.captain_skill_up('ELCANO', 'NAVIGATOR');
    raise exception 'PROOF 58 FAIL: anon called the door';
  exception when insufficient_privilege then null;
  end;
  begin
    perform world.captain_skills('ELCANO');
    raise exception 'PROOF 58 FAIL: anon read the skills';
  exception when insufficient_privilege then null;
  end;
  reset role;
  raise notice 'PASS: SKILL_FIRST_UPGRADE — ELCANO''s Navigator, step 1 through cmd.captain_skill_up: Reputation % to %; her speed term 9 to %; the fleet''s speed % to % kn; purse and ledger untouched; one CAPTAIN_SKILL event; the sheet row: % · % / % · +% %% [ Upgrade · % ]',
    v_bal, v_r ->> 'reputation', trim_scale(pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed')), v_sp0, v_sp1,
    v_x -> 'skills' -> 0 ->> 'word', v_x -> 'skills' -> 0 ->> 'rank', v_x -> 'skills' -> 0 ->> 'max', trim_scale((v_x -> 'skills' -> 0 ->> 'pct_now')::numeric), v_x -> 'skills' -> 0 ->> 'cost';

  -- ══ SKILL_ONE_TERM ══ (step 3 on each of the three: x 1.12, everywhere)
  v_r := pg_temp.up_58(v_p, 'ELCANO', 'NAVIGATOR', 2);
  v_r := pg_temp.up_58(v_p, 'COENQM', 'QUARTERMASTER', 3);
  v_r := pg_temp.up_58(v_p, 'WELSER', 'PURSER', 3);
  for v_seat in select * from jsonb_array_elements('[["ELCANO","speed"],["COENQM","hold"],["WELSER","spread"]]'::jsonb) loop
    v_n := (v_t0 ->> (v_seat ->> 1))::numeric * 1.12;
    if pg_temp.term_58(v_fleet, v_p, v_seat ->> 0, v_seat ->> 1) <> v_n
       or public.crew_pct(v_fleet, null, v_seat ->> 1) <> (v_c0 ->> (v_seat ->> 1))::numeric * 1.12
       or public.crew_pct(v_fleet, null, v_seat ->> 1) * 100 <> v_n
       or pg_temp.sheet_58(v_seat ->> 0, v_seat ->> 1) <> v_n
       or (select (q ->> 'pct')::numeric from jsonb_array_elements(world.crew_bonuses(v_fleet) -> 'totals') q where q ->> 'effect' = v_seat ->> 1) <> round(v_n, 2)
       or (select q ->> 'line' from jsonb_array_elements(world.crew_bonuses(v_fleet) -> 'lines') q where q ->> 'effect' = v_seat ->> 1)
            is distinct from public.trait_effect_words((select ce.words from public.crew_effects ce where ce.code = v_seat ->> 1), v_n, null) then
      raise exception 'PROOF 58 FAIL: at step 3 % is not x 1.12 in every reader: term %, crew_pct %, sheet %, bonuses %', v_seat, pg_temp.term_58(v_fleet, v_p, v_seat ->> 0, v_seat ->> 1),
        public.crew_pct(v_fleet, null, v_seat ->> 1), pg_temp.sheet_58(v_seat ->> 0, v_seat ->> 1), world.crew_bonuses(v_fleet);
    end if;
  end loop;
  v_n := public.crew_pct(v_fleet, null, 'spread', v_good) + public.crew_pct(v_fleet, null, 'category_spread', v_good);
  if abs(voyage.fleet_speed(v_fleet) - v_sp0 / (1 + 0.09) * (1 + 0.09 * 1.12)) > 0.0002
     or public.ship_hold_capacity(v_s1) <> floor(world.ship_stat(v_s1, 'hold') * (1 + (v_c0 ->> 'hold')::numeric * 1.12))
     or public.ship_hold_capacity(v_s1) < v_h0
     or world.spread_effective(v_lis, v_good, v_fleet, false)
        <> greatest(world.spread(v_lis) * public.wc_num('haggle_spread_floor_frac'), world.spread(v_lis) * (1 - v_n) * (1 - public.investor_shave(v_p, v_lis)))
     or world.spread_effective(v_lis, v_good, v_fleet, false) >= v_q0 then
    raise exception 'PROOF 58 FAIL: the speed, the hold or the price does not read the raised term: speed % (from %), hold % (from %), spread % (from %)',
      voyage.fleet_speed(v_fleet), v_sp0, public.ship_hold_capacity(v_s1), v_h0, world.spread_effective(v_lis, v_good, v_fleet, false), v_q0;
  end if;
  raise notice 'PASS: SKILL_ONE_TERM — at step 3 the terms are x 1.12 (speed 9 to %, hold % to %, prices 9 to %) and public.crew_pct, the sheet and the crew bonuses read them to the digit; the fleet''s speed % to % kn, the flagship''s hold % to % tons, a spread at Lisbon % to %',
    9 * 1.12, trim_scale((v_t0 ->> 'hold')::numeric), trim_scale((v_t0 ->> 'hold')::numeric * 1.12), 9 * 1.12, v_sp0, voyage.fleet_speed(v_fleet), v_h0, public.ship_hold_capacity(v_s1), round(v_q0, 6), round(world.spread_effective(v_lis, v_good, v_fleet, false), 6);

  -- ══ SKILL_REFUSALS ══
  v_bal := (select b.balance from public.reputation_balance b where b.player_id = v_p);
  v_i := (select count(*) from public.captain_trait_rank r join public.player_officers po on po.id = r.player_officer_id where po.player_id = v_p);
  update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
  v_r := public.captain_skill_up_for(v_p, 'TARTAGLIA', 'GUNNER');
  v_x := (select q from jsonb_array_elements(world.captain_skills('TARTAGLIA') -> 'skills') q where q ->> 'trait' = 'GUNNER');
  if (v_r ->> 'error_code') is distinct from 'E_TRAIT_IDLE' or (v_r ->> 'error_message') is distinct from 'Gunner does nothing yet.'
     or (v_x ->> 'can')::boolean is not false or (v_x ->> 'in_use')::boolean is not false or (v_x ->> 'why') is distinct from 'Gunner does nothing yet.' or (v_x ->> 'why_code') <> 'E_TRAIT_IDLE' then
    raise exception 'PROOF 58 FAIL: with combat off a Gunner''s skill was not refused E_TRAIT_IDLE, or the read did not say so: % / %', v_r, v_x;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -12.0 where id = v_fleet;
  v_r := public.captain_skill_up_for(v_p, 'TARTAGLIA', 'GUNNER');
  if (v_r ->> 'error_code') is distinct from 'E_NOT_IN_PORT' or (v_r ->> 'error_message') not like '% is at sea aboard Pericia. A skill is raised in port.' then
    raise exception 'PROOF 58 FAIL: at sea a step was not refused E_NOT_IN_PORT: %', v_r;
  end if;
  if (select b.balance from public.reputation_balance b where b.player_id = v_p) <> v_bal
     or (select count(*) from public.captain_trait_rank r join public.player_officers po on po.id = r.player_officer_id where po.player_id = v_p) <> v_i then
    raise exception 'PROOF 58 FAIL: a refusal spent Reputation or wrote a step';
  end if;
  -- ashore is allowed: BERGENNAV sits nowhere, and the fleet being at sea does not hold her
  v_r := pg_temp.up_58(v_p, 'BERGENNAV', 'NAVIGATOR', 1);
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fleet;
  raise notice 'PASS: SKILL_REFUSALS — combat off: "Gunner does nothing yet." (E_TRAIT_IDLE, and the read says the same); at sea: E_NOT_IN_PORT; neither wrote anything; BERGENNAV, ashore, took her step';

  -- ══ SKILL_MAX_BY_GRADE ══
  v_r := pg_temp.up_58(v_p, 'BERGENNAV', 'NAVIGATOR', 2);   -- a C: 3
  v_r := public.captain_skill_up_for(v_p, 'BERGENNAV', 'NAVIGATOR');
  if (v_r ->> 'error_code') is distinct from 'E_TOP_RANK' or (v_r ->> 'error_message') is distinct from 'Navigator is 3 of 3: a B captain reaches 5.' then
    raise exception 'PROOF 58 FAIL: a C captain''s fourth step was not refused in words: %', v_r;
  end if;
  v_r := pg_temp.up_58(v_p, 'ELCANO', 'NAVIGATOR', 7);      -- an S: 10
  v_r := public.captain_skill_up_for(v_p, 'ELCANO', 'NAVIGATOR');
  if (v_r ->> 'error_code') is distinct from 'E_TOP_RANK' or (v_r ->> 'error_message') is distinct from 'Navigator is 10 of 10.' then
    raise exception 'PROOF 58 FAIL: an S captain''s eleventh step was not refused in words: %', v_r;
  end if;
  if (select array_agg((e.payload ->> 'cost')::int order by (e.payload ->> 'rank')::int) from public.events e
       where e.player_id = v_p and e.kind = 'CAPTAIN_SKILL' and e.payload ->> 'officer' = 'ELCANO') is distinct from c_costs
     or (select sum(k.delta) from public.reputation_book k where k.player_id = v_p and k.kind = 'skill' and k.note ->> 'officer' = 'ELCANO') <> -11000
     or (select string_agg(g.code || ':' || (select sum(public.wc_int('rep_skill_base') * r * (r + 1) / 2) from generate_series(1, g.max_rank) r), ',' order by g.ord) from public.captain_grades g)
          <> 'C:500,B:1750,A:4200,S:11000' then
    raise exception 'PROOF 58 FAIL: the ten steps did not cost 50, 150, 300, 500, 750, 1050, 1400, 1800, 2250, 2750 = 11,000';
  end if;
  -- the book: every row follows the one before it, and the balance is the last row's (no sum is the rule; this is the proof's own house)
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  if (select b.balance from public.reputation_balance b where b.player_id = v_p) <> 40000 + (select sum(k.delta) from public.reputation_book k where k.player_id = v_p and k.kind = 'skill')
     or exists (select 1 from public.reputation_book k join public.reputation_book q on q.player_id = k.player_id and q.seq = k.seq - 1
                 where k.player_id = v_p and k.balance_after <> q.balance_after + k.delta) then
    raise exception 'PROOF 58 FAIL: the book is not chained, or the balance is not the seed less every step';
  end if;
  raise notice 'PASS: SKILL_MAX_BY_GRADE — a C stops at 3 ("Navigator is 3 of 3: a B captain reaches 5."), an S at 10 ("Navigator is 10 of 10."); ELCANO''s ten steps cost % = 11,000; to the ceiling a C costs 500, a B 1,750, an A 4,200, an S 11,000; the book is chained and the balance is %',
    c_costs, (select b.balance from public.reputation_balance b where b.player_id = v_p);

  -- ══ SKILL_FLOOR ══ (TARTAGLIA: a C Gunner at 4.5, in the Captain's cabin)
  v_r := pg_temp.up_58(v_p, 'TARTAGLIA', 'GUNNER', 3);
  v_n := pg_temp.term_58(v_fleet, v_p, 'TARTAGLIA', 'accuracy');
  update public.captain_state set grade = 'B' where player_officer_id = pg_temp.po_58(v_p, 'TARTAGLIA');
  v_m := pg_temp.term_58(v_fleet, v_p, 'TARTAGLIA', 'accuracy');
  if v_n <> 4.5 * 1.12 or v_m <> 5.5 * 1.12
     or (select r.rank from public.captain_trait_rank r where r.player_officer_id = pg_temp.po_58(v_p, 'TARTAGLIA') and r.trait = 'GUNNER') <> 3 then
    raise exception 'PROOF 58 FAIL: a promoted captain''s steps do not stand on her new floor: 4.5 x 1.12 = % before, % after (5.5 x 1.12 = 6.16 expected)', v_n, v_m;
  end if;
  v_r := pg_temp.up_58(v_p, 'TARTAGLIA', 'GUNNER', 2);   -- a B: 5
  v_r := public.captain_skill_up_for(v_p, 'TARTAGLIA', 'GUNNER');
  if (v_r ->> 'error_code') is distinct from 'E_TOP_RANK' or (v_r ->> 'error_message') is distinct from 'Gunner is 5 of 5: an A captain reaches 7.'
     or pg_temp.term_58(v_fleet, v_p, 'TARTAGLIA', 'accuracy') <> 5.5 * 1.20 then
    raise exception 'PROOF 58 FAIL: a B captain does not stop at 5 with her term at 5.5 x 1.20: % / %', v_r, pg_temp.term_58(v_fleet, v_p, 'TARTAGLIA', 'accuracy');
  end if;
  raise notice 'PASS: SKILL_FLOOR — TARTAGLIA''s Gunner at step 3: % as a C (4.5 x 1.12), % once a B (her floor 5.5 x 1.12), her 3 steps kept; a B goes on to 5 (5.5 x 1.20 = %) and is refused the sixth ("Gunner is 5 of 5: an A captain reaches 7.")',
    trim_scale(v_n), trim_scale(v_m), trim_scale(pg_temp.term_58(v_fleet, v_p, 'TARTAGLIA', 'accuracy'));

  -- ══ SKILL_CAP ══ (PIRIREIS and DIASNAV board the barca: three navigators in one fleet)
  v_r := public.seat_captain_for(v_p, 'PIRIREIS', v_s2, 1);
  v_x := public.seat_captain_for(v_p, 'DIASNAV', v_s2, 3);
  if not coalesce((v_r ->> 'ok')::boolean, false) or not coalesce((v_x ->> 'ok')::boolean, false) then
    raise exception 'PROOF 58 FAIL: could not seat the two navigators on the barca: % %', v_r, v_x;
  end if;
  v_r := pg_temp.up_58(v_p, 'PIRIREIS', 'NAVIGATOR', 10);
  select sum(t.value_pct) into v_sum from public.crew_terms(v_fleet) t where t.effect = 'speed';
  if v_sum <> 9 * 1.40 + 8.5 * 1.40 + 8 or v_sum <= 25 or public.crew_pct(v_fleet, null, 'speed') <> 0.25
     or pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed') <> 12.6 or pg_temp.sheet_58('ELCANO', 'speed') <> 12.6 then
    raise exception 'PROOF 58 FAIL: three navigators (12.6 + 11.9 + 8 = 32.5) do not read the cap of 25 from public.crew_pct with their own terms whole: sum %, crew %', v_sum, public.crew_pct(v_fleet, null, 'speed');
  end if;
  update public.crew_effects set cap_pct = 8 where code = 'speed';
  if public.crew_pct(v_fleet, null, 'speed') <> 0.08 or pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed') <> 12.6 then
    raise exception 'PROOF 58 FAIL: a cap of 8 is not the crew''s: crew %, her term %', public.crew_pct(v_fleet, null, 'speed'), pg_temp.term_58(v_fleet, v_p, 'ELCANO', 'speed');
  end if;
  update public.crew_effects set cap_pct = 25 where code = 'speed';
  raise notice 'PASS: SKILL_CAP — ELCANO 12.6 (9 x 1.40) + PIRIREIS 11.9 (8.5 x 1.40) + DIASNAV 8 = % in terms, and public.crew_pct reads 25 %%; under a cap of 8 the crew reads 8 and her term still reads 12.6', trim_scale(v_sum);

  -- ══ SKILL_MERCHANT_EQUAL ══ (last: after every step above)
  v_npc := public.new_house(null, 'Casa Mercante 0358', 'PRT', p_ducats => 20000, p_is_npc => true);
  insert into public.player_officers (player_id, officer_id) select v_npc, o.id from public.officers o where o.code = 'ELCANO';
  v_r := public.captain_skill_up_for(v_npc, 'ELCANO', 'NAVIGATOR');
  select count(*), count(*) filter (where m.v is distinct from public.crew_pct(m.fleet, null, m.effect)::text), count(distinct m.fleet) filter (where m.v::numeric > 0)
    into v_cnt, v_i, v_hit from pg_temp.merch_58 m;
  if v_cnt = 0 or v_hit = 0 then
    raise exception 'PROOF 58 FAIL: no merchant fleet with a captain was compared (% answers, % fleets with a term): the comparison is empty', v_cnt, v_hit;
  end if;
  if v_i <> 0 or (v_r ->> 'error_code') is distinct from 'E_NOT_SIGNED'
     or exists (select 1 from public.captain_trait_rank r join public.player_officers po on po.id = r.player_officer_id join public.players pl on pl.id = po.player_id where pl.is_npc) then
    raise exception 'PROOF 58 FAIL: % merchant answers moved, a merchant''s captain has a step, or a merchant''s company was not refused (%)', v_i, v_r;
  end if;
  raise notice 'PASS: SKILL_MERCHANT_EQUAL — % answers (every merchant fleet x speed, hold, spread, crew_saved; % fleets with a term above 0) read what they read before the player''s % steps; no merchant''s captain has a row; a merchant''s company is refused E_NOT_SIGNED',
    v_cnt, v_hit, (select sum(r.rank) from public.captain_trait_rank r);
end
$p$;
