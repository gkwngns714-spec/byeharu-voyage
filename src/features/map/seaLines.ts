import { translate, type Locale } from '../../lib/i18n'
import { formatInt, NBSP } from '../../lib/format'
import type { SeaWall } from '../../lib/rpc'

// A SEA IN ONE SHORT LINE (2026-11-15 owner: shorter words, "just tell me what i have, and what is required"), for the
// map's tight places: a zone's name on the chart, a city's sea in its tray head, a route shut by a sea.
//
//   open:   Title 2 · Waves 12        (what it asks; a wave ask of 0 asks nothing and is left out)
//   closed: Title 1 / 2 · Waves 8 / 30   (hers / its ask, only the asks the server says are short)
//
// Which ask is short is the server's (0396, lib/rpc/seaWall.ts): nothing is compared here. On a world that does not
// say, both asks are printed beside both of hers.

const pair = (have: number | null, need: number) => `${have === null ? '—' : formatInt(have)}${NBSP}/${NBSP}${formatInt(need)}`

/** What an open sea asks. */
export function seaAsksLine(locale: Locale, zone: { title_min: number; wave_min: number }): string {
  const out = [translate(locale, 'seas.asksTitle', { n: formatInt(zone.title_min) })]
  if (zone.wave_min > 0) out.push(translate(locale, 'seas.asksWaves', { n: formatInt(zone.wave_min) }))
  return out.join(' · ')
}

/** What a closed sea lacks: hers / its ask, for each ask the server calls short. */
export function seaShortLine(locale: Locale, wall: SeaWall): string {
  const out: string[] = []
  if (wall.shortTitle !== false) out.push(translate(locale, 'seas.asksTitle', { n: pair(wall.title, wall.needsTitle) }))
  if (wall.shortWave !== false) out.push(translate(locale, 'seas.asksWaves', { n: pair(wall.wave, wall.needsWave) }))
  return out.length > 0 ? out.join(' · ') : translate(locale, 'seas.closedTag')
}
