import type { IconName } from '../components/ui'
import type { CaptainCard, CaptainLevel } from '../lib/rpc'
import { traitEffect } from './captainWords'

// THE RULES BEHIND HOW A CAPTAIN LOOKS (the visual overhaul's slice 6) — her tint, the two levels that matter, and the glyph of what a
// trait does. Pure; the pictures that use them are captainLook.tsx's. One place, so the Inn, You and the Codex draw her the same.

const ink = (n: string) => `var(--color-nation-${n})`
const hue = (h: number) => `oklch(0.76 0.12 ${h})`

/** HER HOME TONGUE'S TINT, by the served language name (data/captains.json `languages`). The first of her languages is her home's
 *  (the generator's rule), and every face serves it on her card with no second read, so she wears one colour wherever she stands.
 *  The seven tongues of the great powers wear their nation's own ink (index.css `--color-nation-*`); the rest a hue each, at the
 *  same lightness. Decided by default. */
const TONGUE_TINT: Readonly<Record<string, string>> = {
  portuguese: ink('prt'),
  spanish: ink('esp'),
  dutch: ink('nld'),
  english: ink('eng'),
  german: ink('han'),
  italian: ink('ita'),
  turkish: ink('ott'),
  french: hue(270),
  nordic: hue(215),
  slavic: hue(5),
  arabic: hue(95),
  persian: hue(180),
  indic: hue(40),
  malay: hue(160),
  thai: hue(75),
  chinese: hue(15),
  japanese: hue(345),
  korean: hue(235),
  swahili: hue(130),
  guinean: hue(60),
}

export function captainTint(c: Pick<CaptainCard, 'languages'>): string {
  const home = c.languages?.[0]?.trim().toLowerCase()
  return (home && TONGUE_TINT[home]) || 'var(--color-ink-faint)'
}

/** THE TWO LEVELS THAT MATTER: her role's track, then the stronger of the other two (level, then points; the served order breaks a tie). */
export function levelsThatMatter(c: CaptainCard & { levels: readonly CaptainLevel[] }): CaptainLevel[] {
  const own = c.levels.find((l) => l.track === c.focus)
  const rest = c.levels.filter((l) => l !== own).sort((a, b) => b.level - a.level || b.points - a.points)
  return [...(own ? [own] : []), ...rest].slice(0, 2)
}

/** One glyph an effect of data/captains.json `effects` (icons.ts, "what a captain's trait does"). */
const EFFECT_ICON: Readonly<Record<string, IconName>> = {
  speed: 'speed',
  hold: 'crate',
  spread: 'tag',
  category_spread: 'tag',
  crew_saved: 'shield',
  homesick_relief: 'heart',
  storm: 'storm',
  supplies: 'cask',
  accuracy: 'target',
  reach: 'cannon',
  attack: 'cutlass',
}

/** The glyph of what a served line does; `plus` for a line of no known shape. */
export function effectIcon(served: string): IconName {
  const e = traitEffect(served)
  return (e && EFFECT_ICON[e]) || 'plus'
}
