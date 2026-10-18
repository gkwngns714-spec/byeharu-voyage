import type { WorkKind } from '../lib/rpc'

/** A city work's one player word (moved 2026-10-18 out of CityTownHall.tsx): the Town Hall and the desk's Invest
 *  face print it. */
export const WORK_NAME: Record<WorkKind, string> = {
  docks: 'Docks',
  market: 'Market',
  production: 'Workshops',
  inn: 'Inn',
}
