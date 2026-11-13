// ═══════════════════════════════════════════════════════════════════════════════
// proof-0362.mjs — THE NEWS TELLS OF BIG TRADES, PRICE SPIKES, PIRATES AND GIFTS (migration 0362): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/news-kinds/proof-0362.mjs [--no-mutations] [--only=<text>] [--with=55,56] [--cost] [--volume]
//
// Restores the cached world at the head before 0362 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 64 on the world with no file: it must fail (its hunks are not in the live bodies);
//   POSITIVE CONTROL  - the real file, then proof 64: every marker it declares;
//   --with            - the real file followed by each named existing proof, one transaction each;
//   --cost            - cost.sql after the file: a real sale, a real buy, the real snapshot and a real passage of raid days, the OLD bodies against the NEW, interleaved.
//                       The old bodies are kept copies in pg_temp, made from the live bodies by the migration's own hunks (gen-checks.mjs);
//   --volume          - volume-scene.sql after the file: every merchant fleet of the local world starts her lap through the real cmd.advance; what her buys come to, how many
//                       reach news_big_trade, and how many rows that tells with the cap;
//   MUTATION CONTROLS - deliberate breakages (below), each required to FAIL the file's own self-assert, or proof 64 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { hunks } from './gen-checks.mjs'

const NAME = '20260818000362_the_news_tells_of_trades_prices_pirates_and_gifts.sql'
const PROOF = 'scripts/db/proofs/64_news_kinds.sql'
const HERE = 'scripts/ops/harness/news-kinds'
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const has = (k) => process.argv.includes(`--${k}`)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)
await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })

function swap(sql, from, to, times = 1) {
  if (sql.split(from).length !== times + 1) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times, not ${times}: ${from.slice(0, 120)}`)
  return sql.replaceAll(from, () => to)
}

async function attempt(...sqls) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    for (const sql of sqls) if (sql) await db.exec(sql, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const green = (r) => !r.err && want.every((m) => r.notes.some((x) => x.includes(`PASS: ${m}`)))

// the OLD bodies as kept copies in pg_temp (<name>_old_0362), for a scene that times old against new in one session: the live body, each NEW text once, reversed, renamed
const OLD_COPIES = `
create temp table hunks_scene (fn text, n int, old text, new text) on commit drop;
insert into hunks_scene (fn, n, old, new) values
${hunks.map((h) => `  ('${h.fn}', ${h.n}, $h$${h.old}$h$, $h$${h.new}$h$)`).join(',\n')};
do $b$
declare
  f record; h record; v_def text; v_name text;
begin
  for f in select distinct x.fn from hunks_scene x order by x.fn loop
    v_def := replace(pg_get_functiondef(f.fn::regprocedure), E'\\r', '');
    for h in select * from hunks_scene x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'scene: hunk % of % is not in the live body exactly once', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    v_name := split_part(split_part(f.fn, '(', 1), '.', 2);
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || split_part(f.fn, '(', 1) || '(', 'CREATE FUNCTION pg_temp.' || v_name || '_old_0362(');
    execute v_def;
  end loop;
end
$b$;
`

// ── RED FIRST ──
if (!arg('only')) {
  const r = await attempt(proof)
  if (!r.err) failures.push('RED FIRST: proof 64 passed on a world with no 0362')
  say(`RED FIRST   proof 64 with no file: ${r.err ? 'red, as it must be: ' + r.err.slice(0, 160) : 'GREEN (wrong)'}`)

  // ── POSITIVE CONTROL ──
  const t = Date.now()
  const g = await attempt(file, proof)
  if (!green(g)) failures.push(`POSITIVE CONTROL: ${g.err ?? 'missing ' + want.filter((m) => !g.notes.some((x) => x.includes(`PASS: ${m}`))).join(', ')}`)
  say(`POSITIVE    the real file, then proof 64: ${green(g) ? `green, ${want.length} of ${want.length} markers` : 'RED ' + (g.err ?? '').slice(0, 800)}, ${Date.now() - t} ms`)
  for (const n of g.notes.filter((x) => x.startsWith('0362'))) say('   ', n.slice(0, 400))
}

// ── --with: the real file, then each named existing proof ──
if (arg('with')) {
  const { readdir } = await import('node:fs/promises')
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('with').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`))
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const marks = [...sql.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
    const t = Date.now()
    const r = await attempt(file, sql)
    const missing = marks.filter((m) => !r.notes.some((x) => x.includes(`PASS: ${m}`)))
    if (r.err || missing.length) failures.push(`WITH ${f}: ${r.err ?? 'missing ' + missing.join(', ')}`)
    say(`WITH        ${f}: ${r.err ? 'RED ' + r.err.slice(0, 1200) : missing.length ? 'MISSING ' + missing.join(', ') : `green, ${marks.length} of ${marks.length} markers`}, ${Date.now() - t} ms`)
  }
}

