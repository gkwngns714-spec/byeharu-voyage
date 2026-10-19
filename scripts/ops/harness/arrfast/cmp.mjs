// cmp.mjs <a.json> ... — one line per arm: sweeps, last 10 min, laps ≤ 0, lay-ups at the end; then, for
// every arm after the first, how many of the kickoff's plans (sim.mjs plans_after_kick: each merchant's
// stops, lines and pause) differ from the first arm's.
import { readFileSync } from 'node:fs'
const arms = process.argv.slice(2).map((f) => [f, JSON.parse(readFileSync(f, 'utf8'))])
for (const [f, o] of arms) {
  const l = o.laps
  console.log(f.split('/').pop().padEnd(14), 'kick', o.kick_ms, '| sweeps', o.sweeps.n, 'avg', o.sweeps.avg, 'p95', o.sweeps.p95,
    '| last10 avg', o.sweeps_after_10.avg, 'p95', o.sweeps_after_10.p95,
    '| laps', l.n, 'le0', l.le0, (100 * l.le0 / l.n).toFixed(0) + '%', 'median', l.median_net, 'sum', l.sum_net, 'le0_sold0', l.le0_sold0,
    '| laid end', o.end.paused?.laid_up, 'sailing', o.end.sailing, '| money m', o.money.merchants, 'c', o.money.cities, '| recon', JSON.stringify(o.reconcile_ms))
}
const [f0, a0] = arms[0]
for (const [f, o] of arms.slice(1)) {
  if (!a0.plans_after_kick || !o.plans_after_kick) { console.log('plans: not recorded in', a0.plans_after_kick ? f : f0); continue }
  const keys = new Set([...Object.keys(a0.plans_after_kick), ...Object.keys(o.plans_after_kick)])
  const diff = [...keys].filter((k) => a0.plans_after_kick[k] !== o.plans_after_kick[k])
  console.log(`plans after the kickoff, ${f.split('/').pop()} against ${f0.split('/').pop()}: ${keys.size - diff.length} of ${keys.size} identical`,
    diff.length ? `— differ: ${diff.slice(0, 10).join(', ')}` : '')
}
