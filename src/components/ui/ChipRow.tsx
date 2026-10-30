import type { ReactNode } from 'react'

// A ROW OF CHIPS THAT WRAPS — bleeding to the gutter, never scrolling sideways (the owner's law
// 2026-10-30: nothing scrolls sideways; a chip set that outgrows one line wraps to the next). Written
// once here (it was the same class recipe in four places on the desk: the fleet strip, the Markets
// filters, the plan builder's Buy at and Sell at). A press on a chip SELECTS; the row never moves.

export function ChipRow({
  label,
  children,
  className = '',
}: {
  /** Names the group for assistive tech ("Filter goods"). */
  label?: string
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`-mx-gutter flex flex-wrap gap-2 px-gutter pb-1 ${className}`}
      role={label ? 'group' : undefined}
      aria-label={label}
    >
      {children}
    </div>
  )
}
