// ═══════════════════════════════════════════════════════════════════════════════
// mutations-0338.mjs — the mutation controls of proof-0338.mjs: deliberate breakages of 0338, each REQUIRED to fail for its own reason.
// ═══════════════════════════════════════════════════════════════════════════════
// Each entry: [label, mutate(sql) -> sql, the error it must raise, (optional) SQL run first on the world]. SELF = the file's own self-assert must catch it; AFTER = the file is clean in itself and only
// proof 45 (run right after it) can see it. A mutation that passes, or fails for another reason, fails the harness.

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

export function mutations(swap) {
  // AFTER: take one hunk's NEW text out again (the hunk becomes a no-op: the file is clean in itself, the live body is the old one)
  const neuter = (sql, fn) => {
    const re = new RegExp(`(\\('${esc(fn)}', 1,\\n\\$h\\$)([\\s\\S]*?)(\\$h\\$,\\n\\$h\\$)([\\s\\S]*?)(\\$h\\$\\))`)
    const m = re.exec(sql)
    if (!m) throw new Error(`no hunk for ${fn}`)
    return sql.replace(re, (_all, a, old, b, _new, c) => a + old + b + old + c)
  }
  const drop = (sql, re) => {
    if (!re.test(sql)) throw new Error(`pattern not found: ${re}`)
    return sql.replace(re, '')
  }
  return [
    // ── SELF ──
    ['SELF a hunk no longer occurs (city_capital, old text moved)', (s) => swap(s, "$h$   where n.id = public.port_nation(p_port)\n$h$,\n$h$   where n.id = public.port_nation(p_port)\n     and not public.pirate_power(n.id)", "$h$    where n.id = public.port_nation(p_port)\n$h$,\n$h$   where n.id = public.port_nation(p_port)\n     and not public.pirate_power(n.id)"), /hunk 1 of public\.city_capital\(uuid\) occurs 0 time/],
    ['SELF another function moved (great_power)', (s) => swap(s, "  v_ms := v_ms || jsonb_build_object('recut'", "  execute replace(pg_get_functiondef('public.great_power(uuid)'::regprocedure), 'select exists', 'select not not exists');\n  v_ms := v_ms || jsonb_build_object('recut'"), /a function this file does not re-cut moved/],
    ['SELF a reader turned volatile (pirate_power)', (s) => swap(s, "create function public.pirate_power(p_nation uuid)\nreturns boolean\nlanguage sql\nstable", "create function public.pirate_power(p_nation uuid)\nreturns boolean\nlanguage sql\nvolatile"), /is not stable, definer, search_path-pinned and server-only/],
    ['SELF a grant to anon (port_is_free)', (s) => swap(s, "  revoke all on function public.port_is_free(uuid) from public, anon, authenticated;", "  revoke all on function public.port_is_free(uuid) from public, anon, authenticated;\n  grant execute on function public.port_is_free(uuid) to anon;"), /is not stable, definer, search_path-pinned and server-only/],
    ['SELF a reader with a moved search_path (nation_joinable)', (s) => swap(s, "create function public.nation_joinable(p_nation uuid)\nreturns boolean\nlanguage sql\nstable\nsecurity definer\nset search_path = public, pg_temp", "create function public.nation_joinable(p_nation uuid)\nreturns boolean\nlanguage sql\nstable\nsecurity definer"), /is not stable, definer, search_path-pinned and server-only/],
    ['SELF a knob moved (tax_rate_max)', (s) => swap(s, "  comment on function public.pirate_power(uuid) is", "  update public.world_config set value = to_jsonb(0.25) where key = 'tax_rate_max';\n  comment on function public.pirate_power(uuid) is"), /a knob moved, or the knobs are not shipped as planned/],
    ['SELF pirates_joinable shipped true', (s) => swap(s, "('pirates_joinable', 'false'::jsonb,", "('pirates_joinable', 'true'::jsonb,"), /a knob moved, or the knobs are not shipped as planned/],
    ['SELF pirate_ports_free shipped false (the free ports dark)', (s) => swap(s, "('pirate_ports_free', 'true'::jsonb,", "('pirate_ports_free', 'false'::jsonb,"), /a knob moved, or the knobs are not shipped as planned/],
    ['SELF port_is_free ignores the lever', (s) => swap(s, "  select coalesce(public.wc('pirate_ports_free') = 'true'::jsonb, false)\n", "  select true\n"), /with pirate_ports_free false a port is still free/],
    ['SELF world.tax_rate still taxes a free port (hunk taken out)', (s) => neuter(s, 'world.tax_rate(uuid, uuid)'), /do not all quote tax 0/],
    ['SELF no unique index: a second pirate power is accepted', (s) => drop(s, /  create unique index great_powers_one_pirate on public\.great_powers \(\(true\)\) where pirate;\n/), /a second pirate power was accepted/],
    ['SELF the home trigger left disabled', (s) => swap(s, "  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;\n", ""), /home guard trigger is not enabled again/],
    ['SELF only three homes claimed', (s) => swap(s, "c_homes constant text[] := array['POR', 'LGA', 'GOT', 'DJE'];", "c_homes constant text[] := array['POR', 'LGA', 'GOT'];"), /pirate homes were claimed, the plan names 4/],
    ['SELF Port Royal held first: the file refuses and applies nothing', (s) => s, /0338 refuses: Port Royal is held/, "update public.port_allegiance set nation_id = (select n.id from public.nations n where n.code = 'PRT') where port_id = (select p.id from public.ports p where p.code = 'POR');"],
    ['SELF the depth is not set', (s) => swap(s, "  update public.port_treasury t set depth_mult = 0.5 from public.ports p where p.id = t.port_id and p.code = any (c_homes);", "  perform 1;"), /depth set on 1 homes/],
    ['SELF the flag clock moves (since = now)', (s) => swap(s, "since = least(a.since, v_since)", "since = now()"), /with the flag clock held/],
    ['SELF nine wars written', (s) => drop(s, /\s+\('ENG', 'English shipping[^\n]*\),/), /war rows written, the plan names 10/],
    ['SELF one war is only a rivalry', (s) => swap(s, "select least(v_pir, n.id), greatest(v_pir, n.id), 'war', w.why", "select least(v_pir, n.id), greatest(v_pir, n.id), case when w.code = 'ENG' then 'rival' else 'war' end, w.why"), /not at war with exactly the ten/],
    ['SELF nation_joinable ignores the knob (always a great power)', (s) => swap(s, "(not public.pirate_power(p_nation) or coalesce(public.wc('pirates_joinable') = 'true'::jsonb, false))", "true"), /11 great powers and 11 joinable/],
    ['SELF nation_joinable never true (the knob is not read)', (s) => swap(s, "(not public.pirate_power(p_nation) or coalesce(public.wc('pirates_joinable') = 'true'::jsonb, false))", "not public.pirate_power(p_nation)"), /with pirates_joinable true, 10 joinable/],
    ['SELF a company is written to', (s) => swap(s, "  -- 6f THE MONEY PROOF BY CONSTRUCTION", "  update public.players set ducats = ducats where id = (select p.id from public.players p order by p.id limit 1);\n  -- 6f THE MONEY PROOF BY CONSTRUCTION"), /wrote 1 row\(s\) to players/],
    ['SELF a new harbour is given gold', (s) => swap(s, "  insert into public.nations (code, name, flag_char, capital_port_code) values ('PIR'", "  update public.port_treasury set ducats = 1 where port_id = (select p.id from public.ports p where p.code = 'LGA');\n  insert into public.nations (code, name, flag_char, capital_port_code) values ('PIR'"), /a new harbour holds gold/],
    ['SELF an influence row is written', (s) => swap(s, "  -- 6f THE MONEY PROOF BY CONSTRUCTION", "  insert into public.port_influence (port_id, nation_id, player_id, points) select p.id, g.nation_id, pl.id, 1 from public.ports p, public.great_powers g, public.players pl where p.code = 'LIS' and not g.pirate and pl.is_npc limit 1;\n  -- 6f THE MONEY PROOF BY CONSTRUCTION"), /wrote 1 row\(s\) to port_influence/],
    // ── AFTER ──
    ['AFTER city_capital still answers a pirate city', (s) => neuter(s, 'public.city_capital(uuid)'), /does not answer as the plan says|is not a free port without a crown/],
    ['AFTER port_fee still charges at a free port', (s) => neuter(s, 'public.port_fee(uuid, uuid, numeric)'), /a company of Portugal meets tax/],
    ['AFTER port_dues still says factor 2 at a free port', (s) => neuter(s, 'public.port_dues(uuid, uuid, numeric)'), /a company of Portugal meets tax/],
    ['AFTER set_tax does not refuse at a free port', (s) => neuter(s, 'cmd.set_tax(uuid, numeric)'), /set_tax at Port Royal answered/],
    ['AFTER depth_day moves a free port', (s) => neuter(s, 'public.depth_day(integer)'), /depth_day moved Port Royal/],
    ['AFTER convoy_ships_wanted names the pirates', (s) => neuter(s, 'public.convoy_ships_wanted()'), /convoy_ships_wanted does not answer the ten crowns/],
    ['AFTER tick_cargo_ships builds a circuit and ships for the pirates', (s) => neuter(s, 'public.tick_cargo_ships(timestamp with time zone, uuid)'), /the cargo job touched the pirates/],
    ['AFTER navy_read writes the pirates a navy', (s) => neuter(s, 'public.navy_read(timestamp with time zone)'), /the navy job touched the pirates/],
    ['AFTER navy_plan_step plans the pirates stations', (s) => neuter(s, 'public.navy_plan_step(timestamp with time zone, uuid)'), /the navy job touched the pirates/],
    ['AFTER world.levels lists the pirates in the regard list', (s) => neuter(s, 'world.levels()'), /the Levels regard list names/],
    ['AFTER world.snapshot does not serve joinable', (s) => neuter(s, 'world.snapshot()'), /the snapshot does not serve great 11, joinable 10/],
    ['AFTER found_house still lets the pirates in', (s) => neuter(s, 'cmd.found_house(text, text)'), /found_house under the pirates answered/],
    ['AFTER change_country still lets the pirates in', (s) => neuter(s, 'cmd.change_country(text)'), /change_country to the pirates answered/],
  ]
}
