// The deliberate breakages of migration 0344: [label, mutate(file), the error it must fail with].
// SELF lines must be caught by the file's own self-assert; PROOF lines pass the self-assert (it runs the writer narrowed to its probe) and must be caught by proof 51 right after.
export const mutations = (swap) => {
  const ins = `    on conflict (ship_id) do update set xp = excluded.xp where public.ship_xp.xp is distinct from excluded.xp;`
  const pick = `     where (p_player is null or s.player_id = p_player) and public.crown_house(s.player_id)\n    on conflict`
  const del = `     where s.id = x.ship_id and (p_player is null or s.player_id = p_player) and public.crown_house(s.player_id);`
  const lvl = `public.level_points(round(public.wc_num('npc_ship_level'))::int)`
  const self = `  -- ── 5. THE SELF-ASSERT: the catalog ──\n`
  return [
    ['SELF the switch ships lit', (s) => swap(s, `('npc_ship_level_enabled', 'false'::jsonb,`, `('npc_ship_level_enabled', 'true'::jsonb,`), /0344 self-assert FAIL: a knob moved, or the two new ones are not false and 5/],
    ['SELF the knob ships at 4', (s) => swap(s, `('npc_ship_level', to_jsonb(5),`, `('npc_ship_level', to_jsonb(4),`), /0344 self-assert FAIL: a knob moved, or the two new ones are not false and 5/],
    ['SELF a client may call the writer', (s) => swap(s, `  revoke all on function public.crown_hull_level_fix(uuid) from public, anon, authenticated;\n`, `  revoke all on function public.crown_hull_level_fix(uuid) from public, anon;\n  grant execute on function public.crown_hull_level_fix(uuid) to authenticated;\n`), /0344 self-assert FAIL: the writer is not VOLATILE, definer/],
    ['SELF the writer is not a definer', (s) => swap(s, `returns integer\nlanguage plpgsql\nsecurity definer\n`, `returns integer\nlanguage plpgsql\n`), /0344 self-assert FAIL: the writer is not VOLATILE, definer/],
    ['SELF another function moved', (s) => swap(s, self, `  execute replace(pg_get_functiondef('public.npc_fix_level(uuid)'::regprocedure), 'Written once,', 'Written  once,');\n${self}`), /0344 self-assert FAIL: another function moved/],
    ['SELF another knob moved', (s) => swap(s, self, `  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';\n${self}`), /0344 self-assert FAIL: a knob moved/],
    ['SELF a table appeared', (s) => swap(s, self, `  create table public.zz_0344 (x int);\n${self}`), /0344 self-assert FAIL: a table, view, index or trigger appeared/],
    ['SELF the level is one too high', (s) => swap(s, lvl, `public.level_points(round(public.wc_num('npc_ship_level'))::int + 1)`), /0344 self-assert FAIL: lit, the navy hull is not level 5/],
    ['SELF a second run writes again', (s) => swap(s, ins, `    on conflict (ship_id) do update set xp = excluded.xp;`), /0344 self-assert FAIL: lit, the navy hull is not written once, or the merchant is written, or a second run writes/],
    ['SELF the writer takes a merchant', (s) => swap(s, pick, `     where (p_player is null or s.player_id = p_player)\n    on conflict`), /0344 self-assert FAIL: lit, the navy hull is not written once, or the merchant is written/],
    ['SELF dark leaves the row', (s) => swap(s, del, `     where false;`), /0344 self-assert FAIL: dark again, the row is not gone/],
    ['SELF the probe is never rolled back', (s) => swap(s, `    raise exception using errcode = 'ZX344', message = 'PROBE_ROLLBACK_0344';\n`, `    null;\n`), /0344 self-assert FAIL: the probe did not run to its end/],
    ["PROOF dark deletes a merchant's experience", (s) => swap(s, del, `     where s.id = x.ship_id and (p_player is null or s.player_id = p_player) and (public.crown_house(s.player_id) or p_player is null);`), /PROOF 51 FAIL: dark, the writer wrote/],
    ['PROOF the writer ignores the knob', (s) => swap(s, lvl, `public.level_points(5)`), /PROOF 51 FAIL: the knob at 3/],
    ['PROOF a pirate hull is not a crown hull', (s) => swap(s, pick, `     where (p_player is null or s.player_id = p_player) and public.crown_house(s.player_id) and not exists (select 1 from public.pirate_ships x where x.player_id = s.player_id)\n    on conflict`), /PROOF 51 FAIL: lit, the writer wrote \d+ rows, not the/],
  ]
}
