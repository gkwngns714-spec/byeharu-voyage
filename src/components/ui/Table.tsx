import { useEffect, useRef, useState } from 'react'
import type { HTMLAttributes, TdHTMLAttributes, ThHTMLAttributes } from 'react'
import { TABLE_SCROLL_HINT } from './tableLayout'
import { fineClass } from './typography'

// Design-system TABLE — the primitive this game is actually made of. A trade ledger is columns of
// numbers, so the table is a first-class primitive here, not an afterthought.
//
// THREE RULES, all structural rather than stylistic:
//   1. THE TABLE SCROLLS, THE PAGE DOES NOT. <Table> wraps its <table> in an `overflow-x-auto`
//      box, so a manifest with eight columns scrolls INSIDE its panel on a 320px phone and can
//      never push the page sideways.
//   2. NUMBERS ARE MONO AND RIGHT-ALIGNED. `align="num"` on a cell does both; the mono token
//      carries tabular figures (see src/index.css), so a column of figures lines up on the
//      decimal. A number in the prose font in a column is a bug, not a preference.
//   3. THE SWIPE HINT IS PRINTED ONLY WHILE THERE IS SOMETHING TO SWIPE TO. See below.
//
// Composition, not configuration: no columns/rows props. Screens write real table markup so a
// cell can hold a badge, a button or a link without the primitive growing a slot for each.
//
// ── WHY THE HINT MOVED IN HERE (2026-08-22) ─────────────────────────────────────────────────────
// `TABLE_SCROLL_HINT` was printed by the caller, unconditionally, under three tables. Measured at
// 390x844: PORT's Alongside face draws five columns for one docked hull, fits inside its box with
// room to spare — and printed "Swipe the table sideways for the rest of the columns." under it
// anyway. There were no other columns. A hint that is false is worse than no hint: it sends a
// player swiping at a table that cannot move, and it teaches them to ignore the line on the tables
// where it is true.
//
// It could not be fixed at the call site, because whether a table overflows is not a fact a screen
// knows — it depends on the rendered content and the width of the glass, which is why it took a
// measurement to find. The BOX knows, so the box says it. `overflow` is watched with a
// ResizeObserver on both the box and the table, so it is right after a read adds rows, after a
// rotation, and after a fleet grows from one hull to eight.
//
// It is NOT foldable behind an Explain dot. Explain.tsx names this exact string as the example of
// what may never go behind one: it discloses an affordance the player cannot otherwise find, and
// hiding it hides the game.

export function Table({
  scrollHint = false,
  className = '',
  children,
  ...rest
}: HTMLAttributes<HTMLDivElement> & {
  /** Print the swipe hint when — and only when — this table is wider than its box. */
  scrollHint?: boolean
}) {
  const boxRef = useRef<HTMLDivElement>(null)
  const [clipped, setClipped] = useState(false)

  useEffect(() => {
    const box = boxRef.current
    if (!scrollHint || !box) return
    // +1 absorbs sub-pixel rounding: a table 331.4px wide in a 331px box is not clipped.
    const measure = () => setClipped(box.scrollWidth > box.clientWidth + 1)
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(box)
    const table = box.querySelector('table')
    if (table) ro.observe(table)
    return () => ro.disconnect()
  })

  return (
    <>
      <div ref={boxRef} className={`-mx-1 overflow-x-auto px-1 ${className}`} {...rest}>
        <table className="w-full min-w-full border-collapse text-sm">{children}</table>
      </div>
      {scrollHint && clipped && <p className={fineClass('mt-1')}>{TABLE_SCROLL_HINT}</p>}
    </>
  )
}

/** Column headings: mono, uppercase, faint — the ledger's ruled header line. */
export function TH({
  align = 'text',
  className = '',
  children,
  ...rest
  // `align` is Omitted from the native attrs on purpose: HTML's own (deprecated) align attribute
  // is typed 'left'|'center'|'right'|… and intersecting it with ours collapses to `never`.
  // Ours is a SEMANTIC choice — text or number — and the alignment follows from it.
}: Omit<ThHTMLAttributes<HTMLTableCellElement>, 'align'> & { align?: 'text' | 'num' }) {
  return (
    <th
      scope="col"
      className={`border-b border-edge px-2 py-2 font-mono text-[11px] font-normal uppercase tracking-wider text-ink-faint ${
        align === 'num' ? 'text-right' : 'text-left'
      } ${className}`}
      {...rest}
    >
      {children}
    </th>
  )
}

export function TD({
  align = 'text',
  className = '',
  children,
  ...rest
}: Omit<TdHTMLAttributes<HTMLTableCellElement>, 'align'> & { align?: 'text' | 'num' }) {
  return (
    <td
      className={`border-b border-edge/50 px-2 py-2 align-baseline text-ink ${
        align === 'num' ? 'text-right font-mono' : 'text-left'
      } ${className}`}
      {...rest}
    >
      {children}
    </td>
  )
}

