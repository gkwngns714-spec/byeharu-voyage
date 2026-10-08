// measure-roster.mjs — measure every candidate merchant loop on the applied chain (PGlite).
// docs/NPC_TRADERS.md §3.2 / §14 (design check 2026-10-08). A MEASUREMENT, not a build step:
// scripts/build-npc-0098.mjs (slice 2) supersedes it with the real executor and the steady-state trim.
// Usage: node scripts/db/measure-roster.mjs [facts|legs|all]   (caches the applied chain as world.tar in the OS temp dir)
import { pathToFileURL, fileURLToPath } from 'node:url'
import { readFile, writeFile, stat } from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.resolve(HERE, '..', '..')
const CACHE = path.join(os.tmpdir(), 'byeharu-voyage-measure-roster-world.tar')
const { PGlite } = await import(pathToFileURL(`${REPO}/node_modules/@electric-sql/pglite/dist/index.js`).href)

const MODE = process.argv[2] ?? 'all'
const t0 = Date.now()
let db
if (await stat(CACHE).then(() => true, () => false)) {
  const bytes = await readFile(CACHE)
  db = await PGlite.create({ loadDataDir: new Blob([bytes], { type: 'application/x-tar' }) })
  console.log(`chain loaded from cache in ${((Date.now() - t0) / 1000).toFixed(1)} s`)
} else {
  const { applyChain } = await import(pathToFileURL(`${REPO}/scripts/db/apply-chain.mjs`).href)
  ;({ db } = await applyChain({ quiet: true, log: () => {} }))
  console.log(`chain applied in ${((Date.now() - t0) / 1000).toFixed(1)} s`)
  const dumped = new Uint8Array(await (await db.dumpDataDir('none')).arrayBuffer())
  await writeFile(CACHE, dumped)
  console.log(`cached ${(dumped.length / 1e6).toFixed(0)} MB at ${CACHE}`)
}
const q = async (sql, params = []) => (await db.query(sql, params)).rows

// ── FACTS ─────────────────────────────────────────────────────────────────────────────────────
if (MODE === 'facts' || MODE === 'all') {
  console.log('\n== registry rows vs privilege')
  const reg = await q(`select fn from public.client_rpc_entry_points()`)
  for (const r of reg) {
    const g = await q(`select has_function_privilege('authenticated', $1, 'execute') as ok`, [r.fn]).catch(() => [{ ok: 'ERR' }])
    if (g[0].ok !== true) console.log(`  NOT GRANTED: ${r.fn} (${g[0].ok})`)
  }
  console.log(`  ${reg.length} registry rows checked`)
  console.log('\n== wc knobs of interest')
  console.log(await q(`select key, value from public.world_config where key in ('route_probe_tuns','route_scan_goods','route_scan_keep','daily_cap_pct','time_compression','game_day_seconds','standing_route_laps_per_game_day','order_queue_max','hire_crew_rate','crew_wage_per_day') order by key`))
  console.log('\n== daily cap function')
  console.log(await q(`select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='world' and p.proname like 'daily_cap%'`))
  console.log('\n== crew_pool readers/writers in live bodies')
  console.log(await q(`select n.nspname||'.'||p.proname as f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind = 'f' and n.nspname in ('public','cmd','world','voyage') and pg_get_functiondef(p.oid) like '%crew_pool%' and pg_get_functiondef(p.oid) ~ 'update public.ports'`))
}

