import { formatDucats, formatInt, formatMiles } from '../lib/format'
import { properName, translate, translateMaybe, type Locale } from '../lib/i18n'
import type { IconName } from '../components/ui'
import type { LevelActivity, LevelBenefit, LevelSkill } from '../lib/rpc'

// THE WORDS OF A LEVEL (0412, docs/LEVELS.md): its name, its mark, what raises it and what a level gives, in the reader's language.
// ONE PLACE: the Levels page, the arrival card and History all name a level through `levelName`.
// NO FIGURE IS TYPED HERE. Every number in a sentence is the served one (`public.level_activity_terms`, `public.level_benefits`):
// this file holds only the words around it. A code this file has no word for prints the server's own English word.

const cap = (code: string): string => code.replace(/(^|_)([a-z])/g, (_, __, c: string) => c.toUpperCase())

/** A level's name: `command.lvTrading`, `command.lvSupplies`, ... by its code; else the served word, else the code. */
export function levelName(locale: Locale, code: string, word?: string): string {
  return translateMaybe(locale, 'command', `lv${cap(code)}`) ?? word ?? code
}

/** A level's mark: an icon of the kit, or strokes drawn here in the kit's own manner (24 px box, stroked, no fill). */
export type LevelMark = { icon: IconName } | { paths: readonly string[] }

const MARKS: Record<string, LevelMark> = {
  trading: { icon: 'coin' },
  exploration: { icon: 'compass' },
  // crossed blades
  combat: { paths: ['M4.5 4.5 15 15', 'M19.5 4.5 9 15', 'm6 13.5 4.5 4.5', 'm18 13.5-4.5 4.5', 'M8.2 15.8 4.5 19.5', 'm15.8 15.8 3.7 3.7'] },
  supplies: { icon: 'cask' },
  // a cloud and a bolt
  weather: { paths: ['M7.5 15.5a4 4 0 0 1-.6-7.96A5.5 5.5 0 0 1 17.4 9a3.3 3.3 0 0 1-.4 6.5', 'm12.5 12-2.5 4.2h4L11.5 20.5'] },
  shipbuilding: { icon: 'mallet' },
  // a written sheet
  requests: { paths: ['M6.5 3.5h8l3 3v14h-11v-17Z', 'M14.5 3.5v3h3', 'M9 10.5h6', 'M9 13.5h6', 'M9 16.5h3.5'] },
  // a toothed wheel
  craft: { paths: ['M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z', 'M12 3v2.5', 'M12 18.5V21', 'M3 12h2.5', 'M18.5 12H21', 'm5.6 5.6 1.8 1.8', 'm16.6 16.6 1.8 1.8', 'm5.6 18.4 1.8-1.8', 'm16.6 7.4 1.8-1.8'] },
  // there and back
  routes: { paths: ['M4 8.5h14', 'm15 5.5 3 3-3 3', 'M20 15.5H6', 'm9 12.5-3 3 3 3'] },
  investment: { icon: 'stats' },
}

export function levelMark(code: string): LevelMark {
  return MARKS[code] ?? { icon: 'wreath' }
}

/** How far a level's bar is filled: experience since this level began, over the span to the next. The top level is full. */
export function levelFill(c: Pick<LevelSkill, 'points' | 'from' | 'next_at'>): number {
  return c.next_at === null || c.next_at <= c.from ? 100 : Math.max(0, Math.min(100, ((c.points - c.from) / (c.next_at - c.from)) * 100))
}

/** One activity as a sentence: what to do, what it gives, and its conditions. Every figure is the served one. */
export function activityLine(locale: Locale, a: LevelActivity): string {
  const t = (key: Parameters<typeof translate>[1], vars?: Parameters<typeof translate>[2]) => translate(locale, key, vars)
  const what = translateMaybe(locale, 'command', `lvAct_${a.code}`) ?? a.word
  const xp = formatInt(a.xp)
  const rate =
    a.unit === 'ducats'
      ? t('command.lvRatePer', { xp, per: formatDucats(a.per) })
      : a.unit === 'nm'
        ? t('command.lvRatePer', { xp, per: formatMiles(a.per) })
        : a.unit === 'day'
          ? t('command.lvRateDay', { xp })
          : t('command.lvRateEach', { xp })
  const notes = [
    a.once ? t('command.lvOnce') : null,
    a.voyage_nm !== null ? t('command.lvVoyage', { nm: formatMiles(a.voyage_nm) }) : null,
    a.most !== null ? t('command.lvMost', { n: formatInt(a.most) }) : null,
  ].filter((x): x is string => x !== null)
  return `${what}: ${rate}${notes.length > 0 ? ` (${notes.join(', ')})` : ''}`
}

/** A benefit of EVERY level, as a sentence (`level` null). */
export function everyLevelLine(locale: Locale, b: LevelBenefit, name: string): string | null {
  if (b.level !== null) return null
  if (b.kind === 'gift') return translate(locale, 'command.lvGiveGift', { n: formatInt(b.n) })
  return translate(locale, 'command.lvGiveCaptains', { name })
}

/** What ONE level gives, as short phrases: its Reputation gift first, then what the rules give at that level. */
export function levelGives(locale: Locale, level: number, benefits: readonly LevelBenefit[]): string[] {
  const out: string[] = []
  if (level < 2) return out
  for (const b of benefits) {
    if (b.level === null) {
      if (b.kind === 'gift') out.push(translate(locale, 'command.lvGiftAt', { n: formatInt(b.n * level) }))
      continue
    }
    if (b.level !== level) continue
    if (b.kind === 'promote') out.push(translate(locale, 'command.lvGivePromote', { grade: b.grade }))
    else if (b.kind === 'fleet') out.push(translate(locale, 'command.lvGiveFleet'))
    else {
      out.push(translate(locale, 'command.lvGiveTitle', { name: properName('title', b.name, b.name), other: levelName(locale, b.with), n: level }))
      if (b.opens.length > 0) out.push(translate(locale, 'command.lvOpens', { what: b.opens.join(', ') }))
    }
  }
  return out
}
