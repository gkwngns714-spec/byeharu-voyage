// dice.mjs - THE ATTACK'S PROOFS AND SPECS UNDER MANY WORLDS' DICE. LOCAL ONLY (it builds and writes throwaway PGlite worlds; it never opens a network connection).
//
// Why: migration 0031 gives every built world its own `world_secret`, and every roll of a fight is keyed by it. A check that holds on one desk's cached world can be red on
// CI's (docs/dev-log/2026-11-12-live-rounds.md). So nothing that checks an attack may assume how a fight goes. This runs them under N other secrets and prints a line a run:
//   proofs   scripts/db/proofs 74 (and 34, 40, which 0374 touched) through attacks/run.mjs --dice (the secret rewritten as the first statement of each proof's transaction)
//   rpc      tests/rpc.battle.spec.ts, tests/rpc.attack.spec.ts, tests/rpc.fights.spec.ts with SPEC_WORLD_SECRET (rpc.battle and rpc.fights rewrite their own world's secret; rpc.attack fights no real fight)
//   browser  tests/battle.live.spec.ts with SPEC_WORLD_SECRET (tests/battleWorld.fixture.ts rewrites the secret of the copy it patches); only with --browser, and it needs
//            a build served: npm run build && npx vite preview --port 4422, PLAYWRIGHT_BASE_URL=http://localhost:4422/byeharu-voyage/
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/dice.mjs [N=10] [--browser] [--proofs=74,34,40]
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..')
const n = Number(process.argv.slice(2).find((a) => /^\d+$/.test(a)) ?? 10)
const browser = process.argv.includes('--browser')
const proofs = process.argv.find((a) => a.startsWith('--proofs='))?.slice(9) ?? '74,34,40'

function run(cmd, args, env) {
  try {
    return { ok: true, out: execFileSync(cmd, args, { cwd: ROOT, env: { ...process.env, ...env }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: process.platform === 'win32', maxBuffer: 64 * 1024 * 1024 }) }
  } catch (e) {
    return { ok: false, out: `${e.stdout ?? ''}\n${e.stderr ?? ''}` }
  }
}
const last = (out, re) => (out.match(re) ?? []).pop() ?? ''

let bad = 0
// the proofs: one restore of the cached world, N secrets, each proof in its own rolled-back transaction
const p = run('node', ['scripts/ops/harness/attacks/run.mjs', `--proofs=${proofs}`, `--dice=${n}`], {})
console.log(p.out.split('\n').filter((l) => / \| /.test(l)).join('\n'))
if (!p.ok) bad += 1
for (let i = 1; i <= n; i++) {
  const secret = `dice-${i}-${randomBytes(32).toString('hex')}`   // 0031: a secret is at least 64 characters
  const rpc = run('npx', ['playwright', 'test', 'tests/rpc.battle.spec.ts', 'tests/rpc.attack.spec.ts', 'tests/rpc.fights.spec.ts', '--reporter=line', '--trace=off'], { SPEC_WORLD_SECRET: secret })
  const web = browser ? run('npx', ['playwright', 'test', 'tests/battle.live.spec.ts', '--reporter=line', '--trace=off', '--workers=2'], { SPEC_WORLD_SECRET: secret }) : null
  const line = [
    `${String(i).padStart(2)} ${secret}`,
    `rpc ${rpc.ok ? last(rpc.out, /\d+ passed/g) : `RED ${last(rpc.out, /\d+ failed[^\n]*/g)}`}`,
    web ? `browser ${web.ok ? last(web.out, /\d+ passed/g) : `RED ${last(web.out, /\d+ failed[^\n]*/g)}`}` : null,
  ].filter(Boolean)
  console.log(line.join(' | '))
  if (!rpc.ok || (web && !web.ok)) {
    bad += 1
    console.log([rpc, web].filter((r) => r && !r.ok).map((r) => r.out.split('\n').filter((l) => /Error|FAIL|expect|Received|Expected|›|console, in error/.test(l)).slice(0, 16).join('\n')).join('\n'))
  }
}
console.log(bad === 0 ? `all ${n} worlds green` : `${bad} run(s) RED`)
process.exit(bad === 0 ? 0 : 1)
