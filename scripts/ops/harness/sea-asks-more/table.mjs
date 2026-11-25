// THE PROVEN TABLE OF sea-asks-more (0525): which hulls meet each ask, and which harbours close at it. LOCAL WORLD IMAGE ONLY:
//   node scripts/ops/harness/sea-asks-more/table.mjs <image .tgz of a chain with 0525> [--harbours]
// A hull "holds the way" when her wave resistance, with the same kit, is the one the way to that sea asks. A kit is any pieces of the
// ordinary (meta 0) gear up to a grade, in her class's own Mid and Low slots, within her deck and hands (crew_max - half her minimum,
// as world.ship_budget at no skill). No refit, perk, set, skill or wear. Harbours closed: the ones no chain of harbour-to-harbour
// courses (public.sea_leg_asks) reaches from Lisbon once the seas of the ask are shut, at that rung.
import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'
const db = await PGlite.create({ loadDataDir: new Blob([await readFile(process.argv[2])]) })
const q = async (s) => (await db.query(s)).rows
const slots = (r) => `coalesce((select sum(s.count) from public.class_slots s where s.class_code = c.code and s.slot = '${r}'), 0)::int as ${r}`
const hulls = await q(`select c.code, c.wave, c.crew_max - (c.crew_required + 1) / 2 as hands, p.deck, k.ice, k.current, k.light, p.size, c.rig, ${slots('mid')}, ${slots('low')}
  from public.ship_classes c join public.class_profile p on p.class_code = c.code join public.sea_stats_class k on k.class_code = c.code order by c.code`)
const fig = (s) => `coalesce((select i.delta from public.sea_stats_item i where i.item_code = ip.item_code and i.stat = '${s}'), 0) as ${s}`
const items = await q(`select ip.item_code as code, ip.rack, ip.grade, ip.deck, ip.hands, coalesce((select e.delta from public.item_effects e
  where e.item_code = ip.item_code and e.stat = 'wave'), 0)::int as wave, ${fig('ice')}, ${fig('current')}, ${fig('light')}
  from public.item_profile ip where ip.rack in ('mid', 'low') and ip.meta = 0 and not exists (select 1 from public.item_unmade u where u.item_code = ip.item_code) order by 1`)

function best(h, stat, wave, grade) {
  if (grade === 0) return h.wave >= wave ? h[stat] : null
  let st = [[0, 0, Math.min(wave, h.wave), h[stat]]]
  for (const rack of ['mid', 'low']) {
    const its = items.filter((i) => i.rack === rack && i.grade <= grade && (i[stat] > 0 || i.wave > 0))
    const beats = (j, i) => j.deck <= i.deck && j.hands <= i.hands && j[stat] >= i[stat] && j.wave >= i.wave
    const keep = its.filter((i, n) => !its.some((j, m) => m !== n && beats(j, i) && (!beats(i, j) || m < n)))
    for (let k = 0; k < h[rack]; k++) {
      const next = [...st]
      for (const [d, n, w, v] of st)
        for (const i of keep) if (d + i.deck <= h.deck && n + i.hands <= h.hands) next.push([d + i.deck, n + i.hands, Math.min(wave, w + i.wave), v + i[stat]])
      next.sort((a, b) => a[0] - b[0] || a[1] - b[1] || b[2] - a[2] || b[3] - a[3])
      st = []
      for (const x of next) if (!st.some((y) => y[0] <= x[0] && y[1] <= x[1] && y[2] >= x[2] && y[3] >= x[3])) st.push(x)
    }
  }
  const ok = st.filter((x) => x[2] >= wave).map((x) => x[3])
  return ok.length ? Math.max(...ok) : null
}

const legs = await q(`select a.code as a, b.code as b, s.zones || own.zones as z from public.sea_leg_asks s join public.ports a on a.id = s.from_port
  join public.ports b on b.id = s.to_port join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port`)
