// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECTIONS — every part of the game is its own, and none of them reach into each other
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER'S RULE, 2026-08-20: "organize them separately and independently so that individual
// have its own separate section ... to have no spaghetti of whatsoever."
//
// A rule that lives only in a comment is a rule that lasts until the next hurried afternoon. This
// spec is the rule with teeth: it reads the import graph off disk and fails when a boundary is
// crossed, so the shape cannot rot quietly.
//
// ── WHAT WAS ACTUALLY WRONG (measured before it was fixed) ─────────────────────────────────────
// Nine imports had one SCREEN reaching into another screen's internals:
//
//   port/PortScreen      -> command/commandDraft, command/orderText, fleets/worldGate, fleets/fleetDerive
//   fleets/FleetsScreen  -> command/commandDraft
//   market/handOff       -> command/commandDraft
//   ledger/LedgerScreen  -> fleets/worldGate
//
// None of those were bad code; every one was a screen borrowing something that was never really
// the lender's. "How much hold is free" is a property of a FLEET, not of the tab that draws one.
// The order being composed belongs to the ORDER, not to the Command tab. So the shared things
// moved out into sections of their own and the borrowing stopped being a border crossing.
//
// ── THE THREE LAYERS, AND THE ONE DIRECTION DEPENDENCIES MAY POINT ─────────────────────────────
//
//   src/domain/*    a part of the GAME: order, fleet. Pure, no React, no store, no screen.
//   src/features/*  a SCREEN. May use any domain, any lib, any component. NEVER another screen.
//   src/lib/*       machinery under the game: rpc, db, format, geo. Knows nothing above it.
//
// Adding a section (skills, buffs, captains, prices…) means a new `src/domain/<name>/` with its own
// entrance, not a new file inside whichever screen happens to show it first.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const SRC = path.resolve(process.cwd(), 'src')

interface Ref {
  from: string
  spec: string
}

/** Every `from '...'` in every TS/TSX file under `dir`, with the importing file's repo path. */
function imports(dir: string): Ref[] {
  const out: Ref[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) {
        walk(full)
        continue
      }
      if (!/\.tsx?$/.test(name)) continue
      const rel = path.relative(SRC, full).split(path.sep).join('/')
      const text = readFileSync(full, 'utf8')
      for (const m of text.matchAll(/from\s+'([^']+)'/g)) {
        // Resolve the specifier against the importing file, so '../../domain/order' becomes
        // 'domain/order' — the comparison is between PLACES, not between spellings.
        const spec = m[1]
        if (!spec.startsWith('.')) continue
        const resolved = path
          .relative(SRC, path.resolve(path.dirname(full), spec))
          .split(path.sep)
          .join('/')
        out.push({ from: rel, spec: resolved })
      }
    }
  }
  walk(dir)
  return out
}

const featureOf = (p: string) => (p.startsWith('features/') ? p.split('/')[1] : null)

test('no screen imports another screen', () => {
  const crossings = imports(path.join(SRC, 'features'))
    .filter((r) => {
      const a = featureOf(r.from)
      const b = featureOf(r.spec)
      return a !== null && b !== null && a !== b
    })
    .map((r) => `${r.from}  ->  ${r.spec}`)

  // The message carries the fix, because whoever trips this will not have read the header.
  expect(
    crossings,
    `A screen is reaching into another screen. Whatever is being shared is not that screen's — ` +
      `move it into a section of its own under src/domain/<name>/ and import it from there.\n` +
      crossings.join('\n'),
  ).toEqual([])
})

// `domain` may compose `domain` and stand on `lib`. Everything else is above it. The list is
// written as what is FORBIDDEN rather than as what is allowed, so a new top-level folder is
// caught by the next test's shape rather than silently permitted here.
const ABOVE_DOMAIN = ['features/', 'app/', 'live/', 'store/', 'components/']

