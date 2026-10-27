// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FROZEN-ASSERT PATCHES — the applier reads two frozen self-asserts differently, and only those
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC (no `page`). src/lib/db/frozenAsserts.ts lets the PGlite appliers run 0019's probe
// without a pirate roll and 0108's stopwatch at 1,200 ms instead of 400, without editing either
// file (an edited applied migration sends CI from zero). This proves, on the REAL files:
//   1. every patch fits its file exactly once, inside the final `do $$` self-assert block;
//   2. a file with no patch is applied byte for byte, and the chain's identity is the FILE's;
//   3. a patch that no longer fits is a loud failure, never a silent no-op.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { FROZEN_ASSERT_PATCHES, sqlToApply } from '../src/lib/db/frozenAsserts'
import { fingerprintChain } from '../src/lib/db/chain'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'

test('every frozen-assert patch fits its real file once, inside the final self-assert block', async () => {
  const files = await loadChain()
  for (const p of FROZEN_ASSERT_PATCHES) {
    const f = files.find((x) => x.name === p.file)
    expect(f, `${p.file} is in the chain`).toBeTruthy()
    const out = sqlToApply(f!)
    expect(out).not.toBe(f!.sql)
    expect(out.length - f!.sql.length).toBe(p.replace.length - p.find.length)
    expect(out.split(p.replace).length - 1).toBeGreaterThanOrEqual(1)
    // Everything before the final do-block is untouched: the schema the file builds is the same.
    const block = f!.sql.lastIndexOf('\ndo $$\n')
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
  expect(out19).toContain("the quay predicted % out / % in and the orders moved % / %")
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
