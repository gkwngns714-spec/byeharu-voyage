import type { ReactNode } from 'react'

// THE FACTS LINE — small facts under a row's label, in the caption voice, wrapping rather than
// overlapping: "54 days of supplies · 4 / 60 tons · hull 80 %", "sold 120 · bought 40 · 240 / 300".
//
// FleetsScreen wrote it for the fleet row (2026-10-01: "THE LINE WRAPS RATHER THAN OVERLAPS"), and the
// Stats tab's Markets and Cities faces wrote it twice more on 2026-10-20 before tests/duplication.spec.ts
// counted three. One recipe here; the callers put their figures and gauges inside it. Spacing above is
// the row's (`mt-1`), because every caller sits under a label.
export function FactsLine({
  children,
  className = '',
  ...rest
}: {
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <span className={`mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-t-caption text-ink-faint ${className}`} {...rest}>
      {children}
    </span>
  )
}
