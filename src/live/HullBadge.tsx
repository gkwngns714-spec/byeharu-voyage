import type { ReactNode } from 'react'

// THE SMALL BADGE BESIDE A HULL'S NAME, once: "Cargo ship" (HullCrown, 0332) and "Gunship" (HullJob, 0366) are the same chip, so the
// recipe is written here and both ask for it (tests/duplication.spec.ts). It never breaks inside its words.
export function HullBadge({ children, ...rest }: { children: ReactNode; 'data-testid'?: string; 'data-job'?: string }) {
  return (
    <span className="mr-1 inline-block whitespace-nowrap rounded-chip bg-accent-soft px-1.5 text-accent" {...rest}>
      {children}
    </span>
  )
}
