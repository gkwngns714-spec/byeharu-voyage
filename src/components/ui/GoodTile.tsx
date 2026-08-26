import type { ReactNode } from 'react'
import { EntryTile, type EntryTileTap } from './EntryTile'
import { Icon } from './Icon'
import { goodIcon } from './goodIcons'
import { RarityMark } from './Rarity'

// THE GOOD'S TILE — `EntryTile` wearing the two things that are true of a trade good and of
// nothing else in the catalogue: its own drawn glyph (goodIcons.ts, one per good in data/goods.json)
// and its SERVED rarity tier (0032).
//
// EVERYTHING ELSE MOVED (2026-08-26). The block, the head, the 44px floor and the three tap shapes
// are `EntryTile`'s — see that file's header for why. This is the composition, not a wrapper: it
// adds two facts a ship class and an officer do not have, and it is the ONLY place either of them
// is drawn for a good, so MARKET, the compendium's goods face and COMMAND's good picker cannot
// disagree about what a good looks like.
//
// COMMAND'S GOOD PICKER WAS THE "NAMED NEXT CALLER" HERE FOR THREE DAYS AND DID NOT ARRIVE. It has
// now: features/command/ArgPickers.tsx's GoodPicker composes this with `tapTarget="head"`, because
// its buy and sell price cells are buttons of their own (docs/OWNER_REQUESTS.md row 6).
//
// The figure LINE is `EntryTileLine`, exported from the design system's index beside this — there
// is no `GoodTileLine`, because a labelled figure line inside a tile was never a fact about goods.

export function GoodTile({
  code,
  category,
  name,
  rarity,
  muted = false,
  onTap,
  tapTitle,
  tapTarget,
  expanded,
  selected,
  children,
  testId,
}: {
  /** The good's CODE (`black-pepper`) — what `goodIcon` keys the drawn mark from. */
  code: string
  /** The served category, the icon table's fallback for a good landed undrawn. */
  category: string
  name: string
  /** The SERVED rarity tier (0032), rendered by the one mark. Absent renders nothing. */
  rarity: string | null | undefined
  /** A good the port will not trade: struck through, dimmed, and NOT tappable — there is no
   *  order to hand over, so there is no button to press. */
  muted?: boolean
  /** Makes the tile tappable (≥44px by construction). Omitted = a plain block. */
  onTap?: () => void
  /** The pointer's sentence for the tap — never printed, so the tile stays a block of figures. */
  tapTitle?: string
  /** `tile` (the default) or `head` when the children carry their own buttons — EntryTile.tsx. */
  tapTarget?: EntryTileTap
  expanded?: boolean
  selected?: boolean
  /** The figures, aligned beneath the title. Composed by the caller; every one the server's. */
  children?: ReactNode
  testId?: string
}) {
  return (
    <EntryTile
      name={name}
      mark={<Icon name={goodIcon(code, category)} size={18} className="mt-0.5 shrink-0 text-ink-muted" />}
      corner={<RarityMark rarity={rarity} size={11} />}
      muted={muted}
      onTap={onTap}
      tapTitle={tapTitle}
      tapTarget={tapTarget}
      expanded={expanded}
      selected={selected}
      testId={testId}
    >
      {children}
    </EntryTile>
  )
}
