import { formatInt, formatRealDuration } from '../../lib/format'
import { properName, translate, translateMaybe, type Locale } from '../../lib/i18n'
import type { LandProgress } from '../../lib/rpc'

// THE LAND'S WORDS (0455): a site's name, a region's, a phase's, a span of seconds. Every figure is the server's (`world.land`); this
// file holds only the words around it. Kept beside the screen: the Land tab is their one reader. The While away card's land line
// (0458, src/app/AwayCard.tsx) needs none of them: a good's name, the skill's name and the word Party are the dictionaries' own.

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

/** Where the party is, in one or two words. 0461: a make job's work turn is "Making", not "Digging". */
export function phaseWord(locale: Locale, phase: LandProgress['phase'], make = false): string {
  const key = make && phase === 'digging' ? 'making' : phase
  return translateMaybe(locale, 'land', `phase_${key}`) ?? phase
}

/** A span the server served in seconds, in the game's real-time words ("4.7 min", "1 h 39 min"). */
export function spanWord(seconds: number): string {
  return formatRealDuration(seconds * 1000)
}

/** 0461: what one unit of a make job uses, as the server served it (public.goods_recipes): "2 Iron · 1 Sea Coal". */
export function inputsWord(inputs: ReadonlyArray<{ code: string; qty: number }>, goodName: (code: string) => string): string {
  return inputs.map((i) => `${formatInt(i.qty)} ${goodName(i.code)}`).join(' · ')
}

/** 0458: rare finds as the server counted them (good code -> units), in one line: "1 Amber, 2 Jade". */
export function foundWord(found: Readonly<Record<string, number>>, goodName: (code: string) => string): string {
  return Object.entries(found)
    .filter(([, n]) => n > 0)
    .map(([code, n]) => `${formatInt(n)} ${goodName(code)}`)
    .join(', ')
}
