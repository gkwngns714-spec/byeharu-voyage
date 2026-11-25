-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 238 - LAND EXPEDITION  (migration 0534, dark: land_expedition_enabled; docs/dev-log/2026-11-25-captain-works.md)
--
-- @pass LX_DARK   dark: the door refuses, the read is {on: false}, the jobs' tick writes no run
-- @pass LX_CARD   lit: the card of a gathering and of a raid: what a round costs, what it brings, the bill, the rounds and what stops them; no chance in it
-- @pass LX_TWO    two captains out at once from one company, each with its own party, crew and log; the dig's party is a third and digs as before
-- @pass LX_TICK   nobody presses: the jobs' tick brings both home; badges, experience, the goods in Storage, one event each
-- @pass LX_COIN   the hands, the provisions and the pay went to the home city, a raid's gold came from the capital: the two purses and the company's sum to what they were
-- @pass LX_FLEETS a fleet's rounds are as 0518 wrote them with a party's run beside them: sent, read, settled
-- @pass LX_CLOSE  a closed company's deletions leave no run
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_me uuid; v_fl uuid; v_pt uuid; v_a text; v_b text; v_act text; v_c jsonb; v_c2 jsonb; v_r jsonb; v_run jsonb; v_w jsonb; v_ev int; v_s0 numeric; v_s1 numeric; v_cap uuid; v_bal int; v_units int; r record;
begin
  v_me := public.new_house('00000000-0534-4000-8000-0000000002a1', 'Casa da Mata 238', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_me;
  v_pt := public.home_port_of(v_me);
  update public.players set ducats = 300000 where id = v_me;
  update public.ports set crew_pool = 400 where id = v_pt;
  perform cmd.assume_identity('00000000-0534-4000-8000-0000000002a1');
  select o.code into v_a from public.officers o order by o.code limit 1;
  select o.code into v_b from public.officers o order by o.code offset 1 limit 1;
  perform public.sign_officer(v_me, v_a, null);
  perform public.sign_officer(v_me, v_b, null);
  update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'captain_works_enabled', 'rounds_enabled', 'land_raids_enabled', 'honor_enabled', 'reputation_on', 'fleet_jobs_enabled', 'city_treasury_enabled');
  update public.world_config set value = '[30, 2]'::jsonb where key = 'land_crew_cap';
  -- LX_DARK
  call public.tick_fleet_jobs(false);
  if cmd.land_expedition(v_a, '{"work": "land_raid", "target": "wolves", "crew": 5}')->>'error_code' <> 'E_NOT_IN_USE' or world.land_expedition(v_a) <> '{"on": false}'::jsonb or exists (select 1 from public.round_runs rr where rr.player_id = v_me) then
    raise exception 'LX_DARK: something is open';
  end if;
  raise notice 'PASS: LX_DARK';

  -- LX_CARD
  update public.world_config set value = 'true'::jsonb where key = 'land_expedition_enabled';
  select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.kind <> 'make' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null'
   order by (public.land_terms(v_me, a.code)->>'trip')::numeric, a.code limit 1;
  v_c := world.land_expedition(v_a, jsonb_build_object('work', 'land_gather', 'target', v_act, 'crew', 20))->'card';
  v_c2 := world.land_expedition(v_b, '{"work": "land_raid", "target": "wolves", "crew": 30}')->'card';
  if v_c ? 'short' or v_c2 ? 'short' or (v_c::text || v_c2::text) ~* '(chance|odds|seed)' then raise exception 'LX_CARD: % / %', v_c, v_c2; end if;
  raise notice 'PASS: LX_CARD — % of %: % rounds (stopped by %), % s each, % units a round, % hands lost a round, bill %', v_c->>'word', v_c->>'crew', v_c->>'most', v_c->>'why', v_c->>'seconds', v_c->>'units', v_c #>> '{cost,hands}', v_c->'bill';
  raise notice 'TIMING: % of %: % rounds (stopped by %), % hands lost a round, bill %', v_c2->>'word', v_c2->>'crew', v_c2->>'most', v_c2->>'why', v_c2 #>> '{cost,hands}', v_c2->'bill';

  -- LX_TWO, LX_COIN
  v_cap := (select cp.id from public.nations n join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR' join public.players pl on pl.nation_id = n.id where pl.id = v_me);
  perform public.treasury_post(v_cap, 'PROOF', 1000000, null, null, true);
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  v_s0 := (select pl.ducats from public.players pl where pl.id = v_me) + public.treasury_balance(v_pt) + case when v_cap <> v_pt then public.treasury_balance(v_cap) else 0 end;
  v_r := cmd.land_expedition(v_a, jsonb_build_object('work', 'land_gather', 'target', v_act, 'crew', 20));
  if not (v_r->>'ok')::boolean then raise exception 'LX_TWO: %', v_r; end if;
  v_r := cmd.land_expedition(v_b, '{"work": "land_raid", "target": "wolves", "crew": 30, "stop": {"rounds": 40}}');
  if not (v_r->>'ok')::boolean then raise exception 'LX_TWO: %', v_r; end if;
  perform public.land_send_for(v_me, v_act, now());
  v_w := world.land_expedition();
  if jsonb_array_length(v_w->'runs') <> 2 or (select count(*) from public.land_parties lp where lp.player_id = v_me) <> 3 or (select count(*) from jsonb_array_elements(v_w->'runs') x where x->>'state' = 'out') <> 2
     or not exists (select 1 from public.land_parties lp where lp.player_id = v_me and lp.ord = 1 and lp.action = v_act) then
    raise exception 'LX_TWO: %', v_w->'runs';
  end if;
  raise notice 'PASS: LX_TWO — % and % out, the dig digs', v_w #>> '{runs,0,name}', v_w #>> '{runs,1,name}';

  -- LX_FLEETS: 0518's own send, read and settle, on a work of this proof's
  insert into public.round_works (code, ord, kind, word, skill, level, seconds, food_days, water_days, crew_pct) values ('proof_sea', 99, 'sea', 'Proof 238', 'exploration', 1, 600, 0.1, 0.1, 0);
  update public.ships set crew = (select sc.crew_required from public.ship_classes sc where sc.id = class_id), food_t = 20, water_t = 20 where fleet_id = v_fl;
  perform public.round_send_for(v_me, v_fl, 'proof_sea', '{"rounds": 2}', now() - interval '30 minutes');
  v_w := world.rounds(v_fl);
  if jsonb_array_length(v_w->'runs') <> 1 or exists (select 1 from jsonb_array_elements(v_w->'works') x where x->>'kind' = 'land') then raise exception 'LX_FLEETS: %', v_w; end if;

  -- LX_TICK
  update public.round_runs set sent_at = sent_at - interval '13 hours', stop_at = stop_at - interval '13 hours' where player_id = v_me and party_id is not null;
  call public.tick_fleet_jobs(false);
  if exists (select 1 from public.round_runs rr where rr.player_id = v_me and rr.state = 'out') or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
    raise exception 'LX_TICK: somebody is still out: %', (select jsonb_agg(to_jsonb(rr) - 'terms' - 'log') from public.round_runs rr where rr.player_id = v_me);
  end if;
  raise notice 'PASS: LX_FLEETS — sent, read and settled beside two parties';
  select b.balance into v_bal from public.honor_balance b where b.player_id = v_me;
  select count(*) into v_ev from public.events e where e.player_id = v_me and e.kind = 'ROUNDS_DONE';
  select coalesce(sum((rr.carry->>'units')::int), 0) into v_units from public.round_runs rr where rr.player_id = v_me and rr.work = 'land_gather';
  if v_ev <> 3 or v_units < 1 or coalesce((select sum(ps.qty) from public.player_storage ps where ps.player_id = v_me), 0) + coalesce((select sum(e.value::numeric) from public.land_parties lp, jsonb_each_text(lp.found_waiting) e where lp.player_id = v_me), 0) < v_units
     or coalesce(v_bal, 0) < 1 or not exists (select 1 from public.captain_work_xp z join public.player_officers po on po.id = z.player_officer_id where po.player_id = v_me and z.work = 'arms' and z.xp > 0) then
    raise exception 'LX_TICK: % events, % units, % badges', v_ev, v_units, v_bal;
  end if;
  raise notice 'PASS: LX_TICK — 3 events, % units home, % badges', v_units, v_bal;
  v_s1 := (select pl.ducats from public.players pl where pl.id = v_me) + public.treasury_balance(v_pt) + case when v_cap <> v_pt then public.treasury_balance(v_cap) else 0 end;
  if v_s1 <> v_s0 or coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and l.kind = 'VOYAGE_REWARD'), 0) < 1 then
    raise exception 'LX_COIN: % before, % after, gold %', v_s0, v_s1, (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and l.kind = 'VOYAGE_REWARD');
  end if;
  raise notice 'PASS: LX_COIN — paid %, gold %, the three purses to the coin', (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and l.kind in ('HIRE', 'PROVISION', 'WAGES')),
    (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and l.kind = 'VOYAGE_REWARD');

  -- LX_CLOSE
  delete from public.land_parties where player_id = v_me;
  if exists (select 1 from public.round_runs rr where rr.player_id = v_me and rr.party_id is not null) then raise exception 'LX_CLOSE: a run of a party that is gone'; end if;
  raise notice 'PASS: LX_CLOSE';
end $p$;
