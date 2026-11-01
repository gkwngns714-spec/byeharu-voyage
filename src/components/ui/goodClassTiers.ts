import type { GoodClass } from '../../lib/rpc'
import { translateMaybe, getLocale } from '../../lib/i18n'

// GOOD CLASS TIERS — the pure half of the class rendering (rarityTiers.ts's split, applied again):
// the ordered scale, the player's word, and the class → (word key, lit bars, colour token, row wash)
// table, with no React, so the name → appearance contract is data a test can read. `GoodClassMark`
// (GoodClassMark.tsx) is the one component that draws it. See that file for what the concept is, and
// `GoodKind` for the one place a good's identity is composed.
//
// THE CLASS IS A SERVED NUMBER (0294, `public.good_class`): 1 plus the number of the knob's four
// base-value edges at or below the good's value. Nothing here reads a price, a rarity or a tier —
// the number off the wire is the only input, exactly as the rarity word is for `rarityTiers.ts`.

/** Ascending, for the legend, the sort and the tests. `satisfies` keeps it honest against the served union. */
export const GOOD_CLASSES = [1, 2, 3, 4, 5] as const satisfies readonly GoodClass[]

/** The meter always draws the WHOLE scale — this many bars; the class is how many of them are lit. */
export const GOOD_CLASS_BARS = 5

/** The five bars' heights in px of the 8-px meter: the block characters ▂▃▅▆█ (2, 3, 5, 6, 8 of 8), so
 *  the meter reads as the ascending staircase the design names and no two bars are the same height. */
export const GOOD_CLASS_BAR_HEIGHTS = [2, 3, 5, 6, 8] as const

/** The player's word for a class — the one reading, like `rarityLabel`. A class this build has never
 *  heard of (a server newer than the client) prints as its bare number: a truthful lesser answer. */
export function goodClassLabel(goodClass: number): string {
  return translateMaybe(getLocale(), 'ui', `class${goodClass}`) ?? String(goodClass)
}

interface ClassLook {
  /** The `ui` dictionary entry that is the class's word. */
  word: string
  /** Bars lit, out of GOOD_CLASS_BARS. The SHAPE channel: it survives colour-blindness and greyscale. */
  bars: number
  /** The colour token (src/index.css `--color-class-N`). The COLOUR channel, measured ≥ 4.5 : 1. */
  tone: string
  /** From class 4 a LIST ROW wears a wash in the class's tone (`bv-class-N`, src/index.css): a soft
   *  fade from the row's start edge, so the premium goods are the ones you can see before you read a
   *  word, at no cost in width, height or overlap. Empty for the everyday classes. */
  row: string
}

// Completeness both ways: Record refuses to build if GoodClass gains a class this table misses.
// The Tailwind class names are spelled out whole on purpose — the scanner only generates a utility
// it can read, and a template string would hide `text-class-4` from it.
export const GOOD_CLASS_LOOK: Record<GoodClass, ClassLook> = {
  1: { word: 'class1', bars: 1, tone: 'text-class-1', row: '' },
  2: { word: 'class2', bars: 2, tone: 'text-class-2', row: '' },
  3: { word: 'class3', bars: 3, tone: 'text-class-3', row: '' },
  4: { word: 'class4', bars: 4, tone: 'text-class-4', row: 'bv-class-4' },
  5: { word: 'class5', bars: 5, tone: 'text-class-5', row: 'bv-class-5' },
}

/** The look of a served class, or undefined for one this build does not know (or for none served). */
export function goodClassLook(goodClass: number | null | undefined): ClassLook | undefined {
  return goodClass == null ? undefined : (GOOD_CLASS_LOOK as Record<number, ClassLook | undefined>)[goodClass]
}

/** What a LIST ROW spreads onto its `Row` / `Tile` to wear a good's class: the number itself
 *  (`data-good-class`, which a test or a stylesheet can read) and, from class 4, the wash. A good the
 *  server gave no class — or one this build does not know — spreads nothing: never a guess. */
export function goodClassRow(goodClass: number | null | undefined): { className?: string; 'data-good-class'?: number } {
  const look = goodClassLook(goodClass)
  if (look === undefined || goodClass == null) return {}
  return look.row === '' ? { 'data-good-class': goodClass } : { className: look.row, 'data-good-class': goodClass }
}
