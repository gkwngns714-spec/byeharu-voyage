import { categoryLabel } from './goodIcons'
import { RarityMark } from './Rarity'

// WHAT A GOOD IS, IN TWO SERVED WORDS — its KIND and how RARE it is.
//
// The owner, 2026-10-20 (docs/OWNER_REQUESTS.md row 177): *"The trade goods should show rarity, and
// what class? What sort it is classified, such as food, weapon, spice etc."*
//
// BOTH WORDS ALREADY COME OFF THE WIRE, and this composition decides neither of them:
//   · the KIND is `goods.category` — one of seventeen authored in `data/goods.json` (food, cloth,
//     crafts, drink, medicine, dye, ship supplies, metal, gems, spice, guns, animals, grain, art,
//     weapons, books, tobacco), served on `snapshot.goods[]` and on every market row, and read
//     into the player's word by `categoryLabel` (goodIcons.ts), which is also the Korean entrance;
//   · the RARITY is the served tier (`public.good_rarity`, 0032 as 0051 rescaled it: how few
//     harbours produce the good, measured against the mean for this world — never its price),
//     drawn by `RarityMark`, the one rendering of it.
// There is no list of 555 goods anywhere in this client and there must never be one.
//
// WHY A COMPOSITION AND NOT TWO LINES IN EACH CALLER: the trade tray, the read-only price tray and
// the Codex all answer "what is this thing" and a good may not read differently on the three
// (docs/NO_SPAGHETTI.md §1). The MARK is still mark-only in a LIST (docs/UI_DIRECTION.md §4.4):
// this is the one place the tier is spelled out, and it stands where a good has been pressed.
export function GoodKind({
  category,
  rarity,
  className = '',
}: {
  /** The served `category`. */
  category: string
  /** The served rarity tier, or absent — then only the kind is drawn, never a guess. */
  rarity: string | null | undefined
  className?: string
}) {
  return (
    <span className={`inline-flex flex-wrap items-center gap-x-2 gap-y-1 ${className}`}>
      <span>{categoryLabel(category)}</span>
      {rarity ? <RarityMark rarity={rarity} withWord /> : null}
    </span>
  )
}