// ── LEGS ──────────────────────────────────────────────────────────────────────────────────────
if (MODE === 'legs' || MODE === 'all') {
  const CLASSES = { barca: { hold: 60, crew: 8, kn: 5.0, draft: 1 }, carlat: { hold: 90, crew: 12, kn: 6.0, draft: 1 }, nau: { hold: 400, crew: 60, kn: 4.4, draft: 3 } }
  const ROSTER = [
    ['Casa da Índia', 'Armada da Índia', 3, 'nau', ['LIS ELM CPT OLD KOC', 'LIS CPT KOC OLD ISL', 'LIS ELM CPT KOC', 'LIS CPT KOZ KOC']],
    ['Casa da Índia', 'Carreira do Brasil', 2, 'carlat', ['LIS LPA SLV', 'LIS SLV ELM', 'LIS SLV REC', 'LIS FNC SLV']],
    ['Casa da Guiné', 'Carreira da Guiné', 2, 'carlat', ['LIS LPA ELM SAO', 'LIS ELM SAO LPA', 'LIS SAO ELM', 'LIS ELM LUA']],
    ['Capitania de Macau', 'Nau do Trato', 2, 'nau', ['MAC NAG', 'MAC NAG MNL', 'MAC MNL NAG', 'MAC NAG OSA']],
    ['Kamer Amsterdam', 'Retourvloot', 3, 'nau', ['AMS CPT JAK BNT', 'AMS CPT JAK BNT ELM', 'AMS CPT MAL JAK', 'AMS CPT JAK']],
    ['Kamer Amsterdam', 'Oostzeevaart', 2, 'carlat', ['AMS GDA', 'AMS GDA COP', 'AMS COP GDA RIG', 'AMS HAM GDA']],
    ['Kamer Zeeland', 'Zeeuwse Vaart', 2, 'carlat', ['MID BOR LIS', 'MID LAR BIL LIS', 'MID LIS CAD BOR', 'MID NAN LIS']],
    ['Casa de Contratación', 'Flota de Indias', 3, 'nau', ['CAD LPA VER HAV', 'CAD LPA CAR HAV', 'CAD HAV VER', 'CAD LPA HAV CAR']],
    ['Casa de Contratación', 'Galeón de Manila', 2, 'nau', ['ACA MNL', 'ACA MNL MAC', 'ACA MAC MNL', 'ACA CLL MNL']],
    ['East India Company', 'Indiamen', 3, 'nau', ['PTH CPT SRT KOC', 'PTH CPT KOC SRT', 'PLY CPT SRT KOC', 'PTH ELM CPT KOC SRT']],
    ['East India Company', 'Country Ships', 2, 'carlat', ['SRT HOR MUS', 'SRT DIU HOR MUS', 'SRT MUS HOR DIU', 'SRT HOR DIU']],
    ['Levant Company', 'Turkey Fleet', 3, 'carlat', ['LON LIV IZM', 'LON LIV IZM ALE', 'PLY LIV IZM IST', 'LON ALE IZM LIV']],
    ['Merchant Adventurers', 'Cloth Fleet', 2, 'carlat', ['LON ARP HAM', 'LON BRU HAM COP', 'LON HAM ARP', 'LON ARP COP HAM']],
    ['Hanse zu Lübeck', 'Bergenfahrer', 2, 'carlat', ['LUB BER', 'LUB BER HAM', 'LUB COP BER', 'LUB BER STO']],
    ['Hanse zu Lübeck', 'Rigafahrer', 2, 'barca', ['LUB RIG', 'LUB GDA RIG STO', 'LUB RIG STO VIS', 'LUB STO RIG']],
    ['Hamburger Kontor', 'Flandernfahrer', 2, 'carlat', ['HAM BRU LAR', 'HAM ARP LAR BOR', 'HAM LON BRU', 'HAM BOR ARP']],
    ['Banco di San Giorgio', 'Coppia Genovese', 2, 'barca', ['GOA PAL', 'GOA LIV PAL NAP', 'GOA MRS BAR', 'GOA NAP PAL']],
    ['Banco di San Giorgio', 'Linea di Cadice', 2, 'carlat', ['GOA VAL CAD', 'GOA BAR VAL CAD', 'GOA CAD LIS MRS', 'GOA CAD BAR']],
    ['Mude di Venezia', "Muda d'Alessandria", 3, 'carlat', ['VEN DBR ALE', 'VEN DBR ALE COR', 'VEN ALE BEI DBR', 'VEN COR ALE']],
    ['Mude di Venezia', 'Muda di Fiandra', 2, 'carlat', ['VEN MES CAD LIS BRU', 'VEN PAL CAD LIS', 'VEN MES LIS MID', 'VEN CAD LIS NAP']],
    ['Marchands de Marseille', 'Caravane du Levant', 2, 'carlat', ['MRS CHS IST', 'MRS IZM IST', 'MRS ALE IZM', 'MRS IST ALE']],
    ['Marchands de Marseille', "Barques d'Alger", 2, 'barca', ['MRS ALG TUN', 'MRS TUN PAL', 'MRS ALG BAR', 'MRS TUN ALG']],
    ['Tüccar-ı İstanbul', 'Mısır Kervanı', 3, 'carlat', ['IST ALE BEI', 'IST IZM ALE BEI', 'IST BEI ALE RHO', 'IST ALE IZM']],
    ['Mercadores de Surat', 'Mocha Fleet', 2, 'carlat', ['SRT ADE JED', 'SRT ADE HOR', 'SRT JED ADE', 'SRT HOR ADE']],
    ['Tujjar al-Basra', 'Gulf Fleet', 2, 'barca', ['BSR HOR DIU', 'BSR HOR MUS', 'BSR DIU HOR', 'BSR MUS HOR']],
    ['Juncos de Quanzhou', 'Rota de Luzon', 3, 'carlat', ['QUA MNL', 'QUA MNL MAC', 'QUA MAC MNL', 'QUA HOI MNL']],
    ['Juncos de Quanzhou', 'Costa de Cantão', 2, 'barca', ['QUA GUA HOI', 'QUA HOI GUA MAC', 'QUA MAC GUA', 'QUA GUA MAC']],
    ['Shuinsen de Nagasaki', 'Shuinsen', 2, 'carlat', ['NAG HOI AYU', 'NAG MAC HOI', 'NAG AYU HOI', 'NAG MNL HOI']],
    ['Waegwan Traders', 'Tsushima Run', 2, 'barca', ['BUS HIR SAK', 'BUS SAK HIR', 'BUS HIR NAG', 'BUS NAG SAK']],
    ['Krom Phra Khlang', 'Siam Junks', 2, 'carlat', ['AYU MAL BNT', 'AYU MAL JAK', 'AYU HOI MAL', 'AYU BNT MAL']],
    ['Dansk Kompagni', 'Øresund Fleet', 2, 'carlat', ['COP LON BRU', 'COP HAM LON', 'COP BER LON', 'COP LON HAM']],
    ['Consulado de Bilbao', 'Flota de Vizcaya', 2, 'carlat', ['BIL NAN LIS', 'BIL LAR BOR', 'BIL LIS BOR', 'BIL BOR NAN LIS']],
    ['Armateurs de Nantes', 'Flotte de Nantes', 2, 'carlat', ['NAN LIS CAD', 'NAN BIL LIS', 'NAN CAD LIS', 'NAN LAR LIS']],
    ['Consolat de Barcelona', 'Nau Catalana', 2, 'carlat', ['BAR VAL PAL', 'BAR MRS GOA', 'BAR PAL NAP', 'BAR ALG VAL']],
    ['Mercadores do Porto', 'Costa do Algarve', 2, 'barca', ['OPO LIS CAD', 'OPO LIS SET', 'OPO BIL LIS', 'OPO LIS MLG']],
  ]
  const portRows = await q(`select id, code, max_draft, crew_pool, kind from public.ports`)
  const portBy = new Map(portRows.map((p) => [p.code, p]))
  const bulkBy = new Map((await q(`select code, bulk from public.goods`)).map((r) => [r.code, Number(r.bulk)]))
  const goodId = new Map((await q(`select id, code from public.goods`)).map((r) => [r.code, r.id]))
  const targetBy = new Map()
  for (const r of await q(`select p.code as port, g.code as good, pg.stock_target from public.port_goods pg join public.ports p on p.id=pg.port_id join public.goods g on g.id=pg.good_id`)) targetBy.set(r.port + ':' + r.good, Number(r.stock_target))

  const legCache = new Map()
  let msTotal = 0, calls = 0
  async function leg(from, to) {
    const k = from + '>' + to
    if (legCache.has(k)) return legCache.get(k)
    const a = portBy.get(from), b = portBy.get(to)
    if (!a || !b) { legCache.set(k, { err: `no port ${!a ? from : to}` }); return legCache.get(k) }
    const t = Date.now()
    const r = await q(`select world.trade_routes($1::uuid, null, null, 6, $2::uuid) as j`, [a.id, b.id])
    msTotal += Date.now() - t; calls++
    const rows = r[0].j.routes ?? []
    let nm = rows[0]?.nm
    if (nm == null) {
      const rr = await q(`select r.nm from voyage.reach_from($1::uuid) r where r.port_id = $2::uuid`, [a.id, b.id]).catch(() => [])
      nm = rr[0]?.nm ?? null
    }
    const out = { nm: nm == null ? null : Number(nm), goods: rows.map((x) => ({ code: x.code, pct: Number(x.return_pct), profit: Number(x.profit), outlay: Number(x.outlay), qty: Number(x.qty) })) }
    legCache.set(k, out)
    return out
  }
  // parcel: bounded by the SOURCE cap (0.35 × target) and the SINK cap, and the hold left (greedy over the top goods)
  async function linesProfit(from, to, goods, holdT) {
    const a = portBy.get(from), b = portBy.get(to)
    let holdLeft = holdT, total = 0, outlay = 0
    const parts = []
    for (const g of goods.slice(0, 3)) {
      const bulk = bulkBy.get(g.code) ?? 1
      const capFrom = 0.35 * (targetBy.get(from + ':' + g.code) ?? 0)
      const capTo = 0.35 * (targetBy.get(to + ':' + g.code) ?? 0)
      const cap = Math.floor(Math.min(capFrom, capTo, holdLeft / bulk))
      if (cap < 1) continue
      const gid = goodId.get(g.code)
      // THE SIZING RULE under test: how many units the SINK takes above the probe's buy price + 5 %,
      // from the quote authority's own p_limit walk (0005:442-448).
      const buyPrice = g.outlay / Math.max(g.qty, 1)
      const take = (await q(`select units from world.quote($1::uuid,$2::uuid,$3::numeric,'sell',$4::numeric,null)`, [b.id, gid, cap, buyPrice * 1.05]))[0]
      const units = Math.floor(Number(take.units))
      if (units < 1) continue
      const buy = (await q(`select units, total from world.quote($1::uuid,$2::uuid,$3::numeric,'buy',null,null)`, [a.id, gid, units]))[0]
      const u = Number(buy.units)
      if (!(u > 0)) continue
      const sell = (await q(`select total from world.quote($1::uuid,$2::uuid,$3::numeric,'sell',null,null)`, [b.id, gid, u]))[0]
      const p = Number(sell.total) - Number(buy.total)
      parts.push(`${g.code} ${g.pct.toFixed(0)}%×${u}u→${Math.round(p)}`)
      total += p; outlay += Number(buy.total); holdLeft -= u * bulk
    }
    return { total, outlay, parts }
  }

  const results = []
  for (const [house, fleet, n, cls, loops] of ROSTER) {
    const c = CLASSES[cls]
    const crew = n * c.crew, holdT = n * c.hold
    console.log(`\n### ${house} — ${fleet} (${n}×${cls}, crew ${crew}, hold ${holdT} t)`)
    for (const loop of loops) {
      const stops = loop.split(' ')
      const problems = []
      for (const s of stops) {
        const p = portBy.get(s)
        if (!p) problems.push(`no port ${s}`)
        else { if (p.kind !== 'HARBOUR') problems.push(`${s} not HARBOUR`); if (c.draft > Number(p.max_draft)) problems.push(`E_DRAFT ${s}(d${p.max_draft})`); if (Number(p.crew_pool) < 0.2 * crew) problems.push(`pool ${s}=${p.crew_pool}`) }
      }
      if (new Set(stops).size !== stops.length) problems.push('repeated harbour')
      let lapNm = 0, lapLines = 0, lapWages = 0, lapOutlay = 0, legLines = [], dark = 0
      for (let i = 0; i < stops.length; i++) {
        const from = stops[i], to = stops[(i + 1) % stops.length]
        const L = await leg(from, to)
        if (L.err) { legLines.push(`${from}→${to}: ${L.err}`); problems.push(`${from}→${to} ${L.err}`); continue }
        const days = L.nm != null ? L.nm / (c.kn * 24) : 0
        const wages = crew * days
        lapNm += L.nm ?? 0; lapWages += wages
        const lp = L.goods.length ? await linesProfit(from, to, L.goods, holdT) : { total: 0, outlay: 0, parts: [] }
        lapLines += lp.total; if (i === 0) lapOutlay = lp.outlay
        if (!L.goods.length) dark++
        legLines.push(`${from}→${to} ${Math.round(L.nm ?? 0)}nm w${Math.round(wages)}: ${lp.parts.join(', ') || '— no paying good'}${lp.parts.length ? ` ⇒ ${Math.round(lp.total)}` : ''}`)
      }
      const lapMin = (lapNm / (c.kn * 24) * 9) / 60
      const net = lapLines - lapWages
      results.push({ house, fleet, loop, net, lapWages, lapMin, problems, dark, lapOutlay, stops: stops.length })
      console.log(`  ${loop.padEnd(22)} lap ${Math.round(lapNm)} nm · ${lapMin.toFixed(1)} min at sea · wages ${Math.round(lapWages)} · lines ${Math.round(lapLines)} · NET ≈ ${Math.round(net)} · stop-0 outlay ${Math.round(lapOutlay)}${dark ? ` · ${dark} ballast leg(s)` : ''}${problems.length ? '  !! ' + problems.join('; ') : ''}`)
      for (const l of legLines) console.log(`      ${l}`)
    }
  }
  console.log(`\ntrade_routes: ${calls} calls, ${(msTotal / Math.max(calls, 1)).toFixed(1)} ms/call`)
  console.log('\n== best clean candidate per fleet (by lap net)')
  const byFleet = new Map()
  for (const r of results) {
    const k = r.house + '|' + r.fleet
    if (r.problems.length) continue
    if (!byFleet.has(k) || byFleet.get(k).net < r.net) byFleet.set(k, r)
  }
  for (const [k, r] of byFleet) console.log(`  ${k.padEnd(46)} ${r.loop.padEnd(22)} net ≈ ${Math.round(r.net).toString().padStart(7)}  wages ${Math.round(r.lapWages).toString().padStart(6)}  net/wages ${(r.net / Math.max(r.lapWages, 1)).toFixed(1)}  ${r.lapMin.toFixed(1)} min  outlay ${Math.round(r.lapOutlay)}`)
  const missing = [...new Set(results.map((r) => r.house + '|' + r.fleet))].filter((k) => !byFleet.has(k))
  if (missing.length) console.log('  NO CLEAN CANDIDATE: ' + missing.join('; '))
}
await db.close()
