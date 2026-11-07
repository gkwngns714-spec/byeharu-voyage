// The deliberate breakages of migration 0335: [label, mutate(file), the error it must fail with].
// SELF lines change the file itself, and its own self-assert must catch them. The rest change a function AFTER the file has applied and passed, by a statement of their own, so only proof 42's real job can see them.
export const mutations = (swap) => {
  const after = (fn, from, to) => (s) => {
    const d = `$o$${from}$o$`
    return s + `\ndo $x$ declare d text := pg_get_functiondef('${fn}'::regprocedure); begin if position(${d} in d) = 0 then raise exception 'mutation text is gone: %', ${d}; end if; execute replace(d, ${d}, $n$${to}$n$); end $x$;\n`
  }
  const can = 'public.capital_can_draw(uuid,bigint)'
  const add = 'public.navy_add(timestamp with time zone,uuid)'
  const pay = 'public.navy_pay(timestamp with time zone,uuid)'
  const donors = 'public.crown_donors(uuid)'
  return [
    ['SELF the draw calls nothing', (s) => swap(s, `    perform public.crown_call(v_short);\n`, ``), /0335 self-assert FAIL: the need was not called exactly/],
    ['SELF a hull can be cut', (s) => swap(s, `    if p_whole and public.city_surplus(p_capital) < p_need then\n`, `    if false then\n`), /0335 self-assert FAIL: a hull the realm could not pay for moved gold/],
    ['SELF every draw is whole', (s) => swap(s, `    if p_whole and public.city_surplus(p_capital) < p_need then\n`, `    if public.city_surplus(p_capital) < p_need then\n`), /0335 self-assert FAIL: an hour's pay did not take/],
    ['SELF the need is a ducat short', (s) => swap(s, `'target', public.treasury_balance(p_capital) + p_need, 'cap'`, `'target', public.treasury_balance(p_capital) + p_need - 1, 'cap'`), /0335 self-assert FAIL/],
    ['SELF a rich capital reads as poor', (s) => swap(s, `  select case when public.city_surplus(p_capital) >= p_need then true\n`, `  select case when false then true\n`), /PROOF 42 FAIL: a rich capital read the realm/],
    ['SELF the richest last', (s) => swap(s, `  select h.id, c.room, row_number() over (order by c.room desc, h.code)\n`, `  select h.id, c.room, row_number() over (order by c.room, h.code)\n`), /0335 self-assert FAIL: the (richest did not pay first|need was not called exactly)/],
    ['SELF any harbour may give', (s) => swap(s, `   where h.kind = 'HARBOUR' and h.id <> p_capital and public.city_capital(h.id) = p_capital and c.room > 0\n$body$`, `   where h.kind = 'HARBOUR' and h.id <> p_capital and c.room > 0\n$body$`), /0335 self-assert FAIL/],
    ['SELF a client can draw', (s) => swap(s, `  revoke all on function public.capital_draw(uuid, bigint, boolean) from public, anon, authenticated;\n`, `  grant execute on function public.capital_draw(uuid, bigint, boolean) to authenticated;\n`), /0335 self-assert FAIL: a client can reach the draw/],
    ['SELF a read function is volatile', (s) => swap(s, `returns boolean\nlanguage sql\nstable\nsecurity definer\nset search_path = public, pg_temp\nas $body$\n  -- 0335: can p_need`, `returns boolean\nlanguage sql\nsecurity definer\nset search_path = public, pg_temp\nas $body$\n  -- 0335: can p_need`), /0335 self-assert FAIL: a new function is not what this file made/],
    ['SELF a hunk does not reverse', (s) => swap(s, `        v_def := replace(v_def, x.new, x.old);\n`, `        v_def := replace(v_def, x.new, x.old || ' ');\n`), /0335 self-assert FAIL: .* does not reverse/],
    ['SELF the body is not what it was cut against', (s) => swap(s, `$h$  v_can := floor(greatest(public.city_surplus(v_cap), 0) / v_slice);\n$h$,\n$h$  perform`, `$h$  v_can := floor(greatest(public.city_surplus(v_cap), 1) / v_slice);\n$h$,\n$h$  perform`), /0335 self-assert FAIL: hunk 2 of public.navy_pay.* occurs 0 time/],
    ['SELF another function moved', (s) => swap(s, `  -- ── 5. THE SELF-ASSERT: the catalog ──\n`, `  execute replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), '0307: THE gold', '0307: THE  gold');\n  -- ── 5. THE SELF-ASSERT: the catalog ──\n`), /0335 self-assert FAIL: another function moved/],
    ['SELF a knob moved', (s) => swap(s, `  -- ── 5. THE SELF-ASSERT: the catalog ──\n`, `  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';\n  -- ── 5. THE SELF-ASSERT: the catalog ──\n`), /0335 self-assert FAIL: a world_config row moved/],

    ['the realm is taken as endless', after(can, `else public.city_surplus(p_capital) + coalesce`, `else 1000000000000 + coalesce`), /PROOF 42 FAIL/],
    ['the gap to the reserve is not counted', after(can, `else public.city_surplus(p_capital) + coalesce`, `else greatest(public.city_surplus(p_capital), 0) + coalesce`), /PROOF 42 FAIL/],
    ['can_draw reads the capital alone', after(can, `else public.city_surplus(p_capital) + coalesce((select sum(d.room) from public.crown_donors(p_capital) d), 0) >= p_need end`, `else false end`), /PROOF 42 FAIL/],
    ['a build draws in parts', after(add, `public.capital_draw(v_cap, v_need, true)`, `public.capital_draw(v_cap, v_need, false)`), /PROOF 42 FAIL: a busy donor/],
    ['a build does not draw', after(add, `      continue when not public.capital_draw(v_cap, v_need, true);\n`, ``), /PROOF 42 FAIL/],
    ['a wake draws', after(add, `    if v_up then\n      update public.navy_ships n`, `    if v_up then\n      perform public.capital_draw(v_cap, v_need, true);\n      update public.navy_ships n`), /PROOF 42 FAIL: a realm that can pay did not wake her, or the wake moved gold/],
    ['the read under the lock is the capital alone', after(add, `    continue when not public.capital_can_draw(v_cap, v_need);\n    if v_up then`, `    continue when public.city_surplus(v_cap) < v_need;\n    if v_up then`), /PROOF 42 FAIL/],
    ['the read before the lock is the capital alone', after(add, `or not public.capital_can_draw(v_cap, v_need);\n    continue when not public.treasury_try_lock`, `or public.city_surplus(v_cap) < v_need;\n    continue when not public.treasury_try_lock`), /PROOF 42 FAIL/],
    ['a realm is called with no read first', after(add, `or not public.capital_can_draw(v_cap, v_need);\n    continue when not public.treasury_try_lock(v_cap);\n    continue when not public.capital_can_draw(v_cap, v_need);\n`, `;\n    continue when not public.treasury_try_lock(v_cap);\n`), /PROOF 42 FAIL/],
    ['a busy capital is taken', after(add, `    continue when not public.treasury_try_lock(v_cap);\n`, ``), /PROOF 42 FAIL: a busy capital was taken/],
    ['a busy capital draws', after(pay, `  if not public.treasury_try_lock(v_cap) then\n    return 0;\n  end if;\n`, ``), /PROOF 42 FAIL: a busy capital drew on its realm/],
    ['pay does not draw', after(pay, `  perform public.capital_draw(v_cap, v_slice * (select count(*) from public.navy_ships_in_service n where n.nation_id = v_nat));\n`, ``), /PROOF 42 FAIL: the hour/],
    ['pay draws for one ship', after(pay, `v_slice * (select count(*) from public.navy_ships_in_service n where n.nation_id = v_nat)`, `v_slice`), /PROOF 42 FAIL: the hour/],
    ['pay draws for more than it pays', after(pay, `v_slice * (select count(*) from public.navy_ships_in_service n where n.nation_id = v_nat)`, `v_slice * 99`), /PROOF 42 FAIL: the hour/],
    ['pay draws all or nothing', after(pay, `where n.nation_id = v_nat));\n`, `where n.nation_id = v_nat), true);\n`), /PROOF 42 FAIL: one slice of realm|PROOF 42 FAIL: what the realm had/],
    ['the donor read drops the room test', after(donors, ` and c.room > 0`, ``), /PROOF 42 FAIL: the lifted read differs/],
    ['the donor read loses its tie order', after(donors, `order by c.room desc, h.code)`, `order by c.room desc, h.code desc)`), /PROOF 42 FAIL: the lifted read differs/],
    ['the capital gives to itself', after(donors, `h.id <> p_capital and `, ``), /PROOF 42 FAIL: the lifted read differs/],
  ]
}
