// dice.mjs: PROOF 101 UNDER OTHER WORLDS. LOCAL ONLY; not in CI. (The pattern of sea-merchants/dice-0400.mjs.)
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/plan-fees/dice.mjs [--n=6]
//
// Runs proof 101 N times on the cached world with 0406 applied (never from zero), each time under ANOTHER SECRET and ANOTHER MARKET: every harbour's
// stock of every good is multiplied by its own random factor between 0.2 and 1.8 before the proof starts, so the planner answers differently (other loops pay, other merchants wait). One line a run; exits 1 if any run is not green. The temporary copy of the proof is removed.
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { readFileSync, rmSync, writeFileSync } from 'node:fs'

const n = Number(process.argv.find((a) => a.startsWith('--n='))?.slice(4) ?? 6)
const PROOF = 'scripts/db/proofs/101_a_merchant_counts_the_ports_fee_before_she_sails.sql'
const TMP = 'scripts/db/proofs/9101_plan_fees_dice_tmp.sql'
let bad = 0
for (let i = 1; i <= n; i++) {
  const secret = `dice-${i}-${randomBytes(32).toString('hex')}`
  const sql = readFileSync(PROOF, 'utf8')
  const at = sql.indexOf('\ndo $p$')
  writeFileSync(TMP, `${sql.slice(0, at)}
update public.world_config set value = to_jsonb('${secret}'::text) where key = 'world_secret';
update public.port_goods set stock = greatest(1, stock * (0.2 + 1.6 * random()));
${sql.slice(at)}`)
  let out
  try {
    out = execFileSync('node', ['scripts/ops/harness/sea-conditions/run.mjs', '--apply=0400,0401,0402,0403,0404,0406', '--proofs=9101', '--notes'],
      { encoding: 'utf8', env: { ...process.env, BYEHARU_PREFIX_CACHE: 'required' }, stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (e) {
    out = `${e.stdout ?? ''}\n${e.stderr ?? ''}`
  } finally {
    rmSync(TMP, { force: true })
  }
  const line = out.split('\n').find((l) => l.startsWith('PROOF ')) ?? out.slice(-300)
  const all = out.split('\n').find((l) => l.includes('PASS: PF_UNDER')) ?? ''
  if (!line.includes('green')) bad++
  console.log(`${String(i).padStart(2)} ${line.replace('PROOF 9101_plan_fees_dice_tmp.sql: ', '').slice(0, 300)} | ${all.trim().slice(0, 160)}`)
}
console.log(bad === 0 ? `ALL GREEN: proof 101 under ${n} other secrets and markets` : `${bad} of ${n} RED`)
process.exit(bad === 0 ? 0 : 1)
