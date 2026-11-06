// The deliberate breakages of migration 0333: [label, mutate(file), the error it must fail with].
export const mutations = (swap) => {
  const P = /PROOF 40 FAIL/
  return [
    // the join rule
    ['the sheet reads the job, not the clock', (s) => swap(s, `and bs.arrives_at <= b.resolves_at order by bs.joined_at`, `and bs.arrives_at <= p_now order by bs.joined_at`), /PROOF 40 FAIL: a minute past she joined/],
    ['everyone called is on the sheet', (s) => swap(s, `where bs.battle_id = p_battle and bs.arrives_at <= b.resolves_at order by bs.joined_at`, `where bs.battle_id = p_battle order by bs.joined_at`), /PROOF 40 FAIL: a minute past she joined/],
    ['the clock itself is too late', (s) => swap(s, `and bs.arrives_at <= b.resolves_at order by bs.joined_at`, `and bs.arrives_at < b.resolves_at order by bs.joined_at`), /PROOF 40 FAIL: on the clock she did not join/],
    ['the close keeps the estimate', (s) => swap(s, `  perform public.battle_sides_come(p_battle, p_now);\n`, ``), /PROOF 40 FAIL/],
    ['no settle at the close', (s) => swap(s, `    perform voyage.settle(s.fleet_id, p_now);\n    update public.battle_sides bs\n`, `    update public.battle_sides bs\n`), P],
    // the call
    ['a probe calls the navy', (s) => swap(s, `  if p_kind = 'ATTACK' then   -- 0333: her country answers; a probe calls nobody\n    perform public.navy_call(v_id, p_defender, v_until, p_now);\n  end if;\n`, ``), P],
    ['the switch is not read', (s) => swap(s, `  if v_nation is null or not public.navy_on() then\n    return 0;\n  end if;\n\n  for r in select n.fleet_id\n`, `  if v_nation is null then\n    return 0;\n  end if;\n\n  for r in select n.fleet_id\n`), /PROOF 40 FAIL: with the navy off a ship answered/],
    ['no ship sails at the call', (s) => swap(s, `      perform public.navy_reinforce(r.fleet_id, v_f.port_id, p_now);\n`, `      null;\n`), /PROOF 40 FAIL: the call was no voyage/],
    ['a ship in port is called to her own quay', (s) => swap(s, `  v_to := (select public.harbour_nearest((b.site ->> 'lat')::double precision, (b.site ->> 'lon')::double precision) from public.battles b where b.id = p_battle);`, `  v_to := public.realm_capital(v_nation);`), P],
    ['her side keeps the estimate', (s) => swap(s, `  update public.battle_sides bs set arrives_at = v.eta\n    from public.voyages v\n   where bs.battle_id = n.battle_id and bs.fleet_id = p_fleet and v.fleet_id = p_fleet and v.status = 'SAILING';\n`, ``), P],
    ['the call has no limit', (s) => swap(s, `    exit when v_k >= v_max or (v_k > 0 and r.at > p_until);`, `    exit when v_k > 0 and r.at > p_until;`), /PROOF 40 FAIL: the call took/],
    ['all sail when none is in time', (s) => swap(s, `    exit when v_k >= v_max or (v_k > 0 and r.at > p_until);`, `    exit when v_k >= v_max;`), /PROOF 40 FAIL: past the clock/],
    ['nobody sails when none is in time', (s) => swap(s, `    exit when v_k >= v_max or (v_k > 0 and r.at > p_until);`, `    exit when v_k >= v_max or r.at > p_until;`), /PROOF 40 FAIL: past the clock/],
    ['a call reaches any distance', (s) => swap(s, `(select r.nm from voyage.reach_from(p_from) r where r.port_id = p_to and r.nm <= public.wc_num('navy_reach_nm'))`, `(select r.nm from voyage.reach_from(p_from) r where r.port_id = p_to)`), /PROOF 40 FAIL: a ship beyond navy_reach_nm/],
    ['an unpaid ship answers', (s) => swap(s, `              and public.navy_on_duty(n.nation_id, n.ord, n.unpaid_since)\n              and exists`, `              and exists`), /PROOF 40 FAIL: the call took/],
    ['a laid-up ship answers', (s) => swap(s, `where n.nation_id = v_nation and n.laid_up_at is null and n.battle_id is null and a.at is not null`, `where n.nation_id = v_nation and n.battle_id is null and a.at is not null`), P],
    ['a wreck answers', (s) => swap(s, `              and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)\n            order by a.at, n.ord loop`, `            order by a.at, n.ord loop`), /PROOF 40 FAIL: the call took/],
    ['a ship in a battle answers another', (s) => swap(s, `where n.nation_id = v_nation and n.laid_up_at is null and n.battle_id is null and a.at is not null`, `where n.nation_id = v_nation and n.laid_up_at is null and a.at is not null`), P],
    ['at sea she is read as if she were sailing there', (s) => swap(s, `    if v.dest_port_id = p_to then\n      return v.eta;\n    end if;\n    v_s := public.navy_leg_seconds(p_fleet, v.dest_port_id, p_to);\n    return greatest(v.eta, p_now) + make_interval(secs => v_s::double precision);`, `    return v.eta;`), /PROOF 40 FAIL: the call touched/],
    ['she leaves her call in port', (s) => swap(s, `  if p_port = n.called_to then\n    return 'CALLED';\n  end if;\n`, ``), P],
    ['the step forgets the call', (s) => swap(s, `  if n.mission = 'REINFORCE' then\n    return public.navy_reinforce(p_fleet, f.port_id, p_now);\n  end if;\n`, ``), P],
    // the close
    ['nothing frees her', (s) => swap(s, `  update public.navy_ships n set mission = case when n.escort_of is not null then 'ESCORT' else 'PATROL' end, called_to = null, battle_id = null where n.battle_id = p_battle;\n`, ``), /PROOF 40 FAIL: she was not freed/],
    ['an escort forgets her ward', (s) => swap(s, `mission = case when n.escort_of is not null then 'ESCORT' else 'PATROL' end, called_to = null`, `mission = 'PATROL', called_to = null`), /PROOF 40 FAIL: after the fight/],
    ['a navy ship set upon is not her country there', (s) => swap(s, ` or (bs.how = 'OPENED' and bs.side = 'DEFENDER' and n.fleet_id is not null))`, `)`), /PROOF 40 FAIL: she fought alone/],
    ['the report says nothing', (s) => swap(s, `        v_rep := jsonb_set(v_rep, '{lines}', (v_rep -> 'lines') || (v_spoils #> '{navy,line}'));\n`, `        null;\n`), /PROOF 40 FAIL: the report/],
    // the ship set upon
    ['a defender is any defender', (s) => swap(s, `where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';`, `where bs.battle_id = p_battle and bs.side = 'DEFENDER' order by bs.how = 'OPENED', bs.fleet_id limit 1;`), P],
    ['the sink is the target alone', (s) => swap(s, `where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.arrives_at <= b.resolves_at order by bs.fleet_id loop`, `where bs.battle_id = p_battle and bs.side = 'ATTACKER' order by bs.fleet_id loop`), P],
    // no ship twice
    ['a called ship can be attacked', (s) => swap(s, `\n     or exists (select 1 from public.navy_ships n where n.fleet_id = p_target and n.battle_id is not null) then`, ` then`), /PROOF 40 FAIL: a called ship was attacked/],
    ['the ship set upon holds no battle', (s) => swap(s, `  update public.navy_ships n set battle_id = p_battle where n.fleet_id = p_defender;\n  if v_nation`, `  if v_nation`), P],
    // escort
    ['the escort stands twice', (s) => swap(s, `    update public.navy_ships n set battle_id = p_battle where n.fleet_id = r.fleet_id;\n    v_n := v_n + 1;`, `    v_n := v_n + 1;`), P],
    ['the escort is not held', (s) => swap(s, `    perform public.battle_stop(r.fleet_id, p_until, p_now);\n`, ``), /PROOF 40 FAIL: she is not held/],
    ['the escort comes late', (s) => swap(s, `values (p_battle, r.fleet_id, 'DEFENDER', p_now, p_now, 'ESCORT');`, `values (p_battle, r.fleet_id, 'DEFENDER', p_now, p_until + interval '1 second', 'ESCORT');`), /PROOF 40 FAIL: she did not join at once/],
    ['every ship goes on escort', (s) => swap(s, `  if p_duty and n.ord > coalesce((select max(x.ord) from public.navy_ships x\n                                   where x.nation_id = n.nation_id and x.laid_up_at is null and public.navy_on_duty(x.nation_id, x.ord, x.unpaid_since)), 0) - public.wc_int('navy_escorts') then`, `  if p_duty then`), /PROOF 40 FAIL: the first ship of the line/],
    ['the poorest ship is followed', (s) => swap(s, `     order by a.aboard desc, c.fleet_id`, `     order by a.aboard, c.fleet_id`), /PROOF 40 FAIL: she does not follow/],
    ['she is not mended', (s) => swap(s, `  if coalesce(public.port_nation(p_port) = n.nation_id, false) then\n    perform public.fleet_mend(p_fleet);\n  end if;\n`, ``), /PROOF 40 FAIL: she was not mended/],
    ['the step skips the escort', (s) => swap(s, `  if v_esc is not null then\n    return v_esc;\n  end if;\n`, ``), /voyages_one_sailing_per_fleet|PROOF 40 FAIL/],
    ['an off-duty ship escorts', (s) => swap(s, `  if p_duty and n.ord > coalesce(`, `  if n.ord > coalesce(`), /voyages_one_sailing_per_fleet|PROOF 40 FAIL: an unpaid or unwanted ship/],
    // the target
    ['a navy ship cannot be attacked', (s) => swap(s, `  if v_kind not in ('CARGO_SHIP', 'NAVY') then`, `  if v_kind <> 'CARGO_SHIP' then`), P],
    ['a merchant can be attacked', (s) => swap(s, `  if v_kind not in ('CARGO_SHIP', 'NAVY') then`, `  if false then`), P],
    ['her country is not read', (s) => swap(s, `  v_nation := public.crown_nation(p_target);\n`, `  v_nation := c.nation_id;\n`), P],
    ['a sunk navy ship has no country', (s) => swap(s, `  c.nation_id := public.crown_nation(v_d);   -- 0333: a navy ship's country too: every line below reads c\n`, ``), /PROOF 40 FAIL: a sunk navy ship cost no more regard/],
    ['the close frees nobody and says nothing', (s) => swap(s, ` || public.navy_close(p_battle, p_now);`, `;`), /PROOF 40 FAIL/],
    ['her limit is not read', (s) => swap(s, `  if v_kind = 'NAVY' and exists (select 1 from public.battle_sides bs join public.battles b`, `  if false and exists (select 1 from public.battle_sides bs join public.battles b`), /PROOF 40 FAIL: inside the hour/],
    ['her limit is forever', (s) => swap(s, `                                    and bs.joined_at > p_now - make_interval(mins => public.wc_int('attack_ship_minutes'))) then`, `                                    ) then`), /PROOF 40 FAIL: past the hour/],
    ['her regard is a cargo ship\'s', (s) => swap(s, `public.wc_num(case when v_kind = 'NAVY' then 'regard_attack_navy' else 'regard_attack_cargo' end)`, `public.wc_num('regard_attack_cargo')`), /PROOF 40 FAIL: regard/],
    ['her reason is a cargo ship\'s', (s) => swap(s, `case when v_kind = 'NAVY' then 'ATTACK_NAVY' else 'ATTACK_CARGO' end`, `'ATTACK_CARGO'`), /PROOF 40 FAIL: the regard names no navy/],
    ['her sink is a cargo ship\'s', (s) => swap(s, `case when public.fleet_kind(v_s) = 'NAVY' then 'SINK_NAVY' else 'SINK_CARGO' end`, `'SINK_CARGO'`), /PROOF 40 FAIL: the sink names no navy/],
    ['the card offers nothing', (s) => swap(s, `    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0333: as a cargo ship's card: the key is served only while attacks are lit$h$)`, `    ;$h$)`), /PROOF 40 FAIL: lit, her card/],
    ['the card always offers', (s) => swap(s, `    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0333: as a cargo ship's card: the key is served only while attacks are lit$h$)`, `    || '{"attack": true}'::jsonb;$h$)`), /PROOF 40 FAIL: dark, the navy card/],
    // the served clock
    ['the preview says nothing of the navy', (s) => swap(s, `return coalesce((select jsonb_build_object('navy_minutes', greatest(1, ceil(extract(epoch from (public.battle_navy_served(p_fleet) ->> 'navy_at')::timestamptz - p_now) / 60)))\n                    where public.battle_navy_served(p_fleet) ? 'navy_at'), '{}'::jsonb)   -- 0333: "Navy arrives in about 6 min", when one would\n    || jsonb_build_object(`, `return jsonb_build_object(`), /PROOF 40 FAIL: the dry run says nothing/],
    ['the card has no navy clock', (s) => swap(s, `    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise\n`, ``), /PROOF 40 FAIL: the card's clock/],
    ['the clock reads a late ship', (s) => swap(s, `join public.battle_sides o on o.battle_id = b.id and o.how <> 'OPENED' and o.arrives_at <= b.resolves_at`, `join public.battle_sides o on o.battle_id = b.id and o.how <> 'OPENED'`), P],
    ['the clock reads the attacked side', (s) => swap(s, `where me.fleet_id = p_fleet and me.side = 'ATTACKER'`, `where me.fleet_id = p_fleet`), /PROOF 40 FAIL: the side set upon read/],
    // the file itself
    ['a hunk that is not there', (s) => swap(s, `$h$  v_leg   jsonb;\nbegin$h$,`, `$h$  v_legs   jsonb;\nbegin$h$,`), /0333 self-assert FAIL: hunk/],
    ['a switch is lit', (s) => swap(s, `  -- ── 4. THE SELF-ASSERT: the catalog and stable reads. No game step, no row. ──\n`, `  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';\n`), /0333 self-assert FAIL: a world_config row moved/],
  ]
}
