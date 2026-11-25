// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FROZEN-ASSERT PATCHES — the applier reads a few frozen self-asserts differently, and only those
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC (no `page`). src/lib/db/frozenAsserts.ts lets the PGlite appliers run 0019's probe
// without a pirate roll and 0108's stopwatch at 1,200 ms instead of 400, 0315's probe sales with a
// fresh daily allowance, 0226's planted pair one hour earlier in UTC hour 01, and 0367's two fleets
// with equal speed rolls before one hull is worn, and the 0266–0274 probe digests with their uuids blanked
// before they sort, without editing any
// of those files (an edited applied migration sends CI from zero). This proves, on the REAL files:
//   1. every patch fits its file exactly once, inside the final `do $$` self-assert block;
//   2. a file with no patch is applied byte for byte, and the chain's identity is the FILE's;
//   3. a patch that no longer fits is a loud failure, never a silent no-op.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { FROZEN_ASSERT_PATCHES, digestRow, sqlToApply } from '../src/lib/db/frozenAsserts'
import { fingerprintChain } from '../src/lib/db/chain'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'

test('every frozen-assert patch fits its real file once, inside the final self-assert block', async () => {
  const files = await loadChain()
  for (const p of FROZEN_ASSERT_PATCHES) {
    const f = files.find((x) => x.name === p.file)
    expect(f, `${p.file} is in the chain`).toBeTruthy()
    const out = sqlToApply(f!)
    expect(out).not.toBe(f!.sql)
    const same = FROZEN_ASSERT_PATCHES.filter((x) => x.file === p.file) // a file may carry several
    expect(out.length - f!.sql.length).toBe(same.reduce((sum, x) => sum + x.replace.length - x.find.length, 0))
    expect(out.split(p.replace).length - 1).toBeGreaterThanOrEqual(1)
    // Everything before the final do-block is untouched: the schema the file builds is the same.
    const block = Math.max(...[...f!.sql.matchAll(/\ndo \$[A-Za-z_]*\$\n/g)].map((m) => m.index!))
    expect(out.slice(0, block)).toBe(f!.sql.slice(0, block))
  }
})

