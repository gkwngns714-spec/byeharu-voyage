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
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
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
  // 2026-10-26, OWNER ROW 229: the doorway is THE trade panel of the mirrored Buy / Sell screen
  // (features/command/buysell/TradePanel.tsx) — the same `useTrade` act, its own stepper; DeskTrade.tsx is gone.
  const DOORWAYS = new Set(['features/command/buysell/TradePanel.tsx'])
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
      `a building's act, the chart for SAIL. See tests/hq.desk.spec.ts.\n` +
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
  // H3 (2026-11-24): the quay's own resupply row went with the Office's market (PortTrade); the Inn's is the one.
  const HOMES = ['live/PortInn.tsx', 'live/PortShipyard.tsx']
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

// EVERY BUILDING FACE HAS ONE HOME, ON HQ (H3 `desk-into-hq`, 2026-11-24; docs/design/simplify-2026-11-24.md S3). Until then the
// Office's City face composed every one of them a second time (and PORT a third, before 2026-10-18). The Office and the Trade desk
// are deleted; each face is ONE component in src/live, composed by HQ's plates (features/city) or HQ's sheet (app/HqSheet.tsx):
//   Market (buy, sell, the best sale, requests) MarketFace · City hall (invest, donate) CityHallPanel, Invest's CityTownHall ·
//   Production PortProduction · Craft PortWorkstation · Inn (hire, resupply, captains) PortInn · Build PortYard ·
//   Repair PortShipyard · Skills PortAcademy · Gear PortGear · the fair QuayFair · a tow TowNote.
test('every building face is one component in src/live, and HQ composes each one', () => {
  const FACES = ['CityTownHall', 'PortWorkstation', 'PortInn', 'PortYard', 'PortShipyard', 'PortAcademy', 'PortGear', 'PortProduction', 'QuayFair', 'TowNote']
  const hq = [
    ...files(path.join(SRC, 'features', 'city')),
    path.join(SRC, 'app', 'HqSheet.tsx'),
    path.join(SRC, 'features', 'command', 'invest', 'Invest.tsx'),
  ]
    .map((f) => readFileSync(f, 'utf8'))
    .join(' ')
  const missing = FACES.filter((name) => !new RegExp(`import [{][^}]*[ ,{]${name}[ ,}][^}]*[}] from '[./]+/live/`).test(hq))
  expect(missing, `HQ does not compose: ${missing.join(', ')}`).toEqual([])
  // the one trade list is HQ's Market plate, and the one trade sheet is HQ's
  expect(readFileSync(path.join(SRC, 'features', 'city', 'CityFace.tsx'), 'utf8'), 'HQ has no Market plate').toContain("import { MarketFace } from './MarketFace'")
  expect(readFileSync(path.join(SRC, 'app', 'HqSheet.tsx'), 'utf8'), 'HQ has no trade sheet').toContain("import { TradePanel } from '../features/command/buysell/TradePanel'")
  // the deleted second homes stay deleted
  for (const gone of ['features/command/city/City.tsx', 'features/command/OfficeScreen.tsx', 'features/command/CommandScreen.tsx', 'live/PortTrade.tsx'])
    expect(existsSync(path.join(SRC, gone)), `${gone} is back: a second home for a building's act`).toBe(false)
  // and no screen keeps a building face of its own
  const portFaces = files(path.join(SRC, 'features')).filter((f) =>
    /\/(Port(Trade|Town|Production|Forge|Workstation|Yard|Shipyard|Academy|Fair)|CityTownHall|TownHallInfluence)\.tsx$/.test(f.split(path.sep).join('/')),
  )
  expect(portFaces.map(rel), 'a building face lives in a screen again').toEqual([])
})
