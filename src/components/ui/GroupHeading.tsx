import type { ReactNode } from 'react'

// THE HEADING OVER A GROUP INSIDE A CARD OR A FACE — "By section", "By place", "Regard": a caption-sized, faint, semibold
// line over the rows it names. It was hand-written on the Report face and again on the You page's levels card
// (tests/duplication.spec.ts, 2026-11-16), so it is spelt here once. `className` carries only the caller's own space above
// it (`mt-3`), never a second type recipe.
export function GroupHeading({ className = '', children }: { className?: string; children: ReactNode }) {
  return <h3 className={`mb-1 text-t-caption font-semibold text-ink-faint ${className}`}>{children}</h3>
}
