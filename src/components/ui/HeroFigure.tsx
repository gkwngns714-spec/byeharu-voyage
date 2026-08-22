import type { ReactNode } from 'react'

// Design-system HERO FIGURE — the one number a block is about.
//
// docs/UI_DIRECTION.md §4 rule 2: **the number is the hero.** "Tabular numerals, right-aligned,
// larger than its label. The label is small-caps and dim; the figure is bright." This is that rule
// as a primitive, so a block's headline figure is drawn one way everywhere.
//
// ── WHY IT IS HERE AND NOT IN THE SCREEN THAT WROTE IT FIRST ───────────────────────────────────
// It was hand-written in `features/command/BuyFleetPanel.tsx` twice — the room in the hold and the
// ceiling on the order — and the unfolded good row in `ArgPickers.tsx` wanted the same shape for
// "how much she can take". Three copies of one recipe in two files is the shape the twelve chips
// started in (buttonStyles.ts:31-35), so it was named before the third one landed rather than
// after somebody counted them.
//
// THE UNIT RIDES SMALL BESIDE THE FIGURE, never inside it and never dropped. EVE's rule (§3): a
// number without its unit is not a number. It is set at `text-sm` and dim so the figure stays the
// thing being read, which is also what stops "4,182 d." from wrapping a 390px column.
//
// It is a `<p>`, not a `<span>`: a headline figure is the block's own line, and every caller had
// already wrapped it in one.

export function HeroFigure({
  value,
  unit,
  className = '',
}: {
  /** The figure itself, already formatted — this primitive has no opinion about grouping. */
  value: ReactNode
  /** `t free`, `t at most`, `d.` — small, dim, and beside it. Omitted when the figure is a count. */
  unit?: ReactNode
  className?: string
}) {
  return (
    <p className={`font-mono text-2xl leading-none text-ink tabular-nums ${className}`}>
      {value}
      {unit !== undefined && <span className="ml-1 text-sm font-normal text-ink-faint">{unit}</span>}
    </p>
  )
}
