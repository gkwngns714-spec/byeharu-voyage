// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT DOES A FIRST VOYAGE PAY? — measured, over the whole world, not argued.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The opening session currently returns about 35% on the stake in ~25 real minutes, which is not a
// trading game, it is a money printer. But "too generous" is a number, and a number has to be
// measured before it can be tuned — over many starting ports, not the one the proof happens to use.
//
// For each sample port this plays the real thing through the real functions: found a house there,
// water and crew her, then for every good the port sells and every port one leg away, buy what a
// Barca can carry and afford, sail, sell, and record the return on the stake. No shortcuts through
// the pricing: world.quote() prices every step exactly as a committed trade would.
//
// Run: node scripts/db/measure-first-voyage.mjs [sampleSize]
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { applyChain } from './apply-chain.mjs'

const SAMPLE = Number(process.argv[2] ?? 24)

const { db } = await applyChain({ quiet: true, log: () => {} })

// A spread of starting ports: the great entrepôts and a tail of ordinary harbours, deterministic
// so two runs of this script are comparable.
const { rows: ports } = await db.query(
  `select id, code, name, size_tier from public.ports
    order by size_tier desc, code
    limit $1`,
  [SAMPLE],
)

const results = []

for (const port of ports) {
  // A uuid must be hex, and a port code is letters — so the code's character codes make the tail.
  const hex = [...port.code].map((ch) => ch.charCodeAt(0).toString(16)).join('')
  const uid = `00000000-0000-4000-9000-${hex.padStart(12, '0').slice(-12)}`
  // new_house() founds at the nation's capital, so the fleet is moved to the port under test —
  // this measures the WORLD's gradients, not Lisbon's.
  await db.query(`select public.new_house($1::uuid, $2, 'PRT')`, [uid, `Casa ${port.code}`])
  await db.query(
    `update public.fleets set port_id = $2
      where player_id = (select id from public.players where auth_uid = $1)`,
    [uid, port.id],
  )

  const { rows: [house] } = await db.query(
    `select p.id as player_id, p.ducats, f.id as fleet_id
       from public.players p join public.fleets f on f.player_id = p.id
      where p.auth_uid = $1`,
    [uid],
  )
  if (!house) continue

  // Water her and sign a full crew, as a captain would before any real voyage.
  await db.query(`select cmd.assume_identity($1::uuid)`, [uid])
  await db.query(`select cmd.do_provision($1::uuid, '{"mode":"FULL"}'::jsonb)`, [house.fleet_id])
  await db.query(
    `select cmd.do_hire($1::uuid, jsonb_build_object('count',
        (select c.crew_max - s.crew from public.ships s
           join public.ship_classes c on c.id = s.class_id where s.fleet_id = $1::uuid)))`,
    [house.fleet_id],
  )

  const { rows: [after] } = await db.query(`select ducats from public.players where id = $1`, [house.player_id])
  const stake = Number(after.ducats)

  // Every (good, neighbour) pair this port offers, priced for real. 0039: the neighbourhood is
  // the same 600 nm of SAILED water proofs 04/05 measure, from the honest reach table.
  const { rows: options } = await db.query(
    `select g.id as good_id, g.code as good, g.bulk, d.id as dest_id, d.code as dest, rf.nm as distance_nm
       from voyage.reach_from($1) rf
       join public.ports d on d.id = rf.port_id and d.kind = 'HARBOUR'
       join public.goods g on true
       join public.port_goods pg_home on pg_home.port_id = $1 and pg_home.good_id = g.id
       join public.port_goods pg_away on pg_away.port_id = d.id and pg_away.good_id = g.id
      where rf.nm <= 600
        and not (d.culture = any(g.culture_mask))
        and not ($2::text = any(g.culture_mask))
      order by pg_away.affinity - pg_home.affinity desc
      limit 60`,
    [port.id, (await db.query(`select culture from public.ports where id = $1`, [port.id])).rows[0].culture],
  )

  const { rows: [ship] } = await db.query(
    `select c.hold, s.water_t, s.food_t from public.ships s
       join public.ship_classes c on c.id = s.class_id where s.fleet_id = $1`,
    [house.fleet_id],
  )
  const free = Number(ship.hold) - Number(ship.water_t) - Number(ship.food_t)

  let best = null
  for (const o of options) {
    const room = Math.floor(free / Number(o.bulk))
    if (room < 1) continue
    // How many can she actually pay for, at the stepped price? Ask the pricing function itself.
    let qty = room
    let buy = null
    while (qty >= 1) {
      const { rows: [q] } = await db.query(
        `select units, total from world.quote($1::uuid, $2::uuid, $3::numeric, 'buy')`,
        [port.id, o.good_id, qty],
      )
      if (Number(q.units) > 0 && Number(q.total) <= stake) { buy = q; break }
      qty = Math.floor(qty / 2)
    }
    if (!buy || Number(buy.units) < 1) continue

    const { rows: [sell] } = await db.query(
      `select units, total from world.quote($1::uuid, $2::uuid, $3::numeric, 'sell')`,
      [o.dest_id, o.good_id, buy.units],
    )
    const gain = Number(sell.total) - Number(buy.total)
    const pct = (gain / stake) * 100
    if (!best || pct > best.pct) {
      best = { good: o.good, dest: o.dest, nm: Number(o.distance_nm), qty: Number(buy.units), spend: Number(buy.total), gain, pct }
    }
  }

  if (best) results.push({ port: port.name, code: port.code, tier: port.size_tier, stake, ...best })
}

results.sort((a, b) => b.pct - a.pct)

console.log('\nBEST ONE-LEG ROUND TRIP A STARTER CAN MAKE, per starting port')
console.log('(buy what she can carry and afford, sail one leg, sell — return on the stake)\n')
console.log('  port                 leg      cargo                qty   spent    gain     return')
for (const r of results) {
  console.log(
    `  ${r.port.padEnd(20)} ${String(Math.round(r.nm)).padStart(5)}nm  ${r.good.padEnd(18)} ` +
      `${String(r.qty).padStart(4)} ${String(Math.round(r.spend)).padStart(7)} ${String(Math.round(r.gain)).padStart(7)}  ${r.pct.toFixed(1).padStart(6)}%`,
  )
}
const pcts = results.map((r) => r.pct).sort((a, b) => a - b)
const at = (q) => pcts[Math.min(pcts.length - 1, Math.floor(q * pcts.length))]
console.log(
  `\n  ports ${results.length} · median ${at(0.5).toFixed(1)}% · p25 ${at(0.25).toFixed(1)}% · p75 ${at(0.75).toFixed(1)}% · ` +
    `worst ${pcts[0].toFixed(1)}% · best ${pcts[pcts.length - 1].toFixed(1)}%`,
)

await db.close()
