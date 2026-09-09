import type { ReactNode } from 'react'

// THE TILE, AND THE FIELD IT STANDS IN.
//
// The owner asked for a field rather than a column of lines TWICE (docs/OWNER_REQUESTS.md; the
// second telling is quoted at tests/layout.spec.ts:246), and the tree answered it three times: the
// compendium's `EntryTile`, the trade `GoodTile` wrapped around it, the verb card written inline in
// `OrderComposer`, `PortPicker`'s `buttonClasses('chip', …, 'flex-col')` chip-tiles, the Fleets
// phone block, the officer and skill cards, and `SendFleet`'s fleet rows. docs/UI_DIRECTION.md §3
// rule 4 names three of those as "three different selectable-block recipes coexisting".
//
// This is the one. A tile is: a MARK, a NAME, one or two FIGURES, and optionally a BAR.
//
// ── THE FIELD IS CSS, NOT ARITHMETIC ───────────────────────────────────────────────────────────
// `TileField` is `repeat(auto-fill, minmax(--spacing-tile-min, 1fr))` and nothing else. The tree it
// replaces computed its column count in JavaScript (`tileFieldCols`, `useTileCols`, `inRowsOf`)
// for ONE reason: a fold inserted beside a pressed tile re-flows that tile's row, so the fold had
// to be placed after the WHOLE row, so the code had to know where a row ended. §5 removes the
// reason instead of the arithmetic — the fold is a `Tray`, docked out of flow, and nothing is ever
// inserted into the grid. With nothing to insert, a row has no end worth computing.
//
// ── THE THREE STATES, AND WHAT SEPARATES THEM ──────────────────────────────────────────────────
//   rest      `surface`, no border. A tile is separated from the sheet by TONE (§4.3).
//   selected  `accent-soft` wash + a 1px accent hairline. Never a fill: a solid accent swallows the
//             two figures and the bar the tile is carrying, which is the exact defect
//             `chip-soft` was added to buttonStyles.ts for.
//   muted     `ink-3` throughout, for a catalogued thing no rule reads yet. It stays legible and
//             stays pressable; the REASON goes in the tray, never on the tile.
//
// ── TWO TAP SHAPES, BECAUSE A PRICE IS A TRADE ─────────────────────────────────────────────────
// `tap="whole"` makes the tile one button (a verb, a harbour, a ship class). `tap="head"` makes
// only the name a button and leaves the body to the caller's own targets — which is what the
// owner's row 6 requires of a good: *"i want to be able to click on buy and sell itself and do
// trades."* Both prices are real 44px labelled buttons inside the tile, and tests/layout.spec.ts
// counts them.

export type TileState = 'rest' | 'selected' | 'muted'

const STATE: Record<TileState, string> = {
  rest: 'bg-surface border border-transparent',
  selected: 'bg-accent-soft border border-accent',
  muted: 'bg-surface border border-transparent text-ink-faint',
}

/** The grid every field of tiles stands in. One line of CSS; see the header for what it retired. */
export function TileField({
  children,
  className = '',
  ...rest
}: {
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <div
      className={`grid grid-cols-[repeat(auto-fill,minmax(var(--spacing-tile-min),1fr))] gap-2 ${className}`}
      {...rest}
    >
      {children}
    </div>
  )
}

export function Tile({
  mark,
  name,
  meta,
  figure,
  second,
  bar,
  state = 'rest',
  tap = 'none',
  onClick,
  disabled = false,
  className = '',
  children,
  ...rest
}: {
  /** The identity glyph — a good's own drawn mark, a verb icon, a rarity mark. */
  mark?: ReactNode
  /** What it is called, in `t-body`. */
  name: ReactNode
  /** One quiet line under the name (`t-caption`): a class, a nation, a category. */
  meta?: ReactNode
  /** The figure the tile is about — a `<Figure>`. */
  figure?: ReactNode
  /** The second figure, when a thing genuinely has two (buy and sell). Never a third. */
  second?: ReactNode
  /** A `<Bar>`: a range, a stock, a hull. */
  bar?: ReactNode
  state?: TileState
  /** `whole` — the tile is one button. `head` — only the name is; the body carries its own targets. */
  tap?: 'whole' | 'head' | 'none'
  onClick?: () => void
  disabled?: boolean
  className?: string
  /** The caller's own tap zones (a good's two price cells), under the figures. */
  children?: ReactNode
} & { 'data-testid'?: string }) {
  const head = (
    <>
      {mark !== undefined && <span className="flex shrink-0 items-center">{mark}</span>}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-t-body">{name}</span>
        {meta !== undefined && <span className="block truncate text-t-caption text-ink-faint">{meta}</span>}
      </span>
    </>
  )

  const inside = (
    <>
      {tap === 'head' ? (
        <button
          type="button"
          onClick={onClick}
          disabled={disabled}
          className="flex min-h-11 w-full items-center gap-2 text-left disabled:opacity-45"
        >
          {head}
        </button>
      ) : (
        <span className="flex items-center gap-2">{head}</span>
      )}
      {(figure !== undefined || second !== undefined) && (
        <span className="flex items-baseline justify-between gap-2">
          {figure}
          {second}
        </span>
      )}
      {bar}
      {children}
    </>
  )

  const shell = [
    'flex min-h-tile flex-col gap-2 rounded-tile p-3 text-left transition',
    STATE[state],
    className,
  ].join(' ')

  if (tap === 'whole') {
    return (
      <button type="button" onClick={onClick} disabled={disabled} className={`${shell} disabled:opacity-45`} {...rest}>
        {inside}
      </button>
    )
  }
  return (
    <div className={shell} {...rest}>
      {inside}
    </div>
  )
}
