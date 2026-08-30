import type { ReactNode } from 'react'
import { fineClass } from './typography'

// THE ENTRY TILE — one catalogued THING as a BLOCK, not a sentence.
//
// The owner, 2026-08-23: "make trade goods in blocks as well, not all alligned in sentences —
// horizontally", and again on 2026-08-26: "i told trade goods to be in grid like shape - organized
// not in lines." The row form read name · kind · figure · figure strung across one full-width line;
// this is the same served facts as a tile a thumb can land on: a mark and the name as the title, a
// mark in the far corner, and the figures aligned beneath, so a wall of entries scans as a field
// rather than reading as a column of sentences.
//
// ── WHY IT IS NOT CALLED GoodTile ANY MORE ─────────────────────────────────────────────────────
// It was, and `GoodTile.tsx` still exists — as the GOOD's composition of this chrome (its drawn
// glyph, its served rarity). What a tile IS — the block, the head of mark + name + corner, the
// 44px floor, the three tap shapes below — is not a fact about trade goods, and the moment the
// compendium's ship classes and officers needed the same block there were two choices: force a
// ship through a prop called `rarity`, or split the chrome from the good. docs/NO_SPAGHETTI.md §2:
// "the moment two screens want the same thing, it stops belonging to the screen that wrote it
// first." Callers: GoodTile (MARKET, the compendium's goods face, COMMAND's good picker) and the
// compendium's ships and captains faces.
//
// ── THREE TAP SHAPES, AND THE THIRD IS THE REASON THIS FILE IS NOT TWO ─────────────────────────
//   · no `onTap`         → a plain block. Nothing to press.
//   · `tapTarget="tile"` → the WHOLE tile is one button (MARKET: tap a good, it lands on Command).
//   · `tapTarget="head"` → the HEAD is the button and the body carries its own buttons (COMMAND's
//     good picker: the buy and sell price cells are the trade itself, docs/OWNER_REQUESTS.md row
//     6). A button inside a button is not markup a browser will honour, so the skin moves onto a
//     div and only the head stays pressable — the same call features/command/ArgPickers.tsx's
//     PickerRow makes for the row form, made once here so the tile and the row cannot drift.
//
// ── WHAT IT REFUSES TO DO ──────────────────────────────────────────────────────────────────────
//   · It never truncates the name. `São Vicente` must not become `São Vice…` — the name wraps and
//     the tile grows, which the grid absorbs (`items-stretch`, tileLayout.ts).
//   · It computes nothing. Every figure inside it arrives composed by the caller, already the
//     server's (worldStore.ts rule 3). The tile is chrome.
//   · It does not decide the grid. `tileFieldClass()` is the one spelling of the field the tiles
//     sit in — two columns at 390px (measured: three crushes the figures), more as the glass
//     widens.

export type EntryTileTap = 'tile' | 'head'

/** The one recipe for the block, in all three shapes and both states, so they cannot drift. */
function tileSkin(selected: boolean, muted: boolean, pressable: boolean): string {
  const base = 'bv-cut flex min-h-11 flex-col gap-1.5 border p-2.5 text-left'
  if (muted) return `${base} border-edge/60 bg-surface text-ink-faint`
  // THE SAME TWO TOKENS `chip-soft` NAMES (buttonStyles.ts) — the soft tint a selected ROW wears,
  // not the solid brass a selected chip wears, because a tile CARRIES a badge, a pill and a meter
  // and a solid fill swallows all three. The tokens are borrowed, not the recipe: `buttonClasses`
  // brings a button's box — rounded, inline-flex, centred, its own padding — and a tile's box is
  // chamfered (`bv-cut`), flows in a column and sets its own. Two tokens, one meaning, one place
  // each of them is chosen.
  if (selected) return `${base} border-accent bg-accent-soft transition`
  return pressable
    ? `${base} border-edge bg-surface-2 transition hover:border-accent/60`
    : `${base} border-edge/60 bg-surface`
}

export function EntryTile({
  name,
  mark,
  corner,
  muted = false,
  onTap,
  tapTitle,
  tapTarget = 'tile',
  expanded,
  selected = false,
  children,
  testId,
}: {
  name: ReactNode
  /** A glyph at the head of the tile. Optional — a nation has no mark to draw. */
  mark?: ReactNode
  /** A mark pushed to the far corner of the head: a rarity, a tier, a "signed" badge. */
  corner?: ReactNode
  /** An entry that cannot be acted on: struck through, dimmed and NOT tappable. `onTap` is ignored
   *  rather than quietly kept, because there is no act to offer. */
  muted?: boolean
  onTap?: () => void
  /** The pointer's sentence for the tap — never printed, so the tile stays a block of figures. */
  tapTitle?: string
  /** Where the tap target is. See the header: `head` is for a tile whose CHILDREN carry buttons. */
  tapTarget?: EntryTileTap
  /** Given only by a tile that UNFOLDS something. A tile that commits on tap says nothing —
   *  `aria-expanded={undefined}` is absent, not false. */
  expanded?: boolean
  /** This is the entry being dealt with — chosen, or open. */
  selected?: boolean
  /** The figures, aligned beneath the title. Composed by the caller; every one the server's. */
  children?: ReactNode
  testId?: string
}) {
  const head = (
    <span className="flex w-full items-start gap-1.5">
      {mark}
      <span
        className={
          muted
            ? 'min-w-0 text-sm text-ink-faint line-through'
            : 'min-w-0 text-sm font-medium text-ink'
        }
      >
        {name}
      </span>
      {corner !== undefined && <span className="ml-auto mt-0.5 shrink-0">{corner}</span>}
    </span>
  )

  const body = children && <span className="flex w-full flex-col gap-1">{children}</span>

  if (muted || !onTap) {
    return (
      <div data-testid={testId} className={tileSkin(selected, muted, false)}>
        {head}
        {body}
      </div>
    )
  }

  if (tapTarget === 'tile') {
    return (
      <button
        type="button"
        onClick={onTap}
        title={tapTitle}
        aria-expanded={expanded}
        data-testid={testId}
        className={tileSkin(selected, false, true)}
      >
        {head}
        {body}
      </button>
    )
  }

  // HEAD-TAP: the skin is the tile's, the button is only the head, and the body is free to carry
  // its own actions. See the header for why this shape exists at all.
  return (
    <div data-testid={testId} className={tileSkin(selected, false, true)}>
      {/* THE SAME `head` NODE the other two shapes render, not a second spelling of it. */}
      <button
        type="button"
        onClick={onTap}
        title={tapTitle}
        aria-expanded={expanded}
        className="flex min-h-11 w-full text-left"
      >
        {head}
      </button>
      {body}
    </div>
  )
}

/** One aligned figure line inside a tile: a small dim label, the value pushed to the far edge.
 *  The label is a NAME, never a sentence (the owner's label law); the value is the hero
 *  (docs/UI_DIRECTION.md §4 rule 2). One spelling here so MARKET's tiles, the compendium's and
 *  COMMAND's cannot drift apart line by line. */
export function EntryTileLine({ label, children }: { label: string; children: ReactNode }) {
  return (
    <span className="flex w-full items-center justify-between gap-2">
      {/* The fine-print voice (typography.ts), uppercased — not a re-spelling of it. */}
      <span className={fineClass('shrink-0 uppercase tracking-wider')}>{label}</span>
      <span className="flex min-w-0 items-center justify-end gap-1 text-right font-mono text-xs text-ink">
        {children}
      </span>
    </span>
  )
}
