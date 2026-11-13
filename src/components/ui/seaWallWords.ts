import { properName, translate, type Locale } from '../../lib/i18n'
import type { SeaWall } from '../../lib/rpc'

// A CLOSED SEA IN PLAIN WORDS — THE ONE WORDING of the sea rule's refusal, in both languages.
//
//   The Western Ocean is closed to this fleet. It asks wave resistance 30. This fleet has 12.
//   Sail a sturdier ship, or fit anchors and planking.
//
// The figures are the server's (lib/rpc/seaWall.ts): which ask is short is its answer (0376), never worked out here.
// On a world that does not say which is short yet, both asks are printed beside both of hers and no advice is given.
// Read by `Note` (every refusal a screen prints), the Map's place tray, Trade and the Codex.

/** The sea's name as the viewer reads it (Korean where the chart has one). */
export function seaName(locale: Locale, wall: Pick<SeaWall, 'zoneName'>): string {
  return properName('sea', wall.zoneName, wall.zoneName, locale)
}

/** What the sea asks that she does not hold, and nothing else: one or two short sentences. */
export function seaWallAsks(locale: Locale, wall: SeaWall): string {
  const out: string[] = []
  if (wall.shortTitle === null || wall.shortWave === null) {
    return wall.title !== null && wall.wave !== null
      ? translate(locale, 'seas.wallBoth', { needTitle: wall.needsTitle, needWaves: wall.needsWave, title: wall.title, waves: wall.wave })
      : translate(locale, 'seas.wallAsks', { needTitle: wall.needsTitle, needWaves: wall.needsWave })
  }
  if (wall.shortTitle) out.push(translate(locale, 'seas.wallTitle', { need: wall.needsTitle, have: wall.title ?? '—' }))
  if (wall.shortWave) out.push(translate(locale, 'seas.wallWaves', { need: wall.needsWave, have: wall.wave ?? '—' }))
  return out.join(' ')
}

/** What to do about it; empty when the server did not say which ask is short. */
export function seaWallFix(locale: Locale, wall: SeaWall): string {
  const out: string[] = []
  if (wall.shortTitle) out.push(translate(locale, 'seas.fixTitle', { need: wall.needsTitle }))
  if (wall.shortWave) out.push(translate(locale, 'seas.fixWaves'))
  return out.join(' ')
}

/** The whole wall: the sea, what it asks, what to do. */
export function seaWallWords(locale: Locale, wall: SeaWall): string {
  return [translate(locale, 'seas.wallHead', { sea: seaName(locale, wall) }), seaWallAsks(locale, wall), seaWallFix(locale, wall)]
    .filter((s) => s !== '')
    .join(' ')
}

/** The wall as one short tag for a tight row: `Needs title 4`, `Needs waves 30`, or `Closed`. */
export function seaWallTag(locale: Locale, wall: SeaWall): string {
  if (wall.shortTitle) return translate(locale, 'seas.closedTitle', { n: wall.needsTitle })
  if (wall.shortWave) return translate(locale, 'seas.closedWaves', { n: wall.needsWave })
  return translate(locale, 'seas.closedTag')
}
