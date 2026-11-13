// dice-0400.mjs: PROOF 95 UNDER OTHER WORLDS. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-merchants/dice-0400.mjs [--n=12]
//
// Why: every built world has its own `world_secret` (0031) and its own market, and what a merchant's planner CHOOSES follows the market. Proof 95's first
// cut asserted the planner's choice and was red on CI's world. This runs proof 95 N times on the cached world with 0400 applied (never from zero), each
// time under ANOTHER SECRET and ANOTHER MARKET: every harbour's stock of every good is multiplied by its own random factor between 0.2 and 1.8 before
// the proof starts (prices follow stock). It prints one line a run and exits 1 if any run is not green. The temporary copy of the proof is removed.
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { readFileSync, rmSync, writeFileSync } from 'node:fs'

const n = Number(process.argv.find((a) => a.startsWith('--n='))?.slice(4) ?? 12)
const PROOF = 'scripts/db/proofs/95_a_merchant_keeps_her_home_waters.sql'
const TMP = 'scripts/db/proofs/995_a_merchant_dice_tmp.sql'
let bad = 0
for (let i = 1; i <= n; i++) {
  const secret = `dice-${i}-${randomBytes(32).toString('hex')}`   // 0031: a secret is at least 64 characters
  const sql = readFileSync(PROOF, 'utf8')
  const at = sql.indexOf('\ndo $$')
  writeFileSync(TMP, `${sql.slice(0, at)}
update public.world_config set value = to_jsonb('${secret}'::text) where key = 'world_secret';
update public.port_goods set stock = greatest(1, stock * (0.2 + 1.6 * random()));
${sql.slice(at)}`)
  let out
  try {
    out = execFileSync('node', ['scripts/ops/harness/sea-conditions/run.mjs', '--apply=0400', '--proofs=995'], { encoding: 'utf8', env: { ...process.env, BYEHARU_PREFIX_CACHE: 'required' }, stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (e) {
    out = `${e.stdout ?? ''}\n${e.stderr ?? ''}`
  } finally {
    rmSync(TMP, { force: true })
  }
  const line = out.split('\n').find((l) => l.startsWith('PROOF ')) ?? out.slice(-300)
  if (!line.includes('green')) bad++
  console.log(`${String(i).padStart(2)} ${secret.slice(0, 14)}… ${line.replace('PROOF 995_a_merchant_dice_tmp.sql: ', '').slice(0, 400)}`)
}
console.log(bad === 0 ? `ALL GREEN: proof 95 under ${n} other secrets and markets` : `${bad} of ${n} RED`)
process.exit(bad === 0 ? 0 : 1)