const level = Object.fromEntries((await q(`select code, title_min from public.sea_zones`)).map((z) => [z.code, z.title_min]))
const out = new Map()
for (const l of legs) {
  if (!out.has(l.a)) out.set(l.a, [])
  out.get(l.a).push(l)
}
const reach = (rung, shut) => {
  const seen = new Set(['LIS'])
  const todo = ['LIS']
  while (todo.length) for (const l of out.get(todo.pop())) if (!seen.has(l.b) && l.z.every((x) => level[x] <= rung && !shut.includes(x))) { seen.add(l.b); todo.push(l.b) }
  return seen
}
const ASKS = [
  ['Ice', 'ice', ['ARC'], 20, 8, [50]],
  ['Ice, a later polar way', 'ice', ['ARC'], 70, 8, [70]],
  ['Current, the Cape', 'current', ['SOU-CAPE'], 44, 2, [16, 20]],
  ['Current, the Kuroshio', 'current', ['PHI-JP'], 44, 6, [25]],
  ['Current, open Pacific', 'current', ['NRT-OPEN', 'STH-OPEN'], 70, 8, [50]],
  ['Light wind, the Doldrums', 'light', ['NOR-DOL'], 24, 4, [20]],
  ['Light wind, Indian Ocean crossing', 'light', ['IND-E'], 44, 5, [20]],
  ['Light wind, Philippine Sea', 'light', ['PHI'], 50, 8, [35]],
]
for (const [name, stat, zones, wave, rung, asks] of ASKS) {
  const lost = (r) => { const b = reach(r, zones); return [...reach(r, [])].filter((x) => !b.has(x)).sort() }
  console.log(`\n${name} (${zones.join(' ')}), wave ${wave}: harbours shut when it is, rung 2 to 8: ${[2, 3, 4, 5, 6, 7, 8].map((r) => lost(r).length).join(' ')}${lost(8).length < 30 ? ' (at 8: ' + lost(8).join(' ') + ')' : ''}; own rung ${rung}`)
  for (const g of [0, 1, 2, 3, 5]) {
    const v = hulls.map((h) => best(h, stat, wave, g)).filter((x) => x !== null).sort((a, b) => a - b)
    console.log(`  grade ${g}: ${v.length} hulls hold the wave; least ${v[0]}, quarter ${v[v.length >> 2]}, middle ${v[v.length >> 1]}, most ${v[v.length - 1]}; ${asks.map((a) => `${a} met by ${v.filter((x) => x >= a).length}`).join(', ')}`)
  }
}
if (process.argv.includes('--harbours')) {
  // harbour by harbour: the least figure each needs for some way to it at its own rung, were the asks of 3.2 set (0: a way round every such sea)
  const P = { ice: { ARC: 50 }, current: { 'SOU-CAPE': 20, 'PHI-JP': 25, 'NRT-OPEN': 50, 'STH-OPEN': 50 }, light: { 'NOR-DOL': 20, 'IND-E': 20, PHI: 35 } }
  const own = Object.fromEntries((await q(`select p.code, o.zones[1] as z from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id where p.kind = 'HARBOUR'`)).map((r) => [r.code, r.z]))
  const memo = new Map()
  const at = (r, z) => { const k = r + z.join(); if (!memo.has(k)) memo.set(k, reach(r, z)); return memo.get(k) }
  const sum = {}
  for (const code of Object.keys(own).sort()) {
    const rung = level[own[code]]
    const need = {}
    for (const [stat, asks] of Object.entries(P)) need[stat] = [0, ...new Set(Object.values(asks))].sort((a, b) => a - b).find((f) => at(rung, Object.keys(asks).filter((z) => asks[z] > f)).has(code))
    console.log(code, own[code], `rung ${rung} ice ${need.ice} current ${need.current} light ${need.light}`)
    const k = `rung ${rung}: ice ${need.ice} current ${need.current} light ${need.light}`
    sum[k] = (sum[k] ?? 0) + 1
  }
  console.log(sum)
}
process.exit(0)
