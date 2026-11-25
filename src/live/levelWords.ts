import { formatDucats, formatInt, formatMiles } from '../lib/format'
import { properName, translate, translateMaybe, type Locale } from '../lib/i18n'
import type { IconName } from '../components/ui'
import type { LevelActivity, LevelBenefit, LevelSkill } from '../lib/rpc'

// THE WORDS OF A LEVEL (0411, docs/LEVELS.md): its name, its mark, what raises it and what a level gives, in the reader's language.
// ONE PLACE: the Levels page, the arrival card and History all name a level through `levelName`.
// NO FIGURE IS TYPED HERE. Every number in a sentence is the served one (`public.level_activity_terms`, `public.level_benefits`):
// this file holds only the words around it. A code this file has no word for prints the server's own English word.

const cap = (code: string): string => code.replace(/(^|_)([a-z])/g, (_, __, c: string) => c.toUpperCase())

/** A level's name: `command.lvTrading`, `command.lvSupplies`, ... by its code; else the served word, else the code. */
export function levelName(locale: Locale, code: string, word?: string): string {
  return translateMaybe(locale, 'command', `lv${cap(code)}`) ?? word ?? code
}

/** The seas a title opens (`title.next.opens`, `sea_zones.name` as served), named in the reader's language and listed: the one
 *  wording of that list (the You page's title block and a level's gifts; 2026-11-22 play-test: English sea names on a Korean You page). */
export function seasOpened(locale: Locale, seas: readonly string[]): string {
  return seas.map((s) => properName('sea', s, s, locale)).join(', ')
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
  // a hull turning away, her wake behind her (0453)
  evasion: { paths: ['M14.5 3.5 20.5 9.5 16 14 10 8Z', 'M10.5 12.5 6 17', 'M8 10 3.5 14.5', 'M13 15 8.5 19.5'] },
  // two pennants (0515)
  management: { paths: ['M5 20V4', 'M5 4.5 13 7l-8 2.5', 'M14 20v-9', 'M14 11.5 21 13.5l-7 2'] },
  // 0455: the land's first skill, the kit's pick (the Land tab's own mark)
  mining: { icon: 'pick' },
  // 0531: an axe in a trunk
  woodcutting: { paths: ['M6 20L15 8', 'M12.5 5.5c2.5-1.5 5.5-.5 7 2l-4 3.5-4.5-3z', 'M4 20h8'] },
  // 0461: an anvil on its block (Smithing, the land's first making skill)
  smithing: { paths: ['M3.5 6.5h13a4 4 0 0 0 4-2', 'M3.5 6.5c0 2 1.5 3 4 3', 'M16.5 6.5v1.5c0 1.5-1.5 2.5-3.5 2.5', 'M7.5 9.5h5.5', 'M9.5 10v5', 'M11.5 10v5', 'M6.5 15h9l1.5 4.5h-12Z'] },
}

/** THE REPUTATION A LEVEL PAYS, by the served gift (`n`, rep_level_per_level) and the skill's `gift_every` (0455): a sea level pays
 *  n x L at every level; a land skill pays n x L / every at every `every`-th level and nothing between (public.level_grant's rule,
 *  served as the two figures). 0 at level 1. The ONE reading the tiles, the tray's "every level" line and its table use. */
export function giftAt(n: number, level: number, every = 1): number {
  if (level < 2 || level % every !== 0) return 0
  return (n * level) / every
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
export function everyLevelLine(locale: Locale, b: LevelBenefit, name: string, every = 1): string | null {
  if (b.level !== null) return null
  if (b.kind === 'gift')
    return every > 1 ? translate(locale, 'command.lvGiveGiftEvery', { n: formatInt(b.n), every }) : translate(locale, 'command.lvGiveGift', { n: formatInt(b.n) })
  return translate(locale, 'command.lvGiveCaptains', { name })
}

/** A step of a level's own benefit (0417), as a sentence with what the benefit is worth from that level on: the served `total`. */
export function perkLine(locale: Locale, b: Extract<LevelBenefit, { kind: 'perk' }>): string {
  return translateMaybe(locale, 'command', `lvPerk_${b.perk}`, { n: formatInt(b.total) }) ?? `${b.word} (${formatInt(b.total)})`
}

/** What her level's own benefits are worth NOW: for each benefit, the step at the highest level she has reached (a pick of a
 *  served row, no sum); a benefit she has no step of yet is named with the level it begins at. */
export function perksNow(locale: Locale, level: number, benefits: readonly LevelBenefit[]): Array<{ perk: string; line: string; has: boolean }> {
  const perks = benefits.filter((b): b is Extract<LevelBenefit, { kind: 'perk' }> => b.kind === 'perk')
  const names = [...new Set(perks.map((b) => b.perk))]
  return names.map((perk) => {
    const steps = perks.filter((b) => b.perk === perk).sort((x, y) => x.level - y.level)
    const mine = steps.filter((b) => b.level <= level).pop()
    if (mine) return { perk, line: perkLine(locale, mine), has: true }
    return { perk, line: translate(locale, 'command.lvPerkFrom', { what: perkLine(locale, steps[0]), n: steps[0].level }), has: false }
  })
}

/** WHAT ONE LEVEL OPENS (0468, docs/design/playable-2026-11-22.md P2): the things a company can use from that level on, as short phrases:
 *  a fleet, a captain's promotion, a step of a benefit (0417's for the levels raised by doing; 0468's for Trading while lit). Not the
 *  Reputation gift (the level line carries it) and not a title (it asks the other track too, so a level alone does not open it). The arrival
 *  card's "Opens:" line and the goal card read this; every phrase is `levelGives`' own. */
export function levelOpens(locale: Locale, level: number, benefits: readonly LevelBenefit[]): string[] {
  if (level < 2) return []
  return levelGives(
    locale,
    level,
    benefits.filter((b) => b.level === level && (b.kind === 'fleet' || b.kind === 'promote' || b.kind === 'perk')),
  )
}

/** The first level above `from` that opens something, and what (the goal card's "Trading 4: Ships a fleet +1"); null when none is left. */
export function nextOpening(locale: Locale, from: number, benefits: readonly LevelBenefit[]): { level: number; what: string } | null {
  const levels = [...new Set(benefits.map((b) => b.level).filter((l): l is number => l !== null && l > from))].sort((a, b) => a - b)
  for (const l of levels) {
    const what = levelOpens(locale, l, benefits)
    if (what.length > 0) return { level: l, what: what.join(', ') }
  }
  return null
}

/** What ONE level gives, as short phrases: its Reputation gift first, then what the rules give at that level. */
export function levelGives(locale: Locale, level: number, benefits: readonly LevelBenefit[], every = 1): string[] {
  const out: string[] = []
  if (level < 2) return out
  for (const b of benefits) {
    if (b.level === null) {
      if (b.kind === 'gift' && giftAt(b.n, level, every) > 0) out.push(translate(locale, 'command.lvGiftAt', { n: formatInt(giftAt(b.n, level, every)) }))
      continue
    }
    if (b.level !== level) continue
    if (b.kind === 'promote') out.push(translate(locale, 'command.lvGivePromote', { grade: b.grade }))
    else if (b.kind === 'fleet') out.push(translate(locale, 'command.lvGiveFleet'))
    else if (b.kind === 'perk') out.push(perkLine(locale, b))
    else {
      out.push(translate(locale, 'command.lvGiveTitle', { name: properName('title', b.name, b.name), other: levelName(locale, b.with), n: level }))
      if (b.opens.length > 0) out.push(translate(locale, 'command.lvOpens', { what: seasOpened(locale, b.opens) }))
    }
  }
  return out
}
