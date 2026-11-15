import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PROOF 56 REBUILDS THE OLD BODIES FROM 0353'S OWN HUNKS — and this holds that they ARE 0353's. Pure Node, no browser.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Proof 56 (scripts/db/proofs/56_combat_log.sql) fights the old engine and skin against the new by REVERSING the 20
// hunks of migration 0353 on the live bodies. It used to hold each rebuilt body to a fixed digest; a later migration
// that legitimately re-cut one of those bodies (0354 added a row to the registry) then turned the proof red on its own
// PR (2026-11-12, #602). The rebuild is now judged as a round trip on the live body, whatever later files made of it.
// A round trip cannot tell whether the proof's COPY of a hunk is the migration's, so that is held here, statically,
// and for ever: migration 0353 is applied and frozen, and every one of its hunks must stand in the proof word for word.
// No digest of any body is held anywhere in the proof.

const MIG = path.resolve('supabase', 'migrations', '20260818000353_a_fight_keeps_its_log.sql')
const PROOF = path.resolve('scripts', 'db', 'proofs', '56_combat_log.sql')
const NAMES: Record<string, string> = {
  c_eng: 'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)',
  c_rep: 'voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
}

// THE LATER RE-CUTS (2026-11-16). The proof REVERSES these hunks on the LIVE bodies, so when a later migration re-cuts a line
// that lies inside one of them, the proof's copy has to follow the live text or the reversal finds nothing (0432 gave Flee a
// raid's bonus; 0433 shortened the server's sentences). The spec used to demand 0353's text unchanged, and so stood red on main
// from #721 on. The law is now: a hunk in the proof is 0353's hunk with EXACTLY the re-cuts listed here applied, nothing else.
// Each entry names the frozen migration that made it; that file must hold both texts, and an entry that changes no hunk fails.
// A new slice that re-cuts a line inside a 0353 hunk adds its line here in the same PR that edits proof 56.
const M432 = '20260818000432_a_raided_ship_may_run.sql'
const M433 = '20260818000433_the_server_says_have_and_need.sql'
const RECUTS: readonly { by: string; from: string; to: string }[] = [
  {
    by: M432,
    from:
      "      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),\n" +
      "                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));",
    to:
      "      -- 0432: a raid's flee bonus (p_opts.a_flee: her speed and her company's handling, public.flee_bonus) within raid_flee_floor..raid_flee_max; without one, 0357's chance\n" +
      "      v_pf := case when p_opts ? 'a_flee'\n" +
      "                   then least(public.wc_num('raid_flee_max'), greatest(public.wc_num('raid_flee_floor'),\n" +
      "                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting') + (p_opts ->> 'a_flee')::numeric))\n" +
      "                   else least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),\n" +
      "                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting'))) end;",
  },
  { by: M433, from: "then 'you are caught unready'", to: "then 'caught unready'" },
  { by: M433, from: "then 'you run before them'", to: "then 'we run'" },
  { by: M433, from: "'You have nothing aboard to pay them with.'::text;", to: "'Nothing aboard to pay.'::text;" },
  { by: M433, from: "'They will take no ransom.'::text;", to: "'No ransom taken.'::text;" },
  { by: M433, from: "'You turn and run.'::text;", to: "'We run.'::text;" },
  { by: M433, from: "'You pay their price, and they let you pass.'::text;", to: "'Paid; let pass.'::text;" },
  { by: M433, from: "v_sentence := 'We paid their price and they let us pass.';", to: "v_sentence := 'Paid; let pass.';" },
  { by: M433, from: "'You get clear of them.'::text;", to: "'Got clear.'::text;" },
  { by: M433, from: "v_sentence := 'We ran, and got clear of them.';", to: "v_sentence := 'Ran; got clear.';" },
]

test('every hunk of migration 0353 stands in proof 56 word for word, and the proof pins no body by digest', () => {
  const mig = readFileSync(MIG, 'utf8').replaceAll('\r', '')
  const proof = readFileSync(PROOF, 'utf8').replaceAll('\r', '')
  const re = /\((c_eng|c_rep|'[a-z_.]+\([a-z ,]*\)'), (\d+),\n\$o\$([\s\S]*?)\$o\$,\n\$n\$([\s\S]*?)\$n\$\)/g
  const hunks = [...mig.matchAll(re)].map((m) => ({ fn: NAMES[m[1]] ?? m[1].slice(1, -1), n: m[2], old: m[3], new: m[4] }))
  expect(hunks, 'migration 0353 holds 20 hunks').toHaveLength(20)
  // THE RE-CUTS: every one is read off its own (frozen) migration, and every one must have changed a hunk.
  const used = new Set<number>()
  const recut = (text: string) =>
    RECUTS.reduce((t, r, i) => {
      if (!t.includes(r.from)) return t
      used.add(i)
      return t.replaceAll(r.from, r.to)
    }, text)
  RECUTS.forEach((r) => {
    const by = readFileSync(path.resolve('supabase', 'migrations', r.by), 'utf8').replaceAll('\r', '')
    expect(by.includes(r.from), `${r.by} does not hold the old text ${JSON.stringify(r.from)}`).toBe(true)
    expect(by.includes(r.to), `${r.by} does not hold the new text ${JSON.stringify(r.to)}`).toBe(true)
  })
  const missing = hunks.filter((h) => !proof.includes(`('${h.fn}', ${h.n}, $h$${recut(h.old)}$h$, $h$${recut(h.new)}$h$)`)).map((h) => `${h.fn} #${h.n}`)
  expect(missing, `proof 56 does not hold these hunks of 0353 word for word (as the listed re-cuts left them): ${missing.join(', ')}`).toEqual([])
  expect(RECUTS.filter((_, i) => !used.has(i)).map((r) => r.from), 'a listed re-cut changes no hunk of 0353: take it off the list').toEqual([])
  // and no more rows than those: a hunk of the proof that is not the migration's would rebuild a body that never was
  expect(proof.match(/^ {2}\('[a-z_.]+\([a-z ,]*\)', \d+, \$h\$/gm) ?? []).toHaveLength(20)
  // the rule: a body other slices may re-cut is never held to a fixed digest
  expect(proof.match(/'[0-9a-f]{32}'/g) ?? [], 'proof 56 pins a body by an md5 literal').toEqual([])
  // the rebuild is a round trip, and the registry is left out of it
  expect(proof).toContain("where x.fn <> 'public.client_rpc_entry_points()'")
  expect(proof).toContain('does not come back to the live body')
})
