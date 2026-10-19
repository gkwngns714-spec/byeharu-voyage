// kick2.mjs <image> <migration|-> — prod-shaped world, KNOBS env applied after prod's, then the kickoff (837 lap-start plans): who waits
import { open, setup, log, shapeSql } from './setup.mjs'
const [image, mig] = process.argv.slice(2)
const db = await open(image, mig && mig !== '-' ? [mig] : [])
const q = await setup(db, false)
for (const kv of (process.env.KNOBS ?? '').split(',').filter(Boolean)) { const [k, v] = kv.split('='); await q(`update public.world_config set value = to_jsonb(${Number(v)}) where key = '${k}'`); log('knob', k, v) }
const t0 = Date.now()
await q(`select count(cmd.advance(nf.fleet_id, now())) n from public.npc_fleets nf`)
const sh = (await q(shapeSql))[0].j
const buys = (await q(`select json_build_object('routes_with_buy', count(distinct l.route_id), 'buy_lines', count(*)) j from public.standing_route_lines l join public.npc_fleets nf on nf.route_id = l.route_id where l.kind = 'BUY'`))[0].j
log(JSON.stringify({ knobs: process.env.KNOBS ?? '', kick_ms: Date.now() - t0, ...sh, ...buys }))
process.exit(0)
