// ═════════════════════════════════════════════════════════════════
// proof-0317.mjs — A DAY IS A DAY (migration 0317): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/a-day/proof-0317.mjs
//
// Restores the cached world at the head before 0317 (never from zero), then applies 0317 to it several times inside a transaction that is rolled back:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 26 run right after it, for the intended reason;
//   POSITIVE CONTROL  - the real file followed by proof 26, which must pass and print their receipts.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000317_a_day_is_a_day.sql'
const PROOF = 'scripts/db/proofs/26_a_day.sql'
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

const MUTATIONS = [
  ['Report: the boundary is a game day (the bug itself)', (s) => swap(s,
    `$h$    -- the EXACT day boundary: public.real_day(t) = floor(epoch(t) / 86400)\n    v_from := to_timestamp(((v_today - v_span + 1) * 86400)::double precision);\n$h$`,
    `$h$    -- the EXACT day boundary: public.real_day(t) = floor(epoch(t) / 86400)\n    v_from := to_timestamp(((v_today - v_span + 1) * 60)::double precision);\n$h$`),
    /PROOF 26 FAIL: (Today|Week)/],
  ['Report: the bars are game days', (s) => swap(s,
    `$h$           public.real_day(l.created_at) as day\n$h$`, `$h$           world.game_day(l.created_at) as day\n$h$`),
    /still names the game clock/],
  ['Paid: yesterday is the last 24 hours, so part of it is cut off', (s) => swap(s,
    `$h$                and l.created_at >= to_timestamp(((v_today - 1) * 86400)::double precision)),\n`,
    `$h$                and l.created_at > now() - interval '1 day'),\n`),
    /PROOF 26 FAIL: paid/],
  ['Paid: yesterday counts the day before too', (s) => swap(swap(s,
    `(where public.real_day(l.created_at) = v_today - 1), 0))\n$h$),`, `(where public.real_day(l.created_at) < v_today), 0))\n$h$),`),
    `$h$                and l.created_at >= to_timestamp(((v_today - 1) * 86400)::double precision)),\n`, `$h$                and l.created_at >= to_timestamp(((v_today - 2) * 86400)::double precision)),\n`),
    /PROOF 26 FAIL: paid/],
  ['Hall: the book is still the daybook (the bug itself)', (s) => swap(s,
    `from jsonb_each_text(coalesce((select c.day -> 'kinds' from public.stats_city c where c.port_id = p_port order by c.slot desc limit 1), '{}'::jsonb)) e),`,
    `from jsonb_each_text('{}'::jsonb) e),`),
    /PROOF 26 FAIL: the hall/],
  ['Hall: the oldest row, not the newest', (s) => swap(s,
    `where c.port_id = p_port order by c.slot desc limit 1)`, `where c.port_id = p_port and c.slot < 9100000000001 order by c.slot desc limit 1)`),
    /PROOF 26 FAIL: the hall/],
  ['Market: a minute, not a day (the bug itself)', (s) => swap(s,
    `s.at > now() - interval '24 hours'`, `s.at > now() - interval '1 minute'`),
    /the volume of 24 hours is/],
  ['Market: every row of the table', (s) => swap(s,
    `   where s.port_id = p_port and s.good_id = p_good and s.at > now() - interval '24 hours'\n`, `   where s.port_id = p_port and s.good_id = p_good\n`),
    /the volume of 24 hours is/],
  ['Haggle: the bargain dies with the game day', (s) => swap(s,
    `$h$                      and h.good_id = p_good and h.day = public.real_day(now())), 0)\n$h$`,
    `$h$                      and h.good_id = p_good and h.day = floor(extract(epoch from now()) / public.wc_num('game_day_seconds'))::int), 0)\n$h$`),
    /still names the game clock|the clock moved a bargain/],
  ['Haggle: a game day gives new tries', (s) => swap(s,
    `$h$  v_day     int  := public.real_day(now());\n$h$`, `$h$  v_day     int  := floor(extract(epoch from now()) / public.wc_num('wage_per_crew_day'))::int;\n$h$`),
    /PROOF 26 FAIL: a new game day|PROOF 26 FAIL: bargain/],
  ['Fair: left at 4 minutes in 30 (the bug itself)', (s) => swap(s,
    `set duration_seconds = duration_seconds * 2880, season_seconds = season_seconds * 2880;`, `set duration_seconds = duration_seconds * 60, season_seconds = season_seconds * 60;`),
    /a fair is not 3.2 hours/],
  ['Fair: the season still counts the game clock', (s) => swap(s,
    `as $body$ select floor(extract(epoch from p_at) / p_season_seconds)::int $body$`, `as $body$ select floor(world.game_day(p_at) * 60 / p_season_seconds)::int $body$`),
    /still names the game clock/],
  ['Crown: the roll drops tax older than the daybook (the bug itself)', (s) => swap(s,
    `coalesce(sum(f.ducats) filter (where f.kind = 'TAX'), 0) as tax,`, `coalesce(sum(f.ducats) filter (where f.kind = 'TAX' and f.gd >= v_today - 30), 0) as tax,`),
    /the crown's share at 60 s|the crown''s share at 60 s/],
  ['Crown: the tax is not closed, so it is shared again each hour', (s) => swap(s,
    `$h$    update public.port_treasury set earned_day = v_last, tax_unshared = 0 where port_id = r.port_id;\n$h$`,
    `$h$    update public.port_treasury set earned_day = v_last, tax_unshared = tax_unshared where port_id = r.port_id;\n$h$`),
    /PROOF 26 FAIL: the crown's share was taken twice|PROOF 26 FAIL: the crown''s share was taken twice/],
  ['Crown: every flow counts as tax', (s) => swap(s,
    `(where f.kind = 'TAX'), 0) as tax,`, `(where f.kind in ('TAX', 'BUY')), 0) as tax,`),
    /PROOF 26 FAIL: the crown/],
  ['a leaf is left open to clients', (s) => swap(s,
    `  revoke all on function public.traded_today(uuid, uuid) from public, anon, authenticated;\n`, `  grant execute on function public.traded_today(uuid, uuid) to authenticated;\n`),
    /a client can reach a leaf/],
  ['a hunk was cut against a body that is not the live one', (s) => swap(s,
    `$h$  v_tax    bigint;\n  v_s      bigint;\n$h$,\n`, `$h$  v_tax   bigint;\n  v_s      bigint;\n$h$,\n`),
    /occurs 0 time/],
  ['a hunk does not reverse: the new body gained a line no hunk knows', (s) => swap(s,
    `    execute v_def;\n  end loop;\n`, `    execute replace(v_def, 'declare\n', 'declare\n  -- drift\n');\n  end loop;\n`),
    /does not reverse to its pre-image/],
  ['a knob moved', (s) => swap(s,
    `  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`,
    `  update public.world_config set value = to_jsonb(61) where key = 'game_day_seconds';\n  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`),
    /a world_config row moved/],
  ['another function moved', (s) => swap(s,
    `  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`,
    `  execute replace(pg_get_functiondef('public.real_day(timestamp with time zone)'::regprocedure), 'select floor', 'select  floor');\n  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`),
    /another function moved/],
]

async function attempt(sql) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(`${mutate(file)}\n${proof}`)
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
}

const green = await attempt(`${file}\n${proof}`)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file and proof 26, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n    ') : green.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall mutations red, the real file green`)
