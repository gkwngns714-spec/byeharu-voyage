// shadow.mjs <world> <minutes> <migration> — the 0209 arm with a SHADOW: every leg any plan prices during the
// kickoff and the sweeps is priced by the new body AND the pre-image in the same state; mismatches are counted.
import { readFileSync } from 'node:fs'
import { open, setup, log } from './setup.mjs'
const [image, mins, mig] = process.argv.slice(2)
const db = await open(image, [])
const q = await setup(db, false)
await db.exec(readFileSync(mig, 'utf8').replace(/\r\n/g, '\n'))
await db.exec(`
create table public.shadow_0209(n int, bad int, buys int);
insert into public.shadow_0209 values (0, 0, 0);
alter function public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric) rename to npc_leg_lines_new_0209;
create function public.npc_leg_lines(p_route uuid, p_from uuid, p_to uuid, p_hold numeric, p_crew integer, p_speed numeric)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $f$
declare a jsonb; b jsonb;
begin
  a := pg_temp.npc_leg_lines_old_0209(p_route, p_from, p_to, p_hold, p_crew, p_speed);
  b := public.npc_leg_lines_new_0209(p_route, p_from, p_to, p_hold, p_crew, p_speed);
  update public.shadow_0209 set n = n + 1, bad = bad + (a is distinct from b)::int, buys = buys + coalesce((b->>'any')::boolean, false)::int;
  return b;
end $f$;`)
const t0 = Date.now()
await q(`select count(cmd.advance(nf.fleet_id, now())) n from public.npc_fleets nf`)
log('kickoff', Date.now() - t0, 'ms', JSON.stringify((await q(`select * from public.shadow_0209`))[0]))
const end = Date.now() + Number(mins) * 60_000
let nextDrift = Date.now() + 600_000, s = 0
while (Date.now() < end) {
  const s0 = Date.now(); await q(`select public.tick_arrivals(now())`); s++
  if (Date.now() >= nextDrift) { await db.exec(`call public.tick_market_drift_each_port()`); nextDrift += 600_000 }
  const w = 15_000 - (Date.now() - s0); if (w > 0) await new Promise((r) => setTimeout(r, w))
}
log('sweeps', s, JSON.stringify((await q(`select * from public.shadow_0209`))[0]))
process.exit(0)
