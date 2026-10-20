import type { WorkKind } from '../lib/rpc'
import { wordTable } from '../lib/i18n'

/** A city work's one player word (moved 2026-10-18 out of CityTownHall.tsx): the Town Hall and the desk's Invest
 *  face print it. */
export const WORK_NAME: Readonly<Record<WorkKind, string>> = wordTable({
  docks: 'town.w_docks',
  market: 'town.w_market',
  production: 'town.w_production',
  inn: 'town.w_inn',
})
