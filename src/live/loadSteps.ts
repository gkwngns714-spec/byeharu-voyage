import type { LoadStep } from '../components/ui'
import type { T } from '../lib/i18n'

// THE WORLD'S LOADING STEPS, SAID ONCE (owner row 255, 2026-10-31: *"when reloading, for example opening the city, or loading
// the map, show percentage of its loading time"*). The store's `boot` (worldStore.ts) counts the boot's REAL completions — 1 the
// served world (its bundle and snapshot), 2 the sea raster, 3 the first beat read (fleets, player, ledger, routes) — and this
// turns them into the meter's first three steps, with the words every screen shares. A screen appends its own served read as the
// last step (the city its hall, the map its roster of the ships at sea) and hands the list to the one `LoadMeter`
// (components/ui/LoadMeter.tsx). Never a timer, never an estimate. Until the drive audit (2026-11-08, D6) the city alone
// composed this and the map had a plain line.
export function worldLoadSteps(t: T, boot: number): LoadStep[] {
  return [
    { id: 'world', label: t('common.loadWorld'), done: boot >= 1 },
    { id: 'sea', label: t('common.loadSea'), done: boot >= 2 },
    { id: 'fleets', label: t('common.loadFleets'), done: boot >= 3 },
  ]
}
