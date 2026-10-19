import { open, setup, log } from './setup.mjs'
import { readFileSync } from 'node:fs'
const db = await open(process.argv[2], [])
const q = async (s, p) => (await db.query(s, p)).rows
const st = JSON.parse(readFileSync('C:/Users/gkwng/dev/bv-harness/redesign-scratch/prod-state.json', 'utf8')).rows[0].json_build_object
await db.query(`create temp table ps2(h text, f text, s text, c text)`)
for (const r of st.ships2) await db.query(`insert into ps2 values ($1,$2,$3,$4)`, r)
console.log(JSON.stringify((await q(`select json_build_object(
  'prod_fleets', (select count(distinct (h,f)) from ps2),
  'img_fleets', (select count(*) from public.npc_fleets),
  'matched_fleets', (select count(*) from public.npc_fleets nf join public.fleets f on f.id=nf.fleet_id join public.players pl on pl.id=nf.player_id where exists (select 1 from ps2 where ps2.h=pl.company_name and ps2.f=f.name)),
  'ship_diff', (select count(*) from ((select h,f,c from ps2 except all select pl.company_name, f.name, c.code from public.npc_fleets nf join public.fleets f on f.id=nf.fleet_id join public.players pl on pl.id=nf.player_id join public.ships s on s.fleet_id=f.id join public.ship_classes c on c.id=s.class_id)
     union all (select pl.company_name, f.name, c.code from public.npc_fleets nf join public.fleets f on f.id=nf.fleet_id join public.players pl on pl.id=nf.player_id join public.ships s on s.fleet_id=f.id join public.ship_classes c on c.id=s.class_id except all select h,f,c from ps2)) z)) j`))[0].j))
process.exit(0)
