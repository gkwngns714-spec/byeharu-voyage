// proof-0331.mjs --cost: the job per call on the probe world, rolled back. It lays the design's 75 hulls by the real job at the design's ship counts, sends them out, and times real runs: dark, lit and busy.
// What it prints is PGlite on this PC, one session, on the probe world's 1,043 courses: a ratio to scale prod's own step cost by, never a prod figure.
const SIZES = { PRT: 15, FRA: 13, ESP: 11, NLD: 10, MNG: 7, OTT: 5, JPN: 5, MUG: 4, ENG: 3, JOS: 2 }

export async function cost(db, file, say) {
  await db.exec('begin')
  await db.exec(file)
  const q = async (s) => (await db.query(s)).rows
  const timed = async (label, n, s) => {
    const all = []
    let last
    for (let i = 0; i < n; i++) {
      const t0 = performance.now()
      last = await q(s(i))
      all.push(performance.now() - t0)
    }
    all.sort((a, b) => a - b)
    say(`COST: ${label}: median ${all[Math.floor(n / 2)].toFixed(1)} ms, max ${all.at(-1).toFixed(1)} ms over ${n} runs; ${JSON.stringify(last[0]?.r ?? '').slice(0, 160)}`)
    return all
  }
  const at = (m) => `now() + make_interval(mins => ${m})`
  await timed('dark, no ship (one knob, one empty read)', 200, () => `select public.tick_navy()::text as r`)
  await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'navy_enabled');
    update public.world_config set value = to_jsonb(0) where key = 'navy_build_hours';
    update public.world_config set value = to_jsonb(200) where key = 'navy_steps_per_run';
    insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
    update public.port_treasury set ducats = 2000000000, reserve = 0;
    update public.ports set crew_pool = 100000;`)
  await q(`select public.tick_navy(${at(0)})`)
  await db.exec(Object.entries(SIZES).map(([c, n]) => `update public.navy_realms r set ships = ${n}, read_at = ${at(100000)} from public.nations x where x.id = r.nation_id and x.code = '${c}';`).join('\n'))
  const plan = await timed('a run that writes one patrol (no ship out)', 12, (i) => `select public.tick_navy(${at(1 + i)})::text as r`)
  let m = 20
  for (let guard = 0; guard < 120; guard++) {
    const r = (await q(`select public.tick_navy(${at(m++)})::text as r, (select count(*)::int from public.navy_ships) as n`))[0]
    if (r.n >= 75 && !JSON.parse(r.r).plan) break
  }
  say(`COST: ${(await q(`select count(*)::int as n, count(*) filter (where f.status = 'SAILING')::int as s from public.navy_ships n join public.fleets f on f.id = n.fleet_id`)).map((x) => `${x.n} hulls, ${x.s} at sea`)}`)
  // every ship in port and past her port time: the worst run the bound allows, then the same with it
  const park = `update public.voyages v set status = 'ABORTED' from public.navy_ships n where n.fleet_id = v.fleet_id and v.status = 'SAILING';
    update public.fleets f set status = 'DOCKED', port_id = n.station_port, lat = null, lon = null, ready_at = null from public.navy_ships n where n.fleet_id = f.id;
    update public.navy_ships n set patrol = null, leg = 0;`
  await db.exec(park)
  await timed('worst case, 75 ships all due, no bound', 1, (i) => `select public.tick_navy(${at(300 + i)})::text as r`)
  await db.exec(park)
  await db.exec(`update public.world_config set value = to_jsonb(40) where key = 'navy_steps_per_run';`)
  await timed('worst case, bound at navy_steps_per_run 40', 1, (i) => `select public.tick_navy(${at(400 + i)})::text as r`)
  await timed('a quiet run, all ships at sea, one country paid', 12, (i) => `select public.tick_navy(${at(500 + i * 70)})::text as r`)
  // the scale: prod's idle cargo step is measured (10 ms, docs/dev-log/2026-11-06-cargo-ships-follow-wealth.md), so the same step here turns PGlite ms into prod ms
  await db.exec(`update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';`)
  await q(`select public.tick_cargo_ships(${at(600)})`)
  await timed('the scale: one idle cargo step', 40, () => `select public.cargo_ship_step((select c.fleet_id from public.cargo_ships c order by c.ord, c.nation_id limit 1))::text as r`)
  await db.exec('rollback')
  return plan
}
