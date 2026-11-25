// WHAT THE BUY TAX (0507) DOES TO PASSIVE NEAR JOBS. Local PGlite only; everything is rolled back.
//   BV_CACHE_DIR=<a private dir> node scripts/ops/harness/buy-tax/measure.mjs
// A fresh company (one Barca) at each home, with 40,000 and 200,000 coin: every near fixed run world.actions offers (a cycle under an hour),
// its served coin an hour (public.run_day with jobs_wait_enabled: the day's gaining runs, 0498), read in one instant under no tax, a tenth of
// the city's rate as it is (half at home: 0505), a tenth of it everywhere (no home half), and a flat 3 % (a mayor's 30 %).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const files = []
for (const name of await migrationFiles()) files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: process.env.BV_CACHE_DIR, log: () => {}, required: true, snapshots: true })
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
const HOMES = [['PRT', 'LIS'], ['NLD', 'AMS'], ['VEN', 'VEN'], ['GEN', 'GOA'], ['JPN', 'NAG']]
const knob = (k, v) => db.query(`update public.world_config set value = $2::jsonb where key = $1`, [k, JSON.stringify(v)])
const CASES = [
  ['none', { buy_tax_enabled: false, tax_thirty_enabled: false }],
  ['city, half at home', { buy_tax_enabled: true, tax_thirty_enabled: true }],
  ['city', { buy_tax_enabled: true, tax_thirty_enabled: false }],
  ['flat 3 %', { buy_tax_enabled: true, tax_thirty_enabled: false, buy_tax_share: 1000 }],
]
console.log('| Home | Purse | Run | Rate at home | No tax | City rate, half at home | City rate | Flat 3 % |\n|---|---|---|---|---|---|---|---|')
let seq = 0
for (const [nation, port] of HOMES)
  for (const purse of [40000, 200000]) {
    await db.exec('begin')
    try {
      await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'jobs_wait_enabled', 'city_treasury_enabled')`)
      seq += 1
      const auth = `00000000-0507-4000-8000-${String(seq).padStart(12, '0')}`
      const a = (await one(`select public.new_house($1, $2, $3, $4) as id`, [auth, `Casa do Imposto ${seq}`, nation, port])).id
      const f = (await one(`select id from public.fleets where player_id = $1`, [a])).id
      await db.query(`update public.players set ducats = $2 where id = $1`, [a, purse])
      await db.query(`select cmd.assume_identity($1)`, [auth])
      const got = {}
      let rate = null
      for (const [name, set] of CASES) {
        for (const [k, v] of Object.entries(set)) await knob(k, v)
        const acts = (await one(`select world.actions('fleet:' || $1) as j`, [f])).j
        got[name] = Object.fromEntries((acts.options ?? []).filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'sell' && o.interval_s < 3600).map((o) => [o.id, o]))
        if (name === 'city') rate = Number((await one(`select public.buy_tax_rate($1, (select port_id from public.fleets where id = $1)) as r`, [f])).r)
      }
      await knob('buy_tax_share', 0.1)
      const ids = Object.entries(got.none).sort((x, y) => y[1].per_hour - x[1].per_hour).slice(0, 4)
      for (const [id] of ids)
        console.log(`| ${port} | ${purse} | ${id.split(':').slice(2, 5).join(' ')} | ${(rate * 100).toFixed(2)} % | ${CASES.map(([n]) => (got[n][id] ? `${Math.round(got[n][id].per_hour)}/h` : 'not offered')).join(' | ')} |`)
      if (!ids.length) console.log(`| ${port} | ${purse} | none offered | | | | | |`)
    } catch (e) {
      console.log(`| ${port} | ${purse} | ERROR ${e.message.slice(0, 120)} |`)
    }
    await db.exec('rollback')
  }
await db.close()
process.exit(0)
