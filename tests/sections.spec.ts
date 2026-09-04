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
// ── THE LAYERS, AND THE ONE DIRECTION DEPENDENCIES MAY POINT ───────────────────────────────────
//
//   src/lib/*       machinery under the game: rpc, db, format, geo. Knows nothing above it.
//   src/components  the design system. One entrance, and it knows nothing above it either.
//   src/domain/*    a part of the GAME: order, fleet, trade. Pure, no React, no store, no screen.
//   src/chart       HOW THE WORLD IS DRAWN. May use lib, domain and the design system.
//   src/features/*  a SCREEN. May use any of the above. NEVER another screen.
//
// Adding a section (skills, buffs, captains, prices…) means a new `src/domain/<name>/` with its own
// entrance, not a new file inside whichever screen happens to show it first.
//
// ── WHY `src/chart` IS A LAYER AND NOT ONE SCREEN'S FOLDER (added 2026-08-23) ──────────────────
// Every file in it was `src/features/map/`, which made the chart the Map tab's property. Then the
// owner asked for a small chart on the SAIL composer — "sail — a small map + current location on
// the left side" — and the FIRST test in this file correctly refused COMMAND an import of MAP.
//
// That refusal is the boundary working, and it is also the boundary's trap, which docs/SECTIONS.md
// states in as many words: forbidding a sideways import does not remove the need to share, it
// converts sharing into a SILENT COPY — and a copy imports nothing, so nothing in this file could
// ever see it. `PortPicker`, and `num`/`str`, are in the tree today for exactly that reason.
//
// The two alternative homes were both tried on paper and both fail on a rule already written below.
// The SVG layers cannot live in `src/components/chart/`, because "machinery knows nothing above it"
// forbids `components/**` importing `domain/**` and every layer needs `ChartModel` / `MapPort` /
// `PortRole`; rewriting each layer to take plain `{x, y, role}` props in order to get around that
// is the "adapter written to survive a boundary" docs/NO_SPAGHETTI.md §2 names as the tell that the
// boundary is in the wrong place. So the chart moved DOWN a layer, kept one entrance, and both
// screens compose it. MapScreen's composition did not change; its import paths did.

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

/**
 * Is this resolved specifier inside `folder`? A section is reachable BY ITS NAME as well as by a
 * path under it — `import '../../chart'` resolves to exactly `chart`, and `startsWith('chart')`
 * would also swallow a future `charts/` or `chartlet.ts`. One predicate, so no rule below has to
 * remember the trailing slash.
 */
const inFolder = (spec: string, folder: string) =>
  spec === folder || spec.startsWith(`${folder}/`)

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

// `domain` may compose `domain` and stand on `lib`. Everything else is above it — INCLUDING the
// chart, because a rule of the game that needs a picture to be proved is not a rule of the game.
// The list is written as what is FORBIDDEN rather than as what is allowed, so a new top-level
// folder is caught by the next test's shape rather than silently permitted here.
const ABOVE_DOMAIN = ['features', 'app', 'live', 'store', 'components', 'chart']

test('a domain section depends on nothing above it', () => {
  const leaks = imports(path.join(SRC, 'domain'))
    .filter((r) => ABOVE_DOMAIN.some((up) => inFolder(r.spec, up)))
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    leaks,
    `A domain section is reaching UP into a screen, the shell, the store, the design system or ` +
      `the chart. A section is a part of the GAME — it must be usable without any of them, and a ` +
      `rule that imports a component or a picture is a rule that cannot be proved without ` +
      `rendering one.\n` + leaks.join('\n'),
  ).toEqual([])
})

// ── ADDED 2026-08-22, with docs/NO_SPAGHETTI.md ────────────────────────────────────────────────
// The two rules below were already WRITTEN in docs/SECTIONS.md — "src/lib/* MACHINERY. Knows
// nothing above it" and "src/components/ui the design system. One import surface" — and neither
// was checked by anything. A rule that lives only in a doc is a rule that lasts until the next
// hurried afternoon, which is the sentence at the top of this file. Both stand at zero today.

