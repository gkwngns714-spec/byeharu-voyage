// The deliberate breakages of migration 0334: [label, mutate(file), the error it must fail with, 'scene' when the dark scene is what must catch it].
export const mutations = (swap) => {
  const finds = `voyage.rng(p_voyage, p_day, 'navy') < h.chance`
  const hull = `set durability = greatest(least(sh.durability, (select b.durability from public.ship_base(sh.id) b) * public.wc_num('navy_hull_floor')), sh.durability - l.lost)`
  const freezeCall = `  if not v_npc then   -- 0334: who may meet her is frozen as she leaves\n    perform voyage.hostile_freeze(v_voyage, v_player, p_at);\n  end if;\n`
  const legTest = `  if v_leg ? 'navy' and voyage.navy_finds(p_voyage, p_day, (v_leg->>'navy')::uuid) then`
  return [
    // dark
    ['the hunt is lit by the file', (s) => swap(s, `('navy_hunt_per_day', to_jsonb(0),`, `('navy_hunt_per_day', to_jsonb(0.5),`), /0334 self-assert FAIL: the hunt is not dark/],
    ['the knob is not read', (s) => swap(s, `if v_p <= 0 or not public.navy_on() then`, `if not public.navy_on() then`), /chance_check|PROOF 41 FAIL: at 0 the hunt wrote something/],
    ['a dark navy hunts', (s) => swap(s, `if v_p <= 0 or not public.navy_on() then`, `if v_p <= 0 then`), /PROOF 41 FAIL: a dark navy hunted her/],
    ['a dark regard hunts', (s) => swap(s, `where h.player_id = p_player and public.regard_on() and public.regard_band`, `where h.player_id = p_player and public.regard_band`), /PROOF 41 FAIL: a dark regard hunted her/],
    ['NAVY joins the sea mix', (s) => swap(s, `array['A navy ship stopped us.'], false, false,`, `array['A navy ship stopped us.'], true, true,`), /mix|E_NO_SEA|0334 self-assert FAIL/],
    // no read for a merchant
    ['a merchant reaches the freeze', (s) => swap(s, freezeCall, `  perform voyage.hostile_freeze(v_voyage, v_player, p_at);\n`), /does not exist/],
    ['a merchant reads the side table on every roll', (s) => swap(s, legTest, `  if exists (select 1 from public.voyage_hostile x where x.voyage_id = p_voyage) and v_leg ? 'navy' and voyage.navy_finds(p_voyage, p_day, (v_leg->>'navy')::uuid) then`), /does not exist/],
    ['a company is treated as a merchant', (s) => swap(s, `  if not v_npc then   -- 0334`, `  if v_npc then   -- 0334`), /PROOF 41 FAIL: (the Hostile row is wrong|a company departed with the tables gone)|does not exist/],
    // the mark
    ['the mark lasts the wrong time', (s) => swap(s, `('wanted_hours', to_jsonb(48),`, `('wanted_hours', to_jsonb(24),`), /PROOF 41 FAIL: the row or its event is wrong/],
    ['a second mark writes a second event', (s) => swap(s, `  if v_n = 0 then\n    return false;\n  end if;\n  perform public.emit_event(p_player, 'WANTED'`, `  perform public.emit_event(p_player, 'WANTED'`), /PROOF 41 FAIL: (a battle did not mark her once|the row or its event is wrong)/],
    ['a merchant is marked', (s) => swap(s, `if p_player is null or p_nation is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then`, `if p_player is null or p_nation is null then`), /PROOF 41 FAIL: a merchant was marked/],
    ['a mark never ends', (s) => swap(s, `from public.wanted w where w.player_id = p_player and w.until > p_at group by w.nation_id`, `from public.wanted w where w.player_id = p_player group by w.nation_id`), /PROOF 41 FAIL: a mark does not end at its hour/],
    ['a battle marks nobody', (s) => swap(s, `    perform public.wanted_mark(v_a.player_id, c.nation_id, p_battle, p_now);\n`, ``), /PROOF 41 FAIL: nobody came and she was not marked/],
    ['a win is not a mark', (s) => swap(s, `if v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d) then`, `if not public.navy_arrived(p_battle, c.nation_id, v_d) then`), /PROOF 41 FAIL: she won and was not marked/],
    ['every battle is a mark', (s) => swap(s, `if v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d) then`, `if true then`), /PROOF 41 FAIL: a ship came in time and she was marked/],
    ['a late ship counts', (s) => swap(s, `and bs.arrives_at <= b.resolves_at)`, `)`), /PROOF 41 FAIL: a late ship counted as an answer/],
    ['the ship set upon is her own answer', (s) => swap(s, ` and bs.fleet_id is distinct from p_target\n`, `\n`), /PROOF 41 FAIL: public.navy_arrived/],
    // the freeze
    ['WANTED is not twice as likely', (s) => swap(s, `least(1, v_p * case when r.wanted then public.wc_num('navy_hunt_wanted_mult') else 1 end)`, `least(1, v_p)`), /PROOF 41 FAIL: WANTED is not twice as likely/],
    ['the chance is not held to one', (s) => swap(s, `least(1, v_p * case when r.wanted then public.wc_num('navy_hunt_wanted_mult') else 1 end)`, `v_p * case when r.wanted then public.wc_num('navy_hunt_wanted_mult') else 1 end`), /chance_check/],
    ['Wary is hunted', (s) => swap(s, `public.regard_band(public.regard_of(p_player, h.nation_id)) ->> 'band' = 'hostile'`, `public.regard_band(public.regard_of(p_player, h.nation_id)) ->> 'band' in ('hostile', 'wary', 'neutral')`), /PROOF 41 FAIL: a company that is not Hostile was frozen/],
    ['every sea is her waters', (s) => swap(s, `(e.seg ->> 'sea_id')::uuid = any (v_seas)\n                          then`, `true\n                          then`), /PROOF 41 FAIL: the marks are not her waters/],
    ['waters reach the whole world', (s) => swap(s, `(r.reaches ->> p.code)::numeric <= public.wc_num('navy_reach_nm')`, `true`), /PROOF 41 FAIL: this proof needs two seas/],
    ['a country with no ship or water still writes', (s) => swap(s, `    continue when v_seas is null;\n`, `    v_seas := coalesce(v_seas, '{}'::uuid[]);\n`), /null value in column "fleet_id"/],
    ['the path is not written', (s) => swap(s, `    update public.voyages v set path = v_path where v.id = p_voyage;\n`, `    null;\n`), /PROOF 41 FAIL: the marks are not her waters/],
    ['the sheet is not frozen', (s) => swap(s, `  v_f := public.fight_sides(p_voyage, p_day, v_ships, h.sheet);`, `  v_f := public.fight_sides(p_voyage, p_day, v_ships, voyage.fleet_hulls(h.fleet_id));`), /PROOF 41 FAIL: the same days read differently/],
    // the roll
    ['the mark is ignored', (s) => swap(s, legTest, `  if false then`), /PROOF 41 FAIL: (a frozen voyage read what came after it|no NAVY day)/],
    ['the roll reads the world at settle', (s) => swap(swap(s, `select coalesce((select ${finds}\n                     from public.voyage_hostile h\n                    where h.voyage_id = p_voyage and h.nation_id = p_nation), false)`, `select coalesce((select ${finds} and public.navy_on()\n                     from public.voyage_hostile h\n                    where h.voyage_id = p_voyage and h.nation_id = p_nation), false)`), `  if not coalesce(v_ok, false) then`, `  if false then`), /PROOF 41 FAIL: a frozen voyage read what came after it/],
    ['more than once a voyage', (s) => swap(s, `\n     and not exists (select 1 from public.voyage_events e where e.voyage_id = p_voyage and e.day_index < p_day and e.kind = 'NAVY')`, ``), /PROOF 41 FAIL: not one NAVY day/],
    ['the hit tells the quote', (s) => swap(s, `    occurred := true;\n    kind := 'NAVY';\n`, `    occurred := true;\n    kind := 'NAVY';\n    p_hazard := 1;\n`), /PROOF 41 FAIL: (a marked day told the quote something|the premium moves with the hunt)/],
    // the meeting
    ['the arm is gone', (s) => swap(s, `      v_payload := v_payload || voyage.navy_meets(v.id, d, p_fleet, f.player_id, v_bound);\n`, ``), /PROOF 41 FAIL/],
    ['the floor is gone', (s) => swap(s, hull, `set durability = greatest(0, sh.durability - l.lost)`), /PROOF 41 FAIL: the floor did not hold/],
    ['the floor is 10 %', (s) => swap(s, `('navy_hull_floor', to_jsonb(0.25),`, `('navy_hull_floor', to_jsonb(0.10),`), /PROOF 41 FAIL: the floor did not hold/],
    ['a hull below the floor is raised', (s) => swap(s, hull, `set durability = greatest((select b.durability from public.ship_base(sh.id) b) * public.wc_num('navy_hull_floor'), sh.durability - l.lost)`), /PROOF 41 FAIL: a hull below the floor was moved/],
    ['her ship takes no hurt', (s) => swap(s, `   where sh.id = l.id and sh.fleet_id = h.fleet_id;\n`, `   where false;\n`), /PROOF 41 FAIL: her real ship took no hurt/],
    ['a sinking costs no regard', (s) => swap(s, `    perform public.regard_add(p_player, h.nation_id, public.wc_num('regard_sink'), 'SINK_NAVY');\n`, `    null;\n`), /PROOF 41 FAIL: sunk, regard did not fall/],
    ['the goods vanish', (s) => swap(s, `    perform public.stock_seized(v_cap, v_taken);\n`, ``), /PROOF 41 FAIL: the stock did not gain what she lost/],
    ['the goods are minted', (s) => swap(s, `set stock = pg.stock + x.q, updated_at`, `set stock = pg.stock + x.q + 1, updated_at`), /PROOF 41 FAIL: the stock did not gain what she lost/],
    ['the goods go nowhere near the capital', (s) => swap(s, `   where pg.port_id = p_port and pg.good_id = x.id\n$body$`, `   where pg.port_id <> p_port and pg.good_id = x.id\n$body$`), /PROOF 41 FAIL: the stock did not gain what she lost/],
    ['nothing is taken', (s) => swap(s, `    v_taken := voyage.raid_takes(p_voyage, p_day, p_fleet, 'PLUNDERED');\n`, ``), /PROOF 41 FAIL: not 25-50/],
    ['she is stripped', (s) => swap(s, `voyage.raid_takes(p_voyage, p_day, p_fleet, 'PLUNDERED')`, `voyage.raid_takes(p_voyage, p_day, p_fleet, 'STRIPPED')`), /PROOF 41 FAIL: not 25-50/],
    ['no hands are lost', (s) => swap(s, `    update public.ships sh set crew = greatest(0, sh.crew - public.raid_crew_lost(p_fleet, sh.crew, v_base)) where sh.fleet_id = p_fleet;\n`, ``), /PROOF 41 FAIL: the hands are not -10/],
    ['the hands are a fifth', (s) => swap(s, `('navy_crew_lost', to_jsonb(0.10),`, `('navy_crew_lost', to_jsonb(0.20),`), /PROOF 41 FAIL: the hands are not -10/],
    ['no insurance', (s) => swap(s, `    perform public.insurance_claim(p_voyage, p_day, v_taken, 'NAVY');\n`, ``), /PROOF 41 FAIL: insurance did not pay/],
    ['the fine is off the table', (s) => swap(s, `    v_fine := public.navy_fine_due(v_value);\n`, ``), /PROOF 41 FAIL: the fine is/],
    ['a thrown-back navy still fines', (s) => swap(s, `  if v_out in ('PLUNDERED', 'RANSOM') then\n    select coalesce(sum((e.value)`, `  if true then\n    select coalesce(sum((e.value)`), /PROOF 41 FAIL: (DRIVEN_OFF|EVADED|SLIPPED)/],
    ['a ransom takes cargo', (s) => swap(s, `  if v_out = 'PLUNDERED' then\n    v_base`, `  if v_out in ('PLUNDERED', 'RANSOM') then\n    v_base`), /PROOF 41 FAIL: (the cap|paid off|a short purse)/],
    ['the fine is minted', (s) => swap(s, `  perform public.pay_city(p_player, v_cap, 'FINE', v_pay, v_event);\n`, `  perform public.treasury_post(v_cap, 'FINE', v_pay, p_player, v_event);\n`), /PROOF 41 FAIL/],
    ['the fine vanishes', (s) => swap(s, `  perform public.pay_city(p_player, v_cap, 'FINE', v_pay, v_event);\n`, `  perform public.credit(p_player, 'FINE', -v_pay, v_event);\n`), /PROOF 41 FAIL/],
    ['the fine goes past her purse', (s) => swap(s, `  v_pay := least(p_fine, greatest(coalesce(v_have, 0), 0));\n`, `  v_pay := p_fine;\n`), /E_INSUFFICIENT_FUNDS/],
    ['an empty purse writes a fine', (s) => swap(s, `  if v_pay <= 0 then\n    return 0;\n  end if;\n  v_owed`, `  v_owed`), /PROOF 41 FAIL: an empty purse paid something|E_/],
    ['the cap is 200,000', (s) => swap(s, `('navy_fine_cap', to_jsonb(100000),`, `('navy_fine_cap', to_jsonb(200000),`), /0334 self-assert FAIL: public.navy_fine_due/],
    ['the fine buys all it can', (s) => swap(s, `least(v_pay, v_owed)::numeric / public.wc_int('regard_fine_per_point')`, `v_pay::numeric / public.wc_int('regard_fine_per_point')`), /PROOF 41 FAIL: (a fine lifted her|100,000 d. bought)/],
    ['a fine at sea does not clear', (s) => swap(s, `  perform public.wanted_clear(p_player, p_nation, p_at);\n  return v_pay;`, `  return v_pay;`), /PROOF 41 FAIL: at sea a fine that left nothing owed/],
    ['a fine at the capital does not clear', (s) => swap(s, `$h$  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');\n  perform public.wanted_clear(p_player, v_nat, now());   -- 0334\n$h$`, `$h$  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');\n  perform 1;   -- 0334\n$h$`), /PROOF 41 FAIL: a fine that left nothing owed did not end the mark/],
    ['a part of a fine clears', (s) => swap(s, `  if public.fine_owed(p_player, p_nation) > 0 then\n    return;\n  end if;\n  update public.wanted w`, `  update public.wanted w`), /PROOF 41 FAIL: a part of a fine ended the mark/],
    ['no rounds in the report', (s) => swap(s, `                            'rounds', to_jsonb(v_lines),\n`, ``), /PROOF 41 FAIL: the report has no rounds/],
    ['the hall reads any country', (s) => swap(s, `from public.wanted_nations(p_player, now()) w where w.nation_id = v_nation), '{}'::jsonb));`, `from public.wanted_nations(p_player, now()) w limit 1), '{}'::jsonb));`), /PROOF 41 FAIL: Spain's hall read Portugal's mark/],
    ['a hunk is off its line', (s) => swap(s, `$h$  returning id into v_voyage;\n$h$,`, `$h$  returning id  into v_voyage;\n$h$,`), /0334 self-assert FAIL: hunk 2 of voyage.depart/],
  ]
}
