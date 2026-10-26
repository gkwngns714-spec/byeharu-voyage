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
  // 2026-10-18 — THE OWNER REVERSED ROW 73 (docs/COMMAND_DESK.md, the table at its head): *"delete port
  // tab, and focus on command tab"*. The desk's ONE trade doorway — the good page's Buy / Sell cell for the
  // city the fleet is docked at — composes THE trade tray (features/command/markets/DeskTrade.tsx), the
  // same tray and the same door PORT's board uses. That file is the exception, by name; every other file
  // under features/command still composes no verb. D5 rewrites this rule to COMMAND_DESK §2.2.
  const DOORWAYS = new Set(['features/command/markets/DeskTrade.tsx'])
  // 2026-10-25 — OWNER ROW 183: *"It should show map (without npcs or name of the cities that aren't
  // associated with the route/plan"*. The Plans face's chart is a PICTURE of the plan, not a doorway:
  // `SmallChart` takes no tap (its header, point 1), so it composes nothing; the plan's SAIL lines are still
  // written by planLines.ts and sent through cmd.issue_lines, as before. Only `SmallChart`, only in this file.
  const PICTURES: Record<string, readonly string[]> = {
    // 2026-10-26, OWNER ROWS 217 AND 218: the chart moved to the map on top of the Buy and Sell faces
    // (plans/TradeMap.tsx), and a harbour pressed on it SELECTS the city the faces read — a view change through
    // the Map tab's own hit test; it orders nothing.
    'features/command/plans/TradeMap.tsx': [/\bSmallChart\b/.source],
  }
  const offenders: string[] = []
  for (const f of files(path.join(SRC, 'features', 'command'))) {
    if (DOORWAYS.has(rel(f))) continue
    const text = readFileSync(f, 'utf8')
    for (const re of COMPOSING) {
      if (PICTURES[rel(f)]?.includes(re.source)) continue
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
  // 2026-10-18 (docs/COMMAND_DESK.md D5): the Shipyard and the quay moved to src/live with every building face,
  // so PORT (until D8) and the desk's City face compose ONE copy of each.
  const HOMES = ['live/PortInn.tsx', 'live/PortShipyard.tsx', 'live/PortTrade.tsx']
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

// 2026-10-18 — EVERY VERB PORT CARRIED HAS A HOME ON COMMAND (docs/COMMAND_DESK.md §2.2, D5; the gate D8 deletes
// PORT behind). The owner: *"delete port tab, and focus on command tab"*. Each building face is ONE component in
// src/live, and the desk's City face composes every one of them, so PORT's folder holds no face of its own:
//   Trade (buy · sell · bargain · basket · requests · resupply) PortTrade · Town PortTown · Town Hall (invest,
//   donate, the purse) CityTownHall · Storage PortStorage · Craft PortWorkstation · Inn (hire, dismiss, resupply,
//   captains) PortInn · Build PortYard · Repair PortShipyard · Skills PortAcademy · the fair QuayFair · a tow TowNote.
test("every building face is one component in src/live, and the desk's City face composes each one", () => {
  const FACES = ['PortTrade', 'PortTown', 'CityTownHall', 'PortStorage', 'PortWorkstation', 'PortInn', 'PortYard',
    'PortShipyard', 'PortAcademy', 'QuayFair', 'TowNote']
  const city = readFileSync(path.join(SRC, 'features', 'command', 'city', 'City.tsx'), 'utf8')
  const missing = FACES.filter((name) => !city.includes(`import { ${name} } from '../../../live/`))
  expect(missing, `the desk's City face does not compose: ${missing.join(', ')}`).toEqual([])
  // and no screen keeps a building face of its own (PORT's folder is its screen and its chrome)
  const portFaces = files(path.join(SRC, 'features')).filter((f) =>
    /\/(Port(Trade|Town|Storage|Workstation|Yard|Shipyard|Academy|Fair)|CityTownHall|TownHallInfluence)\.tsx$/.test(f.split(path.sep).join('/')),
  )
  expect(portFaces.map(rel), 'a building face lives in a screen again').toEqual([])
})