test('a domain section depends on nothing above it', () => {
  const leaks = imports(path.join(SRC, 'domain'))
    .filter((r) => ABOVE_DOMAIN.some((up) => r.spec.startsWith(up)))
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    leaks,
    `A domain section is reaching UP into a screen, the shell, the store or the design system. A ` +
      `section is a part of the GAME — it must be usable without any of them, and a rule that ` +
      `imports a component is a rule that cannot be proved without rendering one.\n` +
      leaks.join('\n'),
  ).toEqual([])
})

// ── ADDED 2026-08-22, with docs/NO_SPAGHETTI.md ────────────────────────────────────────────────
// The two rules below were already WRITTEN in docs/SECTIONS.md — "src/lib/* MACHINERY. Knows
// nothing above it" and "src/components/ui the design system. One import surface" — and neither
// was checked by anything. A rule that lives only in a doc is a rule that lasts until the next
// hurried afternoon, which is the sentence at the top of this file. Both stand at zero today.

test('machinery knows nothing above it', () => {
  const ABOVE_MACHINERY = ['domain/', 'features/', 'app/', 'live/', 'store/']
  const leaks = [...imports(path.join(SRC, 'lib')), ...imports(path.join(SRC, 'components'))]
    .filter((r) => ABOVE_MACHINERY.some((up) => r.spec.startsWith(up)))
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    leaks,
    `src/lib and src/components are the layer everything else stands ON. An import pointing back ` +
      `up makes a cycle, and a cycle is how "which of these two owns the rule?" stops having an ` +
      `answer. Whatever is needed up there is a PARAMETER, not an import.\n` + leaks.join('\n'),
  ).toEqual([])
})

test('the design system has one entrance', () => {
  // src/components/ui/index.ts:1-2 — "the single import surface. Screens import from here, never
  // from the individual files, so the set stays one authority." That is what lets a primitive be
  // renamed, split or re-skinned without touching a screen — and what makes `buttonClasses` the
  // only place a chip recipe can live.
  const deep = [
    ...imports(path.join(SRC, 'features')),
    ...imports(path.join(SRC, 'app')),
    ...imports(path.join(SRC, 'live')),
    ...imports(path.join(SRC, 'domain')),
    ...imports(path.join(SRC, 'store')),
  ]
    .filter((r) => {
      const m = /^components\/ui\/(.+)$/.exec(r.spec)
      return m !== null && m[1] !== 'index'
    })
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    deep,
    `Something imported a design-system file directly instead of the design system. Import from ` +
      `'.../components/ui' — if what you need is not exported there, export it there, because a ` +
      `primitive nobody can reach through the entrance is a primitive the next screen will ` +
      `hand-write instead (twelve times, on the record: buttonStyles.ts:31-35).\n` + deep.join('\n'),
  ).toEqual([])
})

test('every domain section has one entrance', () => {
  const sections = readdirSync(path.join(SRC, 'domain')).filter((n) =>
    statSync(path.join(SRC, 'domain', n)).isDirectory(),
  )
  expect(sections.length, 'src/domain exists but holds no sections').toBeGreaterThan(0)

  for (const s of sections) {
    const files = readdirSync(path.join(SRC, 'domain', s))
    expect(files, `src/domain/${s} has no index.ts — a section without an entrance is a folder`).toContain(
      'index.ts',
    )
  }

  // ...and nothing outside a section reaches past its entrance into a file inside it.
  const deep = [...imports(path.join(SRC, 'features')), ...imports(path.join(SRC, 'app'))]
    .filter((r) => {
      const m = /^domain\/([^/]+)\/(.+)$/.exec(r.spec)
      return m !== null && m[2] !== 'index'
    })
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    deep,
    `Something reached past a section's entrance into its internals. Import the section ` +
      `('../../domain/fleet'), not a file inside it — the entrance is what keeps the inside free ` +
      `to change.\n` + deep.join('\n'),
  ).toEqual([])
})
