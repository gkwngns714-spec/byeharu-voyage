// Throwaway: apply the chain to 0049 ONCE, then run mutated copies of 0050 inside
// begin/rollback and record the REAL red message each of its asserts produces.
// A guard nobody has seen bite is decoration. Delete after use.
import { applyChain, MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000050_a_refusal_is_two_numbers_and_a_verb.sql'
const sql0050 = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')

// Apply everything up to but NOT including 0050.
const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f === LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied to 0049\n')

const MUTATIONS = [
  ['(a) the figures SHAPE', "'have', round(p_have, 1)", "'amount', round(p_have, 1)"],
  ['(a) control: have > need', 'if p_have > p_need then', 'if p_have > p_need and false then'],
  ['(a) control: need <= 0', 'if p_need <= 0 then', 'if p_need <= 0 and false then'],
  ['(a) control: unit is a NAME', "if p_unit !~ '^[a-z]+$' then", 'if false then'],
  ['(a) control: null have', 'if p_have is null or p_need is null then', 'if false then'],
  ['(b) figures cross the RAISE', "detail = coalesce((p_refusal->'figures')::text, '')", "detail = ''"],
  ['(c) a plain message keeps its head', 'return cmd.refusal(\'E_PARSE\', p_message, v_figs);',
    "return cmd.refusal('E_PARSE', substr(p_message, 9), v_figs);"],
  ['(d) no hand-copied split survives', "if sqlerrm ~ '^E_[A-Z0-9_]+:' then\n        v_ref := cmd.refusal_caught(sqlerrm);",
    "if sqlerrm ~ '^E_[A-Z_]+:' then\n        v_ref := cmd.refusal_caught(sqlerrm);"],
  ['(e) served have IS endurance_days', "cmd.figures(v_end, v_days * public.wc_num('endurance_margin'), 'days'));\n    end if;",
    "cmd.figures(v_end - 0.5, v_days * public.wc_num('endurance_margin'), 'days'));\n    end if;"],
  ['(e) the sentence carries no digit', "'no chandler where she is bound — the casks must cover the way home too',",
    "'no chandler where she is bound — the round trip is 28.7 voyage-days',"],
  ['(e) the sentence keeps the REASON', "'no chandler where she is bound — the casks must cover the way home too'",
    "'the casks will not cover it'"],
  ['(f) the halted order keeps figures', "'figures', o.error_figures,\n           'result', o.result) order by o.seq)",
    "'result', o.result) order by o.seq)"],
  ['(g) preview agrees with issue', "'error_message', v_ref->>'sentence',\n                              'figures', v_ref->'figures',\n                              'fixes', cmd.fixes(v_code, p_fleet));$pv3$",
    "'error_message', v_ref->>'sentence',\n                              'fixes', cmd.fixes(v_code, p_fleet));$pv3$"],
  ['(h) the quay still ASKS the gate', "perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));\n    v_routes := world.trade_routes",
    "v_routes := world.trade_routes"],
  ['(i) E_HOLD_FULL figures are the hold’s own', "cmd.figures(v_free, v_qty, 't'));$b3$", "cmd.figures(v_free, v_qty + 1, 't'));$b3$"],
  ['(j) the posture is unmoved', 'revoke all on function cmd.refuse(text, text, jsonb)         from public, anon, authenticated;',
    'grant execute on function cmd.refuse(text, text, jsonb) to authenticated;'],
]

let bad = 0
for (const [name, from, to] of MUTATIONS) {
  if (!sql0050.includes(from)) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  const mutated = sql0050.replace(from, to)
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
