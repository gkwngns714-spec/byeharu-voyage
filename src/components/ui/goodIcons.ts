import type { IconName } from './icons'

// A MARK FOR A TRADE GOOD — the one mapping from a good to the glyph that stands for it.
//
// ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
// `GOOD_ICON` gives EVERY good in `data/goods.json` — all seventy — its own drawn mark. It is the
// primary table and it is complete: the seventy rows below are the seventy rows of that file, in
// its order, and the glyphs they name are drawn in icons.ts under "ONE MARK PER TRADE GOOD".
//
// `CATEGORY_ICON` is the FALLBACK, and only that. A good that arrives from a future migration
// before anyone has drawn it still gets a truthful mark on the day it lands — a spice looks like a
// spice — and nothing here can throw.
//
// ── WHY IT IS SEVENTY AND NOT SEVEN ─────────────────────────────────────────────────────────────
// It was seven, one per category, and that was the wrong answer to a question the owner asked
// twice. A picker of seventy rows that repeats seven marks is a picker whose marks carry no
// information: the reader still has to read every name, and the icon column is then pure cost.
// Distinguishing seventy things is the entire job, not a decoration on top of it.
//
// The hard part is not drawing seventy pictures, it is drawing seventy pictures that are still
// TELLABLE APART at the 22px the good picker renders them at. icons.ts states the rule the glyphs
// obey — separate by outer silhouette, spend interior detail only after the silhouette is won —
// and this file's job is just to be exhaustive and to stay in step with the data.
//
// ── KEEPING IT IN STEP ──────────────────────────────────────────────────────────────────────────
// The keys are good `code`s (the `id` column of data/goods.json, which is what `MarketGood.code`
// and `SnapshotGood.code` carry). The values are `IconName`, so a glyph named here that does not
// exist in ICON_NAMES is a COMPILE error rather than a blank square at runtime. Adding a good is
// three edits — the glyph, its name in ICON_NAMES, its row here — and missing the third is the
// only one of the three that fails quietly, which is why the fallback exists.

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

/** Good `code` → its own mark. Complete over `data/goods.json`, in that file's order. */
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
