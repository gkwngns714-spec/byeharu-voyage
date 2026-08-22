// Design-system icon glyphs — the ONE inline-SVG set. Pure data (no React) so the name→glyph
// contract is testable. Every glyph is 1.5px-stroke line work on a 24×24 viewBox, drawn with
// `currentColor` by <Icon> so it always wears token colors (text-accent, text-ink-muted, …).
//
// The set is deliberately SMALL. This is a text-and-tabs game: icons decorate empty states and
// mark a fold, they never replace a word. A glyph enters this file only when a screen needs it.

export const ICON_NAMES = [
  'anchor',
  'compass',
  'chart',
  'ship',
  'scales',
  'ledger',
  'wreath',
  'profile',
  'chevron',
  'close',
  'plus',
  'info',
  'search',
  'history',
  'coin',
  'cask',
  'crew',
  'mallet',
  'spice',
  'textile',
  'metal',
  'luxury',
  'foodstuff',
  'raw',
  'navalStores',
] as const

export type IconName = (typeof ICON_NAMES)[number]

/** SVG path `d` strings per glyph (one or more subpaths, all stroked, fill none). */
export const ICON_PATHS: Record<IconName, readonly string[]> = {
  // Anchor — Port.
  anchor: ['M12 7.5V21', 'M12 2.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5Z', 'M5 13H2a10 10 0 0 0 20 0h-3', 'M8.5 10.5h7'],
  // Compass rose — Command (where you set a heading).
  compass: ['M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 0 0 0-19Z', 'm15.5 8.5-2 5-5 2 2-5 5-2Z'],
  // Folded chart — Map (a thing you read, not a thing you press).
  chart: ['M9 4 3.5 6v14L9 18l6 2 5.5-2V4L15 6 9 4Z', 'M9 4v14', 'M15 6v14'],
  // Hull with a mast and sail — Fleets.
  ship: ['M3 17.5h18l-2 3.5H5l-2-3.5Z', 'M12 3v14.5', 'M12 5c3 1 5 2.5 6 4.5h-6', 'M12 8c-2 .8-3.5 1.5-4.5 3H12'],
  // Balance — Market.
  scales: ['M12 4v16', 'M6 20h12', 'M4.5 8h15', 'M4.5 8 2 14h5l-2.5-6Z', 'M19.5 8 17 14h5l-2.5-6Z'],
  // Open book — Ledger.
  ledger: ['M12 6.5C10.5 5 8.5 4.5 6 4.5H3.5v13H6c2.5 0 4.5.5 6 2', 'M12 6.5c1.5-1.5 3.5-2 6-2H20.5v13H18c-2.5 0-4.5.5-6 2', 'M12 6.5v15'],
  // Laurel-ringed marker — Rank.
  wreath: ['M12 3.5a8.5 8.5 0 0 1 0 17', 'M12 3.5a8.5 8.5 0 0 0 0 17', 'M8.5 12h7', 'M12 8.5v7'],
  // Head-and-shoulders in a circle — Profile.
  profile: ['M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 0 0 0-19Z', 'M12 7.2a3.1 3.1 0 1 0 0 6.2 3.1 3.1 0 0 0 0-6.2Z', 'M5.8 19a7.5 7.5 0 0 1 12.4 0'],
  // Chevron (points right; rotate via className for other directions).
  chevron: ['m9 5 7 7-7 7'],
  close: ['M6 6l12 12', 'M18 6 6 18'],
  plus: ['M12 5v14', 'M5 12h14'],
  info: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M12 11v5.5', 'M12 7.6v.9'],
  search: ['M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14Z', 'm16.2 16.2 4.3 4.3'],
  // Clock with a back-arrow tick — the log.
  history: ['M12 3a9 9 0 1 0 9 9', 'M12 3 8.5 5.5 12 8', 'M12 7.5V12l3.5 2.5'],
  // The purse. A milled coin: rim, inner rule, and a struck bar — legible at 14px,
  // which the ducat figure in the top bar is rendered at.
  // The three verbs the set could not name. Added with the D12 action cards: a verb card shows
  // WHAT it does before you choose it, and a card with no mark is a list item.
  cask: ['M7.5 4.5h9', 'M7.5 19.5h9', 'M7.5 4.5C5.5 8 5.5 16 7.5 19.5', 'M16.5 4.5c2 3.5 2 11.5 0 15', 'M4.8 9h14.4', 'M4.8 15h14.4'],
  crew: ['M8.5 4.2a2.6 2.6 0 1 0 0 5.2 2.6 2.6 0 0 0 0-5.2Z', 'M2.8 19a5.7 5.7 0 0 1 11.4 0', 'M16 5.2a2.4 2.4 0 1 1 0 4.8', 'M16.6 13.6A5.7 5.7 0 0 1 21.2 19'],
  mallet: ['M13.5 3.2 20.8 10.5l-3 3-7.3-7.3 3-3Z', 'M10.8 8.9 3.4 16.3a2.2 2.2 0 0 0 3.1 3.1l7.4-7.4'],
  // ── THE SEVEN TRADE-GOOD CATEGORIES ──────────────────────────────────────────────────────────
  // The owner asked for "a picture or an icon for each trade good". There are SEVENTY goods and no
  // art in this repository, so seventy bespoke drawings is not a thing that can be honestly
  // delivered; what CAN be is one distinct mark per CATEGORY, which is the axis the goods data
  // actually carries (`goods.json` -> spice / textile / metal / luxury / foodstuff / raw /
  // naval-stores) and the axis a trader reasons in. See goodIcons.ts for the mapping and for the
  // per-good overrides that make the common cargoes individually recognisable.
  spice: ['M12 3c-2.2 2.6-3.4 5-3.4 7.2a3.4 3.4 0 0 0 6.8 0C15.4 8 14.2 5.6 12 3Z', 'M12 13.6V21', 'M8.6 21h6.8'],
  textile: ['M4 6.5h16v11H4z', 'M4 10h16', 'M4 14h16', 'M8.5 6.5v11', 'M15.5 6.5v11'],
  metal: ['M3.5 8.5 7 5h10l3.5 3.5-8.5 4.5L3.5 8.5Z', 'M12 13v6.5', 'M12 19.5 4.5 15.5', 'M12 19.5l7.5-4'],
  luxury: ['M12 3.2 15 8l5.2.9-3.8 3.9.9 5.4-5.3-2.7-5.3 2.7.9-5.4L3.8 8.9 9 8l3-4.8Z'],
  foodstuff: ['M6.5 10.5h11l-1 9.5h-9l-1-9.5Z', 'M9 10.5c0-3 1.3-4.6 3-4.6s3 1.6 3 4.6', 'M12 3.4v2.5'],
  raw: ['M4 19.5 9 6l4.5 5L17 5l3 14.5H4Z', 'M9 6l4.5 5'],
  navalStores: ['M12 3.5v13.5', 'M7.5 8.5 12 3.5l4.5 5', 'M4.5 20.5h15', 'M8 16.8h8'],
  coin: ['M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6Z', 'M12 6.4a5.6 5.6 0 1 0 0 11.2 5.6 5.6 0 0 0 0-11.2Z', 'M9.6 12h4.8'],
}
