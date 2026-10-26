// WHAT A HARBOUR ASKS A COMPANY (0237, docs/CLOSED_ECONOMY.md §4c) — the one reading of a served `dues`
// (`public.port_dues`): "Tax 2× (rival) · Dock fee 110". Pure; every figure is the server's.

import type { PortDues } from '../../lib/rpc'
import { formatDucats } from '../../lib/format'
import { t, type TKey } from '../../lib/i18n'

const STANCE: Record<PortDues['stance'], TKey> = {
  home: 'town.st_home',
  ally: 'town.st_ally',
  peace: 'town.st_peace',
  rival: 'town.st_rival',
  war: 'town.st_war',
}

/** "Tax 2× (rival)" — the country factor on her profit tax there. */
export function taxFactorWords(d: PortDues): string {
  return t('town.taxFactor', { x: String(d.factor), stance: t(STANCE[d.stance]) })
}

/** "Tax 2× (rival) · Dock fee 110" — the factor and the dock fee. */
export function duesWords(d: PortDues): string {
  return t('town.dues', { x: String(d.factor), stance: t(STANCE[d.stance]), fee: formatDucats(d.fee) })
}
