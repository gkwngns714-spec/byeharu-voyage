import { formatRealDuration } from '../../lib/format'
import { properName, translate, translateMaybe, type Locale } from '../../lib/i18n'
import type { LandProgress } from '../../lib/rpc'

// THE LAND'S WORDS (0455): a site's name, a region's, a phase's, a span of seconds. Every figure is the server's (`world.land`); this
// file holds only the words around it. Kept beside the screen: the Land tab is their one reader (the arrival card's "Party: 86 Iron"
// line is a later slice, and when it comes these move to src/live/ where both can reach them).

/** A region's name in the reader's language: names/realms.ts over the served English (`world.land().regions`), else the code. */
export function regionWord(locale: Locale, code: string | null, regions: Readonly<Record<string, string>>): string {
  if (!code) return ''
  return properName('region', code, regions[code] ?? code, locale)
}

/** A site: its own written name (`land.site_<REGION>_<ground>`), else "<region> · Mines". */
export function siteWord(locale: Locale, region: string | null, ground: string, regions: Readonly<Record<string, string>>): string {
  if (!region) return ''
  return (
    translateMaybe(locale, 'land', `site_${region}_${ground}`) ??
    translate(locale, 'land.siteOf', { region: regionWord(locale, region, regions), ground: translateMaybe(locale, 'land', `ground_${ground}`) ?? ground })
  )
}

/** Where the party is, in one or two words. */
export function phaseWord(locale: Locale, phase: LandProgress['phase']): string {
  return translateMaybe(locale, 'land', `phase_${phase}`) ?? phase
}

/** A span the server served in seconds, in the game's real-time words ("4.7 min", "1 h 39 min"). */
export function spanWord(seconds: number): string {
  return formatRealDuration(seconds * 1000)
}