// ── --cost / --volume: a local scene after the file ──
for (const [flag, scene, pre] of [['cost', 'cost.sql', OLD_COPIES], ['volume', 'volume-scene.sql', '']]) {
  if (!has(flag)) continue
  const sql = (await readFile(path.join(HERE, scene), 'utf8')).replaceAll('\r', '')
  if (!sql.startsWith('--') || !sql.includes("raise exception 'local PGlite world only: this scene writes'")) throw new Error(`${scene} does not carry the local-only guard`)
  const r = await attempt(file, pre, sql)
  if (r.err) failures.push(`${flag}: ${r.err}`)
  say(`${flag.toUpperCase()}${r.err ? ' ERROR ' + r.err : ''}`)
  for (const n of r.notes.filter((x) => !x.startsWith('0362 self-assert'))) say('   ', n)
}

// ── MUTATION CONTROLS: each must fail, in the file's self-assert (S) or in proof 64 after it (P) ──
// [name, where it must fail, the regex of the failure, text in the file, its replacement, the same breakage in proof 64's copy of the hunk (when the text is inside a hunk)]
const M = [
  ['a sale is news whatever its total (the threshold is dropped)', 'P', /told 1 row|was told/,
    "  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then\n    perform public.news_big_trade('BIG_SALE'", "  if true then\n    perform public.news_big_trade('BIG_SALE'", true],
  ['a buy is news whatever its total', 'P', /told 1 row|was told/,
    "  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then\n    perform public.news_big_trade('BIG_BUY'", "  if true then\n    perform public.news_big_trade('BIG_BUY'", true],
  ['the knob at 0 means every trade (nullif dropped on the sale)', 'P', /knob at 0|told 1 row/,
    "  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then\n    perform public.news_big_trade('BIG_SALE'", "  if q.total >= public.wc_num('news_big_trade') then\n    perform public.news_big_trade('BIG_SALE'", true],
  ['the cap on the world\'s ships is not asked for a trade', 'S', /news_merchant_hour 0 a merchant/,
    'or coalesce(p_total, 0) <= 0 or (v_npc and not coalesce(public.news_room(p_kind), false)) then', 'or coalesce(p_total, 0) <= 0 then'],
  ['the cap counts nothing', 'S', /news_merchant_hour 0 a merchant|refused/,
    "w.kind = k.kind) < public.wc_int('news_merchant_hour')", "w.kind = k.kind and false) < public.wc_int('news_merchant_hour') + 1"],
  ['a trade has no key (ten parts are ten headlines)', 'S', /told twice/,
    "lower(p_kind) || ':' || p_company::text || ':' || p_port::text || ':' || p_good::text || ':' || to_char(clock_timestamp() at time zone 'UTC', 'YYYYMMDDHH24'),", 'null,'],
  ['a big trade also writes an event (an outcome moves)', 'P', /is not the old body/,
    '  return public.news_post(p_kind, p_port, p_good, p_company, null,', "  perform public.emit_event(p_company, 'NEWS_TOLD', '{}'::jsonb);\n  return public.news_post(p_kind, p_port, p_good, p_company, null,"],
  ['a merchant\'s small loss to pirates is told', 'S', /pirates' news is not a player always/,
    "(p_loss < public.wc_num('news_pirate_loss') or not coalesce(public.news_room('PIRATES'), false))", "(not coalesce(public.news_room('PIRATES'), false))"],
  ['a day that lost nothing is told', 'S', /pirates' news is not a player always/,
    '  if coalesce(p_loss, 0) <= 0 then\n    return null;\n  end if;\n  select pl.is_npc, pl.company_name into v_npc, v_name', '  select pl.is_npc, pl.company_name into v_npc, v_name'],
  ['her cargo is priced after the raiders took it (the loss reads 0)', 'P', /cost her \d+ and its news is/,
    '        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good\'s cost with its last tun)\n        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);\n',
    '        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);\n        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good\'s cost with its last tun)\n', true],
  ['the raid\'s news also moves her purse (an outcome moves)', 'P', /is not the old bodies/,
    "  return public.news_post('PIRATES', null, null, p_company, null, 'pirates:'", "  update public.players set ducats = ducats + 1 where id = p_company;\n  return public.news_post('PIRATES', null, null, p_company, null, 'pirates:'"],
  ['every move is a spike (the per cent is not read)', 'P', /spikes told are not/,
    'and abs(c.bid_c - b.bid_c) * 100 >= v_pct * b.bid_c', 'and abs(c.bid_c - b.bid_c) * 100 >= 0 * v_pct'],
  ['more than the largest five are told', 'S', /spikes told are 7/, '             limit v_top) t', '             limit 100) t'],
  ['a pair is never quiet', 'S', /in the next hour 5 were told/,
    "     where not exists (select 1 from public.world_news w\n                        where w.port_id = t.port_id and w.at > p_now - v_quiet and w.good_id = t.good_id and w.kind = 'PRICE_SPIKE')\n", ''],
  ['the spike reads the wrong hours (the hour beginning against the hour closed)', 'S', /spikes told are/,
    "c.hour = p_hour - interval '1 hour'\n              join public.price_history_hour b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.hour = p_hour - interval '2 hours'",
    "c.hour = p_hour\n              join public.price_history_hour b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.hour = p_hour - interval '1 hour'"],
  ['a gift is told at no city', 'S', /a gift is not one CAPITAL_GIFT row/,
    "  return public.news_post('CAPITAL_GIFT', p_capital, null, p_company, null,", "  return public.news_post('CAPITAL_GIFT', null, null, p_company, null,"],
  ['a gift is told whether or not one was made', 'P', /a real gift is not the old body|PROOF 64 FAIL/,
    '  if v_n > 0 then\n    perform public.news_gift(r.cap_id, r.player_id, r.capital, p_now);\n  end if;\n', '  perform public.news_gift(r.cap_id, r.player_id, r.capital + 1, p_now);\n', true],
  ['a template names a word no writer gives', 'S', /a template names a word/, "'{good} at {city} {p} in an hour'", "'{good} at {city} {pct} in an hour'"],
  ['a client may call a writer', 'S', /a client can reach a writer/,
    'revoke all on function public.news_pirates(uuid, int, uuid, text, numeric) from public, anon, authenticated;', 'grant execute on function public.news_pirates(uuid, int, uuid, text, numeric) to authenticated;'],
  ['a knob is not as written', 'S', /a knob is not as written/, "('news_merchant_hour', to_jsonb(2),", "('news_merchant_hour', to_jsonb(40),"],
  ['a switch of the game is written', 'S', /a world_config row other than this file's six knobs moved/,
    '-- ── 2. THE WRITERS\' LEAVES', "update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';\n-- ── 2. THE WRITERS' LEAVES"],
]
if (!has('no-mutations')) {
  let red = 0
  for (const [name, where, re, from, to, inHunk] of M) {
    if (arg('only') && !name.includes(arg('only'))) continue
    const f2 = swap(file, from, to)
    const p2 = inHunk ? swap(proof, from, to) : proof
    const r = await attempt(f2, p2)
    const inFile = r.err && r.err.includes('0362 self-assert FAIL')
    const ok = r.err && re.test(r.err) && (where === 'S' ? inFile : !inFile)
    if (ok) red++
    else failures.push(`MUTATION "${name}": ${r.err ? 'failed for another reason: ' + r.err.slice(0, 300) : 'PASSED'}`)
    say(`MUTATION    ${ok ? 'red' : 'NOT CAUGHT'} (${where === 'S' ? 'self-assert' : 'proof 64'}): ${name}${ok ? '' : ' :: ' + (r.err ?? 'green').slice(0, 300)}`)
  }
  say(`mutations: ${red} red`)
}

await db.close()
if (failures.length) {
  say('\nFAILED:')
  for (const f of failures) say('  ' + f)
  process.exit(1)
}
say('\nall as it must be')
