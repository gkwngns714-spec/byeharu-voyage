// What a lit run adds: public.crown_donors, public.capital_can_draw and a call, timed on the local world, rolled back. PGlite, not prod: the dev-log says how far to trust it.
export async function cost(db, file, say) {
  await db.exec('begin')
  await db.exec(file)
  await db.exec(`update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled'`)
  await db.exec(`insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing`)
  await db.exec(`update public.port_treasury set ducats = 100000000, reserve = 0`)
  const cap = (await db.query(`select public.realm_capital(g.nation_id) as id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'`)).rows[0].id
  const timed = async (label, sql, n = 20) => {
    const a = []
    for (let i = 0; i < n; i++) {
      const t = performance.now()
      await db.query(sql)
      a.push(performance.now() - t)
    }
    a.sort((x, y) => x - y)
    say(`COST: ${label}: median ${a[n >> 1].toFixed(1)} ms, max ${a[n - 1].toFixed(1)} ms`)
  }
  await timed('crown_donors, one realm', `select count(*) from public.crown_donors('${cap}')`)
  await timed('can_draw, the capital alone', `select public.capital_can_draw('${cap}', 1)`)
  await timed('can_draw, the realm read', `select public.capital_can_draw('${cap}', 900000000000)`)
  await db.exec(`update public.port_treasury set ducats = 0 where port_id = '${cap}'`)
  await timed('capital_draw, one donor', `select public.capital_draw('${cap}', 1000)`, 5)
  await db.exec('rollback')
}
