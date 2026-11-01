import { categoryLabel } from './goodIcons'
import { GoodClassMark } from './GoodClassMark'
import { RarityMark } from './Rarity'

// WHAT A GOOD IS, IN THREE SERVED WORDS — its KIND, how RARE it is, and its CLASS.
//
// The owner, 2026-10-20 (docs/OWNER_REQUESTS.md row 177): *"The trade goods should show rarity, and
// what class? What sort it is classified, such as food, weapon, spice etc."* And 2026-11-01:
// *"new trade goods - distinctive class showing what is more premium."* (0294)
//
// ALL THREE ALREADY COME OFF THE WIRE, and this composition decides none of them:
//   · the KIND is `goods.category` — one of seventeen authored in `data/goods.json` (food, cloth,
//     crafts, drink, medicine, dye, ship supplies, metal, gems, spice, guns, animals, grain, art,
//     weapons, books, tobacco), served on `snapshot.goods[]` and on every market row, and read
//     into the player's word by `categoryLabel` (goodIcons.ts), which is also the Korean entrance;
//   · the RARITY is the served tier (`public.good_rarity`, 0032 as 0051 rescaled it: how few
//     harbours produce the good, measured against the mean for this world — never its price),
//     drawn by `RarityMark`, the one rendering of it;
//   · the CLASS is the served premium class (`public.good_class`, 0294: how much a ton of the good
//     is worth, 1 basic … 5 luxury — never its rarity), drawn by `GoodClassMark`, the one rendering
//     of it. The rarity mark and the class mark are NOT the same idea and do not share a shape: a
//     glyph, and a five-bar meter.
// There is no list of 629 goods anywhere in this client and there must never be one.
//
// WHY A COMPOSITION AND NOT LINES IN EACH CALLER: the trade tray, the read-only price tray, the
// Codex, a Market row and a request all answer "what is this thing" and a good may not read
// differently on them (docs/NO_SPAGHETTI.md §1). It has TWO FORMS, one concept:
//   · the WORDS form (default): the kind, then the rarity and the class each with its word — where a
//     good has been pressed and there is room to spell it out (the trays);
//   · the COMPACT form (`compact`): the two MARKS alone, in one unbreakable cluster that rides inside
//     a name's own line. A LIST is mark-only (docs/UI_DIRECTION.md §4.4, and TradeRow's header: the
//     kind is not in a row because its height is a measured contract), and a mark the row has no room
//     to spell carries its word as its accessible name — the tray a press opens spells it.
// `category` is optional: a caller whose heading already says the kind (the Codex groups by it) omits it.
export function GoodKind({
  category,
  rarity,
  goodClass,
  compact = false,
  classWord = true,
  size,
  className = '',
}: {
  /** The served `category`, or absent — then no kind word is drawn. */
  category?: string | null
  /** The served rarity tier, or absent — then only what is served is drawn, never a guess. */
  rarity?: string | null
  /** The served premium class (0294), or absent — nothing is drawn for it, never a class guessed from a price. */
  goodClass?: number | null
  /** Marks only, in one cluster that does not break — for a list row. */
  compact?: boolean
  /** In the words form, spell the class out beside its meter (default). False draws the meter alone, the
   *  word as its accessible name: for a control whose text must stay the good's name (the Forge's tile — its
   *  tray repeats the name, and its first row says the class). A press opens the tray, which spells it. */
  classWord?: boolean
  /** The rarity glyph's size in px (the class meter has its own). */
  size?: number
  className?: string
}) {
  if (compact) {
    if (!rarity && goodClass == null) return null
    // THE TWO MARKS ARE A STACK, NOT A ROW (measured, 2026-11-02): side by side they cost 20 px of the
    // name's line, and on a phone the cluster then wrapped under the name and every such row grew by
    // a line (Cinnamon 79 → 86 px; a request 59 → 81). Stacked — the glyph over the meter, 20 px in
    // the 24-px line (the glyph's own box has a pixel of air, so no gap is needed) — the cluster is 14 px
    // wide against the glyph's 12 and gives 3 px back by a negative margin, so it advances the line by 11 px
    // where the glyph alone advanced it by 12. A name that fitted still fits, whatever a machine's font
    // metrics; a row that sits ON its wrap edge (Cinnamon at 390 does, on main, to the quarter pixel; a Linux
    // runner wrapped it at an advance of 12) fits with the mark where it would wrap without; none gets a
    // line it did not have. The next word starts after a space or a flex gap, so the 3 px lie over blank.
    const both = Boolean(rarity) && goodClass != null
    return (
      <span
        className={`inline-flex flex-col items-center whitespace-nowrap align-middle ${both ? '-mr-[3px]' : ''} ${className}`}
        data-testid="good-marks"
      >
        {rarity ? <RarityMark rarity={rarity} size={size} /> : null}
        <GoodClassMark goodClass={goodClass} />
      </span>
    )
  }
  return (
    <span className={`inline-flex flex-wrap items-center gap-x-2 gap-y-1 ${className}`}>
      {category ? <span>{categoryLabel(category)}</span> : null}
      {rarity ? <RarityMark rarity={rarity} withWord size={size} /> : null}
      <GoodClassMark goodClass={goodClass} withWord={classWord} />
    </span>
  )
}
