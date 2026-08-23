import type { IconName } from './icons'

// A MARK FOR A TRADE GOOD — the one mapping from a good to the glyph that stands for it.
//
// ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
// `GOOD_ICON` gives a good its own drawn mark; `CATEGORY_ICON` is the fallback — a good with no
// drawing of its own wears its category's glyph, which is truthful (a spice looks like a spice)
// and can never throw.
//
// ── THE POLICY, SINCE THE CATALOGUE GREW 70 -> 243 ──────────────────────────────────────────────
// When the catalogue was seventy goods, every one had its own mark, because a picker of seventy
// rows that repeats seven marks is a picker whose marks carry no information. At 243 goods that
// arithmetic INVERTS: most of the catalogue is a long tail of one- and two-port specialities a
// player meets rarely, and 243 hand-drawn marks could not stay tellable apart at the 22px the
// good picker renders them at — the design constraint icons.ts states (separate by outer
// silhouette first) runs out of distinct silhouettes long before 243.
//
// So the rule is now MEASURED, not felt: every good offered at FIVE OR MORE ports (the uncommon
// tier and up — the goods a player actually meets on quay after quay) has its own drawn mark; the
// long tail wears its category glyph plus its name and rarity mark, which together already
// distinguish it. The original seventy keep their drawings; the twelve most-traded of the new
// catalogue earned theirs; a tail good that grows into the uncommon tier earns its drawing then.
//
// ── KEEPING IT IN STEP ──────────────────────────────────────────────────────────────────────────
// The keys are good `code`s (the `id` column of data/goods.json, which is what `MarketGood.code`
// and `SnapshotGood.code` carry). The values are `IconName`, so a glyph named here that does not
// exist in ICON_NAMES is a COMPILE error rather than a blank square at runtime.

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

/** Good `code` → its own mark: the original seventy, plus every newer good offered at 5+ ports. */
const GOOD_ICON: Record<string, IconName> = {
  // spice
  'black-pepper': 'goodBlackPepper',
  cloves: 'goodCloves',
  nutmeg: 'goodNutmeg',
  mace: 'goodMace',
  cinnamon: 'goodCinnamon',
  ginger: 'goodGinger',
  cardamom: 'goodCardamom',
  // textile
  'wool-cloth': 'goodWoolCloth',
  linen: 'goodLinen',
  'cotton-cloth': 'goodCottonCloth',
  muslin: 'goodMuslin',
  chintz: 'goodChintz',
  'silk-cloth': 'goodSilkCloth',
  'silk-raw': 'goodSilkRaw',
  carpets: 'goodCarpets',
  'ramie-cloth': 'goodRamieCloth',
  // metal
  gold: 'goodGold',
  silver: 'goodSilver',
  copper: 'goodCopper',
  tin: 'goodTin',
  iron: 'goodIron',
  // luxury
  porcelain: 'goodPorcelain',
  lacquerware: 'goodLacquerware',
  glassware: 'goodGlassware',
  pearls: 'goodPearls',
  diamonds: 'goodDiamonds',
  ivory: 'goodIvory',
  ambergris: 'goodAmbergris',
  musk: 'goodMusk',
  coral: 'goodCoral',
  amber: 'goodAmber',
  frankincense: 'goodFrankincense',
  myrrh: 'goodMyrrh',
  // foodstuff
  wheat: 'goodWheat',
  rice: 'goodRice',
  sugar: 'goodSugar',
  salt: 'goodSalt',
  'olive-oil': 'goodOliveOil',
  wine: 'goodWine',
  'dried-fish': 'goodDriedFish',
  herring: 'goodHerring',
  cheese: 'goodCheese',
  'salted-beef': 'goodSaltedBeef',
  coffee: 'goodCoffee',
  tea: 'goodTea',
  cacao: 'goodCacao',
  'dried-fruit': 'goodDriedFruit',
  // raw
  tobacco: 'goodTobacco',
  indigo: 'goodIndigo',
  cochineal: 'goodCochineal',
  brazilwood: 'goodBrazilwood',
  logwood: 'goodLogwood',
  alum: 'goodAlum',
  saltpetre: 'goodSaltpetre',
  sulphur: 'goodSulphur',
  hides: 'goodHides',
  furs: 'goodFurs',
  wax: 'goodWax',
  'cotton-raw': 'goodCottonRaw',
  'wool-raw': 'goodWoolRaw',
  'gum-arabic': 'goodGumArabic',
  sandalwood: 'goodSandalwood',
  ginseng: 'goodGinseng',
  horses: 'goodHorses',
  // naval stores
  timber: 'goodTimber',
  'naval-timber': 'goodNavalTimber',
  tar: 'goodTar',
  hemp: 'goodHemp',
  flax: 'goodFlax',
  'whale-oil': 'goodWhaleOil',
  // the most-traded of the 243-good catalogue (offered at 5+ ports); the tail wears its category
  citrus: 'goodCitrus',
  coconuts: 'goodCoconuts',
  dates: 'goodDates',
  rye: 'goodRye',
  beer: 'goodBeer',
  coir: 'goodCoir',
  sappanwood: 'goodSappanwood',
  soap: 'goodSoap',
  'areca-nuts': 'goodArecaNuts',
  butter: 'goodButter',
  paper: 'goodPaper',
  honey: 'goodHoney',
}

/**
 * The glyph for a good. Give it the good's `code` and `category` — both are on `MarketGood` and on
 * `SnapshotGood`, so no caller has to look anything up. The category is the fallback for a good
 * that has no drawn mark yet; every good in today's data has one.
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
