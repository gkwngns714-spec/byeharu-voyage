// Design-system icon glyphs — the ONE inline-SVG set. Pure data (no React) so the name→glyph
// contract is testable. Every glyph is 1.5px-stroke line work on a 24×24 viewBox, drawn with
// `currentColor` by <Icon> so it always wears token colors (text-accent, text-ink-muted, …).
//
// The NAVIGATION half of the set is deliberately small. This is a text-and-tabs game: those icons
// decorate empty states and mark a fold, they never replace a word. A glyph enters that half only
// when a screen needs it.
//
// The TRADE-GOOD half is the opposite: it is a complete set, one mark per row of `data/goods.json`,
// because the owner asked for a picture for each trade good and a picker of seventy rows that
// repeats seven marks is a picker with no marks at all. See the header of that section for the
// constraint every one of them was drawn against.

export const ICON_NAMES = [
  'anchor',
  'compass',
  'chart',
  'ship',
  'scales',
  'ledger',
  'wreath',
  'profile',
  'codex',
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
  // The seven trade-good CATEGORIES. Not a good's own mark any more — the fallback, for a good
  // that arrives from a migration before anyone has drawn it. See goodIcons.ts.
  'spice',
  'textile',
  'metal',
  'luxury',
  'foodstuff',
  'raw',
  'navalStores',
  // ── ONE MARK PER TRADE GOOD, in `data/goods.json` order ──────────────────────────────────────
  // spice
  'goodBlackPepper',
  'goodCloves',
  'goodNutmeg',
  'goodMace',
  'goodCinnamon',
  'goodGinger',
  'goodCardamom',
  // textile
  'goodWoolCloth',
  'goodLinen',
  'goodCottonCloth',
  'goodMuslin',
  'goodChintz',
  'goodSilkCloth',
  'goodSilkRaw',
  'goodCarpets',
  'goodRamieCloth',
  // metal
  'goodGold',
  'goodSilver',
  'goodCopper',
  'goodTin',
  'goodIron',
  // luxury
  'goodPorcelain',
  'goodLacquerware',
  'goodGlassware',
  'goodPearls',
  'goodDiamonds',
  'goodIvory',
  'goodAmbergris',
  'goodMusk',
  'goodCoral',
  'goodAmber',
  'goodFrankincense',
  'goodMyrrh',
  // foodstuff
  'goodWheat',
  'goodRice',
  'goodSugar',
  'goodSalt',
  'goodOliveOil',
  'goodWine',
  'goodDriedFish',
  'goodHerring',
  'goodCheese',
  'goodSaltedBeef',
  'goodCoffee',
  'goodTea',
  'goodCacao',
  'goodDriedFruit',
  // raw
  'goodTobacco',
  'goodIndigo',
  'goodCochineal',
  'goodBrazilwood',
  'goodLogwood',
  'goodAlum',
  'goodSaltpetre',
  'goodSulphur',
  'goodHides',
  'goodFurs',
  'goodWax',
  'goodCottonRaw',
  'goodWoolRaw',
  'goodGumArabic',
  'goodSandalwood',
  'goodGinseng',
  'goodHorses',
  // naval stores
  'goodTimber',
  'goodNavalTimber',
  'goodTar',
  'goodHemp',
  'goodFlax',
  'goodWhaleOil',
  // ── THE FOUR RARITY TIERS (0032) — a SHAPE per tier, so rarity is never colour alone ─────────
  // Drawn for ~12px: four distinct silhouettes (ring, diamond, faceted gem, four-point star),
  // because at that size interior detail is gone and the outline is all a colourblind player or a
  // greyscale screenshot gets. Consumed only by RarityMark; the tier→shape table lives there.
  'rarityCommon',
  'rarityUncommon',
  'rarityRare',
  'rarityExotic',
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
  // CLOSED book with a bookmark — Compendium (the reference you look things up in). The OPEN book
  // is the Ledger's, and the two must stay tellable apart: the record you write vs the book you consult.
  codex: ['M7 2.5h12.5v19H7A2.5 2.5 0 0 1 4.5 19V5A2.5 2.5 0 0 1 7 2.5Z', 'M4.5 19a2.5 2.5 0 0 1 2.5-2.5h12.5', 'M13.5 2.5V9l2.25-1.7L18 9V2.5'],
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
  coin: ['M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6Z', 'M12 6.4a5.6 5.6 0 1 0 0 11.2 5.6 5.6 0 0 0 0-11.2Z', 'M9.6 12h4.8'],
  // The three verbs the set could not name. Added with the D12 action cards: a verb card shows
  // WHAT it does before you choose it, and a card with no mark is a list item.
  cask: ['M7.5 4.5h9', 'M7.5 19.5h9', 'M7.5 4.5C5.5 8 5.5 16 7.5 19.5', 'M16.5 4.5c2 3.5 2 11.5 0 15', 'M4.8 9h14.4', 'M4.8 15h14.4'],
  crew: ['M8.5 4.2a2.6 2.6 0 1 0 0 5.2 2.6 2.6 0 0 0 0-5.2Z', 'M2.8 19a5.7 5.7 0 0 1 11.4 0', 'M16 5.2a2.4 2.4 0 1 1 0 4.8', 'M16.6 13.6A5.7 5.7 0 0 1 21.2 19'],
  mallet: ['M13.5 3.2 20.8 10.5l-3 3-7.3-7.3 3-3Z', 'M10.8 8.9 3.4 16.3a2.2 2.2 0 0 0 3.1 3.1l7.4-7.4'],

  // ── THE SEVEN CATEGORY MARKS — now the FALLBACK, not the answer ───────────────────────────────
  // Every good in `data/goods.json` has its own mark below. These seven remain because a good can
  // arrive from a migration before anyone has drawn it, and a picker row must still show something
  // truthful on that day. `goodIcon()` reaches them only when the per-good table has no entry.
  spice: ['M12 3c-2.2 2.6-3.4 5-3.4 7.2a3.4 3.4 0 0 0 6.8 0C15.4 8 14.2 5.6 12 3Z', 'M12 13.6V21', 'M8.6 21h6.8'],
  textile: ['M4 6.5h16v11H4z', 'M4 10h16', 'M4 14h16', 'M8.5 6.5v11', 'M15.5 6.5v11'],
  metal: ['M3.5 8.5 7 5h10l3.5 3.5-8.5 4.5L3.5 8.5Z', 'M12 13v6.5', 'M12 19.5 4.5 15.5', 'M12 19.5l7.5-4'],
  luxury: ['M12 3.2 15 8l5.2.9-3.8 3.9.9 5.4-5.3-2.7-5.3 2.7.9-5.4L3.8 8.9 9 8l3-4.8Z'],
  foodstuff: ['M6.5 10.5h11l-1 9.5h-9l-1-9.5Z', 'M9 10.5c0-3 1.3-4.6 3-4.6s3 1.6 3 4.6', 'M12 3.4v2.5'],
  raw: ['M4 19.5 9 6l4.5 5L17 5l3 14.5H4Z', 'M9 6l4.5 5'],
  navalStores: ['M12 3.5v13.5', 'M7.5 8.5 12 3.5l4.5 5', 'M4.5 20.5h15', 'M8 16.8h8'],

  // ══ ONE MARK PER TRADE GOOD ═══════════════════════════════════════════════════════════════════
  //
  // THE CONSTRAINT THESE WERE DRAWN AGAINST, and it is the whole design brief: the good picker
  // renders them at 22px (src/features/command/ArgPickers.tsx) and the rest of the app at 16-18px.
  // At 22px a 24-unit glyph has roughly a 3×3 grid of perceptible detail. Two marks that differ
  // only in an interior line ARE THE SAME MARK there. So every one of these is separated by its
  // OUTER SILHOUETTE first — a nut, a pod, a bolt, a bale, an ingot, a jar, a leaf, an animal, a
  // tool — and interior detail is spent only where the silhouette is already won.
  //
  // Where two goods are genuinely alike, the split is the thing's REAL form, taken from the `note`
  // in data/goods.json rather than invented: a cinnamon quill is a rolled tube, saffron-like mace
  // is a splayed aril, pepper is berries on a spike. Decorative detail added to tell two marks
  // apart is detail that vanishes at 22px and is therefore a lie about how distinct they are.
  //
  // Adding a good: add its glyph here, its name to ICON_NAMES, and its row to GOOD_ICON in
  // goodIcons.ts — the Record<IconName, …> typing turns a typo in any of the three into a compile
  // error, which is the point of not weakening it.

  // ── SPICE ────────────────────────────────────────────────────────────────────────────────────
  // Peppercorns on a stalk — the vine's fruiting spike, three berries and no more.
  goodBlackPepper: ['M12 3.2v3.6', 'M6.3 9.8a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0Z', 'M12.7 9.8a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0Z', 'M9.5 15.4a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0Z'],
  // A clove nail: the dried flower bud on its shaft, with the two calyx points that name it.
  goodCloves: ['M12 21V11', 'M12 11c-2 0-3.2-1.4-3.2-3.2 0-2 1.4-3.6 3.2-4.6 1.8 1 3.2 2.6 3.2 4.6 0 1.8-1.2 3.2-3.2 3.2Z', 'M8.8 7.8 6.2 6.2', 'M15.2 7.8l2.6-1.6'],
  // The nut alone. The ONE plain egg in the set — nothing else may be a bare oval.
  goodNutmeg: ['M12 4.2c3.4 0 5.8 3.2 5.8 7.4s-2.4 8.2-5.8 8.2-5.8-4-5.8-8.2 2.4-7.4 5.8-7.4Z', 'M12 4.6v14.8'],
  // The same Banda fruit's scarlet aril: a smaller nut inside splayed arms.
  goodMace: ['M12 9.6c2.6 0 4.4 2.2 4.4 5.1s-1.8 5.1-4.4 5.1-4.4-2.2-4.4-5.1 1.8-5.1 4.4-5.1Z', 'M12 9.8c-.4-3-1.8-5-4.2-6.2', 'M12 9.8c.4-3 1.8-5 4.2-6.2', 'M12 9.8V3.4'],
  // A quill — the peeled Ceylon bark rolled into a tube. The set's only vertical cylinder.
  goodCinnamon: ['M9 6.6a3 1.8 0 1 0 6 0a3 1.8 0 1 0 -6 0Z', 'M9 6.6v11', 'M15 6.6v11', 'M9 17.6a3 1.8 0 0 0 6 0', 'M10.6 6.6a1.4 .9 0 0 1 2.8 0'],
  // The rhizome — a knobbly hand lying flat, with two sprouts.
  goodGinger: ['M4.6 13.6c0-2.2 1.8-3.4 3.6-3.2 1.6.2 2.2 1.2 3.6 1.2 1.6 0 2.2-2.6 4.2-2.6 1.8 0 3.4 1.4 3.4 3.4 0 2-1.4 3.2-3 3.4-1.6.2-2.4-.6-3.8-.4-1.6.2-2.2 2.2-4.2 2.2-2 0-3.8-1.6-3.8-4Z', 'M9 9.4c.2-1.4-.4-2.6-1.4-3.4', 'M15.6 8.8c.4-1.6 1.6-2.6 3-2.8'],
  // Three small pods — cardamom is sold by the pod, and the count is what tells it from a cacao.
  goodCardamom: ['M9.4 7.4c1.2 0 2 1.4 2 3.2s-.8 3.2-2 3.2-2-1.4-2-3.2.8-3.2 2-3.2Z', 'M14.8 7.4c1.2 0 2 1.4 2 3.2s-.8 3.2-2 3.2-2-1.4-2-3.2.8-3.2 2-3.2Z', 'M12.1 13.6c1.2 0 2 1.4 2 3.2s-.8 3.2-2 3.2-2-1.4-2-3.2.8-3.2 2-3.2Z', 'M9.4 7.4V5.4', 'M14.8 7.4V5.4'],

  // ── TEXTILE ──────────────────────────────────────────────────────────────────────────────────
  // Broadcloth folded in an accordion, the way a bolt is laid on a counter.
  goodWoolCloth: ['M4.4 6h12a2.6 2.6 0 0 1 0 5.2H7.6a2.6 2.6 0 0 0 0 5.2h12', 'M4.4 8.6h12a2.6 2.6 0 0 1 0 5.2H7.6a2.6 2.6 0 0 0 0 5.2h12'],
  // A hanging panel with a wavy hem — plain cloth, no frame, no print.
  goodLinen: ['M5.5 4.6h13v11', 'M5.5 4.6v11', 'M5.5 15.6c1.6 0 1.6 2 3.2 2s1.6-2 3.2-2 1.6 2 3.2 2 1.7-2 3.4-2'],
  // Folded calico, stacked — the parallelogram silhouette of cloth folded twice.
  goodCottonCloth: ['M4.6 9.6 12 6.4l7.4 3.2-7.4 3.2z', 'M4.6 13.6 12 16.8l7.4-3.2', 'M4.6 9.6v4', 'M19.4 9.6v4'],
  // Gossamer. No outline at all — three drifting lines is the whole point of a Dhaka muslin.
  goodMuslin: ['M3.5 7.5c3-2.4 6-2.4 8.5 0s5.5 2.4 8.5 0', 'M3.5 12c3-2.4 6-2.4 8.5 0s5.5 2.4 8.5 0', 'M3.5 16.5c3-2.4 6-2.4 8.5 0s5.5 2.4 8.5 0'],
  // A printed square: the painted Coromandel cotton, marked by its flower.
  goodChintz: ['M4.8 4.8h14.4v14.4H4.8z', 'M10.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0Z', 'M12 10.4V7.8', 'M12 13.6v2.6', 'M10.4 12H7.8', 'M13.6 12h2.6'],
  // A bolt of woven silk falling in an S — the drape is the mark.
  goodSilkCloth: ['M4 8.2c2.6-3.4 5.4-3.4 8 0s5.4 3.4 8 0', 'M4 13.4c2.6-3.4 5.4-3.4 8 0s5.4 3.4 8 0', 'M4 8.2v5.2', 'M20 8.2v5.2'],
  // A bobbin of filature silk — thread wound on a spool, which is not a bolt and not a quill.
  goodSilkRaw: ['M6.4 4.2h11.2v2.4H6.4z', 'M6.4 17.4h11.2v2.4H6.4z', 'M9 6.6v10.8', 'M15 6.6v10.8', 'M9 10h6', 'M9 13.6h6'],
  // A rug laid flat: double border and a centre medallion, wider than it is tall.
  goodCarpets: ['M3.4 6.6h17.2v10.8H3.4z', 'M5.8 8.8h12.4v6.4H5.8z', 'M12 9.8 14.4 12 12 14.2 9.6 12z'],
  // Korean mosi hung from a rod, cut with the V of a banner — cloth on a pole, not cloth in a bolt.
  goodRamieCloth: ['M3.8 5h16.4', 'M6.6 5v13l5.4-3.4 5.4 3.4V5'],

  // ── METAL ────────────────────────────────────────────────────────────────────────────────────
  // Three cast bars stacked — bullion.
  goodGold: ['M3.6 19.4h7.4l-1-3.4H4.6z', 'M13 19.4h7.4l-1-3.4H14z', 'M8.3 15.9h7.4l-1-3.4H9.3z'],
  // Coin blanks stacked on edge: struck metal, not cast metal.
  goodSilver: ['M7.4 8.4a4.6 1.7 0 1 0 9.2 0a4.6 1.7 0 1 0 -9.2 0Z', 'M7.4 8.4v7.2', 'M16.6 8.4v7.2', 'M7.4 12a4.6 1.7 0 0 0 9.2 0', 'M7.4 15.6a4.6 1.7 0 0 0 9.2 0'],
  // Two long bars — the Japanese and Swedish trade came as bar copper.
  goodCopper: ['M4.2 10.4 15.4 4.6l2.2 4.2L6.4 14.6z', 'M6.4 15.2 17.6 9.4l2.2 4.2L8.6 19.4z'],
  // One stamped ingot. Malay tin was cast and passed as money, and it is stamped to say so.
  goodTin: ['M5.6 16.8h12.8l-2.4-6.4H8z', 'M8.8 13.6h6.4'],
  // An anvil — iron as the thing it is worked into, and the one unmistakable outline for it.
  goodIron: ['M4.4 9.2h11.2l4 1.4-4 2H4.4z', 'M9.2 12.6h4.4v4H17v2.2H7v-2.2h2.2z'],

  // ── LUXURY ───────────────────────────────────────────────────────────────────────────────────
  // A kraak vase: narrow neck, full belly, and the band the blue-and-white is painted in.
  goodPorcelain: ['M9.4 3.6h5.2', 'M9.6 3.6c0 2.2-4 3.4-4 8.2 0 4.2 2.8 7.4 6.4 7.4s6.4-3.2 6.4-7.4c0-4.8-4-6-4-8.2', 'M8.4 12.6c2.4 1.4 4.8 1.4 7.2 0'],
  // A tiered lidded box — urushi ware travelled as cabinet goods, and a lid is its silhouette.
  goodLacquerware: ['M5.4 8.2h13.2v3.4H5.4z', 'M6.4 11.6h11.2v7.2H6.4z', 'M10.8 6.4h2.4v1.8h-2.4z'],
  // A cristallo goblet: bowl, stem, foot.
  goodGlassware: ['M6.8 4.6h10.4c0 4.4-2.2 7.2-5.2 7.2S6.8 9 6.8 4.6Z', 'M12 11.8v6.2', 'M8.2 19.4h7.6'],
  // A strand — pearls are counted and strung, never loose.
  goodPearls: ['M4.4 8.4c1.4-2.6 4.2-4.2 7.6-4.2s6.2 1.6 7.6 4.2', 'M3.5 10.2a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z', 'M5.9 13.6a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z', 'M10.3 15a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z', 'M14.7 13.6a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z', 'M17.1 10.2a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z'],
  // A cut stone: crown, girdle, pavilion. The set's only faceted point-down shape.
  goodDiamonds: ['M7.6 5h8.8l3.4 4.4L12 19.4 4.2 9.4z', 'M4.2 9.4h15.6', 'M9.4 9.4 12 19.4l2.6-10', 'M7.6 5l1.8 4.4', 'M16.4 5l-1.8 4.4'],
  // A pair of tusks facing each other. One tusk is a crescent and a crescent is a leaf at 22px —
  // the PAIR, opening upward, is what tells it from tobacco.
  goodIvory: ['M11.2 19.8C7.4 19.2 4.2 15.6 3.6 10.8 3.4 9.2 4.2 8.2 5.4 8.4c3.6.6 6.2 5.6 5.8 11.4Z', 'M12.8 19.8c3.8-.6 7-4.2 7.6-9 .2-1.6-.6-2.6-1.8-2.4-3.6.6-6.2 5.6-5.8 11.4Z'],
  // A lump found on the tideline. The wave under it is half the mark.
  goodAmbergris: ['M8 12.6c-1.6-1-1.2-3.6.8-4.4 1-2.4 4.2-2.8 5.8-.8 2.4-.4 4 2.2 2.6 4.2-.4 2-3 2.8-4.6 1.6-1.6 1-3.8.2-4.6-.6Z', 'M3.6 18c1.8-1.6 3.6-1.6 5.4 0s3.6 1.6 5.4 0 3.6-1.6 5.6 0'],
  // The pod, tied at the neck — musk was sold by the ounce in exactly this.
  goodMusk: ['M12 8.2c3.6 0 6.4 2.6 6.4 5.8s-2.8 5.6-6.4 5.6-6.4-2.4-6.4-5.6S8.4 8.2 12 8.2Z', 'M9.6 8.6 9 5.4h6l-.6 3.2', 'M8.4 6.4h7.2'],
  // A branching sprig of red coral, the way it comes off the Barbary banks.
  goodCoral: ['M12 20.2v-6.4', 'M12 13.8 8 9.8V5.8', 'M12 13.8 16 9.8V5.8', 'M8 9.8 5.2 7.2', 'M16 9.8l2.8-2.6'],
  // A rough nugget with an inclusion — the fleck is why Samland amber was worth cutting.
  goodAmber: ['M7.4 5.6 15.6 4l4 5.6-2.4 7.6-7.8 2.4-4.6-4.8 1-6.4z', 'M10.8 11.6a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0Z'],
  // A censer on its chains — frankincense is bought to be burnt.
  goodFrankincense: ['M6.6 12.4h10.8c0 3.2-2.4 5.6-5.4 5.6s-5.4-2.4-5.4-5.6Z', 'M7.8 12.2 11.4 6.6', 'M16.2 12.2 12.6 6.6', 'M12 6.6a1.4 1.4 0 1 0 0-2.8a1.4 1.4 0 1 0 0 2.8Z'],
  // The tapped branch and the bead of gum on it — the same dry country, a different thing.
  goodMyrrh: ['M7.6 3.8c0 6.6 1.8 11.4 5.4 14.6', 'M8.6 8.6c1.8 0 3.4-.8 4.8-2.2', 'M14.6 13.4a1.8 1.8 0 1 0 3.6 0a1.8 1.8 0 1 0 -3.6 0Z'],

  // ── FOODSTUFF ────────────────────────────────────────────────────────────────────────────────
  // An ear of rye or wheat on the stalk.
  goodWheat: ['M12 20.4V5.8', 'M12 10.2c-2.6 0-4.2-1.8-4.2-4.2 2.6 0 4.2 1.8 4.2 4.2Z', 'M12 10.2c2.6 0 4.2-1.8 4.2-4.2-2.6 0-4.2 1.8-4.2 4.2Z', 'M12 15.6c-2.6 0-4.2-1.8-4.2-4.2 2.6 0 4.2 1.8 4.2 4.2Z', 'M12 15.6c2.6 0 4.2-1.8 4.2-4.2-2.6 0-4.2 1.8-4.2 4.2Z'],
  // A heaped bowl — rice is bought where it is eaten, and that is the shape it arrives in.
  goodRice: ['M4.4 12.4h15.2c0 3.8-3.4 6.8-7.6 6.8s-7.6-3-7.6-6.8Z', 'M7.4 12.2c.8-2.4 2.6-3.8 4.6-3.8s3.8 1.4 4.6 3.8'],
  // A sugarloaf in its wrapper, twisted at the point — how a mill sold it.
  goodSugar: ['M12 4.2 17.6 18.4H6.4z', 'M8.4 13.6h7.2', 'M12 4.2 10.6 2.6'],
  // A salt crystal. Cubic, and drawn as one, because that is what comes off a pan.
  goodSalt: ['M12 3.8 20 8.4v7.2L12 20.2 4 15.6V8.4z', 'M4 8.4 12 13l8-4.6', 'M12 13v7.2'],
  // Olives on the branch — the fruit, not the jar, so no vessel has to be told from another.
  goodOliveOil: ['M4.4 18.8c4.6-1.6 8.2-4.9 10.6-9.8', 'M6.4 13.6a2.4 2.4 0 1 0 4.8 0a2.4 2.4 0 1 0 -4.8 0Z', 'M11.6 8.6a2.4 2.4 0 1 0 4.8 0a2.4 2.4 0 1 0 -4.8 0Z', 'M15.8 7.2c1.6-2.6 3.4-3.6 5.4-3.4-.2 2.8-2 4.2-5.4 3.4Z'],
  // A bottle with its label band.
  goodWine: ['M10.2 3.4h3.6v3.8c2 1.2 3.2 3.4 3.2 5.8v6.4c0 .8-.6 1.4-1.4 1.4H8.4c-.8 0-1.4-.6-1.4-1.4V13c0-2.4 1.2-4.6 3.2-5.8z', 'M7 14.6h10'],
  // Stockfish on the rack, forked tail down — dried hanging is the whole of what makes it keep.
  goodDriedFish: ['M4 4.2h16', 'M12 4.2v1.8', 'M12 6c-2.4 1.8-3.8 4.2-3.8 6.6 0 2.1 1.1 3.9 2.8 5H13c1.7-1.1 2.8-2.9 2.8-5 0-2.4-1.4-4.8-3.8-6.6Z', 'M9.6 17.2 12 21.6l2.4-4.4'],
  // A shoal — herring is never one fish, it is a fishery.
  goodHerring: ['M3.4 5 5.8 6.6 3.4 8.2z M5.8 6.6c1.8-1.7 4.8-1.7 6.6 0-1.8 1.7-4.8 1.7-6.6 0Z', 'M10.2 10.4 12.6 12l-2.4 1.6z M12.6 12c1.8-1.7 4.8-1.7 6.6 0-1.8 1.7-4.8 1.7-6.6 0Z', 'M4.6 15.8 7 17.4l-2.4 1.6z M7 17.4c1.8-1.7 4.8-1.7 6.6 0-1.8 1.7-4.8 1.7-6.6 0Z'],
  // A cut wedge off the wheel.
  goodCheese: ['M3.6 17.4 19.4 8.6v6.2c0 1.4-1.2 2.6-2.6 2.6z', 'M8.4 14.6a1.2 1.2 0 1 0 2.4 0a1.2 1.2 0 1 0 -2.4 0Z', 'M13.6 12.8a1 1 0 1 0 2 0a1 1 0 1 0 -2 0Z'],
  // A joint on the bone — barrelled beef and pork, drawn as the thing in the barrel.
  goodSaltedBeef: ['M8 17.8c-1.9-1.6-2-4.4 0-6.8 2.4-2.9 6.2-4.3 8.4-3 2 1.2 2.3 4.1.7 6.7-1.9 3.1-6.2 5-9.1 3.1Z', 'M8.4 11.4 5.8 8.6', 'M2.9 7.4a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0Z'],
  // Two beans with their seam — Mocha's whole export.
  goodCoffee: ['M6.2 5.4c2-1.6 4.8-1 6.2 1.4s.8 5.4-1.2 7-4.8 1-6.2-1.4-.8-5.4 1.2-7Z', 'M6.8 6c1.6 1.4 2.2 4.6 1 7.4', 'M13 11c2-1.6 4.8-1 6.2 1.4s.8 5.4-1.2 7-4.8 1-6.2-1.4-.8-5.4 1.2-7Z', 'M13.6 11.6c1.6 1.4 2.2 4.6 1 7.4'],
  // Two leaves and a bud — the pluck, and the smallest leaf shape in the set.
  goodTea: ['M12 20.4V12', 'M12 12c-3.4 0-5.6-2.2-5.6-5.6 3.4 0 5.6 2.2 5.6 5.6Z', 'M12 12c3.4 0 5.6-2.2 5.6-5.6-3.4 0-5.6 2.2-5.6 5.6Z', 'M12 8.6c-1 0-1.8-1-1.8-2.4 0-1.6.8-2.8 1.8-3.6 1 .8 1.8 2 1.8 3.6 0 1.4-.8 2.4-1.8 2.4Z'],
  // A pod hanging off the trunk. The branch it hangs from is what keeps it off the nutmeg's egg.
  goodCacao: ['M6.2 3.8h5', 'M11.2 3.8c0 1 .3 1.7 .8 2.2', 'M12 6c3.4 2.4 5.2 6.2 5.2 9.6 0 3.2-2.2 5.4-5.2 5.4s-5.2-2.2-5.2-5.4c0-3.4 1.8-7.2 5.2-9.6Z', 'M9.6 8.6c-.7 3.4-.7 7.2.2 10.4'],
  // A bunch — raisins and currants came off the vine and were sold as the bunch.
  goodDriedFruit: ['M12 9.4V5.6', 'M12 6.4c1.8-1.8 3.6-2.2 5.4-1.2-.8 2-2.6 2.8-5.4 1.2Z', 'M6.7 11.4a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z', 'M10.1 11.4a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z', 'M13.5 11.4a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z', 'M8.4 14.8a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z', 'M11.8 14.8a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z', 'M10.1 18.2a1.9 1.9 0 1 0 3.8 0a1.9 1.9 0 1 0 -3.8 0Z'],

  // ── RAW ──────────────────────────────────────────────────────────────────────────────────────
  // One broad leaf filling the box — tobacco was shipped as cured leaf.
  goodTobacco: ['M20 4c-8 0-13.6 4.8-13.6 10.6 0 2.2.8 4 2.2 5.2C15.6 19.2 20 12.6 20 4Z', 'M8 19.4C11.6 14 15.4 9.6 19.4 5', 'M10.4 16.6c1.6.4 3.2.2 4.6-.6'],
  // A drop of dye and the ripple it lands in.
  goodIndigo: ['M12 2.8c3.2 4.2 4.8 7.2 4.8 9.2a4.8 4.8 0 0 1-9.6 0c0-2 1.6-5 4.8-9.2Z', 'M4.4 19.6c2.2-1.8 4.4-1.8 6.6 0s4.4 1.8 6.6 0'],
  // The insect itself. Oaxaca sold a dried bug by weight, and legs are what say so.
  goodCochineal: ['M12 6.4c2.6 0 4.6 2.4 4.6 5.6s-2 5.6-4.6 5.6-4.6-2.4-4.6-5.6 2-5.6 4.6-5.6Z', 'M7.6 10.4h8.8', 'M7.6 13.6h8.8', 'M7.4 9 4.6 7.4', 'M16.6 9l2.8-1.6', 'M7.4 15l-2.8 1.6', 'M16.6 15l2.8 1.6'],
  // A billet of dyewood with its end grain — the log, whole.
  goodBrazilwood: ['M15.8 8.6a3 3.4 0 1 0 0 6.8a3 3.4 0 1 0 0-6.8Z', 'M4.4 8.6h11.4', 'M4.4 15.4h11.4', 'M4.4 8.6a3 3.4 0 0 0 0 6.8', 'M15.8 10.4a1.4 1.6 0 1 0 0 3.2a1.4 1.6 0 1 0 0-3.2Z'],
  // Cut billets crossed — Campeche logwood was shipped chopped, not whole.
  goodLogwood: ['M4.6 7 7 4.6l12.4 12.4-2.4 2.4z', 'M17 4.6 19.4 7 7 19.4 4.6 17z'],
  // Mordant crystals — three thin lozenges, nothing faceted.
  goodAlum: ['M12 3 14.4 11.6 12 20.2 9.6 11.6z', 'M6.2 7.6 8.2 13.2 6.2 18.8 4.2 13.2z', 'M17.8 7.6 19.8 13.2 17.8 18.8 15.8 13.2z'],
  // A powder keg with a lit fuse — Patna refined it for exactly one buyer.
  goodSaltpetre: ['M7 8.6h10v9.8H7z', 'M7 11.4h10', 'M7 15.6h10', 'M14.4 8.6c.6-2 1.6-3.2 3-3.6', 'M18.4 2.4l.8 1.8 1.8.8-1.8.8-.8 1.8-.8-1.8-1.8-.8 1.8-.8z'],
  // Brimstone: a rough lump and the fumes coming off it.
  goodSulphur: ['M5 17.8 6.6 13.2 10.4 11 15 12.2 18.4 15.2 17.4 19.6z', 'M8.6 8.6c-1.2-1.2-1.2-2.6 0-3.8', 'M12 8.6c-1.2-1.2-1.2-2.6 0-3.8', 'M15.4 8.6c-1.2-1.2-1.2-2.6 0-3.8'],
  // A hide stretched flat, legs out — the Plata cattle trade in one shape.
  goodHides: ['M8.4 7.4h7.2c2 0 3.2 1.6 3.2 3.6v2c0 2-1.2 3.6-3.2 3.6H8.4c-2 0-3.2-1.6-3.2-3.6v-2c0-2 1.2-3.6 3.2-3.6Z', 'M8.6 7.4 7.4 4.2', 'M15.4 7.4l1.2-3.2', 'M8.6 16.6 7.4 19.8', 'M15.4 16.6l1.2 3.2'],
  // A pelt taken whole, ears still on it — beaver and sable were counted as animals, not weighed.
  goodFurs: ['M8.6 7.4c-1.2 1.6-1.8 3.6-1.8 5.8 0 3.4 2.2 5.8 5.2 5.8s5.2-2.4 5.2-5.8c0-2.2-.6-4.2-1.8-5.8z', 'M8.6 7.4 7.6 3.4 11.2 6z', 'M15.4 7.4l1-4L12.8 6z', 'M12 19c0 1.5.9 2.4 2.4 2.4'],
  // A candle — beeswax and tallow are bought to be burnt, and the flame says which trade it is.
  goodWax: ['M8.6 9.6h6.8v9.8H8.6z', 'M7 19.4h10', 'M12 9.6V8', 'M12 8c-1.4-1-2-2-2-3 0-1.4 1-2.6 2-3.4 1 .8 2 2 2 3.4 0 1-.6 2-2 3Z'],
  // A boll on its stem — the puff, before anyone spins it.
  goodCottonRaw: ['M8.6 13.4c-1.8 0-3.2-1.4-3.2-3.2 0-1.4.8-2.6 2-3-.2-2 1.4-3.8 3.4-3.8.8 0 1.6.2 2.2.8.6-.6 1.4-1 2.4-1 2 0 3.6 1.6 3.6 3.6v.4c1.2.4 2 1.6 2 3 0 1.8-1.4 3.2-3.2 3.2z', 'M12 13.4v5.4', 'M12 15.4 9 13.8', 'M12 15.4l3-1.6'],
  // Shears. Raw wool is wool that has been taken off the sheep and not yet been anything else.
  goodWoolRaw: ['M4.2 18.6a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0 -4.4 0Z', 'M15.4 18.6a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0 -4.4 0Z', 'M6 4.2 15.8 16.6', 'M18 4.2 8.2 16.6'],
  // Mortar and pestle — gums and simples are apothecary goods, sold to be ground.
  goodGumArabic: ['M5.4 11.4h13.2c0 4-2.6 6.8-6.6 6.8s-6.6-2.8-6.6-6.8Z', 'M4.4 11.4h15.2', 'M13.6 12.2 18.8 4.2'],
  // Incense sticks standing in their holder, with the smoke that is why anyone buys the wood.
  goodSandalwood: ['M9.4 18.4h5.2v2.6H9.4z', 'M10.6 18.4 8.2 6.8', 'M12 18.4V6.4', 'M13.4 18.4l2.4-11.6', 'M12 5.6c-1.2-1-1.2-2.2 0-3.2'],
  // The root, tapering, whiskers off its sides — ginseng is priced on the shape of the root itself.
  // Drawn as a root and NOT as a head with limbs: the first cut of this read as a standing figure.
  goodGinseng: ['M9.4 6.6h5.2c0 3.4-.7 6.2-2.6 13-1.9-6.8-2.6-9.6-2.6-13Z', 'M10 10.4 7 8.8', 'M14 10.4l3-1.6', 'M10.6 14.2 8.2 13.2', 'M13.4 14.2l2.4-1', 'M12 6.6c-1.4-1.4-1.4-2.6 0-3.8 1.4 1.2 1.4 2.4 0 3.8Z'],
  // A shoe. Nothing else in the set is an open ring, and at 22px a horse's head is a smudge.
  goodHorses: ['M12 3.4c-4.2 0-7.4 3.4-7.4 7.8 0 3 1.2 5.6 1.6 7.6.2 1.2.6 1.8 1.6 1.8h1.8c1 0 1.4-.8 1.2-1.8-.4-2-1.4-4.2-1.4-6.6 0-2.2 1.2-3.8 2.6-3.8s2.6 1.6 2.6 3.8c0 2.4-1 4.6-1.4 6.6-.2 1 .2 1.8 1.2 1.8h1.8c1 0 1.4-.6 1.6-1.8.4-2 1.6-4.6 1.6-7.6 0-4.4-3.2-7.8-7.4-7.8Z'],

  // ── NAVAL STORES ─────────────────────────────────────────────────────────────────────────────
  // Sawn boards stacked with the offset a timber yard stacks them in.
  goodTimber: ['M3.4 6.4h13.6v3.2H3.4z', 'M6.4 10.4h13.6v3.2H6.4z', 'M3.4 14.4h13.6v3.2H3.4z'],
  // A mast standing with its yard across — a spar is a shaped stick, not a plank.
  goodNavalTimber: ['M12 3.4v16.4', 'M5.4 7.4h13.2', 'M8.6 19.8h6.8', 'M10.6 3.4h2.8'],
  // A pitch bucket on its bail, filled to the line.
  goodTar: ['M5.8 8.6h12.4l-1.4 9.6H7.2z', 'M7.2 8.6c0-2.6 2.2-4.6 4.8-4.6s4.8 2 4.8 4.6', 'M6.6 13.4h10.8'],
  // A coil of cordage seen from above — the only annulus in the set.
  goodHemp: ['M12 5.2a6.8 6.8 0 1 0 0 13.6a6.8 6.8 0 1 0 0-13.6Z', 'M12 9.2a2.8 2.8 0 1 0 0 5.6a2.8 2.8 0 1 0 0-5.6Z', 'M6.4 9 9.6 10.6', 'M17.6 9l-3.2 1.6', 'M12 18.8v-4'],
  // A spare sail, cut and seamed — what the canvas is bought to become.
  goodFlax: ['M6.4 4.2v15.2h11.4C13.8 14 10.2 8.6 6.4 4.2Z', 'M7 15.4c2.6.8 4.6 2.2 6 3.8'],
  // A lamp burning it. A whale's fluke was the first cut of this mark and it read as the tea sprig;
  // the thing train oil is actually bought for does not collide with anything.
  goodWhaleOil: ['M4.4 14.2h11.2l3.6-1.6-.8 3c-.7 2.4-2.9 4-5.6 4h-3c-3.2 0-5.4-2.3-5.4-5.4Z', 'M18.6 11.4c-1.5-1.2-2.2-2.4-2.2-3.6 0-1.5 1-2.8 2.2-3.8 1.2 1 2.2 2.3 2.2 3.8 0 1.2-.7 2.4-2.2 3.6Z', 'M4.4 14.6c-1.3 0-2.2-.9-2.2-2s.9-2 2.2-2'],
  // ── rarity tiers (0032) — silhouettes only; see the note on ICON_NAMES ───────────────────────
  // A plain ring: the everyday coin of the catalogue.
  rarityCommon: ['M12 6.6a5.4 5.4 0 1 0 0 10.8a5.4 5.4 0 1 0 0-10.8Z'],
  // A diamond on its point — the first step away from round.
  rarityUncommon: ['M12 4.8 18.8 12 12 19.2 5.2 12Z'],
  // A faceted gem: flat crown, cut shoulders — reads as "cut stone" beside the plain diamond.
  rarityRare: ['M5 9.6 8.4 5.2h7.2L19 9.6 12 19.6Z', 'M5 9.6h14'],
  // A four-point star — the only concave silhouette in the set.
  rarityExotic: ['M12 3.4c.6 4.4 2 5.8 8.6 8.6-6.6 2.8-8 4.2-8.6 8.6-.6-4.4-2-5.8-8.6-8.6 6.6-2.8 8-4.2 8.6-8.6Z'],
}
