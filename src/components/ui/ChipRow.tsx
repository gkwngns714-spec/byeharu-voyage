import type { ReactNode } from 'react'

// A ROW OF CHIPS THAT SCROLLS SIDEWAYS — bleeding to the gutter, with no native bar (`.bv-scroll-x`):
// the clipped chip at the edge says there is more. Written once here (it was the same class recipe in
// four places on the desk: the fleet strip, the Markets filters, the plan builder's Buy at and Sell at).
// A press on a chip SELECTS; the row never moves.

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
      className={`bv-scroll-x -mx-gutter flex gap-2 overflow-x-auto px-gutter pb-1 ${className}`}
      role={label ? 'group' : undefined}
      aria-label={label}
    >
      {children}
    </div>
  )
}
