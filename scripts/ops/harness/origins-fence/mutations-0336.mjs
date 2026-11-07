// The deliberate breakages of migration 0336: [label, mutate(file), the error it must fail with].
// A label that starts with SELF must be caught by the file's own self-assert: the mutation is a statement injected into the file right after it has cut the function and before it judges it, so the probe scenes (and the
// catalog checks) face a function that is wrong the way a careless edit of the hunk, or of a line beside it, would make it. The rest run AFTER the file has applied and passed, by a statement of their own, and only proof 43 can see them.
// "Remove the fence" cannot change one row of any answer (it is a plan), so no scene of equality can see it: the self-assert pins it by a text test on the live body, proof 43 by counting the calls public.crown_call_room receives.
export const mutations = (swap) => {
  const GET_DEF = `pg_get_functiondef('public.cargo_origins(uuid)'::regprocedure)`
  const stmt = (from, to) => {
    const d = `$o$${from}$o$`
    return `do $x$ declare d text := ${GET_DEF}; begin if position(${d} in d) = 0 or position(${d} in substr(d, position(${d} in d) + 1)) > 0 then raise exception 'mutation text is not there exactly once: %', ${d}; end if; execute replace(d, ${d}, $n$${to}$n$); end $x$;\n`
  }
  const JUDGE = `  -- ── 2. THE SELF-ASSERT: the catalog ──\n`
  const SURVIVES = `  -- nothing of the probe survives, and nothing else moved\n`
  const inject = (from, to) => (s) => swap(s, JUDGE, stmt(from, to) + JUDGE)
  const injectSql = (sql, at = JUDGE) => (s) => swap(s, at, sql + '\n' + at)
  const after = (from, to) => (s) => s + '\n' + stmt(from, to)

  const FENCE = ` offset 0) h`
  const INNER_ORDER = `order by x.room desc, h.code\n`
  const COURSE_LINE = `where x.room > 0\n                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)\n`
  const COURSE_END = `where c.from_port = h.id or c.to_port = h.id)\n                                      order by`
  const FALLBACK = `array[public.realm_capital(p_nation)])\n              else array[public.realm_capital(p_nation)] end`
  const THE_ROSTER = /PROOF 43 FAIL: (limit \d|scene \w+)/

  // The live body made wrong, one line at a time: each is run twice, as SELF (injected into the file's own run) and after the file (proof 43).
  const LIVE = [
    { label: 'the realm test is dropped', from: `and public.port_nation(p.id) = p_nation offset 0) h`, to: `offset 0) h`, self: /scene all: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'another realm, not this one', from: `public.port_nation(p.id) = p_nation offset 0) h`, to: `public.port_nation(p.id) <> p_nation offset 0) h`, self: /scene all: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'the sea place test is dropped', from: `where p.kind = 'HARBOUR' and public.port_nation(p.id)`, to: `where public.port_nation(p.id)`, self: /scene all: the new read/, proof: /PROOF 43 FAIL: scene all/ },
    { label: 'the course test is dropped', from: COURSE_LINE, to: `where x.room > 0\n`, self: /scene all: the new read/, proof: THE_ROSTER },
    { label: 'a course counts only at its start', from: COURSE_END, to: `where c.from_port = h.id)\n                                      order by`, self: /scene all: the new read/, proof: THE_ROSTER },
    { label: 'a course counts only at its end', from: COURSE_END, to: `where c.to_port = h.id)\n                                      order by`, self: /scene all: the new read/, proof: THE_ROSTER },
    { label: 'the room test is dropped', from: `where x.room > 0\n`, to: `where true\n`, self: /scene all: the new read/, proof: THE_ROSTER },
    { label: 'room 1 is not room', from: `where x.room > 0\n`, to: `where x.room > 1\n`, self: /scene all: the new read/, proof: /PROOF 43 FAIL: scene all/ },
    { label: 'the roster is ordered by the least room', from: INNER_ORDER, to: `order by x.room, h.code\n`, self: /scene cut3: the new read/, proof: THE_ROSTER },   // the inner order shows only where the limit cuts; the outer aggregate sorts what is left
    { label: 'a tie is cut at the higher code', from: INNER_ORDER, to: `order by x.room desc, h.code desc\n`, self: /scene cut1: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'the limit is always 3', from: `limit public.wc_int('convoy_rich_ports')) y)`, to: `limit 3) y)`, self: /scene all: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'there is no limit', from: `\n                                      limit public.wc_int('convoy_rich_ports')) y)`, to: `) y)`, self: /scene cut3: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'the limit is read from the wrong knob', from: `wc_int('convoy_rich_ports')`, to: `wc_int('convoy_rebase_idle_days')`, self: /scene cut3: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'an empty realm has no fallback', from: FALLBACK, to: `null::uuid[])\n              else array[public.realm_capital(p_nation)] end`, self: /scene none: the new read/, proof: /PROOF 43 FAIL: limit 1/ },
    { label: 'the off arm is not the capital', from: `              else array[public.realm_capital(p_nation)] end`, to: `              else null::uuid[] end`, self: /scene dark: the new read/, proof: /PROOF 43 FAIL: off, an origin is not the capital/ },
    { label: 'the switch is ignored', from: `select case when public.rich_cities_on()`, to: `select case when true`, self: /scene dark: the new read/, proof: /PROOF 43 FAIL: off, an origin is not the capital/ },
  ]

  return [
    // the file's own machinery
    ['SELF the body is not what the file was cut against', (s) => swap(s, `$h$                                       from public.ports h\n`, `$h$                                       from public.ports hh\n`), /0336 self-assert FAIL: hunk 1 of public\.cargo_origins\(uuid\) occurs 0 time/],
    ['SELF a hunk does not reverse', (s) => swap(s, `    v_def := replace(v_def, hk.new, hk.old);\n`, `    v_def := replace(v_def, hk.new, hk.old || ' ');\n`), /0336 self-assert FAIL: .* does not reverse to its pre-image/],
    ['SELF the fence is taken out of the hunk (its text)', (s) => swap(s, `public.port_nation(p.id) = p_nation offset 0) h\n`, `public.port_nation(p.id) = p_nation) h\n`), /0336 self-assert FAIL: the realm test does not stand ahead of public\.crown_call_room/],
    ['SELF the fence is taken out of the live body', inject(FENCE, `) h`), /0336 self-assert FAIL: the realm test does not stand ahead of public\.crown_call_room/],
    ['SELF the function becomes volatile', injectSql(`alter function public.cargo_origins(uuid) volatile;`), /0336 self-assert FAIL: the ACL, volatility, definer or config of public\.cargo_origins moved/],
    ['SELF a client can reach it', injectSql(`grant execute on function public.cargo_origins(uuid) to anon;`), /0336 self-assert FAIL: the ACL, volatility, definer or config of public\.cargo_origins moved/],
    ['SELF its search path moves', injectSql(`alter function public.cargo_origins(uuid) set search_path = public;`), /0336 self-assert FAIL: the ACL, volatility, definer or config of public\.cargo_origins moved/],
    ['SELF another function moved', injectSql(`do $x$ begin execute replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), '0307: THE gold', '0307: THE  gold'); end $x$;`), /0336 self-assert FAIL: another function moved/],
    ['SELF a knob moved', injectSql(`update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';`, SURVIVES), /0336 self-assert FAIL: a world_config row moved/],
    ['SELF the probe leaves a nation behind', injectSql(`insert into public.nations (code, name, flag_char) values ('QX6', 'x', 'x');`, SURVIVES), /0336 self-assert FAIL: the probe left rows behind/],
    ['SELF a probe purse drifts from the room it was built for', (s) => swap(s, `"QYB": 50010,`, `"QYB": 50020,`), /0336 self-assert FAIL: the probe purses are not the rooms the scenes were built on/],
    ['SELF the OLD reference is not the pre-image', (s) => swap(s, `  execute v_old;\n`, `  execute replace(v_old, 'x.room > 0', 'x.room > 1');\n`), /0336 self-assert FAIL: scene all: the OLD body does not answer what the scene was built to ask/],
    ['SELF a scene runs with the other switch', (s) => swap(s, `('all',  true,  9, c_base),`, `('all',  false, 9, c_base),`), /0336 self-assert FAIL: scene all did not run with the switch it names/],

    // the live body made wrong, in the file's own self-assert
    ...LIVE.map((m) => [`SELF ${m.label}`, inject(m.from, m.to), m.self]),
    // and after the file has passed, in proof 43
    ['the fence is taken out (proof 43 counts the calls)', after(FENCE, `) h`), /PROOF 43 FAIL: public\.crown_call_room was asked of a harbour outside the realm/],
    ...LIVE.map((m) => [m.label, after(m.from, m.to), m.proof]),
  ]
}
