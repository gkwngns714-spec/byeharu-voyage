// 0364: THE SPECS AND THE PROOF UNDER MANY WORLDS' DICE. LOCAL ONLY (it builds and writes throwaway PGlite worlds; it never opens a network connection).
//
// Why: migration 0031 gives every built world its own `world_secret`, and every roll of a fight is keyed by it. A check that holds on one desk's cached world can
// be red on CI's (docs/dev-log/2026-11-12-live-rounds.md; and tests/rpc.fights.spec.ts on 2026-11-13). So nothing of 0364's checks may assume how a fight goes.
// This runs them under N other secrets, one after another, and prints a line a run:
//   proof    scripts/db/proofs/66_fight_rings.sql, with `world_secret` rewritten as its first statement (a temporary copy beside it, removed afterwards)
//   rpc      tests/rpc.fights.spec.ts with SPEC_WORLD_SECRET (the spec rewrites the secret of its own memory:// world)
//   browser  tests/map.fight.spec.ts with SPEC_WORLD_SECRET (the fixtures rewrite the secret of the copy they patch); only with --browser, and it needs a build
//            served: npm run build && npx vite preview --port 4414, PLAYWRIGHT_BASE_URL=http://localhost:4414/byeharu-voyage/
//
//   node scripts/ops/harness/fight-rings/dice.mjs [N=10] [--browser] [--grep="a playwright -g pattern for the browser spec"]
import { execFileSync } from 'node:child_process'
import { readFileSync, rmSync, writeFileSync } from 'node:fs'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..')
const n = Number(process.argv.slice(2).find((a) => /^\d+$/.test(a)) ?? 10)
const browser = process.argv.includes('--browser')
const grep = process.argv.find((a) => a.startsWith('--grep='))?.slice('--grep='.length)
const PROOF = path.join(ROOT, 'scripts', 'db', 'proofs', '66_fight_rings.sql')
const TMP = path.join(ROOT, 'scripts', 'db', 'proofs', '66_fight_rings_dice_tmp.sql')

function run(cmd, args, env) {
  try {
    return { ok: true, out: execFileSync(cmd, args, { cwd: ROOT, env: { ...process.env, ...env }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: process.platform === 'win32' }) }
  } catch (e) {
    return { ok: false, out: `${e.stdout ?? ''}\n${e.stderr ?? ''}` }
  }
}
const last = (out, re) => (out.match(re) ?? []).pop() ?? ''

let bad = 0
for (let i = 1; i <= n; i++) {
  const secret = `dice-${i}-${randomBytes(32).toString("hex")}`   // 0031: a secret is at least 64 characters
  const sql = readFileSync(PROOF, 'utf8')
  const at = sql.indexOf('\ndo $$')
  writeFileSync(TMP, `${sql.slice(0, at)}\nupdate public.world_config set value = to_jsonb('${secret}'::text) where key = 'world_secret';\n${sql.slice(at)}`)
  let proof
  try {
    proof = run('node', ['scripts/db/proof.mjs', '66_fight_rings_dice_tmp'])
  } finally {
    rmSync(TMP, { force: true })
  }
  const rpc = run('npx', ['playwright', 'test', 'tests/rpc.fights.spec.ts', '--reporter=line'], { SPEC_WORLD_SECRET: secret })
  const web = browser
    ? run('npx', ['playwright', 'test', 'tests/map.fight.spec.ts', '--reporter=line', '--workers=1', ...(grep ? ['-g', `"${grep}"`] : [])], { SPEC_WORLD_SECRET: secret })
    : null
  const line = [
    `${String(i).padStart(2)} ${secret}`,
    `proof ${proof.ok ? last(proof.out, /\d+\/\d+ PASS markers/g) : `RED ${last(proof.out, /(SQL ERROR|PROOF 66 FAIL)[^\n]*/g).slice(0, 300)}`}`,
    `rpc ${rpc.ok ? last(rpc.out, /\d+ passed/g) : `RED ${last(rpc.out, /\d+ failed[^\n]*/g)}`}`,
    web ? `browser ${web.ok ? last(web.out, /\d+ passed/g) : `RED ${last(web.out, /\d+ failed[^\n]*/g)}`}` : null,
    // how the proof's fights went under this secret: the endings differ from world to world, which is the point
    `endings ${[...proof.out.matchAll(/closed \(([A-Z_]+)\)|round\(s\), ([A-Z_]+)\)/g)].map((m) => m[1] ?? m[2]).join(',')}`,
  ].filter(Boolean)
  console.log(line.join(' | '))
  if (!proof.ok || !rpc.ok || (web && !web.ok)) {
    bad += 1
    console.log([proof, rpc, web].filter((r) => r && !r.ok).map((r) => r.out.split('\n').filter((l) => /Error|FAIL|expect|Received|Expected|›/.test(l)).slice(0, 14).join('\n')).join('\n'))
  }
}
console.log(bad === 0 ? `all ${n} worlds green` : `${bad} of ${n} worlds RED`)
process.exit(bad === 0 ? 0 : 1)
