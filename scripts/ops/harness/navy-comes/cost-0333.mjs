// proof-0333.mjs --cost: what a press costs and what the job gains, with a country's 24 hulls on the probe world. PGlite on this PC, rolled back. Prod is not measured: the dev-log scales these.
export async function cost(db, file, say) {
  const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]
  await db.exec('begin')
  await db.exec(file)
  await db.exec(`
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'convoys_enabled', 'attack_enabled', 'navy_enabled');
    insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
    update public.port_treasury set ducats = 50000000, reserve = 0;
    update public.ports p set crew_pool = 5000;
    do $$ declare v uuid; n int; begin for v in select g.nation_id from public.great_powers g loop for n in 1 .. 3 loop perform public.tick_cargo_ships(now(), v); end loop; end loop; end $$;
  `)
  const nat = (await db.query(`select g.nation_id as id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP'`)).rows[0].id
  await db.query(
    `insert into public.navy_realms (nation_id, ships, read_at) values ($1, 24, now()) on conflict (nation_id) do update set ships = 24, read_at = now()`,
    [nat],
  )
  await db.exec(`
    do $$
    declare
      v_nat uuid := '${nat}';
      v_cap uuid := public.realm_capital(v_nat);
      v_o   int;
    begin
      for v_o in 1 .. 24 loop
        perform public.navy_commission(v_nat, v_o, v_cap, public.refit_yard(v_cap), v_cap, now());
      end loop;
    end $$;
  `)
  const time = async (sql, args = []) => {
    const t = performance.now()
    await db.query(sql, args)
    return performance.now() - t
  }
  // the reads a press makes, on 24 hulls in port: harbour, arrival of each. Nothing written.
  const site = (await db.query(`select p.lat::float8 as lat, p.lon::float8 as lon from public.ports p where p.kind = 'HARBOUR' order by p.code offset 40 limit 1`)).rows[0]
  const near = []
  for (let i = 0; i < 12; i++) near.push(await time(`select public.harbour_nearest($1, $2)`, [site.lat, site.lon]))
  say(`COST: harbour_nearest ${median(near).toFixed(1)} ms`)
  const to = (await db.query(`select public.harbour_nearest($1, $2) as id`, [site.lat, site.lon])).rows[0].id
  const arr = []
  for (let i = 0; i < 12; i++) arr.push(await time(`select count(public.navy_arrival(n.fleet_id, $1, now(), now())) from public.navy_ships n where n.nation_id = $2`, [to, nat]))
  say(`COST: navy_arrival over 24 hulls ${median(arr).toFixed(1)} ms`)
  const cap = (await db.query(`select public.realm_capital($1) as id`, [nat])).rows[0].id
  const plan = []
  for (let i = 0; i < 12; i++) plan.push(await time(`select public.cargo_circuit_plan($1, $2, $3) #> '{legs,0,nm}'`, [nat, cap, to]))
  say(`COST: one path (cargo_circuit_plan) ${median(plan).toFixed(1)} ms`)
  // an escort's step: the port read of the richest ship, with nobody to follow and with the rule reading the line
  const fl = (await db.query(`select n.fleet_id as id from public.navy_ships n where n.nation_id = $1 order by n.ord desc limit 1`, [nat])).rows[0].id
  const esc = []
  for (let i = 0; i < 12; i++) esc.push(await time(`select public.navy_escort_step($1, $2, true, now())`, [fl, cap]))
  say(`COST: escort step, no ship with funds at sea, ${median(esc).toFixed(1)} ms`)
  const fls = (await db.query(`select n.fleet_id as id from public.navy_ships n where n.nation_id = $1 order by n.ord limit 1`, [nat])).rows[0].id
  const none = []
  for (let i = 0; i < 12; i++) none.push(await time(`select public.navy_escort_step($1, $2, true, now())`, [fls, cap]))
  say(`COST: escort step, the first of the line, ${median(none).toFixed(1)} ms`)
  await db.exec('rollback')
}
