// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BALANCE SWEEP — try knob settings against the real economy and print what each one pays.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Balance is measured, never argued. This applies the chain ONCE, then for each candidate setting
// of the four affinity knobs it re-derives all 14,980 affinities through `world.affinity_for()` —
// the same function the seed uses, so the sweep cannot drift from the game — and replays the best
// opening voyage from a sample of ports.
//
// What is being tuned: how much a first voyage pays. Too little and there is no game; too much and
// the purse doubles before the player has learned the map. The band this aims at is stated in the
// self-assert at the foot of migration 0005.
//
// Run: node scripts/db/tune-balance.mjs
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { applyChain } from './apply-chain.mjs'

const CANDIDATES = [
  { producer: 0.60, home: 0.85, span: 1.50, reach: 6000, curve: 1.0 },   // what shipped: 32% median
  { producer: 0.88, home: 0.97, span: 0.90, reach: 8000, curve: 0.70 },
  { producer: 0.90, home: 0.98, span: 0.88, reach: 8000, curve: 0.75 },
  { producer: 0.90, home: 0.99, span: 0.85, reach: 9000, curve: 0.80 },
  { producer: 0.92, home: 0.99, span: 0.85, reach: 9000, curve: 0.80 },
  { producer: 0.92, home: 1.00, span: 0.80, reach: 9000, curve: 0.85 },
]

const SAMPLE = Number(process.env.SAMPLE ?? 14)

const { db } = await applyChain({ quiet: true, log: () => {} })

const { rows: ports } = await db.query(
  `select id, code, name, culture, size_tier from public.ports order by size_tier desc, code limit $1`,
  [SAMPLE],
)

// One house per sample port, founded once and reused across every candidate: founding is the slow
// part, and the purse is reset between runs so each setting is judged from the same standing start.
const houses = []
for (const port of ports) {
  const hex = [...port.code].map((ch) => ch.charCodeAt(0).toString(16)).join('')
  const uid = `00000000-0000-4000-9000-${hex.padStart(12, '0').slice(-12)}`
  await db.query(`select public.new_house($1::uuid, $2, 'PRT')`, [uid, `Casa ${port.code}`])
  const { rows: [h] } = await db.query(
    `select p.id as player_id, f.id as fleet_id from public.players p
       join public.fleets f on f.player_id = p.id where p.auth_uid = $1`,
    [uid],
  )
  await db.query(`update public.fleets set port_id = $2 where id = $1`, [h.fleet_id, port.id])
  await db.query(`select cmd.assume_identity($1::uuid)`, [uid])
  await db.query(`select cmd.do_provision($1::uuid, '{"mode":"FULL"}'::jsonb)`, [h.fleet_id])
  await db.query(
    `select cmd.do_hire($1::uuid, jsonb_build_object('count',
       (select c.crew_max - s.crew from public.ships s
          join public.ship_classes c on c.id = s.class_id where s.fleet_id = $1::uuid)))`,
    [h.fleet_id],
  )
  const { rows: [ship] } = await db.query(
    `select c.hold, s.water_t, s.food_t from public.ships s
       join public.ship_classes c on c.id = s.class_id where s.fleet_id = $1`,
    [h.fleet_id],
  )
  const { rows: [purse] } = await db.query(`select ducats from public.players where id = $1`, [h.player_id])
  houses.push({
    port,
    ...h,
    free: Number(ship.hold) - Number(ship.water_t) - Number(ship.food_t),
    stake: Number(purse.ducats),
  })
}

async function retune({ producer, home, span, reach, curve }) {
  await db.query(
    `update public.world_config set value = to_jsonb($1::numeric) where key = 'affinity_producer'`, [producer])
  await db.query(
    `update public.world_config set value = to_jsonb($1::numeric) where key = 'affinity_home'`, [home])
  await db.query(
    `update public.world_config set value = to_jsonb($1::numeric) where key = 'affinity_span'`, [span])
  await db.query(
    `update public.world_config set value = to_jsonb($1::numeric) where key = 'affinity_reach_nm'`, [reach])
  await db.query(
    `update public.world_config set value = to_jsonb($1::numeric) where key = 'affinity_curve'`, [curve])
  // The SAME function the seed used, so the sweep measures the game and not a copy of it.
  await db.query(
    `update public.port_goods pg
        set affinity = world.affinity_for(pg.port_id, pg.good_id),
            drift = 0`)
  await db.query(
    `update public.port_goods pg
        set stock_target = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))),
            stock        = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity)))
       from public.ports p where p.id = pg.port_id`)
}

async function bestVoyage(house) {
  const { rows: options } = await db.query(
    `select g.id as good_id, g.code as good, g.bulk, d.id as dest_id, l.distance_nm
       from public.legs l
       join public.ports d
         on d.id = case when l.from_port_id = $1 then l.to_port_id else l.from_port_id end
       join public.goods g on true
       join public.port_goods pg_home on pg_home.port_id = $1 and pg_home.good_id = g.id
       join public.port_goods pg_away on pg_away.port_id = d.id and pg_away.good_id = g.id
      where (l.from_port_id = $1 or l.to_port_id = $1)
        and not (d.culture = any(g.culture_mask))
        and not ($2::text = any(g.culture_mask))
      order by pg_away.affinity - pg_home.affinity desc
      limit 40`,
    [house.port.id, house.port.culture],
  )

  let best = null
  for (const o of options) {
    const room = Math.floor(house.free / Number(o.bulk))
    if (room < 1) continue
    let qty = room
    let buy = null
    while (qty >= 1) {
      const { rows: [q] } = await db.query(
        `select units, total from world.quote($1::uuid, $2::uuid, $3::numeric, 'buy')`,
        [house.port.id, o.good_id, qty],
      )
      if (Number(q.units) > 0 && Number(q.total) <= house.stake) { buy = q; break }
      qty = Math.floor(qty / 2)
    }
    if (!buy) continue
    const { rows: [sell] } = await db.query(
      `select units, total from world.quote($1::uuid, $2::uuid, $3::numeric, 'sell')`,
      [o.dest_id, o.good_id, buy.units],
    )
    const pct = ((Number(sell.total) - Number(buy.total)) / house.stake) * 100
    if (!best || pct > best.pct) best = { pct, good: o.good, nm: Number(o.distance_nm) }
  }
  return best
}

console.log('\nknobs                                 median   p25    p75    worst   best   (return on the stake)')
for (const c of CANDIDATES) {
  await retune(c)
  const pcts = []
  for (const h of houses) {
    const b = await bestVoyage(h)
    if (b) pcts.push(b.pct)
  }
  pcts.sort((a, b) => a - b)
  const at = (q) => pcts[Math.min(pcts.length - 1, Math.floor(q * pcts.length))]
  console.log(
    `prod ${c.producer.toFixed(2)} home ${c.home.toFixed(2)} span ${c.span.toFixed(2)} reach ${String(c.reach).padStart(4)} curve ${c.curve.toFixed(2)}  ` +
      `${at(0.5).toFixed(1).padStart(6)}% ${at(0.25).toFixed(1).padStart(5)}% ${at(0.75).toFixed(1).padStart(5)}% ` +
      `${pcts[0].toFixed(1).padStart(6)}% ${pcts[pcts.length - 1].toFixed(1).padStart(6)}%`,
  )
}

await db.close()
