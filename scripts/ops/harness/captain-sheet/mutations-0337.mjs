// The deliberate breakages of migration 0337: [label, mutate(file), the error it must fail with].
// SELF lines change the file itself, and its own self-assert must catch them. The rest are caught by proof 44 right after the file has applied and passed (a few are caught earlier still, by the self-assert's probe or by an
// earlier marker of the proof: those regexes name both). LIVE lines change a function the proof LEANS ON
// AFTER the file, by a statement of their own (the sheet composes crew_terms and captain_level, so a break there must still be seen by a number worked out from the tables, not by the sheet agreeing with it).
export const mutations = (swap) => {
  const after = (fn, from, to) => (s) => {
    const d = `$o$${from}$o$`
    return s + `\ndo $x$ declare d text := pg_get_functiondef('${fn}'::regprocedure); begin if position(${d} in d) = 0 then raise exception 'mutation text is gone: %', ${d}; end if; execute replace(d, ${d}, $n$${to}$n$); end $x$;\n`
  }
  const terms = 'public.crew_terms(uuid,timestamp with time zone)'
  const mult = 'public.captain_level_mult(uuid,text)'
  const accuracy = `      (1, 'gunnery',    'combat',      1, 'accuracy'),`
  const boarding = `      (2, 'boarding',   'combat',      1, 'attack'),`
  const body = `language plpgsql\nstable\nsecurity definer\nset search_path = public, pg_temp\nas $body$\n-- 0337: A CAPTAIN HAS A SHEET (docs/WORLD_POWERS.md 2.4). YOUR signing`
  const pct = `else coalesce((v_mine ->> d.effect)::numeric, 0) end as pct`
  const hosp = `v_hosp := case when public.skills_bite_on() then coalesce(world.skill_pct(v_player, null, 'homesick'), 0) end;`
  return [
    // ── the file's own asserts ──
    ['SELF the sheet is not STABLE', (s) => swap(s, body, body.replace('stable\n', '')), /0337 self-assert FAIL: the sheet is not STABLE/],
    ['SELF the sheet is not a definer', (s) => swap(s, body, body.replace('security definer\n', '')), /0337 self-assert FAIL: the sheet is not STABLE, definer/],
    ['SELF anon may read', (s) => swap(s, `  grant execute on function world.captain_stats(text) to authenticated;\n`, `  grant execute on function world.captain_stats(text) to authenticated;\n  grant execute on function world.captain_stats(text) to anon;\n`), /0337 self-assert FAIL: the grants are not its sibling/],
    ['SELF the registry row is missing', (s) => swap(s, `      ('world',       'captain_stats',         'text'),\n$h$;`, `$h$;`), /0337 self-assert FAIL: the read is not in the client registry/],
    ['SELF the registry hunk does not reverse', (s) => swap(s, `  if replace(v_def, c_new, c_old) <> v_pre then`, `  if replace(v_def, c_new, c_old) || ' ' <> v_pre then`), /0337 self-assert FAIL: public.client_rpc_entry_points does not reverse/],
    ['SELF the body is not what the hunk was cut against', (s) => swap(s, `c_old  constant text := $h$      ('world',       'navy_ship_card',        'uuid'),\n$h$;`, `c_old  constant text := $h$      ('world',       'navy_ship_cards',       'uuid'),\n$h$;`), /0337 self-assert FAIL: the registry hunk occurs 0 time/],
    ['SELF another function moved', (s) => swap(s, `  -- ── 3. THE SELF-ASSERT: the catalog ──\n`, `  execute replace(pg_get_functiondef('public.captain_level_mult(uuid,text)'::regprocedure), 'in the TRACK of the trait counted', 'in the TRACK  of the trait counted');\n  -- ── 3. THE SELF-ASSERT: the catalog ──\n`), /0337 self-assert FAIL: another function moved/],
    ['SELF a knob moved', (s) => swap(s, `  -- ── 3. THE SELF-ASSERT: the catalog ──\n`, `  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';\n  -- ── 3. THE SELF-ASSERT: the catalog ──\n`), /0337 self-assert FAIL: a world_config row moved/],
    ['SELF a table appeared', (s) => swap(s, `  -- ── 3. THE SELF-ASSERT: the catalog ──\n`, `  create table public.zz_0337 (x int);\n  -- ── 3. THE SELF-ASSERT: the catalog ──\n`), /0337 self-assert FAIL: a table, view, sequence or index appeared/],
    ['SELF the probe is never rolled back', (s) => swap(s, `    raise exception using errcode = 'ZX337', message = 'PROBE_ROLLBACK_0337';\n`, `    null;\n`), /0337 self-assert FAIL: the probe did not run to its end/],
    ['SELF a lone captain does not read crew_pct', (s) => swap(s, pct, `else coalesce((v_mine ->> d.effect)::numeric, 0) / 2 end as pct`), /0337 self-assert FAIL: a captain alone in her crew does not read crew_pct itself/],

    // ── proof 44 ──
    ['the part is the whole crew\'s answer, not hers', (s) => swap(s, pct, `else public.crew_pct(v_fleet, v_ship, d.effect) * 100 end as pct`), /PROOF 44 FAIL: (ELCANO's speed line reads|the parts do not add up to crew_pct)/],
    ['another captain\'s term is counted as hers', (s) => swap(s, `from public.crew_terms(v_fleet) t where t.player_officer_id = v_po group by t.effect`, `from public.crew_terms(v_fleet) t where t.player_officer_id is not null group by t.effect`), /PROOF 44 FAIL: (ELCANO's speed line reads|the parts do not add up to crew_pct)/],
    ['the part is cut at the effect\'s cap', (s) => swap(s, pct, `else least(coalesce((v_mine ->> d.effect)::numeric, 0), ce.cap_pct) end as pct`), /PROOF 44 FAIL: a cap of 8 is the crew's/],
    ['Gunnery is filed under the Exploration track', (s) => swap(s, accuracy, `      (1, 'gunnery',    'exploration', 1, 'accuracy'),`), /0337 self-assert FAIL: the sheet is not five stats in order|PROOF 44 FAIL: the sheet of .* is not the five stats, their tracks and their effects/],
    ['Gunnery reads the Trading level', (s) => swap(s, `jsonb_build_object('combat', public.captain_level(v_po, 'combat'),`, `jsonb_build_object('combat', public.captain_level(v_po, 'trading'),`), /PROOF 44 FAIL: .* reads levels that are not exploration/],
    ['Seamanship reads her own level, not the company-capped one', (s) => swap(s, `'exploration', public.captain_level(v_po, 'exploration'),`, `'exploration', public.level_from_points((select x.exploration from public.captain_xp x where x.player_officer_id = v_po)),`), /PROOF 44 FAIL: .* reads levels that are not exploration/],
    ['Gunnery and Boarding swap their effects', (s) => swap(swap(s, accuracy, `      (1, 'gunnery',    'combat',      1, 'attack'),`), boarding, `      (2, 'boarding',   'combat',      1, 'accuracy'),`), /PROOF 44 FAIL: the sheet of .* is not the five stats, their tracks and their effects/],
    ['Seamanship loses the storm', (s) => swap(s, `      (3, 'seamanship', 'exploration', 2, 'storm'),\n`, ``), /PROOF 44 FAIL: the sheet of .* is not the five stats, their tracks and their effects/],
    ['a signing with no xp row reads level 1', (s) => swap(s, `if exists (select 1 from public.captain_xp x where x.player_officer_id = v_po) then`, `if true then`), /PROOF 44 FAIL: a signing with no xp row does not read a blank level/],
    ['a captain ashore reads numbers', (s) => swap(s, `case when v_ship is null then null\n                  when ce.scope`, `case when false then null\n                  when ce.scope`), /0337 self-assert FAIL: ashore, a captain does not read blank parts|PROOF 44 FAIL: a captain ashore does not read blank parts|PROOF 44 FAIL: a role that is not hers/],
    ['a ship effect is read while combat is off', (s) => swap(s, `                  when ce.scope = 'ship' and not public.combat_bite_on() then null\n`, ``), /PROOF 44 FAIL: combat off: ship parts are not blank/],
    ['Hospitality is read while skills are off', (s) => swap(s, hosp, `v_hosp := coalesce(world.skill_pct(v_player, null, 'homesick'), 0);`), /PROOF 44 FAIL: skills off, a sheet still reads Hospitality/],
    ['Hospitality is read for a captain ashore', (s) => swap(s, `  if v_ship is not null then\n    select coalesce(jsonb_object_agg`, `  if true then\n    select coalesce(jsonb_object_agg`), /PROOF 44 FAIL: MURAKAMI reads Hospitality/],
    ['a part of 0 carries a line', (s) => swap(s, `case when p.pct > 0 then public.trait_effect_words`, `case when p.pct >= 0 then public.trait_effect_words`), /PROOF 44 FAIL: a part that is not hers carries a line/],
    ['the read writes an event (still declared STABLE)', (s) => swap(s, `  if v_po is null then\n    return null;\n  end if;\n  select cs.ship_id`, `  if v_po is null then\n    return null;\n  end if;\n  perform public.emit_event(v_player, 'PROBE_SHEET', '{}'::jsonb);\n  select cs.ship_id`), /PROOF 44 FAIL: the read is not stable or it wrote/],

    // ── a live rule the proof leans on: the sheet composes it, so only a number worked out from the tables can see it ──
    ['LIVE the grade floor lifts a captain who was never promoted', after(terms, `case when gs.ord > gb.ord then gs.floor_pct else 0 end`, `case when gs.ord >= gb.ord then gs.floor_pct else 0 end`), /PROOF 44 FAIL: ELCANO storm: crew_terms gives/],
    ['LIVE the grade floor is one grade too high to lift anyone', after(terms, `case when gs.ord > gb.ord then gs.floor_pct else 0 end`, `case when gs.ord > gb.ord + 1 then gs.floor_pct else 0 end`), /PROOF 44 FAIL: TARTAGLIA accuracy: crew_terms gives/],
    ['LIVE a level is worth one level less', after(mult, `(public.captain_level(p_signing, p_focus) - 1)`, `(public.captain_level(p_signing, p_focus) - 2)`), /PROOF 44 FAIL: ELCANO('s speed line| speed: crew_terms gives)/],
    ['LIVE a cabin off her focus is worth as much as her own', after(terms, `* case when x.cabin in ('captain', t.focus) then 1 else v_off end as value_pct`, `* 1 as value_pct`), /PROOF 44 FAIL: (YIJANGSON|WELSER) (accuracy|speed): crew_terms gives/],
  ]
}
