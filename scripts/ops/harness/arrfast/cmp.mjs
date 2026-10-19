// cmp.mjs <a.json> ... — one line per arm: sweeps, last 10 min, laps ≤ 0, lay-ups at the end
import { readFileSync } from 'node:fs'
for (const f of process.argv.slice(2)) {
  const o = JSON.parse(readFileSync(f, 'utf8'))
  const l = o.laps
  console.log(f.split('/').pop().padEnd(14), 'kick', o.kick_ms, '| sweeps', o.sweeps.n, 'avg', o.sweeps.avg, 'p95', o.sweeps.p95,
    '| last10 avg', o.sweeps_after_10.avg, 'p95', o.sweeps_after_10.p95,
    '| laps', l.n, 'le0', l.le0, (100 * l.le0 / l.n).toFixed(0) + '%', 'median', l.median_net, 'sum', l.sum_net, 'le0_sold0', l.le0_sold0,
    '| laid end', o.end.paused?.laid_up, 'sailing', o.end.sailing, '| money m', o.money.merchants, 'c', o.money.cities, '| recon', JSON.stringify(o.reconcile_ms))
}
