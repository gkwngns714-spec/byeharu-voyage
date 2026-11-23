// Design-system icon glyphs — the ONE inline-SVG set. Pure data (no React) so the name→glyph
// contract is testable. Every glyph is 1.5px-stroke line work on a 24×24 viewBox, drawn with
// `currentColor` by <Icon> so it always wears token colors (text-accent, text-ink-muted, …).
//
// The NAVIGATION half of the set is deliberately small. This is a text-and-tabs game: those icons
// decorate empty states and mark a fold, they never replace a word. A glyph enters that half only
// when a screen needs it.
//
// The TRADE-GOOD half covers every good a player meets often: the original seventy each keep
// their own mark, and of the 243-good catalogue every good offered at five or more ports has one
// too — the long tail wears its category glyph beside its name and rarity mark, which is truthful
// and tellable. goodIcons.ts states the policy; the section header below states the drawing rule.

export const ICON_NAMES = [
  'anchor',
  'compass',
  'chart',
  'stats',
  'ship',
  'ledger',
  'wreath',
  'codex',
  'chevron',
  'close',
  'plus',
  'minus',
  'resize',
  'info',
  'search',
  'locate',
  'regions',
  'history',
  'coin',
  'cask',
  'crew',
  'mallet',
  'pick',
  // A captain's trait, by what it does (visual slice 6): the chips on her sheet and the Inn's cards
  'speed',
  'crate',
  'tag',
  'shield',
  'heart',
  'storm',
  'target',
  'cannon',
  'cutlass',
  // ── ONE GLYPH PER DESTINATION (2026-11-23, the visual overhaul's slice 1) ─────────────────────
  'fort',
  'scales',
  'office',
  'trophy',
  'route',
  'mountain',
  'person',
  'cog',
  'menu',
  'laurel',
  'levelUp',
  // The house's title (slice 9): the You page's plate
  'coronet',
  // The Office's doors on HQ (slice 2)
  'invest',
  'report',
  // A ship's three figures (slice 5): her hold, her hull, her speed; and a fleet under way
  'hold',
  'hull',
  'knots',
  'sailing',
  // The Map's filter chips (slice 4)
  'layers',
  'waves',
  'people',
  'banner',
  'pact',
  'wrench',
  'fitting',
  'captain',
  // A price's side on the goods card (slice 3): bought into the hold, sold out of it
  'buyIn',
  'sellOut',
  // Visual pass 3: the face strips' own marks (Stats, History, Rank) and Production's building
  'news',
  'candles',
  'pirate',
  'more',
  'merchant',
  'navy',
  'calendar',
  'helm',
  'nation',
  'works',
  // The seven trade-good CATEGORIES. Not a good's own mark any more — the fallback, for a good
  // that arrives from a migration before anyone has drawn it. See goodIcons.ts.
  'spice',
  'textile',
  'metal',
  'luxury',
  'foodstuff',
  'raw',
  'navalStores',
  // The long tail's FAMILIES (visual slice 9): the twelve categories that wore another category's glyph now wear their own, so a
  // screen of the Codex's rarer grains, drinks or medicines is told apart by family at a glance (goodIcons.ts CATEGORY_ICON).
  'grain',
  'drink',
  'tobacco',
  'medicine',
  'dye',
  'gems',
  'crafts',
  'weapons',
  'guns',
  'art',
  'books',
  'animals',
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
  // ── DRAWN MARKS FOR THE MOST-TRADED OF THE 243-GOOD CATALOGUE ────────────────────────────────
  // When the catalogue grew 70 -> 243, drawing every good stopped being honest work: 173 new
  // goods, most offered at one or two ports, would be 173 marks nobody could tell apart at 22px.
  // The policy is now: every good a player meets OFTEN gets its own mark, and the long tail wears
  // its category glyph — which is truthful (a spice looks like a spice) and already the fallback
  // goodIcon() serves. "Often" is measured, not felt: these twelve are the new goods offered at
  // five or more ports (the uncommon tier and up). A new good that grows into that tier earns its
  // drawing then.
  'goodCitrus',
  'goodCoconuts',
  'goodDates',
  'goodRye',
  'goodBeer',
  'goodCoir',
  'goodSappanwood',
  'goodSoap',
  'goodArecaNuts',
  'goodButter',
  'goodPaper',
  'goodHoney',
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
  // Three bars rising on a baseline — Stats (the world's figures, 0214). Not the folded chart: that
  // mark already means the Map tab, and a figure is not a place.
  stats: ['M3.5 20.5h17', 'M6 17v-5', 'M12 17V7', 'M18 17v-8'],
  // Hull with a mast and sail — Fleets.
  ship: ['M3 17.5h18l-2 3.5H5l-2-3.5Z', 'M12 3v14.5', 'M12 5c3 1 5 2.5 6 4.5h-6', 'M12 8c-2 .8-3.5 1.5-4.5 3H12'],
  // Balance — Market.
  // Open book — Ledger.
  ledger: ['M12 6.5C10.5 5 8.5 4.5 6 4.5H3.5v13H6c2.5 0 4.5.5 6 2', 'M12 6.5c1.5-1.5 3.5-2 6-2H20.5v13H18c-2.5 0-4.5.5-6 2', 'M12 6.5v15'],
  // Laurel-ringed marker — Rank.
  wreath: ['M12 3.5a8.5 8.5 0 0 1 0 17', 'M12 3.5a8.5 8.5 0 0 0 0 17', 'M8.5 12h7', 'M12 8.5v7'],
  // CLOSED book with a bookmark — Compendium (the reference you look things up in). The OPEN book
  // is the Ledger's, and the two must stay tellable apart: the record you write vs the book you consult.
  codex: ['M7 2.5h12.5v19H7A2.5 2.5 0 0 1 4.5 19V5A2.5 2.5 0 0 1 7 2.5Z', 'M4.5 19a2.5 2.5 0 0 1 2.5-2.5h12.5', 'M13.5 2.5V9l2.25-1.7L18 9V2.5'],
  // Chevron (points right; rotate via className for other directions).
  chevron: ['m9 5 7 7-7 7'],
  close: ['M6 6l12 12', 'M18 6 6 18'],
  plus: ['M12 5v14', 'M5 12h14'],
  // The counterpart of `plus`. Added in step 2 for `Stepper`: docs/UI_DIRECTION.md §4.5 bans the
  // text glyphs this game drew its controls with (`▾ ▓ ⚑ ✕ > −`), and a stepper whose `+` is a drawn
  // stroke and whose `−` is a MINUS SIGN CHARACTER is the ban half-kept.
  minus: ['M5 12h14'],
  // Two arrowheads on one diagonal: the minimap's grip (drag to make it larger or smaller).
  resize: ['M14 4h6v6', 'M10 20H4v-6', 'M20 4 4 20'],
  info: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M12 11v5.5', 'M12 7.6v.9'],
  search: ['M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14Z', 'm16.2 16.2 4.3 4.3'],
  // Crosshair with a centre point — the chart's "find" control (ViewControls): bring what this
  // surface is about back onto the glass. Not the compass, deliberately: that mark already means
  // Command (navTabs) and SAIL (verbIcons), and one glyph carrying a third meaning is a glyph
  // carrying none.
  locate: [
    'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14Z',
    'M12 2.5V5',
    'M12 19v2.5',
    'M2.5 12H5',
    'M19 12h2.5',
    'M12 10.8a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4Z',
  ],
  // A globe parted into regions — the chart's Regions filter (ViewControls, owner row 93). Not
  // the folded chart: that mark already means the Map tab.
  regions: [
    'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z',
    'M3.6 9.5c2.8 1.8 5.6.2 8.4 1.6s5.6 3 8.4 1.2',
    'M12 3c-3.2 4.2-3.2 13.8 0 18',
  ],
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
  // 0455: a miner's pick, the Land tab's mark (docs/design/land-2026-11.md 6.7): the head's arc and the haft
  pick: ['M3.5 9.5C7.5 5.2 14.5 4.2 20.5 7', 'M12.4 5.6 8.5 20.5'],

  // ── WHAT A CAPTAIN'S TRAIT DOES (2026-11-23, the visual overhaul's slice 6) ──────────────────────
  // One glyph an effect of data/captains.json `effects` (captainWords.ts `traitEffect` reads it from the served line), so a trait
  // is a chip of mark and figure, not a sentence. Days of supplies wear the `cask` they wear everywhere; nothing here is a place's.
  // Three lines streaming behind a point — speed.
  speed: ['M3 8h8.5', 'M1.5 12h11', 'M3 16h8.5', 'M14.5 6.5 20 12l-5.5 5.5'],
  // A crate on its corner — cargo space (the hold).
  crate: ['M4 8 12 4l8 4v8.5L12 20.5 4 16.5V8Z', 'M4 8l8 4 8-4', 'M12 12v8.5'],
  // A price tag with its eyelet — better prices.
  tag: ['M3.5 4h8.2l8.8 8.8-7.7 7.7L4 11.7V4Z', 'M8 7.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z'],
  // A shield — fewer crew lost to pirates.
  shield: ['M12 3 19.5 6v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6L12 3Z'],
  // A heart — homesickness eased.
  heart: ['M12 20s-7.5-4.6-7.5-10A4.2 4.2 0 0 1 12 7.6 4.2 4.2 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10Z'],
  // A bolt — less storm damage.
  storm: ['M13.5 2.5 5.5 13.5h6l-1 8 8-11h-6l1-8Z'],
  // Rings and a bead — accuracy. Not `locate`: that is the chart's find control.
  target: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M12 7.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9Z', 'M12 11.2a.8.8 0 1 0 0 1.6.8.8 0 0 0 0-1.6Z'],
  // A gun on its wheel — reach.
  cannon: ['M2.5 11.5 15 7l1.6 4.4L4 16Z', 'M16.4 9.2h4.6', 'M8.5 14.5a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z'],
  // One blade with its guard — attack. The crossed blades are the Combat level's (levelWords.ts).
  cutlass: ['M5 19 17 5.5c1.6 1.4 2 3.2 1.2 5L8 20.5', 'M3.5 16.5l4 4', 'M4.5 19.5 3 21'],

  // ── ONE GLYPH PER DESTINATION (2026-11-23, docs/design/visual-overhaul-2026-11-23.md, slice 1) ──
  // The bar and the Menu drew HQ and Rank with the same wreath, Map and Routes with the same chart, Office with the coin that
  // is also the Trading level's mark, and Trade with the compass that is also Exploration's. A glyph that means two places
  // means none, so every destination has its own here, and each is drawn to read at 22 px on a 56-px cell.
  // A harbour fort: the house's seat in its home city — HQ.
  fort: ['M3.5 20.5h17', 'M5 20.5V9.5h14v11', 'M5 9.5V5h2.6v2h2.2V5h4.4v2h2.2V5H19v4.5', 'M10 20.5v-3.8a2 2 0 0 1 4 0v3.8'],
  // A merchant's balance — Trade (buy here, sell there).
  scales: ['M12 4v16', 'M8 20h8', 'M5 7.5h14', 'M5 7.5 2.6 13a2.4 2.4 0 0 0 4.8 0L5 7.5', 'M19 7.5 16.6 13a2.4 2.4 0 0 0 4.8 0L19 7.5'],
  // A counting house under its pediment — Office (the city, investments, the report).
  office: ['M3.5 9 12 4l8.5 5', 'M4.5 9h15', 'M6.5 9v8.5', 'M10.2 9v8.5', 'M13.8 9v8.5', 'M17.5 9v8.5', 'M4.5 17.5h15', 'M3.5 20.5h17'],
  // A cup on its foot — Rank.
  trophy: ['M7.5 4h9v5a4.5 4.5 0 0 1-9 0V4Z', 'M7.5 6H4.5a3 3 0 0 0 3.2 3.9', 'M16.5 6h3a3 3 0 0 1-3.2 3.9', 'M12 13.5v3.5', 'M8.5 20.5h7', 'M9.5 17h5v3.5'],
  // Two harbours and the lane between them — Routes.
  route: ['M6 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z', 'M18 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z', 'M7.6 16.8c2.4-1.6 1-4.8 4.4-5.8s4.6-1.6 4.8-3.8'],
  // A peak with its snow line — Land (the party ashore).
  mountain: ['M2.5 19.5 9.5 6.5l4.2 7.2 2.3-3.4 5.5 9.2H2.5Z', 'M7.4 10.4l2.1 1.6 2.1-1.6'],
  // One head and shoulders — You (who you have become). `crew` (two figures) stays the inn's and the captains'.
  person: ['M12 3.8a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2Z', 'M4.8 20.2a7.2 7.2 0 0 1 14.4 0'],
  // A cog — Profile (the account and its settings).
  cog: [
    'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z',
    'M10.4 3.2h3.2l.5 2.4 1.9 1.1 2.3-.8 1.6 2.8-1.8 1.6v2.2l1.8 1.6-1.6 2.8-2.3-.8-1.9 1.1-.5 2.4h-3.2l-.5-2.4-1.9-1.1-2.3.8-1.6-2.8 1.8-1.6v-2.2L4.1 8.7l1.6-2.8 2.3.8 1.9-1.1.5-2.4Z',
  ],
  // Four tiles — the Menu (the group that opens the rest). The chevron it wore said "this opens"; the tray's own handle says
  // that once it stands, and a grid says "more places" at a glance, as every game's menu button does.
  menu: ['M4.5 4.5h6v6h-6z', 'M13.5 4.5h6v6h-6z', 'M4.5 13.5h6v6h-6z', 'M13.5 13.5h6v6h-6z'],
  // A laurel, two branches open at the top — Reputation (what the world thinks of your house). The wreath stays City hall's.
  laurel: ['M9 20.5c-3.4-1.6-5.5-5-5.5-8.7 0-3 1.2-5.6 3.2-7.3', 'M15 20.5c3.4-1.6 5.5-5 5.5-8.7 0-3-1.2-5.6-3.2-7.3', 'M4 9.6l2.4.6', 'M3.8 13.6l2.4-.2', 'M5.4 17.4l2-1', 'M20 9.6l-2.4.6', 'M20.2 13.6l-2.4-.2', 'M18.6 17.4l-2-1'],
  // Two chevrons climbing — Levels (the company's levels, a rank's stripes).
  levelUp: ['m6 12.5 6-6 6 6', 'm6 18.5 6-6 6 6'],
  // A coronet, five points over its band — the house's TITLE (slice 9). Not the wreath (City hall) nor the laurel (Reputation).
  coronet: ['M5 17 3.8 8.5l4.4 3.6L12 5.5l3.8 6.6 4.4-3.6L19 17Z', 'M5 20h14', 'M12 13.2a1 1 0 1 0 0 2a1 1 0 1 0 0-2Z'],
  // ── THE OFFICE'S DOORS ON HQ (2026-11-23, the visual overhaul's slice 2): City wears the Office's counting house; these two are new.
  // A stack of coins with a rising arrow — Invest (money put into a city). Not the coin: that is the purse and the Trading level.
  invest: ['M3.5 20h10', 'M3.5 16.5h10', 'M4.5 13h8', 'M3.5 20v-3.5', 'M13.5 20v-3.5', 'M15 12.5 20.5 7', 'M16.5 7h4v4'],
  // A page with a folded corner and its lines — Report (the company's book of results). Not the open book: that is History.
  report: ['M6 3h8.5L19 7.5V21H6V3Z', 'M14.5 3v4.5H19', 'M9 12h7', 'M9 15.5h7', 'M9 19h4'],
  // ── A SHIP'S FIGURES AS MARKS (2026-11-23, the visual overhaul's slice 5: "[hold] 0 / 194", never "Cargo 0 / 194 tons" in words) ──────────
  // A crate seen from a corner — the Hold (what she carries, against what she can). Not the cask: that is her supplies.
  hold: ['M12 3.5 20 7.5v9L12 20.5 4 16.5v-9L12 3.5Z', 'M4 7.5 12 11.5l8-4', 'M12 11.5v9', 'M8 5.5l8 4'],
  // A hull from the side, her planking and her keel, no mast — the Hull (how sound she is). Not the ship: that is the Fleets tab.
  hull: ['M2.5 9.5h19l-2.6 7.2a2 2 0 0 1-1.9 1.3H7a2 2 0 0 1-1.9-1.3L2.5 9.5Z', 'M3.9 13.4h16.2', 'M12 18v2.5'],
  // Three lines of wind, two curling — her Speed in knots. Not the compass: that is the Exploration level.
  knots: ['M3 8.5h10.5a2.5 2.5 0 1 0-2.5-2.5', 'M3 12.5h16', 'M3 16.5h8.5a2.5 2.5 0 1 1-2.5 2.5'],
  // A sail full of wind over a wave — Under way (how many of your fleets are sailing). Not the ship: that is the Fleets tab.
  sailing: ['M7 3.5v13', 'M7 3.5c5 1.6 8.2 5.3 8.8 10.5H7', 'M3 20c2-1.3 4-1.3 6 0s4 1.3 6 0 4-1.3 6 0'],
  // ── THE MAP'S FILTER CHIPS (2026-11-23, the visual overhaul's slice 4) ──
  // Three sheets stacked — the chart's filter itself, and its "Off" chip (the plain chart). `regions` stays the Regions chip.
  layers: ['M12 4 3 8.5l9 4.5 9-4.5L12 4Z', 'M3 12.5l9 4.5 9-4.5', 'M3 16.5l9 4.5 9-4.5'],
  // Three swells — the Seas chip (the sea zones, their waves and what each asks to pass). Not `route`, not the chart.
  waves: ['M3 8c2-1.6 4-1.6 6 0s4 1.6 6 0 4-1.6 6 0', 'M3 13c2-1.6 4-1.6 6 0s4 1.6 6 0 4-1.6 6 0', 'M3 18c2-1.6 4-1.6 6 0s4 1.6 6 0 4-1.6 6 0'],
  // ── VISUAL PASS 2 (2026-11-23): the facts that were still a word with no mark ──
  // Three roofs in a row — a city's Population. Not `crew` (your hands) nor `person` (You).
  people: ['M2.5 20.5h19', 'M3.5 20.5v-6l3.5-3 3.5 3v6', 'M10.5 20.5V11l3.5-3.5 3.5 3.5v9.5', 'M17.5 20.5v-6l2-1.8'],
  // A pennant on its pole — your Status in a city (your influence points there). Not the flag tile: that is a country.
  banner: ['M6 21V3.5', 'M6 4.5h12l-3 4 3 4H6'],
  // Two clasped rings — a city's Relationship with you. Not the heart: that is a captain's trait.
  pact: ['M9 8.5a5 5 0 1 0 0 7', 'M15 15.5a5 5 0 1 0 0-7', 'M9 12h6'],
  // A spanner — Repair (a hull made whole). Not the mallet: that is the build yard and Shipbuilding.
  wrench: ['M14.7 6.3a4 4 0 0 0 5 5L12 19a2.1 2.1 0 0 1-3-3l7.7-7.7a4 4 0 0 0-2-2Z', 'M14.7 6.3 17 4'],
  // A block and its hook — Gear (the fittings a ship carries). Not the cog: that is the Account.
  fitting: ['M12 2.5v3', 'M12 5.5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9Z', 'M12 8.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3Z', 'M12 14.5v3a2.5 2.5 0 1 1-2.5 2.5'],
  // A tricorne — Captains (the people you hire to sit in a ship's cabins). Not `person` (You) nor `crew` (the hands).
  captain: ['M2.5 14.5c3 .8 6 1.2 9.5 1.2s6.5-.4 9.5-1.2', 'M4 14.7 6.5 9c1.6.8 3.5 1.2 5.5 1.2s3.9-.4 5.5-1.2l2.5 5.7', 'M12 10.2V7.5'],
  // ── A PRICE'S SIDE ON THE GOODS CARD (2026-11-23, the visual overhaul's slice 3: the card's two prices read Buy / Sell by tone and
  // arrow, not by word). An arrow down into an open tray — BUY (what the city asks: goods come into your hold). An arrow up out of
  // it — SELL (what the city bids: goods go out, coin comes in). Not the chevron, not levelUp: those are a door and the Levels.
  buyIn: ['M12 3.5v11', 'm7.5 10 4.5 4.5 4.5-4.5', 'M4 15.5v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3'],
  sellOut: ['M12 14.5v-11', 'm7.5 8 4.5-4.5 4.5 4.5', 'M4 15.5v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3'],
  // ── VISUAL PASS 3 (2026-11-23): the Stats, History and Rank face strips draw a mark over each word ──
  // A folded news sheet, its columns of lines — Stats > News. Not the report's page: that is the company's book.
  news: ['M4 4.5h12.5v14.5a1.5 1.5 0 0 0 1.5 1.5H6A2 2 0 0 1 4 18.5V4.5Z', 'M16.5 8.5h3.5V19a1.5 1.5 0 0 1-3 0', 'M7 8h6.5', 'M7 11.5h6.5', 'M7 15h4'],
  // Two price candles on their wicks — Stats > Markets (what the goods trade at). Not `stats` (the tab) nor `invest`.
  candles: ['M7.5 3.5v17', 'M5.5 7.5h4v8h-4z', 'M16.5 3.5v17', 'M14.5 10h4v6h-4z'],
  // A skull over crossed bones — the pirates (Stats > Pirates, Rank > Bounties: the named pirates).
  pirate: [
    'M12 3.5a6 6 0 0 0-6 6c0 2 1 3.4 2.2 4.3V16h7.6v-2.2C17 12.9 18 11.5 18 9.5a6 6 0 0 0-6-6Z',
    'M9.8 9.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z',
    'M14.2 9.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z',
    'M5 17.5 19 21',
    'M19 17.5 5 21',
  ],
  // Three dots — More (the faces folded behind one cell). Not the Menu's four tiles.
  more: ['M5.5 10.7a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6Z', 'M12 10.7a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6Z', 'M18.5 10.7a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6Z'],
  // A tied sack of goods — the merchant companies. Not the hold (cargo space) nor the crate (a store).
  merchant: ['M9 4h6l-1.6 3.2c3.4 1.1 5.6 4.6 5.6 8.3a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4c0-3.7 2.2-7.2 5.6-8.3L9 4Z', 'M10.6 7.2h2.8'],
  // A star over the swell — a country's navy. Not the shield: that is a captain's trait.
  navy: ['M12 3l1.8 3.7 4 .6-2.9 2.8.7 4-3.6-1.9-3.6 1.9.7-4-2.9-2.8 4-.6L12 3Z', 'M3 19c2-1.5 4-1.5 6 0s4 1.5 6 0 4-1.5 6 0'],
  // A page of a calendar — Rank > Week (the houses' board of the week).
  calendar: ['M4 6h16v14H4z', 'M4 10h16', 'M8 3.5v4', 'M16 3.5v4', 'M8 14h2', 'M14 14h2', 'M8 17h2'],
  // A ship's wheel — Rank > Captains (the companies' board). Not the tricorne: that is a hired captain.
  helm: [
    'M12 5.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13Z',
    'M12 10.3a1.7 1.7 0 1 0 0 3.4 1.7 1.7 0 0 0 0-3.4Z',
    'M12 2.5v7.8',
    'M12 13.7v7.8',
    'M2.5 12h7.8',
    'M13.7 12h7.8',
    'M5.3 5.3l5.5 5.5',
    'M13.2 13.2l5.5 5.5',
    'M18.7 5.3l-5.5 5.5',
    'M10.8 13.2l-5.5 5.5',
  ],
  // A square flag with its cross on a pole — Rank > Countries. Not the pennant: that is your Status in a city.
  nation: ['M5 21V3.5', 'M5 4.5h14v9H5', 'M11 4.5v9', 'M5 9h14'],
  // A workshop under its saw-tooth roof, its chimney — HQ's Production (storage, cargo, recipes). The mallet stays the build yard.
  works: ['M3.5 20.5h17', 'M4.5 20.5v-9l5 3v-3l5 3v-3l5 3v6', 'M16.5 12.5V4h2.5v10'],

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
  // ── the long tail's families (visual slice 9): one silhouette each, apart from every good's own mark ─────────────────────
  // Grain: a sheaf — three stalks bound at the waist, three heads.
  grain: ['M8 21 12 14 8.5 6.5', 'M16 21l-4-7 3.5-7.5', 'M12 21V5.5', 'M9.6 14h4.8', 'M8.5 6.5c-1-1-1-2.6 0-3.8 1 1.2 1 2.8 0 3.8Z', 'M12 5.5c-1-1-1-2.6 0-3.8 1 1.2 1 2.8 0 3.8Z', 'M15.5 6.5c-1-1-1-2.6 0-3.8 1 1.2 1 2.8 0 3.8Z'],
  // Drink: an amphora — lip, neck, round belly and two handles.
  drink: ['M9.5 3.5h5', 'M10.5 3.5v3c-2.5 1-4 3.5-4 6.5 0 3.6 2.4 7 5.5 7s5.5-3.4 5.5-7c0-3-1.5-5.5-4-6.5v-3', 'M7.6 10C5.8 9.4 5.2 7.6 6.4 6.4', 'M16.4 10c1.8-.6 2.4-2.4 1.2-3.6'],
  // Tobacco: a clay pipe — the bowl, the long stem, a curl of smoke.
  tobacco: ['M4.5 10h5v4a2.5 2.5 0 0 1-5 0Z', 'M9.5 12.6 20.5 9', 'M7 7.5c-1-1-1-2.2 0-3.4'],
  // Medicine: an apothecary's bottle with a cross on its belly.
  medicine: ['M9.5 3.5h5', 'M10.5 3.5V7L7 10.8v8.2A1.5 1.5 0 0 0 8.5 20.5h7A1.5 1.5 0 0 0 17 19v-8.2L13.5 7V3.5', 'M12 12.5v5', 'M9.5 15h5'],
  // Dye: a skein dipped in a vat.
  dye: ['M5 11.5h14l-1.5 8.5h-11Z', 'M5.6 14.5h12.8', 'M7.5 4h9', 'M10 4c0 3.4.6 5.6 2 7.5 1.4-1.9 2-4.1 2-7.5'],
  // Gems: a ring with its stone set high.
  gems: ['M12 10a5.2 5.2 0 1 0 0 10.4a5.2 5.2 0 1 0 0-10.4Z', 'M9.8 6.8 12 3.6l2.2 3.2L12 10Z'],
  // Crafts: a woven basket with its handle.
  crafts: ['M4.5 10.5h15l-2 9h-11Z', 'M8 10.5a4 4 0 0 1 8 0', 'M5.2 13.6h13.6', 'M5.9 16.6h12.2', 'M10 10.5v9', 'M14 10.5v9'],
  // Weapons: a halberd — the pole, the axe's blade, its back spike.
  weapons: ['M12 2.5v19', 'M12 5c3 0 5 1.6 5 4s-2 4-5 4', 'M12 8.5H8.5'],
  // Guns: a musket — the barrel, the stock, the trigger's guard.
  guns: ['M2.5 10h12.5', 'M15 9h2.6l3.9 4.6-2.2 1.6-3.4-3.2H15Z', 'M12.2 11c0 1.6 1 2.6 2.6 2.6'],
  // Art: a framed portrait.
  art: ['M4.5 3.5h15v17h-15Z', 'M7 6h10v12H7Z', 'M12 8.4a1.8 1.8 0 1 0 0 3.6a1.8 1.8 0 1 0 0-3.6Z', 'M8.8 16.4c.6-1.8 1.8-2.6 3.2-2.6s2.6.8 3.2 2.6'],
  // Books: three on a shelf, the last one leaning.
  books: ['M3.5 20.5h17', 'M5 5h3v15.5H5Z', 'M8 7.5h3v13H8Z', 'M12.5 8.4l2.9-.8 3.5 12.6-2.9.8Z'],
  // Animals: an ox's head — the horns, the long face, the muzzle.
  animals: ['M8 10c0 5 1.8 9 4 9s4-4 4-9c0-2-1.8-3.5-4-3.5S8 8 8 10Z', 'M8.4 8C6 8 4.5 6.5 4.2 4.5', 'M15.6 8c2.4 0 3.9-1.5 4.2-3.5', 'M10 15.8c1.3.8 2.7.8 4 0'],

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
  // Lemon: the pointed-oval fruit with a stem leaf — nothing else in the set is a tipped ellipse.
  goodCitrus: ['M6.2 9.8a6.6 5 45 1 0 9.4 9.4a6.6 5 45 1 0 -9.4-9.4Z', 'M6.2 9.8 4.6 8.2', 'M15.6 4.4c1.6-.4 3 0 4 1.2-1.2 1-2.6 1.2-4 .4-.4-.6-.4-1.2 0-1.6Z', 'M16.4 6.4l-1.6 2.2'],
  // Coconut: the round nut with its three germination eyes — a circle carrying three dots.
  goodCoconuts: ['M12 4.6a7.6 7.6 0 1 0 0 15.2a7.6 7.6 0 1 0 0-15.2Z', 'M12 8.6a.9.9 0 1 0 0 1.8a.9.9 0 1 0 0-1.8Z', 'M9.4 13a.9.9 0 1 0 0 1.8a.9.9 0 1 0 0-1.8Z', 'M14.6 13a.9.9 0 1 0 0 1.8a.9.9 0 1 0 0-1.8Z'],
  // Date palm: trunk, four fronds, and the hanging fruit cluster under them.
  goodDates: ['M12 21V9.5', 'M12 9.5C9.5 9.5 7 8 5.5 5.5 8.5 5 11 6.5 12 9.5Z', 'M12 9.5c2.5 0 5-1.5 6.5-4-3-.5-5.5 1-6.5 4Z', 'M12 9.5C10.5 7 10.5 4.5 12 2.5c1.5 2 1.5 4.5 0 7Z', 'M9.8 11.6a1.1 1.1 0 1 0 0 2.2a1.1 1.1 0 1 0 0-2.2Z', 'M14.2 11.6a1.1 1.1 0 1 0 0 2.2a1.1 1.1 0 1 0 0-2.2Z'],
  // Rye: a bearded ear — the awns wheat's twin-lobed glyph deliberately does not have.
  goodRye: ['M12 21V4.5', 'M12 7.5 8.5 4', 'M12 7.5 15.5 4', 'M12 11 8.5 7.5', 'M12 11l3.5-3.5', 'M12 14.5 8.5 11', 'M12 14.5l3.5-3.5'],
  // Beer: a tankard — body, handle and the foam standing proud of the rim.
  goodBeer: ['M6.5 8.5h9.5V20a1 1 0 0 1-1 1h-7.5a1 1 0 0 1-1-1Z', 'M16 11h2.2a2.6 2.6 0 0 1 0 5.2H16', 'M6.5 8.5c-.4-2.6 1-4.2 2.8-4.2 .6-1 1.6-1.6 2.8-1.6 1.4 0 2.6.8 3 2 1.6.4 2.4 1.8 1.9 3.8Z'],
  // Coir: a coiled rope with its working end loose — read as rope, not as the hemp leaf-ring.
  goodCoir: ['M12 5.4a6.6 6.6 0 1 0 0 13.2a6.6 6.6 0 1 0 0-13.2Z', 'M12 8.8a3.2 3.2 0 1 0 0 6.4a3.2 3.2 0 1 0 0-6.4Z', 'M17 16.6 21 20.4', 'M18.6 15l2.9 2.9'],
  // Sappanwood: a split billet dripping its dye — two staves and the drop beneath.
  goodSappanwood: ['M5 4.8h4l1.6 12H6.6Z', 'M15 4.8h4l-1.6 12h-4Z', 'M12 17.4c-1 1.2-1.5 2.1-1.5 2.9a1.5 1.5 0 0 0 3 0c0-.8-.5-1.7-1.5-2.9Z'],
  // Soap: a bar with rising bubbles.
  goodSoap: ['M4.5 12.5a2 2 0 0 1 2-2h11a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2Z', 'M8.5 6.8a1.4 1.4 0 1 0 0 2.8a1.4 1.4 0 1 0 0-2.8Z', 'M13.4 3.6a2 2 0 1 0 0 4a2 2 0 1 0 0-4Z', 'M17.6 7.4a1.1 1.1 0 1 0 0 2.2a1.1 1.1 0 1 0 0-2.2Z'],
  // Areca: the pointed betel leaf with two nuts at its foot.
  goodArecaNuts: ['M12 2.8c4 2.6 6 5.8 6 9 0 3.4-2.6 6-6 6s-6-2.6-6-6c0-3.2 2-6.4 6-9Z', 'M12 6v11', 'M9.2 18.6a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0Z', 'M13.6 19.4a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0 -2.6 0Z'],
  // Butter: the slab on its dish, a pat cut off the end.
  goodButter: ['M4 16.5h16', 'M5.5 16.5 7 19h10l1.5-2.5', 'M6.5 16.5v-4h8v4', 'M14.5 12.5h3.5v4', 'M14.5 14.5h3.5'],
  // Paper: a scroll — rolled head, hanging sheet, two written lines.
  goodPaper: ['M8 4.2a2.2 2.2 0 1 0 0 4.4h11a2.2 2.2 0 0 1-2.2-2.2A2.2 2.2 0 0 0 14.6 4.2Z', 'M8 8.6h8.8V19a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V6.4', 'M9.5 12.4h5.8', 'M9.5 15.6h5.8'],
  // Honey: the straw skep — dome, coiled bands, and its little arch of a door.
  goodHoney: ['M12 4.5c-4.4 0-7.5 3.6-7.5 8.2 0 2.6.8 4.8 2.2 6.3h10.6c1.4-1.5 2.2-3.7 2.2-6.3 0-4.6-3.1-8.2-7.5-8.2Z', 'M5 9.6h14', 'M4.5 14h15', 'M5.8 17h12.4', 'M12 19v-2.6a1.6 1.6 0 0 0-1.6-1.6', 'M12 19v-2.6a1.6 1.6 0 0 1 1.6-1.6'],
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
