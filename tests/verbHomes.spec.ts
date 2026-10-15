// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A VERB'S DOORWAY BELONGS WHERE ITS ACT HAPPENS — the rule with teeth
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-09: "In command, there are so many things, like buy, sell, fit, take etc.
// Buy and sell should be in port - market. Get it? they should be located accordingly at
// different locations - the command."
//
// COMMAND drew twelve verb tiles in one grid and a question for whichever was pressed. Every one
// of those acts happens somewhere — a quay, a shed, a workstation, a yard, an inn, a shipyard, the
// sea — and that somewhere has a face. So the grid is gone, and this spec is what keeps it gone:
//
//   1. COMMAND composes no verb. It imports none of the composing apparatus.
//   2. No screen hands a VERB to COMMAND. The draft may still be pointed at a HULL (FLEETS'
//      "Command her" does that); a `verb:` in a hand-off is a doorway that leads nowhere.
//   3. The stepped question (HIRE · REPAIR · PROVISION) has ONE home: the Inn, the Shipyard and the
//      quay are the only faces that import `StepQuestion` or `useStepOrder`. A second
//      `checked`/`issuing` pair for a verb is the duplication docs/NO_SPAGHETTI.md §1 names.
//
// Static, like tests/sections.spec.ts: it reads the tree off disk, so it runs without a browser
// and fails on the commit that reintroduces the grid rather than on the playtest that finds it.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const SRC = path.resolve(process.cwd(), 'src')

function files(dir: string): string[] {
  const out: string[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (/\.tsx?$/.test(name)) out.push(full)
    }
  }
  walk(dir)
  return out
}

const rel = (f: string) => path.relative(SRC, f).split(path.sep).join('/')

test('COMMAND composes no verb — it keeps whose orders, and her queue', () => {
  // The apparatus a verb is composed with. Any one of these in features/command is a doorway
  // coming back to the screen the owner called a dump.
  const COMPOSING = [
    /\bTradeTile\b/,
    /\bTradeTray\b/,
    /\bStepper\b/,
    /\bSmallChart\b/,
    /from '\.\.\/\.\.\/chart'/,
    /\buseTrade\b/,
    /\bchooseVerb\b/,
    /\bfindVerb\(/,
    /\borderText\(/,
    /\bpreview\(/,
  ]
  const offenders: string[] = []
  for (const f of files(path.join(SRC, 'features', 'command'))) {
    const text = readFileSync(f, 'utf8')
    for (const re of COMPOSING) {
      if (re.test(text)) offenders.push(`${rel(f)}  ${re.source}`)
    }
  }
  expect(
    offenders,
    `COMMAND is composing a verb again. Its doorway belongs where the act happens — a PORT face for ` +
      `a building's act, the chart for SAIL. See src/features/command/CommandScreen.tsx.\n` +
      offenders.join('\n'),
  ).toEqual([])
})

test('no screen hands a VERB to COMMAND', () => {
  const offenders: string[] = []
  for (const f of files(path.join(SRC, 'features'))) {
    const text = readFileSync(f, 'utf8')
    // A hand-off or a "command her" press whose intent literal carries a verb.
    for (const m of text.matchAll(/\b(handOff|command)\(\{[^}]*\bverb\s*:/g)) {
      offenders.push(`${rel(f)}  ${m[0].slice(0, 60)}`)
    }
  }
  expect(
    offenders,
    `A screen is handing a verb to COMMAND, which composes nothing. Compose it on the face of the ` +
      `building whose act it is (features/port) or on the chart (features/map).\n` + offenders.join('\n'),
  ).toEqual([])
})

test('the stepped question has one home — the three building faces', () => {
  // 2026-10-16: the Inn face (PortInn) and the stepped question it composes moved from
  // features/port to src/live, because the map's city panel draws the SAME Inn as PORT's Inn tab
  // (owner, 2026-10-15: "inn should be a place where we can hire crew and buy provisions"), and
  // tests/sections.spec.ts forbids MAP importing a PORT file. So this reads src/live as well as the
  // screens, and names the composers by FILE — the Inn, the Shipyard, the quay — which is tighter
  // than the folder it replaced: a fourth face composing a verb fails here wherever it is put.
  const HOMES = ['live/PortInn.tsx', 'features/port/PortShipyard.tsx', 'features/port/PortTrade.tsx']
  const importers: string[] = []
  for (const f of [...files(path.join(SRC, 'features')), ...files(path.join(SRC, 'live'))]) {
    const text = readFileSync(f, 'utf8')
    // IMPORTS, not mentions: CommandScreen's header names the file it sent these to, and that is
    // the record, not a doorway. The two files that ARE the apparatus import each other.
    if (/from '[^']*(StepQuestion|useStepOrder)'/.test(text)) {
      importers.push(rel(f))
    }
  }
  const composers = importers.filter((p) => p !== 'live/StepQuestion.tsx' && p !== 'live/useStepOrder.ts')
  expect(composers.length, 'nothing composes StepQuestion — has HIRE / REPAIR / PROVISION lost its doorway?').toBeGreaterThan(0)
  const outside = composers.filter((p) => !HOMES.includes(p))
  expect(
    outside,
    `StepQuestion / useStepOrder is composed outside the Inn, the Shipyard and the quay. HIRE, ` +
      `REPAIR and PROVISION each have ONE doorway; a second composer is a second ` +
      `\`checked\`/\`issuing\` pair for the same verb.\n` + outside.join('\n'),
  ).toEqual([])
})
