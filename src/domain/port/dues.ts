// WHAT A HARBOUR ASKS A COMPANY (0237, docs/CLOSED_ECONOMY.md §4c) — the one reading of a served `dues`
// (`public.port_dues`): "Tax 2× (rival) · Dock fee 110". Pure; every figure is the server's.

import type { PortDues, RegardBand } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import { t, type TKey } from '../../lib/i18n'

const STANCE: Record<PortDues['stance'], TKey> = {
  home: 'town.st_home',
  ally: 'town.st_ally',
  peace: 'town.st_peace',
  rival: 'town.st_rival',
  war: 'town.st_war',
}

/** 0318: the bands, as the player reads them. The Relationship figure and the hall's line both read this one table. */
const BAND: Record<RegardBand, TKey> = {
  honoured: 'town.band_honoured',
  friendly: 'town.band_friendly',
  neutral: 'town.band_neutral',
  wary: 'town.band_wary',
  hostile: 'town.band_hostile',
}

export function regardBandWord(band: RegardBand): string {
  return t(BAND[band])
}

/** "Tax 2× (rival)" — the country factor on her profit tax there. */
export function taxFactorWords(d: PortDues): string {
  return t('town.taxFactor', { x: String(d.factor), stance: t(STANCE[d.stance]) })
}

/** "Tax 2× (rival) · Dock fee 110" — the factor and the dock fee; lit (0318), "· Wary -180" after them. */
export function duesWords(d: PortDues): string {
  const line = t('town.dues', { x: String(d.factor), stance: t(STANCE[d.stance]), fee: formatDucats(d.fee) })
  return d.regard ? `${line} · ${regardBandWord(d.regard.band)} ${formatInt(d.regard.score)}` : line
}
