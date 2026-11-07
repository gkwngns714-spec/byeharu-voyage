// What the fence saves, on the local world: the calls public.crown_call_room receives, and the time of one lit read, 0324's body against the fenced one, for the realm with the most harbours. Rolled back.
// PGlite is Postgres 18 compiled to wasm: it plans as prod's Postgres does (the plan text matches), but its clock is not prod's. The CALLS are the portable figure; the milliseconds are only a local reading.
export async function cost(db, file, say) {
  const q = async (sql) => (await db.query(sql)).rows
  await db.exec('begin')
  // 0324's body, renamed into pg_temp BEFORE the file replaces it
  await db.exec(`do $x$ begin execute replace(pg_get_functiondef('public.cargo_origins(uuid)'::regprocedure), 'FUNCTION public.cargo_origins(', 'FUNCTION pg_temp.cargo_origins_pre('); end $x$`)
  await db.exec(file)
  await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('convoys_enabled', 'convoy_rich_enabled')`)
  await db.exec(`update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share'`)
  await db.exec(`update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover'`)
  await db.exec(`update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor'`)
  await db.exec(`insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing`)
  await db.exec(`update public.port_treasury t set ducats = case when x.n % 3 = 0 then 0 else 3000000 + x.n * 1000 end, reserve = x.n % 50000 from (select p.id, abs(hashtextextended(p.code, 0)) % 1000000 as n from public.ports p) x where x.id = t.port_id`)
  const big = (await q(`select g.nation_id as id, n.code, (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = g.nation_id)::int as harbours
                          from public.great_powers g join public.nations n on n.id = g.nation_id order by 3 desc, 2 limit 1`))[0]
  const harbours = (await q(`select count(*)::int as n from public.ports p where p.kind = 'HARBOUR'`))[0].n
  say(`COST: realm ${big.code}, ${big.harbours} of the world's ${harbours} harbours`)
  const timed = async (label, sql, n = 20) => {
    const a = []
    for (let i = 0; i < n; i++) {
      const t = performance.now()
      await db.query(sql)
      a.push(performance.now() - t)
    }
    a.sort((x, y) => x - y)
    say(`COST: ${label}: median ${a[n >> 1].toFixed(1)} ms, max ${a[n - 1].toFixed(1)} ms (${n} reads)`)
  }
  await timed('0324 body, one lit read', `select pg_temp.cargo_origins_pre('${big.id}')`)
  await timed('fenced body, one lit read', `select public.cargo_origins('${big.id}')`)
  // the calls: a stable wrapper that notes each harbour it is asked about
  await db.exec(`alter function public.crown_call_room(uuid) rename to crown_call_room_real_cost`)
  await db.exec(`create function public.crown_call_room(p_port uuid) returns bigint language plpgsql stable as $b$ begin perform set_config('byeharu.crc_cost', coalesce(current_setting('byeharu.crc_cost', true), '') || p_port::text || ',', true); return public.crown_call_room_real_cost(p_port); end $b$`)
  const calls = async (sql) => {
    await db.query(`select set_config('byeharu.crc_cost', '', true)`)
    await db.query(sql)
    const ids = (await q(`select current_setting('byeharu.crc_cost', true) as c`))[0].c.split(',').filter(Boolean)
    const outside = (await q(`select count(*)::int as n from unnest('{${ids.join(',')}}'::uuid[]) i where public.port_nation(i) is distinct from '${big.id}'`))[0].n
    return { n: ids.length, outside }
  }
  const o = await calls(`select pg_temp.cargo_origins_pre('${big.id}')`)
  const f = await calls(`select public.cargo_origins('${big.id}')`)
  say(`COST: calls to public.crown_call_room for ${big.code}: 0324 body ${o.n} (${o.outside} for harbours of other realms), fenced body ${f.n} (${f.outside} for harbours of other realms)`)
  await db.exec('rollback')
}