test('machinery knows nothing above it', () => {
  const ABOVE_MACHINERY = ['domain', 'chart', 'features', 'app', 'live', 'store']
  const leaks = [...imports(path.join(SRC, 'lib')), ...imports(path.join(SRC, 'components'))]
    .filter((r) => ABOVE_MACHINERY.some((up) => inFolder(r.spec, up)))
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
    // The chart draws with the design system too, and a layer that hand-writes a control is how a
    // recipe reaches twelve copies. It is held to the same entrance as a screen.
    ...imports(path.join(SRC, 'chart')),
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

// ── ADDED 2026-08-23, WITH `src/chart` ─────────────────────────────────────────────────────────
// The chart got a layer of its own so that MAP and COMMAND could draw the SAME chart instead of
// each owning one (see this file's header for why the two obvious homes were both wrong). A layer
// with no edges is a folder, so here are its two edges. Both were broken on purpose and watched go
// red before they were trusted — a guard nobody has seen fail is a guard nobody should trust
// (docs/SECTIONS.md:8-9, docs/NO_SPAGHETTI.md §7).

test('the chart knows nothing above it', () => {
  // It may use `lib`, `domain` and the design system — it draws the GAME, so it is allowed to know
  // what a fleet is. It may not know that a screen, a shell, a store or a live world exists.
  //
  // `live/` is the sharp one and the reason this rule is worth having. Reading the world inside the
  // chart would make it impossible to draw one anywhere but the tab the store happens to be about,
  // and it would put `useWorld()` inside a component that renders on every pan. What the chart
  // needs from up there is a PARAMETER: MapScreen and the SAIL composer each read the store
  // themselves and hand over ports, legs and fleets.
  const ABOVE_CHART = ['features', 'app', 'live', 'store']
  const leaks = imports(path.join(SRC, 'chart'))
    .filter((r) => ABOVE_CHART.some((up) => inFolder(r.spec, up)))
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    leaks,
    `src/chart is a LAYER, under every screen and above the design system. An import pointing up ` +
      `into a screen, the shell, the store or src/live makes the chart the property of whatever it ` +
      `reached for — which is the state it was just carved out of. Whatever it needs from up ` +
      `there is a PARAMETER, not an import.\n` + leaks.join('\n'),
  ).toEqual([])
})

test('the chart has one entrance', () => {
  const files = readdirSync(path.join(SRC, 'chart'))
  expect(files, 'src/chart has no index.ts — a layer without an entrance is a folder').toContain(
    'index.ts',
  )

  // Nothing outside reaches past it. This is the half that keeps the SVG layers, the label planner
  // and the coastline builder free to change: they are exported to NOBODY, and `ChartCanvas` is the
  // one thing that composes them, which is what makes the paint order a rule instead of a habit.
  const deep = [
    ...imports(path.join(SRC, 'features')),
    ...imports(path.join(SRC, 'app')),
    ...imports(path.join(SRC, 'live')),
    ...imports(path.join(SRC, 'store')),
  ]
    .filter((r) => {
      const m = /^chart\/(.+)$/.exec(r.spec)
      return m !== null && m[1] !== 'index'
    })
    .map((r) => `${r.from}  ->  ${r.spec}`)

  expect(
    deep,
    `Something reached past src/chart's entrance into its internals. Import '../../chart', not a ` +
      `file inside it — and if what you need is not exported there, export it there. A layer ` +
      `nobody can reach through the entrance is a layer the next screen copies a file out of, ` +
      `which is the silent copy no import check can see (docs/NO_SPAGHETTI.md §2).\n` +
      deep.join('\n'),
  ).toEqual([])
})

// ── ADDED 2026-09-04, WITH THE ROADSTEAD LAYER (0076) ──────────────────────────────────────────
// A new SVG layer is the moment the rule above is easiest to break, because a layer is a component
// and a component looks exportable. docs/SECTIONS.md:108 says what it costs: the layers are
// "exported to nobody", and `ChartCanvas` being their ONLY composer "is what makes the paint order
// a rule rather than a habit". Export `RoadsteadsLayer` and a screen can mount the roads with no
// tracks under them and no port marks over them — two paint orders, which can disagree.
//
// This is written as a rule about ONE file rather than a general one because it can be: the layers
// are a closed set that changes about twice a year, and a general "no .tsx in src/chart is
// exported" rule would have to know which .tsx files are surfaces (`ChartCanvas`, `SmallChart`,
// `Minimap`, `ViewControls`) and which are layers, which is a list either way.
test('the roadstead layer is furniture: ChartCanvas composes it and nobody else can reach it', () => {
  const entrance = readFileSync(path.join(SRC, 'chart', 'index.ts'), 'utf8')
  expect(
    entrance.includes('RoadsteadsLayer'),
    `src/chart/index.ts exports RoadsteadsLayer. The SVG layers are exported to nobody — what a ` +
      `caller may have is the DECISION (roadsteadMarks), not the paint.`,
  ).toBe(false)

  const importers = imports(path.join(SRC, 'chart'))
    .filter((r) => r.spec === 'chart/RoadsteadsLayer')
    .map((r) => r.from)
  expect(
    importers,
    `RoadsteadsLayer is imported by something other than ChartCanvas. There is one composer, and ` +
      `that is what makes the paint order — coastline, tracks, roadsteads, ports, fleets, names — ` +
      `a rule instead of a habit.`,
  ).toEqual(['chart/ChartCanvas.tsx'])
})
