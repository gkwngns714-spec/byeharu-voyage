import type { IconName } from '../components/ui'
import type { TKey } from '../lib/i18n'
import { num, str } from '../lib/json'
import type { LedgerEvent, SeaChoiceKind } from '../lib/rpc'

// 0486 (roadmap 2026-11-23 slice 16): CHOICES AT SEA, as every face reads them. The marks (each event's glyph and word, each option's) live
// here once, for HQ's decision card, While away and the arrival card; and a SEA_CHOICE event (public.sea_choice_settle, at her arrival) as
// the arrival card and the history read it. Nothing is computed: the server's option, end and coin.

export const SEA_KIND_ICON: Record<SeaChoiceKind, IconName> = { storm: 'storm', wreck: 'hull', sail: 'sailing' }
export const SEA_KIND_WORD: Record<SeaChoiceKind, TKey> = { storm: 'hq.seaStorm', wreck: 'hq.seaWreck', sail: 'hq.seaSail' }

const OPTION_ICON: Record<string, IconName> = {
  shelter: 'anchor',
  push: 'waves',
  pass: 'sailing',
  salvage: 'crate',
  dive: 'search',
  away: 'compass',
  hail: 'pact',
  chase: 'cannon',
}

/** An option's glyph (an unknown key, a later table's: the compass). */
export function seaOptionIcon(key: string): IconName {
  return OPTION_ICON[key] ?? 'compass'
}

/** An option's word key (an unknown key falls back to the event's own word at the caller). */
export function seaOptionWord(key: string): TKey | null {
  return key in OPTION_ICON ? (`hq.sea_${key}` as TKey) : null
}

export interface SeaEnd {
  id: string
  fleet: string | null
  kind: SeaChoiceKind
  option: string
  good: boolean
  /** The coin that moved (a loss negative), cut to the purse that paid it. */
  amount: number
  by: 'you' | 'default'
}

/** A SEA_CHOICE event's line; null for any other event. */
export function seaChoiceOf(e: LedgerEvent): SeaEnd | null {
  if (e.kind !== 'SEA_CHOICE') return null
  const p = e.payload
  const kind = str(p, 'kind')
  return {
    id: e.id,
    fleet: str(p, 'fleet'),
    kind: kind === 'storm' || kind === 'wreck' || kind === 'sail' ? kind : 'storm',
    option: str(p, 'option') ?? '',
    good: p?.good === true,
    amount: num(p, 'amount') ?? 0,
    by: str(p, 'by') === 'default' ? 'default' : 'you',
  }
}
