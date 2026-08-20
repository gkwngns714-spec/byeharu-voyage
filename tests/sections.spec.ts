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

test('a domain section depends on nothing above it', () => {
  const leaks = imports(path.join(SRC, 'domain'))
    .filter((r) => r.spec.startsWith('features/') || r.spec.startsWith('app/'))
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    leaks,
    `A domain section is reaching UP into a screen or the shell. A section is a part of the game ` +
      `and must be usable without any of them.\n` + leaks.join('\n'),
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
