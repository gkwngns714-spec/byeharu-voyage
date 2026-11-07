// mutations-0340.mjs — deliberate breakages of 0340, each required to FAIL the file's own self-assert, or proof 48 right after it, for the intended reason.
// `swap(sql, from, to)` throws when `from` is not in the file exactly once, so a mutation that no longer fits is loud.
export function mutations(swap) {
  return [
    // the switch
    ['the hunt reads the navy switch alone', (s) => swap(s, `  select public.navy_on() and public.pirates_on()\n`, `  select public.navy_on()\n`), /navy on and pirates off, she is not on her patrol|navy on and pirates off, a fight happened/],
    ['the hunt reads the pirates alone', (s) => swap(s, `  select public.navy_on() and public.pirates_on()\n`, `  select public.pirates_on()\n`), /navy off and pirates on, the hunt read lit|the hunt reads lit/],
    ['the pass answers 0 dark, not null', (s) => swap(s, `  if not public.navy_hunts_on() then\n    return null;\n  end if;\n  if not exists (select 1 from public.pirate_ships_at_work x where x.sea_id is not null) then`, `  if not public.navy_hunts_on() then\n    return 0;\n  end if;\n  if not exists (select 1 from public.pirate_ships_at_work x where x.sea_id is not null) then`), /the job answers|navy on and pirates off, she is not on her patrol/],
    // the hour
    ['a ship fights twice in an hour', (s) => swap(s, `              and (n.fought_at is null or n.fought_at <= p_now - interval '1 hour')\n`, `              and (n.fought_at is null or n.fought_at <= p_now - interval '1 minute')\n`), /the navy ship's own stamp did not hold her/],
    ['the pirate stamp is not read', (s) => swap(s, `    continue when exists (select 1 from public.pirate_ships x where x.fleet_id = v_p and x.fought_at > p_now - interval '1 hour')\n`, `    continue when false\n`), /inside the hour .* more fight|the pirate's stamp/],
    ['the pirate stamp is not written', (s) => swap(s, `  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;\n`, `\n`), /the hour-stamps were not both written/],
    ['the navy stamp is not written', (s) => swap(s, `  update public.navy_ships x set fought_at = p_now, fought = v_line where x.fleet_id = p_navy;\n`, `  update public.navy_ships x set fought = v_line where x.fleet_id = p_navy;\n`), /the hour-stamps were not both written/],
    ['the round is the minute', (s) => swap(s, `  v_round  int := floor(extract(epoch from p_now) / 3600)::int;\n`, `  v_round  int := floor(extract(epoch from p_now) / 60)::int;\n`), /not seeded by her fleet and the hour/],
    ['the seed is the pirate', (s) => swap(s, `  v_f := public.fight_sides(p_navy, v_round, v_a, v_b, '{}'::jsonb);\n`, `  v_f := public.fight_sides(p_pirate, v_round, v_a, v_b, '{}'::jsonb);\n`), /not seeded by her fleet and the hour/],
    ['the sides are swapped', (s) => swap(s, `  v_f := public.fight_sides(p_navy, v_round, v_a, v_b, '{}'::jsonb);\n`, `  v_f := public.fight_sides(p_navy, v_round, v_b, v_a, '{}'::jsonb);\n`), /hull loss did not land on both exactly/],
    // the hulls
    ['the hull writer skips side b', (s) => swap(s, `          select x.key::uuid, x.value::numeric from jsonb_each_text(coalesce(p_fight->'hull_lost'->'b', '{}'::jsonb)) x) l\n   where sh.id = l.id\n$$`, `          select x.key::uuid, x.value::numeric from jsonb_each_text('{}'::jsonb) x) l\n   where sh.id = l.id\n$$`), /hull loss did not land on both exactly/],
    ['a battle writes no hull', (s) => swap(s, `$h$  perform public.fight_hulls_write(v_f);   -- 0340: these lines, lifted: THE hull writer, which the navy's fight with a pirate ship shares\n$h$`, `$h$  perform public.fight_hulls_write(v_f - 'hull_lost');   -- 0340: these lines, lifted: THE hull writer, which the navy's fight with a pirate ship shares\n$h$`), /sinking a pirate ship/],
    ['a battle hunk is off its line', (s) => swap(s, `   where sh.id = l.id;\n$h$,`, `   where sh.id = l.id ;\n$h$,`), /occurs 0 time/],
    // the wreck
    ['a sunk pirate at sea is not wrecked', (s) => swap(s, `      if v_voy.id is not null then\n        perform voyage.npc_wreck(v_x, v_voy.id, v_voy.last_settled_day + 1);\n      end if;\n`, `\n`), /did not respawn at her home/],
    ['a sunk ship in port can still sail', (s) => swap(s, `     where f.id = v_x and f.status = 'DOCKED'\n       and (select sh.durability from public.ships sh where sh.fleet_id = f.id and sh.is_flagship) <= 0;\n`, `     where f.id = v_x and f.status = 'DOCKED'\n       and false;\n`), /sunk in port can still sail/],
    // the line and the card
    ['the line names a player', (s) => swap(s, `  v_ev := public.emit_event(null, 'NAVY_FIGHT', jsonb_build_object(\n`, `  v_ev := public.emit_event(nf.player_id, 'NAVY_FIGHT', jsonb_build_object(\n`), /not one public NAVY_FIGHT naming both/],
    ['the result words are wrong', (s) => swap(s, `                when v_f ->> 'outcome' = 'DRIVEN_OFF' then 'LOST'\n`, `                when v_f ->> 'outcome' = 'DRIVEN_OFF' then 'WON'\n`), /not one public NAVY_FIGHT naming both|her card does not keep/],
    ['the card serves the key dark', (s) => swap(s, `    || case when n.fought is null then '{}'::jsonb else jsonb_build_object('fought', n.fought) end;   -- 0340`, `    || jsonb_build_object('fought', n.fought);   -- 0340`), /her card serves a key/],
    ['the job serves the key dark', (s) => swap(s, `    || case when v_fights is null then '{}'::jsonb else jsonb_build_object('fights', v_fights) end;   -- 0340`, `    || jsonb_build_object('fights', v_fights);   -- 0340`), /dark, the job answers/],
    // the hunt
    ['the hunt ignores reach', (s) => swap(s, `                   where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station and r.nm <= public.wc_num('navy_reach_nm')\n`, `                   where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station\n`), /not in order, one a sea, within reach|pressed sea in reach is not the first target|did not sail for the pressed sea/],
    ['the hunt reads the sea as authored', (s) => swap(s, `            from (select p.sea_id, voyage.sea_danger(p.sea_id, p_now) as danger, r.port_id, r.nm, r.code\n`, `            from (select p.sea_id, voyage.sea_danger(p.sea_id, null) as danger, r.port_id, r.nm, r.code\n`), /pressed sea in reach is not the first target|did not sail for the pressed sea/],
    ['she hunts off duty', (s) => swap(s, `  if not (p_duty and public.navy_hunts_on()) then\n`, `  if not public.navy_hunts_on() then\n`), /off duty she hunted/],
    ['she hunts with the pirates dark', (s) => swap(s, `  if not (p_duty and public.navy_hunts_on()) then\n`, `  if not (p_duty and public.navy_on()) then\n`), /navy on and pirates off, she is not on her patrol|the pirates dark, she did not patrol/],
    ['she never lies', (s) => swap(s, `    if n.hunt_until is not null and n.hunt_until > p_now then\n      return 'HUNTING';\n    end if;\n`, `\n`), /she did not lie|did not keep watching|inside the hours she did not lie/],
    ['her lie never ends', (s) => swap(s, `    if n.hunt_until is not null and n.hunt_until > p_now then\n      return 'HUNTING';\n    end if;\n`, `    if n.hunt_until is not null then\n      return 'HUNTING';\n    end if;\n`), /past the hours she did not pick again|past the hours she did not sail home/],
    ['the step is not hunked', (s) => swap(s, `  v_hunt := public.navy_hunt_step(p_fleet, f.port_id, v_home, v_duty, p_now);\n  if v_hunt is not null then\n    return v_hunt;\n  end if;\n`, `\n`), /she did not sail for the pressed sea|is not in the new body once/],
    // the regard
    ['the pirate row pays the pirates too', (s) => swap(s, `       from public.great_powers g join public.nations gn on gn.id = g.nation_id where not g.pirate order by gn.code;\n`, `       from public.great_powers g join public.nations gn on gn.id = g.nation_id order by gn.code;\n`), /beating a pirate ship earned/],
    ['the pirate row pays when beaten', (s) => swap(s, `     and (v_out in ('PLUNDERED', 'RANSOM') or not exists (select 1 from public.ships s where s.fleet_id = v_d and s.durability > 0)) then\n`, `     then\n`), /beaten by a pirate ship, regard moved/],
    ['the pirate row pays for a cargo ship', (s) => swap(s, `  if public.fleet_kind(v_d) = 'PIRATE'\n`, `  if public.fleet_kind(v_d) in ('PIRATE', 'CARGO_SHIP')\n`), /a cargo ship beaten earned the pirate row/],
    ['the knob ships lit', (s) => swap(s, `    ('regard_pirate_beaten', to_jsonb(30),`, `    ('regard_pirate_beaten', to_jsonb(31),`), /the knobs are not as shipped/],
    // the catalog
    ['a client can call the pass', (s) => swap(s, `  revoke all on function public.navy_hunt_pass(timestamptz, uuid) from public, anon, authenticated;\n`, `  grant execute on function public.navy_hunt_pass(timestamptz, uuid) to authenticated;\n`), /a new function can be called from a client/],
    ['the read is volatile', (s) => swap(s, `create function public.navy_hunts_on()\nreturns boolean\nlanguage sql\nstable\n`, `create function public.navy_hunts_on()\nreturns boolean\nlanguage sql\nvolatile\n`), /a read is not stable/],
    ['a hunk is off its line', (s) => swap(s, `$h$  v_esc   text;   -- 0333\nbegin\n$h$,`, `$h$  v_esc   text;    -- 0333\nbegin\n$h$,`), /occurs 0 time/],
    ['the switch is lit by the file', (s) => swap(s, `  -- ── 1. THE KNOBS AND THE COLUMNS (all new; no existing key is touched) ──\n`, `  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';\n`), /a switch is not off|a world_config row moved/],
    // the review of 2026-11-07 (one mutation a fix; the events clause's index is a cost, which no proof can see)
    ['a pirate harbour is a hunt\'s harbour', (s) => swap(s, `                     and not public.pirate_power(public.port_nation(p.id))\n`, `\n`), /a harbour the pirates hold is a target|she hunted a harbour the pirates hold/],
    ['a stale hunt survives a call', (s) => swap(s, `  if n.mission <> 'HUNT' and (n.hunt_port is not null or n.hunt_until is not null) then\n`, `  if false then\n`), /a stale hunt survived a call/],
    ['the sea is read outside the ship\'s block', (s) => swap(s, `    begin   -- everything of one ship inside her own block: a sea that cannot be read (voyage.sea_near raises E_NO_SEA for a point no sea claims) skips her with a warning, and the rest go on\n      v_sea := public.fleet_sea(r.fleet_id, p_now);\n`, `    v_sea := public.fleet_sea(r.fleet_id, p_now);\n    begin\n`), /E_NO_SEA/],
  ]
}
