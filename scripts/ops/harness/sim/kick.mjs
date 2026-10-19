// kick.mjs <image> [newcand] — prod-shaped world, every merchant at her lap start: the kickoff (cmd.advance each = npc_plan) timed; who waits
import { readFileSync } from 'node:fs'
import { open, setup, log, shapeSql } from './setup.mjs'
const [image, nc, ...migs] = process.argv.slice(2)
const db = await open(image, migs)
if (nc && nc !== '-') { await db.query(`insert into public.world_config (key, value, description) values ('npc_route_trade_candidates', to_jsonb(${Number(nc)}), 'sim') on conflict (key) do update set value = excluded.value`); await db.exec(readFileSync('C:/Users/gkwng/dev/bv-harness/redesign-scratch/new_npc_loop_candidates.sql', 'utf8')); log('new candidates', nc) }
const q = await setup(db, true)
log(JSON.stringify((await q(shapeSql))[0].j))
process.exit(0)
