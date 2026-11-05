// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0318.mjs — A HOUSE HAS A REGARD (migration 0318): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/regard/proof-0318.mjs
//
// Restores the cached world at the head before 0318 (never from zero), then applies 0318 to it several times inside a transaction that is rolled back:
//   POSITIVE CONTROL  - the real file alone, then the real file followed by proof 27;
//   DEPLOY ORDER      - with --first=a.sql,b.sql, those files are applied first, in that order (0316 and 0317 were read from their branches this way);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 27 run right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it. `browser` is the variant this PC keeps a prefix of; its world is the same chain.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { IMAGE_CACHE_DIR, BROWSER_VARIANT, chainAndFingerprint } from '../../../db/build-image.mjs'

const NAME = '20260818000318_a_house_has_a_regard.sql'
const PROOF = 'scripts/db/proofs/27_regard.sql'
const failures = []
const say = (...a) => console.log(...a)

const files = []
const chain = await chainAndFingerprint()
for (const f of chain.files) if (f.name !== NAME) files.push(f)
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

// One attempt, rolled back. `withProof` runs proof 27 after the file. Answers the error, or null, and the notices.
async function attempt(sql, withProof) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    await db.exec(sql, { onNotice })
    if (withProof) await db.exec(proof, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['dark multiplier on the tax is 2, not 1', (s) => swap(s, `  if not public.regard_on() or p_player is null then\n    return 1;\n  end if;\n  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then\n    return 1;`,
    `  if not public.regard_on() or p_player is null then\n    return 2;\n  end if;\n  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then\n    return 1;`), /PROOF 27 FAIL: dark, a quote moved/],
  ['the merchant test is dropped from the factor', (s) => swap(s, `  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then\n    return 1;\n  end if;\n`, ''), /PROOF 27 FAIL: a merchant reads a row/],
  ['the merchant test is dropped from the writer', (s) => swap(s, `  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then\n    return null;\n  end if;\n`, ''), /PROOF 27 FAIL: a merchant has regard/],
  ['the writer writes while dark', (s) => swap(s, `  if not public.regard_on() or p_player is null or p_nation is null or coalesce(p_delta, 0) = 0 then`, `  if p_player is null or p_nation is null or coalesce(p_delta, 0) = 0 then`), /PROOF 27 FAIL: dark, regard_add answered/],
  ['no fold: regard_add adds to the raw points', (s) => swap(s, `set points = public.regard_fold(r.points, r.as_of) + excluded.points`, `set points = r.points + excluded.points`), /PROOF 27 FAIL: regard_add did not fold/],
  ['half-life off by one: 0.5 becomes 0.51', (s) => swap(s, `power(0.5::numeric,`, `power(0.51::numeric,`), /PROOF 27 FAIL: one half-life leaves/],
  ['no floor on age: a future row grows', (s) => swap(s, `greatest(extract(epoch from now() - p_as_of) / 3600, 0)::numeric`, `(extract(epoch from now() - p_as_of) / 3600)::numeric`), /PROOF 27 FAIL: a row from the future grew/],
  ['the score is not rounded before the band', (s) => swap(s, `round(p_score) >= (b.value ->> 'from')::numeric`, `p_score >= (b.value ->> 'from')::numeric`), /0318 self-assert FAIL: a band is not where/],
  ['Wary pays 1.2, not 1.25', (s) => swap(s, `{"band": "wary", "from": -299, "factor": 1.25}`, `{"band": "wary", "from": -299, "factor": 1.2}`), /PROOF 27 FAIL: score -?\d+ is band/],
  ['the dock fee forgets the multiplier', (s) => swap(s, `(select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))\n                           * public.regard_factor(p_player, p_port)))::bigint;`,
    `(select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port))))) ::bigint;`), /PROOF 27 FAIL: (score|0318|.*port_fee)|does not carry its 0318 term/],
  ['the multiplier is outside the cap', (s) => swap(s, `return least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max')));`,
    `return least(v_base * public.country_factor(v_stance), greatest(v_base, public.wc_num('tariff_rate_max'))) * public.regard_factor(p_player, p_port);`), /PROOF 27 FAIL: a Hostile company at war pays|does not carry its 0318 term/],
  ['a fine buys the stance base too', (s) => swap(s, `from (select public.regard_fold(r.points, r.as_of) as p from public.house_regard r\n                            where r.player_id = p_player and r.nation_id = p_nation) x\n                    where x.p < 0), 0)::bigint`,
    `from (select public.regard_of(p_player, p_nation) as p) x\n                    where x.p < 0), 0)::bigint`), /PROOF 27 FAIL: (-1000 points owe|the receipt reads|a stance base|a good name)/],
  ['a fine is not held to what is owed', (s) => swap(s, `v_pay := least(greatest(coalesce(p_coin, 0), 0), v_owed, coalesce(v_have, 0));`, `v_pay := least(greatest(coalesce(p_coin, 0), 0), coalesce(v_have, 0));`), /PROOF 27 FAIL: asked for 4,000,000/],
  ['a fine is not held to her purse', (s) => swap(s, `v_pay := least(greatest(coalesce(p_coin, 0), 0), v_owed, coalesce(v_have, 0));`, `v_pay := least(greatest(coalesce(p_coin, 0), 0), v_owed);`), /insufficient|E_INSUFFICIENT_FUNDS|PROOF 27 FAIL: a fine is not held/i],
  ['a fine is paid anywhere', (s) => swap(s, `if v_nat is null or public.city_capital(p_port) is distinct from p_port then`, `if false then`), /E_NOT_DOCKED: dock a fleet here/],   // the capital test gone, the next test answers where the proof asked for E_NOT_A_CAPITAL
  ['a fine needs no fleet docked', (s) => swap(s, `if not exists (select 1 from public.fleets f where f.player_id = p_player and f.status = 'DOCKED' and f.port_id = p_port) then\n    perform cmd.refuse('E_NOT_DOCKED', 'dock a fleet here to pay a fine');\n  end if;\n`, ''), /E_NO_FINE: you owe/],   // the dock test gone, the next test answers where the proof asked for E_NOT_DOCKED
  ['FINE counts as made gold', (s) => swap(s, `values ('FINE', 'moved', 'Fines', 48)`, `values ('FINE', 'minted', 'Fines', 48)`), /0318 self-assert FAIL: FINE is not a moved kind/],
  ['the fine pays nobody: the purse only', (s) => swap(s, `v_after := public.pay_city(p_player, p_port, 'FINE', v_pay, v_event);`, `v_after := public.credit(p_player, 'FINE', -v_pay, v_event);`), /PROOF 27 FAIL: the fine did not move/],
  ['a gift earns twice', (s) => swap(s, `p_coin * public.wc_num('regard_per_100k') / 100000`, `2 * p_coin * public.wc_num('regard_per_100k') / 100000`), /PROOF 27 FAIL: 100,000 d\. given earned/],
  ['the stake is not hooked', (s) => swap(s, `  perform public.regard_gift(p_player, p_port, v_cost, 'SHARE');   -- 0318: dark, nothing\n`, ''), /PROOF 27 FAIL: a stake of/],
  ['the line is served dark', (s) => swap(s, `  if not public.regard_on() or p_player is null then\n    return '{}'::jsonb;`, `  if p_player is null then\n    return '{}'::jsonb;`), /PROOF 27 FAIL: dark, a quote moved/],
  ['dues.factor leaves regard out', (s) => swap(s, `'factor', public.country_factor(v_stance) * public.regard_factor(p_player, p_port),   -- 0318: the factor she really pays`, `'factor', public.country_factor(v_stance),   -- 0318: x`), /does not carry its 0318 term/],
  ['the fine is offered away from the capital', (s) => swap(s, `'fine', case when public.city_capital(p_port) = p_port then public.fine_owed(p_player, v_nation) else 0 end`, `'fine', public.fine_owed(p_player, v_nation)`), /PROOF 27 FAIL: a fine is offered away/],
  ['regard is lit by the file', (s) => swap(s, `('regard_enabled', 'false'::jsonb,`, `('regard_enabled', 'true'::jsonb,`), /0318 self-assert FAIL: regard is not dark/],
  ['the door is open to anon', (s) => swap(s, `  grant execute on function cmd.pay_fine(uuid, bigint) to authenticated;`, `  grant execute on function cmd.pay_fine(uuid, bigint) to authenticated, anon;`), /0318 self-assert FAIL: the grants/],
  ['a hunk does not reverse: the file also rewrites a neighbour', (s) => swap(s, `  -- ── 7. THE SELF-ASSERT`, `  execute replace(pg_get_functiondef('public.country_factor(text)'::regprocedure), '0237 (docs', '0237 x (docs');\n  -- ── 7. THE SELF-ASSERT`), /0318 self-assert FAIL: another function moved/],
]

say('\nPOSITIVE CONTROL: the real file alone')
const alone = await attempt(file, false)
if (alone.err) failures.push(`the real file failed: ${alone.err}`)
say('  ', alone.err ?? alone.notes.find((n) => n.includes('0318 self-assert ok')))

say('POSITIVE CONTROL: the real file, then proof 27')
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice('--first='.length).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)
const whole = await attempt(before + '\n' + file, true)
if (whole.err) failures.push(`proof 27 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:'))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(mutate(file), true)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 220)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${MUTATIONS.length} mutations red, the real file and proof 27 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
