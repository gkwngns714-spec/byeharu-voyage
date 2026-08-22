import type { IconName } from './icons'

// A MARK FOR A TRADE GOOD — the one mapping from a good to the glyph that stands for it.
//
// ── THE OWNER ASKED FOR A PICTURE PER GOOD, AND THIS IS THE HONEST FORM OF THAT ─────────────────
// There are SEVENTY goods in `data/goods.json` and there is no art in this repository at all — not
// one raster, not one illustration. Seventy bespoke drawings is not something that can be delivered
// truthfully, and seventy near-identical ones would be worse than none: a mark that does not
// distinguish is decoration that costs a tap's worth of attention.
//
// So the mark is carried on the axis the data actually has. Every good already declares a
// `category` — spice, textile, metal, luxury, foodstuff, raw, naval-stores — and that is also the
// axis a trader reasons in ("is this a bulk cargo or a luxury?"). Seven distinct glyphs, one per
// category, applied to all seventy goods.
//
// ── AND THEN THE ONES WORTH KNOWING BY SIGHT ────────────────────────────────────────────────────
// A category mark makes salt and wheat look identical, and those are the two cargoes a new captain
// handles first. `GOOD_ICON` overrides the category for specific goods where a more telling glyph
// already exists in the set. It is deliberately SHORT: an override earns its place by being a
// cargo people actually run, and a table of seventy overrides would just be the seventy drawings
// again, badly.
//
// A good with no override falls back to its category; a category that somehow does not resolve
// falls back to `raw`. Neither can throw — a new good added by a migration gets a sensible mark on
// the day it lands, with no edit here.

/** Category → glyph. The seven are exactly the categories `data/goods.json` declares. */
const CATEGORY_ICON: Record<string, IconName> = {
  spice: 'spice',
  textile: 'textile',
  metal: 'metal',
  luxury: 'luxury',
  foodstuff: 'foodstuff',
  raw: 'raw',
  'naval-stores': 'navalStores',
}

/** The few cargoes worth recognising without reading. Keep this list short — see the header. */
const GOOD_ICON: Record<string, IconName> = {
  // The starter loop's own goods (DESIGN K.1 sails salt and wheat before anything else).
  salt: 'foodstuff',
  wheat: 'foodstuff',
  // Coin-like and weighed-by-value cargoes read better as the luxury star than as ore.
  gold: 'luxury',
  silver: 'luxury',
  pearls: 'luxury',
  // Timber, pitch and cordage are what a yard eats; the anchor-ish mark says "this repairs a ship".
  timber: 'navalStores',
  pitch: 'navalStores',
  hemp: 'navalStores',
}

/**
 * The glyph for a good. Give it the good's `code` and `category` — both are on `MarketGood` and on
 * `SnapshotGood`, so no caller has to look anything up.
 */
export function goodIcon(code: string, category: string): IconName {
  return GOOD_ICON[code] ?? CATEGORY_ICON[category] ?? 'raw'
}

/**
 * The human word for a category, for the line that sits beside a good's name. The data spells
 * naval stores with a hyphen because it is a code; a person reading a picker should not have to.
 */
export function categoryLabel(category: string): string {
  return category === 'naval-stores' ? 'naval stores' : category
}
