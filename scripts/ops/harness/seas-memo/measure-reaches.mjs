#!/usr/bin/env node
// measure-reaches.mjs: THE QUOTED DISTANCES, MEASURED AGAIN, AND WHAT THAT DOES TO PRICES (0442; owner row 352). LOCAL; reads a world image.
//
//   node scripts/ops/harness/seas-memo/measure-reaches.mjs <image.tar.gz> <out.json>
//
// public.sea_reaches.reaches is the distance the quay quotes between two places. It was last measured at 0076/0091/0217/0338/0414 by the search as it
// stood, between the roadsteads as they stood. 0440 moved 69 roadsteads and opened three straits, 0440's course author re-sails every course off the
// drawn land, and 0441 changed the search's rule: the voyage sailed is no longer the distance quoted. This measures every pair again, two ways:
//   raw      the search's own course (src/lib/sea floodPathTo), what the table held until now
//   sailed   the course the browser's course author proposes (the search, then refineCourse off the coast mask): what a fleet really sails
// and, for each, what world.haul_rows() would give every market row (public.port_goods.haul is a multiplier on the price), inside a transaction that
// is rolled back. It writes the new figures to <out.json> ({ raw: {A: {B: nm}}, sailed: {...} }) for scripts/build-sea-legs-migration.mjs.
import { writeFileSync } from 'node:fs'
import { openImage, readMask } from '../../../db/audit-land-crossings.mjs'
import { navFromServed, floodFrom, floodPathTo, refineCourse, coastLand, gcNm } from '../../../../src/lib/sea/index.ts'

const [image, outFile] = process.argv.slice(2)
const db = await openImage(image)
const raster = (await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell, replace(encode(cells, 'base64'), e'\\n', '') as cells_base64 from public.sea_raster where id = 1`)).rows[0]
const places = (await db.query(`select sr.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon, sr.reaches from public.sea_reaches sr order by sr.code collate "C"`)).rows
const nav = navFromServed(raster)
const land = coastLand(readMask(), nav)
const len = (c) => c.reduce((t, p, i) => (i ? t + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : t), 0)
const out = { raw: {}, sailed: {} }
for (const p of places) {
  out.raw[p.code] = {}
  out.sailed[p.code] = {}
}
const t0 = Date.now()
for (let i = 0; i < places.length; i++) {
  const a = places[i]
  const flood = floodFrom(nav, a)
  if (!flood) throw new Error(`${a.code}: its roadstead reaches no water`)
  for (let j = i + 1; j < places.length; j++) {
    const b = places[j]
    const r = floodPathTo(flood, a, b)
    if (!r) throw new Error(`${a.code} to ${b.code}: no way by sea`)
    const raw = Number(r.nm.toFixed(1))
    const sailed = Number(len(refineCourse(nav, land, r.path).path).toFixed(1))
    out.raw[a.code][b.code] = out.raw[b.code][a.code] = raw
    out.sailed[a.code][b.code] = out.sailed[b.code][a.code] = sailed
  }
  if (i % 40 === 0) console.log(`  ${i + 1}/${places.length} places, ${Math.round((Date.now() - t0) / 1000)} s`)
}
writeFileSync(outFile, JSON.stringify(out))

const pct = (xs, q) => (xs.length ? xs[Math.min(xs.length - 1, Math.floor(q * xs.length))] : 0)
const haulSql = `select port_id::text || ':' || good_id::text as k, haul_nm::float8 as nm, haul::float8 as haul from world.haul_rows()`
const base = new Map((await db.query(haulSql)).rows.map((r) => [r.k, r]))
for (const kind of ['raw', 'sailed']) {
  // the distances
  let n = 0
  let moved = 0
  const rel = []
  let worst = { d: 0 }
  for (const a of places) {
    for (const b of places) {
      if (a.code >= b.code) continue
      n++
      const was = Number(a.reaches[b.code])
      const now = out[kind][a.code][b.code]
      if (was === now) continue
      moved++
      const d = (now - was) / was
      rel.push(Math.abs(d))
      if (Math.abs(d) > Math.abs(worst.d)) worst = { d, k: `${a.code}-${b.code}`, was, now }
    }
  }
  rel.sort((x, y) => x - y)
  console.log(`${kind}: ${moved} of ${n} pairs' distances move; |change| median ${(pct(rel, 0.5) * 100).toFixed(2)} %, p95 ${(pct(rel, 0.95) * 100).toFixed(2)} %, p99 ${(pct(rel, 0.99) * 100).toFixed(2)} %; over 1 %: ${rel.filter((x) => x > 0.01).length}, over 5 %: ${rel.filter((x) => x > 0.05).length}; largest ${worst.k} ${worst.was} -> ${worst.now}`)
  // the prices: every market row's haul (a multiplier on its price), before and after
  await db.exec('begin')
  await db.query(`update public.sea_reaches sr set reaches = v.value from jsonb_each($1::jsonb) v where v.key = sr.code`, [JSON.stringify(out[kind])])
  const after = (await db.query(haulSql)).rows
  await db.exec('rollback')
  let nmMoved = 0
  let haulMoved = 0
  const dp = []
  let w = { d: 0 }
  for (const r of after) {
    const o = base.get(r.k)
    if (o.nm !== r.nm) nmMoved++
    if (o.haul !== r.haul) {
      haulMoved++
      const d = r.haul / o.haul - 1
      dp.push(Math.abs(d))
      if (Math.abs(d) > Math.abs(w.d)) w = { d, was: o.haul, now: r.haul, nm0: o.nm, nm1: r.nm }
    }
  }
  dp.sort((x, y) => x - y)
  console.log(`${kind}: of ${after.length} market rows, ${nmMoved} change their haul distance and ${haulMoved} their price multiplier; |price change| on those: median ${(pct(dp, 0.5) * 100).toFixed(3)} %, p95 ${(pct(dp, 0.95) * 100).toFixed(3)} %, p99 ${(pct(dp, 0.99) * 100).toFixed(3)} %, largest ${(w.d * 100).toFixed(2)} % (multiplier ${w.was} -> ${w.now}, haul ${w.nm0} -> ${w.nm1} nm); over 1 %: ${dp.filter((x) => x > 0.01).length}, over 2 %: ${dp.filter((x) => x > 0.02).length}`)
}
await db.close()