test('the patched asserts can still fail', async () => {
  const files = await loadChain()
  const f108 = files.find((x) => x.name.startsWith('20260818000108_'))!
  const out = sqlToApply(f108)
  expect(out).toMatch(/if v_ms > 1200 then\n\s+raise exception '0108 self-assert FAIL: the board now takes/)
  const f19 = files.find((x) => x.name.startsWith('20260818000019_'))!
  const out19 = sqlToApply(f19)
  // The knob is set inside the probe's begin … exception block that 0019 rolls back, and the
  // to-the-ducat comparison that follows is unchanged.
  expect(out19).toContain("set value = to_jsonb(0.0) where key = 'hazard_p_max';\n    v_played   := world.trade_routes")
  const f315 = files.find((x) => x.name.startsWith('20260818000315_'))!
  // Cleared only below 1e6, so step (h)'s spent allowance (1e8) still refuses and its assert still fails.
  expect(sqlToApply(f315)).toContain('qty < 1000000;\n  v_res := cmd.enqueue(')
  expect(f315.sql).toContain("error_code' is distinct from 'E_DAILY_CAP'")
  // 0154: both arrival comparisons still judge, and the two raises and every other clause are the file's own.
  const f154 = files.find((x) => x.name.startsWith('20260818000154_'))!
  const out154 = sqlToApply(f154)
  const p154 = FROZEN_ASSERT_PATCHES.filter((p) => p.file === f154.name)
  expect(p154).toHaveLength(2)
  let back154 = out154
  for (const p of p154) {
    expect(p.replace).toContain(p.find.trim().slice(3)) // the file's own comparison stands inside
    back154 = back154.replace(p.replace, () => p.find)
  }
  expect(back154).toBe(f154.sql)
  // 0315 (c), (d): only the bid is read again; both judgements after it are the file's own.
  const out315 = sqlToApply(f315)
  const c315 = '    -- (c) THE FLOOR IS KEPT'
  expect(out315.slice(out315.indexOf(c315))).toBe(f315.sql.slice(f315.sql.indexOf(c315)))
  expect(out315).toContain("v_bid := (select q.avg_price from world.quote(v_port, v_good, 3, 'sell', null, v_f1) q);@    -- (c)".replace('@', String.fromCharCode(10)))
  expect(out19).toContain("the quay predicted % out / % in and the orders moved % / %")
  // 0226: only the plant line moves, and only in UTC hour 01 (a pair planted 26 h back is 23:00 and 00:00
  // there, two days, so the day folds into two rows of n 4). Every assertion that judges the hour rows, the
  // day row and the pruning is the file's own, still in the patched text. The 24-hour proof, patched and
  // unpatched, with the mutants that keep the assert able to fail, is scripts/ops/harness/frozen-0226/.
  const f226 = files.find((x) => x.name.startsWith('20260818000226_'))!
  const out226 = sqlToApply(f226)
  expect(out226).toContain(
    "v_h0 := date_trunc('hour', now()) - interval '26 hours' - case when extract(hour from now() at time zone 'UTC') = 1 then interval '1 hour' else interval '0' end;\n",
  )
  for (const keep of [
    "raise exception '0226 self-assert FAIL: the day folded day % o % h % l % c % n %'",
    "raise exception '0226 self-assert FAIL: % hour row(s) at the planted hours for the probe pair, expected 2 (run: %)'",
    "raise exception '0226 self-assert FAIL: the planted fine rows outlived the fine window'",
  ]) {
    expect(f226.sql).toContain(keep)
    expect(out226).toContain(keep)
  }
  // 0367: the two speed rolls are made equal just before the probe wears the second fleet's hull; the comparison
  // that judges "both sail at the slower fleet's speed, and she is the slower" is the file's own, right after it.
  const f367 = files.find((x) => x.name.startsWith('20260818000367_'))!
  const out367 = sqlToApply(f367)
  expect(out367).toContain(
    '    update public.ships set roll_speed = 1 where fleet_id in (v_f1, v_f2);\n' +
      '    update public.ships set durability = durability * 0.5 where fleet_id = v_f2;   -- the second fleet is the slower now\n' +
      '    if voyage.fleet_speed(v_f1) <> voyage.fleet_speed(v_f2) or voyage.fleet_speed(v_f1) <> voyage.fleet_speed_alone_at(v_f2, null)\n' +
      '       or voyage.fleet_speed_alone_at(v_f1, null) <= voyage.fleet_speed_alone_at(v_f2, null) then\n' +
      "      raise exception '0367 self-assert FAIL: both fleets of an armada do not sail at the slower fleet''s speed';\n",
  )
  expect(out367.split('\n').length).toBe(f367.sql.split('\n').length + 1)
  // 0473: only the probe harbour is chosen (a trial that rolls back); everything from v_open on is the file's own.
  const f473 = files.find((x) => x.name.startsWith('20260818000473_'))!
  const out473 = sqlToApply(f473)
  const from473 = f473.sql.slice(f473.sql.indexOf('    v_open := (select count(*)'))
  expect(out473.endsWith(from473)).toBe(true)
  expect(from473).toContain("raise exception '0473 self-assert FAIL: lit, the probe harbour did not post two hold jobs within reach'")
  expect(from473).toContain("raise exception '0473 self-assert FAIL: a hold job''s source is not a seller within reach")
  const was = f226.sql.split('\n')
  const now = out226.split('\n')
  expect(now.length).toBe(was.length)
  expect(was.filter((line, i) => line !== now[i])).toHaveLength(1)
})

// 0266 / 0269 / 0270 / 0272 / 0273 / 0274 (2026-11-15): the probe digest sorted a house's ledger rows and events
// by text that still held the uuids the probe drew, so two rows of one kind and one amount swapped at random and
// two identical runs digested differently (main run 43708858363: "0270 self-assert FAIL: the loop leaves different
// rows"). The patch re-cuts the temp digest from its live text at the head of the self-assert. Held here: the two
// row texts it replaces are in each file's digest exactly once (so the re-cut adds exactly what its own length
// check expects), the signature it names is the file's, every judging comparison is still the file's own, and no
// other migration carries the same sort unpatched.
test('the six probe digests blank their uuids before they sort', async () => {
  const files = await loadChain()
  const six = FROZEN_ASSERT_PATCHES.filter((p) => p.replace.includes('pg_temp.digest_'))
  expect(six.map((p) => p.file.slice(10, 14))).toEqual(['0266', '0269', '0270', '0272', '0273', '0274'])
  const rows = [digestRow('l', 'ledger'), digestRow('e', 'events')]
  for (const p of six) {
    const n = p.file.slice(10, 14)
    const f = files.find((x) => x.name === p.file)!
    const at = f.sql.indexOf(`create function pg_temp.digest_${n}(`)
    expect(at).toBeGreaterThan(0)
    const body = f.sql.slice(at, f.sql.indexOf('\n$$;', at))
    for (const row of rows) {
      expect(body.split(row.was).length - 1, `${n}: ${row.was}`).toBe(1)
      expect(f.sql.split(row.was).length - 1).toBe(1)
      expect(p.replace).toContain(`$fz$${row.was}$fz$`)
      expect(p.replace).toContain(`$fz$${row.now}$fz$`)
      // the uuids are blanked INSIDE the row text that `order by x` sorts
      expect(row.now).toMatch(/^regexp_replace\(\(to_jsonb\([le]\) - 'id'\)::text, '\[0-9a-f\]\{8\}-.*', 'U', 'g'\) as x from public\./)
    }
    const grows = rows.reduce((sum, row) => sum + row.now.length - row.was.length, 0)
    expect(p.replace).toContain(`if length(v_fz) <> length(v_fz_was) + ${grows} then\n      raise exception '${n} frozen-assert patch FAIL`)
    const named = new RegExp(`pg_temp\\.digest_${n}\\(([a-z,]+)\\)'::regprocedure`).exec(p.replace)![1].split(',')
    const declared = new RegExp(`^create function pg_temp\\.digest_${n}\\(([^)]*)\\)`).exec(body)![1]
    expect(named).toEqual(declared.split(',').map((a) => a.trim().split(' ')[1]))
    // The self-assert's own judgement is untouched: the patch only adds lines, before its first statement.
    const out = sqlToApply(f)
    const head = `  select * into v_b from before_${n};\n`
    expect(out.endsWith(f.sql.slice(f.sql.indexOf(head)))).toBe(true)
    expect(out.slice(0, f.sql.indexOf(head))).toBe(f.sql.slice(0, f.sql.indexOf(head)))
    expect(out).not.toContain('$$' + '$fz$')
    expect(p.replace.split('$$').length).toBe(1) // nothing that could close the do $$ block early
  }
  // The same sort in a file with no patch would be the same flake: every carrier is one of the six.
  for (const f of files) {
    if (rows.some((row) => f.sql.includes(row.was))) expect(six.some((p) => p.file === f.name), f.name).toBe(true)
  }
})

test('a file with no patch is applied as written, and the chain identity is the files', async () => {
  const files = await loadChain()
  const patched = new Set(FROZEN_ASSERT_PATCHES.map((p) => p.file))
  for (const f of files) if (!patched.has(f.name)) expect(sqlToApply(f)).toBe(f.sql)
  // fingerprintChain hashes the files; the patch never reaches it.
  expect(fingerprintChain(files)).toBe(fingerprintChain(await loadChain()))
})

test('a patch that no longer fits fails loudly', () => {
  const name = FROZEN_ASSERT_PATCHES[1].file
  expect(() => sqlToApply({ name, sql: 'do $$\nbegin\n  if v_ms > 500 then null; end if;\nend $$;\n' })).toThrow(
    /FROZEN ASSERT PATCH NO LONGER FITS/,
  )
  // Twice is as wrong as never.
  const twice = `do $$\nbegin\n${FROZEN_ASSERT_PATCHES[1].find}${FROZEN_ASSERT_PATCHES[1].find}end $$;\n`
  expect(() => sqlToApply({ name, sql: twice })).toThrow(/NO LONGER FITS/)
  // Outside the final do-block (in the schema half of the file) is refused.
  const outside = `${FROZEN_ASSERT_PATCHES[1].find}\ndo $$\nbegin null; end $$;\n`
  expect(() => sqlToApply({ name, sql: outside })).toThrow(/NO LONGER FITS/)
})
